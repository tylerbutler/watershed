import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import startest/expect
import watershed/tree/fixtures
import watershed/tree/identifier_fixture
import watershed/tree/schema
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
  string.contains(encoded, "\"availability\":\"missing-input\"")
  |> expect.to_be_false
  [
    "\"id\":\"narrow\",\"classification\":\"upstream-refusal\",\"compatibility\":{\"canView\":false,\"canUpgrade\":false,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"new-required\",\"classification\":\"upstream-refusal\",\"compatibility\":{\"canView\":false,\"canUpgrade\":false,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"optional-to-required\",\"classification\":\"upstream-refusal\",\"compatibility\":{\"canView\":false,\"canUpgrade\":false,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"node-kind-replacement\",\"classification\":\"m4-profile-exclusion\",\"compatibility\":{\"canView\":false,\"canUpgrade\":true,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"sequence\",\"classification\":\"m4-profile-exclusion\",\"compatibility\":{\"canView\":false,\"canUpgrade\":true,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"handle\",\"classification\":\"m4-profile-exclusion\",\"compatibility\":{\"canView\":false,\"canUpgrade\":true,\"isEquivalent\":false},\"preparation\":{\"outcome\":\"refused\"",
    "\"id\":\"metadata\",\"parsed\":true,\"classification\":\"compatibility\",\"compatibility\":{\"canView\":true,\"canUpgrade\":true,\"isEquivalent\":true}",
    "\"id\":\"duplicate-keys\",\"parsed\":false,\"classification\":\"stored-decode-refusal\",\"error\":",
    "\"id\":\"ordering\",\"parsed\":true,\"classification\":\"compatibility\",\"compatibility\":{\"canView\":true,\"canUpgrade\":true,\"isEquivalent\":true}",
    "\"id\":\"unused-definitions\",\"parsed\":true,\"classification\":\"compatibility\",\"compatibility\":{\"canView\":true,\"canUpgrade\":false,\"isEquivalent\":false}",
    "\"id\":\"required-cycle\",\"parsed\":true,\"classification\":\"compatibility\",\"compatibility\":{\"canView\":false,\"canUpgrade\":false,\"isEquivalent\":false}",
  ]
  |> list.each(fn(expected) {
    string.contains(encoded, expected) |> expect.to_be_true
  })
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

pub fn shared_tree_schema_evolution_identifier_widens_one_way_test() {
  let identifier = identifier_fixture.stored()
  let value = identifier_fixture.view("Value")
  schema.compatibility(identifier, value)
  |> expect.to_equal(Ok(schema.Compatibility(True, True, False)))
  let assert Ok(Some(upgraded)) = schema.prepare_upgrade(identifier, value)
  schema.field_schema(upgraded, identifier_fixture.point_type, "id")
  |> expect.to_equal(
    Ok(schema.FieldSchema(schema.Required, ["com.fluidframework.leaf.string"])),
  )

  let value_stored = schema.view_to_stored(value)
  let identifier_view = identifier_fixture.view("Identifier")
  schema.compatibility(value_stored, identifier_view)
  |> expect.to_equal(Ok(schema.Compatibility(False, False, False)))
  let assert Error(_) = schema.prepare_upgrade(value_stored, identifier_view)
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
