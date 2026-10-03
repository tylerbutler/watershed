@target(erlang)
import gleam/dict.{type Dict}
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/int
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/tree/client_protocol as protocol
@target(erlang)
import watershed/tree/client_retained_evidence
@target(erlang)
import watershed/tree/types.{
  type TreeCommitKind, type TreeCommitOutcome, DefaultCommit, FullyApplied,
  FullyDropped, NewContentOnly, ObjectValue, RedoCommit, UndoCommit,
}
@target(erlang)
import watershed/tree_kernel.{SchemaChanged, TreeChanged}
@target(erlang)
import watershed_beam as watershed

@target(erlang)
@external(erlang, "client_io", "descriptor")
fn descriptor() -> String

@target(erlang)
@external(erlang, "client_io", "token")
fn token() -> String

@target(erlang)
@external(erlang, "client_io", "read_line")
fn read_line() -> Result(String, Nil)

@target(erlang)
@external(erlang, "client_io", "write_line")
fn write_line(line: String) -> Nil

@target(erlang)
@external(erlang, "client_io", "fail")
fn fail(reason: String) -> Nil

@target(erlang)
pub fn main() -> Nil {
  case protocol.decode_descriptor(descriptor()) {
    Error(reason) ->
      fail(protocol.encode_startup_error(
        "descriptor-decode-failed",
        "descriptor",
        reason.message,
      ))
    Ok(config) ->
      case
        watershed.connect(
          host: config.host,
          port: config.port,
          tenant: config.tenant,
          document: config.document_id,
          token: token(),
          user_id: "shared-tree-client-beam",
        )
      {
        Error(reason) ->
          fail(protocol.encode_startup_error(
            "bootstrap-failed",
            "connect",
            reason,
          ))
        Ok(document) ->
          case watershed.resolve_root(document) {
            Error(reason) -> {
              watershed.close(document)
              fail(protocol.encode_startup_error(
                "root-lookup-failed",
                "resolve-root",
                reason,
              ))
            }
            Ok(root) ->
              case watershed.get(root, "tree") {
                Error(_) -> {
                  watershed.close(document)
                  fail(protocol.encode_startup_error(
                    "root-lookup-failed",
                    "resolve-root",
                    "Root map has no tree handle",
                  ))
                }
                Ok(handle) ->
                  case watershed.resolve_tree(document, handle, config.view) {
                    Error(reason) -> {
                      watershed.close(document)
                      fail(protocol.encode_startup_error(
                        "view-resolution-failed",
                        "resolve-view",
                        reason,
                      ))
                    }
                    Ok(tree) -> {
                      let handle_store_ready = process.new_subject()
                      process.spawn_unlinked(fn() {
                        let handle_store = process.new_subject()
                        process.send(handle_store_ready, handle_store)
                        handle_store_loop(handle_store, dict.new(), None, [], 0)
                      })
                      let handle_store =
                        process.receive_forever(from: handle_store_ready)
                      let _ =
                        watershed.subscribe_tree_commits(tree, fn(event) {
                          observe_commit(event, handle_store)
                        })
                      loop(
                        document,
                        handle,
                        config,
                        tree,
                        None,
                        False,
                        handle_store,
                      )
                      watershed.close(document)
                    }
                  }
              }
          }
      }
  }
}

@target(erlang)
fn observe(
  document: watershed.Document(a),
) -> runtime_core.ConnectionObservation {
  runtime_beam.connection_observation(watershed.runtime_subject(document))
}

@target(erlang)
fn response(
  id: Option(Int),
  result: Result(Json, protocol.ProtocolError),
  document: watershed.Document(a),
) -> String {
  protocol.encode_response(protocol.Response(id, result, observe(document)))
  |> json.to_string
}

@target(erlang)
fn map_result(
  operation: String,
  outcome: Result(a, String),
  encode: fn(a) -> Json,
) -> Result(Json, protocol.ProtocolError) {
  case outcome {
    Ok(value) -> Ok(encode(value))
    Error(reason) ->
      Error(protocol.ProtocolError("facade-error", operation, reason))
  }
}

