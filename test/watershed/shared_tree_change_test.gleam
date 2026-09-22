import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{
  type AtomId, type Edit, type TreeValue, AtomId, ClearField, CorruptData,
  InvalidEdit, InvalidHistory, NullValue, NumberValue, ObjectValue, SetField,
  StringValue,
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

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

fn synthetic_first_data() -> change.ChangeData {
  let root =
    change.OptionalField(optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom_b(4))],
      Some(optional_field.Replacement(
        True,
        Some(optional_field.Detached(atom(30))),
        atom(31),
      )),
    ))
  let nested = change.ValueField(optional_field.set(False, atom(40), atom(41)))
  let pruned_optional =
    change.OptionalField(optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom(5))],
      None,
    ))
  change.ChangeData(
    ..empty_data(),
    max_local_id: 41,
    revisions: [change.RevisionInfo(revision_a(), None)],
    fields: [#("root", root)],
    nodes: [
      #(
        atom(4),
        change.NodeChange([
          #("nested-required", nested),
          #("pruned-optional", pruned_optional),
        ]),
      ),
      #(atom(5), change.NodeChange([])),
    ],
    parents: [
      #(atom(4), change.ParentField(None, "root")),
      #(atom(5), change.ParentField(Some(atom(4)), "pruned-optional")),
    ],
    aliases: [#(atom_b(4), atom(4))],
    builds: [forest.Build(atom(20), [StringValue("built")])],
    refreshers: [forest.Build(atom_b(21), [StringValue("stale")])],
  )
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  stored
}

fn point(x: Float, y: Float) -> TreeValue {
  ObjectValue("Point", [
    #("x", NumberValue(x)),
    #("y", NumberValue(y)),
  ])
}

fn root() -> TreeValue {
  ObjectValue("Root", [#("point", point(1.0, 2.0))])
}

fn initial_forest() -> forest.Forest {
  let view = revision("00000000-0000-4000-8000-000000000001")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  state
}

fn authored(revision: fluid_ids.StableId, operation: Edit) -> change.Changeset {
  let assert Ok(authored) =
    change.edit(stored_schema(), initial_forest(), revision, operation)
  authored
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

pub fn shared_tree_change_rejects_alias_keyed_node_tables_test() {
  let alias = #(atom(1), atom(2))
  let node_keyed_by_alias =
    change.ChangeData(
      ..empty_data(),
      fields: [#("root", change.GenericField([#(0, atom(2))]))],
      nodes: [#(atom(1), change.NodeChange([]))],
      parents: [#(atom(1), change.ParentField(None, "root"))],
      aliases: [alias],
    )
  let assert Error(CorruptData("node changes", _)) =
    change.from_data(node_keyed_by_alias)

  let parent_keyed_by_alias =
    change.ChangeData(
      ..empty_data(),
      fields: [#("root", change.GenericField([#(0, atom(2))]))],
      nodes: [#(atom(2), change.NodeChange([]))],
      parents: [#(atom(1), change.ParentField(None, "root"))],
      aliases: [alias],
    )
  let assert Error(CorruptData("node parents", _)) =
    change.from_data(parent_keyed_by_alias)
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

pub fn shared_tree_change_nested_leaf_edit_builds_complete_delta_test() {
  let initial = initial_forest()
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      initial,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let expected =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 3,
      revisions: [change.RevisionInfo(revision_a(), None)],
      fields: [
        #("rootFieldKey", change.GenericField([#(0, atom(3))])),
      ],
      nodes: [
        #(
          atom(2),
          change.NodeChange([
            #(
              "x",
              change.ValueField(optional_field.set(False, atom(0), atom(1))),
            ),
          ]),
        ),
        #(
          atom(3),
          change.NodeChange([
            #("point", change.GenericField([#(0, atom(2))])),
          ]),
        ),
      ],
      parents: [
        #(atom(2), change.ParentField(Some(atom(3)), "point")),
        #(atom(3), change.ParentField(None, "rootFieldKey")),
      ],
      builds: [forest.Build(atom(0), [NumberValue(7.0)])],
    )
  change.to_data(authored) |> expect.to_equal(expected)

  let tagged = change.TaggedChange(Some(revision_a()), None, authored)
  let assert Ok(delta) = change.into_delta(tagged)
  forest.delta_data(delta)
  |> expect.to_equal(
    forest.DeltaData(
      latest_revision: Some(revision_a()),
      fields: [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #(
                "point",
                forest.FieldDelta([
                  forest.Mark(1, None, None, [
                    #(
                      "x",
                      forest.FieldDelta([
                        forest.Mark(1, Some(atom(0)), Some(atom(1)), []),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ]),
          ]),
        ),
      ],
      build: [forest.Build(atom(0), [NumberValue(7.0)])],
      refreshers: [],
      global: [],
      rename: [],
      destroy: [],
    ),
  )

  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.read(updated, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  forest.read(initial, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn shared_tree_change_optional_edit_uses_detach_then_fill_ids_test() {
  let initial = initial_forest()
  let assert Ok(set) =
    change.edit(
      stored_schema(),
      initial,
      revision_a(),
      SetField(["note"], StringValue("present")),
    )
  let set_data = change.to_data(set)
  set_data.max_local_id |> expect.to_equal(2)
  set_data.builds
  |> expect.to_equal([forest.Build(atom(1), [StringValue("present")])])
  set_data.nodes
  |> expect.to_equal([
    #(
      atom(2),
      change.NodeChange([
        #(
          "note",
          change.OptionalField(optional_field.set(True, atom(1), atom(0))),
        ),
      ]),
    ),
  ])

  let assert Ok(clear) =
    change.edit(stored_schema(), initial, revision_a(), ClearField(["note"]))
  let clear_data = change.to_data(clear)
  clear_data.max_local_id |> expect.to_equal(1)
  clear_data.builds |> expect.to_equal([])
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, clear))
  forest.delta_data(delta).fields
  |> expect.to_equal([
    #("rootFieldKey", forest.FieldDelta([forest.Mark(1, None, None, [])])),
  ])
}

pub fn shared_tree_change_optional_root_set_and_clear_test() {
  let optional_schema =
    string.replace(
      tree_schema,
      "\"root\":{\"kind\":\"Value\"",
      "\"root\":{\"kind\":\"Optional\"",
    )
  let assert Ok(stored) = schema.stored_from_string(optional_schema)
  let view = revision("00000000-0000-4000-8000-000000000002")
  let assert Ok(empty_root) = forest.new(view, stored, None)
  let assert Ok(set) =
    change.edit(stored, empty_root, revision_a(), SetField([], root()))
  change.to_data(set).fields
  |> expect.to_equal([
    #(
      "rootFieldKey",
      change.OptionalField(optional_field.set(True, atom(1), atom(0))),
    ),
  ])
  let assert Ok(set_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, set))
  let assert Ok(with_root) = forest.apply_delta(empty_root, set_delta)
  forest.visible_root(with_root) |> expect.to_equal(Ok(Some(root())))

  let assert Ok(clear) =
    change.edit(stored, with_root, revision_b(), ClearField([]))
  let assert Ok(clear_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, clear))
  let assert Ok(cleared) = forest.apply_delta(with_root, clear_delta)
  forest.visible_root(cleared) |> expect.to_equal(Ok(None))
}

pub fn shared_tree_change_rejects_invalid_edit_paths_and_values_test() {
  let initial = initial_forest()
  [
    ClearField([]),
    ClearField(["point"]),
    SetField(["note", "child"], StringValue("x")),
    SetField(["point", "x", "child"], NumberValue(3.0)),
    SetField(["unknown"], NumberValue(3.0)),
    SetField(["point"], ObjectValue("Point", [])),
    SetField(["note"], NullValue),
  ]
  |> list.each(fn(operation) {
    let assert Error(InvalidEdit(_, _)) =
      change.edit(stored_schema(), initial, revision_a(), operation)
    Nil
  })
}

pub fn shared_tree_change_root_field_key_child_is_not_root_path_test() {
  let source =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Root\":{\"kind\":{\"object\":{\"rootFieldKey\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"
  let assert Ok(stored) = schema.stored_from_string(source)
  let view = revision("00000000-0000-4000-8000-000000000002")
  let initial_value = ObjectValue("Root", [#("rootFieldKey", NumberValue(1.0))])
  let assert Ok(initial) = forest.new(view, stored, Some(initial_value))
  let assert Ok(authored) =
    change.edit(
      stored,
      initial,
      revision_a(),
      SetField(["rootFieldKey"], NumberValue(2.0)),
    )
  change.to_data(authored)
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 2,
      revisions: [change.RevisionInfo(revision_a(), None)],
      fields: [
        #("rootFieldKey", change.GenericField([#(0, atom(2))])),
      ],
      nodes: [
        #(
          atom(2),
          change.NodeChange([
            #(
              "rootFieldKey",
              change.ValueField(optional_field.set(False, atom(0), atom(1))),
            ),
          ]),
        ),
      ],
      parents: [
        #(atom(2), change.ParentField(None, "rootFieldKey")),
      ],
      builds: [forest.Build(atom(0), [NumberValue(2.0)])],
    ),
  )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.read(updated, ["rootFieldKey"])
  |> expect.to_equal(Ok(Some(NumberValue(2.0))))
}

pub fn shared_tree_change_parent_replacement_retains_old_node_test() {
  let initial = initial_forest()
  let assert Ok(old_point) = forest.locate(initial, ["point"])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      initial,
      revision_a(),
      SetField(["point"], point(10.0, 20.0)),
    )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  let assert Ok(new_point) = forest.locate(updated, ["point"])
  expect.to_equal(new_point == old_point, False)
  forest.is_attached(updated, old_point) |> expect.to_equal(Ok(False))
  forest.read_node(updated, old_point) |> expect.to_equal(Ok(point(1.0, 2.0)))
  forest.locate_detached(updated, atom(1)) |> expect.to_equal(Ok(old_point))
}

