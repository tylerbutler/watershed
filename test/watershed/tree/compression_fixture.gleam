import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/history
import watershed/tree/runtime_fixture
import watershed/tree/summary as tree_summary
import watershed/tree_kernel
import watershed/wire.{type SequencedEnvelope}
import watershed/wire/fluid_document
import watershed/wire/fluid_summary
import watershed/wire/socket

const fixture_path = "test/fixtures/shared_tree/compression.json"

type Frame {
  Frame(id: String, compressed: String, decoded: String)
}

type RawCase {
  RawCase(id: String, messages: List(Dynamic))
}

pub type ExpectedCase {
  ExpectedCase(grouped: Bool, messages: List(ExpectedMessage))
}

pub type ExpectedMessage {
  ExpectedMessage(
    contents: json.Json,
    metadata: Option(json.Json),
    sequence_number: Int,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    timestamp: Int,
  )
}

pub fn frame(id: String) -> Result(#(BitArray, BitArray), String) {
  use raw <- result.try(
    simplifile.read(fixture_path)
    |> result.map_error(fn(_) {
      "could not read compression fixture at " <> fixture_path
    }),
  )
  use frames <- result.try(
    json.parse(raw, decode.at(["frames"], decode.list(frame_decoder())))
    |> result.map_error(fn(error) {
      "could not decode compression frames: " <> string.inspect(error)
    }),
  )
  use selected <- result.try(
    list.find(frames, fn(frame) { frame.id == id })
    |> result.map_error(fn(_) { "compression frame is missing: " <> id }),
  )
  use compressed <- result.try(
    bit_array.base64_decode(selected.compressed)
    |> result.replace_error(
      "compression frame has invalid compressed bytes: " <> id,
    ),
  )
  use decoded <- result.try(
    bit_array.base64_decode(selected.decoded)
    |> result.replace_error(
      "compression frame has invalid decoded bytes: " <> id,
    ),
  )
  Ok(#(compressed, decoded))
}

pub fn envelopes(id: String) -> Result(List(SequencedEnvelope), String) {
  use raw <- result.try(read_fixture())
  use cases <- result.try(
    json.parse(raw, decode.at(["cases"], decode.list(raw_case_decoder())))
    |> result.map_error(fn(error) {
      "could not decode compression cases: " <> string.inspect(error)
    }),
  )
  use selected <- result.try(
    list.find(cases, fn(item) { item.id == id })
    |> result.map_error(fn(_) { "compression case is missing: " <> id }),
  )
  list.try_map(selected.messages, fn(message) {
    decode.run(message, socket.sequenced_envelope_decoder())
    |> result.map_error(fn(error) {
      "could not decode compression envelope: " <> string.inspect(error)
    })
  })
}

pub fn expected(id: String) -> Result(ExpectedCase, String) {
  use raw <- result.try(read_fixture())
  use cases <- result.try(
    json.parse(raw, decode.at(["cases"], decode.list(expected_case_decoder())))
    |> result.map_error(fn(error) {
      "could not decode compression expectations: " <> string.inspect(error)
    }),
  )
  use selected <- result.try(
    list.find(cases, fn(item) { item.0 == id })
    |> result.map_error(fn(_) { "compression case is missing: " <> id }),
  )
  use expected <- result.try(
    decode.run(selected.1, decode.list(expected_result_decoder()))
    |> result.map_error(fn(error) {
      "could not decode compression expectation: " <> string.inspect(error)
    }),
  )
  case expected {
    [expected] -> Ok(expected)
    _ -> Error("compression case must have one expected result: " <> id)
  }
}

pub fn summary_prefix(
  id: String,
) -> Result(#(List(#(String, List(String))), Int, Int), String) {
  use raw <- result.try(read_fixture())
  use cases <- result.try(
    json.parse(raw, decode.at(["cases"], decode.list(summary_case_decoder())))
    |> result.map_error(fn(error) {
      "could not decode compression summary: " <> string.inspect(error)
    }),
  )
  use selected <- result.try(
    list.find(cases, fn(item) { item.0 == id })
    |> result.map_error(fn(_) { "compression case is missing: " <> id }),
  )
  decode.run(selected.1, summary_selected_decoder())
  |> result.map_error(fn(error) {
    "could not decode selected compression summary: " <> string.inspect(error)
  })
}

pub fn core_case(
  id: String,
) -> Result(#(runtime_core.Core, List(SequencedEnvelope)), String) {
  use envelopes <- result.try(envelopes(id))
  let checkpoint = case list.first(envelopes) {
    Ok(first) -> first.message.sequence_number - 1
    Error(_) -> 0
  }
  use raw <- result.try(read_fixture())
  use cases <- result.try(
    json.parse(raw, decode.at(["cases"], decode.list(decode.dynamic)))
    |> result.map_error(string.inspect),
  )
  use selected <- result.try(
    list.find(cases, fn(value) {
      decode.run(value, decode.at(["id"], decode.string)) == Ok(id)
    })
    |> result.map_error(fn(_) { "compression case is missing: " <> id }),
  )
  use workload_id <- result.try(
    decode.run(
      selected,
      decode.at(["treeContext", "workloadId"], decode.string),
    )
    |> result.map_error(fn(_) { "compression case has no tree context: " <> id }),
  )
  let required_prelude =
    decode.run(selected, decode.at(["treeContext"], required_prelude_decoder()))
    |> result.unwrap(None)
  use workloads <- result.try(
    json.parse(
      raw,
      decode.at(
        ["probe", "treeState", "workloads"],
        decode.list(decode.dynamic),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use workload <- result.try(
    list.find(workloads, fn(value) {
      decode.run(value, decode.at(["id"], decode.string)) == Ok(workload_id)
    })
    |> result.map_error(fn(_) {
      "compression workload is missing: " <> workload_id
    }),
  )
  use context <- result.try(
    decode.run(workload, decode.at(["context"], decode.dynamic))
    |> result.map_error(string.inspect),
  )
  use session_text <- result.try(
    decode.run(context, decode.at(["sessionId"], decode.string))
    |> result.map_error(string.inspect),
  )
  use _source_session <- result.try(
    fluid_ids.session_id(session_text) |> result.map_error(string.inspect),
  )
  use session <- result.try(
    fluid_ids.session_id("90000000-0000-4000-8000-000000000009")
    |> result.map_error(string.inspect),
  )
  use compressor_text <- result.try(
    decode.run(context, decode.at(["compressor"], decode.string))
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(compressor_text), session)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(case required_prelude {
    None -> Ok(compressor)
    Some(_) -> {
      use preludes <- result.try(
        decode.run(
          workload,
          decode.at(
            ["allocationPreludes"],
            decode.list(wire.json_value_decoder()),
          ),
        )
        |> result.map_error(string.inspect),
      )
      use first <- result.try(
        list.first(preludes)
        |> result.map_error(fn(_) { "required allocation prelude is missing" }),
      )
      use range <- result.try(
        fluid_ids.creation_range_from_json(first)
        |> result.map_error(string.inspect),
      )
      fluid_ids.finalize(compressor, range) |> result.map_error(string.inspect)
    }
  })
  use entry <- result.try(
    decode.run(context, decode.at(["summary"], summary_entry_decoder()))
    |> result.map_error(string.inspect),
  )
  use data <- result.try(
    summary_codec.decode(
      entry,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id("50000000-0000-4000-8000-000000000005")
    |> result.map_error(string.inspect),
  )
  use captured_snapshot <- result.try(
    tree_summary.from_wire(data, view_id, compressor, 2, 0)
    |> result.map_error(string.inspect),
  )
  let #(stored, forest, _) = tree_kernel.snapshot_parts(captured_snapshot)
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest,
      history.HistorySnapshot(history.InitialBase, [], [], checkpoint, 0, []),
    )
    |> result.map_error(string.inspect),
  )
  use store <- result.try(
    decode.run(context, decode.at(["dataStoreAddress"], decode.string))
    |> result.map_error(string.inspect),
  )
  use tree <- result.try(
    decode.run(context, decode.at(["channelAddress"], decode.string))
    |> result.map_error(string.inspect),
  )
  use created <- result.try(
    fluid_document.initial_tree_with_layout(
      stored,
      forest.root,
      session,
      view_id,
      fluid_document.InitialLayout(
        stores: [fluid_document.InitialDatastore(store, None)],
        channels: [
          fluid_document.InitialTree(store, tree, stored, forest.root),
        ],
        bindings: [
          fluid_document.InitialBinding("A", "root", "captured", store, tree),
        ],
      ),
    )
    |> result.map_error(string.inspect),
  )
  let stores = fluid_document.datastores(created)
  let channels =
    list.flat_map(stores, fn(datastore) {
      list.map(datastore.channels, fn(item) {
        #(datastore.id <> "/" <> item.id, case item.snapshot {
          channel.TreeSnapshot(_) -> channel.TreeSnapshot(snapshot)
          _ -> item.snapshot
        })
      })
    })
  use captured <- result.try(
    fluid_document.capture(
      created,
      channels,
      Some(compressor),
      fluid_document.CaptureRouting(
        fluid_document.aliases(created),
        list.map(stores, fn(datastore) {
          #(datastore.id, datastore.package_path)
        }),
        list.flat_map(stores, fn(datastore) {
          list.map(datastore.channels, fn(item) {
            #(datastore.id <> "/" <> item.id, item.attributes)
          })
        }),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(
    fluid_document.encode(captured) |> result.map_error(string.inspect),
  )
  use encoded <- result.try(
    adapt_checkpoint(encoded, checkpoint)
    |> result.map_error(string.inspect),
  )
  use summary <- result.try(
    fluid_document.decode(encoded, None, session, view_id)
    |> result.map_error(string.inspect),
  )
  use bootstrapped <- result.try(
    runtime_core.bootstrap_document(
      runtime_fixture.connected("compression-reader", [], checkpoint),
      summary,
    )
    |> result.map_error(string.inspect),
  )
  case bootstrapped {
    runtime_core.Complete(core) -> Ok(#(core, envelopes))
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("captured channel context did not produce a complete bootstrap")
  }
}

fn adapt_checkpoint(
  encoded: fluid_summary.SummaryEntry,
  checkpoint: Int,
) -> Result(fluid_summary.SummaryEntry, Nil) {
  let assert fluid_summary.SummaryTree(entries) = encoded
  use protocol <- result.try(list.key_find(entries, ".protocol"))
  let assert fluid_summary.SummaryTree(protocol_entries) = protocol
  let attributes_json =
    json.object([
      #("sequenceNumber", json.int(checkpoint)),
      #("minimumSequenceNumber", json.int(0)),
    ])
    |> json.to_string
  let attributes = fluid_summary.SummaryBlob(<<attributes_json:utf8>>)
  let protocol =
    fluid_summary.SummaryTree([
      #("attributes", attributes),
      ..list.filter(protocol_entries, fn(entry) { entry.0 != "attributes" })
    ])
  Ok(
    fluid_summary.SummaryTree([
      #(".protocol", protocol),
      ..list.filter(entries, fn(entry) { entry.0 != ".protocol" })
    ]),
  )
}

fn read_fixture() -> Result(String, String) {
  simplifile.read(fixture_path)
  |> result.map_error(fn(_) {
    "could not read compression fixture at " <> fixture_path
  })
}

fn summary_entry_decoder() -> decode.Decoder(fluid_summary.SummaryEntry) {
  use kind <- decode.field("type", decode.int)
  case kind {
    1 -> {
      use entries <- decode.field(
        "tree",
        decode.dict(decode.string, summary_entry_decoder()),
      )
      decode.success(fluid_summary.SummaryTree(dict.to_list(entries)))
    }

    2 -> {
      use content <- decode.field("content", decode.string)
      decode.success(fluid_summary.SummaryBlob(<<content:utf8>>))
    }
    _ ->
      decode.failure(
        fluid_summary.SummaryBlob(<<>>),
        "unsupported summary entry",
      )
  }
}

fn required_prelude_decoder() -> decode.Decoder(Option(String)) {
  use prelude <- decode.optional_field(
    "requiredPrelude",
    None,
    decode.map(decode.string, Some),
  )
  decode.success(prelude)
}

fn raw_case_decoder() -> decode.Decoder(RawCase) {
  use id <- decode.field("id", decode.string)
  use messages <- decode.field("messages", decode.list(decode.dynamic))
  decode.success(RawCase(id:, messages:))
}

fn expected_case_decoder() -> decode.Decoder(#(String, Dynamic)) {
  use id <- decode.field("id", decode.string)
  use expected <- decode.field("expected", decode.dynamic)
  decode.success(#(id, expected))
}

fn expected_result_decoder() -> decode.Decoder(ExpectedCase) {
  use result_type <- decode.field("type", decode.string)
  use grouped <- decode.field("groupedBatch", decode.bool)
  use messages <- decode.field(
    "messages",
    decode.list(expected_message_decoder()),
  )
  case result_type {
    "fullBatch" -> decode.success(ExpectedCase(grouped:, messages:))
    _ ->
      decode.failure(
        ExpectedCase(False, []),
        "expected result is not a full batch",
      )
  }
}

fn expected_message_decoder() -> decode.Decoder(ExpectedMessage) {
  use message_type <- decode.field("type", decode.string)
  use contents <- decode.field("contents", wire.json_value_decoder())
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  use client_sequence_number <- decode.field("clientSequenceNumber", decode.int)
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  use timestamp <- decode.field("timestamp", decode.int)
  decode.success(ExpectedMessage(
    contents: json.object([
      #("type", json.string(message_type)),
      #("contents", contents),
    ]),
    metadata:,
    sequence_number:,
    client_sequence_number:,
    reference_sequence_number:,
    timestamp:,
  ))
}

fn summary_case_decoder() -> decode.Decoder(#(String, Dynamic)) {
  use id <- decode.field("id", decode.string)
  use value <- decode.then(decode.dynamic)
  decode.success(#(id, value))
}

fn summary_selected_decoder() -> decode.Decoder(
  #(List(#(String, List(String))), Int, Int),
) {
  use summary <- decode.field("partialSummary", chunk_summary_decoder())
  use delivery <- decode.field("delivery", delivery_decoder())
  decode.success(#(summary, delivery.0, delivery.1))
}

fn delivery_decoder() -> decode.Decoder(#(Int, Int)) {
  use prefix_length <- decode.field("prefixLength", decode.int)
  use tail_length <- decode.field("tailLength", decode.int)
  decode.success(#(prefix_length, tail_length))
}

fn chunk_summary_decoder() -> decode.Decoder(List(#(String, List(String)))) {
  decode.list({
    use pair <- decode.then(decode.list(decode.dynamic))
    case pair {
      [_, _] -> {
        use sender <- decode.field(0, decode.string)
        use pieces <- decode.field(1, decode.list(decode.string))
        decode.success(#(sender, pieces))
      }
      _ -> decode.failure(#("", []), "sender and chunk prefix")
    }
  })
}

fn frame_decoder() -> decode.Decoder(Frame) {
  use id <- decode.field("id", decode.string)
  use compressed <- decode.field("compressedBase64", decode.string)
  use decoded <- decode.field("decodedBase64", decode.string)
  decode.success(Frame(id:, compressed:, decoded:))
}
