import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/optional_field
import watershed/tree/runtime
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{
  type SequencePoint, type TreeError, AtomId, NumberValue, ObjectValue,
  SequencePoint, SetField, StringValue,
}
import watershed/tree_kernel

type SchemaEntry {
  SchemaEntry(id: String, raw: String)
}

type Scenario {
  Scenario(id: String, stored: String, requested: String, operation: String)
}

type RawProbe {
  RawProbe(id: String, raw: String)
}

type Input {
  Input(
    schemas: List(SchemaEntry),
    scenarios: List(Scenario),
    refusals: List(Scenario),
    raw_probes: List(RawProbe),
  )
}

type ObservationStatus {
  ObservationStatus(
    id: String,
    can_view: Bool,
    can_upgrade: Bool,
    is_equivalent: Bool,
  )
}

type AlgebraState {
  AlgebraState(
    originator: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
    schema_change: shared_change.TaggedChange,
    data_change: shared_change.TaggedChange,
    second_data_revision: fluid_ids.StableId,
    second_schema_change: shared_change.TaggedChange,
    empty_change: shared_change.TaggedChange,
    inverse_revision: fluid_ids.StableId,
    identity_order: change.IdentityOrder,
    schema_encodings: List(SchemaEncoding),
  )
}

type SchemaEncoding {
  SchemaEncoding(
    before: schema.SchemaState,
    after: schema.SchemaState,
    old: JsonValue,
    new: JsonValue,
  )
}

pub fn run_compatibility(input: Json) -> Result(Json, String) {
  use input <- result.try(
    json.parse(json.to_string(input), input_decoder())
    |> result.map_error(fn(error) {
      "invalid schema evolution fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(validate_input(input))
  let catalog =
    input.schemas
    |> list.map(fn(entry) { #(entry.id, entry.raw) })
    |> dict.from_list
  use observations <- result.try(
    list.try_map(input.scenarios, fn(scenario) {
      run_scenario(catalog, scenario)
    }),
  )
  use refusals <- result.try(
    list.try_map(input.refusals, fn(scenario) {
      run_refusal_scenario(catalog, scenario)
    }),
  )
  let assert [first, ..] = input.scenarios
  use baseline_raw <- result.try(find_schema(catalog, first.stored))
  use baseline <- result.try(
    schema.view_from_string(baseline_raw)
    |> result.map_error(fn(error) {
      "invalid raw probe baseline: " <> string.inspect(error)
    }),
  )
  use raw_probes <- result.try(
    list.try_map(input.raw_probes, fn(probe) { run_raw_probe(probe, baseline) }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
      #("refusals", json.array(refusals, fn(value) { value })),
      #("rawProbes", json.array(raw_probes, fn(value) { value })),
    ]),
  )
}

pub fn run_algebra(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "schemas", "revisions", "operands", "transitions", "scenarios",
    ]),
  )
  use state <- result.try(algebra_state(input))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(scenarios, fn(scenario) {
      use _ <- result.try(fixture_codec.exact(scenario, ["id"]))
      use id <- result.try(fixture_codec.field(
        scenario,
        "id",
        fixture_codec.text,
      ))
      run_algebra_scenario(id, state)
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

type HistoryClient {
  HistoryClient(
    index: Int,
    state: tree_kernel.TreeState,
    session: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
    view: schema.ViewSchema,
    next_revision: Int,
    next_rollback: Int,
    events: List(String),
    listening: Bool,
    listen_on_upgrade: Bool,
    connected: Bool,
    paused: Bool,
    backlog: List(#(HistoryMessage, HistoryPoint)),
  )
}

type HistoryMessage {
  HistoryMessage(sender: Int, commit: history.Commit)
}

type HistoryPoint {
  HistoryPoint(
    point: SequencePoint,
    reference_sequence_number: Int,
    minimum_sequence_number: Int,
  )
}

type HistoryDriver {
  HistoryDriver(
    clients: List(HistoryClient),
    queue: List(HistoryMessage),
    points: List(HistoryPoint),
    identities: Json,
    catalog: dict.Dict(String, schema.StoredSchema),
    extras: List(#(String, Json)),
  )
}

type HistoryAllocation {
  HistoryAllocation(
    session: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
    revisions: List(fluid_ids.StableId),
    next: Int,
  )
}

pub fn run_history(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "schemas", "scenarios", "initialRoot", "initializationHistory",
      "rollbackReplay",
    ]),
  )
  use catalog <- result.try(algebra_schema_catalog(input))
  use root <- result.try(fixture_codec.get(input, "initialRoot"))
  use initialization <- result.try(fixture_codec.get(
    input,
    "initializationHistory",
  ))
  use initial <- result.try(
    dict.get(catalog, "v1")
    |> result.map_error(fn(_) { "history schema v1 is missing" }),
  )
  use root <- result.try(
    json.parse(
      json.to_string(json_ot.to_json(root)),
      fixtures.tree_value_decoder(),
    )
    |> result.map_error(string.inspect),
  )
  use root <- result.try(normalize_tree(initial, root))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(scenarios, fn(scenario) {
      use id <- result.try(fixture_codec.field(
        scenario,
        "id",
        fixture_codec.text,
      ))
      run_history_scenario(scenario, catalog, initial, root, initialization)
      |> result.map_error(fn(error) { id <> ": " <> error })
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

pub fn history_projection(value: Json) -> Result(Json, String) {
  use value <- result.try(
    json.parse(json.to_string(value), json_ot.decoder())
    |> result.map_error(string.inspect),
  )
  use observations <- result.try(fixture_codec.field(
    value,
    "observations",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(observations, fn(observation) {
      case observation {
        VObject(fields) ->
          Ok(
            VObject(
              list.filter(fields, fn(entry) {
                !list.contains(
                  [
                    "acceptedMessage", "replay", "continuation",
                    "historicalDecode",
                  ],
                  entry.0,
                )
              }),
            ),
          )
        _ -> Error("history observation must be an object")
      }
    }),
  )
  Ok(
    json_ot.to_json(
      VObject([
        #("observations", VArray(observations)),
      ]),
    ),
  )
}

fn run_history_scenario(
  scenario: JsonValue,
  catalog: dict.Dict(String, schema.StoredSchema),
  initial: schema.StoredSchema,
  root: types.TreeValue,
  initialization: JsonValue,
) -> Result(Json, String) {
  use id <- result.try(fixture_codec.field(scenario, "id", fixture_codec.text))
  use sessions <- result.try(fixture_codec.get(scenario, "sessions"))
  use clients <- result.try(history_clients(
    sessions,
    initial,
    root,
    initialization,
  ))
  use points <- result.try(fixture_codec.field(
    scenario,
    "sequencePoints",
    history_points,
  ))
  use actions <- result.try(fixture_codec.field(
    scenario,
    "actions",
    fixture_codec.items,
  ))
  let clients = initialize_history_listeners(clients, actions)
  use driver <- result.try(
    list.try_fold(
      list.index_map(actions, fn(action, index) { #(action, index + 1) }),
      HistoryDriver(clients, [], points, json_ot.to_json(sessions), catalog, []),
      fn(driver, entry) {
        run_history_action(id, driver, entry.0)
        |> result.map_error(fn(error) {
          id <> "/action-" <> int.to_string(entry.1) <> ": " <> error
        })
      },
    ),
  )
  use driver <- result.try(finish_history_scenario(actions, driver))
  history_observation(id, actions, driver)
}

fn history_clients(
  value: JsonValue,
  initial: schema.StoredSchema,
  root: types.TreeValue,
  initialization: JsonValue,
) -> Result(List(HistoryClient), String) {
  use entries <- result.try(fixture_codec.items(value))
  use clients <- result.try(
    entries
    |> list.index_map(fn(entry, index) { #(entry, index) })
    |> list.try_map(fn(indexed) {
      let #(entry, index) = indexed
      use session <- result.try(
        fixture_codec.field(entry, "session", fn(value) {
          use value <- result.try(fixture_codec.text(value))
          fluid_ids.session_id(value) |> result.map_error(string.inspect)
        }),
      )
      use compressor <- result.try(
        fixture_codec.field(entry, "compressor", fn(value) {
          use encoded <- result.try(fixture_codec.field(
            value,
            "state",
            fixture_codec.text,
          ))
          case fluid_ids.deserialize(json.string(encoded), session) {
            Ok(compressor) -> Ok(compressor)
            Error(fluid_ids.SessionMismatch) -> {
              use fresh <- result.try(
                fluid_ids.session_id(case index {
                  0 -> "30000000-0000-4000-8000-000000000010"
                  _ -> "30000000-0000-4000-8000-000000000011"
                })
                |> result.map_error(string.inspect),
              )
              fluid_ids.deserialize(json.string(encoded), fresh)
              |> result.map_error(fn(error) {
                "compressor "
                <> int.to_string(index)
                <> ": "
                <> string.inspect(error)
              })
            }
            Error(error) ->
              Error(
                "compressor "
                <> int.to_string(index)
                <> ": "
                <> string.inspect(error),
              )
          }
        }),
      )
      use view <- result.try(
        schema.view_from_json(schema.stored_to_json(initial))
        |> result.map_error(string.inspect),
      )
      use view_id <- result.try(
        fluid_ids.stable_id(case index {
          0 -> "00000000-0000-4000-8000-000000000010"
          _ -> "00000000-0000-4000-8000-000000000011"
        })
        |> result.map_error(string.inspect),
      )
      use history <- result.try(initial_history_snapshot(
        initialization,
        compressor,
        initial,
      ))
      let snapshot =
        tree_kernel.snapshot_from_parts(
          view_id,
          initial,
          forest.ForestData(Some(root), [], 0),
          history,
        )
      use snapshot <- result.try(snapshot |> result.map_error(string.inspect))
      use state <- result.try(
        tree_kernel.restore(snapshot, view_id, session, view)
        |> result.map_error(string.inspect),
      )
      use #(state, _) <- result.try(
        tree_kernel.advance_document(state, 2, 0, Nil, fn(_) {
          Error(types.InvalidHistory("unexpected bootstrap allocation"))
        })
        |> result.map_error(string.inspect),
      )
      Ok(
        HistoryClient(
          index,
          state,
          session,
          compressor,
          view,
          case index {
            0 -> 2
            _ -> 1
          },
          0,
          [],
          False,
          False,
          True,
          False,
          [],
        ),
      )
    }),
  )
  case clients {
    [_, _] -> Ok(clients)
    _ -> Error("history scenario must contain two sessions")
  }
}

fn initial_history_snapshot(
  initialization: JsonValue,
  compressor: fluid_ids.Compressor,
  initial: schema.StoredSchema,
) -> Result(history.HistorySnapshot, String) {
  use messages <- result.try(fixture_codec.field(
    initialization,
    "messages",
    fixture_codec.items,
  ))
  use operation <- result.try(case messages {
    [_, operation, ..] -> Ok(operation)
    _ -> Error("initialization operation is missing")
  })
  use contents <- result.try(fixture_codec.get(operation, "contents"))
  use message <- result.try(
    codec.decode_message_with_schema(
      json.to_string(json_ot.to_json(contents)),
      codec.DecodeContext(codec.Fluid310, compressor),
      initial,
    )
    |> result.map_error(string.inspect),
  )
  use commit <- result.try(
    runtime.wire_to_commit(message.commit)
    |> result.map_error(string.inspect),
  )
  Ok(history.HistorySnapshot(
    history.InitialBase,
    [history.SequencedCommit(commit, SequencePoint(2, 0))],
    [],
    2,
    0,
  ))
}

fn history_points(value: JsonValue) -> Result(List(HistoryPoint), String) {
  use values <- result.try(fixture_codec.items(value))
  history_operation_points(values)
}

fn history_operation_points(
  values: List(JsonValue),
) -> Result(List(HistoryPoint), String) {
  case values {
    [] -> Ok([])
    [first, second, ..rest] -> {
      use same <- result.try(same_history_submission(first, second))
      case same {
        True -> {
          use point <- result.try(decode_history_point(second))
          use rest <- result.try(history_operation_points(rest))
          Ok(case point {
            None -> rest
            Some(point) -> [point, ..rest]
          })
        }
        False -> {
          use point <- result.try(decode_history_point(first))
          use rest <- result.try(history_operation_points([second, ..rest]))
          Ok(case point {
            None -> rest
            Some(point) -> [point, ..rest]
          })
        }
      }
    }
    [first] -> {
      use point <- result.try(decode_history_point(first))
      Ok(case point {
        None -> []
        Some(point) -> [point]
      })
    }
  }
}

fn same_history_submission(
  first: JsonValue,
  second: JsonValue,
) -> Result(Bool, String) {
  use first_sequence <- result.try(fixture_codec.field(
    first,
    "clientSequenceNumber",
    fixture_codec.integer,
  ))
  use second_sequence <- result.try(fixture_codec.field(
    second,
    "clientSequenceNumber",
    fixture_codec.integer,
  ))
  use first_client <- result.try(fixture_codec.field(
    first,
    "clientId",
    fixture_codec.text,
  ))
  use second_client <- result.try(fixture_codec.field(
    second,
    "clientId",
    fixture_codec.text,
  ))
  Ok(first_sequence == second_sequence && first_client == second_client)
}

fn decode_history_point(
  value: JsonValue,
) -> Result(Option(HistoryPoint), String) {
  use raw_sequence <- result.try(fixture_codec.get(value, "sequenceNumber"))
  case raw_sequence {
    VNull -> Ok(None)
    VNumber(NInt(sequence)) -> {
      use batch <- result.try(fixture_codec.field(
        value,
        "indexInBatch",
        fixture_codec.integer,
      ))
      use reference <- result.try(fixture_codec.field(
        value,
        "referenceSequenceNumber",
        fixture_codec.integer,
      ))
      use minimum <- result.try(fixture_codec.field(
        value,
        "minimumSequenceNumber",
        fixture_codec.integer,
      ))
      Ok(Some(HistoryPoint(SequencePoint(sequence, batch), reference, minimum)))
    }
    _ -> Error("history sequence number must be an integer or null")
  }
}

fn run_history_action(
  scenario: String,
  driver: HistoryDriver,
  action: JsonValue,
) -> Result(HistoryDriver, String) {
  use operation <- result.try(fixture_codec.field(
    action,
    "op",
    fixture_codec.text,
  ))
  case operation {
    "upgrade" -> {
      let tree = action_tree(action)
      use schema_id <- result.try(fixture_codec.field(
        action,
        "schema",
        fixture_codec.text,
      ))
      author_schema(driver, tree, schema_id)
    }
    "set" -> {
      let tree = action_tree(action)
      use path <- result.try(action_path(action))
      use value <- result.try(fixture_codec.get(action, "value"))
      use value <- result.try(history_edit_value(value))
      author_data(driver, tree, path, value)
    }
    "sequence" ->
      case fixture_codec.get(action, "order") {
        Ok(VString("tree-0-first")) -> {
          let driver =
            HistoryDriver(
              ..driver,
              queue: list.append(
                list.filter(driver.queue, fn(message) { message.sender == 0 }),
                list.filter(driver.queue, fn(message) { message.sender != 0 }),
              ),
            )
          use losing <- result.try(history_client(driver.clients, 1))
          use before <- result.try(history_forest_json(losing))
          use before_schema <- result.try(history_schema_id(
            driver.catalog,
            tree_kernel.stored_schema(losing.state),
          ))
          use before_pending <- result.try(history_commits_json(
            tree_kernel.history_view(losing.state).pending,
            losing,
          ))
          use #(retained_value, retained_content) <- result.try(
            history_visible_extra(losing),
          )
          let driver =
            put_history_extras(driver, [
              #("losingAuthorBefore", before),
              #("losingAuthorSchema", json.string(before_schema)),
              #(
                "losingAuthorPending",
                json.array(before_pending, fn(value) { value }),
              ),
              #(
                "pendingBeforeCompetingEdit",
                json.array(before_pending, fn(value) { value }),
              ),
              #("_retainedExtraValue", json.string(retained_value)),
              #("_retainedExtraContent", retained_content),
            ])
          use driver <- result.try(sequence_one(driver))
          use losing <- result.try(history_client(driver.clients, 1))
          use after_pending <- result.try(history_commits_json(
            tree_kernel.history_view(losing.state).pending,
            losing,
          ))
          let driver =
            put_history_extras(driver, [
              #(
                "pendingAfterCompetingEdit",
                json.array(after_pending, fn(value) { value }),
              ),
            ])
          use driver <- result.try(sequence_all(driver))
          use losing <- result.try(history_client(driver.clients, 1))
          use schema_id <- result.try(history_schema_id(
            driver.catalog,
            tree_kernel.stored_schema(losing.state),
          ))
          set_view(driver, 1, schema_id)
        }
        _ -> sequence_all(driver)
      }
    "sequence-through" -> {
      use change <- result.try(fixture_codec.field(
        action,
        "change",
        fixture_codec.text,
      ))
      case change {
        "schema" -> {
          use driver <- result.try(sequence_one(driver))
          capture_acknowledged_schema(driver)
        }
        "id-allocation" -> Ok(driver)
        _ -> Error("unsupported sequence-through change " <> change)
      }
    }
    "disconnect" -> set_connection(driver, action_tree(action), False)
    "reconnect" -> reconnect_client(driver, action_tree(action))
    "pause-inbound" -> set_paused(driver, action_tree(action), True)
    "resume-inbound" -> resume_client(driver, action_tree(action))
    "observe-view" ->
      set_history_listener(driver, action_tree(action), True, False)
    "dispose-view" ->
      set_history_listener(driver, action_tree(action), False, False)
    "open-view" -> {
      let tree = action_tree(action)
      use schema_id <- result.try(fixture_codec.field(
        action,
        "schema",
        fixture_codec.text,
      ))
      use driver <- result.try(set_view(driver, tree, schema_id))
      use driver <- result.try(set_history_listener(driver, tree, True, True))
      capture_reopened_peer(driver, tree)
    }
    "summarize" -> validate_history_summary(driver, action_tree(action))
    "load-summary" | "replay-tail" | "decode" -> Ok(driver)
    _ -> Error(scenario <> ": unknown history operation " <> operation)
  }
}

fn action_tree(action: JsonValue) -> Int {
  case fixture_codec.field(action, "tree", fixture_codec.integer) {
    Ok(value) -> value
    Error(_) -> 0
  }
}

fn initialize_history_listeners(
  clients: List(HistoryClient),
  actions: List(JsonValue),
) -> List(HistoryClient) {
  let rollback =
    list.any(actions, fn(action) {
      fixture_codec.field(action, "order", fixture_codec.text)
      == Ok("tree-0-first")
    })
  let pending_summary = history_summary_before_sequence(actions)
  let upgrade_before_sequence = history_upgrade_before_sequence(actions, 0)
  clients
  |> list.index_map(fn(client, index) {
    case index {
      0 ->
        HistoryClient(
          ..client,
          listening: !rollback && !pending_summary && !upgrade_before_sequence,
          listen_on_upgrade: !rollback
            && !pending_summary
            && upgrade_before_sequence,
        )
      _ -> client
    }
  })
}

fn history_summary_before_sequence(actions: List(JsonValue)) -> Bool {
  case actions {
    [] -> False
    [action, ..rest] ->
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok("sequence") | Ok("sequence-through") -> False
        Ok("summarize") -> True
        _ -> history_summary_before_sequence(rest)
      }
  }
}

fn history_upgrade_before_sequence(
  actions: List(JsonValue),
  index: Int,
) -> Bool {
  case actions {
    [] -> False
    [action, ..rest] ->
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok("sequence") | Ok("sequence-through") -> False
        Ok("upgrade") ->
          case action_tree(action) == index {
            True -> True
            False -> history_upgrade_before_sequence(rest, index)
          }
        _ -> history_upgrade_before_sequence(rest, index)
      }
  }
}

fn history_edit_value(value: JsonValue) -> Result(types.TreeValue, String) {
  case value {
    VString(value) -> Ok(StringValue(value))
    VNumber(NInt(value)) -> Ok(NumberValue(int.to_float(value)))
    VNumber(NFloat(value)) -> Ok(NumberValue(value))
    _ -> Error("history edit value is not supported")
  }
}

fn author_schema(
  driver: HistoryDriver,
  index: Int,
  schema_id: String,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  use after <- result.try(
    dict.get(driver.catalog, schema_id)
    |> result.map_error(fn(_) { "unknown history schema " <> schema_id }),
  )
  use revision <- result.try(
    history_revision(client)
    |> result.map_error(fn(error) { "schema revision: " <> error }),
  )
  use order <- result.try(
    history_order(client, revision)
    |> result.map_error(fn(error) { "schema order: " <> error }),
  )
  use outer <- result.try(
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(tree_kernel.stored_schema(client.state)),
        schema.FixedSchema(after),
        False,
      ),
    ])
    |> result.map_error(string.inspect),
  )
  use #(state, commit, events) <- result.try(
    tree_kernel.apply_local_change(client.state, revision, order, outer)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_json(schema.stored_to_json(after))
    |> result.map_error(string.inspect),
  )
  let client =
    HistoryClient(
      ..client,
      state:,
      view:,
      next_revision: client.next_revision + 1,
      events: case client.listen_on_upgrade {
        True -> append_history_events(client.events, events.events)
        False -> client.events
      },
      listening: client.listen_on_upgrade,
      listen_on_upgrade: False,
    )
  enqueue_authored(
    HistoryDriver(
      ..driver,
      clients: put_history_client(driver.clients, index, client),
    ),
    index,
    commit,
  )
}

