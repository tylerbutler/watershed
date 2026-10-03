import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VBool, VNull, VObject, VString}
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"Point\"]}}}},\"NamedMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"Point\"]}}},\"Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"featured\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"byKey\":{\"kind\":\"Value\",\"types\":[\"NamedMap\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const selected_fields = [
  "object-set",
  "map-set",
  "array-insert",
  "same-array-move",
  "outer-transaction",
]

pub fn run(name: String, input: Json) -> Result(Json, String) {
  case name {
    "undo-redo-fields" -> run_fields(input)
    "undo-redo-kinds" -> run_kinds(input)
    "revertible-lifetime" -> run_lifetime(input)
    "undo-redo-constraints" -> run_constraints(input)
    _ -> Error("unsupported undo fixture " <> name)
  }
}

pub fn projection(name: String, expected: Json) -> Result(Json, String) {
  case name {
    "undo-redo-fields" -> project_fields(expected)
    "undo-redo-kinds" -> project_kinds(expected)
    "revertible-lifetime" -> project_lifetime(expected)
    "undo-redo-constraints" -> project_constraints(expected)
    _ -> Error("unsupported undo fixture " <> name)
  }
}

fn run_fields(input: Json) -> Result(Json, String) {
  use scenarios <- result.try(input_scenarios(input))
  use selected <- result.try(
    list.try_map(
      list.filter(scenarios, fn(scenario) {
        list.contains(selected_fields, scenario.0)
      }),
      fn(scenario) { run_field(scenario.0, scenario.1) },
    ),
  )
  use _ <- result.try(require(
    list.map(selected, fn(entry) { entry.0 }) == selected_fields,
    "undo field scenarios are missing or out of order",
  ))
  Ok(observation_json(list.map(selected, fn(entry) { entry.1 })))
}

fn run_field(id: String, operation: String) -> Result(#(String, Json), String) {
  use state <- result.try(initial_state())
  use before <- result.try(field_observation(id, state))
  use #(edited, commit) <- result.try(case operation {
    "object-set" ->
      apply_edit(
        state,
        revision("00000000-0000-4000-8000-000000000101"),
        types.SetField(["title"], types.StringValue("object-set")),
      )
    "map-set" ->
      apply_edit(
        state,
        revision("00000000-0000-4000-8000-000000000102"),
        types.MapSet(["byKey"], "new", point("map", 4.0, "map-id")),
      )
    "array-insert" ->
      apply_edit(
        state,
        revision("00000000-0000-4000-8000-000000000103"),
        types.ArrayInsert(["left"], 2, [point("inserted", 5.0, "inserted-id")]),
      )
    "same-array-move" ->
      apply_edit(
        state,
        revision("00000000-0000-4000-8000-000000000104"),
        types.ArrayMove(["left"], 0, 1, ["left"], 2),
      )
    "outer-transaction" -> apply_transaction(state)
    _ -> Error("unsupported undo field operation " <> operation)
  })
  use edited_value <- result.try(field_observation(id, edited))
  use #(retained, handle) <- result.try(
    native(tree_kernel.retain_revertible(
      edited,
      commit.revision,
      types.DefaultCommit,
    )),
  )
  let inverse_revision = revision("00000000-0000-4000-8000-00000000010f")
  use order <- result.try(native(order_for(retained, [inverse_revision])))
  use #(undone, _, kind, _) <- result.try(
    native(tree_kernel.revert(retained, handle, inverse_revision, order)),
  )
  use undo <- result.try(field_observation(id, undone))
  Ok(#(
    id,
    json.object([
      #("id", json.string(id)),
      #("before", before),
      #("edited", edited_value),
      #("undo", undo),
      #("status", json.bool(tree_kernel.revertible_is_valid(undone, handle))),
      #(
        "kinds",
        json.array(
          [json.string("Default"), json.string(kind_name(kind))],
          fn(value) { value },
        ),
      ),
    ]),
  ))
}

