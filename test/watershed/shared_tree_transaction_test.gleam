import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/transaction_fixture
import watershed/tree/types
import watershed/wire

const items_type = "org.watershed.shared-tree.m3.Items"

const point_type = "org.watershed.shared-tree.m3.Point"

fn transaction_revision() -> fluid_ids.StableId {
  let assert Ok(revision) =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000001")
  revision
}

fn constraint_forest(view: fluid_ids.StableId) -> forest.Forest {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.ObjectValue(point_type, [
            #("label", types.StringValue("point")),
            #("x", types.NumberValue(1.0)),
          ]),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #(
        "byKey",
        types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [
          #("item", types.StringValue("value")),
        ]),
      ),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(state) =
    forest.new(view, array_fixture.stored("objectArrays"), Some(root))
  state
}

fn apply_constraint_edit(
  state: forest.Forest,
  operation: types.Edit,
) -> Result(forest.Forest, types.TreeError) {
  let revision = transaction_revision()
  use order <- result.try(change.identity_order([#(revision, 0)]))
  use authored <- result.try(change.edit(
    array_fixture.stored("objectArrays"),
    state,
    revision,
    operation,
    order,
  ))
  use delta <- result.try(
    change.into_delta(change.TaggedChange(Some(revision), None, authored)),
  )
  forest.apply_delta(state, delta)
}

pub fn shared_tree_constraint_resolves_attached_node_kinds_test() -> Nil {
  let state = constraint_forest(array_fixture.view_id())
  [
    [],
    ["byKey"],
    ["left", "0"],
  ]
  |> list.each(fn(path) {
    let assert Ok(reference) = forest.locate(state, path)
    let assert Ok(change.ConstraintTarget(resolved, resolved_path)) =
      change.resolve_constraint(state, path)
    resolved |> expect.to_equal(reference)
    resolved_path |> expect.to_equal(path)
  })
}

pub fn shared_tree_constraint_resolution_preserves_moved_identity_test() -> Nil {
  let initial = constraint_forest(array_fixture.view_id())
  let assert Ok(reference) = forest.locate(initial, ["left", "0"])
  let assert Ok(moved) =
    apply_constraint_edit(
      initial,
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
    )
  let assert Ok(change.ConstraintTarget(resolved, path)) =
    change.resolve_constraint(moved, ["right", "0"])
  resolved |> expect.to_equal(reference)
  path |> expect.to_equal(["right", "0"])
}

pub fn shared_tree_constraint_rejects_invalid_targets_test() -> Nil {
  let initial = constraint_forest(array_fixture.view_id())
  let assert Error(types.InvalidEdit(_, _)) =
    change.resolve_constraint(initial, ["missing"])
  let assert Ok(target) = change.resolve_constraint(initial, ["left", "0"])
  let assert Ok(removed) =
    apply_constraint_edit(initial, types.ArrayRemove(["left"], 0, 1))
  let assert Error(types.InvalidEdit(_, _)) =
    change.add_node_exists_constraints(change.empty(), removed, [target])

  let other_view =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000002")
    |> result.unwrap(transaction_revision())
  let other = constraint_forest(other_view)
  let assert Error(types.InvalidEdit(_, _)) =
    change.add_node_exists_constraints(change.empty(), other, [target])
  Nil
}

pub fn shared_tree_constraint_duplicate_targets_collapse_test() -> Nil {
  let state = constraint_forest(array_fixture.view_id())
  let assert Ok(target) = change.resolve_constraint(state, ["left", "0"])
  let assert Ok(constrained) =
    change.add_node_exists_constraints(change.empty(), state, [target, target])
  let data = change.to_data(constrained)
  data.constraint_violation_count |> expect.to_equal(0)
  data.nodes
  |> list.filter(fn(entry) {
    entry.1.node_exists_constraint == Some(change.NodeExistsConstraint(False))
  })
  |> list.length
  |> expect.to_equal(1)
}

pub fn shared_tree_transaction_wire_requires_input_sections_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))

  ["messageBytes", "compressor", "context", "operands", "scenarios"]
  |> list.each(fn(key) {
    let changed =
      root
      |> list.filter(fn(entry) { entry.0 != key })
      |> VObject
      |> json_ot.to_json
    let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_transaction_wire_rejects_unknown_context_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(context)) = list.key_find(root, "context")
  let changed =
    root
    |> list.key_set(
      "context",
      VObject(list.key_set(context, "minVersionForCollab", VString("unknown"))),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_rejects_malformed_compressor_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(compressors)) = list.key_find(root, "compressor")
  let assert Ok(VObject(nonviolated)) =
    list.key_find(compressors, "nonviolated")
  let changed =
    root
    |> list.key_set(
      "compressor",
      VObject(list.key_set(
        compressors,
        "nonviolated",
        VObject(list.key_set(nonviolated, "serialized", VString("invalid"))),
      )),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_observes_constraints_and_encoder_output_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(VString(nonviolated_bytes)) =
    list.key_find(message_bytes, "nonviolated")
  let assert Ok(VString(violated_bytes)) =
    list.key_find(message_bytes, "violated")
  let assert Ok(nonviolated_message) = normalize_message(nonviolated_bytes)
  let assert Ok(violated_message) = normalize_message(violated_bytes)

  let original = case transaction_fixture.run_wire(input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(original)
  let assert Ok(nonviolated) = list.key_find(observation, "nonviolated")
  let assert Ok(violated) = list.key_find(observation, "violated")
  let assert Ok(VObject(encoded_messages)) =
    list.key_find(observation, "message")
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(encoded_nonviolated_message) =
    list.key_find(encoded_messages, "nonviolated")
  let assert Ok(encoded_violated_message) =
    list.key_find(encoded_messages, "violated")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  let assert Ok(VString(encoded_violated)) =
    list.key_find(encoded_bytes, "violated")
  nonviolated
  |> expect.to_equal(
    VObject([
      #("constraints", VArray([VObject([#("violated", json_ot.VBool(False))])])),
      #("violations", json_ot.VNumber(json_ot.NInt(0))),
    ]),
  )
  violated
  |> expect.to_equal(
    VObject([
      #("constraints", VArray([VObject([#("violated", json_ot.VBool(True))])])),
      #("violations", json_ot.VNumber(json_ot.NInt(1))),
    ]),
  )
  wire.json_semantically_equal(
    json_ot.to_json(encoded_nonviolated_message),
    json_ot.to_json(nonviolated_message),
  )
  |> expect.to_be_true
  wire.json_semantically_equal(
    json_ot.to_json(encoded_violated_message),
    json_ot.to_json(violated_message),
  )
  |> expect.to_be_true
  let assert Ok(encoded_nonviolated_value) =
    json_ot.parse_json(encoded_nonviolated)
  let assert Ok(encoded_violated_value) = json_ot.parse_json(encoded_violated)
  encoded_nonviolated_value |> expect.to_equal(encoded_nonviolated_message)
  encoded_violated_value |> expect.to_equal(encoded_violated_message)
}

pub fn shared_tree_transaction_wire_rejects_noncanonical_bytes_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(VString(nonviolated_bytes)) =
    list.key_find(message_bytes, "nonviolated")
  let assert Ok(expected_message) = normalize_message(nonviolated_bytes)
  let changed_bytes =
    nonviolated_bytes
    |> string.replace("{\"revision\":4", "{ \"revision\":4")
  let changed =
    root
    |> list.key_set(
      "messageBytes",
      VObject(list.key_set(message_bytes, "nonviolated", VString(changed_bytes))),
    )
    |> VObject
    |> json_ot.to_json

  let encoded = case transaction_fixture.run_wire(changed) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(encoded)
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  let is_echo = encoded_nonviolated == changed_bytes
  is_echo |> expect.to_be_false
  let assert Ok(encoded_message) = json_ot.parse_json(encoded_nonviolated)
  wire.json_semantically_equal(
    json_ot.to_json(encoded_message),
    json_ot.to_json(expected_message),
  )
  |> expect.to_be_true
}

pub fn shared_tree_transaction_wire_observes_independent_input_mutations_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(original) = transaction_fixture.run_wire(input)

  [
    #(
      "nonviolated constraint flag",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"violated\":false",
        "\"violated\":true",
      ),
    ),
    #(
      "violated count",
      replace_nested_string(
        input,
        "messageBytes",
        "violated",
        "\"violations\":1",
        "\"violations\":0",
      ),
    ),
    #(
      "compressor session",
      replace_input(
        input,
        "989422b1-6ee8-49b7-bb0c-b27c95030135",
        "989422b1-6ee8-49b7-bb0c-b27c95030136",
      ),
    ),
    #(
      "modular version",
      replace_nested_integer(input, "context", "modularChange", 5, 4),
    ),
    #(
      "message byte",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"revision\":4",
        "\"revision\":3",
      ),
    ),
  ]
  |> list.each(fn(mutation) {
    case transaction_fixture.run_wire(mutation.1) {
      Error(_) -> Nil
      Ok(observation) ->
        case observation == original {
          False -> Nil
          True -> panic as { mutation.0 <> " mutation was not observed" }
        }
    }
  })
}