fn author_data(
  driver: HistoryDriver,
  index: Int,
  path: List(String),
  value: types.TreeValue,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  use revision <- result.try(
    history_revision(client)
    |> result.map_error(fn(error) { "data revision: " <> error }),
  )
  use order <- result.try(
    history_order(client, revision)
    |> result.map_error(fn(error) { "data order: " <> error }),
  )
  use #(state, commit, events) <- result.try(
    tree_kernel.apply_local(client.state, revision, order, case path, value {
      ["extra", "value"], StringValue(value) ->
        SetField(
          ["extra"],
          ObjectValue("org.watershed.shared-tree.m4.Extra", [
            #("value", StringValue(value)),
          ]),
        )
      _, _ -> SetField(path, value)
    })
    |> result.map_error(string.inspect),
  )
  let client =
    HistoryClient(
      ..client,
      state:,
      next_revision: client.next_revision + 1,
      events: case client.listening {
        True -> append_history_events(client.events, events.events)
        False -> client.events
      },
    )
  enqueue_authored(
    HistoryDriver(
      ..driver,
      clients: put_history_client(driver.clients, index, client),
    ),
    index,
    commit,
  )
}

fn history_revision(
  client: HistoryClient,
) -> Result(fluid_ids.StableId, String) {
  local_stable_id(client.session, client.next_revision)
}

fn local_stable_id(
  session: fluid_ids.SessionId,
  generation: Int,
) -> Result(fluid_ids.StableId, String) {
  use #(compressor, id) <- result.try(
    generate_local_id(fluid_ids.new(session), generation)
    |> result.map_error(string.inspect),
  )
  fluid_ids.decompress(compressor, id)
  |> result.map_error(string.inspect)
}

fn generate_local_id(
  compressor: fluid_ids.Compressor,
  remaining: Int,
) -> Result(
  #(fluid_ids.Compressor, fluid_ids.SessionSpaceId),
  fluid_ids.IdError,
) {
  use #(compressor, id) <- result.try(fluid_ids.generate(compressor))
  case remaining {
    1 -> Ok(#(compressor, id))
    _ -> generate_local_id(compressor, remaining - 1)
  }
}

fn history_order(
  client: HistoryClient,
  revision: fluid_ids.StableId,
) -> Result(change.IdentityOrder, String) {
  codec.identity_order(
    [revision, ..tree_kernel.identity_revisions(client.state)],
    client.compressor,
    "history identity order",
  )
  |> result.map_error(string.inspect)
}

fn enqueue_authored(
  driver: HistoryDriver,
  sender: Int,
  commit: history.Commit,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, sender))
  case client.connected {
    True ->
      Ok(
        HistoryDriver(
          ..driver,
          queue: list.append(driver.queue, [HistoryMessage(sender, commit)]),
        ),
      )
    False -> Ok(driver)
  }
}

fn sequence_all(driver: HistoryDriver) -> Result(HistoryDriver, String) {
  case driver.queue {
    [] -> Ok(driver)
    _ -> {
      use driver <- result.try(sequence_one(driver))
      sequence_all(driver)
    }
  }
}

fn sequence_one(driver: HistoryDriver) -> Result(HistoryDriver, String) {
  case driver.queue, driver.points {
    [], _ -> Ok(driver)
    _, [] -> Error("history sequence metadata is exhausted")
    [message, ..queue], [point, ..points] -> {
      use clients <- result.try(advance_history_clients(
        driver.clients,
        point.point.sequence_number - 1,
        point.minimum_sequence_number,
      ))
      use clients <- result.try(deliver_history_message(clients, message, point))
      Ok(HistoryDriver(..driver, clients:, queue:, points:))
    }
  }
}

fn advance_history_clients(
  clients: List(HistoryClient),
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(List(HistoryClient), String) {
  list.try_map(clients, fn(client) {
    case client.connected, client.paused {
      True, False -> {
        let allocation =
          HistoryAllocation(
            client.session,
            client.compressor,
            tree_kernel.identity_revisions(client.state),
            case client.next_rollback {
              0 -> 0 - client.next_revision
              next -> next
            },
          )
        use #(state, allocation) <- result.try(
          tree_kernel.advance_document(
            client.state,
            sequence_number,
            minimum_sequence_number,
            allocation,
            mint_history_revision,
          )
          |> result.map_error(string.inspect),
        )
        Ok(HistoryClient(..client, state:, next_rollback: allocation.next))
      }
      _, _ -> Ok(client)
    }
  })
}