fn apply_transaction(
  state: tree_kernel.TreeState,
) -> Result(#(tree_kernel.TreeState, history.Commit), String) {
  use open <- result.try(
    native(transaction.begin(state, fluid_ids.new(session()), [])),
  )
  use open <- result.try(
    native(transaction.apply_edit(
      open,
      types.SetField(["title"], types.StringValue("transaction")),
    )),
  )
  use open <- result.try(
    native(transaction.apply_edit(
      open,
      types.SetField(["count"], types.NumberValue(2.0)),
    )),
  )
  use open <- result.try(
    native(transaction.apply_edit(
      open,
      types.ArrayInsert(["left"], 2, [types.StringValue("transaction-item")]),
    )),
  )
  use #(finish, _) <- result.try(native(transaction.finish(open)))
  case finish {
    transaction.Commit(state, _, commit) -> Ok(#(state, commit))
    transaction.NoCommit(_, _) -> Error("undo transaction produced no commit")
  }
}

fn run_kinds(input: Json) -> Result(Json, String) {
  use value <- result.try(parse(input))
  use sequence <- result.try(string_list(field(value, "sequence")))
  use _ <- result.try(require(
    sequence == ["Default", "Undo", "Redo"],
    "unsupported undo kind sequence",
  ))
  use state <- result.try(initial_state())
  let target_revision = revision("00000000-0000-4000-8000-000000000201")
  let undo_revision = revision("00000000-0000-4000-8000-000000000202")
  let redo_revision = revision("00000000-0000-4000-8000-000000000203")
  use #(edited, target) <- result.try(apply_edit(
    state,
    target_revision,
    types.SetField(["title"], types.StringValue("changed")),
  ))
  use #(retained, target_handle) <- result.try(
    native(tree_kernel.retain_revertible(
      edited,
      target.revision,
      types.DefaultCommit,
    )),
  )
  use order <- result.try(
    native(order_for(retained, [undo_revision, redo_revision])),
  )
  use #(undone, undo, undo_kind, _) <- result.try(
    native(tree_kernel.revert(retained, target_handle, undo_revision, order)),
  )
  use #(retained, undo_handle) <- result.try(
    native(tree_kernel.retain_revertible(
      undone,
      undo.revision,
      types.UndoCommit,
    )),
  )
  use #(redone, _, redo_kind, _) <- result.try(
    native(tree_kernel.revert(retained, undo_handle, redo_revision, order)),
  )
  use title <- result.try(text_at(redone, ["title"]))
  Ok(
    observation_json([
      json.object([
        #("id", json.string("kind-sequence")),
        #(
          "kinds",
          json.array(
            [
              json.string("Default"),
              json.string(kind_name(undo_kind)),
              json.string(kind_name(redo_kind)),
            ],
            fn(value) { value },
          ),
        ),
        #("title", json.string(title)),
      ]),
    ]),
  )
}