@target(erlang)
fn loop(
  document: watershed.Document(a),
  handle: Json,
  config: protocol.Descriptor,
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
  handle_store: process.Subject(HandleMessage),
) -> Nil {
  case read_line() {
    Error(_) -> Nil
    Ok(line) -> {
      case protocol.decode_request(line) {
        Ok(protocol.Request(_, protocol.Summarize)) -> {
          process.spawn_unlinked(fn() {
            let #(output, _, _, _, _) =
              execute(
                line,
                document,
                handle,
                config,
                tree,
                events,
                active,
                handle_store,
              )
            write_line(output)
          })
          loop(document, handle, config, tree, events, active, handle_store)
        }
        _ -> {
          let #(output, next_tree, next_events, next_active, closing) =
            execute(
              line,
              document,
              handle,
              config,
              tree,
              events,
              active,
              handle_store,
            )
          write_line(output)
          case closing {
            True -> Nil
            False ->
              loop(
                document,
                handle,
                config,
                next_tree,
                next_events,
                next_active,
                handle_store,
              )
          }
        }
      }
    }
  }
}

@target(erlang)
fn execute(
  raw: String,
  document: watershed.Document(a),
  handle: Json,
  config: protocol.Descriptor,
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
  handle_store: process.Subject(HandleMessage),
) -> #(
  String,
  watershed.SharedTree,
  Option(process.Subject(tree_kernel.TreeEvent)),
  Bool,
  Bool,
) {
  case protocol.decode_request(raw) {
    Error(error) -> #(
      response(protocol.request_id(raw), Error(error), document),
      tree,
      events,
      active,
      False,
    )
    Ok(protocol.Request(id, command)) -> {
      let #(outcome, next_tree, next_events, next_active, closing) = case
        command
      {
        protocol.Read(path) -> #(
          map_result(
            "read",
            watershed.tree_get(tree, path),
            protocol.encode_read,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.Set(path, value) -> #(
          map_result("set", watershed.tree_set(tree, path, value), fn(_) {
            json.null()
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.Clear(path) -> #(
          map_result("clear", watershed.tree_clear(tree, path), fn(_) {
            json.null()
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.MapGet(path, key) -> #(
          map_result(
            "map-get",
            watershed.tree_map_get(tree, path, key),
            protocol.encode_read,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.MapSet(path, key, value) -> #(
          map_result(
            "map-set",
            watershed.tree_map_set(tree, path, key, value),
            fn(_) { json.null() },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.MapDelete(path, key) -> #(
          map_result(
            "map-delete",
            watershed.tree_map_delete(tree, path, key),
            fn(_) { json.null() },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.MapKeys(path) -> #(
          map_result(
            "map-keys",
            watershed.tree_map_keys(tree, path),
            protocol.encode_map_keys,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.MapEntries(path) -> #(
          map_result(
            "map-entries",
            watershed.tree_map_entries(tree, path),
            protocol.encode_map_entries,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.SchemaCompatibility(label) -> {
          let outcome = case protocol.descriptor_view(config, label) {
            Error(error) -> Error(error)
            Ok(view) -> {
              use opened <- result.try(
                watershed.open_tree(document, handle, view)
                |> result.map_error(fn(reason) {
                  protocol.ProtocolError(
                    "facade-error",
                    "schema-compatibility",
                    reason,
                  )
                }),
              )
              map_result(
                "schema-compatibility",
                watershed.tree_compatibility(opened),
                protocol.encode_compatibility,
              )
            }
          }
          #(outcome, tree, events, active, False)
        }
        protocol.SchemaUpgrade(label) -> {
          let outcome = case protocol.descriptor_view(config, label) {
            Error(error) -> Error(error)
            Ok(view) -> {
              use opened <- result.try(
                watershed.open_tree(document, handle, view)
                |> result.map_error(fn(reason) {
                  protocol.ProtocolError(
                    "facade-error",
                    "schema-upgrade",
                    reason,
                  )
                }),
              )
              map_result(
                "schema-upgrade",
                watershed.tree_upgrade_schema(opened),
                fn(_) { json.null() },
              )
            }
          }
          #(outcome, tree, events, active, False)
        }
        protocol.OpenView(label) ->
          case protocol.descriptor_view(config, label) {
            Error(error) -> #(Error(error), tree, events, active, False)
            Ok(view) ->
              case watershed.open_tree(document, handle, view) {
                Error(reason) -> #(
                  Error(protocol.ProtocolError(
                    "facade-error",
                    "open-view",
                    reason,
                  )),
                  tree,
                  events,
                  active,
                  False,
                )
                Ok(opened) -> #(Ok(json.null()), opened, events, active, False)
              }
          }
        protocol.ArrayGet(path, index) -> #(
          map_result(
            "array-get",
            watershed.tree_array_get(tree, path, index),
            protocol.encode_read,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.ArrayValues(path) -> #(
          map_result(
            "array-values",
            watershed.tree_array_values(tree, path),
            protocol.encode_array_values,
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.ArrayInsert(path, index, values) -> #(
          map_result(
            "array-insert",
            watershed.tree_array_insert(tree, path, index, values),
            fn(_) { json.null() },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.ArrayRemove(path, start, end) -> #(
          map_result(
            "array-remove",
            watershed.tree_array_remove(tree, path, start, end),
            fn(_) { json.null() },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.ArrayMove(
          source_path,
          source_start,
          source_end,
          destination_path,
          destination_gap,
        ) -> #(
          map_result(
            "array-move",
            watershed.tree_array_move(
              tree,
              source_path,
              source_start,
              source_end,
              destination_path,
              destination_gap,
            ),
            fn(_) { json.null() },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.ConstrainedArrayRemove(target_path, path, start, end) -> {
          let outcome = case
            watershed.tree_transaction(
              tree,
              [watershed.NodeInDocument(target_path)],
              fn(transaction_tree) {
                watershed.tree_array_remove(transaction_tree, path, start, end)
              },
            )
          {
            Ok(_) -> Ok(json.null())
            Error(watershed.TransactionFailed(reason)) ->
              Error(protocol.ProtocolError(
                "facade-error",
                "constrained-array-remove",
                reason,
              ))
            Error(watershed.Aborted(reason)) ->
              Error(protocol.ProtocolError(
                "facade-error",
                "constrained-array-remove",
                reason,
              ))
          }
          #(outcome, tree, events, active, False)
        }
        protocol.Transaction(scope) -> #(
          run_transaction(document, tree, events, active, scope),
          tree,
          events,
          active,
          False,
        )
        protocol.RetainLastLocalCommit(name) -> #(
          process.call(handle_store, waiting: 1000, sending: fn(reply) {
            RetainHandle(
              name,
              fn() {
                watershed.tree_history_evidence(tree)
                |> result.map(protocol.history_revisions)
                |> result.unwrap([])
              },
              reply,
            )
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.RevertibleStatus(name) -> #(
          process.call(handle_store, waiting: 1000, sending: fn(reply) {
            HandleStatus(name, reply)
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.DisposeRevertible(name) -> #(
          process.call(handle_store, waiting: 1000, sending: fn(reply) {
            DisposeHandle(name, reply)
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.Revert(name, dispose) -> #(
          process.call(handle_store, waiting: 1000, sending: fn(reply) {
            RevertHandle(
              name,
              dispose,
              fn() {
                watershed.tree_history_evidence(tree)
                |> result.map(protocol.history_commit_ids)
                |> result.unwrap([])
              },
              reply,
            )
          }),
          tree,
          events,
          active,
          False,
        )
        protocol.Checkpoint -> #(
          checkpoint(tree, events, active, handle_store),
          tree,
          events,
          active,
          False,
        )
        protocol.Subscribe -> {
          let subscriber = case events {
            None -> Some(watershed.subscribe_tree(tree))
            Some(_) -> events
          }
          #(Ok(json.null()), tree, subscriber, True, False)
        }
        protocol.Unsubscribe -> #(Ok(json.null()), tree, events, False, False)
        protocol.Disconnect -> {
          watershed.force_reconnect(document)
          #(Ok(json.null()), tree, events, active, False)
        }
        protocol.Reconnect -> {
          watershed.force_reconnect(document)
          #(Ok(json.null()), tree, events, active, False)
        }
        protocol.AwaitSynced(watermark) -> #(
          await_synced(document, watermark, 1200),
          tree,
          events,
          active,
          False,
        )
        protocol.Summarize -> #(
          map_result("summarize", watershed.summarize(document), json.string),
          tree,
          events,
          active,
          False,
        )
        protocol.PendingSummaryEvidence -> #(
          map_result(
            "pending-summary-evidence",
            watershed.pending_summary_evidence(document),
            fn(value) { value },
          ),
          tree,
          events,
          active,
          False,
        )
        protocol.Close -> #(Ok(json.null()), tree, events, active, True)
      }
      #(
        response(Some(id), outcome, document),
        next_tree,
        next_events,
        next_active,
        closing,
      )
    }
  }
}

@target(erlang)
type ScopeFailure {
  RequestedAbort(protocol.TransactionObservation)
  EditFailed(protocol.ProtocolError)
}

@target(erlang)
fn facade(operation: String, reason: String) -> protocol.ProtocolError {
  protocol.ProtocolError("facade-error", operation, reason)
}

@target(erlang)
fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

@target(erlang)
fn require_revert_evidence(
  condition: Bool,
  message: String,
) -> Result(Nil, protocol.ProtocolError) {
  case condition {
    True -> Ok(Nil)
    False -> Error(facade("revert", message))
  }
}

@target(erlang)
fn await_submitted_revisions(
  revisions: fn() -> List(#(String, String)),
  before: List(#(String, String)),
  retained_revision: Option(String),
  attempts: Int,
) -> Result(List(String), protocol.ProtocolError) {
  use originator <- result.try(
    list.find(before, fn(entry) { Some(entry.0) == retained_revision })
    |> result.map(fn(entry) { entry.1 })
    |> result.map_error(fn(_) {
      facade("revert", "Revert target lacks an originator")
    }),
  )
  let before_revisions = list.map(before, fn(entry) { entry.0 })
  let submitted =
    list.filter(revisions(), fn(candidate) {
      candidate.1 == originator && !list.contains(before_revisions, candidate.0)
    })
    |> list.map(fn(entry) { entry.0 })
  case list.length(submitted), attempts {
    1, _ -> Ok(submitted)
    count, _ if count > 1 ->
      Error(facade("revert", "Revert submitted another operation count"))
    _, 0 ->
      Error(facade("revert", "Revert submitted no attributable operation"))
    _, _ -> {
      process.sleep(25)
      await_submitted_revisions(
        revisions,
        before,
        retained_revision,
        attempts - 1,
      )
    }
  }
}

@target(erlang)
fn apply_transaction_edit(
  tree: watershed.SharedTree,
  edit: protocol.TransactionEdit,
) -> Result(Nil, protocol.ProtocolError) {
  let outcome = case edit {
    protocol.TransactionSet(path, value) ->
      watershed.tree_set(tree, path, value)
    protocol.TransactionClear(path) -> watershed.tree_clear(tree, path)
    protocol.TransactionMapSet(path, key, value) ->
      watershed.tree_map_set(tree, path, key, value)
    protocol.TransactionMapDelete(path, key) ->
      watershed.tree_map_delete(tree, path, key)
    protocol.TransactionArrayInsert(path, index, values) ->
      watershed.tree_array_insert(tree, path, index, values)
    protocol.TransactionArrayRemove(path, start, end) ->
      watershed.tree_array_remove(tree, path, start, end)
    protocol.TransactionArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ) ->
      watershed.tree_array_move(
        tree,
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      )
    protocol.TransactionNested(_) ->
      Error("nested transaction is not a plain edit")
  }
  outcome |> result.map_error(fn(reason) { facade("transaction", reason) })
}

@target(erlang)
fn apply_transaction_scope(
  tree: watershed.SharedTree,
  scope: protocol.TransactionScope,
) -> Result(protocol.TransactionObservation, ScopeFailure) {
  use counted <- result.try(
    list.try_fold(scope.edits, #(0, []), fn(state, edit) {
      let #(applied, nested) = state
      case edit {
        protocol.TransactionNested(inner) ->
          case run_transaction_scope(tree, inner) {
            Ok(observation) -> Ok(#(applied + 1, [observation, ..nested]))
            Error(error) -> Error(EditFailed(error))
          }
        _ ->
          case apply_transaction_edit(tree, edit) {
            Ok(_) -> Ok(#(applied + 1, nested))
            Error(error) -> Error(EditFailed(error))
          }
      }
    }),
  )
  let #(applied, nested) = counted
  let observed = case watershed.tree_get(tree, []) {
    Ok(value) -> protocol.encode_read(value)
    Error(_) -> protocol.encode_read(None)
  }
  let nested = list.reverse(nested)
  case scope.result {
    protocol.CommitScope ->
      Ok(protocol.TransactionObservation(
        "committed",
        scope.constraints,
        applied,
        observed,
        nested,
      ))
    protocol.AbortScope ->
      Error(
        RequestedAbort(protocol.TransactionObservation(
          "aborted",
          scope.constraints,
          applied,
          observed,
          nested,
        )),
      )
  }
}

@target(erlang)
fn run_transaction_scope(
  tree: watershed.SharedTree,
  scope: protocol.TransactionScope,
) -> Result(protocol.TransactionObservation, protocol.ProtocolError) {
  let constraints = list.map(scope.constraints, watershed.NodeInDocument)
  case
    watershed.tree_transaction(tree, constraints, fn(scope_tree) {
      apply_transaction_scope(scope_tree, scope)
    })
  {
    Ok(observation) -> Ok(observation)
    Error(watershed.Aborted(RequestedAbort(observation))) -> Ok(observation)
    Error(watershed.Aborted(EditFailed(error))) -> Error(error)
    Error(watershed.TransactionFailed(reason)) ->
      Error(facade("transaction", reason))
  }
}

@target(erlang)
fn run_transaction(
  document: watershed.Document(a),
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
  scope: protocol.TransactionScope,
) -> Result(Json, protocol.ProtocolError) {
  // The mailbox holds the events of earlier commands. Take them out, run the
  // transaction, then put them back so that the next checkpoint still sees
  // them. The transaction reports only the events that it emitted.
  let subject = case events, active {
    Some(subject), True -> Some(subject)
    _, _ -> None
  }
  let earlier = case subject {
    None -> []
    Some(subject) -> collect_events(subject, [])
  }
  let before_pending = observe(document).pending_tree_count
  let outcome = run_transaction_scope(tree, scope)
  let emitted = case subject {
    None -> []
    Some(subject) -> collect_events(subject, [])
  }
  case subject {
    None -> Nil
    Some(subject) ->
      list.each(earlier, fn(event) { process.send(subject, event) })
  }
  use observation <- result.try(outcome)
  let outbound =
    int.max(observe(document).pending_tree_count - before_pending, 0)
  let revision = case outbound > 0 {
    False -> None
    True ->
      case watershed.tree_history_evidence(tree) {
        Ok(history) -> protocol.last_pending_revision(history)
        Error(_) -> None
      }
  }
  let final = case watershed.tree_get(tree, []) {
    Ok(value) -> protocol.encode_read(value)
    Error(_) -> protocol.encode_read(None)
  }
  Ok(protocol.encode_transaction_result(
    observation,
    list.map(emitted, encode_event),
    revision,
    outbound,
    final,
  ))
}

@target(erlang)
fn collect_events(
  events: process.Subject(tree_kernel.TreeEvent),
  collected: List(tree_kernel.TreeEvent),
) -> List(tree_kernel.TreeEvent) {
  case process.receive(from: events, within: 0) {
    Error(_) -> list.reverse(collected)
    Ok(event) -> collect_events(events, [event, ..collected])
  }
}

@target(erlang)
fn encode_event(event: tree_kernel.TreeEvent) -> Json {
  case event {
    SchemaChanged(local) ->
      json.object([
        #("kind", json.string("schema")),
        #("local", json.bool(local)),
      ])
    TreeChanged(local) ->
      json.object([
        #("kind", json.string("data")),
        #("local", json.bool(local)),
      ])
  }
}

@target(erlang)
fn checkpoint(
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
  handle_store: process.Subject(HandleMessage),
) -> Result(Json, protocol.ProtocolError) {
  use history <- result.try(
    watershed.tree_history_evidence(tree)
    |> result.map_error(fn(reason) {
      protocol.ProtocolError("facade-error", "checkpoint", reason)
    }),
  )
  let changes = case events, active {
    Some(subject), True -> drain(subject, [])
    _, _ -> []
  }
  let commits =
    process.call(handle_store, waiting: 1000, sending: fn(reply) {
      DrainCommits(reply)
    })
  case watershed.tree_get(tree, []) {
    Error(reason) ->
      Ok(protocol.encode_checkpoint(
        protocol.encode_read(None),
        [],
        changes,
        commits,
        history,
        Some(reason),
        None,
      ))
    Ok(root_value) -> {
      let root = protocol.encode_read(root_value)
      use values <- result.try(case root_value {
        Some(ObjectValue("org.watershed.shared-tree.m2.Root", _)) -> {
          use keys <- result.try(map_result(
            "checkpoint",
            watershed.tree_map_keys(tree, ["items"]),
            protocol.encode_map_keys,
          ))
          use entries <- result.try(map_result(
            "checkpoint",
            watershed.tree_map_entries(tree, ["items"]),
            protocol.encode_map_entries,
          ))
          Ok([#("keys", keys), #("entries", entries)])
        }
        Some(ObjectValue("org.watershed.shared-tree.m3.Root", _)) -> Ok([])
        _ ->
          Ok(
            [
              #("title", ["title"]),
              #("enabled", ["enabled"]),
              #("rating", ["rating"]),
              #("marker", ["marker"]),
              #("note", ["note"]),
              #("score", ["score"]),
              #("point", ["point"]),
              #("x", ["point", "x"]),
              #("y", ["point", "y"]),
            ]
            |> list.filter_map(fn(entry) {
              case watershed.tree_get(tree, entry.1) {
                Ok(value) -> Ok(#(entry.0, protocol.encode_read(value)))
                Error(_) -> Error(Nil)
              }
            }),
          )
      })
      use retained <- result.try(case root_value {
        Some(ObjectValue("org.watershed.shared-tree.m3.Root", _)) -> {
          use snapshot <- result.try(
            watershed.tree_retained_snapshot(tree)
            |> result.map_error(fn(reason) {
              protocol.ProtocolError("facade-error", "checkpoint", reason)
            }),
          )
          client_retained_evidence.encode(snapshot)
          |> result.map(Some)
          |> result.map_error(fn(reason) {
            protocol.ProtocolError("facade-error", "checkpoint", reason)
          })
        }
        _ -> Ok(None)
      })
      Ok(protocol.encode_checkpoint(
        root,
        values,
        changes,
        commits,
        history,
        None,
        retained,
      ))
    }
  }
}

@target(erlang)
type HandleMessage {
  CaptureCommit(
    TreeCommitKind,
    Bool,
    Bool,
    Option(watershed.TreeRevertible),
    Option(String),
  )
  SettleCommit(TreeCommitKind, TreeCommitOutcome)
  RetainHandle(
    String,
    fn() -> List(String),
    process.Subject(Result(Json, protocol.ProtocolError)),
  )
  HandleStatus(String, process.Subject(Result(Json, protocol.ProtocolError)))
  DisposeHandle(String, process.Subject(Result(Json, protocol.ProtocolError)))
  RevertHandle(
    String,
    Bool,
    fn() -> List(#(String, String)),
    process.Subject(Result(Json, protocol.ProtocolError)),
  )
  DrainCommits(process.Subject(List(Json)))
}

@target(erlang)
fn commit_kind(kind: TreeCommitKind) -> String {
  case kind {
    DefaultCommit -> "Default"
    UndoCommit -> "Undo"
    RedoCommit -> "Redo"
  }
}

@target(erlang)
fn commit_outcome(outcome: TreeCommitOutcome) -> String {
  case outcome {
    FullyApplied -> "FullyApplied"
    FullyDropped -> "FullyDropped"
    NewContentOnly -> "NewContentOnly"
  }
}

@target(erlang)
fn revertible_status(handle: watershed.TreeRevertible) -> String {
  case watershed.tree_revertible_status(handle) {
    watershed.RevertibleValid -> "Valid"
    watershed.RevertibleDisposed -> "Disposed"
  }
}

@target(erlang)
fn observe_commit(
  event: watershed.TreeCommitEvent,
  handle_store: process.Subject(HandleMessage),
) -> Nil {
  let watershed.TreeCommitEvent(kind, local, factory, settlement) = event
  let acquired = case local, factory {
    True, Some(get_revertible) ->
      case get_revertible() {
        Ok(handle) -> Some(handle)
        Error(_) -> None
      }
    _, _ -> None
  }
  process.send(
    handle_store,
    CaptureCommit(kind, local, option.is_some(factory), acquired, None),
  )
  case settlement {
    None -> Nil
    Some(on_settled) -> {
      let _ =
        on_settled(fn(outcome) {
          process.send(handle_store, SettleCommit(kind, outcome))
        })
      Nil
    }
  }
}

@target(erlang)
fn await_revert_commit(
  subject: process.Subject(HandleMessage),
  commits: List(Json),
  next_event_id: Int,
) -> Result(
  #(
    TreeCommitKind,
    Option(watershed.TreeRevertible),
    Json,
    List(Json),
    Int,
    Option(String),
  ),
  protocol.ProtocolError,
) {
  case process.receive(subject, 1000) {
    Error(_) -> Error(facade("revert", "Revert authored no local commit event"))
    Ok(SettleCommit(kind, outcome)) ->
      await_revert_commit(
        subject,
        [
          json.object([
            #("type", json.string("settlement")),
            #("kind", json.string(commit_kind(kind))),
            #("outcome", json.string(commit_outcome(outcome))),
          ]),
          ..commits
        ],
        next_event_id,
      )
    Ok(CaptureCommit(kind, local, factory_available, acquired, revision)) -> {
      let event_id = next_event_id + 1
      let commit =
        json.object([
          #("type", json.string("commit")),
          #("kind", json.string(commit_kind(kind))),
          #("local", json.bool(local)),
          #("factoryAvailable", json.bool(factory_available)),
          #("handleAcquired", json.bool(option.is_some(acquired))),
          #("eventId", json.int(event_id)),
          #("revision", optional_string(revision)),
        ])
      case local {
        True -> Ok(#(kind, acquired, commit, commits, event_id, revision))
        False -> await_revert_commit(subject, [commit, ..commits], event_id)
      }
    }
    Ok(_) ->
      Error(facade("revert", "Revert produced an unexpected handle operation"))
  }
}

@target(erlang)
fn handle_store_loop(
  subject: process.Subject(HandleMessage),
  handles: Dict(
    String,
    #(watershed.TreeRevertible, TreeCommitKind, Option(String)),
  ),
  last_local: Option(
    #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String)),
  ),
  commits: List(Json),
  next_event_id: Int,
) -> Nil {
  let message = process.receive_forever(from: subject)
  case message {
    CaptureCommit(kind, local, factory_available, acquired, revision) -> {
      let event_id = next_event_id + 1
      let commit =
        json.object([
          #("type", json.string("commit")),
          #("kind", json.string(commit_kind(kind))),
          #("local", json.bool(local)),
          #("factoryAvailable", json.bool(factory_available)),
          #("handleAcquired", json.bool(option.is_some(acquired))),
          #("eventId", json.int(event_id)),
          #("revision", optional_string(revision)),
        ])
      let next = case acquired {
        Some(handle) -> Some(#(handle, kind, event_id, revision))
        None -> last_local
      }
      handle_store_loop(subject, handles, next, [commit, ..commits], event_id)
    }
    SettleCommit(kind, outcome) ->
      handle_store_loop(
        subject,
        handles,
        last_local,
        [
          json.object([
            #("type", json.string("settlement")),
            #("kind", json.string(commit_kind(kind))),
            #("outcome", json.string(commit_outcome(outcome))),
          ]),
          ..commits
        ],
        next_event_id,
      )
    RetainHandle(name, revisions, reply) ->
      case last_local {
        None -> {
          process.send(
            reply,
            Error(facade(
              "retainLastLocalCommit",
              "No unretained local commit is available",
            )),
          )
          handle_store_loop(
            subject,
            handles,
            last_local,
            commits,
            next_event_id,
          )
        }
        Some(entry) -> {
          let revision = case entry.3 {
            Some(_) -> entry.3
            None -> revisions() |> list.last |> option.from_result
          }
          process.send(
            reply,
            Ok(
              json.object([
                #("name", json.string(name)),
                #("kind", json.string(commit_kind(entry.1))),
                #("factoryAvailable", json.bool(True)),
                #("status", json.string(revertible_status(entry.0))),
                #("eventId", json.int(entry.2)),
                #("revision", optional_string(revision)),
              ]),
            ),
          )
          handle_store_loop(
            subject,
            dict.insert(handles, name, #(entry.0, entry.1, revision)),
            None,
            commits,
            next_event_id,
          )
        }
      }
    HandleStatus(name, reply) -> {
      let outcome = case dict.get(handles, name) {
        Error(_) ->
          Error(facade(
            "revertibleStatus",
            "Unknown revertible handle: " <> name,
          ))
        Ok(entry) ->
          Ok(
            json.object([
              #("name", json.string(name)),
              #("status", json.string(revertible_status(entry.0))),
            ]),
          )
      }
      process.send(reply, outcome)
      handle_store_loop(subject, handles, last_local, commits, next_event_id)
    }
    DisposeHandle(name, reply) -> {
      let outcome = case dict.get(handles, name) {
        Error(_) ->
          Error(facade(
            "disposeRevertible",
            "Unknown revertible handle: " <> name,
          ))
        Ok(entry) ->
          watershed.tree_dispose_revertible(entry.0)
          |> result.map(fn(_) {
            json.object([
              #("name", json.string(name)),
              #("status", json.string(revertible_status(entry.0))),
            ])
          })
          |> result.map_error(fn(reason) { facade("disposeRevertible", reason) })
      }
      process.send(reply, outcome)
      handle_store_loop(subject, handles, last_local, commits, next_event_id)
    }
    RevertHandle(name, dispose, revisions, reply) ->
      case dict.get(handles, name) {
        Error(_) -> {
          process.send(
            reply,
            Error(facade("revert", "Unknown revertible handle: " <> name)),
          )
          handle_store_loop(
            subject,
            handles,
            last_local,
            commits,
            next_event_id,
          )
        }
        Ok(entry) -> {
          let before_revisions = revisions()
          let outcome = case watershed.tree_revert(entry.0, dispose) {
            Error(reason) -> Error(facade("revert", reason))
            Ok(_) ->
              case await_revert_commit(subject, commits, next_event_id) {
                Error(error) -> Error(error)
                Ok(#(
                  authored_kind,
                  acquired,
                  commit,
                  observed_commits,
                  event_id,
                  _revision,
                )) -> {
                  use submitted_revisions <- result.try(
                    await_submitted_revisions(
                      revisions,
                      before_revisions,
                      entry.2,
                      40,
                    ),
                  )
                  let authored_event_ids = [event_id]
                  use _ <- result.try(require_revert_evidence(
                    list.length(authored_event_ids) == 1,
                    "Revert authored another local commit count",
                  ))
                  use _ <- result.try(require_revert_evidence(
                    list.length(submitted_revisions) == 1,
                    "Revert submitted another operation count",
                  ))
                  let submitted_revision =
                    list.first(submitted_revisions) |> option.from_result
                  Ok(#(
                    json.object([
                      #("name", json.string(name)),
                      #("authoredKind", json.string(commit_kind(authored_kind))),
                      #("status", json.string(revertible_status(entry.0))),
                      #("settlement", json.string("Pending")),
                      #(
                        "authoredCount",
                        json.int(list.length(authored_event_ids)),
                      ),
                      #(
                        "outboundCount",
                        json.int(list.length(submitted_revisions)),
                      ),
                      #(
                        "authoredEventIds",
                        json.array(authored_event_ids, json.int),
                      ),
                      #(
                        "submittedRevisions",
                        json.array(submitted_revisions, json.string),
                      ),
                    ]),
                    authored_kind,
                    acquired,
                    commit,
                    observed_commits,
                    event_id,
                    submitted_revision,
                  ))
                }
              }
          }
          case outcome {
            Error(error) -> {
              process.send(reply, Error(error))
              handle_store_loop(
                subject,
                handles,
                last_local,
                commits,
                next_event_id,
              )
            }
            Ok(#(
              value,
              authored_kind,
              acquired,
              commit,
              observed_commits,
              event_id,
              revision,
            )) -> {
              process.send(reply, Ok(value))
              let next = case acquired {
                Some(handle) ->
                  Some(#(handle, authored_kind, event_id, revision))
                None -> last_local
              }
              handle_store_loop(
                subject,
                handles,
                next,
                [commit, ..observed_commits],
                event_id,
              )
            }
          }
        }
      }
    DrainCommits(reply) -> {
      process.send(reply, list.reverse(commits))
      handle_store_loop(subject, handles, last_local, [], next_event_id)
    }
  }
}

@target(erlang)
fn drain(
  events: process.Subject(tree_kernel.TreeEvent),
  collected: List(Json),
) -> List(Json) {
  list.append(collected, list.map(collect_events(events, []), encode_event))
}

@target(erlang)
fn await_synced(
  document: watershed.Document(a),
  watermark: Int,
  attempts: Int,
) -> Result(Json, protocol.ProtocolError) {
  let state = observe(document)
  case
    state.error,
    state.phase == "ready",
    state.synced,
    state.sequence_number
  {
    Some(reason), _, _, _ ->
      Error(protocol.ProtocolError("connection-failed", "await-synced", reason))
    None, True, True, Some(sequence) if sequence >= watermark ->
      Ok(json.int(sequence))
    None, _, _, _ if attempts <= 0 ->
      Error(protocol.ProtocolError(
        "checkpoint-timeout",
        "await-synced",
        "connection did not reach the required sequenced watermark",
      ))
    None, _, _, _ -> {
      process.sleep(25)
      await_synced(document, watermark, attempts - 1)
    }
  }
}
