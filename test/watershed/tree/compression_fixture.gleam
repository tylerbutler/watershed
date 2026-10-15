import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
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

fn frame_decoder() -> decode.Decoder(Frame) {
  use id <- decode.field("id", decode.string)
  use compressed <- decode.field("compressedBase64", decode.string)
  use decoded <- decode.field("decodedBase64", decode.string)
  decode.success(Frame(id:, compressed:, decoded:))
}
