import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

const max_safe_integer = 9_007_199_254_740_991

type Scenario {
  Scenario(
    id: String,
    schema: String,
    root: Option(types.TreeValue),
    actions: List(Action),
  )
}

type Action {
  Retain(id: String, name: String, path: List(String))
  RetainDetached(id: String, name: String, atom: types.AtomId)
  Apply(id: String, delta: forest.DeltaData)
  Observe(id: String)
  Copy(id: String)
}

type Retained {
  Retained(name: String, reference: forest.NodeRef, generation: Int)
}

type Execution {
  Execution(
    tree: forest.Forest,
    schema: schema.StoredSchema,
    references: List(Retained),
    generation: Int,
    next_scope: Int,
    checkpoints: List(Json),
  )
}

type Replay {
  Replay(observations: List(Json), next_scope: Int)
}

pub fn run(input: Json) -> Result(Json, String) {
  use scenarios <- result.try(
    json.parse(json.to_string(input), {
      use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
      exact_decoder(fields, ["scenarios"], [], {
        use scenarios <- decode.field(
          "scenarios",
          decode.list(scenario_decoder()),
        )
        decode.success(scenarios)
      })
    })
    |> result.map_error(fn(error) {
      "invalid forest fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(validate_scenarios(scenarios))
  use replay <- result.try(
    list.try_fold(scenarios, Replay([], 1), fn(replay, scenario) {
      use #(observation, next_scope) <- result.try(run_scenario(
        scenario,
        replay.next_scope,
      ))
      Ok(Replay(observations: [observation, ..replay.observations], next_scope:))
    }),
  )
  Ok(
    json.object([
      #("observations", array(list.reverse(replay.observations))),
    ]),
  )
}

fn scenario_decoder() -> Decoder(Scenario) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "schema", "root", "actions"],
    Scenario("", "", None, []),
    {
      use id <- decode.field("id", decode.string)
      use stored <- decode.field("schema", decode.string)
      use root <- decode.field(
        "root",
        decode.optional(fixtures.tree_value_decoder()),
      )
      use actions <- decode.field("actions", decode.list(action_decoder()))
      decode.success(Scenario(id:, schema: stored, root:, actions:))
    },
  )
}

fn action_decoder() -> Decoder(Action) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use id <- decode.field("id", decode.string)
  use operation <- decode.field("op", decode.string)
  case operation {
    "retain" ->
      exact_decoder(fields, ["id", "op", "name", "path"], Observe(id), {
        use name <- decode.field("name", decode.string)
        use path <- decode.field("path", decode.list(decode.string))
        decode.success(Retain(id, name, path))
      })
    "retainDetached" ->
      exact_decoder(fields, ["id", "op", "name", "atom"], Observe(id), {
        use name <- decode.field("name", decode.string)
        use atom <- decode.field("atom", atom_decoder())
        decode.success(RetainDetached(id, name, atom))
      })
    "apply" ->
      exact_decoder(fields, ["id", "op", "delta"], Observe(id), {
        use delta <- decode.field("delta", delta_decoder())
        decode.success(Apply(id, delta))
      })
    "observe" ->
      exact_decoder(
        fields,
        ["id", "op"],
        Observe(id),
        decode.success(Observe(id)),
      )
    "copy" ->
      exact_decoder(fields, ["id", "op"], Observe(id), decode.success(Copy(id)))
    _ -> decode.failure(Observe(id), "known forest action")
  }
}

fn delta_decoder() -> Decoder(forest.DeltaData) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    [
      "latestRevision",
      "fields",
      "build",
      "refreshers",
      "global",
      "rename",
      "destroy",
    ],
    empty_delta(),
    {
      use latest_revision <- decode.field("latestRevision", revision_decoder())
      use field_changes <- decode.field("fields", field_map_decoder())
      use build <- decode.field("build", decode.list(build_decoder()))
      use refreshers <- decode.field("refreshers", decode.list(build_decoder()))
      use global <- decode.field(
        "global",
        decode.list(detached_change_decoder()),
      )
      use rename <- decode.field("rename", decode.list(rename_decoder()))
      use destroy <- decode.field("destroy", decode.list(destroy_decoder()))
      decode.success(forest.DeltaData(
        latest_revision:,
        fields: field_changes,
        build:,
        refreshers:,
        global:,
        rename:,
        destroy:,
      ))
    },
  )
}