pub fn shared_tree_change_missing_build_fails_without_mutating_forest_test() {
  let initial = initial_forest()
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      initial,
      revision_a(),
      SetField(["point"], point(10.0, 20.0)),
    )
  let data = change.to_data(authored)
  let assert Ok(incomplete) =
    change.from_data(change.ChangeData(..data, builds: []))
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, incomplete))
  let assert Error(CorruptData(_, _)) = forest.apply_delta(initial, delta)
  forest.visible_root(initial) |> expect.to_equal(Ok(Some(root())))
}

pub fn shared_tree_change_delta_collects_global_rename_and_detached_data_test() {
  let detached = atom(20)
  let node = atom(30)
  let field =
    change.ValueField(optional_field.FieldChange(
      [#(atom(10), atom(11))],
      [#(optional_field.Detached(detached), node)],
      None,
    ))
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 30,
      fields: [#("root", field)],
      nodes: [#(node, change.NodeChange([]))],
      parents: [#(node, change.ParentField(None, "root"))],
      builds: [forest.Build(atom(40), [NumberValue(4.0)])],
      destroys: [forest.Destroy(atom(50), 1)],
      refreshers: [forest.Build(atom(60), [NumberValue(6.0)])],
    )
  let assert Ok(authored) = change.from_data(data)
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
  forest.delta_data(delta)
  |> expect.to_equal(
    forest.DeltaData(
      latest_revision: Some(revision_a()),
      fields: [],
      build: [forest.Build(atom(40), [NumberValue(4.0)])],
      refreshers: [forest.Build(atom(60), [NumberValue(6.0)])],
      global: [forest.DetachedChange(detached, [])],
      rename: [forest.Rename(atom(10), atom(11), 1)],
      destroy: [forest.Destroy(atom(50), 1)],
    ),
  )
}

pub fn shared_tree_change_delta_orders_nested_globals_child_first_test() {
  let outer = atom(10)
  let inner = atom(20)
  let outer_node = atom(30)
  let inner_node = atom(40)
  let data =
    change.ChangeData(
      ..empty_data(),
      fields: [
        #(
          "root",
          change.OptionalField(optional_field.FieldChange(
            [],
            [#(optional_field.Detached(outer), outer_node)],
            None,
          )),
        ),
      ],
      nodes: [
        #(
          outer_node,
          change.NodeChange([
            #(
              "inner",
              change.OptionalField(optional_field.FieldChange(
                [],
                [#(optional_field.Detached(inner), inner_node)],
                None,
              )),
            ),
          ]),
        ),
        #(inner_node, change.NodeChange([])),
      ],
      parents: [
        #(outer_node, change.ParentField(None, "root")),
        #(inner_node, change.ParentField(Some(outer_node), "inner")),
      ],
      refreshers: [
        forest.Build(outer, [point(1.0, 2.0)]),
        forest.Build(inner, [NumberValue(3.0)]),
      ],
    )
  let assert Ok(authored) = change.from_data(data)
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
  forest.delta_data(delta).global
  |> expect.to_equal([
    forest.DetachedChange(inner, []),
    forest.DetachedChange(outer, []),
  ])

  let assert Ok(updated) = forest.apply_delta(initial_forest(), delta)
  let assert Ok(exported) = forest.export_data(updated)
  let assert [outer_entry, inner_entry] = exported.detached
  outer_entry.id |> expect.to_equal(outer)
  outer_entry.forest_root_id |> expect.to_equal(1)
  inner_entry.id |> expect.to_equal(inner)
  inner_entry.forest_root_id |> expect.to_equal(0)
}

pub fn shared_tree_change_compose_nested_edits_matches_sequential_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  let data = change.to_data(composed)
  data.max_local_id |> expect.to_equal(3)
  data.revisions
  |> expect.to_equal([
    change.RevisionInfo(revision_a(), None),
    change.RevisionInfo(revision_b(), None),
  ])
  data.aliases
  |> expect.to_equal([
    #(atom_b(2), atom(2)),
    #(atom_b(3), atom(3)),
  ])
  data.fields
  |> expect.to_equal([
    #("rootFieldKey", change.GenericField([#(0, atom(3))])),
  ])
  data.nodes
  |> expect.to_equal([
    #(
      atom(2),
      change.NodeChange([
        #("x", change.ValueField(optional_field.set(False, atom(0), atom(1)))),
        #(
          "y",
          change.ValueField(optional_field.set(False, atom_b(0), atom_b(1))),
        ),
      ]),
    ),
    #(
      atom(3),
      change.NodeChange([
        #("point", change.GenericField([#(0, atom(2))])),
      ]),
    ),
  ])

  let initial = initial_forest()
  let assert Ok(first_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, first))
  let assert Ok(after_first) = forest.apply_delta(initial, first_delta)
  let assert Ok(second_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, second))
  let assert Ok(sequential) = forest.apply_delta(after_first, second_delta)
  let assert Ok(composed_delta) =
    change.into_delta(change.TaggedChange(None, None, composed))
  let assert Ok(composed_state) = forest.apply_delta(initial, composed_delta)
  forest.visible_root(composed_state)
  |> expect.to_equal(forest.visible_root(sequential))
  let assert Ok(composed_x) = forest.locate_detached(composed_state, atom(1))
  let assert Ok(sequential_x) = forest.locate_detached(sequential, atom(1))
  forest.read_node(composed_state, composed_x)
  |> expect.to_equal(forest.read_node(sequential, sequential_x))
  let assert Ok(composed_y) = forest.locate_detached(composed_state, atom_b(1))
  let assert Ok(sequential_y) = forest.locate_detached(sequential, atom_b(1))
  forest.read_node(composed_state, composed_y)
  |> expect.to_equal(forest.read_node(sequential, sequential_y))
}