fn deliver_history_message(
  clients: List(HistoryClient),
  message: HistoryMessage,
  point: HistoryPoint,
) -> Result(List(HistoryClient), String) {
  clients
  |> list.index_map(fn(client, index) { #(client, index) })
  |> list.try_map(fn(entry) {
    let #(client, index) = entry
    case client.connected, client.paused {
      False, _ -> Ok(client)
      True, True ->
        Ok(
          HistoryClient(
            ..client,
            backlog: list.append(client.backlog, [#(message, point)]),
          ),
        )
      True, False -> receive_history_message(client, index, message, point)
    }
  })
}

fn receive_history_message(
  client: HistoryClient,
  _index: Int,
  message: HistoryMessage,
  point: HistoryPoint,
) -> Result(HistoryClient, String) {
  use order <- result.try(
    codec.identity_order(
      [
        message.commit.revision,
        ..list.append(
          shared_change.identity_revisions(message.commit.change),
          tree_kernel.identity_revisions(client.state),
        )
      ],
      client.compressor,
      "history receive identity order",
    )
    |> result.map_error(string.inspect),
  )
  let allocation =
    HistoryAllocation(
      client.session,
      client.compressor,
      [
        message.commit.revision,
        ..list.append(
          shared_change.identity_revisions(message.commit.change),
          tree_kernel.identity_revisions(client.state),
        )
      ],
      case client.next_rollback {
        0 -> 0 - client.next_revision
        next -> next
      },
    )
  use #(state, events, allocation) <- result.try(
    tree_kernel.receive_ordered(
      client.state,
      message.commit,
      order,
      point.point,
      point.reference_sequence_number,
      point.minimum_sequence_number,
      allocation,
      mint_history_revision,
    )
    |> result.map_error(string.inspect),
  )
  Ok(
    HistoryClient(
      ..client,
      state:,
      next_rollback: allocation.next,
      events: case client.listening {
        True -> append_history_events(client.events, events.events)
        False -> client.events
      },
    ),
  )
}

fn mint_history_revision(
  allocation: HistoryAllocation,
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, HistoryAllocation),
  TreeError,
) {
  use revision <- result.try(
    local_stable_id(allocation.session, 0 - allocation.next)
    |> result.map_error(fn(detail) {
      types.CorruptData("history rollback revision", detail)
    }),
  )
  use order <- result.try(codec.identity_order(
    [revision, ..allocation.revisions],
    allocation.compressor,
    "history rollback identity order",
  ))
  Ok(#(
    revision,
    order,
    HistoryAllocation(
      ..allocation,
      revisions: [revision, ..allocation.revisions],
      next: allocation.next - 1,
    ),
  ))
}

fn set_connection(
  driver: HistoryDriver,
  index: Int,
  connected: Bool,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  Ok(
    HistoryDriver(
      ..driver,
      clients: put_history_client(
        driver.clients,
        index,
        HistoryClient(..client, connected:),
      ),
    ),
  )
}

fn reconnect_client(
  driver: HistoryDriver,
  index: Int,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  let driver =
    HistoryDriver(
      ..driver,
      clients: put_history_client(
        driver.clients,
        index,
        HistoryClient(..client, connected: True),
      ),
    )
  use driver <- result.try(sequence_all(driver))
  use client <- result.try(history_client(driver.clients, index))
  use commits <- result.try(
    tree_kernel.resubmit_commits(client.state)
    |> result.map_error(string.inspect),
  )
  Ok(
    HistoryDriver(
      ..driver,
      queue: list.append(
        driver.queue,
        list.map(commits, fn(commit) { HistoryMessage(index, commit) }),
      ),
    ),
  )
}

fn set_paused(
  driver: HistoryDriver,
  index: Int,
  paused: Bool,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  Ok(
    HistoryDriver(
      ..driver,
      clients: put_history_client(
        driver.clients,
        index,
        HistoryClient(..client, paused:),
      ),
    ),
  )
}

fn resume_client(
  driver: HistoryDriver,
  index: Int,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  let backlog = client.backlog
  let client = HistoryClient(..client, paused: False, backlog: [])
  use client <- result.try(
    list.try_fold(backlog, client, fn(client, entry) {
      receive_history_message(client, index, entry.0, entry.1)
    }),
  )
  Ok(
    HistoryDriver(
      ..driver,
      clients: put_history_client(driver.clients, index, client),
    ),
  )
}

fn set_view(
  driver: HistoryDriver,
  index: Int,
  schema_id: String,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  use stored <- result.try(
    dict.get(driver.catalog, schema_id)
    |> result.map_error(fn(_) { "unknown history view schema " <> schema_id }),
  )
  use view <- result.try(
    schema.view_from_json(schema.stored_to_json(stored))
    |> result.map_error(string.inspect),
  )
  Ok(
    HistoryDriver(
      ..driver,
      clients: put_history_client(
        driver.clients,
        index,
        HistoryClient(..client, view:),
      ),
    ),
  )
}

fn set_history_listener(
  driver: HistoryDriver,
  index: Int,
  listening: Bool,
  clear: Bool,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  Ok(
    HistoryDriver(
      ..driver,
      clients: put_history_client(
        driver.clients,
        index,
        HistoryClient(
          ..client,
          listening:,
          listen_on_upgrade: False,
          events: case clear {
            True -> []
            False -> client.events
          },
        ),
      ),
    ),
  )
}

fn validate_history_summary(
  driver: HistoryDriver,
  index: Int,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  use snapshot <- result.try(
    tree_kernel.snapshot(client.state) |> result.map_error(string.inspect),
  )
  let #(_, _, _) = tree_kernel.snapshot_parts(snapshot)
  Ok(driver)
}

fn finish_history_scenario(
  actions: List(JsonValue),
  driver: HistoryDriver,
) -> Result(HistoryDriver, String) {
  case driver.points, list.last(actions) {
    [], _ -> Ok(driver)
    _, Ok(action) ->
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok("sequence-through") -> Ok(driver)
        _ -> sequence_all(driver)
      }
    _, Error(Nil) -> Ok(driver)
  }
}

fn capture_acknowledged_schema(
  driver: HistoryDriver,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, 0))
  case tree_kernel.history_view(client.state).pending {
    [commit] ->
      case shared_change.to_changes(commit.change) {
        [shared_change.DataChange(_)] -> {
          use remaining <- result.try(history_commit_json(commit, client))
          Ok(
            put_history_extras(driver, [
              #("acknowledgedSchema", json.bool(True)),
              #("remainingDependentEdit", remaining),
            ]),
          )
        }
        _ -> Ok(driver)
      }
    _ -> Ok(driver)
  }
}

fn capture_reopened_peer(
  driver: HistoryDriver,
  index: Int,
) -> Result(HistoryDriver, String) {
  use client <- result.try(history_client(driver.clients, index))
  use root <- result.try(history_forest_json(client))
  use schema_id <- result.try(history_schema_id(
    driver.catalog,
    tree_kernel.stored_schema(client.state),
  ))
  use compatibility <- result.try(
    schema.compatibility(tree_kernel.stored_schema(client.state), client.view)
    |> result.map_error(string.inspect),
  )
  use compatibility <- result.try(history_compatibility_json(
    tree_kernel.stored_schema(client.state),
    client.view,
    compatibility,
  ))
  Ok(
    put_history_extras(driver, [
      #(
        "reopenedPeer",
        json.object([
          #("tree", json.string("tree-" <> int.to_string(index))),
          #("schema", json.string(schema_id)),
          #("root", root),
          #("compatibility", compatibility),
        ]),
      ),
    ]),
  )
}

fn put_history_extras(
  driver: HistoryDriver,
  additions: List(#(String, Json)),
) -> HistoryDriver {
  let names = list.map(additions, fn(entry) { entry.0 })
  HistoryDriver(
    ..driver,
    extras: list.append(
      list.filter(driver.extras, fn(entry) { !list.contains(names, entry.0) }),
      additions,
    ),
  )
}

fn history_observation(
  id: String,
  actions: List(JsonValue),
  driver: HistoryDriver,
) -> Result(Json, String) {
  let local_index = history_observation_index(actions)
  let peer_index = case local_index {
    0 -> 1
    _ -> 0
  }
  use local <- result.try(history_client(driver.clients, local_index))
  use peer <- result.try(history_client(driver.clients, peer_index))
  use observer <- result.try(history_observer(driver.clients, actions, local))
  use visible_schema <- result.try(history_schema_id(
    driver.catalog,
    tree_kernel.stored_schema(local.state),
  ))
  use snapshot <- result.try(
    tree_kernel.snapshot(local.state)
    |> result.map_error(fn(error) { "snapshot: " <> string.inspect(error) }),
  )
  let #(sequenced_schema, _, _) = tree_kernel.snapshot_parts(snapshot)
  use sequenced_schema <- result.try(history_schema_id(
    driver.catalog,
    sequenced_schema,
  ))
  use visible_root <- result.try(
    history_forest_json(local)
    |> result.map_error(fn(error) { "visible root: " <> error }),
  )
  let local_history = tree_kernel.history_view(local.state)
  let peer_history = tree_kernel.history_view(peer.state)
  use pending <- result.try(
    history_commits_json(local_history.pending, local)
    |> result.map_error(fn(error) { "pending: " <> error }),
  )
  use trunk <- result.try(
    history_sequenced_json(peer_history.sequenced.trunk, peer)
    |> result.map_error(fn(error) { "trunk: " <> error }),
  )
  use peer_trunk <- result.try(
    history_sequenced_json(peer_history.sequenced.trunk, peer)
    |> result.map_error(fn(error) { "peer trunk: " <> error }),
  )
  use compatibility <- result.try(
    schema.compatibility(tree_kernel.stored_schema(local.state), observer.view)
    |> result.map_error(fn(error) { "compatibility: " <> string.inspect(error) }),
  )
  let outer =
    list.append(
      local_history.pending,
      list.map(local_history.sequenced.trunk, fn(entry) { entry.commit }),
    )
    |> unique_history_commits
  use outer <- result.try(
    history_outer_commits_json(outer, local)
    |> result.map_error(fn(error) { "outer: " <> error }),
  )
  use detached <- result.try(history_detached_json(local))
  use compatibility <- result.try(history_compatibility_json(
    tree_kernel.stored_schema(local.state),
    observer.view,
    compatibility,
  ))
  use special <- result.try(history_special_fields(driver, peer))
  let fields = [
    #("id", json.string(id)),
    #("visibleSchema", json.string(visible_schema)),
    #("sequencedSchema", json.string(sequenced_schema)),
    #("visibleRoot", visible_root),
    #("pendingRevisions", json.array(pending, fn(value) { value })),
    #("outerChanges", json.array(outer, fn(value) { value })),
    #("trunkRevisions", json.array(trunk, fn(value) { value })),
    #("peerRevisions", json.array(peer_trunk, fn(value) { value })),
    #("detachedIdentities", detached),
    #("compatibility", compatibility),
    #("events", json.array(observer.events, json.string)),
    #("identities", driver.identities),
    ..list.append(
      list.filter(driver.extras, fn(entry) { !string.starts_with(entry.0, "_") }),
      special,
    )
  ]
  Ok(json.object(fields))
}

fn unique_history_commits(
  commits: List(history.Commit),
) -> List(history.Commit) {
  case commits {
    [] -> []
    [first, ..rest] -> [
      first,
      ..unique_history_commits(
        list.filter(rest, fn(commit) { commit.revision != first.revision }),
      )
    ]
  }
}

fn history_observation_index(actions: List(JsonValue)) -> Int {
  case
    list.find(actions, fn(action) {
      fixture_codec.field(action, "order", fixture_codec.text)
      == Ok("tree-0-first")
    })
  {
    Ok(_) -> 1
    Error(Nil) ->
      actions
      |> list.reverse
      |> list.find(fn(action) {
        case fixture_codec.field(action, "op", fixture_codec.text) {
          Ok("open-view") -> True
          _ -> False
        }
      })
      |> result.map(action_tree)
      |> result.unwrap(0)
  }
}

fn history_observer(
  clients: List(HistoryClient),
  actions: List(JsonValue),
  local: HistoryClient,
) -> Result(HistoryClient, String) {
  case
    actions
    |> list.reverse
    |> list.find(fn(action) {
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok("observe-view") | Ok("open-view") -> True
        _ -> False
      }
    })
  {
    Ok(action) -> history_client(clients, action_tree(action))
    Error(Nil) -> Ok(local)
  }
}

