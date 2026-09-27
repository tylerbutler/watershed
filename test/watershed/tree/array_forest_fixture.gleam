import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VArray, VNull, VObject, VString}
import watershed/tree/array_change_fixture
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

const root_array_type = "org.watershed.shared-tree.m3.ForestRoots"

const node_type = "org.watershed.shared-tree.m3.ForestNode"

const field_array_type = "org.watershed.shared-tree.m3.ForestField"

const string_type = "com.fluidframework.leaf.string"

const forest_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m3.ForestField\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m3.ForestNode\"]}}}},\"org.watershed.shared-tree.m3.ForestNode\":{\"kind\":{\"object\":{\"label\":{\"kind\":\"Optional\",\"types\":[\"org.watershed.shared-tree.m3.ForestField\"]},\"child\":{\"kind\":\"Optional\",\"types\":[\"org.watershed.shared-tree.m3.ForestField\"]}}}},\"org.watershed.shared-tree.m3.ForestRoots\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m3.ForestNode\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m3.ForestRoots\"]}}"

const cycle_array_type = "org.watershed.shared-tree.m3.cycle.Items"

const cycle_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m3.cycle.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m3.cycle.Items\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m3.cycle.Items\"]}}"

type Context {
  Context(revisions: List(#(Int, StableId)))
}

type Execution {
  Execution(
    state: forest.Forest,
    retained: Option(forest.NodeRef),
    context: Context,
    checkpoints: List(Json),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(run_scenarios(scenarios, 1, []))
  Ok(json.object([#("observations", array(list.reverse(observations)))]))
}

fn run_scenarios(
  scenarios: List(JsonValue),
  scope: Int,
  observations: List(Json),
) -> Result(List(Json), String) {
  case scenarios {
    [] -> Ok(observations)
    [scenario, ..rest] -> {
      use observation <- result.try(run_scenario(scenario, scope))
      run_scenarios(rest, scope + 1, [observation, ..observations])
    }
  }
}

fn run_scenario(value: JsonValue, scope: Int) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use revisions <- result.try(
    codec.field(value, "revisions", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use context <- result.try(context(revisions))
  use result <- result.try(case operation {
    "apply-deltas" -> run_deltas(value, context, scope)
    "apply-modular" -> run_modular(value, context, scope)
    "public-move-cycle" -> run_cycle(value, scope)
    _ -> Error("unsupported array forest operation: " <> operation)
  })
  Ok(
    json.object([
      #("id", json.string(id)),
      #("executed", json.bool(True)),
      #("accepted", json.bool(True)),
      #("value", result),
      #("result", result),
    ]),
  )
}

fn run_modular(
  scenario: JsonValue,
  context: Context,
  scope: Int,
) -> Result(Json, String) {
  use initial <- result.try(codec.get(scenario, "initialState"))
  use operands <- result.try(codec.get(scenario, "operands"))
  use runs <- result.try(codec.field(operands, "runs", codec.items))
  use observations <- result.try(
    list.try_map(runs, fn(run) {
      use id <- result.try(codec.field(run, "id", codec.text))
      use retain_index <- result.try(codec.get(run, "retainIndex"))
      use steps <- result.try(codec.field(run, "steps", codec.items))
      use deltas <- result.try(
        list.try_map(steps, fn(step) {
          use output <- result.try(
            array_change_fixture.run(
              json.object([
                #("scenarios", array([json_ot.to_json(step)])),
              ]),
            ),
          )
          use output <- result.try(codec.parse(output))
          use observations <- result.try(codec.field(
            output,
            "observations",
            codec.items,
          ))
          use observation <- result.try(case observations {
            [observation] -> Ok(observation)
            _ -> Error("a modular forest step must return one observation")
          })
          use result_value <- result.try(codec.get(observation, "result"))
          use delta <- result.try(codec.get(result_value, "delta"))
          use decoded <- result.try(decode_delta(delta, context))
          Ok(#(delta, adapt_delta(decoded)))
        }),
      )
      let replay =
        VObject([
          #("initialState", initial),
          #(
            "operands",
            VObject([
              #("retainIndex", retain_index),
              #("deltas", VArray(list.map(deltas, fn(delta) { delta.0 }))),
            ]),
          ),
        ])
      use checkpoints <- result.try(run_deltas(replay, context, scope))
      Ok(
        json.object([
          #("id", json.string(id)),
          #("checkpoints", checkpoints),
        ]),
      )
    }),
  )
  Ok(array(observations))
}

fn run_deltas(
  scenario: JsonValue,
  context: Context,
  scope: Int,
) -> Result(Json, String) {
  use initial <- result.try(
    codec.field(scenario, "initialState", codec.get(_, "field")),
  )
  use values <- result.try(codec.many(initial, decode_tree))
  use operands <- result.try(
    codec.field(scenario, "operands", fn(value) { Ok(value) }),
  )
  use retain_index <- result.try(
    codec.field(operands, "retainIndex", fn(value) {
      codec.optional(value, codec.integer)
    }),
  )
  use encoded_deltas <- result.try(codec.field(operands, "deltas", codec.items))
  use deltas <- result.try(
    list.try_map(encoded_deltas, fn(value) {
      decode_delta(value, context)
      |> result.map(fn(delta) { #(value, adapt_delta(delta)) })
    }),
  )
  use stored <- result.try(
    schema.stored_from_string(forest_schema)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(view_id(scope))
  use state <- result.try(
    forest.new(view, stored, Some(types.ArrayValue(root_array_type, values)))
    |> native_error,
  )
  use retained <- result.try(case retain_index {
    None -> Ok(None)
    Some(index) ->
      forest.locate(state, [int.to_string(index)])
      |> native_error
      |> result.map(Some)
  })
  use execution <- result.try(apply_deltas(
    deltas,
    Execution(state, retained, context, []),
  ))
  Ok(array(list.reverse(execution.checkpoints)))
}

fn apply_deltas(
  deltas: List(#(JsonValue, forest.DeltaData)),
  execution: Execution,
) -> Result(Execution, String) {
  case deltas {
    [] -> Ok(execution)
    [#(encoded, data), ..rest] -> {
      use before <- result.try(observe(execution.state, execution.context))
      case forest.delta(data) {
        Error(error) ->
          Ok(
            Execution(..execution, checkpoints: [
              checkpoint(encoded, before, failure(error), invalidated()),
              ..execution.checkpoints
            ]),
          )
        Ok(delta) ->
          case forest.apply_delta(execution.state, delta) {
            Error(error) ->
              Ok(
                Execution(..execution, checkpoints: [
                  checkpoint(encoded, before, failure(error), invalidated()),
                  ..execution.checkpoints
                ]),
              )
            Ok(state) -> {
              use after <- result.try(observe_after(
                state,
                execution.retained,
                execution.context,
              ))
              apply_deltas(
                rest,
                Execution(..execution, state:, checkpoints: [
                  checkpoint(encoded, before, success(), after),
                  ..execution.checkpoints
                ]),
              )
            }
          }
      }
    }
  }
}

fn checkpoint(
  delta: JsonValue,
  before: Json,
  outcome: Json,
  after: Json,
) -> Json {
  json.object([
    #("before", before),
    #("delta", json_ot.to_json(delta)),
    #("result", outcome),
    #("after", after),
  ])
}

fn observe(state: forest.Forest, context: Context) -> Result(Json, String) {
  use data <- result.try(forest.export_data(state) |> native_error)
  use root <- result.try(root_values(data.root))
  use detached <- result.try(
    list.try_map(data.detached, fn(entry) {
      use source_id <- result.try(source_atom(entry.id, context))
      Ok(#(
        source_id,
        json.object([
          #("id", atom_json(source_id)),
          #("values", array([tree_json(entry.value)])),
        ]),
      ))
    }),
  )
  let detached =
    detached
    |> list.sort(fn(left, right) { compare_source_atom(left.0, right.0) })
    |> list.map(fn(entry) { entry.1 })
  Ok(json.object([#("root", array(root)), #("detached", array(detached))]))
}

fn observe_after(
  state: forest.Forest,
  retained: Option(forest.NodeRef),
  context: Context,
) -> Result(Json, String) {
  use observed <- result.try(observe(state, context))
  use identity <- result.try(identity_json(state, retained))
  use value <- result.try(codec.parse(observed))
  let assert VObject(fields) = value
  Ok(
    json.object([
      #(
        "root",
        json_ot.to_json(list.key_find(fields, "root") |> result.unwrap(VNull)),
      ),
      #(
        "detached",
        json_ot.to_json(
          list.key_find(fields, "detached") |> result.unwrap(VNull),
        ),
      ),
      #("identity", identity),
    ]),
  )
}

fn identity_json(
  state: forest.Forest,
  retained: Option(forest.NodeRef),
) -> Result(Json, String) {
  case retained {
    None -> Ok(json.null())
    Some(reference) -> {
      case forest.is_attached(state, reference) {
        Error(types.InvalidEdit([], "node reference is no longer valid")) ->
          Ok(json.null())
        Error(error) -> native_error(Error(error))
        Ok(True) -> {
          use values <- result.try(
            forest.array_values(state, []) |> native_error,
          )
          use index <- result.try(find_attached(state, reference, values, 0))
          Ok(path_json("rootFieldKey", index))
        }
        Ok(False) -> {
          use data <- result.try(forest.export_data(state) |> native_error)
          use root <- result.try(find_detached(state, reference, data.detached))
          Ok(path_json("watershed-array-forest-" <> int.to_string(root), 0))
        }
      }
    }
  }
}

fn find_attached(
  state: forest.Forest,
  reference: forest.NodeRef,
  values: List(types.TreeValue),
  index: Int,
) -> Result(Int, String) {
  case values {
    [] -> Error("retained node is attached outside the root sequence")
    [_, ..rest] ->
      case forest.locate(state, [int.to_string(index)]) {
        Ok(candidate) if candidate == reference -> Ok(index)
        _ -> find_attached(state, reference, rest, index + 1)
      }
  }
}

fn find_detached(
  state: forest.Forest,
  reference: forest.NodeRef,
  entries: List(forest.DetachedTreeData),
) -> Result(Int, String) {
  case entries {
    [] -> Error("retained node is not present in the detached index")
    [entry, ..rest] ->
      case forest.locate_detached(state, entry.id) {
        Ok(candidate) if candidate == reference -> Ok(entry.forest_root_id)
        _ -> find_detached(state, reference, rest)
      }
  }
}

fn path_json(field: String, index: Int) -> Json {
  json.object([
    #("field", json.string(field)),
    #("index", json.int(index)),
    #("parent", json.null()),
  ])
}

fn run_cycle(scenario: JsonValue, scope: Int) -> Result(Json, String) {
  use initial <- result.try(codec.field(scenario, "initialState", codec.items))
  use values <- result.try(list.try_map(initial, decode_cycle))
  use operands <- result.try(
    codec.field(scenario, "operands", fn(value) { Ok(value) }),
  )
  use move <- result.try(codec.field(operands, "move", fn(value) { Ok(value) }))
  use source_start <- result.try(codec.field(move, "sourceStart", codec.integer))
  use source_end <- result.try(codec.field(move, "sourceEnd", codec.integer))
  use source_path <- result.try(
    codec.field(move, "sourcePath", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use destination_gap <- result.try(codec.field(
    move,
    "destinationGap",
    codec.integer,
  ))
  use destination_path <- result.try(
    codec.field(move, "destinationPath", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use stored <- result.try(
    schema.stored_from_string(cycle_schema)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(view_id(scope))
  use state <- result.try(
    forest.new(view, stored, Some(types.ArrayValue(cycle_array_type, values)))
    |> native_error,
  )
  use before <- result.try(cycle_values(state))
  let moved = types.AtomId(None, 0)
  use #(outcome, after_state) <- result.try(
    case
      validate_move(
        values,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      )
    {
      Error(error) -> Ok(#(move_failure(error), state))
      Ok(Nil) if source_start == source_end -> {
        use value <- result.try(cycle_values(state))
        Ok(#(success_value(value), state))
      }
      Ok(Nil) -> {
        use field_delta <- result.try(move_delta(
          source_path,
          source_start,
          source_end,
          destination_path,
          destination_gap,
          moved,
        ))
        let data =
          forest.DeltaData(
            None,
            [
              #(
                "rootFieldKey",
                forest.FieldDelta([
                  forest.Mark(1, None, None, [
                    #("", field_delta),
                  ]),
                ]),
              ),
            ],
            [],
            [],
            [],
            [],
            [],
          )
        case forest.delta(data) {
          Error(error) -> Ok(#(move_failure(error), state))
          Ok(delta) ->
            case forest.apply_delta(state, delta) {
              Error(error) -> Ok(#(move_failure(error), state))
              Ok(after_state) -> {
                use value <- result.try(cycle_values(after_state))
                Ok(#(success_value(value), after_state))
              }
            }
        }
      }
    },
  )
  use after <- result.try(cycle_values(after_state))
  Ok(
    json.object([
      #("before", before),
      #("result", outcome),
      #("after", after),
    ]),
  )
}

fn validate_move(
  root: List(types.TreeValue),
  source_path: List(Int),
  source_start: Int,
  source_end: Int,
  destination_path: List(Int),
  destination_gap: Int,
) -> Result(Nil, types.TreeError) {
  use source <- result.try(cycle_path(root, source_path))
  use destination <- result.try(cycle_path(root, destination_path))
  use _ <- result.try(
    case
      source_start >= 0
      && source_end >= source_start
      && source_end <= list.length(source)
    {
      True -> Ok(Nil)
      False -> Error(types.CorruptData("", "move range is outside the field"))
    },
  )
  case destination_gap >= 0 && destination_gap <= list.length(destination) {
    True -> Ok(Nil)
    False -> Error(types.CorruptData("", "move gap is outside the field"))
  }
}

fn cycle_path(
  values: List(types.TreeValue),
  path: List(Int),
) -> Result(List(types.TreeValue), types.TreeError) {
  case path {
    [] -> Ok(values)
    [index, ..rest] ->
      case index >= 0, values |> list.drop(index) |> list.first {
        True, Ok(types.ArrayValue(type_id, values))
          if type_id == cycle_array_type
        -> cycle_path(values, rest)
        _, _ ->
          Error(types.CorruptData("", "move path does not identify an array"))
      }
  }
}

fn move_delta(
  source_path: List(Int),
  source_start: Int,
  source_end: Int,
  destination_path: List(Int),
  destination_gap: Int,
  moved: types.AtomId,
) -> Result(forest.FieldDelta, String) {
  let count = source_end - source_start
  case source_path, destination_path {
    [], [] ->
      Ok(same_field_move(source_start, source_end, destination_gap, moved))
    [], [target, ..rest] ->
      Ok(detach_with_child_change(
        source_start,
        source_end,
        moved,
        target,
        change_at_path(rest, attach_delta(destination_gap, count, moved)),
      ))
    [target, ..rest], [] ->
      Ok(attach_with_child_change(
        destination_gap,
        count,
        moved,
        target,
        change_at_path(rest, detach_delta(source_start, source_end, moved)),
      ))
    [left, ..left_rest], [right, ..right_rest] if left == right -> {
      use nested <- result.try(move_delta(
        left_rest,
        source_start,
        source_end,
        right_rest,
        destination_gap,
        moved,
      ))
      Ok(select_child(left, nested))
    }
    [left, ..left_rest], [right, ..right_rest] if left < right ->
      Ok(select_two_children(
        left,
        change_at_path(left_rest, detach_delta(source_start, source_end, moved)),
        right,
        change_at_path(right_rest, attach_delta(destination_gap, count, moved)),
      ))
    [left, ..left_rest], [right, ..right_rest] ->
      Ok(select_two_children(
        right,
        change_at_path(right_rest, attach_delta(destination_gap, count, moved)),
        left,
        change_at_path(left_rest, detach_delta(source_start, source_end, moved)),
      ))
  }
}

fn detach_delta(
  source_start: Int,
  source_end: Int,
  moved: types.AtomId,
) -> forest.FieldDelta {
  forest.FieldDelta(
    list.append(unchanged(source_start), [
      forest.Mark(source_end - source_start, None, Some(moved), []),
    ]),
  )
}

fn attach_delta(
  destination_gap: Int,
  count: Int,
  moved: types.AtomId,
) -> forest.FieldDelta {
  forest.FieldDelta(
    list.append(unchanged(destination_gap), [
      forest.Mark(count, Some(moved), None, []),
    ]),
  )
}

fn detach_with_child_change(
  source_start: Int,
  source_end: Int,
  moved: types.AtomId,
  child: Int,
  change: forest.FieldDelta,
) -> forest.FieldDelta {
  let count = source_end - source_start
  let marks = case child < source_start, child >= source_end {
    True, _ ->
      list.flatten([
        unchanged(child),
        [forest.Mark(1, None, None, [#("", change)])],
        unchanged(source_start - child - 1),
        detach(count, moved, []),
      ])
    _, True ->
      list.flatten([
        unchanged(source_start),
        detach(count, moved, []),
        unchanged(child - source_end),
        [forest.Mark(1, None, None, [#("", change)])],
      ])
    False, False -> {
      let before = child - source_start
      list.flatten([
        unchanged(source_start),
        detach(before, moved, []),
        [
          forest.Mark(1, None, Some(offset_atom(moved, before)), [
            #("", change),
          ]),
        ],
        detach(count - before - 1, offset_atom(moved, before + 1), []),
      ])
    }
  }
  forest.FieldDelta(marks)
}

fn attach_with_child_change(
  destination_gap: Int,
  count: Int,
  moved: types.AtomId,
  child: Int,
  change: forest.FieldDelta,
) -> forest.FieldDelta {
  let marks = case child < destination_gap {
    True ->
      list.flatten([
        unchanged(child),
        [forest.Mark(1, None, None, [#("", change)])],
        unchanged(destination_gap - child - 1),
        [forest.Mark(count, Some(moved), None, [])],
      ])
    False ->
      list.flatten([
        unchanged(destination_gap),
        [forest.Mark(count, Some(moved), None, [])],
        unchanged(child - destination_gap),
        [forest.Mark(1, None, None, [#("", change)])],
      ])
  }
  forest.FieldDelta(marks)
}

fn select_child(index: Int, change: forest.FieldDelta) -> forest.FieldDelta {
  forest.FieldDelta(
    list.append(unchanged(index), [
      forest.Mark(1, None, None, [#("", change)]),
    ]),
  )
}

fn select_two_children(
  first_index: Int,
  first_change: forest.FieldDelta,
  second_index: Int,
  second_change: forest.FieldDelta,
) -> forest.FieldDelta {
  forest.FieldDelta(
    list.flatten([
      unchanged(first_index),
      [forest.Mark(1, None, None, [#("", first_change)])],
      unchanged(second_index - first_index - 1),
      [forest.Mark(1, None, None, [#("", second_change)])],
    ]),
  )
}

fn same_field_move(
  source_start: Int,
  source_end: Int,
  destination_gap: Int,
  moved: types.AtomId,
) -> forest.FieldDelta {
  let count = source_end - source_start
  let marks = case destination_gap <= source_start {
    True ->
      list.flatten([
        unchanged(destination_gap),
        [forest.Mark(count, Some(moved), None, [])],
        unchanged(source_start - destination_gap),
        [forest.Mark(count, None, Some(moved), [])],
      ])
    False ->
      case destination_gap >= source_end {
        True ->
          list.flatten([
            unchanged(source_start),
            [forest.Mark(count, None, Some(moved), [])],
            unchanged(destination_gap - source_end),
            [forest.Mark(count, Some(moved), None, [])],
          ])
        False -> []
      }
  }
  forest.FieldDelta(marks)
}

fn change_at_path(
  path: List(Int),
  change: forest.FieldDelta,
) -> forest.FieldDelta {
  case path {
    [] -> change
    [index, ..rest] ->
      forest.FieldDelta(
        list.append(unchanged(index), [
          forest.Mark(1, None, None, [
            #("", change_at_path(rest, change)),
          ]),
        ]),
      )
  }
}

fn unchanged(count: Int) -> List(forest.Mark) {
  case count {
    0 -> []
    _ -> [forest.Mark(count, None, None, [])]
  }
}

fn detach(
  count: Int,
  id: types.AtomId,
  fields: List(#(String, forest.FieldDelta)),
) -> List(forest.Mark) {
  case count {
    0 -> []
    _ -> [forest.Mark(count, None, Some(id), fields)]
  }
}

fn offset_atom(id: types.AtomId, count: Int) -> types.AtomId {
  types.AtomId(id.revision, id.local_id + count)
}

fn cycle_values(state: forest.Forest) -> Result(Json, String) {
  use values <- result.try(forest.array_values(state, []) |> native_error)
  Ok(array(list.map(values, cycle_json)))
}

fn decode_delta(
  value: JsonValue,
  context: Context,
) -> Result(forest.DeltaData, String) {
  use fields <- result.try(
    optional_field(value, "fields", decode_fields(_, context), []),
  )
  use build <- result.try(
    optional_field(
      value,
      "build",
      fn(value) { codec.many(value, decode_build(_, context)) },
      [],
    ),
  )
  use refreshers <- result.try(
    optional_field(
      value,
      "refreshers",
      fn(value) { codec.many(value, decode_build(_, context)) },
      [],
    ),
  )
  use global <- result.try(
    optional_field(
      value,
      "global",
      fn(value) { codec.many(value, decode_global(_, context)) },
      [],
    ),
  )
  use rename <- result.try(
    optional_field(
      value,
      "rename",
      fn(value) { codec.many(value, decode_rename(_, context)) },
      [],
    ),
  )
  use destroy <- result.try(
    optional_field(
      value,
      "destroy",
      fn(value) { codec.many(value, decode_destroy(_, context)) },
      [],
    ),
  )
  Ok(forest.DeltaData(None, fields, build, refreshers, global, rename, destroy))
}

fn adapt_delta(data: forest.DeltaData) -> forest.DeltaData {
  let fields = adapt_fields(data.fields)
  let global =
    list.map(data.global, fn(change) {
      let forest.DetachedChange(id, fields) = change
      forest.DetachedChange(id, adapt_fields(fields))
    })
  forest.DeltaData(..data, fields:, global:)
}

fn adapt_fields(
  fields: List(#(String, forest.FieldDelta)),
) -> List(#(String, forest.FieldDelta)) {
  list.map(fields, fn(pair) {
    #(
      pair.0,
      forest.FieldDelta([
        forest.Mark(1, None, None, [
          #("", adapt_field_delta(pair.1)),
        ]),
      ]),
    )
  })
}

fn adapt_field_delta(delta: forest.FieldDelta) -> forest.FieldDelta {
  let forest.FieldDelta(marks) = delta
  forest.FieldDelta(
    list.map(marks, fn(mark) {
      let forest.Mark(count, attach, detach, fields) = mark
      forest.Mark(count, attach, detach, adapt_fields(fields))
    }),
  )
}

fn decode_fields(
  value: JsonValue,
  context: Context,
) -> Result(List(#(String, forest.FieldDelta)), String) {
  codec.many(value, fn(entry) {
    use #(key, value) <- result.try(codec.pair(entry))
    use key <- result.try(codec.text(key))
    use marks <- result.try(
      codec.field(value, "marks", fn(value) {
        codec.many(value, decode_mark(_, context))
      }),
    )
    Ok(#(key, forest.FieldDelta(marks)))
  })
}

fn decode_mark(
  value: JsonValue,
  context: Context,
) -> Result(forest.Mark, String) {
  use count <- result.try(codec.field(value, "count", codec.integer))
  use attach <- result.try(optional_field(
    value,
    "attach",
    fn(value) { decode_optional_atom(value, context) },
    None,
  ))
  use detach <- result.try(optional_field(
    value,
    "detach",
    fn(value) { decode_optional_atom(value, context) },
    None,
  ))
  use fields <- result.try(
    optional_field(value, "fields", decode_fields(_, context), []),
  )
  Ok(forest.Mark(count, attach, detach, fields))
}

fn decode_optional_atom(
  value: JsonValue,
  context: Context,
) -> Result(Option(types.AtomId), String) {
  case value {
    VNull -> Ok(None)
    value -> {
      let #(major_key, minor_key) = case codec.get(value, "major") {
        Ok(_) -> #("major", "minor")
        Error(_) -> #("revision", "localId")
      }
      use major <- result.try(
        codec.field(value, major_key, fn(value) {
          codec.optional(value, codec.integer)
        }),
      )
      use minor <- result.try(codec.field(value, minor_key, codec.integer))
      case major {
        None -> Ok(Some(types.AtomId(None, minor)))
        Some(major) -> {
          use revision <- result.try(context_revision(context, major))
          Ok(Some(types.AtomId(Some(revision), minor)))
        }
      }
    }
  }
}

fn decode_build(
  value: JsonValue,
  context: Context,
) -> Result(forest.Build, String) {
  use id <- result.try(decode_required_atom(value, "id", context))
  use trees <- result.try(
    codec.field(value, "trees", fn(value) { codec.many(value, decode_tree) }),
  )
  Ok(forest.Build(id, trees))
}

fn decode_global(
  value: JsonValue,
  context: Context,
) -> Result(forest.DetachedChange, String) {
  use id <- result.try(decode_required_atom(value, "id", context))
  use fields <- result.try(
    codec.field(value, "fields", decode_fields(_, context)),
  )
  Ok(forest.DetachedChange(id, fields))
}

fn decode_rename(
  value: JsonValue,
  context: Context,
) -> Result(forest.Rename, String) {
  use old_id <- result.try(decode_required_atom(value, "oldId", context))
  use new_id <- result.try(decode_required_atom(value, "newId", context))
  use count <- result.try(codec.field(value, "count", codec.integer))
  Ok(forest.Rename(old_id, new_id, count))
}

fn decode_destroy(
  value: JsonValue,
  context: Context,
) -> Result(forest.Destroy, String) {
  use id <- result.try(decode_required_atom(value, "id", context))
  use count <- result.try(codec.field(value, "count", codec.integer))
  Ok(forest.Destroy(id, count))
}

fn decode_required_atom(
  value: JsonValue,
  key: String,
  context: Context,
) -> Result(types.AtomId, String) {
  use atom <- result.try(
    codec.field(value, key, fn(value) { decode_optional_atom(value, context) }),
  )
  case atom {
    Some(atom) -> Ok(atom)
    None -> Error(key <> " must contain an atom")
  }
}

fn decode_tree(value: JsonValue) -> Result(types.TreeValue, String) {
  use type_id <- result.try(codec.field(value, "type", codec.text))
  case type_id {
    value_type if value_type == string_type ->
      codec.field(value, "value", codec.text)
      |> result.map(types.StringValue)
    value_type if value_type == node_type -> {
      use fields <- result.try(
        codec.field(value, "fields", fn(value) {
          codec.many(value, fn(entry) {
            use #(key, values) <- result.try(codec.pair(entry))
            use key <- result.try(codec.text(key))
            use values <- result.try(codec.many(values, decode_tree))
            Ok(#(key, types.ArrayValue(field_array_type, values)))
          })
        }),
      )
      Ok(types.ObjectValue(type_id, complete_node_fields(fields)))
    }
    _ -> Error("unsupported source forest node type: " <> type_id)
  }
}

fn decode_cycle(value: JsonValue) -> Result(types.TreeValue, String) {
  case value {
    VString(value) -> Ok(types.StringValue(value))
    VArray(values) -> {
      use values <- result.try(list.try_map(values, decode_cycle))
      Ok(types.ArrayValue(cycle_array_type, values))
    }
    _ -> Error("cycle content must contain strings or arrays")
  }
}

fn tree_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.ObjectValue(type_id, fields) ->
      json.object([
        #("type", json.string(type_id)),
        #(
          "fields",
          array(
            fields
            |> list.sort(fn(left, right) {
              canonical_json.compare(left.0, right.0)
            })
            |> list.filter_map(fn(field) {
              case field_json(field.1) {
                None -> Error(Nil)
                Some(value) -> Ok(array([json.string(field.0), value]))
              }
            }),
          ),
        ),
      ])
    types.ArrayValue(_, values) -> array(list.map(values, tree_json))
    _ -> json.null()
  }
}

fn complete_node_fields(
  fields: List(#(String, types.TreeValue)),
) -> List(#(String, types.TreeValue)) {
  list.fold(["label", "child"], fields, fn(fields, key) {
    case list.key_find(fields, key) {
      Ok(_) -> fields
      Error(Nil) ->
        list.append(fields, [#(key, types.ArrayValue(field_array_type, []))])
    }
  })
}

fn field_json(value: types.TreeValue) -> Option(Json) {
  case value {
    types.ArrayValue(type_id, []) if type_id == field_array_type -> None
    types.ArrayValue(type_id, values) if type_id == field_array_type ->
      Some(array(list.map(values, tree_json)))
    _ -> Some(array([tree_json(value)]))
  }
}

fn cycle_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.ArrayValue(_, values) -> array(list.map(values, cycle_json))
    _ -> json.null()
  }
}

fn root_values(root: Option(types.TreeValue)) -> Result(List(Json), String) {
  case root {
    Some(types.ArrayValue(type_id, values)) if type_id == root_array_type ->
      Ok(list.map(values, tree_json))
    _ -> Error("forest adapter root is not an array")
  }
}

fn optional_field(
  value: JsonValue,
  key: String,
  decode: fn(JsonValue) -> Result(a, String),
  default: a,
) -> Result(a, String) {
  case value {
    VObject(fields) ->
      case list.key_find(fields, key) {
        Ok(value) -> decode(value)
        Error(Nil) -> Ok(default)
      }
    _ -> Error("expected an object for " <> key)
  }
}

fn context(revisions: List(Int)) -> Result(Context, String) {
  use values <- result.try(
    list.try_map(revisions, fn(revision) {
      revision_for(revision) |> result.map(fn(stable) { #(revision, stable) })
    }),
  )
  Ok(Context(values))
}

fn revision_for(revision: Int) -> Result(StableId, String) {
  let suffix =
    revision
    |> int.absolute_value
    |> int.to_base_string(16)
    |> result.unwrap("0")
    |> string.pad_start(12, "0")
  fluid_ids.stable_id("10000000-0000-4000-8000-" <> suffix)
  |> result.map_error(string.inspect)
}

fn context_revision(
  context: Context,
  revision: Int,
) -> Result(StableId, String) {
  let Context(revisions) = context
  list.key_find(revisions, revision)
  |> result.map_error(fn(_) {
    "atom uses an undeclared revision: " <> int.to_string(revision)
  })
}

fn source_atom(
  id: types.AtomId,
  context: Context,
) -> Result(#(Option(Int), Int), String) {
  let Context(revisions) = context
  use major <- result.try(case id.revision {
    None -> Ok(None)
    Some(revision) ->
      list.find(revisions, fn(pair) { pair.1 == revision })
      |> result.map(fn(pair) { Some(pair.0) })
      |> result.map_error(fn(_) { "unknown fixture revision" })
  })
  Ok(#(major, id.local_id))
}

fn atom_json(id: #(Option(Int), Int)) -> Json {
  json.object([
    #("major", case id.0 {
      None -> json.null()
      Some(major) -> json.int(major)
    }),
    #("minor", json.int(id.1)),
  ])
}

fn compare_source_atom(
  left: #(Option(Int), Int),
  right: #(Option(Int), Int),
) -> order.Order {
  case left.0, right.0 {
    None, None -> int.compare(left.1, right.1)
    None, Some(_) -> order.Lt
    Some(_), None -> order.Gt
    Some(left_major), Some(right_major) ->
      case int.compare(left_major, right_major) {
        order.Eq -> int.compare(left.1, right.1)
        compared -> compared
      }
  }
}

fn view_id(scope: Int) -> Result(StableId, String) {
  use suffix <- result.try(
    int.to_base_string(scope, 16)
    |> result.map_error(fn(_) { "could not encode array forest scope" }),
  )
  fluid_ids.stable_id(
    "20000000-0000-4000-8000-" <> string.pad_start(suffix, 12, "0"),
  )
  |> result.map_error(string.inspect)
}

fn success() -> Json {
  json.object([
    #("accepted", json.bool(True)),
    #("value", json.object([])),
  ])
}

fn success_value(value: Json) -> Json {
  json.object([
    #("accepted", json.bool(True)),
    #("value", value),
  ])
}

fn failure(error: types.TreeError) -> Json {
  let detail = case error {
    types.CorruptData(_, "overlapping identifier ranges") -> "Error: 0x92a"
    _ -> "Error: " <> string.inspect(error)
  }
  json.object([
    #("accepted", json.bool(False)),
    #("error", json.string(detail)),
  ])
}

fn move_failure(error: types.TreeError) -> Json {
  case error {
    types.CorruptData("forest", "node has multiple owners or a cycle") ->
      cycle_failure()
    types.CorruptData("forest", "unowned nodes remain") -> cycle_failure()
    _ -> failure(error)
  }
}

fn cycle_failure() -> Json {
  json.object([
    #("accepted", json.bool(False)),
    #(
      "error",
      json.string(
        "Error: Invalid move operation: the destination is located under one of the moved elements. Consider using the Tree.contains API to detect this.",
      ),
    ),
  ])
}

fn invalidated() -> Json {
  json.object([#("invalidated", json.bool(True))])
}

fn native_error(value: Result(a, types.TreeError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