fn run_lifetime(input: Json) -> Result(Json, String) {
  use value <- result.try(parse(input))
  use scenarios <- result.try(string_list(field(value, "scenarios")))
  use _ <- result.try(require(
    list.contains(scenarios, "retained-repeated-revert")
      && list.contains(scenarios, "disposed-errors"),
    "undo lifetime scenarios are missing",
  ))
  use state <- result.try(initial_state())
  let target_revision = revision("00000000-0000-4000-8000-000000000301")
  let first_inverse = revision("00000000-0000-4000-8000-000000000302")
  let second_inverse = revision("00000000-0000-4000-8000-000000000303")
  use #(edited, target) <- result.try(apply_edit(
    state,
    target_revision,
    types.SetField(["title"], types.StringValue("changed")),
  ))
  use #(retained, handle) <- result.try(
    native(tree_kernel.retain_revertible(
      edited,
      target.revision,
      types.DefaultCommit,
    )),
  )
  let before = tree_kernel.revertible_is_valid(retained, handle)
  use order <- result.try(
    native(order_for(retained, [first_inverse, second_inverse])),
  )
  use #(first, _, _, _) <- result.try(
    native(tree_kernel.revert(retained, handle, first_inverse, order)),
  )
  let after_first = tree_kernel.revertible_is_valid(first, handle)
  use #(second, _, _, _) <- result.try(
    native(tree_kernel.revert(first, handle, second_inverse, order)),
  )
  let after_second = tree_kernel.revertible_is_valid(second, handle)
  use disposed <- result.try(
    native(tree_kernel.dispose_revertible(second, handle)),
  )
  let after_dispose = tree_kernel.revertible_is_valid(disposed, handle)
  let second_dispose_error = case
    tree_kernel.dispose_revertible(disposed, handle)
  {
    Error(_) -> True
    Ok(_) -> False
  }
  let disposed_revert_error = case
    tree_kernel.revert(disposed, handle, first_inverse, order)
  {
    Error(_) -> True
    Ok(_) -> False
  }
  use title <- result.try(text_at(disposed, ["title"]))
  Ok(
    observation_json([
      json.object([
        #("id", json.string("lifetime")),
        #("before", json.bool(before)),
        #("afterFirst", json.bool(after_first)),
        #("afterSecond", json.bool(after_second)),
        #("afterDispose", json.bool(after_dispose)),
        #("secondDisposeError", json.bool(second_dispose_error)),
        #("disposedRevertError", json.bool(disposed_revert_error)),
        #("title", json.string(title)),
      ]),
    ]),
  )
}

fn run_constraints(input: Json) -> Result(Json, String) {
  use scenarios <- result.try(input_scenarios(input))
  use selected <- result.try(
    list.try_map(
      list.filter(scenarios, fn(entry) {
        entry.0 == "constraint-satisfied" || entry.0 == "constraint-violated"
      }),
      fn(entry) { run_constraint(entry.0, entry.1) },
    ),
  )
  Ok(observation_json(selected))
}

fn run_constraint(id: String, required: String) -> Result(Json, String) {
  use state <- result.try(initial_state())
  use target <- result.try(
    native(tree_kernel.resolve_constraint(state, ["left", "0"])),
  )
  use open <- result.try(
    native(transaction.begin(state, fluid_ids.new(session()), [target])),
  )
  use open <- result.try(
    native(transaction.apply_edit(
      open,
      types.SetField(["left", "0", "x"], types.NumberValue(10.0)),
    )),
  )
  use #(finish, _) <- result.try(native(transaction.finish(open)))
  use #(edited, commit) <- result.try(case finish {
    transaction.Commit(state, _, commit) -> Ok(#(state, commit))
    transaction.NoCommit(_, _) ->
      Error("constraint transaction produced no commit")
  })
  use #(retained, handle) <- result.try(
    native(tree_kernel.retain_revertible(
      edited,
      commit.revision,
      types.DefaultCommit,
    )),
  )
  let later_revision = revision("00000000-0000-4000-8000-000000000401")
  use #(before_undo, _) <- result.try(case required {
    "present" ->
      apply_edit(
        retained,
        later_revision,
        types.ArrayInsert(["right"], 1, [types.StringValue("unrelated")]),
      )
    "removed" ->
      apply_edit(retained, later_revision, types.ArrayRemove(["left"], 0, 1))
    _ -> Error("unsupported required node state " <> required)
  })
  let inverse_revision = revision("00000000-0000-4000-8000-000000000402")
  use order <- result.try(native(order_for(before_undo, [inverse_revision])))
  use #(undone, _, kind, _) <- result.try(
    native(tree_kernel.revert(before_undo, handle, inverse_revision, order)),
  )
  use before <- result.try(constraint_value(before_undo, required))
  use after <- result.try(constraint_value(undone, required))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("before", before),
      #("undo", after),
      #("status", json.bool(tree_kernel.revertible_is_valid(undone, handle))),
      #("kind", json.string(kind_name(kind))),
    ]),
  )
}