fn history_compatibility_json(
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
  compatibility: schema.Compatibility,
) -> Result(Json, String) {
  use discrepancies <- result.try(history_schema_discrepancies(stored, view))
  Ok(
    json.object(list.append(
      [
        #("canView", json.bool(compatibility.can_view)),
        #("canUpgrade", json.bool(compatibility.can_upgrade)),
        #("isEquivalent", json.bool(compatibility.is_equivalent)),
      ],
      list.append(
        case discrepancies {
          [] -> []
          values -> [
            #("discrepancies", json.array(values, fn(value) { value })),
          ]
        },
        [#("canInitialize", json.bool(False))],
      ),
    )),
  )
}

fn history_schema_discrepancies(
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(List(Json), String) {
  use stored_nodes <- result.try(history_schema_nodes(stored))
  use view_nodes <- result.try(
    history_schema_nodes(schema.view_to_stored(view)),
  )
  use common_nodes <- result.try(
    list.try_fold(stored_nodes, [], fn(common, entry) {
      case list.key_find(view_nodes, entry.0) {
        Ok(view_node) ->
          Ok(list.append(common, [#(entry.0, entry.1, view_node)]))
        Error(Nil) -> Ok(common)
      }
    }),
  )
  common_nodes
  |> list.try_map(fn(entry) {
    let #(node_type, stored_node, view_node) = entry
    use stored_fields <- result.try(history_object_fields(stored_node))
    use view_fields <- result.try(history_object_fields(view_node))
    let field_keys =
      list.append(
        list.map(stored_fields, fn(field) { field.0 }),
        list.map(view_fields, fn(field) { field.0 }),
      )
      |> list.unique
    field_keys
    |> list.fold([], fn(discrepancies, field_key) {
      case
        history_field_discrepancy(
          node_type,
          field_key,
          list.key_find(stored_fields, field_key) |> option.from_result,
          list.key_find(view_fields, field_key) |> option.from_result,
        )
      {
        Some(discrepancy) -> list.append(discrepancies, [discrepancy])
        None -> discrepancies
      }
    })
    |> Ok
  })
  |> result.map(list.flatten)
}

fn history_schema_nodes(
  stored: schema.StoredSchema,
) -> Result(List(#(String, JsonValue)), String) {
  use value <- result.try(
    json.parse(json.to_string(schema.stored_to_json(stored)), json_ot.decoder())
    |> result.map_error(string.inspect),
  )
  use nodes <- result.try(fixture_codec.get(value, "nodes"))
  case nodes {
    VObject(entries) -> Ok(entries)
    _ -> Error("history schema nodes must be an object")
  }
}

fn history_object_fields(
  node: JsonValue,
) -> Result(List(#(String, JsonValue)), String) {
  use kind <- result.try(fixture_codec.get(node, "kind"))
  case fixture_codec.get(kind, "object") {
    Ok(VObject(fields)) -> Ok(fields)
    Ok(_) -> Error("history object fields must be an object")
    Error(_) -> Ok([])
  }
}

fn history_field_discrepancy(
  node_type: String,
  field_key: String,
  stored: Option(JsonValue),
  view: Option(JsonValue),
) -> Option(Json) {
  let stored_kind = history_field_kind(stored)
  let view_kind = history_field_kind(view)
  let location =
    json.object([
      #("nodeType", json.string(node_type)),
      #("fieldKey", json.string(field_key)),
    ])
  case stored_kind == view_kind {
    False ->
      Some(
        json.object([
          #("mismatch", json.string("fieldKind")),
          #("location", location),
          #("view", json.string(view_kind)),
          #("stored", json.string(stored_kind)),
        ]),
      )
    True -> {
      let stored_types = history_field_types(stored)
      let view_types = history_field_types(view)
      case stored_types == view_types {
        True -> None
        False ->
          Some(
            json.object([
              #("mismatch", json.string("allowedTypes")),
              #("location", location),
              #(
                "view",
                json.array(
                  list.filter(view_types, fn(item) {
                    !list.contains(stored_types, item)
                  }),
                  json.string,
                ),
              ),
              #(
                "stored",
                json.array(
                  list.filter(stored_types, fn(item) {
                    !list.contains(view_types, item)
                  }),
                  json.string,
                ),
              ),
            ]),
          )
      }
    }
  }
}

fn history_field_kind(field: Option(JsonValue)) -> String {
  case field {
    None -> "Forbidden"
    Some(value) ->
      fixture_codec.field(value, "kind", fixture_codec.text)
      |> result.unwrap("Forbidden")
  }
}

fn history_field_types(field: Option(JsonValue)) -> List(String) {
  case field {
    None -> []
    Some(value) ->
      fixture_codec.field(value, "types", fn(types) {
        use types <- result.try(fixture_codec.items(types))
        list.try_map(types, fixture_codec.text)
      })
      |> result.unwrap([])
  }
}

fn history_special_fields(
  driver: HistoryDriver,
  peer: HistoryClient,
) -> Result(List(#(String, Json)), String) {
  case list.key_find(driver.extras, "losingAuthorBefore") {
    Ok(_) -> {
      use after <- result.try(history_forest_json(peer))
      use after_schema <- result.try(history_schema_id(
        driver.catalog,
        tree_kernel.stored_schema(peer.state),
      ))
      use retained <- result.try(history_retained_extra(driver, peer))
      Ok([
        #("losingAuthorAfter", after),
        #("losingAuthorSchemaAfter", json.string(after_schema)),
        #("retainedExtra", retained),
      ])
    }
    _ -> Ok([])
  }
}

fn history_retained_extra(
  driver: HistoryDriver,
  client: HistoryClient,
) -> Result(Json, String) {
  use value_json <- result.try(
    list.key_find(driver.extras, "_retainedExtraValue")
    |> result.map_error(fn(_) { "retained Extra value is missing" }),
  )
  use value_json <- result.try(
    json.parse(json.to_string(value_json), json_ot.decoder())
    |> result.map_error(string.inspect),
  )
  use value <- result.try(fixture_codec.text(value_json))
  use content <- result.try(
    list.key_find(driver.extras, "_retainedExtraContent")
    |> result.map_error(fn(_) { "retained Extra content is missing" }),
  )
  use detached <- result.try(history_detached_json(client))
  Ok(
    json.object([
      #("type", json.string("org.watershed.shared-tree.m4.Extra")),
      #("value", json.string(value)),
      #("content", content),
      #("detached", detached),
    ]),
  )
}

fn history_visible_extra(
  client: HistoryClient,
) -> Result(#(String, Json), String) {
  use data <- result.try(
    tree_kernel.visible_data(client.state) |> result.map_error(string.inspect),
  )
  use extra <- result.try(case data.root {
    Some(ObjectValue(_, fields)) ->
      list.key_find(fields, "extra")
      |> result.map_error(fn(_) { "visible Extra content is missing" })
    _ -> Error("visible root is not an object")
  })
  use value <- result.try(case extra {
    ObjectValue("org.watershed.shared-tree.m4.Extra", fields) -> {
      use value <- result.try(
        list.key_find(fields, "value")
        |> result.map_error(fn(_) { "visible Extra value is missing" }),
      )
      case value {
        StringValue(value) -> Ok(value)
        _ -> Error("visible Extra value is not a string")
      }
    }
    _ -> Error("visible Extra content has the wrong type")
  })
  use content <- result.try(history_tree_value_json(extra))
  Ok(#(value, content))
}

fn history_schema_id(
  catalog: dict.Dict(String, schema.StoredSchema),
  stored: schema.StoredSchema,
) -> Result(String, String) {
  catalog
  |> dict.to_list
  |> list.find(fn(entry) { entry.1 == stored })
  |> result.map(fn(entry) { entry.0 })
  |> result.map_error(fn(_) { "history schema is not in the catalog" })
}

fn history_forest_json(client: HistoryClient) -> Result(Json, String) {
  use data <- result.try(
    tree_kernel.visible_data(client.state) |> result.map_error(string.inspect),
  )
  use root <- result.try(list.try_map(
    case data.root {
      None -> []
      Some(root) -> [root]
    },
    history_tree_value_json,
  ))
  let retained = tree_kernel.identity_revisions(client.state)
  use removed <- result.try(
    data.detached
    |> list.filter(fn(entry) {
      case entry.id.revision {
        None -> True
        Some(revision) -> list.contains(retained, revision)
      }
    })
    |> list.try_map(fn(entry) {
      use value <- result.try(history_tree_value_json(entry.value))
      Ok(
        json.array(
          [
            history_optional_revision_json(entry.id.revision, client),
            json.int(entry.id.local_id),
            value,
          ],
          fn(value) { value },
        ),
      )
    }),
  )
  Ok(
    json.object([
      #("tree", json.array(root, fn(value) { value })),
      #("removed", json.array(removed, fn(value) { value })),
    ]),
  )
}

fn history_detached_json(client: HistoryClient) -> Result(Json, String) {
  case tree_kernel.visible_data(client.state) {
    Error(error) -> Error(string.inspect(error))
    Ok(data) -> {
      let retained = tree_kernel.identity_revisions(client.state)
      use detached <- result.try(
        data.detached
        |> list.filter(fn(entry) {
          case entry.id.revision {
            None -> True
            Some(revision) -> list.contains(retained, revision)
          }
        })
        |> list.try_map(fn(entry) {
          use value <- result.try(history_tree_value_json(entry.value))
          Ok(
            json.array(
              [
                history_optional_revision_json(entry.id.revision, client),
                json.int(entry.id.local_id),
                value,
              ],
              fn(value) { value },
            ),
          )
        }),
      )
      Ok(json.array(detached, fn(value) { value }))
    }
  }
}

fn history_tree_value_json(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.StringValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.string")),
          #("value", json.string(value)),
        ]),
      )
    types.NumberValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.number")),
          #("value", json.float(value)),
        ]),
      )
    types.BooleanValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.boolean")),
          #("value", json.bool(value)),
        ]),
      )
    types.NullValue ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.null")),
          #("value", json.null()),
        ]),
      )
    types.ObjectValue(identifier, fields) -> {
      use fields <- result.try(history_tree_fields_json(fields))
      Ok(
        json.object([
          #("type", json.string(identifier)),
          #("fields", json.object(fields)),
        ]),
      )
    }
    types.MapValue(identifier, entries) -> {
      use fields <- result.try(history_tree_fields_json(entries))
      Ok(
        json.object([
          #("type", json.string(identifier)),
          #("fields", json.object(fields)),
        ]),
      )
    }
    types.ArrayValue(identifier, elements) -> {
      use elements <- result.try(list.try_map(elements, history_tree_value_json))
      let members = [#("type", json.string(identifier))]
      let members = case elements {
        [] -> members
        _ ->
          list.append(members, [
            #(
              "fields",
              json.object([#("", json.array(elements, fn(value) { value }))]),
            ),
          ])
      }
      Ok(json.object(members))
    }
  }
}

