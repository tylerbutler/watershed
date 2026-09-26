import gleam/json
import watershed/tree/fixtures
import watershed/tree/schema_evolution_fixture

pub fn shared_tree_schema_evolution_compatibility_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-compatibility",
    schema_evolution_fixture.run_compatibility,
  )
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
