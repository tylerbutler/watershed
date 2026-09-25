import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{
  type AtomId, type Edit, type TreeError, type TreeValue, AtomId, InvalidEdit,
  MapDelete, MapSet, MapValue, NumberValue, ObjectValue, StringValue,
}
import watershed/tree_kernel

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const root_type = "org.watershed.shared-tree.m2.Root"

const m2_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m2.DynamicMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\"]}}},\"org.watershed.shared-tree.m2.Root\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Root\"]}}"

type InvalidMapCase {
  InvalidMapCase(
    state: fn() -> #(schema.StoredSchema, forest.Forest, tree_kernel.TreeState),
    edit: Edit,
    error: TreeError,
    detached: Bool,
  )
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn authored_revision() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-0000000000a0")
}

fn view_revision() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-000000000001")
}

fn setup_revision() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-0000000000b0")
}

fn inverse_revision() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-0000000000c0")
}

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000002")
  id
}

fn identity_order() -> change.IdentityOrder {
  let assert Ok(order) = change.identity_order([#(authored_revision(), 0)])
  order
}

fn atomic_identity_order() -> change.IdentityOrder {
  let assert Ok(order) =
    change.identity_order([
      #(setup_revision(), 0),
      #(authored_revision(), 1),
      #(inverse_revision(), 2),
    ])
  order
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(m2_schema)
  stored
}

fn root_map_forest() -> forest.Forest {
  let root = MapValue(map_type, [#("key", StringValue("old"))])
  let assert Ok(state) =
    forest.new(view_revision(), stored_schema(), Some(root))
  state
}

fn object_map_forest() -> forest.Forest {
  let root =
    ObjectValue(root_type, [
      #(
        "items",
        MapValue(map_type, [
          #("key", StringValue("old")),
          #(
            "nested",
            MapValue(map_type, [#("inside", StringValue("retained"))]),
          ),
        ]),
      ),
    ])
  let assert Ok(state) =
    forest.new(view_revision(), stored_schema(), Some(root))
  state
}

fn authored(state: forest.Forest, operation: Edit) -> change.ChangeData {
  change.to_data(authored_change(state, operation))
}

fn authored_change(state: forest.Forest, operation: Edit) -> change.Changeset {
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      authored_revision(),
      operation,
      identity_order(),
    )
  authored
}

fn atom(local_id: Int) -> AtomId {
  AtomId(Some(authored_revision()), local_id)
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

fn object_map_change(
  field: String,
  field_change: change.FieldChange,
  max_local_id: Int,
  builds: List(forest.Build),
) -> change.ChangeData {
  change.ChangeData(
    ..empty_data(),
    max_local_id: max_local_id,
    revisions: [change.RevisionInfo(authored_revision(), None)],
    fields: [#("rootFieldKey", change.GenericField([#(0, atom(max_local_id))]))],
    nodes: [
      #(atom(max_local_id - 1), change.NodeChange([#(field, field_change)])),
      #(
        atom(max_local_id),
        change.NodeChange([
          #("items", change.GenericField([#(0, atom(max_local_id - 1))])),
        ]),
      ),
    ],
    parents: [
      #(
        atom(max_local_id - 1),
        change.ParentField(Some(atom(max_local_id)), "items"),
      ),
      #(atom(max_local_id), change.ParentField(None, "rootFieldKey")),
    ],
    builds: builds,
  )
}

pub fn shared_tree_map_change_sets_absent_entry_test() {
  authored(object_map_forest(), MapSet(["items"], "new", StringValue("value")))
  |> expect.to_equal(
    object_map_change(
      "new",
      change.OptionalField(optional_field.set(True, atom(1), atom(0))),
      3,
      [forest.Build(atom(1), [StringValue("value")])],
    ),
  )
}

pub fn shared_tree_map_change_replaces_present_entry_test() {
  authored(object_map_forest(), MapSet(["items"], "key", StringValue("value")))
  |> expect.to_equal(
    object_map_change(
      "key",
      change.OptionalField(optional_field.set(False, atom(1), atom(0))),
      3,
      [forest.Build(atom(1), [StringValue("value")])],
    ),
  )
}

pub fn shared_tree_map_change_deletes_present_entry_test() {
  authored(object_map_forest(), MapDelete(["items"], "key"))
  |> expect.to_equal(
    object_map_change(
      "key",
      change.OptionalField(optional_field.clear(False, atom(0))),
      2,
      [],
    ),
  )
}

pub fn shared_tree_map_change_deletes_absent_entry_test() {
  authored(object_map_forest(), MapDelete(["items"], "missing"))
  |> expect.to_equal(
    object_map_change(
      "missing",
      change.OptionalField(optional_field.clear(True, atom(0))),
      2,
      [],
    ),
  )
}

pub fn shared_tree_map_change_wraps_root_map_entry_test() {
  authored(root_map_forest(), MapSet([], "root-key", StringValue("value")))
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 2,
      revisions: [change.RevisionInfo(authored_revision(), None)],
      fields: [#("rootFieldKey", change.GenericField([#(0, atom(2))]))],
      nodes: [
        #(
          atom(2),
          change.NodeChange([
            #(
              "root-key",
              change.OptionalField(optional_field.set(True, atom(1), atom(0))),
            ),
          ]),
        ),
      ],
      parents: [#(atom(2), change.ParentField(None, "rootFieldKey"))],
      builds: [forest.Build(atom(1), [StringValue("value")])],
    ),
  )
}

pub fn shared_tree_map_change_sets_nested_map_entry_test() {
  authored(
    object_map_forest(),
    MapSet(["items", "nested"], "after", StringValue("value")),
  )
  |> expect.to_equal(
    change.ChangeData(
      ..empty_data(),
      max_local_id: 4,
      revisions: [change.RevisionInfo(authored_revision(), None)],
      fields: [#("rootFieldKey", change.GenericField([#(0, atom(4))]))],
      nodes: [
        #(
          atom(2),
          change.NodeChange([
            #(
              "after",
              change.OptionalField(optional_field.set(True, atom(1), atom(0))),
            ),
          ]),
        ),
        #(
          atom(3),
          change.NodeChange([
            #("nested", change.GenericField([#(0, atom(2))])),
          ]),
        ),
        #(
          atom(4),
          change.NodeChange([
            #("items", change.GenericField([#(0, atom(3))])),
          ]),
        ),
      ],
      parents: [
        #(atom(2), change.ParentField(Some(atom(3)), "nested")),
        #(atom(3), change.ParentField(Some(atom(4)), "items")),
        #(atom(4), change.ParentField(None, "rootFieldKey")),
      ],
      builds: [forest.Build(atom(1), [StringValue("value")])],
    ),
  )
}