fn history_tree_fields_json(
  fields: List(#(String, types.TreeValue)),
) -> Result(List(#(String, Json)), String) {
  list.try_map(fields, fn(entry) {
    use child <- result.try(history_tree_value_json(entry.1))
    Ok(#(entry.0, json.array([child], fn(value) { value })))
  })
}

fn history_optional_revision_json(
  revision: Option(fluid_ids.StableId),
  client: HistoryClient,
) -> Json {
  case revision {
    None -> json.int(0)
    Some(revision) ->
      case
        codec.encode_stable_revision(
          revision,
          codec.EncodeContext(codec.Fluid310, client.compressor, None),
          "history observation revision",
        )
      {
        Ok(value) -> json.int(value)
        Error(_) -> json.null()
      }
  }
}

fn history_commits_json(
  commits: List(history.Commit),
  client: HistoryClient,
) -> Result(List(Json), String) {
  list.try_map(commits, fn(commit) { history_commit_json(commit, client) })
}

fn history_outer_commits_json(
  commits: List(history.Commit),
  client: HistoryClient,
) -> Result(List(Json), String) {
  list.try_map(commits, fn(commit) { history_commit_json(commit, client) })
}

fn history_sequenced_json(
  commits: List(history.SequencedCommit),
  client: HistoryClient,
) -> Result(List(Json), String) {
  commits
  |> list.map(fn(entry) { entry.commit })
  |> history_commits_json(client)
}

fn history_commit_json(
  commit: history.Commit,
  client: HistoryClient,
) -> Result(Json, String) {
  use revision <- result.try(case shared_change.to_changes(commit.change) {
    [
      shared_change.SchemaChange(_, _, _),
      shared_change.DataChange(_),
      shared_change.SchemaChange(_, _, _),
    ] ->
      case commit.originator == client.session {
        True -> Ok(-1)
        False ->
          codec.encode_stable_revision(
            commit.revision,
            codec.EncodeContext(codec.Fluid310, client.compressor, None),
            "history observation commit",
          )
          |> result.map_error(string.inspect)
      }
    _ ->
      case history_local_generation(client.session, commit.revision, 1) {
        Some(generation) ->
          Ok(case client.index {
            0 -> generation - 1
            _ -> 0 - generation
          })
        None ->
          codec.encode_stable_revision(
            commit.revision,
            codec.EncodeContext(codec.Fluid310, client.compressor, None),
            "history observation commit",
          )
          |> result.map_error(string.inspect)
      }
  })
  Ok(history_commit_value(commit, revision))
}

fn history_commit_value(commit: history.Commit, revision: Int) -> Json {
  json.object([
    #("revision", json.int(revision)),
    #(
      "kinds",
      json.array(shared_change.to_changes(commit.change), fn(item) {
        json.string(case item {
          shared_change.DataChange(_) -> "data"
          shared_change.SchemaChange(_, _, _) -> "schema"
        })
      }),
    ),
  ])
}

fn history_local_generation(
  session: fluid_ids.SessionId,
  revision: fluid_ids.StableId,
  generation: Int,
) -> Option(Int) {
  case generation > 32 {
    True -> None
    False ->
      case local_stable_id(session, generation) {
        Ok(candidate) if candidate == revision -> Some(generation)
        _ -> history_local_generation(session, revision, generation + 1)
      }
  }
}

fn append_history_events(
  events: List(String),
  next: List(tree_kernel.TreeEvent),
) -> List(String) {
  list.fold(next, events, fn(events, event) {
    case event {
      tree_kernel.SchemaChanged(_) ->
        list.append(events, ["schemaChanged", "rootChanged"])
      tree_kernel.TreeChanged(_) -> events
    }
  })
}

fn history_client(
  clients: List(HistoryClient),
  index: Int,
) -> Result(HistoryClient, String) {
  case clients, index {
    [client, ..], 0 -> Ok(client)
    [_, ..rest], index if index > 0 -> history_client(rest, index - 1)
    _, _ -> Error("history client index is invalid")
  }
}

fn put_history_client(
  clients: List(HistoryClient),
  index: Int,
  replacement: HistoryClient,
) -> List(HistoryClient) {
  clients
  |> list.index_map(fn(client, current) {
    case current == index {
      True -> replacement
      False -> client
    }
  })
}

pub fn project_algebra_expected(
  input: Json,
  expected: Json,
) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use state <- result.try(algebra_state(input))
  use expected <- result.try(fixture_codec.parse(expected))
  use _ <- result.try(fixture_codec.exact(expected, ["observations"]))
  use observations <- result.try(fixture_codec.field(
    expected,
    "observations",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(observations, fn(observation) {
      case observation {
        VObject(members) ->
          members
          |> list.try_map(fn(member) {
            case member {
              #("change", value) -> {
                use value <- result.try(project_expected_outer(value, state))
                Ok(#("change", value))
              }
              #(name, value) -> Ok(#(name, json_ot.to_json(value)))
            }
          })
          |> result.map(json.object)
        _ -> Error("algebra observation must be an object")
      }
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

pub fn data_observation(value: change.Changeset) -> Json {
  fixture_codec.state_json(value)
}

pub fn forest_transition(
  input: Json,
  before_id: String,
  after_id: String,
) -> Result(
  #(schema.StoredSchema, schema.StoredSchema, types.TreeValue),
  String,
) {
  use input <- result.try(fixture_codec.parse(input))
  use catalog <- result.try(algebra_schema_catalog(input))
  use before <- result.try(
    dict.get(catalog, before_id)
    |> result.map_error(fn(_) { "unknown schema " <> before_id }),
  )
  use after <- result.try(
    dict.get(catalog, after_id)
    |> result.map_error(fn(_) { "unknown schema " <> after_id }),
  )
  use root <- result.try(fixture_codec.get(input, "initialRoot"))
  use root <- result.try(
    json.parse(
      json.to_string(json_ot.to_json(root)),
      fixtures.tree_value_decoder(),
    )
    |> result.map_error(string.inspect),
  )
  use root <- result.try(normalize_tree(before, root))
  Ok(#(before, after, root))
}

pub fn forest_rollback(
  input: Json,
  view_id: fluid_ids.StableId,
) -> Result(#(forest.Forest, types.AtomId), String) {
  use #(restored, _, root) <- result.try(forest_transition(input, "v1", "v1"))
  use input <- result.try(fixture_codec.parse(input))
  use catalog <- result.try(algebra_schema_catalog(input))
  use replay <- result.try(fixture_codec.get(input, "rollbackReplay"))
  use _ <- result.try(fixture_codec.exact(replay, ["scenario", "detachedId"]))
  use scenario_id <- result.try(fixture_codec.field(
    replay,
    "scenario",
    fixture_codec.text,
  ))
  use detached <- result.try(fixture_codec.get(replay, "detachedId"))
  use _ <- result.try(fixture_codec.exact(detached, ["revision", "localId"]))
  use detached_revision <- result.try(fixture_codec.field(
    detached,
    "revision",
    fixture_codec.text,
  ))
  use detached_local_id <- result.try(fixture_codec.field(
    detached,
    "localId",
    fixture_codec.integer,
  ))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use scenario <- result.try(
    list.find(scenarios, fn(value) {
      fixture_codec.field(value, "id", fixture_codec.text) == Ok(scenario_id)
    })
    |> result.map_error(fn(_) { "rollback replay scenario is missing" }),
  )
  use actions <- result.try(fixture_codec.field(
    scenario,
    "actions",
    fixture_codec.items,
  ))
  use #(upgrade, authored_edit, competing_edit, sequence) <- result.try(
    case actions {
      [upgrade, authored_edit, competing_edit, sequence] ->
        Ok(#(upgrade, authored_edit, competing_edit, sequence))
      _ -> Error("rollback replay must contain four actions")
    },
  )
  use _ <- result.try(expect_action(upgrade, "upgrade", Some(1)))
  use schema_id <- result.try(fixture_codec.field(
    upgrade,
    "schema",
    fixture_codec.text,
  ))
  use authored <- result.try(
    dict.get(catalog, schema_id)
    |> result.map_error(fn(_) { "unknown rollback authoring schema" }),
  )
  use _ <- result.try(expect_action(authored_edit, "set", Some(1)))
  use authored_path <- result.try(action_path(authored_edit))
  use _ <- result.try(expect(
    authored_path == ["extra", "value"],
    "unexpected rollback authored path",
  ))
  use retained_value <- result.try(fixture_codec.field(
    authored_edit,
    "value",
    fixture_codec.text,
  ))
  use authored_id <- result.try(replay_atom(scenario, authored_edit))
  use _ <- result.try(expect_action(competing_edit, "set", Some(0)))
  use competing_path <- result.try(action_path(competing_edit))
  use _ <- result.try(expect(
    competing_path == ["title"],
    "unexpected rollback competing path",
  ))
  use competing_value <- result.try(fixture_codec.field(
    competing_edit,
    "value",
    fixture_codec.text,
  ))
  use competing_id <- result.try(replay_atom(scenario, competing_edit))
  use detached_title_local_id <- result.try(fixture_codec.field(
    competing_edit,
    "detachedLocalId",
    fixture_codec.integer,
  ))
  use _ <- result.try(expect_action(sequence, "sequence", None))
  use order <- result.try(fixture_codec.field(
    sequence,
    "order",
    fixture_codec.text,
  ))
  use _ <- result.try(expect(
    order == "tree-0-first",
    "unexpected rollback sequence order",
  ))
  use #(identifier, fields) <- result.try(case root {
    types.ObjectValue(identifier, fields) -> Ok(#(identifier, fields))
    _ -> Error("rollback root must be an object")
  })
  use extra_field <- result.try(
    schema.field_schema(authored, identifier, "extra")
    |> result.map_error(string.inspect),
  )
  use extra_type <- result.try(case extra_field {
    schema.FieldSchema(_, [extra_type]) -> Ok(extra_type)
    _ -> Error("rollback extra field must allow one node type")
  })
  let retained =
    types.ObjectValue(extra_type, [#("value", StringValue(retained_value))])
  use detached_revision <- result.try(
    fluid_ids.stable_id(detached_revision) |> result.map_error(string.inspect),
  )
  let observed_id = AtomId(Some(detached_revision), detached_local_id)
  use _ <- result.try(expect(
    observed_id == authored_id,
    "rollback detached identity has no action allocation provenance",
  ))
  use state <- result.try(
    forest.new(view_id, restored, Some(types.ObjectValue(identifier, fields)))
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    forest.replace_schema(state, authored) |> result.map_error(string.inspect),
  )
  use state <- result.try(apply_forest(
    state,
    forest.DeltaData(
      latest_revision: authored_id.revision,
      fields: [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #(
                "extra",
                forest.FieldDelta([
                  forest.Mark(1, Some(authored_id), None, []),
                ]),
              ),
            ]),
          ]),
        ),
      ],
      build: [forest.Build(authored_id, [retained])],
      refreshers: [],
      global: [],
      rename: [],
      destroy: [],
    ),
  ))
  let removed_title = AtomId(competing_id.revision, detached_title_local_id)
  use state <- result.try(apply_forest(
    state,
    forest.DeltaData(
      latest_revision: competing_id.revision,
      fields: [
        #(
          "rootFieldKey",
          forest.FieldDelta([
            forest.Mark(1, None, None, [
              #(
                "title",
                forest.FieldDelta([
                  forest.Mark(1, Some(competing_id), Some(removed_title), []),
                ]),
              ),
              #(
                "extra",
                forest.FieldDelta([
                  forest.Mark(1, None, Some(authored_id), []),
                ]),
              ),
            ]),
          ]),
        ),
      ],
      build: [forest.Build(competing_id, [StringValue(competing_value)])],
      refreshers: [],
      global: [],
      rename: [],
      destroy: [],
    ),
  ))
  use state <- result.try(
    forest.replace_schema(state, restored) |> result.map_error(string.inspect),
  )
  Ok(#(state, authored_id))
}

pub fn forest_rollback_attached_observation(
  input: Json,
  raw: Json,
) -> Result(types.TreeValue, String) {
  use #(restored, _, _) <- result.try(forest_transition(input, "v1", "v1"))
  use raw <- result.try(fixture_codec.parse(raw))
  use root <- result.try(
    fixture_codec.field(raw, "rollback", fn(rollback) {
      fixture_codec.field(rollback, "visibleRoot", fn(visible) {
        fixture_codec.field(visible, "tree", fn(value) {
          use trees <- result.try(fixture_codec.items(value))
          case trees {
            [tree] -> decode_snapshot_tree(tree)
            _ -> Error("rollback observation must contain one attached root")
          }
        })
      })
    }),
  )
  normalize_tree(restored, root)
}