fn project_fields(expected: Json) -> Result(Json, String) {
  use observations <- result.try(expected_observations(expected))
  use projected <- result.try(
    list.try_map(selected_fields, fn(id) {
      use observation <- result.try(find_observation(observations, id))
      use before <- result.try(field_projection(
        id,
        field(observation, "before"),
      ))
      use edited <- result.try(field_projection(
        id,
        field(observation, "edited"),
      ))
      use undo <- result.try(field_projection(
        id,
        field(observation, "optimisticUndo"),
      ))
      use status <- result.try(status_valid(field(observation, "status")))
      use kinds <- result.try(event_kinds(field(observation, "events")))
      Ok(
        json.object([
          #("id", json.string(id)),
          #("before", json_ot.to_json(before)),
          #("edited", json_ot.to_json(edited)),
          #("undo", json_ot.to_json(undo)),
          #("status", json.bool(status)),
          #(
            "kinds",
            json.array(list.map(kinds, json.string), fn(value) { value }),
          ),
        ]),
      )
    }),
  )
  Ok(observation_json(projected))
}

fn project_kinds(expected: Json) -> Result(Json, String) {
  use observations <- result.try(expected_observations(expected))
  use observation <- result.try(find_observation(observations, "kind-sequence"))
  use kinds <- result.try(event_kinds(field(observation, "events")))
  use snapshot <- result.try(object(field(observation, "snapshot")))
  use title <- result.try(text(field(snapshot, "title")))
  Ok(
    observation_json([
      json.object([
        #("id", json.string("kind-sequence")),
        #(
          "kinds",
          json.array(list.map(kinds, json.string), fn(value) { value }),
        ),
        #("title", json.string(title)),
      ]),
    ]),
  )
}

fn project_lifetime(expected: Json) -> Result(Json, String) {
  use observations <- result.try(expected_observations(expected))
  use observation <- result.try(find_observation(observations, "lifetime"))
  use status <- result.try(object(field(observation, "status")))
  use snapshot <- result.try(object(field(observation, "snapshot")))
  use title <- result.try(text(field(snapshot, "title")))
  Ok(
    observation_json([
      json.object([
        #("id", json.string("lifetime")),
        #(
          "before",
          json.bool(status_text(status, "beforeRepeatedRevert") == "Valid"),
        ),
        #(
          "afterFirst",
          json.bool(status_text(status, "afterFirstRepeatedRevert") == "Valid"),
        ),
        #(
          "afterSecond",
          json.bool(status_text(status, "afterSecondRepeatedRevert") == "Valid"),
        ),
        #(
          "afterDispose",
          json.bool(status_text(status, "afterDispose") == "Valid"),
        ),
        #(
          "secondDisposeError",
          json.bool(has_text(observation, "secondDisposeError")),
        ),
        #(
          "disposedRevertError",
          json.bool(has_text(observation, "disposedRevertError")),
        ),
        #("title", json.string(title)),
      ]),
    ]),
  )
}

fn project_constraints(expected: Json) -> Result(Json, String) {
  use observations <- result.try(expected_observations(expected))
  use projected <- result.try(
    list.try_map(["constraint-satisfied", "constraint-violated"], fn(id) {
      use observation <- result.try(find_observation(observations, id))
      use remove_target <- result.try(
        boolean(field(observation, "removeTarget")),
      )
      let required = case remove_target {
        True -> "removed"
        False -> "present"
      }
      use before <- result.try(constraint_snapshot(
        field(observation, "beforeUndo"),
        required,
      ))
      use undo <- result.try(constraint_snapshot(
        field(observation, "optimisticUndo"),
        required,
      ))
      use status <- result.try(status_valid(field(observation, "status")))
      use kinds <- result.try(event_kinds(field(observation, "events")))
      use kind <- result.try(
        list.last(kinds)
        |> result.map_error(fn(_) { "constraint event kind is missing" }),
      )
      Ok(
        json.object([
          #("id", json.string(id)),
          #("before", json_ot.to_json(before)),
          #("undo", json_ot.to_json(undo)),
          #("status", json.bool(status)),
          #("kind", json.string(kind)),
        ]),
      )
    }),
  )
  Ok(observation_json(projected))
}