fn field_map_decoder() -> Decoder(List(#(String, forest.FieldDelta))) {
  decode.list({
    use pair <- decode.then(decode.list(decode.dynamic))
    case pair {
      [_, _] -> {
        use key <- decode.field(0, decode.string)
        use delta <- decode.field(1, decode.recursive(field_delta_decoder))
        decode.success(#(key, delta))
      }
      _ ->
        decode.failure(#("", forest.FieldDelta([])), "two-element field entry")
    }
  })
}

fn field_delta_decoder() -> Decoder(forest.FieldDelta) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["marks"], forest.FieldDelta([]), {
    use marks <- decode.field("marks", decode.list(mark_decoder()))
    decode.success(forest.FieldDelta(marks))
  })
}

fn mark_decoder() -> Decoder(forest.Mark) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["count", "attach", "detach", "fields"],
    forest.Mark(0, None, None, []),
    {
      use count <- decode.field("count", decode.int)
      use attach <- decode.field("attach", decode.optional(atom_decoder()))
      use detach <- decode.field("detach", decode.optional(atom_decoder()))
      use nested <- decode.field("fields", decode.recursive(field_map_decoder))
      decode.success(forest.Mark(count, attach, detach, nested))
    },
  )
}

fn build_decoder() -> Decoder(forest.Build) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "trees"], forest.Build(empty_atom(), []), {
    use id <- decode.field("id", atom_decoder())
    use trees <- decode.field(
      "trees",
      decode.list(fixtures.tree_value_decoder()),
    )
    decode.success(forest.Build(id, trees))
  })
}

fn detached_change_decoder() -> Decoder(forest.DetachedChange) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "fields"],
    forest.DetachedChange(empty_atom(), []),
    {
      use id <- decode.field("id", atom_decoder())
      use changes <- decode.field("fields", field_map_decoder())
      decode.success(forest.DetachedChange(id, changes))
    },
  )
}

fn rename_decoder() -> Decoder(forest.Rename) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["oldId", "newId", "count"],
    forest.Rename(empty_atom(), empty_atom(), 0),
    {
      use old_id <- decode.field("oldId", atom_decoder())
      use new_id <- decode.field("newId", atom_decoder())
      use count <- decode.field("count", decode.int)
      decode.success(forest.Rename(old_id, new_id, count))
    },
  )
}

fn destroy_decoder() -> Decoder(forest.Destroy) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "count"], forest.Destroy(empty_atom(), 0), {
    use id <- decode.field("id", atom_decoder())
    use count <- decode.field("count", decode.int)
    decode.success(forest.Destroy(id, count))
  })
}

fn atom_decoder() -> Decoder(types.AtomId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["revision", "localId"], empty_atom(), {
    use revision <- decode.field("revision", revision_decoder())
    use local_id <- decode.field("localId", decode.int)
    case local_id >= 0 && local_id <= max_safe_integer {
      True -> decode.success(types.AtomId(revision, local_id))
      False -> decode.failure(empty_atom(), "nonnegative safe atom localId")
    }
  })
}

fn revision_decoder() -> Decoder(Option(fluid_ids.StableId)) {
  decode.optional(decode.string)
  |> decode.then(fn(raw) {
    case raw {
      None -> decode.success(None)
      Some(raw) ->
        case fluid_ids.stable_id(raw) {
          Ok(revision) -> decode.success(Some(revision))
          Error(_) -> decode.failure(None, "valid stable revision")
        }
    }
  })
}

fn empty_atom() -> types.AtomId {
  types.AtomId(None, 0)
}

fn empty_delta() -> forest.DeltaData {
  forest.DeltaData(None, [], [], [], [], [], [])
}

fn exact_decoder(
  fields: Dict(String, Dynamic),
  expected: List(String),
  placeholder: a,
  decoder: Decoder(a),
) -> Decoder(a) {
  case exact_fields(fields, expected) {
    True -> decoder
    False -> decode.failure(placeholder, "object with exact fields")
  }
}

fn exact_fields(fields: Dict(String, Dynamic), expected: List(String)) -> Bool {
  dict.size(fields) == list.length(expected)
  && list.all(expected, fn(field) { dict.has_key(fields, field) })
}

fn validate_scenarios(scenarios: List(Scenario)) -> Result(Nil, String) {
  case scenarios {
    [] -> Error("forest fixture scenarios must not be empty")
    [_, ..] -> {
      use _ <- result.try(
        list.try_fold(scenarios, set.new(), fn(ids, scenario) {
          use ids <- result.try(unique_name(ids, scenario.id, "scenario id"))
          use _ <- result.try(validate_actions(scenario))
          Ok(ids)
        }),
      )
      Ok(Nil)
    }
  }
}

