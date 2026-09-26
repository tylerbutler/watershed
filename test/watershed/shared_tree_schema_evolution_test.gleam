import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/tree/fixtures
import watershed/tree/schema_evolution_fixture

pub fn shared_tree_schema_evolution_compatibility_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-compatibility")
  let assert Ok(actual) =
    schema_evolution_fixture.run_compatibility(fixture.input)
  let assert Ok(actual_status) =
    schema_evolution_fixture.compatibility_projection(actual)
  let assert Ok(expected_status) =
    schema_evolution_fixture.compatibility_projection(fixture.expected)
  fixtures.first_difference(actual_status, expected_status)
  |> expect.to_equal(Ok(Nil))
  array_length(actual, "observations") |> expect.to_equal(10)
  array_length(actual, "refusals") |> expect.to_equal(6)
  array_length(actual, "rawProbes") |> expect.to_equal(5)
  let encoded = json.to_string(actual)
  string.contains(encoded, "submittedMessages") |> expect.to_be_false
  string.contains(encoded, "beforeRoot") |> expect.to_be_false
  string.contains(encoded, "discrepancies") |> expect.to_be_false
  string.contains(encoded, "\"id\":\"narrow\",\"compatibility\"")
  |> expect.to_be_true
  string.contains(
    encoded,
    "\"id\":\"optional-to-required\",\"availability\":\"missing-input\"",
  )
  |> expect.to_be_true
  string.contains(encoded, "\"id\":\"duplicate-keys\",\"parsed\":false")
  |> expect.to_be_true
}

pub fn shared_tree_schema_evolution_runner_rejects_empty_input_test() -> Nil {
  let input =
    json.object([
      #("schemas", json.array([], fn(value) { value })),
      #("scenarios", json.array([], fn(value) { value })),
      #("refusals", json.array([], fn(value) { value })),
      #("rawProbes", json.array([], fn(value) { value })),
    ])
  let assert Error(_) = schema_evolution_fixture.run_compatibility(input)
  Nil
}

fn array_length(input: json.Json, field: String) -> Int {
  let assert Ok(values) =
    json.parse(
      json.to_string(input),
      decode.at([field], decode.list(decode.dynamic)),
    )
  list.length(values)
}
