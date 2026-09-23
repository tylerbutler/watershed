import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/json_ot.{VArray, VObject, VString}
import watershed/tree/codec_fixture
import watershed/tree/fixtures

pub fn shared_tree_codec_matches_upstream_test() -> Nil {
  fixtures.assert_case("tree-codecs", codec_fixture.run)
}

pub fn shared_tree_codec_fixture_rejects_missing_input_test() -> Nil {
  let _ = codec_fixture.run(json.object([])) |> expect.to_be_error
  Nil
}

pub fn shared_tree_codec_fixture_detects_message_mutation_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) = fixtures.load("tree-codecs")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VArray(scenarios)) = list.key_find(root, "scenarios")
  let assert [VObject(first), ..rest] = scenarios
  let assert Ok(VArray([VString(message), ..messages])) =
    list.key_find(first, "messages")
  let changed_message =
    message
    |> string.replace("\"version\":7", "\"version\":999")
  let changed_first =
    VObject(list.key_set(
      first,
      "messages",
      VArray([VString(changed_message), ..messages]),
    ))
  let changed =
    VObject(list.key_set(root, "scenarios", VArray([changed_first, ..rest])))
    |> json_ot.to_json
  let _ = codec_fixture.run(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_codec_fixture_observes_message_content_mutation_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) = fixtures.load("tree-codecs")
  let assert Ok(original) = codec_fixture.run(input)
  let changed = replace_input(input, "\\\"right\\\"", "\\\"changed\\\"")
  case codec_fixture.run(changed) {
    Error(_) -> Nil
    Ok(observation) -> expect.to_be_false(observation == original)
  }
}

pub fn shared_tree_codec_fixture_rejects_context_and_summary_mutations_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) = fixtures.load("tree-codecs")
  [
    #("\"requestedClusterSize\":512", "\"requestedClusterSize\":0"),
    #(
      "\\\"root\\\":{\\\"kind\\\":\\\"Forbidden\\\"",
      "\\\"root\\\":{\\\"kind\\\":\\\"Sequence\\\"",
    ),
    #("\\\"maxId\\\":4", "\\\"maxId\\\":1"),
    #("\\\"sequenceNumber\\\":6", "\\\"sequenceNumber\\\":3"),
  ]
  |> list.each(fn(replacement) {
    let changed = replace_input(input, replacement.0, replacement.1)
    let _ = codec_fixture.run(changed) |> expect.to_be_error
    Nil
  })
}

fn replace_input(input: json.Json, before: String, after: String) -> json.Json {
  let raw = json.to_string(input)
  let changed = string.replace(raw, before, after)
  expect.to_be_false(changed == raw)
  let assert Ok(value) = json_ot.parse_json(changed)
  json_ot.to_json(value)
}