pub fn shared_tree_change_compose_uses_balanced_alias_order_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let revision_d = revision("00000000-0000-4000-8000-0000000000d0")
  let third = authored(revision_c, SetField(["point"], point(10.0, 20.0)))
  let fourth = authored(revision_d, SetField(["note"], StringValue("present")))

  let assert Ok(three) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
      change.TaggedChange(Some(revision_c), None, third),
    ])
  change.to_data(three).aliases
  |> expect.to_equal([
    #(atom_b(2), atom(2)),
    #(atom_b(3), atom(3)),
    #(AtomId(Some(revision_c), 2), atom_b(3)),
  ])

  let assert Ok(four) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
      change.TaggedChange(Some(revision_c), None, third),
      change.TaggedChange(Some(revision_d), None, fourth),
    ])
  change.to_data(four).aliases
  |> expect.to_equal([
    #(atom_b(2), atom(2)),
    #(atom_b(3), atom(3)),
    #(AtomId(Some(revision_c), 2), atom(3)),
    #(AtomId(Some(revision_d), 2), AtomId(Some(revision_c), 2)),
  ])
}

pub fn shared_tree_change_replace_revisions_remaps_collisions_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Ok(replaced) =
    change.replace_revisions(
      composed,
      [Some(revision_a()), Some(revision_b())],
      revision_c,
    )
  let data = change.to_data(replaced)
  data.max_local_id |> expect.to_equal(3)
  data.revisions
  |> expect.to_equal([change.RevisionInfo(revision_c, None)])
  data.aliases |> expect.to_equal([])
  data.fields
  |> expect.to_equal([
    #("rootFieldKey", change.GenericField([#(0, AtomId(Some(revision_c), 3))])),
  ])
  let assert [
    #(AtomId(Some(revision_c), 2), change.NodeChange([#("x", x), #("y", y)])),
    _,
  ] = data.nodes
  x
  |> expect.to_equal(
    change.ValueField(optional_field.set(
      False,
      AtomId(Some(revision_c), 0),
      AtomId(Some(revision_c), 1),
    )),
  )
  y
  |> expect.to_equal(
    change.ValueField(optional_field.set(
      False,
      AtomId(Some(revision_c), 5),
      AtomId(Some(revision_c), 4),
    )),
  )
  data.builds
  |> expect.to_equal([
    forest.Build(AtomId(Some(revision_c), 0), [NumberValue(7.0)]),
    forest.Build(AtomId(Some(revision_c), 5), [NumberValue(9.0)]),
  ])
}