fn field_projection(id: String, snapshot: Result(JsonValue, String)) {
  use snapshot <- result.try(snapshot)
  use root <- result.try(object(Ok(snapshot)))
  case id {
    "object-set" -> field(root, "title")
    "map-set" -> map_label(root, "new")
    "array-insert" | "same-array-move" -> array_labels(field(root, "left"))
    "outer-transaction" -> {
      use title <- result.try(field(root, "title"))
      use count <- result.try(field(root, "count"))
      use left <- result.try(array_labels(field(root, "left")))
      Ok(
        VObject([
          #("title", title),
          #("count", count),
          #("left", left),
        ]),
      )
    }
    _ -> Error("unsupported field projection " <> id)
  }
}

fn field_observation(
  id: String,
  state: tree_kernel.TreeState,
) -> Result(Json, String) {
  case id {
    "object-set" -> text_at(state, ["title"]) |> result.map(json.string)
    "map-set" -> {
      use value <- result.try(
        native(tree_kernel.map_get(state, ["byKey"], "new")),
      )
      case value {
        None -> Ok(json.null())
        Some(value) -> point_label(value) |> result.map(json.string)
      }
    }
    "array-insert" | "same-array-move" ->
      labels_at(state, ["left"])
      |> result.map(fn(labels) {
        json.array(list.map(labels, json.string), fn(value) { value })
      })
    "outer-transaction" -> {
      use title <- result.try(text_at(state, ["title"]))
      use count <- result.try(number_at(state, ["count"]))
      use left <- result.try(labels_at(state, ["left"]))
      Ok(
        json.object([
          #("title", json.string(title)),
          #("count", json.float(count)),
          #(
            "left",
            json.array(list.map(left, json.string), fn(value) { value }),
          ),
        ]),
      )
    }
    _ -> Error("unsupported field observation " <> id)
  }
}

fn constraint_value(
  state: tree_kernel.TreeState,
  required: String,
) -> Result(Json, String) {
  case required {
    "present" -> {
      use x <- result.try(number_at(state, ["left", "0", "x"]))
      use right <- result.try(labels_at(state, ["right"]))
      Ok(
        json.object([
          #("x", json.float(x)),
          #(
            "right",
            json.array(list.map(right, json.string), fn(value) { value }),
          ),
        ]),
      )
    }
    "removed" ->
      labels_at(state, ["left"])
      |> result.map(fn(left) {
        json.array(list.map(left, json.string), fn(value) { value })
      })
    _ -> Error("unsupported constraint observation")
  }
}

