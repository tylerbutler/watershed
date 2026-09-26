import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/schema
import watershed/tree/schema_evolution_fixture
import watershed/tree/shared_change

pub fn shared_tree_outer_empty_is_not_empty_modular_test() -> Nil {
  shared_change.to_changes(shared_change.empty())
  |> expect.to_equal([])
  shared_change.to_changes(shared_change.from_data(change.empty()))
  |> expect.to_equal([shared_change.DataChange(change.empty())])
}

pub fn shared_tree_schema_evolution_algebra_test() -> Nil {
  fixtures.assert_case(
    "schema-evolution-algebra",
    schema_evolution_fixture.run_algebra,
  )
}

pub fn shared_tree_schema_change_preserves_metadata_payloads_test() -> Nil {
  let before_raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1},\"metadata\":{\"description\":\"before\"}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let after_raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1},\"metadata\":{\"description\":\"after\"}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let assert Ok(before) = schema.stored_from_string(before_raw)
  let assert Ok(after) = schema.stored_from_string(after_raw)
  let item =
    shared_change.SchemaChange(
      schema.FixedSchema(before),
      schema.FixedSchema(after),
      False,
    )
  let assert Ok(value) = shared_change.from_changes([item])
  let assert [
    shared_change.SchemaChange(
      schema.FixedSchema(actual_before),
      schema.FixedSchema(actual_after),
      False,
    ),
  ] = shared_change.to_changes(value)
  schema.stored_to_json(actual_before)
  |> expect.to_equal(schema.stored_to_json(before))
  schema.stored_to_json(actual_after)
  |> expect.to_equal(schema.stored_to_json(after))
}

pub fn shared_tree_data_only_rebase_matches_modular_rebase_test() -> Nil {
  let data = change.empty()
  let assert Ok(context) = change.rebase_context([])
  let assert Ok(expected) =
    change.rebase(
      change.TaggedChange(None, None, data),
      change.TaggedChange(None, None, data),
      context,
    )
  let assert Ok(actual) =
    shared_change.rebase(
      shared_change.TaggedChange(None, None, shared_change.from_data(data)),
      shared_change.TaggedChange(None, None, shared_change.from_data(data)),
      context,
    )
  shared_change.to_changes(actual)
  |> expect.to_equal([shared_change.DataChange(expected)])
}

pub fn shared_tree_schema_only_revision_and_local_id_test() -> Nil {
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000008")
  let assert Ok(value) =
    shared_change.from_changes([
      shared_change.SchemaChange(schema.EmptySchema, schema.EmptySchema, False),
    ])
  let tagged = shared_change.TaggedChange(Some(revision), None, value)
  shared_change.revision_infos(tagged)
  |> expect.to_equal([change.RevisionInfo(revision, None)])
  shared_change.max_local_id(value) |> expect.to_equal(-1)
}

pub fn shared_tree_revision_infos_retain_conflicting_metadata_test() -> Nil {
  let assert Ok(revision) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000008")
  let assert Ok(original) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000009")
  let assert Ok(order) = change.identity_order([#(revision, 0)])
  let assert Ok(data) =
    change.from_data(
      change.ChangeData(
        max_local_id: -1,
        revisions: [change.RevisionInfo(revision, None)],
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        builds: [],
        destroys: [],
        refreshers: [],
      ),
      order,
    )
  shared_change.revision_infos(shared_change.TaggedChange(
    Some(revision),
    Some(original),
    shared_change.from_data(data),
  ))
  |> expect.to_equal([
    change.RevisionInfo(revision, Some(original)),
    change.RevisionInfo(revision, None),
  ])
}
