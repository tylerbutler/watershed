import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/schema_evolution_fixture
import watershed/tree/shared_change
import watershed/tree/types.{AtomId, StringValue}

pub fn shared_tree_outer_empty_is_not_empty_modular_test() -> Nil {
  shared_change.to_changes(shared_change.empty())
  |> expect.to_equal([])
  shared_change.to_changes(shared_change.from_data(change.empty()))
  |> expect.to_equal([shared_change.DataChange(change.empty())])
}

pub fn shared_tree_schema_evolution_algebra_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-algebra")
  let assert Ok(expected) =
    schema_evolution_fixture.project_algebra_expected(
      fixture.input,
      fixture.expected,
    )
  let assert Ok(actual) = schema_evolution_fixture.run_algebra(fixture.input)
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_algebra_observation_uses_returned_data_test() -> Nil {
  let revision = stable_id("00000000-0000-4000-8000-000000000008")
  let order = identity_order([#(revision, 0)])
  let original =
    modular_change(
      order,
      change.ChangeData(
        ..empty_data(),
        max_local_id: 0,
        revisions: [change.RevisionInfo(revision, None)],
        builds: [forest.Build(AtomId(Some(revision), 0), [StringValue("one")])],
      ),
    )
  let different =
    modular_change(
      order,
      change.ChangeData(..change.to_data(original), builds: [
        forest.Build(AtomId(Some(revision), 0), [StringValue("two")]),
      ]),
    )
  schema_evolution_fixture.data_observation(original)
  |> json.to_string
  |> expect.to_not_equal(
    schema_evolution_fixture.data_observation(different) |> json.to_string,
  )
}

pub fn shared_tree_adjacent_data_normalizes_with_metadata_test() -> Nil {
  let first_revision = stable_id("00000000-0000-4000-8000-000000000008")
  let second_revision = stable_id("00000000-0000-4000-8000-000000000009")
  let rollback_revision = stable_id("00000000-0000-4000-8000-00000000000a")
  let order =
    identity_order([
      #(first_revision, 0),
      #(second_revision, 1),
      #(rollback_revision, 2),
    ])
  let first_build =
    forest.Build(AtomId(Some(first_revision), 0), [StringValue("first")])
  let second_build =
    forest.Build(AtomId(Some(second_revision), 0), [StringValue("second")])
  let first =
    modular_change(
      order,
      change.ChangeData(..empty_data(), max_local_id: 0, builds: [first_build]),
    )
  let second =
    modular_change(
      order,
      change.ChangeData(..empty_data(), max_local_id: 0, builds: [second_build]),
    )
  let assert Ok(composed) =
    shared_change.compose([
      shared_change.TaggedChange(
        Some(first_revision),
        None,
        shared_change.from_data(first),
      ),
      shared_change.TaggedChange(
        Some(second_revision),
        Some(rollback_revision),
        shared_change.from_data(second),
      ),
    ])
  let assert [shared_change.DataChange(data)] =
    shared_change.to_changes(composed)
  let data = change.to_data(data)
  data.builds |> expect.to_equal([first_build, second_build])
  data.revisions
  |> expect.to_equal([
    change.RevisionInfo(first_revision, None),
    change.RevisionInfo(second_revision, Some(rollback_revision)),
    change.RevisionInfo(rollback_revision, None),
  ])
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

fn empty_data() -> change.ChangeData {
  change.ChangeData(
    max_local_id: -1,
    revisions: [],
    fields: [],
    nodes: [],
    parents: [],
    aliases: [],
    builds: [],
    destroys: [],
    refreshers: [],
  )
}

fn stable_id(raw: String) -> fluid_ids.StableId {
  let assert Ok(value) = fluid_ids.stable_id(raw)
  value
}

fn identity_order(
  entries: List(#(fluid_ids.StableId, Int)),
) -> change.IdentityOrder {
  let assert Ok(value) = change.identity_order(entries)
  value
}

fn modular_change(
  order: change.IdentityOrder,
  data: change.ChangeData,
) -> change.Changeset {
  let assert Ok(value) = change.from_data(data, order)
  value
}
