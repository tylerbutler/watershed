import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VArray, VNull, VObject, VString}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

const root_array_type = "org.watershed.shared-tree.m3.ForestRoots"

const node_type = "org.watershed.shared-tree.m3.ForestNode"

const string_type = "com.fluidframework.leaf.string"

const forest_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m3.ForestNode\":{\"kind\":{\"object\":{\"label\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"child\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"org.watershed.shared-tree.m3.ForestRoots\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m3.ForestNode\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m3.ForestRoots\"]}}"

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
      |> result.map(fn(delta) { #(value, adapt_root_delta(delta)) })
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
      use id <- result.try(atom_json(entry.id, context))
      Ok(
        json.object([
          #("id", id),
          #("values", array([tree_json(entry.value)])),
        ]),
      )
    }),
  )
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
      use attached <- result.try(
        forest.is_attached(state, reference) |> native_error,
      )
      case attached {
        True -> {
          use values <- result.try(
            forest.array_values(state, []) |> native_error,
          )
          use index <- result.try(find_attached(state, reference, values, 0))
          Ok(path_json("rootFieldKey", index))
        }
        False -> {
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
  use _ <- result.try(case destination_path {
    [destination] if destination == source_start -> Ok(Nil)
    _ -> Error("cycle adapter requires a destination in the moved root")
  })
  let count = source_end - source_start
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
  let marks =
    list.append(
      case source_start {
        0 -> []
        _ -> [forest.Mark(source_start, None, None, [])]
      },
      [
        forest.Mark(count, None, Some(moved), [
          #(
            "",
            forest.FieldDelta(
              list.append(
                case destination_gap {
                  0 -> []
                  _ -> [forest.Mark(destination_gap, None, None, [])]
                },
                [forest.Mark(count, Some(moved), None, [])],
              ),
            ),
          ),
        ]),
      ],
    )
  let data =
    forest.DeltaData(
      None,
      [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #("", forest.FieldDelta(marks)),
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
  let outcome = case forest.delta(data) {
    Error(error) -> cycle_failure(error)
    Ok(delta) ->
      case forest.apply_delta(state, delta) {
        Error(error) -> cycle_failure(error)
        Ok(_) -> success()
      }
  }
  use after <- result.try(cycle_values(state))
  Ok(
    json.object([
      #("before", before),
      #("result", outcome),
      #("after", after),
    ]),
  )
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

fn adapt_root_delta(data: forest.DeltaData) -> forest.DeltaData {
  let fields =
    list.map(data.fields, fn(pair) {
      case pair.0 {
        "rootFieldKey" -> #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [#("", pair.1)]),
          ]),
        )
        _ -> pair
      }
    })
  forest.DeltaData(..data, fields:)
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
      use major <- result.try(codec.field(value, "major", codec.integer))
      use minor <- result.try(codec.field(value, "minor", codec.integer))
      use revision <- result.try(context_revision(context, major))
      Ok(Some(types.AtomId(Some(revision), minor)))
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
            case values {
              [value] -> Ok(#(key, value))
              _ -> Error("forest node fields must contain one child")
            }
          })
        }),
      )
      Ok(types.ObjectValue(type_id, fields))
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
            list.map(fields, fn(field) {
              array([
                json.string(field.0),
                array([tree_json(field.1)]),
              ])
            }),
          ),
        ),
      ])
    types.ArrayValue(_, values) -> array(list.map(values, tree_json))
    _ -> json.null()
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

fn atom_json(id: types.AtomId, context: Context) -> Result(Json, String) {
  let Context(revisions) = context
  use major <- result.try(case id.revision {
    None -> Ok(json.null())
    Some(revision) ->
      list.find(revisions, fn(pair) { pair.1 == revision })
      |> result.map(fn(pair) { json.int(pair.0) })
      |> result.map_error(fn(_) { "unknown fixture revision" })
  })
  Ok(
    json.object([
      #("major", major),
      #("minor", json.int(id.local_id)),
    ]),
  )
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

fn cycle_failure(_error: types.TreeError) -> Json {
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
