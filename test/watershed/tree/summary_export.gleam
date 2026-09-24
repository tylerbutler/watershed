//// Exports fresh document summaries from real sequenced inputs on each target.

import envoy
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import simplifile
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/runtime_fixture
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_summary
import watershed/wire/socket

pub fn main() {
  let assert Ok(input_path) = envoy.get("WATERSHED_TREE_SUMMARY_INPUT")
  let assert Ok(output_path) = envoy.get("WATERSHED_TREE_SUMMARY_OUTPUT")
  let assert Ok(target) = envoy.get("WATERSHED_TREE_SUMMARY_TARGET")
  let assert True = target == "javascript" || target == "erlang"
  let assert Ok(raw) = simplifile.read(input_path)
  let assert Ok(input) = json.parse(raw, wire.json_value_decoder())
  let artifact = case export(input, target) {
    Ok(value) -> value
    Error(detail) -> panic as { detail }
  }
  let assert Ok(Nil) =
    simplifile.write(output_path, json.to_string(artifact) <> "\n")
}

pub fn export(input: Json, target: String) -> Result(Json, String) {
  use states <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(
        ["input", "persistenceStates"],
        decode.list(wire.json_value_decoder()),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use cases <- result.try(list.try_map(states, export_case))
  Ok(
    json.object([
      #("target", json.string(target)),
      #(
        "reference",
        json.object([
          #("package", json.string("@fluidframework/tree")),
          #("version", json.string("3.1.0")),
          #("commit", json.string("c3c5bf0ecd313362e83fe8a02b7d39e7e0736960")),
        ]),
      ),
      #("cases", json.array(cases, fn(value) { value })),
    ]),
  )
}

fn export_case(state: Json) -> Result(Json, String) {
  use id <- result.try(
    json.parse(json.to_string(state), decode.at(["id"], decode.string))
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    json.parse(
      json.to_string(state),
      decode.at(["snapshot"], wire.json_value_decoder()),
    )
    |> result.map_error(string.inspect),
  )
  use sequence <- result.try(
    json.parse(json.to_string(state), decode.at(["sequenceNumber"], decode.int))
    |> result.map_error(string.inspect),
  )
  use tail <- result.try(
    json.parse(
      json.to_string(state),
      decode.at(
        ["tail"],
        decode.list(socket.sequenced_document_message_decoder()),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use session <- result.try(
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
    |> result.map_error(string.inspect),
  )
  use hierarchy <- result.try(runtime_fixture.read_snapshot(snapshot))
  use summary <- result.try(
    fluid_document.decode(hierarchy, None, session, view)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(case fluid_document.sequence_number(summary) == sequence {
    True -> Ok(Nil)
    False -> Error(id <> ": snapshot sequence differs from declared state")
  })
  use core <- result.try(
    case
      runtime_core.bootstrap_document(
        runtime_fixture.connected("reader", [], sequence),
        summary,
      )
    {
      Ok(runtime_core.Complete(core)) -> Ok(core)
      Ok(runtime_core.MissingPrefix(_, _, _, _)) ->
        Error(id <> ": bootstrap needs a missing prefix")
      Error(error) -> Error(string.inspect(error))
    },
  )
  use core <- result.try(
    list.try_fold(tail, core, fn(core, message) {
      runtime_core.handle_sequenced(core, message)
      |> result.map(fn(outcome) { outcome.0 })
      |> result.map_error(string.inspect)
    }),
  )
  use captured <- result.try(
    runtime_core.capture_summary(core)
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(
    fluid_document.encode(captured)
    |> result.map_error(string.inspect),
  )
  use reloaded <- result.try(
    fluid_document.decode(encoded, None, session, view)
    |> result.map_error(string.inspect),
  )
  use address <- result.try(tree_address(reloaded))
  use restored <- result.try(
    case
      runtime_core.bootstrap_document(
        runtime_fixture.connected(
          "reader",
          [],
          fluid_document.sequence_number(reloaded),
        ),
        reloaded,
      )
    {
      Ok(runtime_core.Complete(core)) -> Ok(core)
      Ok(runtime_core.MissingPrefix(_, _, _, _)) ->
        Error(id <> ": restored summary needs a missing prefix")
      Error(error) -> Error(string.inspect(error))
    },
  )
  use before <- result.try(
    runtime_core.tree_read(core, address, [])
    |> result.map_error(string.inspect),
  )
  use after <- result.try(
    runtime_core.tree_read(restored, address, [])
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case
      before == after
      && fluid_document.sequence_number(reloaded)
      == fluid_document.sequence_number(captured)
    {
      True -> Ok(Nil)
      False -> Error(id <> ": restored summary changed tree root or sequence")
    },
  )
  use tree <- result.try(entry_json(encoded))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("snapshotSequenceNumber", json.int(sequence)),
      #(
        "publicationSequenceNumber",
        json.int(fluid_document.sequence_number(captured)),
      ),
      #("tree", tree),
    ]),
  )
}

fn tree_address(
  summary: fluid_document.DocumentSummary,
) -> Result(String, String) {
  let trees =
    list.flat_map(fluid_document.datastores(summary), fn(store) {
      list.flat_map(store.channels, fn(item) {
        case item.snapshot {
          channel.TreeSnapshot(_) -> [store.id <> "/" <> item.id]
          _ -> []
        }
      })
    })
  case trees {
    [address] -> Ok(address)
    _ -> Error("summary needs exactly one SharedTree channel")
  }
}

fn entry_json(entry: fluid_summary.SummaryEntry) -> Result(Json, String) {
  case entry {
    fluid_summary.SummaryTree(entries) -> {
      use children <- result.try(
        list.try_map(entries, fn(entry) {
          use child <- result.try(entry_json(entry.1))
          Ok(json.array([json.string(entry.0), child], fn(value) { value }))
        }),
      )
      Ok(
        json.object([
          #("type", json.string("tree")),
          #("entries", json.array(children, fn(value) { value })),
        ]),
      )
    }
    fluid_summary.SummaryBlob(bytes) ->
      Ok(
        json.object([
          #("type", json.string("blob")),
          #("base64", json.string(bit_array.base64_encode(bytes, True))),
        ]),
      )
    fluid_summary.SummaryHandle(_, _) ->
      Error("published summary has an unresolved reference")
  }
}