pub fn forest_rollback_observation(
  raw: Json,
) -> Result(types.TreeValue, String) {
  use raw <- result.try(fixture_codec.parse(raw))
  fixture_codec.field(raw, "rollback", fn(rollback) {
    fixture_codec.field(rollback, "retainedExtra", fn(extra) {
      use identifier <- result.try(fixture_codec.field(
        extra,
        "type",
        fixture_codec.text,
      ))
      use value <- result.try(fixture_codec.field(
        extra,
        "value",
        fixture_codec.text,
      ))
      Ok(types.ObjectValue(identifier, [#("value", StringValue(value))]))
    })
  })
}

fn replay_atom(
  scenario: JsonValue,
  action: JsonValue,
) -> Result(types.AtomId, String) {
  use tree <- result.try(fixture_codec.field(
    action,
    "tree",
    fixture_codec.integer,
  ))
  use identity <- result.try(fixture_codec.get(action, "identity"))
  use _ <- result.try(fixture_codec.exact(identity, ["revision", "localId"]))
  use encoded_revision <- result.try(fixture_codec.field(
    identity,
    "revision",
    fixture_codec.integer,
  ))
  use local_id <- result.try(fixture_codec.field(
    identity,
    "localId",
    fixture_codec.integer,
  ))
  use sessions <- result.try(fixture_codec.field(
    scenario,
    "sessions",
    fixture_codec.items,
  ))
  use session <- result.try(
    list.find(sessions, fn(value) {
      fixture_codec.field(value, "tree", fixture_codec.text)
      == Ok("tree-" <> int.to_string(tree))
    })
    |> result.map_error(fn(_) { "rollback action session is missing" }),
  )
  use session_id <- result.try(
    fixture_codec.field(session, "session", fn(value) {
      use value <- result.try(fixture_codec.text(value))
      fluid_ids.session_id(value) |> result.map_error(string.inspect)
    }),
  )
  use compressor_data <- result.try(fixture_codec.get(session, "compressor"))
  use _ <- result.try(fixture_codec.field(
    compressor_data,
    "state",
    fixture_codec.text,
  ))
  use _ <- result.try(expect(
    encoded_revision < 0,
    "rollback action revision must be a local allocation",
  ))
  let generation = int.absolute_value(encoded_revision)
  use allocations <- result.try(fixture_codec.field(
    compressor_data,
    "allocations",
    fixture_codec.items,
  ))
  use _ <- result.try(expect(
    list.any(allocations, fn(allocation) {
      let first =
        fixture_codec.field(allocation, "firstGenCount", fixture_codec.integer)
      let count =
        fixture_codec.field(allocation, "count", fixture_codec.integer)
      case first, count {
        Ok(first), Ok(count) ->
          generation >= first && generation < first + count
        _, _ -> False
      }
    }),
    "rollback action revision is outside its session allocation",
  ))
  use compressor <- result.try(generate_ids(
    fluid_ids.new(session_id),
    generation,
  ))
  use session_space_id <- result.try(
    fluid_ids.session_space_id(encoded_revision)
    |> result.map_error(string.inspect),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, session_space_id)
    |> result.map_error(string.inspect),
  )
  Ok(AtomId(Some(revision), local_id))
}

fn apply_forest(
  state: forest.Forest,
  data: forest.DeltaData,
) -> Result(forest.Forest, String) {
  use delta <- result.try(
    forest.delta(data) |> result.map_error(string.inspect),
  )
  forest.apply_delta(state, delta) |> result.map_error(string.inspect)
}

fn decode_snapshot_tree(value: JsonValue) -> Result(types.TreeValue, String) {
  use identifier <- result.try(fixture_codec.field(
    value,
    "type",
    fixture_codec.text,
  ))
  case fixture_codec.get(value, "value") {
    Ok(VString(value)) -> Ok(StringValue(value))
    Ok(VNumber(NInt(value))) -> Ok(types.NumberValue(int.to_float(value)))
    Ok(VNumber(NFloat(value))) -> Ok(types.NumberValue(value))
    Ok(VBool(value)) -> Ok(types.BooleanValue(value))
    Ok(VNull) -> Ok(types.NullValue)
    Ok(_) -> Error("unsupported rollback leaf value")
    Error(_) -> {
      use fields <- result.try(
        fixture_codec.field(value, "fields", fn(value) {
          case value {
            VObject(fields) -> Ok(fields)
            _ -> Error("rollback object fields must be an object")
          }
        }),
      )
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          use children <- result.try(fixture_codec.items(field.1))
          case children {
            [child] ->
              decode_snapshot_tree(child)
              |> result.map(fn(child) { #(field.0, child) })
            _ -> Error("rollback field must contain one node")
          }
        }),
      )
      Ok(types.ObjectValue(identifier, fields))
    }
  }
}

fn expect_action(
  action: JsonValue,
  operation: String,
  tree: Option(Int),
) -> Result(Nil, String) {
  use actual <- result.try(fixture_codec.field(action, "op", fixture_codec.text))
  use _ <- result.try(expect(actual == operation, "unexpected rollback action"))
  case tree {
    None -> Ok(Nil)
    Some(tree) -> {
      use actual <- result.try(fixture_codec.field(
        action,
        "tree",
        fixture_codec.integer,
      ))
      expect(actual == tree, "unexpected rollback action tree")
    }
  }
}

fn action_path(action: JsonValue) -> Result(List(String), String) {
  fixture_codec.field(action, "path", fn(value) {
    fixture_codec.many(value, fixture_codec.text)
  })
}

fn expect(valid: Bool, message: String) -> Result(Nil, String) {
  case valid {
    True -> Ok(Nil)
    False -> Error(message)
  }
}

fn normalize_tree(
  stored: schema.StoredSchema,
  value: types.TreeValue,
) -> Result(types.TreeValue, String) {
  case value {
    types.ObjectValue(identifier, fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          use value <- result.try(normalize_tree(stored, field.1))
          Ok(#(field.0, value))
        }),
      )
      use node <- result.try(
        schema.node_schema(stored, identifier)
        |> result.map_error(string.inspect),
      )
      case node {
        schema.Map(_) -> Ok(types.MapValue(identifier, fields))
        schema.Object(_) -> Ok(types.ObjectValue(identifier, fields))
        schema.Array(_) | schema.Leaf(_) ->
          Error(identifier <> " is not an object node")
      }
    }
    types.MapValue(identifier, entries) -> {
      use entries <- result.try(
        list.try_map(entries, fn(entry) {
          use value <- result.try(normalize_tree(stored, entry.1))
          Ok(#(entry.0, value))
        }),
      )
      Ok(types.MapValue(identifier, entries))
    }
    _ -> Ok(value)
  }
}

fn algebra_state(input: JsonValue) -> Result(AlgebraState, String) {
  let assert Ok(originator) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000000")
  use revisions <- result.try(fixture_codec.get(input, "revisions"))
  use revision_numbers <- result.try(algebra_revision_numbers(revisions))
  let maximum = list.fold(revision_numbers, 0, int_max)
  use compressor <- result.try(algebra_compressor(originator, maximum + 1))
  use schema_revision <- result.try(algebra_revision(
    revisions,
    "schema",
    originator,
    compressor,
  ))
  use data_revision <- result.try(algebra_revision(
    revisions,
    "data",
    originator,
    compressor,
  ))
  use second_data_revision <- result.try(algebra_revision(
    revisions,
    "secondData",
    originator,
    compressor,
  ))
  use second_schema_revision <- result.try(algebra_revision(
    revisions,
    "secondSchema",
    originator,
    compressor,
  ))
  use inverse_revision <- result.try(algebra_revision(
    revisions,
    "inverse",
    originator,
    compressor,
  ))
  use catalog <- result.try(algebra_schema_catalog(input))
  use transitions <- result.try(fixture_codec.field(
    input,
    "transitions",
    fixture_codec.items,
  ))
  use transitions <- result.try(
    list.try_map(transitions, fn(transition) {
      decode_transition(transition, catalog, originator, compressor)
    }),
  )
  use schema_transition <- result.try(find_transition(
    transitions,
    schema_revision,
  ))
  use second_schema_transition <- result.try(find_transition(
    transitions,
    second_schema_revision,
  ))
  use operands <- result.try(fixture_codec.get(input, "operands"))
  use _ <- result.try(
    fixture_codec.exact(operands, [
      "schemaChange", "dataChange", "secondSchemaChange", "emptyChange",
    ]),
  )
  use _ <- result.try(
    fixture_codec.field(operands, "schemaChange", fn(value) {
      compare_schema_operand(value, schema_transition.1)
    }),
  )
  use _ <- result.try(
    fixture_codec.field(operands, "secondSchemaChange", fn(value) {
      compare_schema_operand(value, second_schema_transition.1)
    }),
  )
  use identity_order <- result.try(algebra_identity_order(
    originator,
    compressor,
    maximum,
  ))
  use data <- result.try(
    fixture_codec.field(operands, "dataChange", fn(value) {
      decode_data_operand(
        value,
        data_revision,
        originator,
        compressor,
        identity_order,
      )
    }),
  )
  use empty <- result.try(fixture_codec.field(
    operands,
    "emptyChange",
    decode_empty_operand,
  ))
  Ok(
    AlgebraState(
      originator:,
      compressor:,
      schema_change: schema_transition.0,
      data_change: data,
      second_data_revision:,
      second_schema_change: second_schema_transition.0,
      empty_change: shared_change.TaggedChange(None, None, empty),
      inverse_revision:,
      identity_order:,
      schema_encodings: [schema_transition.1, second_schema_transition.1],
    ),
  )
}