fn validate_actions(scenario: Scenario) -> Result(Nil, String) {
  case scenario.actions {
    [] -> Error(scenario.id <> ": actions must not be empty")
    [_, ..] -> {
      use _ <- result.try(
        list.try_fold(
          scenario.actions,
          #(set.new(), set.new()),
          fn(seen, action) {
            use action_ids <- result.try(unique_name(
              seen.0,
              action_id(action),
              scenario.id <> " action id",
            ))
            use reference_names <- result.try(case action {
              Retain(_, name, _) | RetainDetached(_, name, _) ->
                unique_name(seen.1, name, scenario.id <> " reference name")
              _ -> Ok(seen.1)
            })
            Ok(#(action_ids, reference_names))
          },
        ),
      )
      Ok(Nil)
    }
  }
}

fn unique_name(
  seen: set.Set(String),
  name: String,
  field: String,
) -> Result(set.Set(String), String) {
  case string.is_empty(name) || set.contains(seen, name) {
    True -> Error("empty or duplicate " <> field <> ": " <> name)
    False -> Ok(set.insert(seen, name))
  }
}

fn action_id(action: Action) -> String {
  case action {
    Retain(id, _, _) -> id
    RetainDetached(id, _, _) -> id
    Apply(id, _) -> id
    Observe(id) -> id
    Copy(id) -> id
  }
}

fn run_scenario(
  scenario: Scenario,
  next_scope: Int,
) -> Result(#(Json, Int), String) {
  use stored <- result.try(
    schema.stored_from_string(scenario.schema)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid schema: " <> string.inspect(error)
    }),
  )
  use view <- result.try(scope_id(next_scope))
  use tree <- result.try(
    forest.new(view, stored, scenario.root)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid initial forest: " <> string.inspect(error)
    }),
  )
  use execution <- result.try(run_actions(
    scenario.id,
    scenario.actions,
    Execution(tree, stored, [], 0, next_scope + 1, []),
  ))
  Ok(#(
    json.object([
      #("id", json.string(scenario.id)),
      #("checkpoints", array(list.reverse(execution.checkpoints))),
    ]),
    execution.next_scope,
  ))
}

fn run_actions(
  scenario_id: String,
  actions: List(Action),
  state: Execution,
) -> Result(Execution, String) {
  case actions {
    [] -> Ok(state)
    [action, ..rest] -> {
      let location = scenario_id <> "." <> action_id(action)
      use #(state, accepted) <- result.try(
        run_action(action, state)
        |> result.map_error(fn(error) { location <> ": " <> error }),
      )
      case accepted {
        True -> {
          use observation <- result.try(
            observe(state)
            |> result.map_error(fn(error) { location <> ": " <> error }),
          )
          let checkpoint =
            json.object([
              #("id", json.string(action_id(action))),
              #("accepted", json.bool(True)),
              #("state", observation),
            ])
          run_actions(
            scenario_id,
            rest,
            Execution(..state, checkpoints: [checkpoint, ..state.checkpoints]),
          )
        }
        False ->
          case rest {
            [] ->
              Ok(
                Execution(..state, checkpoints: [
                  json.object([
                    #("id", json.string(action_id(action))),
                    #("accepted", json.bool(False)),
                    #("state", json.null()),
                  ]),
                  ..state.checkpoints
                ]),
              )
            [_, ..] ->
              Error(location <> ": a refused action must end its scenario")
          }
      }
    }
  }
}

