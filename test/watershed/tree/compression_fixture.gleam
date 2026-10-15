import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const fixture_path = "test/fixtures/shared_tree/compression.json"

type Frame {
  Frame(id: String, compressed: String, decoded: String)
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

fn frame_decoder() -> decode.Decoder(Frame) {
  use id <- decode.field("id", decode.string)
  use compressed <- decode.field("compressedBase64", decode.string)
  use decoded <- decode.field("decodedBase64", decode.string)
  decode.success(Frame(id:, compressed:, decoded:))
}