pub fn shared_tree_change_replace_revisions_refuses_dangling_alias_test() {
  let root_id = atom(4)
  let alias = atom_b(4)
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 4,
      fields: [#("root", change.GenericField([#(0, alias)]))],
      nodes: [#(root_id, change.NodeChange([]))],
      parents: [#(root_id, change.ParentField(None, "root"))],
      aliases: [#(alias, root_id)],
    )
  let assert Ok(authored) = change.from_data(data)
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Error(CorruptData(_, _)) =
    change.replace_revisions(
      authored,
      [Some(revision_a()), Some(revision_b())],
      revision_c,
    )
  change.to_data(authored) |> expect.to_equal(data)
}

pub fn shared_tree_change_prune_keeps_unused_aliases_test() {
  let leaf = atom(2)
  let root_id = atom(3)
  let alias = atom_b(3)
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 3,
      fields: [#("root", change.GenericField([#(0, alias)]))],
      nodes: [
        #(leaf, change.NodeChange([#("empty", change.GenericField([]))])),
        #(
          root_id,
          change.NodeChange([
            #("child", change.GenericField([#(0, leaf)])),
          ]),
        ),
      ],
      parents: [
        #(leaf, change.ParentField(Some(root_id), "child")),
        #(root_id, change.ParentField(None, "root")),
      ],
      aliases: [#(alias, root_id)],
    )
  let assert Ok(authored) = change.from_data(data)
  let assert Ok(pruned) = change.prune(authored)
  let pruned = change.to_data(pruned)
  pruned.fields |> expect.to_equal([])
  pruned.nodes |> expect.to_equal([])
  pruned.parents |> expect.to_equal([])
  pruned.aliases |> expect.to_equal([#(alias, root_id)])
}

pub fn shared_tree_change_removed_roots_and_refreshers_follow_ranges_test() {
  let child = atom(5)
  let field =
    change.ValueField(optional_field.FieldChange(
      [#(atom(10), atom(11))],
      [
        #(optional_field.Detached(atom(20)), child),
        #(optional_field.Active, atom(6)),
      ],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Detached(atom(30))),
        atom(31),
      )),
    ))
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 31,
      fields: [#("root", field)],
      nodes: [
        #(child, change.NodeChange([])),
        #(atom(6), change.NodeChange([])),
      ],
      parents: [
        #(child, change.ParentField(None, "root")),
        #(atom(6), change.ParentField(None, "root")),
      ],
      builds: [
        forest.Build(atom(19), [
          NumberValue(19.0),
          NumberValue(20.0),
        ]),
      ],
      refreshers: [forest.Build(atom(99), [NumberValue(99.0)])],
    )
  let assert Ok(authored) = change.from_data(data)
  let assert Ok(roots) = change.relevant_removed_roots(authored)
  roots |> expect.to_equal([atom(10), atom(20), atom(30)])

  let assert Ok(refreshed) =
    change.update_refreshers(authored, roots, [
      forest.Build(atom(10), [NumberValue(10.0)]),
      forest.Build(atom(29), [
        NumberValue(29.0),
        NumberValue(30.0),
      ]),
    ])
  change.to_data(refreshed).refreshers
  |> expect.to_equal([
    forest.Build(atom(10), [NumberValue(10.0)]),
    forest.Build(atom(30), [NumberValue(30.0)]),
  ])

  let assert Error(CorruptData(_, _)) =
    change.update_refreshers(authored, [atom(40)], [])
  Nil
}

pub fn shared_tree_change_compose_cancels_matching_build_destroy_test() {
  let build = forest.Build(atom(10), [NumberValue(1.0)])
  let assert Ok(first) =
    change.from_data(change.ChangeData(..empty_data(), builds: [build]))
  let assert Ok(second) =
    change.from_data(
      change.ChangeData(..empty_data(), destroys: [forest.Destroy(atom(10), 1)]),
    )
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(None, None, first),
      change.TaggedChange(None, None, second),
    ])
  change.to_data(composed).builds |> expect.to_equal([])
  change.to_data(composed).destroys |> expect.to_equal([])

  let assert Ok(mismatch) =
    change.from_data(
      change.ChangeData(..empty_data(), destroys: [forest.Destroy(atom(10), 2)]),
    )
  let assert Error(CorruptData(_, _)) =
    change.compose([
      change.TaggedChange(None, None, first),
      change.TaggedChange(None, None, mismatch),
    ])
  Nil
}

pub fn shared_tree_change_compose_normalizes_generic_concrete_fields_test() {
  let first_id = atom(1)
  let second_id = atom_b(1)
  let assert Ok(first) =
    change.from_data(
      change.ChangeData(
        ..empty_data(),
        fields: [#("root", change.GenericField([#(0, first_id)]))],
        nodes: [#(first_id, change.NodeChange([]))],
        parents: [#(first_id, change.ParentField(None, "root"))],
      ),
    )
  let assert Ok(second) =
    change.from_data(
      change.ChangeData(
        ..empty_data(),
        fields: [
          #(
            "root",
            change.ValueField(optional_field.FieldChange(
              [],
              [#(optional_field.Active, second_id)],
              None,
            )),
          ),
        ],
        nodes: [#(second_id, change.NodeChange([]))],
        parents: [#(second_id, change.ParentField(None, "root"))],
      ),
    )
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  let data = change.to_data(composed)
  data.fields
  |> expect.to_equal([
    #(
      "root",
      change.ValueField(optional_field.FieldChange(
        [],
        [#(optional_field.Active, first_id)],
        None,
      )),
    ),
  ])
  data.aliases |> expect.to_equal([#(second_id, first_id)])
}

pub fn shared_tree_change_compose_keeps_earlier_duplicate_content_test() {
  let earlier = forest.Build(atom(10), [NumberValue(1.0)])
  let later = forest.Build(atom(10), [NumberValue(2.0)])
  let assert Ok(first) =
    change.from_data(
      change.ChangeData(..empty_data(), builds: [earlier], refreshers: [earlier]),
    )
  let assert Ok(second) =
    change.from_data(
      change.ChangeData(..empty_data(), builds: [later], refreshers: [later]),
    )
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(None, None, first),
      change.TaggedChange(None, None, second),
    ])
  change.to_data(composed).builds |> expect.to_equal([earlier])
  change.to_data(composed).refreshers |> expect.to_equal([earlier])
}

pub fn shared_tree_change_compose_collects_tagged_rollback_metadata_test() {
  let assert Ok(first) = change.from_data(empty_data())
  let assert Ok(second) = change.from_data(empty_data())
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_b()), Some(revision_a()), first),
      change.TaggedChange(Some(revision_c), None, second),
    ])
  change.to_data(composed).revisions
  |> expect.to_equal([
    change.RevisionInfo(revision_b(), Some(revision_a())),
    change.RevisionInfo(revision_c, None),
    change.RevisionInfo(revision_a(), None),
  ])
}

pub fn shared_tree_change_delta_omits_empty_generic_fields_test() {
  let assert Ok(authored) =
    change.from_data(
      change.ChangeData(..empty_data(), fields: [
        #("root", change.GenericField([])),
      ]),
    )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(None, None, authored))
  forest.delta_data(delta).fields |> expect.to_equal([])
}

pub fn shared_tree_change_invert_distinguishes_rollback_and_undo_test() {
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let authored =
    authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let tagged = change.TaggedChange(Some(revision_a()), None, authored)

  let assert Ok(rollback) = change.invert(tagged, True, revision_c)
  let rollback_data = change.to_data(rollback)
  rollback_data.max_local_id |> expect.to_equal(3)
  rollback_data.revisions
  |> expect.to_equal([
    change.RevisionInfo(revision_c, Some(revision_a())),
  ])
  rollback_data.destroys
  |> expect.to_equal([forest.Destroy(atom(0), 1)])

  let initial = initial_forest()
  let assert Ok(old_x) = forest.locate(initial, ["point", "x"])
  let assert Ok(authored_delta) = change.into_delta(tagged)
  let assert Ok(changed) = forest.apply_delta(initial, authored_delta)
  let assert Ok(rollback_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_c),
      Some(revision_a()),
      rollback,
    ))
  let assert Ok(restored) = forest.apply_delta(changed, rollback_delta)
  forest.visible_root(restored) |> expect.to_equal(Ok(Some(root())))
  forest.locate(restored, ["point", "x"]) |> expect.to_equal(Ok(old_x))

  let assert Ok(undo) = change.invert(tagged, False, revision_c)
  let undo_data = change.to_data(undo)
  undo_data.max_local_id |> expect.to_equal(4)
  undo_data.revisions
  |> expect.to_equal([change.RevisionInfo(revision_c, None)])
  undo_data.destroys |> expect.to_equal([])
}