fn project_expected_outer(
  value: JsonValue,
  state: AlgebraState,
) -> Result(Json, String) {
  use _ <- result.try(fixture_codec.exact(value, ["changes"]))
  use changes <- result.try(fixture_codec.field(
    value,
    "changes",
    fixture_codec.items,
  ))
  use changes <- result.try(
    list.try_map(changes, fn(item) {
      use kind <- result.try(fixture_codec.field(
        item,
        "type",
        fixture_codec.text,
      ))
      case kind {
        "data" -> {
          use inner <- result.try(fixture_codec.get(item, "innerChange"))
          use data <- result.try(decode_internal_data(
            inner,
            state.originator,
            state.compressor,
            state.identity_order,
          ))
          Ok(
            json.object([
              #("type", json.string("data")),
              #("innerChange", data_observation(data)),
            ]),
          )
        }
        "schema" -> Ok(json_ot.to_json(item))
        _ -> Error("unexpected outer change type " <> kind)
      }
    }),
  )
  Ok(json.object([#("changes", json.array(changes, fn(value) { value }))]))
}

fn compare_schema_operand(
  operand: JsonValue,
  encoding: SchemaEncoding,
) -> Result(Nil, String) {
  fixtures.first_difference(
    json_ot.to_json(operand),
    schema_operand_json(encoding),
  )
  |> result.map_error(fn(path) {
    "schema operand and transition differ at " <> path
  })
}

fn schema_operand_json(encoding: SchemaEncoding) -> Json {
  json.object([
    #(
      "changes",
      json.array(
        [
          json.object([
            #("type", json.string("schema")),
            #(
              "innerChange",
              json.object([
                #(
                  "schema",
                  json.object([
                    #("old", json_ot.to_json(encoding.old)),
                    #("new", json_ot.to_json(encoding.new)),
                  ]),
                ),
                #("isInverse", json.bool(False)),
              ]),
            ),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}

fn algebra_revision_numbers(value: JsonValue) -> Result(List(Int), String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "schema", "data", "secondData", "secondSchema", "inverse",
    ]),
  )
  list.try_map(
    ["schema", "data", "secondData", "secondSchema", "inverse"],
    fn(name) { fixture_codec.field(value, name, fixture_codec.integer) },
  )
}

fn algebra_compressor(
  originator: fluid_ids.SessionId,
  count: Int,
) -> Result(fluid_ids.Compressor, String) {
  use compressor <- result.try(generate_ids(fluid_ids.new(originator), count))
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  case range {
    None -> Ok(compressor)
    Some(range) ->
      fluid_ids.finalize(compressor, range)
      |> result.map_error(string.inspect)
  }
}

fn generate_ids(
  compressor: fluid_ids.Compressor,
  count: Int,
) -> Result(fluid_ids.Compressor, String) {
  case count {
    0 -> Ok(compressor)
    _ -> {
      use #(compressor, _) <- result.try(
        fluid_ids.generate(compressor) |> result.map_error(string.inspect),
      )
      generate_ids(compressor, count - 1)
    }
  }
}

fn algebra_revision(
  revisions: JsonValue,
  name: String,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(fluid_ids.StableId, String) {
  use value <- result.try(fixture_codec.field(
    revisions,
    name,
    fixture_codec.integer,
  ))
  codec.decode_stable_revision(
    value,
    originator,
    codec.DecodeContext(codec.Fluid310, compressor),
    "algebra revision",
  )
  |> result.map_error(string.inspect)
}

fn algebra_identity_order(
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  maximum: Int,
) -> Result(change.IdentityOrder, String) {
  use revisions <- result.try(
    algebra_revisions(originator, compressor, 0, maximum, []),
  )
  codec.identity_order(revisions, compressor, "algebra identity order")
  |> result.map_error(string.inspect)
}

fn algebra_revisions(
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  current: Int,
  maximum: Int,
  revisions: List(fluid_ids.StableId),
) -> Result(List(fluid_ids.StableId), String) {
  case current > maximum {
    True -> Ok(list.reverse(revisions))
    False -> {
      use revision <- result.try(
        codec.decode_stable_revision(
          current,
          originator,
          codec.DecodeContext(codec.Fluid310, compressor),
          "algebra identity order",
        )
        |> result.map_error(string.inspect),
      )
      algebra_revisions(originator, compressor, current + 1, maximum, [
        revision,
        ..revisions
      ])
    }
  }
}

fn algebra_schema_catalog(
  input: JsonValue,
) -> Result(dict.Dict(String, schema.StoredSchema), String) {
  use entries <- result.try(fixture_codec.field(
    input,
    "schemas",
    fixture_codec.items,
  ))
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      use _ <- result.try(fixture_codec.exact(entry, ["id", "raw"]))
      use id <- result.try(fixture_codec.field(entry, "id", fixture_codec.text))
      use raw <- result.try(fixture_codec.field(
        entry,
        "raw",
        fixture_codec.text,
      ))
      use stored <- result.try(
        schema.stored_from_string(raw) |> result.map_error(string.inspect),
      )
      Ok(#(id, stored))
    }),
  )
  Ok(dict.from_list(entries))
}

fn decode_transition(
  value: JsonValue,
  catalog: dict.Dict(String, schema.StoredSchema),
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(#(shared_change.TaggedChange, SchemaEncoding), String) {
  use _ <- result.try(
    fixture_codec.exact(value, ["revision", "before", "after", "change"]),
  )
  use revision_number <- result.try(fixture_codec.field(
    value,
    "revision",
    fixture_codec.integer,
  ))
  use revision <- result.try(
    codec.decode_stable_revision(
      revision_number,
      originator,
      codec.DecodeContext(codec.Fluid310, compressor),
      "schema transition revision",
    )
    |> result.map_error(string.inspect),
  )
  use before_id <- result.try(fixture_codec.field(
    value,
    "before",
    fixture_codec.text,
  ))
  use after_id <- result.try(fixture_codec.field(
    value,
    "after",
    fixture_codec.text,
  ))
  use before <- result.try(
    dict.get(catalog, before_id)
    |> result.map_error(fn(_) { "unknown transition schema " <> before_id }),
  )
  use after <- result.try(
    dict.get(catalog, after_id)
    |> result.map_error(fn(_) { "unknown transition schema " <> after_id }),
  )
  use encoded <- result.try(fixture_codec.get(value, "change"))
  use inner <- result.try(single_outer_change(encoded, "schema"))
  use _ <- result.try(fixture_codec.exact(inner, ["schema", "isInverse"]))
  use is_inverse <- result.try(fixture_codec.field(
    inner,
    "isInverse",
    fixture_codec.boolean,
  ))
  use _ <- result.try(case is_inverse {
    False -> Ok(Nil)
    True -> Error("input schema transition must not be inverse")
  })
  use schema_value <- result.try(fixture_codec.get(inner, "schema"))
  use _ <- result.try(fixture_codec.exact(schema_value, ["old", "new"]))
  use old <- result.try(fixture_codec.get(schema_value, "old"))
  use new <- result.try(fixture_codec.get(schema_value, "new"))
  let before = schema.FixedSchema(before)
  let after = schema.FixedSchema(after)
  let change =
    shared_change.from_changes([
      shared_change.SchemaChange(before, after, False),
    ])
  use change <- result.try(change |> result.map_error(string.inspect))
  Ok(#(
    shared_change.TaggedChange(Some(revision), None, change),
    SchemaEncoding(before, after, old, new),
  ))
}

fn find_transition(
  transitions: List(#(shared_change.TaggedChange, SchemaEncoding)),
  revision: fluid_ids.StableId,
) -> Result(#(shared_change.TaggedChange, SchemaEncoding), String) {
  list.find(transitions, fn(transition) {
    transition.0.revision == Some(revision)
  })
  |> result.map_error(fn(_) { "missing schema transition revision" })
}

fn decode_data_operand(
  value: JsonValue,
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  identity_order: change.IdentityOrder,
) -> Result(shared_change.TaggedChange, String) {
  use inner <- result.try(single_outer_change(value, "data"))
  use data <- result.try(decode_internal_data(
    inner,
    originator,
    compressor,
    identity_order,
  ))
  Ok(shared_change.TaggedChange(
    Some(revision),
    None,
    shared_change.from_data(data),
  ))
}

fn decode_internal_data(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  identity_order: change.IdentityOrder,
) -> Result(change.Changeset, String) {
  use max_local_id <- result.try(fixture_codec.field(
    value,
    "maxId",
    fixture_codec.integer,
  ))
  use revisions <- result.try(
    fixture_codec.field(value, "revisions", fn(value) {
      fixture_codec.many(value, fn(value) {
        use revision <- result.try(
          fixture_codec.field(value, "revision", fn(value) {
            decode_internal_revision(value, originator, compressor)
          }),
        )
        let rollback = case fixture_codec.get(value, "rollbackOf") {
          Error(_) -> Ok(None)
          Ok(value) ->
            decode_internal_revision(value, originator, compressor)
            |> result.map(Some)
        }
        use rollback <- result.try(rollback)
        Ok(change.RevisionInfo(revision, rollback))
      })
    }),
  )
  use fields <- result.try(
    fixture_codec.field(value, "fieldChanges", fn(value) {
      decode_internal_fields(value, originator, compressor)
    }),
  )
  use nodes <- result.try(
    fixture_codec.field(value, "nodeChanges", fn(value) {
      decode_internal_nodes(value, originator, compressor)
    }),
  )
  use parents <- result.try(
    fixture_codec.field(value, "nodeToParent", fn(value) {
      decode_internal_parents(value, originator, compressor)
    }),
  )
  use aliases <- result.try(
    fixture_codec.field(value, "nodeAliases", fn(value) {
      decode_internal_aliases(value, originator, compressor)
    }),
  )
  let builds = case fixture_codec.get(value, "builds") {
    Error(_) -> Ok([])
    Ok(value) -> decode_internal_builds(value, originator, compressor)
  }
  use builds <- result.try(builds)
  let destroys = case fixture_codec.get(value, "destroys") {
    Error(_) -> Ok([])
    Ok(value) -> decode_internal_destroys(value, originator, compressor)
  }
  use destroys <- result.try(destroys)
  change.from_data(
    change.ChangeData(
      max_local_id:,
      revisions:,
      fields:,
      nodes:,
      parents:,
      aliases:,
      builds:,
      destroys:,
      refreshers: [],
      cross_field_keys: [],
    ),
    identity_order,
  )
  |> result.map_error(string.inspect)
}

fn decode_internal_revision(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(fluid_ids.StableId, String) {
  use value <- result.try(fixture_codec.integer(value))
  codec.decode_stable_revision(
    value,
    originator,
    codec.DecodeContext(codec.Fluid310, compressor),
    "algebra data revision",
  )
  |> result.map_error(string.inspect)
}

fn decode_internal_atom(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(types.AtomId, String) {
  case value {
    VObject(_) -> {
      use local_id <- result.try(fixture_codec.field(
        value,
        "localId",
        fixture_codec.integer,
      ))
      use revision <- result.try(
        fixture_codec.field(value, "revision", fn(value) {
          decode_internal_revision(value, originator, compressor)
        }),
      )
      Ok(AtomId(Some(revision), local_id))
    }
    VArray([revision, local_id]) -> {
      use revision <- result.try(decode_internal_revision(
        revision,
        originator,
        compressor,
      ))
      use local_id <- result.try(fixture_codec.integer(local_id))
      Ok(AtomId(Some(revision), local_id))
    }
    _ -> Error("invalid algebra atom")
  }
}

fn decode_internal_fields(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(String, change.FieldChange)), String) {
  use entries <- result.try(internal_map_entries(value))
  list.try_map(entries, fn(entry) {
    use #(key, field) <- result.try(fixture_codec.pair(entry))
    use key <- result.try(fixture_codec.text(key))
    use kind <- result.try(fixture_codec.field(
      field,
      "fieldKind",
      fixture_codec.text,
    ))
    use encoded <- result.try(fixture_codec.get(field, "change"))
    case kind {
      "ModularEditBuilder.Generic" -> {
        use children <- result.try(internal_btree_entries(encoded))
        use children <- result.try(
          list.try_map(children, fn(child) {
            use index <- result.try(fixture_codec.integer(child.0))
            use id <- result.try(decode_internal_atom(
              child.1,
              originator,
              compressor,
            ))
            Ok(#(index, id))
          }),
        )
        Ok(#(key, change.GenericField(children)))
      }
      "Value" | "Optional" -> {
        use replacement <- result.try(
          fixture_codec.field(encoded, "valueReplace", fn(replacement) {
            use was_empty <- result.try(fixture_codec.field(
              replacement,
              "isEmpty",
              fixture_codec.boolean,
            ))
            let source = case fixture_codec.get(replacement, "src") {
              Error(_) -> Ok(None)
              Ok(source) ->
                decode_internal_atom(source, originator, compressor)
                |> result.map(optional_field.Detached)
                |> result.map(Some)
            }
            use source <- result.try(source)
            use detach <- result.try(
              fixture_codec.field(replacement, "dst", fn(value) {
                decode_internal_atom(value, originator, compressor)
              }),
            )
            Ok(optional_field.Replacement(was_empty, source, detach))
          }),
        )
        let field_change = optional_field.FieldChange([], [], Some(replacement))
        Ok(
          #(key, case kind {
            "Value" -> change.ValueField(field_change)
            _ -> change.OptionalField(field_change)
          }),
        )
      }
      _ -> Error("unsupported algebra field kind " <> kind)
    }
  })
}

fn decode_internal_nodes(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, change.NodeChange)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use fields <- result.try(
      fixture_codec.field(entry.1, "fieldChanges", fn(value) {
        decode_internal_fields(value, originator, compressor)
      }),
    )
    Ok(#(id, change.NodeChange(fields)))
  })
}

fn decode_internal_parents(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, change.ParentField)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use field <- result.try(fixture_codec.field(
      entry.1,
      "field",
      fixture_codec.text,
    ))
    let parent = case fixture_codec.get(entry.1, "parent") {
      Error(_) -> Ok(None)
      Ok(parent) ->
        decode_internal_atom(parent, originator, compressor)
        |> result.map(Some)
    }
    use parent <- result.try(parent)
    Ok(#(id, change.ParentField(parent, field)))
  })
}

fn decode_internal_aliases(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, types.AtomId)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use source <- result.try(decode_internal_atom(
      entry.0,
      originator,
      compressor,
    ))
    use destination <- result.try(decode_internal_atom(
      entry.1,
      originator,
      compressor,
    ))
    Ok(#(source, destination))
  })
}

fn decode_internal_builds(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(forest.Build), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use tree <- result.try(decode_internal_tree(entry.1))
    Ok(forest.Build(id, [tree]))
  })
}

fn decode_internal_destroys(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(forest.Destroy), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use count <- result.try(fixture_codec.integer(entry.1))
    Ok(forest.Destroy(id, count))
  })
}

fn decode_internal_tree(value: JsonValue) -> Result(types.TreeValue, String) {
  use kind <- result.try(fixture_codec.field(value, "type", fixture_codec.text))
  case kind {
    "com.fluidframework.leaf.string" -> {
      use value <- result.try(fixture_codec.field(
        value,
        "value",
        fixture_codec.text,
      ))
      Ok(StringValue(value))
    }
    _ -> Error("unsupported algebra build type " <> kind)
  }
}

fn internal_map_entries(value: JsonValue) -> Result(List(JsonValue), String) {
  use kind <- result.try(fixture_codec.field(value, "$type", fixture_codec.text))
  case kind {
    "Map" -> fixture_codec.field(value, "entries", fixture_codec.items)
    _ -> Error("expected an internal Map")
  }
}

fn internal_btree_entries(
  value: JsonValue,
) -> Result(List(#(JsonValue, JsonValue)), String) {
  use root <- result.try(fixture_codec.get(value, "_root"))
  use keys <- result.try(fixture_codec.field(root, "keys", fixture_codec.items))
  use values <- result.try(fixture_codec.field(
    root,
    "values",
    fixture_codec.items,
  ))
  case list.length(values) >= list.length(keys) {
    True -> Ok(list.zip(keys, list.take(values, list.length(keys))))
    False -> Error("internal tree has fewer values than keys")
  }
}

fn decode_empty_operand(
  value: JsonValue,
) -> Result(shared_change.Changeset, String) {
  use _ <- result.try(fixture_codec.exact(value, ["changes"]))
  use changes <- result.try(fixture_codec.field(
    value,
    "changes",
    fixture_codec.items,
  ))
  case changes {
    [] -> Ok(shared_change.empty())
    _ -> Error("empty operand contains changes")
  }
}

fn single_outer_change(
  value: JsonValue,
  expected: String,
) -> Result(JsonValue, String) {
  use _ <- result.try(fixture_codec.exact(value, ["changes"]))
  use changes <- result.try(fixture_codec.field(
    value,
    "changes",
    fixture_codec.items,
  ))
  case changes {
    [item] -> {
      use _ <- result.try(fixture_codec.exact(item, ["type", "innerChange"]))
      use kind <- result.try(fixture_codec.field(
        item,
        "type",
        fixture_codec.text,
      ))
      case kind == expected {
        True -> fixture_codec.get(item, "innerChange")
        False -> Error("unexpected outer change type " <> kind)
      }
    }
    _ -> Error("operand must contain one outer change")
  }
}

fn run_algebra_scenario(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  case id {
    "schema-over-data" ->
      rebase_observation(id, state.schema_change, state.data_change, state)
    "data-over-schema" ->
      rebase_observation(id, state.data_change, state.schema_change, state)
    "schema-over-schema" ->
      rebase_observation(
        id,
        state.schema_change,
        state.second_schema_change,
        state,
      )
    "empty-operand" ->
      rebase_observation(id, state.schema_change, state.empty_change, state)
    "data-schema-data-schema-compose" -> compose_observation(id, state)
    "inverse-schema-encoding-refusal" -> inverse_observation(id, state)
    _ -> Error("unknown algebra scenario " <> id)
  }
}

fn rebase_observation(
  id: String,
  value: shared_change.TaggedChange,
  over: shared_change.TaggedChange,
  state: AlgebraState,
) -> Result(Json, String) {
  use context <- result.try(
    change.rebase_context(list.append(
      shared_change.revision_infos(value),
      shared_change.revision_infos(over),
    ))
    |> result.map_error(string.inspect),
  )
  use rebased <- result.try(
    shared_change.rebase(value, over, context)
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(rebased, state))
  Ok(json.object([#("id", json.string(id)), #("change", encoded)]))
}

fn compose_observation(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  let second_data =
    shared_change.TaggedChange(
      Some(state.second_data_revision),
      None,
      state.data_change.change,
    )
  let changes = [
    state.data_change,
    state.schema_change,
    second_data,
    state.second_schema_change,
  ]
  use composed <- result.try(
    shared_change.compose(changes) |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(composed, state))
  use revisions <- result.try(
    list.try_map(changes, fn(tagged) {
      case tagged.revision {
        None -> Error("composed algebra change has no revision")
        Some(revision) -> encode_revision(revision, state)
      }
    }),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #(
        "kinds",
        json.array(shared_change.to_changes(composed), fn(item) {
          json.string(case item {
            shared_change.DataChange(_) -> "data"
            shared_change.SchemaChange(_, _, _) -> "schema"
          })
        }),
      ),
      #("change", encoded),
      #("revisions", json.array(revisions, fn(value) { value })),
    ]),
  )
}

fn inverse_observation(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  let second_data =
    shared_change.TaggedChange(
      Some(state.second_data_revision),
      None,
      state.data_change.change,
    )
  use composed <- result.try(
    shared_change.compose([
      state.data_change,
      state.schema_change,
      second_data,
      state.second_schema_change,
    ])
    |> result.map_error(string.inspect),
  )
  use inverted <- result.try(
    shared_change.invert(
      shared_change.TaggedChange(
        state.second_schema_change.revision,
        None,
        composed,
      ),
      True,
      state.inverse_revision,
    )
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(inverted, state))
  let error = case encode_for_wire(inverted) {
    Ok(_) -> "missing inverse schema encoding refusal"
    Error(detail) -> detail
  }
  use revision <- result.try(encode_revision(state.inverse_revision, state))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("error", json.string(error)),
      #("change", encoded),
      #("revision", revision),
    ]),
  )
}

