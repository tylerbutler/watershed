import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

import watershed/wire.{type SequencedEnvelope}
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

fn read_fixture() -> Result(String, String) {
  simplifile.read(fixture_path)
  |> result.map_error(fn(_) {
    "could not read compression fixture at " <> fixture_path
  })
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
