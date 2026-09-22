import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/types.{
  type AtomId, AtomId, CorruptData, InvalidHistory, NumberValue,
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn revision_a() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-0000000000a0")
}

fn revision_b() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-0000000000b0")
}

fn atom(local_id: Int) -> AtomId {
  AtomId(Some(revision_a()), local_id)
}

fn atom_b(local_id: Int) -> AtomId {
  AtomId(Some(revision_b()), local_id)
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

pub fn shared_tree_change_empty_data_round_trips_test() {
  let empty = change.empty()
  change.to_data(empty) |> expect.to_equal(empty_data())
  change.from_data(change.to_data(empty))
  |> expect.to_equal(Ok(empty))
}

pub fn shared_tree_change_rejects_duplicate_tables_and_generic_indices_test() {
  let field = change.GenericField([#(0, atom(1))])
  let node = change.NodeChange([])
  [
    change.ChangeData(..empty_data(), fields: [
      #("root", field),
      #("root", field),
    ]),
    change.ChangeData(..empty_data(), nodes: [
      #(atom(1), node),
      #(atom(1), node),
    ]),
    change.ChangeData(..empty_data(), fields: [
      #("root", change.GenericField([#(1, atom(1))])),
    ]),
  ]
  |> list.each(fn(data) {
    let assert Error(CorruptData(_, _)) = change.from_data(data)
    Nil
  })
}

pub fn shared_tree_change_rejects_alias_and_rollback_cycles_test() {
  let alias_cycle =
    change.ChangeData(..empty_data(), aliases: [
      #(atom(1), atom(2)),
      #(atom(2), atom(1)),
    ])
  let assert Error(CorruptData(_, _)) = change.from_data(alias_cycle)

  let rollback_cycle =
    change.ChangeData(..empty_data(), revisions: [
      change.RevisionInfo(revision_a(), Some(revision_b())),
      change.RevisionInfo(revision_b(), Some(revision_a())),
    ])
  let assert Error(InvalidHistory(_)) = change.from_data(rollback_cycle)
  Nil
}

pub fn shared_tree_change_accepts_unused_alias_chain_and_safe_boundary_test() {
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 9_007_199_254_740_991,
      aliases: [#(atom(1), atom(2)), #(atom(2), atom(3))],
    )
  let assert Ok(parsed) = change.from_data(data)
  change.to_data(parsed) |> expect.to_equal(data)

  change.rebase_context([
    change.RevisionInfo(revision_a(), None),
    change.RevisionInfo(revision_b(), Some(revision_a())),
  ])
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_change_validates_concrete_field_changes_test() {
  let invalid =
    optional_field.FieldChange([#(AtomId(None, -1), atom(1))], [], None)
  let data =
    change.ChangeData(..empty_data(), fields: [
      #("root", change.ValueField(invalid)),
    ])
  let assert Error(CorruptData(_, _)) = change.from_data(data)
  Nil
}

pub fn shared_tree_change_rejects_duplicate_detached_ranges_test() {
  let build = forest.Build(atom(10), [NumberValue(1.0)])
  let data = change.ChangeData(..empty_data(), builds: [build, build])
  let assert Error(CorruptData(_, _)) = change.from_data(data)
  Nil
}

pub fn shared_tree_change_rejects_missing_and_multiply_owned_nodes_test() {
  let missing =
    change.ChangeData(..empty_data(), fields: [
      #("root", change.GenericField([#(0, atom(1))])),
    ])
  let assert Error(CorruptData(_, _)) = change.from_data(missing)

  let child = change.GenericField([#(0, atom(1))])
  let multiply_owned =
    change.ChangeData(
      ..empty_data(),
      fields: [#("left", child), #("right", child)],
      nodes: [#(atom(1), change.NodeChange([]))],
      parents: [#(atom(1), change.ParentField(None, "left"))],
    )
  let assert Error(CorruptData(_, _)) = change.from_data(multiply_owned)
  Nil
}

pub fn shared_tree_change_accepts_alias_bearing_nested_graph_test() {
  let root =
    change.OptionalField(optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom_b(4))],
      None,
    ))
  let nested =
    change.OptionalField(optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom(5))],
      None,
    ))
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 5,
      revisions: [change.RevisionInfo(revision_a(), None)],
      fields: [#("root", root)],
      nodes: [
        #(atom(4), change.NodeChange([#("child", nested)])),
        #(atom(5), change.NodeChange([])),
      ],
      parents: [
        #(atom(4), change.ParentField(None, "root")),
        #(atom(5), change.ParentField(Some(atom(4)), "child")),
      ],
      aliases: [#(atom_b(4), atom(4))],
    )
  let assert Ok(parsed) = change.from_data(data)
  change.to_data(parsed) |> expect.to_equal(data)
}

pub fn shared_tree_change_allows_missing_rollback_target_metadata_test() {
  let revisions = [change.RevisionInfo(revision_b(), Some(revision_a()))]
  change.rebase_context(revisions) |> expect.to_be_ok
  Nil
}
