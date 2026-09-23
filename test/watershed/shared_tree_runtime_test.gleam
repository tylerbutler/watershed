import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import startest/expect
import watershed/fluid_ids
import watershed/tree/fixtures
import watershed/tree/runtime_fixture
import watershed/wire

const peer_session = "30000000-0000-4000-8000-000000000003"

pub fn shared_tree_runtime_fixture_reads_empty_trunk_and_prefix_test() {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  list.each(["bootstrap-map-handles", "batched-commits"], fn(name) {
    let assert Ok(fixture) = fixtures.load(name)
    let assert Ok(input) = runtime_fixture.read(fixture.input, session)
    input.sequence_number |> expect.to_equal(0)
    input.minimum_sequence_number |> expect.to_equal(0)
    input.tree.history.trunk |> expect.to_equal([])
    input.tree.history.branches |> expect.to_equal([])
    list.map(input.prefix, fn(message) { message.sequence_number })
    |> expect.to_equal([1, 2])
    list.map(input.prefix, fn(message) { message.message_type })
    |> expect.to_equal(["join", "join"])
  })
}

pub fn shared_tree_runtime_fixture_refuses_missing_prefix_test() {
  let assert Ok(session) = fluid_ids.session_id(peer_session)
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Ok(fields) =
    json.parse(
      json.to_string(fixture.input),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
  let assert Ok(decoder_input) = dict.get(fields, "decoderInput")
  let assert Ok(decoder_fields) =
    json.parse(
      json.to_string(decoder_input),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
  list.each([False, True], fn(missing) {
    let decoder_fields = case missing {
      True -> dict.delete(decoder_fields, "deliveryPrefix")
      False ->
        dict.insert(
          decoder_fields,
          "deliveryPrefix",
          json.preprocessed_array([]),
        )
    }
    let input =
      fields
      |> dict.insert("decoderInput", json.object(dict.to_list(decoder_fields)))
      |> dict.to_list
      |> json.object
    runtime_fixture.read(input, session) |> expect.to_be_error()
  })
}