pub fn shared_tree_change_invert_reserves_each_original_revision_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
    ])
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Ok(undo) =
    change.invert(change.TaggedChange(None, None, composed), False, revision_c)
  let data = change.to_data(undo)
  data.max_local_id |> expect.to_equal(9)
  let assert [
    #(
      _,
      change.NodeChange([
        #("x", change.ValueField(x)),
        #("y", change.ValueField(y)),
      ]),
    ),
    _,
  ] = data.nodes
  let assert optional_field.FieldChange(_, _, Some(x)) = x
  let assert optional_field.FieldChange(_, _, Some(y)) = y
  x.detach_id |> expect.to_equal(AtomId(Some(revision_c), 8))
  y.detach_id |> expect.to_equal(AtomId(Some(revision_c), 9))

  let assert Ok(rollback) =
    change.invert(change.TaggedChange(None, None, composed), True, revision_c)
  let rollback = change.to_data(rollback)
  rollback.max_local_id |> expect.to_equal(7)
  rollback.destroys
  |> expect.to_equal([
    forest.Destroy(atom(0), 1),
    forest.Destroy(atom_b(0), 1),
  ])
}

pub fn shared_tree_change_invert_rejects_destroying_change_test() {
  let data =
    change.ChangeData(..empty_data(), destroys: [forest.Destroy(atom(10), 1)])
  let assert Ok(authored) = change.from_data(data)
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Error(CorruptData(_, _)) =
    change.invert(
      change.TaggedChange(Some(revision_a()), None, authored),
      True,
      revision_c,
    )
  Nil
}

pub fn shared_tree_change_invert_allocator_exhaustion_is_atomic_test() {
  let field =
    change.OptionalField(optional_field.FieldChange(
      [],
      [],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Active),
        atom(0),
      )),
    ))
  let data =
    change.ChangeData(
      ..empty_data(),
      max_local_id: 9_007_199_254_740_991,
      revisions: [change.RevisionInfo(revision_a(), None)],
      fields: [#("root", field)],
    )
  let assert Ok(authored) = change.from_data(data)
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let assert Error(CorruptData(_, _)) =
    change.invert(
      change.TaggedChange(Some(revision_a()), None, authored),
      False,
      revision_c,
    )
  change.to_data(authored) |> expect.to_equal(data)
}