fn constraint_snapshot(
  snapshot: Result(JsonValue, String),
  required: String,
) -> Result(JsonValue, String) {
  use snapshot <- result.try(snapshot)
  use root <- result.try(object(Ok(snapshot)))
  case required {
    "present" -> {
      use left <- result.try(array(field(root, "left")))
      use first <- result.try(
        list.first(left)
        |> result.map_error(fn(_) { "constraint point is missing" }),
      )
      use first <- result.try(object(Ok(first)))
      use x <- result.try(field(first, "x"))
      use right <- result.try(array_labels(field(root, "right")))
      Ok(VObject([#("x", x), #("right", right)]))
    }
    "removed" -> array_labels(field(root, "left"))
    _ -> Error("unsupported constraint snapshot")
  }
}

fn initial_state() -> Result(tree_kernel.TreeState, String) {
  use stored <- result.try(native(schema.stored_from_string(tree_schema)))
  use view <- result.try(native(schema.view_from_string(tree_schema)))
  let initial = history.inspect(history.new(session())).sequenced
  use snapshot <- result.try(
    native(tree_kernel.snapshot_from_parts(
      revision("00000000-0000-4000-8000-000000000001"),
      stored,
      forest.ForestData(Some(initial_root()), [], 0),
      initial,
    )),
  )
  native(tree_kernel.restore(
    snapshot,
    revision("00000000-0000-4000-8000-000000000001"),
    session(),
    view,
  ))
}

fn initial_root() -> types.TreeValue {
  types.ObjectValue("Root", [
    #("title", types.StringValue("base")),
    #("note", types.StringValue("seed")),
    #("count", types.NumberValue(0.0)),
    #("featured", point("featured", 0.0, "featured-id")),
    #(
      "left",
      types.ArrayValue("Items", [
        point("left-a", 1.0, "left-a-id"),
        point("left-b", 2.0, "left-b-id"),
      ]),
    ),
    #("right", types.ArrayValue("Items", [point("right-a", 3.0, "right-a-id")])),
    #(
      "byKey",
      types.MapValue("NamedMap", [#("seed", types.StringValue("value"))]),
    ),
  ])
}

fn point(label: String, x: Float, id: String) -> types.TreeValue {
  types.ObjectValue("Point", [
    #("id", types.StringValue(id)),
    #("label", types.StringValue(label)),
    #("x", types.NumberValue(x)),
  ])
}

fn apply_edit(
  state: tree_kernel.TreeState,
  revision: fluid_ids.StableId,
  edit: types.Edit,
) -> Result(#(tree_kernel.TreeState, history.Commit), String) {
  use order <- result.try(native(order_for(state, [revision])))
  use #(state, commit, _) <- result.try(
    native(tree_kernel.apply_local(state, revision, order, edit)),
  )
  Ok(#(state, commit))
}

fn order_for(
  state: tree_kernel.TreeState,
  added: List(fluid_ids.StableId),
) -> Result(change.IdentityOrder, types.TreeError) {
  let revisions =
    list.append(tree_kernel.identity_revisions(state), added) |> list.unique
  let offset = 0 - list.length(revisions)
  change.identity_order(
    list.index_map(revisions, fn(revision, index) {
      #(revision, offset + index)
    }),
  )
}

fn labels_at(
  state: tree_kernel.TreeState,
  path: types.FieldPath,
) -> Result(List(String), String) {
  use values <- result.try(native(tree_kernel.array_values(state, path)))
  list.try_map(values, fn(value) {
    case value {
      types.StringValue(value) -> Ok(value)
      value -> point_label(value)
    }
  })
}

fn point_label(value: types.TreeValue) -> Result(String, String) {
  case value {
    types.ObjectValue(_, fields) ->
      case list.key_find(fields, "label") {
        Ok(types.StringValue(label)) -> Ok(label)
        _ -> Error("point label is missing")
      }
    _ -> Error("value is not a point")
  }
}

fn text_at(
  state: tree_kernel.TreeState,
  path: types.FieldPath,
) -> Result(String, String) {
  use value <- result.try(native(tree_kernel.read(state, path)))
  case value {
    Some(types.StringValue(value)) -> Ok(value)
    _ -> Error("tree text value is missing")
  }
}

fn number_at(
  state: tree_kernel.TreeState,
  path: types.FieldPath,
) -> Result(Float, String) {
  use value <- result.try(native(tree_kernel.read(state, path)))
  case value {
    Some(types.NumberValue(value)) -> Ok(value)
    _ -> Error("tree number value is missing")
  }
}

fn input_scenarios(input: Json) -> Result(List(#(String, String)), String) {
  use root <- result.try(parse(input))
  use scenarios <- result.try(array(field(root, "scenarios")))
  list.try_map(scenarios, fn(value) {
    use scenario <- result.try(object(Ok(value)))
    use id <- result.try(text(field(scenario, "id")))
    let detail = case field(scenario, "operation") {
      Ok(value) -> text(Ok(value))
      Error(_) ->
        case field(scenario, "requiredNode") {
          Ok(value) -> text(Ok(value))
          Error(_) -> Ok("")
        }
    }
    use detail <- result.try(detail)
    Ok(#(id, detail))
  })
}

fn expected_observations(expected: Json) -> Result(List(JsonValue), String) {
  use root <- result.try(parse(expected))
  array(field(root, "observations"))
}

fn find_observation(
  observations: List(JsonValue),
  id: String,
) -> Result(List(#(String, JsonValue)), String) {
  use value <- result.try(
    observations
    |> list.find(fn(value) {
      case value {
        VObject(fields) -> list.key_find(fields, "id") == Ok(VString(id))
        _ -> False
      }
    })
    |> result.map_error(fn(_) { "missing undo observation " <> id }),
  )
  object(Ok(value))
}

fn event_kinds(
  events: Result(JsonValue, String),
) -> Result(List(String), String) {
  use events <- result.try(array(events))
  list.try_map(events, fn(event) {
    use event <- result.try(object(Ok(event)))
    text(field(event, "kind"))
  })
}

fn map_label(
  root: List(#(String, JsonValue)),
  key: String,
) -> Result(JsonValue, String) {
  use entries <- result.try(array(field(root, "byKey")))
  case
    list.find(entries, fn(entry) {
      case entry {
        VArray([VString(found), _]) -> found == key
        _ -> False
      }
    })
  {
    Error(Nil) -> Ok(VNull)
    Ok(VArray([_, VObject(point)])) -> field(point, "label")
    Ok(_) -> Error("map entry has invalid shape")
  }
}

fn array_labels(value: Result(JsonValue, String)) -> Result(JsonValue, String) {
  use values <- result.try(array(value))
  use labels <- result.try(
    list.try_map(values, fn(value) {
      case value {
        VString(value) -> Ok(VString(value))
        VObject(fields) -> field(fields, "label")
        _ -> Error("array item has no label")
      }
    }),
  )
  Ok(VArray(labels))
}

fn status_valid(value: Result(JsonValue, String)) -> Result(Bool, String) {
  use value <- result.try(text(value))
  Ok(value == "Valid")
}

fn status_text(fields: List(#(String, JsonValue)), key: String) -> String {
  field(fields, key) |> text |> result.unwrap("")
}

fn has_text(fields: List(#(String, JsonValue)), key: String) -> Bool {
  field(fields, key) |> text |> result.is_ok
}

fn observation_json(observations: List(Json)) -> Json {
  json.object([
    #("observations", json.array(observations, fn(value) { value })),
  ])
}

fn kind_name(kind: types.TreeCommitKind) -> String {
  case kind {
    types.DefaultCommit -> "Default"
    types.UndoCommit -> "Undo"
    types.RedoCommit -> "Redo"
  }
}

fn parse(value: Json) -> Result(List(#(String, JsonValue)), String) {
  use value <- result.try(
    json_ot.parse_json(json.to_string(value))
    |> result.map_error(fn(_) { "invalid undo fixture JSON" }),
  )
  object(Ok(value))
}

fn field(
  fields: List(#(String, JsonValue)),
  key: String,
) -> Result(JsonValue, String) {
  list.key_find(fields, key)
  |> result.map_error(fn(_) { "missing undo fixture field " <> key })
}

fn object(
  value: Result(JsonValue, String),
) -> Result(List(#(String, JsonValue)), String) {
  use value <- result.try(value)
  case value {
    VObject(fields) -> Ok(fields)
    _ -> Error("undo fixture value is not an object")
  }
}

fn array(value: Result(JsonValue, String)) -> Result(List(JsonValue), String) {
  use value <- result.try(value)
  case value {
    VArray(values) -> Ok(values)
    _ -> Error("undo fixture value is not an array")
  }
}

fn text(value: Result(JsonValue, String)) -> Result(String, String) {
  use value <- result.try(value)
  case value {
    VString(value) -> Ok(value)
    _ -> Error("undo fixture value is not text")
  }
}

fn boolean(value: Result(JsonValue, String)) -> Result(Bool, String) {
  use value <- result.try(value)
  case value {
    VBool(value) -> Ok(value)
    _ -> Error("undo fixture value is not a boolean")
  }
}

fn string_list(
  value: Result(JsonValue, String),
) -> Result(List(String), String) {
  use values <- result.try(array(value))
  list.try_map(values, fn(value) { text(Ok(value)) })
}

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  value
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(value) = fluid_ids.stable_id(value)
  value
}

fn native(value: Result(a, b)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn require(valid: Bool, detail: String) -> Result(Nil, String) {
  case valid {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}
