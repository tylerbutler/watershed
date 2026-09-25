import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/change_fixture_codec as input
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{
  type TreeValue, BooleanValue, ClearField, NullValue, NumberValue, ObjectValue,
  SequencePoint, SetField, StringValue,
}
import watershed/tree_kernel
import watershed/wire/fluid_summary

const view_0 = "00000000-0000-4000-8000-000000000010"

const view_1 = "00000000-0000-4000-8000-000000000011"

const reload_view = "00000000-0000-4000-8000-000000000012"

const reload_session = "00000000-0000-4000-8000-000000000013"

type Client {
  Client(
    state: tree_kernel.TreeState,
    session: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
    last_sequence: Int,
    changes: Int,
    retained: Option(forest.NodeRef),
  )
}

type Message {
  Allocation(sender: Int, reference: Int, range: fluid_ids.CreationRange)
  Operation(sender: Int, reference: Int, commit: history.Commit)
}

type Driver {
  Driver(
    clients: List(Client),
    queue: List(Message),
    sequence: Int,
    minimum: Int,
    references: List(#(Int, Int)),
    checkpoints: List(Json),
  )
}

pub fn run(value: Json) -> Result(Json, String) {
  use value <- result.try(input.parse(value))
  use runtime <- result.try(input.field(value, "runtime", input.text))
  use _ <- result.try(require(
    runtime == "upstream-TestTreeProviderLite",
    "unsupported object schedule runtime",
  ))
  use schedules <- result.try(input.field(value, "schedules", input.items))
  use observations <- result.try(list.try_map(schedules, run_schedule))
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn run_schedule(value: JsonValue) -> Result(Json, String) {
  use label <- result.try(input.field(value, "label", input.text))
  use flush <- result.try(input.field(value, "flushMode", input.integer))
  use _ <- result.try(require(flush == 0, "unsupported flush mode"))
  use initial <- result.try(input.get(value, "initial"))
  use driver <- result.try(bootstrap(initial))
  use driver <- result.try(record(driver, "initial"))
  use actions <- result.try(input.field(value, "actions", input.items))
  use driver <- result.try(
    list.try_fold(
      list.index_map(actions, fn(action, index) { #(action, index + 1) }),
      driver,
      fn(driver, entry) { run_action(driver, entry.0, entry.1) },
    ),
  )
  use driver <- result.try(case label {
    "delayed-attached-peer-edit" -> record_retained_reference(driver)
    _ -> Ok(driver)
  })
  use final <- result.try(reload(driver))
  Ok(
    json.object([
      #("label", json.string(label)),
      #(
        "checkpoints",
        json.array(list.reverse([final, ..driver.checkpoints]), fn(value) {
          value
        }),
      ),
    ]),
  )
}

fn record_retained_reference(driver: Driver) -> Result(Driver, String) {
  use client <- result.try(client_at(driver.clients, 0))
  use reference <- result.try(retained_reference(client))
  use point <- result.try(
    tree_kernel.read_reference(client.state, reference) |> native,
  )
  use fields <- result.try(object_fields(point, "retained point"))
  use x <- result.try(field(fields, "x"))
  use y <- result.try(field(fields, "y"))
  use x <- result.try(as_number(x))
  use y <- result.try(as_number(y))
  let checkpoint =
    json.object([
      #("label", json.string("retained-reference-updated")),
      #("x", json.float(x)),
      #("y", json.float(y)),
    ])
  Ok(Driver(..driver, checkpoints: [checkpoint, ..driver.checkpoints]))
}

fn bootstrap(initial: JsonValue) -> Result(Driver, String) {
  use sessions <- result.try(
    input.field(initial, "sessions", fn(value) {
      input.many(value, fn(value) {
        use raw <- result.try(input.text(value))
        fluid_ids.session_id(raw) |> native
      })
    }),
  )
  use _ <- result.try(require(
    list.length(sessions) == 2,
    "object schedules require two sessions",
  ))
  use compressors <- result.try(
    input.field(initial, "compressors", fn(value) {
      input.many(value, fn(value) {
        use raw <- result.try(input.text(value))
        Ok(json.string(raw))
      })
    }),
  )
  use _ <- result.try(require(
    list.length(compressors) == 2,
    "object schedules require two compressors",
  ))
  use compressors <- result.try(
    list.try_map(list.zip(compressors, sessions), fn(entry) {
      fluid_ids.deserialize(entry.0, entry.1) |> native
    }),
  )
  use serialized <- result.try(input.get(initial, "summary"))
  use entry <- result.try(summary_entry(serialized))
  use source_session <- result.try(
    list.first(sessions)
    |> result.map_error(fn(_) { "missing summary session" }),
  )
  use compressor <- result.try(
    list.first(compressors)
    |> result.map_error(fn(_) { "missing summary compressor" }),
  )
  use decoded <- result.try(
    summary.decode(
      entry,
      None,
      source_session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  use data <- result.try(summary_data(decoded))
  use history <- result.try(summary_history(decoded))
  use view <- result.try(
    schema.view_from_json(schema.stored_to_json(decoded.schema))
    |> native,
  )
  use clients <- result.try(
    list.try_map(
      list.index_map(list.zip(sessions, compressors), fn(pair, index) {
        #(pair, index)
      }),
      fn(entry) {
        let #(session, compressor) = entry.0
        let view_id = case entry.1 {
          0 -> view_0
          _ -> view_1
        }
        use view_id <- result.try(fluid_ids.stable_id(view_id) |> native)
        use snapshot <- result.try(
          tree_kernel.snapshot_from_parts(
            view_id,
            decoded.schema,
            data,
            history,
          )
          |> native,
        )
        use state <- result.try(
          tree_kernel.restore(snapshot, view_id, session, view)
          |> native,
        )
        Ok(Client(state, session, compressor, 2, 0, None))
      },
    ),
  )
  use messages <- result.try(input.field(
    initial,
    "initializationMessages",
    input.items,
  ))
  use #(sequence, minimum, references) <- result.try(
    list.try_fold(messages, #(0, 0, []), fn(state, message) {
      use number <- result.try(input.field(
        message,
        "sequenceNumber",
        input.integer,
      ))
      use minimum <- result.try(input.field(
        message,
        "minimumSequenceNumber",
        input.integer,
      ))
      use sender <- result.try(input.field(message, "clientId", input.text))
      use reference <- result.try(input.field(
        message,
        "referenceSequenceNumber",
        input.integer,
      ))
      use sender <- result.try(sender_index(sender))
      use _ <- result.try(require(
        number == state.0 + 1,
        "initialization sequence has a gap",
      ))
      Ok(#(number, minimum, set_reference(state.2, sender, reference)))
    }),
  )
  use _ <- result.try(require(
    sequence == history.sequence_number,
    "summary and initialization sequences differ",
  ))
  Ok(Driver(clients, [], sequence, minimum, references, []))
}

fn sender_index(value: String) -> Result(Int, String) {
  case value {
    "test-client-0" -> Ok(0)
    "test-client-1" -> Ok(1)
    _ -> Error("unsupported initialization client " <> value)
  }
}

fn summary_entry(
  value: JsonValue,
) -> Result(fluid_summary.SummaryEntry, String) {
  use kind <- result.try(input.field(value, "type", input.integer))
  case kind {
    1 -> {
      use tree <- result.try(input.get(value, "tree"))
      case tree {
        VObject(fields) ->
          list.try_map(fields, fn(field) {
            use entry <- result.try(summary_entry(field.1))
            Ok(#(field.0, entry))
          })
          |> result.map(fluid_summary.SummaryTree)
        _ -> Error("summary tree is not an object")
      }
    }
    2 -> {
      use content <- result.try(input.field(value, "content", input.text))
      Ok(fluid_summary.SummaryBlob(<<content:utf8>>))
    }
    _ -> Error("unsupported summary entry")
  }
}

fn summary_data(
  value: summary.TreeSummaryData,
) -> Result(forest.ForestData, String) {
  let summary.TreeSummaryData(
    _,
    summary.ForestSummary(fields),
    summary.DetachedFieldIndex(entries, max_id),
    _,
  ) = value
  use _ <- result.try(require(
    list.length(fields) == list.length(entries) + 1,
    "summary has unindexed forest fields",
  ))
  use root <- result.try(
    list.key_find(fields, "rootFieldKey")
    |> result.map_error(fn(_) { "summary root is missing" }),
  )
  use root <- result.try(singleton(root, "summary root"))
  use detached <- result.try(
    list.try_map(entries, fn(entry) {
      let summary.DetachedField(major, minor, root_id) = entry
      use trees <- result.try(
        list.key_find(fields, "repair-" <> int.to_string(root_id))
        |> result.map_error(fn(_) { "summary repair field is missing" }),
      )
      use tree <- result.try(singleton(trees, "summary repair field"))
      let revision = case major {
        summary.RootRevision -> None
        summary.StableRevision(id) -> Some(id)
      }
      Ok(forest.DetachedTreeData(
        types.AtomId(revision, minor),
        root_id,
        None,
        tree,
      ))
    }),
  )
  let next_id = case entries {
    [] -> max_id
    _ -> max_id + 1
  }
  Ok(forest.ForestData(Some(root), detached, next_id))
}

fn singleton(values: List(a), location: String) -> Result(a, String) {
  case values {
    [value] -> Ok(value)
    _ -> Error(location <> " must contain one tree")
  }
}

fn summary_history(
  value: summary.TreeSummaryData,
) -> Result(history.HistorySnapshot, String) {
  let summary.TreeSummaryData(
    stored,
    _,
    _,
    summary.EditManagerSummary(trunk, branches),
  ) = value
  use _ <- result.try(require(
    branches == [],
    "initial summary has unsupported peer branches",
  ))
  use trunk <- result.try(
    list.try_map(trunk, fn(entry) {
      let summary.SummaryCommit(wire, sequence, batch) = entry
      let codec.WireCommit(revision, originator, changes, _) = wire
      use sequence <- result.try(case sequence {
        Some(value) -> Ok(value)
        None -> Error("unsequenced summary trunk commit")
      })
      use data <- result.try(bootstrap_changes(changes, stored))
      Ok(history.SequencedCommit(
        history.Commit(revision, originator, data),
        SequencePoint(sequence, case batch {
          Some(index) -> index
          _ -> 0
        }),
      ))
    }),
  )
  use last <- result.try(
    list.last(trunk)
    |> result.map_error(fn(_) { "initial summary has no trunk commit" }),
  )
  Ok(history.HistorySnapshot(
    history.InitialBase,
    trunk,
    [],
    last.point.sequence_number,
    0,
  ))
}

fn bootstrap_changes(
  changes: List(codec.TreeChange),
  stored: schema.StoredSchema,
) -> Result(change.Changeset, String) {
  use #(current, data) <- result.try(
    list.try_fold(changes, #(codec.EmptySchema, []), fn(state, item) {
      case item {
        codec.SchemaChange(before, after) -> {
          use _ <- result.try(require(
            before == state.0,
            "initial schema changes are not contiguous",
          ))
          Ok(#(after, state.1))
        }
        codec.DataChange(change) -> Ok(#(state.0, [change, ..state.1]))
      }
    }),
  )
  use _ <- result.try(require(
    current == codec.FixedSchema(stored),
    "initial schema does not match stored schema",
  ))
  case data {
    [only] -> Ok(only)
    _ -> Error("initial commit needs exactly one data change")
  }
}

fn require(condition: Bool, detail: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}

fn native(value: Result(a, error)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn set_reference(
  values: List(#(Int, Int)),
  sender: Int,
  reference: Int,
) -> List(#(Int, Int)) {
  [#(sender, reference), ..list.filter(values, fn(entry) { entry.0 != sender })]
}

fn run_action(
  driver: Driver,
  action: JsonValue,
  number: Int,
) -> Result(Driver, String) {
  use op <- result.try(input.field(action, "op", input.text))
  case op {
    "set" | "clear" -> {
      use sender <- result.try(input.field(action, "client", input.integer))
      use path <- result.try(input.field(action, "path", input.text))
      use client <- result.try(client_at(driver.clients, sender))
      let path = string.split(path, ".")
      use edit <- result.try(case op {
        "clear" -> Ok(ClearField(path))
        _ -> {
          use value <- result.try(input.get(action, "value"))
          use value <- result.try(edit_value(path, value))
          Ok(SetField(path, value))
        }
      })
      use _ <- result.try(
        tree_kernel.validate_edit(client.state, edit) |> native,
      )
      use absent <- result.try(case edit {
        ClearField(path) ->
          tree_kernel.read(client.state, path)
          |> native
          |> result.map(fn(value) { value == None })
        _ -> Ok(False)
      })
      case absent {
        True -> record(driver, "edit-" <> int.to_string(number))
        False -> {
          use retained <- result.try(case path, client.retained {
            ["point"], None ->
              tree_kernel.reference_at(client.state, path)
              |> native
              |> result.map(Some)
            _, _ -> Ok(client.retained)
          })
          apply_edit(driver, Client(..client, retained:), sender, edit, number)
        }
      }
    }
    "deliver" -> deliver(driver)
    "invalid-assignment" | "invalid-clear" -> {
      use client <- result.try(client_at(driver.clients, 0))
      use path <- result.try(input.field(action, "path", input.text))
      let path = string.split(path, ".")
      use edit <- result.try(case op {
        "invalid-clear" -> Ok(ClearField(path))
        _ -> {
          use value <- result.try(input.get(action, "value"))
          use value <- result.try(edit_value(path, value))
          Ok(SetField(path, value))
        }
      })
      use _ <- result.try(case tree_kernel.validate_edit(client.state, edit) {
        Error(_) -> Ok(Nil)
        Ok(_) -> Error("invalid action was accepted")
      })
      use visible <- result.try(tree_kernel.read(client.state, []) |> native)
      use visible <- result.try(visible_root(visible))
      let checkpoint =
        json.object([
          #("label", json.string("atomic-refusal")),
          #("visible", visible),
          #("refused", json.bool(True)),
        ])
      Ok(Driver(..driver, checkpoints: [checkpoint, ..driver.checkpoints]))
    }
    "edit-retained-point" -> {
      use sender <- result.try(input.field(action, "client", input.integer))
      use client <- result.try(client_at(driver.clients, sender))
      use path <- result.try(input.field(action, "path", input.text))
      use _ <- result.try(require(
        path == "x" || path == "y",
        "unsupported retained edit path",
      ))
      use _ <- result.try(input.field(action, "value", number_value))
      use reference <- result.try(retained_reference(client))
      use point <- result.try(
        tree_kernel.read_reference(client.state, reference) |> native,
      )
      use before <- result.try(point_json(point))
      use _ <- result.try(
        case tree_kernel.ensure_attached(client.state, reference) {
          Error(types.InvalidEdit(_, _)) -> Ok(Nil)
          Error(error) -> Error(string.inspect(error))
          Ok(_) -> Error("retained reference is still attached")
        },
      )
      use point <- result.try(
        tree_kernel.read_reference(client.state, reference) |> native,
      )
      use after <- result.try(point_json(point))
      let checkpoint =
        json.object([
          #("label", json.string("detached-edit-refused")),
          #("before", before),
          #("after", after),
          #("refused", json.bool(True)),
        ])
      use driver <- result.try(record(
        Driver(..driver, checkpoints: [checkpoint, ..driver.checkpoints]),
        "after-detached-edit-refusal",
      ))
      Ok(driver)
    }
    _ -> Error("unsupported object action " <> op)
  }
}

fn retained_reference(client: Client) -> Result(forest.NodeRef, String) {
  case client.retained {
    Some(reference) -> Ok(reference)
    None -> Error("retained point reference is missing")
  }
}

fn apply_edit(
  driver: Driver,
  client: Client,
  sender: Int,
  edit: types.Edit,
  number: Int,
) -> Result(Driver, String) {
  use #(compressor, id) <- result.try(
    fluid_ids.generate(client.compressor) |> native,
  )
  use revision <- result.try(fluid_ids.decompress(compressor, id) |> native)
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(case range {
    Some(range) -> Ok(range)
    None -> Error("local commit has no ID creation range")
  })
  use order <- result.try(
    identity_order(Client(..client, compressor:), [revision]),
  )
  use #(state, commit, events) <- result.try(
    tree_kernel.apply_local(client.state, revision, order, edit) |> native,
  )
  let clients =
    replace_client(
      driver.clients,
      sender,
      Client(
        ..client,
        state:,
        compressor:,
        changes: client.changes + list.length(events),
      ),
    )
  let queue =
    list.append(driver.queue, [
      Allocation(sender, client.last_sequence, range),
      Operation(sender, client.last_sequence, commit),
    ])
  record(Driver(..driver, clients:, queue:), "edit-" <> int.to_string(number))
}

fn client_at(clients: List(Client), index: Int) -> Result(Client, String) {
  use _ <- result.try(require(index >= 0, "client index must be nonnegative"))
  clients
  |> list.drop(index)
  |> list.first
  |> result.map_error(fn(_) { "client index is out of range" })
}

fn replace_client(
  clients: List(Client),
  index: Int,
  client: Client,
) -> List(Client) {
  list.index_map(clients, fn(old, position) {
    case position == index {
      True -> client
      False -> old
    }
  })
}

fn edit_value(
  path: List(String),
  value: JsonValue,
) -> Result(TreeValue, String) {
  case path, value {
    ["point"], VObject(_) -> {
      use _ <- result.try(input.exact(value, ["x", "y"]))
      use x <- result.try(input.field(value, "x", number_value))
      use y <- result.try(input.field(value, "y", number_value))
      Ok(
        ObjectValue("org.watershed.shared-tree.m1.Point", [
          #("x", NumberValue(x)),
          #("y", NumberValue(y)),
        ]),
      )
    }
    _, VString(value) -> Ok(StringValue(value))
    _, VBool(value) -> Ok(BooleanValue(value))
    _, VNull -> Ok(NullValue)
    _, VNumber(_) -> number_value(value) |> result.map(NumberValue)
    _, _ -> Error("unsupported action value")
  }
}

fn number_value(value: JsonValue) -> Result(Float, String) {
  case value {
    VNumber(NFloat(value)) -> Ok(value)
    VNumber(NInt(value)) ->
      float.parse(int.to_string(value) <> ".0")
      |> result.map_error(fn(_) { "invalid number" })
    _ -> Error("expected numeric action value")
  }
}

fn identity_order(
  client: Client,
  additional: List(fluid_ids.StableId),
) -> Result(change.IdentityOrder, String) {
  let revisions =
    list.append(tree_kernel.identity_revisions(client.state), additional)
  use entries <- result.try(
    list.try_map(list.unique(revisions), fn(revision) {
      use compressed <- result.try(
        fluid_ids.recompress(client.compressor, revision) |> native,
      )
      use compressed <- result.try(case compressed {
        Some(id) -> Ok(id)
        None -> Error("kernel revision is not in the compressor")
      })
      use operation <- result.try(
        fluid_ids.to_op(client.compressor, compressed) |> native,
      )
      Ok(#(revision, fluid_ids.op_id_to_int(operation)))
    }),
  )
  change.identity_order(entries) |> native
}

fn deliver(driver: Driver) -> Result(Driver, String) {
  list.try_fold(driver.queue, Driver(..driver, queue: []), fn(driver, message) {
    use next <- result.try(deliver_one(driver, message))
    record(next, "delivery-" <> int.to_string(next.sequence))
  })
}

fn deliver_one(driver: Driver, message: Message) -> Result(Driver, String) {
  let #(sender, reference) = case message {
    Allocation(sender, reference, _) -> #(sender, reference)
    Operation(sender, reference, _) -> #(sender, reference)
  }
  use _ <- result.try(client_at(driver.clients, sender))
  let references = set_reference(driver.references, sender, reference)
  let minimum =
    references
    |> list.map(fn(entry) { entry.1 })
    |> list.fold(reference, int.min)
  let sequence = driver.sequence + 1
  use clients <- result.try(
    list.try_map(
      list.index_map(driver.clients, fn(client, index) { #(client, index) }),
      fn(entry) {
        let #(client, index) = entry
        use compressor <- result.try(case message {
          Allocation(_, _, range) ->
            fluid_ids.finalize(client.compressor, range) |> native
          _ -> Ok(client.compressor)
        })
        use #(state, events, compressor) <- result.try(case message {
          Operation(_, reference, commit) -> {
            let candidate = Client(..client, compressor:)
            use order <- result.try(
              identity_order(candidate, [
                commit.revision,
              ]),
            )
            tree_kernel.receive_ordered(
              client.state,
              commit,
              order,
              SequencePoint(sequence, 0),
              reference,
              minimum,
              candidate,
              fn(client) {
                use #(compressor, id) <- result.try(
                  fluid_ids.generate(client.compressor)
                  |> result.map_error(fn(error) {
                    types.InvalidHistory(string.inspect(error))
                  }),
                )
                use revision <- result.try(
                  fluid_ids.decompress(compressor, id)
                  |> result.map_error(fn(error) {
                    types.InvalidHistory(string.inspect(error))
                  }),
                )
                let client = Client(..client, compressor:)
                use order <- result.try(
                  identity_order(client, [revision])
                  |> result.map_error(types.InvalidHistory),
                )
                Ok(#(revision, order, client))
              },
            )
            |> result.map(fn(value) { #(value.0, value.1, value.2.compressor) })
            |> native
          }
          _ -> Ok(#(client.state, [], compressor))
        })
        let _ = index
        Ok(
          Client(
            ..client,
            state:,
            compressor:,
            last_sequence: sequence,
            changes: client.changes + list.length(events),
          ),
        )
      },
    ),
  )
  Ok(Driver(..driver, clients:, sequence:, minimum:, references:))
}

fn record(driver: Driver, label: String) -> Result(Driver, String) {
  use clients <- result.try(
    list.try_map(driver.clients, fn(client) { observe_client(client) }),
  )
  let checkpoint =
    json.object([
      #("label", json.string(label)),
      #("clients", json.array(clients, fn(value) { value })),
    ])
  Ok(
    Driver(
      ..driver,
      clients: list.map(driver.clients, fn(client) {
        Client(..client, changes: 0)
      }),
      checkpoints: [checkpoint, ..driver.checkpoints],
    ),
  )
}

fn observe_client(client: Client) -> Result(Json, String) {
  use root <- result.try(tree_kernel.read(client.state, []) |> native)
  use visible <- result.try(visible_root(root))
  use data <- result.try(tree_kernel.visible_data(client.state) |> native)
  let view = tree_kernel.history_view(client.state)
  use pending <- result.try(
    list.try_map(view.pending, fn(commit) {
      revision_number(client.compressor, commit.revision)
    }),
  )
  use trunk <- result.try(
    list.try_map(view.sequenced.trunk, fn(entry) {
      revision_number(client.compressor, entry.commit.revision)
    }),
  )
  use removed <- result.try(removed_json(data, client.compressor))
  Ok(
    json.object([
      #("visible", visible),
      #("pending", json.array(pending, json.int)),
      #("trunk", json.array(trunk, json.int)),
      #("removed", removed),
      #("changes", json.int(client.changes)),
    ]),
  )
}

fn revision_number(
  compressor: fluid_ids.Compressor,
  revision: fluid_ids.StableId,
) -> Result(Int, String) {
  use id <- result.try(fluid_ids.recompress(compressor, revision) |> native)
  case id {
    Some(id) -> Ok(fluid_ids.session_space_id_to_int(id))
    None -> Error("revision is absent from the compressor")
  }
}

fn reload(driver: Driver) -> Result(Json, String) {
  use client <- result.try(client_at(driver.clients, 0))
  use _ <- result.try(require(
    tree_kernel.history_view(client.state).pending == [],
    "reload has pending edits",
  ))
  use snapshot <- result.try(tree_kernel.snapshot(client.state) |> native)
  let #(stored, _, _) = tree_kernel.snapshot_parts(snapshot)
  use view <- result.try(
    schema.view_from_json(schema.stored_to_json(stored)) |> native,
  )
  use id <- result.try(fluid_ids.stable_id(reload_view) |> native)
  use session <- result.try(fluid_ids.session_id(reload_session) |> native)
  use restored <- result.try(
    tree_kernel.restore(snapshot, id, session, view) |> native,
  )
  use serialized <- result.try(
    fluid_ids.serialize(client.compressor, False) |> native,
  )
  use compressor <- result.try(
    fluid_ids.deserialize(serialized, session) |> native,
  )
  use visible <- result.try(tree_kernel.read(restored, []) |> native)
  use visible <- result.try(visible_root(visible))
  use data <- result.try(tree_kernel.visible_data(restored) |> native)
  use removed <- result.try(removed_json(data, compressor))
  Ok(
    json.object([
      #("label", json.string("reloaded")),
      #("visible", visible),
      #("removed", removed),
    ]),
  )
}

fn visible_root(root: Option(TreeValue)) -> Result(Json, String) {
  use root <- result.try(case root {
    Some(root) -> Ok(root)
    None -> Error("root object is absent")
  })
  use fields <- result.try(object_fields(root, "root"))
  use title <- result.try(field(fields, "title"))
  use enabled <- result.try(field(fields, "enabled"))
  use rating <- result.try(field(fields, "rating"))
  use marker <- result.try(field(fields, "marker"))
  use point <- result.try(field(fields, "point"))
  use point <- result.try(point_json(point))
  use note <- result.try(case list.key_find(fields, "note") {
    Ok(StringValue(note)) ->
      Ok(
        json.object([
          #("present", json.bool(True)),
          #("value", json.string(note)),
        ]),
      )
    Ok(_) -> Error("optional note has an invalid value")
    Error(Nil) -> Ok(json.object([#("present", json.bool(False))]))
  })
  use title <- result.try(as_string(title))
  use enabled <- result.try(as_bool(enabled))
  use rating <- result.try(as_number(rating))
  use _ <- result.try(require(marker == NullValue, "marker is not null"))
  Ok(
    json.object([
      #("title", json.string(title)),
      #("enabled", json.bool(enabled)),
      #("rating", json.float(rating)),
      #("negativeZero", json.bool(False)),
      #("marker", json.null()),
      #("note", note),
      #("point", point),
    ]),
  )
}

fn object_fields(
  value: TreeValue,
  location: String,
) -> Result(List(#(String, TreeValue)), String) {
  case value {
    ObjectValue(_, fields) -> Ok(fields)
    _ -> Error(location <> " is not an object")
  }
}

fn field(fields: List(#(String, a)), name: String) -> Result(a, String) {
  list.key_find(fields, name)
  |> result.map_error(fn(_) { "missing tree field " <> name })
}

fn as_string(value: TreeValue) -> Result(String, String) {
  case value {
    StringValue(value) -> Ok(value)
    _ -> Error("expected string leaf")
  }
}

fn as_bool(value: TreeValue) -> Result(Bool, String) {
  case value {
    BooleanValue(value) -> Ok(value)
    _ -> Error("expected boolean leaf")
  }
}

fn as_number(value: TreeValue) -> Result(Float, String) {
  case value {
    NumberValue(value) -> Ok(value)
    _ -> Error("expected number leaf")
  }
}

fn point_json(value: TreeValue) -> Result(Json, String) {
  use fields <- result.try(object_fields(value, "point"))
  use x <- result.try(field(fields, "x"))
  use y <- result.try(field(fields, "y"))
  use x <- result.try(as_number(x))
  use y <- result.try(as_number(y))
  Ok(
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
    ]),
  )
}

fn removed_json(
  data: forest.ForestData,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use entries <- result.try(
    list.try_map(data.detached, fn(entry) {
      let forest.DetachedTreeData(types.AtomId(major, minor), _, _, value) =
        entry
      use major <- result.try(case major {
        Some(revision) -> {
          use id <- result.try(
            fluid_ids.recompress(compressor, revision) |> native,
          )
          use id <- result.try(case id {
            Some(id) -> Ok(id)
            None -> Error("detached revision is absent from the compressor")
          })
          use op <- result.try(fluid_ids.to_op(compressor, id) |> native)
          Ok(fluid_ids.op_id_to_int(op))
        }
        None -> Ok(0)
      })
      use value <- result.try(content_json(value))
      Ok(
        json.array(
          [
            json.int(major),
            json.int(minor),
            value,
          ],
          fn(value) { value },
        ),
      )
    }),
  )
  use values <- result.try(
    input.parse(json.array(entries, fn(value) { value })),
  )
  normalize_removed(values)
}

fn normalize_removed(value: JsonValue) -> Result(Json, String) {
  use values <- result.try(input.items(value))
  use values <- result.try(
    list.try_map(values, fn(value) {
      case value {
        VArray([_, _, _]) -> Ok(#(canonical_json.to_string(value), value))
        _ -> Error("removed entry must have identity and content")
      }
    }),
  )
  Ok(
    json.array(
      list.sort(values, fn(left, right) {
        canonical_json.compare(left.0, right.0)
      }),
      fn(value) { json_ot.to_json(value.1) },
    ),
  )
}

fn content_json(value: TreeValue) -> Result(Json, String) {
  case value {
    StringValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.string")),
          #("value", json.string(value)),
        ]),
      )
    NumberValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.number")),
          #("value", json.float(value)),
        ]),
      )
    BooleanValue(value) ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.boolean")),
          #("value", json.bool(value)),
        ]),
      )
    NullValue ->
      Ok(
        json.object([
          #("type", json.string("com.fluidframework.leaf.null")),
          #("value", json.null()),
        ]),
      )
    ObjectValue(identifier, fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(entry) {
          use child <- result.try(content_json(entry.1))
          Ok(#(entry.0, json.array([child], fn(value) { value })))
        }),
      )
      Ok(
        json.object([
          #("type", json.string(identifier)),
          #("fields", json.object(fields)),
        ]),
      )
    }
    types.MapValue(_, _) ->
      Error("map values are not supported by kernel fixtures")
  }
}

pub fn project_expected(expected: Json) -> Result(Json, String) {
  use expected <- result.try(input.parse(expected))
  use observations <- result.try(input.field(
    expected,
    "observations",
    input.items,
  ))
  use observations <- result.try(
    list.try_map(observations, fn(observation) {
      use label <- result.try(input.field(observation, "label", input.text))
      use checkpoints <- result.try(input.field(
        observation,
        "checkpoints",
        input.items,
      ))
      use #(_, checkpoints) <- result.try(
        list.try_fold(checkpoints, #(None, []), fn(state, checkpoint) {
          use #(previous, projected) <- result.try(project_checkpoint(
            checkpoint,
            state.0,
          ))
          Ok(#(previous, [projected, ..state.1]))
        }),
      )
      Ok(
        json.object([
          #("label", json.string(label)),
          #(
            "checkpoints",
            json.array(list.reverse(checkpoints), fn(value) { value }),
          ),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn project_checkpoint(
  checkpoint: JsonValue,
  previous: Option(List(#(JsonValue, Int))),
) -> Result(#(Option(List(#(JsonValue, Int))), Json), String) {
  use label <- result.try(input.field(checkpoint, "label", input.text))
  case label {
    "atomic-refusal" -> {
      use visible <- result.try(input.get(checkpoint, "visible"))
      Ok(#(
        previous,
        json.object([
          #("label", json.string(label)),
          #("visible", json_ot.to_json(visible)),
          #("refused", json.bool(True)),
        ]),
      ))
    }
    "detached-edit-refused" -> {
      use before <- result.try(input.get(checkpoint, "before"))
      use after <- result.try(input.get(checkpoint, "after"))
      Ok(#(
        previous,
        json.object([
          #("label", json.string(label)),
          #("before", json_ot.to_json(before)),
          #("after", json_ot.to_json(after)),
          #("refused", json.bool(True)),
        ]),
      ))
    }
    "retained-reference-updated" -> {
      use x <- result.try(input.get(checkpoint, "x"))
      use y <- result.try(input.get(checkpoint, "y"))
      Ok(#(
        previous,
        json.object([
          #("label", json.string(label)),
          #("x", json_ot.to_json(x)),
          #("y", json_ot.to_json(y)),
        ]),
      ))
    }
    "reloaded" -> {
      use visible <- result.try(input.get(checkpoint, "visible"))
      use removed <- result.try(input.get(checkpoint, "removed"))
      use removed <- result.try(normalize_removed(removed))
      Ok(#(
        previous,
        json.object([
          #("label", json.string(label)),
          #("visible", json_ot.to_json(visible)),
          #("removed", removed),
        ]),
      ))
    }
    _ -> {
      use clients <- result.try(input.field(checkpoint, "clients", input.items))
      use projections <- result.try(
        list.try_map(
          list.index_map(clients, fn(client, index) { #(client, index) }),
          fn(entry) {
            use visible <- result.try(input.get(entry.0, "visible"))
            use pending <- result.try(input.get(entry.0, "pending"))
            use trunk <- result.try(input.get(entry.0, "trunk"))
            use removed <- result.try(input.get(entry.0, "removed"))
            use removed <- result.try(normalize_removed(removed))
            use events <- result.try(input.field(entry.0, "events", input.items))
            use _ <- result.try(
              list.try_each(events, fn(event) {
                use name <- result.try(input.text(event))
                require(name == "afterBatch", "unsupported upstream event")
              }),
            )
            let event_count = list.length(events)
            use before <- result.try(case previous {
              Some(values) ->
                values
                |> list.drop(entry.1)
                |> list.first
                |> result.map(Some)
                |> result.map_error(fn(_) { "checkpoint client count changed" })
              None -> Ok(None)
            })
            let changes = case before {
              Some(before) if before.0 != visible -> 1
              _ -> 0
            }
            use _ <- result.try(case before {
              Some(before) ->
                require(
                  event_count >= before.1 + changes,
                  "visible change has no upstream batch event",
                )
              None -> Ok(Nil)
            })
            Ok(
              json.object([
                #("visible", json_ot.to_json(visible)),
                #("pending", json_ot.to_json(pending)),
                #("trunk", json_ot.to_json(trunk)),
                #("removed", removed),
                #("changes", json.int(changes)),
              ]),
            )
          },
        ),
      )
      use current <- result.try(
        list.try_map(clients, fn(client) {
          use visible <- result.try(input.get(client, "visible"))
          use events <- result.try(input.field(client, "events", input.items))
          Ok(#(visible, list.length(events)))
        }),
      )
      Ok(#(
        Some(current),
        json.object([
          #("label", json.string(label)),
          #("clients", json.array(projections, fn(value) { value })),
        ]),
      ))
    }
  }
}