fn wire_observation(value: json.Json) -> Result(json_ot.JsonValue, Nil) {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([observation])) = list.key_find(root, "observations")
  Ok(observation)
}

fn normalize_message(bytes: String) -> Result(JsonValue, Nil) {
  let assert Ok(VObject(root)) = json_ot.parse_json(bytes)
  let assert Ok(VArray([VObject(change)])) = list.key_find(root, "changeset")
  let assert Ok(VObject(data)) = list.key_find(change, "data")
  let data =
    data
    |> list.filter(fn(member) {
      member.0 != "builds" && member.0 != "refreshers"
    })
    |> VObject
  let change = change |> list.key_set("data", data) |> VObject
  Ok(VObject(list.key_set(root, "changeset", VArray([change]))))
}

fn replace_nested_string(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: String,
  after: String,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(VString(value)) = list.key_find(parent, child_key)
  let changed = string.replace(value, before, after)
  expect.to_be_false(changed == value)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(parent, child_key, VString(changed))),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_nested_integer(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: Int,
  after: Int,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(json_ot.VNumber(json_ot.NInt(value))) =
    list.key_find(parent, child_key)
  value |> expect.to_equal(before)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(
      parent,
      child_key,
      json_ot.VNumber(json_ot.NInt(after)),
    )),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_input(input: json.Json, before: String, after: String) -> json.Json {
  let raw = json.to_string(input)
  let changed = string.replace(raw, before, after)
  expect.to_be_false(changed == raw)
  let assert Ok(value) = json_ot.parse_json(changed)
  json_ot.to_json(value)
}