fn run_action(
  action: Action,
  state: Execution,
) -> Result(#(Execution, Bool), String) {
  case action {
    Retain(_, name, path) -> {
      use reference <- result.try(
        forest.locate(state.tree, path) |> native_error,
      )
      Ok(#(
        Execution(
          ..state,
          references: list.append(state.references, [
            Retained(name, reference, state.generation),
          ]),
        ),
        True,
      ))
    }
    RetainDetached(_, name, atom) -> {
      use reference <- result.try(
        forest.locate_detached(state.tree, atom) |> native_error,
      )
      Ok(#(
        Execution(
          ..state,
          references: list.append(state.references, [
            Retained(name, reference, state.generation),
          ]),
        ),
        True,
      ))
    }
    Apply(_, data) -> {
      use delta <- result.try(
        forest.delta(data)
        |> result.map_error(fn(error) {
          "invalid delta: " <> string.inspect(error)
        }),
      )
      case forest.apply_delta(state.tree, delta) {
        Ok(tree) -> Ok(#(Execution(..state, tree:), True))
        Error(_) -> Ok(#(state, False))
      }
    }
    Observe(_) -> Ok(#(state, True))
    Copy(_) -> {
      use data <- result.try(forest.export_data(state.tree) |> native_error)
      use view <- result.try(scope_id(state.next_scope))
      use tree <- result.try(
        forest.import_data(view, state.schema, data) |> native_error,
      )
      use _ <- result.try(
        list.try_each(state.references, fn(retained) {
          verify_foreign(tree, retained.reference)
        }),
      )
      Ok(#(
        Execution(
          ..state,
          tree:,
          generation: state.generation + 1,
          next_scope: state.next_scope + 1,
        ),
        True,
      ))
    }
  }
}

fn verify_foreign(
  tree: forest.Forest,
  reference: forest.NodeRef,
) -> Result(Nil, String) {
  case forest.read_node(tree, reference), forest.is_attached(tree, reference) {
    Error(types.InvalidEdit(_, _)), Error(types.InvalidEdit(_, _)) -> Ok(Nil)
    _, _ -> Error("copy retained a reference from the old scope")
  }
}

fn observe(state: Execution) -> Result(Json, String) {
  use data <- result.try(forest.export_data(state.tree) |> native_error)
  use references <- result.try(
    state.references
    |> list.sort(fn(left, right) {
      canonical_json.compare(left.name, right.name)
    })
    |> list.try_map(observe_reference(state)),
  )
  let detached =
    list.map(data.detached, fn(entry) {
      json.object([
        #("id", atom_to_json(entry.id)),
        #("forestRootId", json.int(entry.forest_root_id)),
        #(
          "latestRelevantRevision",
          revision_to_json(entry.latest_relevant_revision),
        ),
        #("value", fixtures.tree_value_to_json(entry.value)),
      ])
    })
  Ok(
    json.object([
      #("root", option_value_to_json(data.root)),
      #("references", array(references)),
      #("detached", array(detached)),
      #("nextDetachedRootId", json.int(data.next_detached_root_id)),
    ]),
  )
}

fn observe_reference(state: Execution) -> fn(Retained) -> Result(Json, String) {
  fn(retained: Retained) {
    case retained.generation == state.generation {
      False ->
        Ok(reference_json(retained.name, "invalidated-by-copy", json.null()))
      True ->
        case forest.read_node(state.tree, retained.reference) {
          Error(types.InvalidEdit(_, _)) ->
            Ok(reference_json(retained.name, "destroyed", json.null()))
          Error(error) -> native_error(Error(error))
          Ok(value) -> {
            use attached <- result.try(
              forest.is_attached(state.tree, retained.reference)
              |> native_error,
            )
            let status = case attached {
              True -> "attached"
              False -> "detached"
            }
            Ok(reference_json(
              retained.name,
              status,
              fixtures.tree_value_to_json(value),
            ))
          }
        }
    }
  }
}

fn reference_json(name: String, status: String, value: Json) -> Json {
  json.object([
    #("name", json.string(name)),
    #("status", json.string(status)),
    #("value", value),
  ])
}

fn atom_to_json(id: types.AtomId) -> Json {
  json.object([
    #("revision", revision_to_json(id.revision)),
    #("localId", json.int(id.local_id)),
  ])
}

fn revision_to_json(revision: Option(fluid_ids.StableId)) -> Json {
  case revision {
    None -> json.null()
    Some(revision) -> json.string(fluid_ids.stable_id_to_string(revision))
  }
}

fn option_value_to_json(value: Option(types.TreeValue)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> fixtures.tree_value_to_json(value)
  }
}

fn scope_id(value: Int) -> Result(fluid_ids.StableId, String) {
  use suffix <- result.try(
    int.to_base_string(value, 16)
    |> result.map_error(fn(_) { "could not encode test scope" }),
  )
  let raw = "00000000-0000-4000-8000-" <> string.pad_start(suffix, 12, "0")
  fluid_ids.stable_id(raw)
  |> result.map_error(fn(error) {
    "could not create test scope: " <> string.inspect(error)
  })
}

fn native_error(value: Result(a, types.TreeError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
