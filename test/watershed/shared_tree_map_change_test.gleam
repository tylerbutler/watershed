import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{
  type AtomId, type Edit, AtomId, MapDelete, MapSet, MapValue, ObjectValue,
  StringValue,
}

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const root_type = "org.watershed.shared-tree.m2.Root"

const m2_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m2.DynamicMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\"]}}},\"org.watershed.shared-tree.m2.Root\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Root\"]}}"

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

fn identity_order() -> change.IdentityOrder {
  let assert Ok(order) = change.identity_order([#(authored_revision(), 0)])
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
          #("nested", MapValue(map_type, [])),
        ]),
      ),
    ])
  let assert Ok(state) =
    forest.new(view_revision(), stored_schema(), Some(root))
  state
}

fn authored(state: forest.Forest, operation: Edit) -> change.ChangeData {
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      authored_revision(),
      operation,
      identity_order(),
    )
  change.to_data(authored)
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