pub fn shared_tree_change_invert_synthetic_reserves_metadata_revisions_test() {
  let assert Ok(first) = change.from_data(synthetic_first_data())
  let assert Ok(inverse) =
    change.invert(
      change.TaggedChange(Some(revision_a()), None, first),
      False,
      revision_b(),
    )
  change.to_data(inverse)
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 43,
      revisions: [change.RevisionInfo(revision_b(), None)],
      fields: [
        #(
          "root",
          change.OptionalField(optional_field.FieldChange(
            [],
            [#(optional_field.Active, atom_b(4))],
            Some(optional_field.Replacement(False, None, atom_b(42))),
          )),
        ),
      ],
      nodes: [
        #(
          atom(4),
          change.NodeChange([
            #(
              "nested-required",
              change.ValueField(optional_field.set(False, atom(41), atom_b(43))),
            ),
            #(
              "pruned-optional",
              change.OptionalField(optional_field.FieldChange(
                [],
                [#(optional_field.Active, atom(5))],
                None,
              )),
            ),
          ]),
        ),
        #(atom(5), change.NodeChange([])),
      ],
      parents: [
        #(atom(4), change.ParentField(None, "root")),
        #(atom(5), change.ParentField(Some(atom(4)), "pruned-optional")),
      ],
      aliases: [#(atom_b(4), atom(4))],
    ),
  )
}

pub fn shared_tree_change_invert_restores_clear_and_parent_replacement_test() {
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let initial = initial_forest()
  let assert Ok(set) =
    change.edit(
      stored_schema(),
      initial,
      revision_a(),
      SetField(["note"], StringValue("present")),
    )
  let assert Ok(set_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, set))
  let assert Ok(with_note) = forest.apply_delta(initial, set_delta)
  let assert Ok(old_note) = forest.locate(with_note, ["note"])
  let assert Ok(clear) =
    change.edit(stored_schema(), with_note, revision_b(), ClearField(["note"]))
  let assert Ok(clear_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, clear))
  let assert Ok(without_note) = forest.apply_delta(with_note, clear_delta)
  let assert Ok(clear_rollback) =
    change.invert(
      change.TaggedChange(Some(revision_b()), None, clear),
      True,
      revision_c,
    )
  let assert Ok(clear_rollback_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_c),
      Some(revision_b()),
      clear_rollback,
    ))
  let assert Ok(restored_note) =
    forest.apply_delta(without_note, clear_rollback_delta)
  forest.locate(restored_note, ["note"])
  |> expect.to_equal(Ok(old_note))
  forest.read_node(restored_note, old_note)
  |> expect.to_equal(Ok(StringValue("present")))

  let assert Ok(old_point) = forest.locate(initial, ["point"])
  let parent = authored(revision_a(), SetField(["point"], point(10.0, 20.0)))
  let assert Ok(parent_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, parent))
  let assert Ok(replaced) = forest.apply_delta(initial, parent_delta)
  let assert Ok(parent_rollback) =
    change.invert(
      change.TaggedChange(Some(revision_a()), None, parent),
      True,
      revision_c,
    )
  let assert Ok(parent_rollback_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_c),
      Some(revision_a()),
      parent_rollback,
    ))
  let assert Ok(restored_parent) =
    forest.apply_delta(replaced, parent_rollback_delta)
  forest.locate(restored_parent, ["point"])
  |> expect.to_equal(Ok(old_point))
  forest.read_node(restored_parent, old_point)
  |> expect.to_equal(Ok(point(1.0, 2.0)))
}

pub fn shared_tree_change_rebase_independent_nested_fields_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(context) =
    change.rebase_context([
      change.RevisionInfo(revision_a(), None),
      change.RevisionInfo(revision_b(), None),
    ])
  let assert Ok(rebased) =
    change.rebase(
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
      context,
    )
  let initial = initial_forest()
  let assert Ok(second_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, second))
  let assert Ok(after_second) = forest.apply_delta(initial, second_delta)
  let assert Ok(rebased_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, rebased))
  let assert Ok(updated) = forest.apply_delta(after_second, rebased_delta)
  forest.visible_root(updated)
  |> expect.to_equal(
    Ok(
      Some(
        ObjectValue("Root", [
          #("point", point(7.0, 9.0)),
        ]),
      ),
    ),
  )
}

pub fn shared_tree_change_rebase_parent_child_keeps_old_object_test() {
  let child =
    authored(revision_a(), SetField(["point", "x"], NumberValue(42.0)))
  let parent = authored(revision_b(), SetField(["point"], point(10.0, 20.0)))
  let assert Ok(context) =
    change.rebase_context([
      change.RevisionInfo(revision_a(), None),
      change.RevisionInfo(revision_b(), None),
    ])
  let assert Ok(child_over_parent) =
    change.rebase(
      change.TaggedChange(Some(revision_a()), None, child),
      change.TaggedChange(Some(revision_b()), None, parent),
      context,
    )
  let rebased_data = change.to_data(child_over_parent)
  let assert [
    #(_, _),
    #(
      root_node_id,
      change.NodeChange([#("point", change.ValueField(point_change))]),
    ),
  ] = rebased_data.nodes
  root_node_id |> expect.to_equal(atom(3))
  let assert optional_field.FieldChange(
    [],
    [#(optional_field.Detached(detached), child_id)],
    None,
  ) = point_change
  detached |> expect.to_equal(atom_b(1))
  child_id |> expect.to_equal(atom(2))
  let initial = initial_forest()
  let assert Ok(old_point) = forest.locate(initial, ["point"])
  let assert Ok(parent_delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, parent))
  let assert Ok(replaced) = forest.apply_delta(initial, parent_delta)
  let assert Ok(child_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_a()),
      None,
      child_over_parent,
    ))
  let assert Ok(updated) = forest.apply_delta(replaced, child_delta)
  forest.read(updated, ["point"])
  |> expect.to_equal(Ok(Some(point(10.0, 20.0))))
  forest.read_node(updated, old_point)
  |> expect.to_equal(Ok(point(42.0, 2.0)))

  let assert Ok(parent_over_child) =
    change.rebase(
      change.TaggedChange(Some(revision_b()), None, parent),
      change.TaggedChange(Some(revision_a()), None, child),
      context,
    )
  let parent_data = change.to_data(parent)
  change.to_data(parent_over_child)
  |> expect.to_equal(change.ChangeData(..parent_data, max_local_id: 3))
  let assert Ok(child_authored_delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, child))
  let assert Ok(child_first) = forest.apply_delta(initial, child_authored_delta)
  let assert Ok(parent_rebased_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_b()),
      None,
      parent_over_child,
    ))
  let assert Ok(opposite) =
    forest.apply_delta(child_first, parent_rebased_delta)
  forest.read(opposite, ["point"])
  |> expect.to_equal(Ok(Some(point(10.0, 20.0))))
  forest.read_node(opposite, old_point)
  |> expect.to_equal(Ok(point(42.0, 2.0)))
}