fn encode_outer(
  value: shared_change.Changeset,
  state: AlgebraState,
) -> Result(Json, String) {
  use changes <- result.try(
    list.try_map(shared_change.to_changes(value), fn(item) {
      case item {
        shared_change.DataChange(data) ->
          Ok(
            json.object([
              #("type", json.string("data")),
              #("innerChange", data_observation(data)),
            ]),
          )
        shared_change.SchemaChange(before, after, is_inverse) -> {
          use encoding <- result.try(find_schema_encoding(
            state.schema_encodings,
            before,
            after,
            is_inverse,
          ))
          Ok(
            json.object([
              #("type", json.string("schema")),
              #(
                "innerChange",
                json.object([
                  #(
                    "schema",
                    json.object([
                      #("old", json_ot.to_json(encoding.0)),
                      #("new", json_ot.to_json(encoding.1)),
                    ]),
                  ),
                  #("isInverse", json.bool(is_inverse)),
                ]),
              ),
            ]),
          )
        }
      }
    }),
  )
  Ok(json.object([#("changes", json.array(changes, fn(value) { value }))]))
}

fn find_schema_encoding(
  encodings: List(SchemaEncoding),
  before: schema.SchemaState,
  after: schema.SchemaState,
  is_inverse: Bool,
) -> Result(#(JsonValue, JsonValue), String) {
  use encoding <- result.try(
    list.find(encodings, fn(encoding) {
      case is_inverse {
        False -> encoding.before == before && encoding.after == after
        True -> encoding.before == after && encoding.after == before
      }
    })
    |> result.map_error(fn(_) { "missing schema encoding" }),
  )
  case is_inverse {
    False -> Ok(#(encoding.old, encoding.new))
    True -> Ok(#(encoding.new, encoding.old))
  }
}

fn encode_for_wire(value: shared_change.Changeset) -> Result(Nil, String) {
  case
    list.any(shared_change.to_changes(value), fn(item) {
      case item {
        shared_change.SchemaChange(_, _, True) -> True
        _ -> False
      }
    })
  {
    True -> Error("Error: 0x933")
    False -> Ok(Nil)
  }
}

fn encode_revision(
  revision: fluid_ids.StableId,
  state: AlgebraState,
) -> Result(Json, String) {
  codec.encode_stable_revision(
    revision,
    codec.EncodeContext(codec.Fluid310, state.compressor, None),
    "algebra revision",
  )
  |> result.map(json.int)
  |> result.map_error(string.inspect)
}

fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}

pub fn compatibility_projection(input: Json) -> Result(Json, String) {
  use observations <- result.try(
    json.parse(json.to_string(input), {
      use observations <- decode.field(
        "observations",
        decode.list(observation_status_decoder()),
      )
      decode.success(observations)
    })
    |> result.map_error(fn(error) {
      "invalid schema compatibility observations: " <> string.inspect(error)
    }),
  )
  Ok(
    json.object([
      #(
        "observations",
        json.array(observations, fn(observation) {
          json.object([
            #("id", json.string(observation.id)),
            #(
              "compatibility",
              json.object([
                #("canView", json.bool(observation.can_view)),
                #("canUpgrade", json.bool(observation.can_upgrade)),
                #("isEquivalent", json.bool(observation.is_equivalent)),
              ]),
            ),
          ])
        }),
      ),
    ]),
  )
}

fn run_scenario(
  catalog: dict.Dict(String, String),
  scenario: Scenario,
) -> Result(Json, String) {
  use _ <- result.try(check_operation(scenario, "compatibility"))
  use stored_raw <- result.try(find_schema(catalog, scenario.stored))
  use requested_raw <- result.try(find_schema(catalog, scenario.requested))
  use stored <- result.try(
    schema.stored_from_string(stored_raw)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid stored schema: " <> string.inspect(error)
    }),
  )
  use view <- result.try(
    schema.view_from_string(requested_raw)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid requested schema: " <> string.inspect(error)
    }),
  )
  native_observation(scenario.id, stored, view)
}

fn run_refusal_scenario(
  catalog: dict.Dict(String, String),
  scenario: Scenario,
) -> Result(Json, String) {
  use _ <- result.try(check_operation(scenario, "prepare-upgrade"))
  use stored_raw <- result.try(find_schema(catalog, scenario.stored))
  use requested_raw <- result.try(find_schema(catalog, scenario.requested))
  use stored <- result.try(
    schema.stored_from_string(stored_raw)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid stored schema: " <> string.inspect(error)
    }),
  )
  use view <- result.try(
    schema.view_from_string(requested_raw)
    |> result.map_error(fn(error) {
      scenario.id <> ": invalid requested schema: " <> string.inspect(error)
    }),
  )
  use status <- result.try(
    schema.compatibility(stored, view)
    |> result.map_error(fn(error) {
      scenario.id <> ": compatibility error: " <> string.inspect(error)
    }),
  )
  use preparation <- result.try(preparation_json(scenario.id, stored, view))
  let classification = case status.can_upgrade {
    True -> "m4-profile-exclusion"
    False -> "upstream-refusal"
  }
  Ok(
    json.object([
      #("id", json.string(scenario.id)),
      #("classification", json.string(classification)),
      #("compatibility", compatibility_json(status)),
      #("preparation", preparation),
    ]),
  )
}

fn native_observation(
  id: String,
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(Json, String) {
  use status <- result.try(
    schema.compatibility(stored, view)
    |> result.map_error(fn(error) {
      id <> ": compatibility error: " <> string.inspect(error)
    }),
  )
  use preparation <- result.try(preparation_json(id, stored, view))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("compatibility", compatibility_json(status)),
      #("preparation", preparation),
    ]),
  )
}

fn preparation_json(
  id: String,
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(Json, String) {
  case schema.prepare_upgrade(stored, view) {
    Ok(None) ->
      Ok(
        json.object([
          #("outcome", json.string("no-op")),
          #("error", json.null()),
        ]),
      )
    Ok(Some(_)) ->
      Ok(
        json.object([
          #("outcome", json.string("upgrade")),
          #("error", json.null()),
        ]),
      )
    Error(types.InvalidSchema(detail)) ->
      Ok(
        json.object([
          #("outcome", json.string("refused")),
          #("error", json.string(detail)),
        ]),
      )
    Error(error) ->
      Error(id <> ": unexpected upgrade error: " <> string.inspect(error))
  }
}

fn run_raw_probe(
  probe: RawProbe,
  baseline: schema.ViewSchema,
) -> Result(Json, String) {
  case schema.stored_from_string(probe.raw) {
    Error(error) ->
      Ok(
        json.object([
          #("id", json.string(probe.id)),
          #("parsed", json.bool(False)),
          #("classification", json.string("stored-decode-refusal")),
          #("error", json.string(string.inspect(error))),
        ]),
      )
    Ok(stored) -> {
      use status <- result.try(
        schema.compatibility(stored, baseline)
        |> result.map_error(fn(error) {
          probe.id <> ": compatibility error: " <> string.inspect(error)
        }),
      )
      Ok(
        json.object([
          #("id", json.string(probe.id)),
          #("parsed", json.bool(True)),
          #("classification", json.string("compatibility")),
          #("compatibility", compatibility_json(status)),
        ]),
      )
    }
  }
}

fn compatibility_json(status: schema.Compatibility) -> Json {
  json.object([
    #("canView", json.bool(status.can_view)),
    #("canUpgrade", json.bool(status.can_upgrade)),
    #("isEquivalent", json.bool(status.is_equivalent)),
  ])
}

fn check_operation(
  scenario: Scenario,
  expected: String,
) -> Result(Nil, String) {
  case scenario.operation == expected {
    True -> Ok(Nil)
    False -> Error(scenario.id <> ": unknown operation " <> scenario.operation)
  }
}

fn validate_input(input: Input) -> Result(Nil, String) {
  use _ <- result.try(case input.schemas, input.scenarios {
    [], _ -> Error("schema evolution schemas must not be empty")
    _, [] -> Error("schema evolution scenarios must not be empty")
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(unique_ids(
    input.schemas,
    fn(entry) { entry.id },
    "schema",
  ))
  use _ <- result.try(unique_ids(
    input.scenarios,
    fn(scenario) { scenario.id },
    "scenario",
  ))
  use _ <- result.try(unique_ids(
    input.refusals,
    fn(scenario) { scenario.id },
    "refusal",
  ))
  unique_ids(input.raw_probes, fn(probe) { probe.id }, "raw probe")
}

fn unique_ids(
  values: List(a),
  identifier: fn(a) -> String,
  kind: String,
) -> Result(Nil, String) {
  values
  |> list.try_fold(set.new(), fn(ids, value) {
    let id = identifier(value)
    case string.is_empty(id) || set.contains(ids, id) {
      True -> Error("empty or duplicate " <> kind <> " id: " <> id)
      False -> Ok(set.insert(ids, id))
    }
  })
  |> result.map(fn(_) { Nil })
}

fn find_schema(
  catalog: dict.Dict(String, String),
  identifier: String,
) -> Result(String, String) {
  dict.get(catalog, identifier)
  |> result.map_error(fn(_) { "unknown schema " <> identifier })
}

fn input_decoder() -> Decoder(Input) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["schemas", "scenarios", "refusals", "rawProbes"],
    Input([], [], [], []),
    {
      use schemas <- decode.field("schemas", decode.list(schema_decoder()))
      use scenarios <- decode.field(
        "scenarios",
        decode.list(scenario_decoder()),
      )
      use refusals <- decode.field("refusals", decode.list(scenario_decoder()))
      use raw_probes <- decode.field(
        "rawProbes",
        decode.list(raw_probe_decoder()),
      )
      decode.success(Input(schemas:, scenarios:, refusals:, raw_probes:))
    },
  )
}

fn schema_decoder() -> Decoder(SchemaEntry) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "raw"], SchemaEntry("", ""), {
    use id <- decode.field("id", decode.string)
    use raw <- decode.field("raw", decode.string)
    decode.success(SchemaEntry(id:, raw:))
  })
}

fn scenario_decoder() -> Decoder(Scenario) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "stored", "requested", "operation"],
    Scenario("", "", "", ""),
    {
      use id <- decode.field("id", decode.string)
      use stored <- decode.field("stored", decode.string)
      use requested <- decode.field("requested", decode.string)
      use operation <- decode.field("operation", decode.string)
      decode.success(Scenario(id:, stored:, requested:, operation:))
    },
  )
}

fn raw_probe_decoder() -> Decoder(RawProbe) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "raw"], RawProbe("", ""), {
    use id <- decode.field("id", decode.string)
    use raw <- decode.field("raw", decode.string)
    decode.success(RawProbe(id:, raw:))
  })
}

fn observation_status_decoder() -> Decoder(ObservationStatus) {
  use id <- decode.field("id", decode.string)
  use compatibility <- decode.field("compatibility", {
    use can_view <- decode.field("canView", decode.bool)
    use can_upgrade <- decode.field("canUpgrade", decode.bool)
    use is_equivalent <- decode.field("isEquivalent", decode.bool)
    decode.success(#(can_view, can_upgrade, is_equivalent))
  })
  decode.success(ObservationStatus(
    id:,
    can_view: compatibility.0,
    can_upgrade: compatibility.1,
    is_equivalent: compatibility.2,
  ))
}

fn exact_decoder(
  fields: dict.Dict(String, Dynamic),
  expected: List(String),
  placeholder: a,
  decoder: Decoder(a),
) -> Decoder(a) {
  case
    dict.size(fields) == list.length(expected)
    && list.all(expected, fn(field) { dict.has_key(fields, field) })
  {
    True -> decoder
    False -> decode.failure(placeholder, "object with exact fields")
  }
}