pub fn shared_tree_map_invalid_edits_are_atomic_test() {
  assert_invalid_map_edits_are_atomic()
}

pub fn shared_tree_map_change_repairs_replaced_and_deleted_entries_test() {
  [
    #(MapSet(["items"], "key", StringValue("new")), StringValue("old")),
    #(
      MapDelete(["items"], "nested"),
      MapValue(map_type, [#("inside", StringValue("retained"))]),
    ),
  ]
  |> list.each(fn(entry) {
    let authored = authored_change(object_map_forest(), entry.0)
    let assert Ok(authored) =
      change.from_data(change.to_data(authored), atomic_identity_order())
    let assert Ok(inverted) =
      change.invert(
        change.TaggedChange(Some(authored_revision()), None, authored),
        False,
        inverse_revision(),
      )
    let assert Ok(roots) = change.relevant_removed_roots(inverted)
    roots |> expect.to_equal([atom(0)])
    let repair = forest.Build(atom(0), [entry.1])
    let assert Ok(refreshed) =
      change.update_refreshers(inverted, roots, [repair])
    change.to_data(refreshed).refreshers
    |> expect.to_equal([repair])
  })
}

fn assert_invalid_map_edits_are_atomic() {
  let following = MapSet(["items"], "after-invalid", StringValue("accepted"))
  [
    InvalidMapCase(
      object_map_state,
      MapSet([], "bad", StringValue("value")),
      InvalidEdit([], "node is not a map"),
      False,
    ),
    InvalidMapCase(
      object_map_state,
      MapSet(["items", "key"], "bad", StringValue("value")),
      InvalidEdit(["items", "key"], "node is not a map"),
      False,
    ),
    InvalidMapCase(
      object_map_state,
      MapDelete(["items", "missing"], "bad"),
      InvalidEdit(["items", "missing"], "field is absent"),
      False,
    ),
    InvalidMapCase(
      object_map_state,
      MapSet(["items"], "bad", NumberValue(1.0)),
      InvalidEdit(
        ["bad"],
        "node type is not allowed: com.fluidframework.leaf.number",
      ),
      False,
    ),
    InvalidMapCase(
      object_map_state,
      MapSet(
        ["items"],
        "bad",
        MapValue(map_type, [#("nested", ObjectValue("Missing", []))]),
      ),
      InvalidEdit(["bad", "nested"], "node type is not allowed: Missing"),
      False,
    ),
    InvalidMapCase(
      detached_map_state,
      MapSet(["items", "nested"], "bad", StringValue("value")),
      InvalidEdit(["items", "nested"], "field is absent"),
      True,
    ),
  ]
  |> list.each(fn(test_case) {
    let InvalidMapCase(build, edit, error, detached) = test_case
    let #(stored, visible, attempted_state) = build()
    let #(_, _, control_state) = build()
    let assert Ok(before_snapshot) = tree_kernel.snapshot(attempted_state)
    let before_parts = tree_kernel.snapshot_parts(before_snapshot)
    let before_history = tree_kernel.history_view(attempted_state)
    let assert Ok(before_visible) = tree_kernel.visible_data(attempted_state)
    case detached {
      True -> list.is_empty(before_visible.detached) |> expect.to_be_false
      False -> Nil
    }

    change.validate_edit(stored, visible, edit)
    |> expect.to_equal(Error(error))
    tree_kernel.validate_edit(attempted_state, edit)
    |> expect.to_equal(Error(error))
    tree_kernel.apply_local(
      attempted_state,
      authored_revision(),
      atomic_identity_order(),
      edit,
    )
    |> expect.to_equal(Error(error))

    let assert Ok(after_snapshot) = tree_kernel.snapshot(attempted_state)
    after_snapshot |> expect.to_equal(before_snapshot)
    tree_kernel.snapshot_parts(after_snapshot)
    |> expect.to_equal(before_parts)
    tree_kernel.history_view(attempted_state)
    |> expect.to_equal(before_history)
    tree_kernel.visible_data(attempted_state)
    |> expect.to_equal(Ok(before_visible))

    let assert Ok(#(after_attempt, attempted_commit, attempted_events)) =
      tree_kernel.apply_local(
        attempted_state,
        authored_revision(),
        atomic_identity_order(),
        following,
      )
    let assert Ok(#(after_control, control_commit, control_events)) =
      tree_kernel.apply_local(
        control_state,
        authored_revision(),
        atomic_identity_order(),
        following,
      )
    change.to_data(attempted_commit.change)
    |> expect.to_equal(change.to_data(control_commit.change))
    let assert Ok(attempted_snapshot) = tree_kernel.snapshot(after_attempt)
    let assert Ok(control_snapshot) = tree_kernel.snapshot(after_control)
    attempted_snapshot |> expect.to_equal(control_snapshot)
    tree_kernel.visible_data(after_attempt)
    |> expect.to_equal(tree_kernel.visible_data(after_control))
    attempted_events |> expect.to_equal(control_events)
  })
}

fn object_map_state() -> #(
  schema.StoredSchema,
  forest.Forest,
  tree_kernel.TreeState,
) {
  state_from(m2_schema, object_map_root())
}

fn detached_map_state() -> #(
  schema.StoredSchema,
  forest.Forest,
  tree_kernel.TreeState,
) {
  let #(_, _, initial) = object_map_state()
  let assert Ok(#(detached, _, _)) =
    tree_kernel.apply_local(
      initial,
      setup_revision(),
      atomic_identity_order(),
      MapDelete(["items"], "nested"),
    )
  let assert Ok(data) = tree_kernel.visible_data(detached)
  let stored = stored_schema()
  let assert Ok(visible) = forest.import_data(view_revision(), stored, data)
  #(stored, visible, detached)
}

fn state_from(
  raw_schema: String,
  root: TreeValue,
) -> #(schema.StoredSchema, forest.Forest, tree_kernel.TreeState) {
  let assert Ok(stored) = schema.stored_from_string(raw_schema)
  let assert Ok(view) = schema.view_from_string(raw_schema)
  let assert Ok(visible) = forest.new(view_revision(), stored, Some(root))
  let assert Ok(data) = forest.export_data(visible)
  let history_snapshot = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_revision(),
      stored,
      data,
      history_snapshot,
    )
  let assert Ok(state) =
    tree_kernel.restore(snapshot, view_revision(), session(), view)
  #(stored, visible, state)
}

fn object_map_root() -> TreeValue {
  ObjectValue(root_type, [
    #(
      "items",
      MapValue(map_type, [
        #("key", StringValue("old")),
        #("nested", MapValue(map_type, [#("inside", StringValue("retained"))])),
      ]),
    ),
  ])
}