pub fn shared_tree_change_rebase_repeated_replacement_keeps_detached_target_test() {
  let revision_c = revision("00000000-0000-4000-8000-0000000000c0")
  let child =
    authored(revision_a(), SetField(["point", "x"], NumberValue(42.0)))
  let first_parent =
    authored(revision_b(), SetField(["point"], point(10.0, 20.0)))
  let assert Ok(context) =
    change.rebase_context([
      change.RevisionInfo(revision_a(), None),
      change.RevisionInfo(revision_b(), None),
      change.RevisionInfo(revision_c, None),
    ])
  let assert Ok(detached_child) =
    change.rebase(
      change.TaggedChange(Some(revision_a()), None, child),
      change.TaggedChange(Some(revision_b()), None, first_parent),
      context,
    )

  let initial = initial_forest()
  let assert Ok(original_point) = forest.locate(initial, ["point"])
  let assert Ok(first_parent_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_b()),
      None,
      first_parent,
    ))
  let assert Ok(after_first_parent) =
    forest.apply_delta(initial, first_parent_delta)
  let assert Ok(intermediate_point) =
    forest.locate(after_first_parent, ["point"])
  let assert Ok(second_parent) =
    change.edit(
      stored_schema(),
      after_first_parent,
      revision_c,
      SetField(["point"], point(100.0, 200.0)),
    )
  let assert Ok(rebased_again) =
    change.rebase(
      change.TaggedChange(Some(revision_a()), None, detached_child),
      change.TaggedChange(Some(revision_c), None, second_parent),
      context,
    )
  change.to_data(rebased_again)
  |> expect.to_equal(change.to_data(detached_child))
  let assert Ok(second_parent_delta) =
    change.into_delta(change.TaggedChange(Some(revision_c), None, second_parent))
  let assert Ok(after_second_parent) =
    forest.apply_delta(after_first_parent, second_parent_delta)
  let assert Ok(rebased_delta) =
    change.into_delta(change.TaggedChange(
      Some(revision_a()),
      None,
      rebased_again,
    ))
  let assert Ok(updated) =
    forest.apply_delta(after_second_parent, rebased_delta)
  forest.read(updated, ["point"])
  |> expect.to_equal(Ok(Some(point(100.0, 200.0))))
  forest.read_node(updated, intermediate_point)
  |> expect.to_equal(Ok(point(10.0, 20.0)))
  forest.read_node(updated, original_point)
  |> expect.to_equal(Ok(point(42.0, 2.0)))
}

pub fn shared_tree_change_rebase_requires_complete_context_test() {
  let first = authored(revision_a(), SetField(["point", "x"], NumberValue(7.0)))
  let second =
    authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(context) =
    change.rebase_context([change.RevisionInfo(revision_a(), None)])
  let assert Error(InvalidHistory(_)) =
    change.rebase(
      change.TaggedChange(Some(revision_a()), None, first),
      change.TaggedChange(Some(revision_b()), None, second),
      context,
    )
  Nil
}

pub fn shared_tree_change_optional_root_leaf_values_match_upstream_test() {
  let string_schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let null_schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.null\"]}}"
  let view = revision("00000000-0000-4000-8000-000000000002")

  [#(string_schema, StringValue("after")), #(null_schema, NullValue)]
  |> list.each(fn(example) {
    let assert Ok(stored) = schema.stored_from_string(example.0)
    let assert Ok(initial) = forest.new(view, stored, None)
    let assert Ok(authored) =
      change.edit(stored, initial, revision_a(), SetField([], example.1))
    change.to_data(authored)
    |> expect.to_equal(
      change.ChangeData(
        ..empty_data(),
        max_local_id: 1,
        revisions: [change.RevisionInfo(revision_a(), None)],
        fields: [
          #(
            "rootFieldKey",
            change.OptionalField(optional_field.set(True, atom(1), atom(0))),
          ),
        ],
        builds: [forest.Build(atom(1), [example.1])],
      ),
    )
    let assert Ok(delta) =
      change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
    let assert Ok(updated) = forest.apply_delta(initial, delta)
    forest.visible_root(updated) |> expect.to_equal(Ok(Some(example.1)))
  })
}

pub fn shared_tree_change_optional_root_clear_retains_old_leaf_test() {
  let string_schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let assert Ok(stored) = schema.stored_from_string(string_schema)
  let view = revision("00000000-0000-4000-8000-000000000002")
  let assert Ok(initial) = forest.new(view, stored, Some(StringValue("before")))
  let assert Ok(old_root) = forest.locate(initial, [])
  let assert Ok(authored) =
    change.edit(stored, initial, revision_b(), ClearField([]))
  change.to_data(authored)
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 0,
      revisions: [change.RevisionInfo(revision_b(), None)],
      fields: [
        #(
          "rootFieldKey",
          change.OptionalField(optional_field.clear(False, atom_b(0))),
        ),
      ],
    ),
  )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_b()), None, authored))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.visible_root(updated) |> expect.to_equal(Ok(None))
  forest.locate_detached(updated, atom_b(0))
  |> expect.to_equal(Ok(old_root))
  forest.read_node(updated, old_root)
  |> expect.to_equal(Ok(StringValue("before")))
}

pub fn shared_tree_change_optional_clear_present_keeps_parent_attached_test() {
  let initial_value =
    ObjectValue("Root", [
      #("point", point(1.0, 2.0)),
      #("note", StringValue("present")),
    ])
  let view = revision("00000000-0000-4000-8000-000000000002")
  let assert Ok(initial) =
    forest.new(view, stored_schema(), Some(initial_value))
  let assert Ok(old_point) = forest.locate(initial, ["point"])
  let assert Ok(old_note) = forest.locate(initial, ["note"])
  let assert Ok(authored) =
    change.edit(stored_schema(), initial, revision_a(), ClearField(["note"]))
  change.to_data(authored)
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 1,
      revisions: [change.RevisionInfo(revision_a(), None)],
      fields: [
        #("rootFieldKey", change.GenericField([#(0, atom(1))])),
      ],
      nodes: [
        #(
          atom(1),
          change.NodeChange([
            #(
              "note",
              change.OptionalField(optional_field.clear(False, atom(0))),
            ),
          ]),
        ),
      ],
      parents: [
        #(atom(1), change.ParentField(None, "rootFieldKey")),
      ],
    ),
  )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision_a()), None, authored))
  let assert Ok(updated) = forest.apply_delta(initial, delta)
  forest.read(updated, ["note"]) |> expect.to_equal(Ok(None))
  forest.is_attached(updated, old_point) |> expect.to_equal(Ok(True))
  forest.locate_detached(updated, atom(0))
  |> expect.to_equal(Ok(old_note))
}

pub fn shared_tree_change_compose_reversed_nested_edits_matches_upstream_test() {
  let x = authored(revision_a(), SetField(["point", "x"], NumberValue(42.0)))
  let y = authored(revision_b(), SetField(["point", "y"], NumberValue(9.0)))
  let assert Ok(composed) =
    change.compose([
      change.TaggedChange(Some(revision_b()), None, y),
      change.TaggedChange(Some(revision_a()), None, x),
    ])
  change.to_data(composed)
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 3,
      revisions: [
        change.RevisionInfo(revision_b(), None),
        change.RevisionInfo(revision_a(), None),
      ],
      fields: [
        #("rootFieldKey", change.GenericField([#(0, atom_b(3))])),
      ],
      nodes: [
        #(
          atom_b(2),
          change.NodeChange([
            #(
              "y",
              change.ValueField(optional_field.set(False, atom_b(0), atom_b(1))),
            ),
            #(
              "x",
              change.ValueField(optional_field.set(False, atom(0), atom(1))),
            ),
          ]),
        ),
        #(
          atom_b(3),
          change.NodeChange([
            #("point", change.GenericField([#(0, atom_b(2))])),
          ]),
        ),
      ],
      parents: [
        #(atom_b(2), change.ParentField(Some(atom_b(3)), "point")),
        #(atom_b(3), change.ParentField(None, "rootFieldKey")),
      ],
      aliases: [#(atom(2), atom_b(2)), #(atom(3), atom_b(3))],
      builds: [
        forest.Build(atom(0), [NumberValue(42.0)]),
        forest.Build(atom_b(0), [NumberValue(9.0)]),
      ],
    ),
  )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(None, None, composed))
  let assert Ok(updated) = forest.apply_delta(initial_forest(), delta)
  forest.read(updated, ["point"])
  |> expect.to_equal(Ok(Some(point(42.0, 9.0))))
}

pub fn shared_tree_change_delta_represents_additive_nested_fields_test() {
  let first = synthetic_first_data()
  let root =
    change.OptionalField(optional_field.FieldChange(
      [#(atom(30), atom_b(51))],
      [#(optional_field.Active, atom_b(4))],
      Some(optional_field.Replacement(
        True,
        Some(optional_field.Detached(atom_b(50))),
        atom(31),
      )),
    ))
  let data =
    change.ChangeData(
      ..first,
      max_local_id: 51,
      revisions: [
        change.RevisionInfo(revision_a(), None),
        change.RevisionInfo(revision_b(), None),
      ],
      fields: [#("root", root)],
    )
  let assert Ok(authored) = change.from_data(data)
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(None, None, authored))
  forest.delta_data(delta)
  |> expect.to_equal(
    forest.DeltaData(
      latest_revision: None,
      fields: [
        #(
          "root",
          forest.FieldDelta([
            forest.Mark(1, Some(atom_b(50)), None, [
              #(
                "nested-required",
                forest.FieldDelta([
                  forest.Mark(1, Some(atom(40)), Some(atom(41)), []),
                ]),
              ),
              #(
                "pruned-optional",
                forest.FieldDelta([forest.Mark(1, None, None, [])]),
              ),
            ]),
          ]),
        ),
      ],
      build: [forest.Build(atom(20), [StringValue("built")])],
      refreshers: [forest.Build(atom_b(21), [StringValue("stale")])],
      global: [],
      rename: [forest.Rename(atom(30), atom_b(51), 1)],
      destroy: [],
    ),
  )
}

pub fn shared_tree_change_additive_nested_delta_application_is_atomic_test() {
  let initial = initial_forest()
  let assert Ok(before) = forest.export_data(initial)
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        latest_revision: Some(revision_a()),
        fields: [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, Some(atom(30)), None, [
                #("point", forest.FieldDelta([])),
              ]),
            ]),
          ),
        ],
        build: [],
        refreshers: [],
        global: [],
        rename: [],
        destroy: [],
      ),
    )
  forest.apply_delta(initial, delta)
  |> expect.to_equal(
    Error(CorruptData(
      "rootFieldKey",
      "attach-only mark cannot change an old child",
    )),
  )
  forest.export_data(initial) |> expect.to_equal(Ok(before))
}
