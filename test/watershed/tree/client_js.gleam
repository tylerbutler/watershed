@target(javascript)
import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import watershed
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/tree/client_protocol as protocol
@target(javascript)
import watershed/tree/client_retained_evidence
@target(javascript)
import watershed/tree/types.{ObjectValue}
@target(javascript)
import watershed/tree_kernel.{SchemaChanged, TreeChanged}

@target(javascript)
@external(javascript, "./client_io.mjs", "descriptor")
fn descriptor() -> String

@target(javascript)
@external(javascript, "./client_io.mjs", "token")
fn token() -> String

@target(javascript)
@external(javascript, "./client_io.mjs", "wait")
fn wait(milliseconds: Int) -> Promise(Nil)

@target(javascript)
@external(javascript, "./client_io.mjs", "lines")
fn lines(
  handle: fn(String) -> Promise(String),
  finish: fn() -> Nil,
) -> Promise(Nil)

@target(javascript)
@external(javascript, "./client_io.mjs", "fail")
fn fail(message: String) -> Nil

@target(javascript)
pub fn main() -> Promise(Nil) {
  case protocol.decode_descriptor(descriptor()) {
    Error(error) -> {
      fail(protocol.encode_startup_error(
        "descriptor-decode-failed",
        "descriptor",
        error.message,
      ))
      promise.resolve(Nil)
    }
    Ok(config) -> {
      let #(ready, signal) = promise.start()
      let document =
        watershed.connect(
          watershed.WatershedConfig(
            url: config.socket_url,
            tenant: config.tenant,
            document: config.document_id,
            token: token(),
            user_id: "shared-tree-client-js",
          ),
          on_ready: signal,
        )
      use opened <- promise.await(ready)
      case opened {
        Error(reason) -> {
          watershed.close(document)
          fail(protocol.encode_startup_error(
            "bootstrap-failed",
            "connect",
            reason,
          ))
          promise.resolve(Nil)
        }
        Ok(Nil) ->
          case watershed.resolve_root(document) {
            Error(reason) -> {
              watershed.close(document)
              fail(protocol.encode_startup_error(
                "root-lookup-failed",
                "resolve-root",
                reason,
              ))
              promise.resolve(Nil)
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
                  promise.resolve(Nil)
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
                      promise.resolve(Nil)
                    }
                    Ok(tree) -> {
                      let active_tree = transport_js.new_cell(tree)
                      let events = transport_js.new_cell([])
                      let subscription = transport_js.new_cell(None)
                      lines(
                        fn(raw) {
                          execute(
                            raw,
                            document,
                            handle,
                            config,
                            active_tree,
                            events,
                            subscription,
                          )
                        },
                        fn() { watershed.close(document) },
                      )
                    }
                  }
              }
          }
      }
    }
  }
}

@target(javascript)
fn observe(
  document: watershed.Document(a),
) -> runtime_core.ConnectionObservation {
  runtime.connection_observation(watershed.runtime_of(document))
}

@target(javascript)
fn response(
  request_id: Option(Int),
  result: Result(Json, protocol.ProtocolError),
  document: watershed.Document(a),
) -> String {
  protocol.encode_response(protocol.Response(
    request_id,
    result,
    observe(document),
  ))
  |> json.to_string
}

@target(javascript)
fn facade(operation: String, error: String) -> protocol.ProtocolError {
  protocol.ProtocolError("facade-error", operation, error)
}

@target(javascript)
fn execute(
  raw: String,
  document: watershed.Document(a),
  handle: Json,
  config: protocol.Descriptor,
  active_tree: Cell(watershed.SharedTree),
  events: Cell(List(Json)),
  subscription: Cell(Option(watershed.SubscriptionToken)),
) -> Promise(String) {
  case protocol.decode_request(raw) {
    Error(error) ->
      promise.resolve(response(protocol.request_id(raw), Error(error), document))
    Ok(protocol.Request(id, command)) -> {
      let tree = transport_js.get_cell(active_tree)
      let result = case command {
        protocol.Read(path) ->
          map_result(
            "read",
            watershed.tree_get(tree, path),
            protocol.encode_read,
          )
        protocol.Set(path, value) ->
          map_result("set", watershed.tree_set(tree, path, value), fn(_) {
            json.null()
          })
        protocol.Clear(path) ->
          map_result("clear", watershed.tree_clear(tree, path), fn(_) {
            json.null()
          })
        protocol.MapGet(path, key) ->
          map_result(
            "map-get",
            watershed.tree_map_get(tree, path, key),
            protocol.encode_read,
          )
        protocol.MapSet(path, key, value) ->
          map_result(
            "map-set",
            watershed.tree_map_set(tree, path, key, value),
            fn(_) { json.null() },
          )
        protocol.MapDelete(path, key) ->
          map_result(
            "map-delete",
            watershed.tree_map_delete(tree, path, key),
            fn(_) { json.null() },
          )
        protocol.MapKeys(path) ->
          map_result(
            "map-keys",
            watershed.tree_map_keys(tree, path),
            protocol.encode_map_keys,
          )
        protocol.MapEntries(path) ->
          map_result(
            "map-entries",
            watershed.tree_map_entries(tree, path),
            protocol.encode_map_entries,
          )
        protocol.SchemaCompatibility(label) ->
          case protocol.descriptor_view(config, label) {
            Error(error) -> Error(error)
            Ok(view) -> {
              use opened <- result.try(
                watershed.open_tree(document, handle, view)
                |> result.map_error(fn(reason) {
                  facade("schema-compatibility", reason)
                }),
              )
              map_result(
                "schema-compatibility",
                watershed.tree_compatibility(opened),
                protocol.encode_compatibility,
              )
            }
          }
        protocol.SchemaUpgrade(label) ->
          case protocol.descriptor_view(config, label) {
            Error(error) -> Error(error)
            Ok(view) -> {
              use opened <- result.try(
                watershed.open_tree(document, handle, view)
                |> result.map_error(fn(reason) {
                  facade("schema-upgrade", reason)
                }),
              )
              map_result(
                "schema-upgrade",
                watershed.tree_upgrade_schema(opened),
                fn(_) { json.null() },
              )
            }
          }
        protocol.OpenView(label) ->
          case protocol.descriptor_view(config, label) {
            Error(error) -> Error(error)
            Ok(view) -> {
              use opened <- result.try(
                watershed.open_tree(document, handle, view)
                |> result.map_error(fn(reason) { facade("open-view", reason) }),
              )
              transport_js.set_cell(active_tree, opened)
              Ok(json.null())
            }
          }
        protocol.ArrayGet(path, index) ->
          map_result(
            "array-get",
            watershed.tree_array_get(tree, path, index),
            protocol.encode_read,
          )
        protocol.ArrayValues(path) ->
          map_result(
            "array-values",
            watershed.tree_array_values(tree, path),
            protocol.encode_array_values,
          )
        protocol.ArrayInsert(path, index, values) ->
          map_result(
            "array-insert",
            watershed.tree_array_insert(tree, path, index, values),
            fn(_) { json.null() },
          )
        protocol.ArrayRemove(path, start, end) ->
          map_result(
            "array-remove",
            watershed.tree_array_remove(tree, path, start, end),
            fn(_) { json.null() },
          )
        protocol.ArrayMove(
          source_path,
          source_start,
          source_end,
          destination_path,
          destination_gap,
        ) ->
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
          )
        protocol.ConstrainedArrayRemove(target_path, path, start, end) ->
          case
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
              Error(facade("constrained-array-remove", reason))
            Error(watershed.Aborted(reason)) ->
              Error(facade("constrained-array-remove", reason))
          }
        protocol.Transaction(scope) ->
          run_transaction(document, tree, events, scope)
        protocol.Checkpoint -> checkpoint(tree, events)
        protocol.Disconnect -> {
          watershed.go_offline(document)
          Ok(json.null())
        }
        protocol.Reconnect -> {
          watershed.go_online(document)
          Ok(json.null())
        }
        protocol.Subscribe -> {
          case transport_js.get_cell(subscription) {
            Some(_) -> Ok(json.null())
            None -> {
              let subscriber =
                watershed.subscribe_tree(tree, fn(event) {
                  case event {
                    SchemaChanged(local) -> {
                      let previous = transport_js.get_cell(events)
                      transport_js.set_cell(events, [
                        json.object([
                          #("kind", json.string("schema")),
                          #("local", json.bool(local)),
                        ]),
                        ..previous
                      ])
                    }
                    TreeChanged(local) -> {
                      let previous = transport_js.get_cell(events)
                      transport_js.set_cell(events, [
                        json.object([
                          #("kind", json.string("data")),
                          #("local", json.bool(local)),
                        ]),
                        ..previous
                      ])
                    }
                  }
                })
              transport_js.set_cell(subscription, Some(subscriber))
              Ok(json.null())
            }
          }
        }
        protocol.Unsubscribe -> {
          case transport_js.get_cell(subscription) {
            None -> Nil
            Some(subscriber) -> watershed.unsubscribe(subscriber)
          }
          transport_js.set_cell(subscription, None)
          Ok(json.null())
        }
        protocol.Close -> {
          watershed.close(document)
          Ok(json.null())
        }
        protocol.PendingSummaryEvidence ->
          map_result(
            "pending-summary-evidence",
            watershed.pending_summary_evidence(document),
            fn(value) { value },
          )
        protocol.AwaitSynced(_) | protocol.Summarize -> Ok(json.null())
      }
      case command {
        protocol.AwaitSynced(watermark) -> {
          use synced <- promise.await(await_synced(document, watermark, 1200))
          promise.resolve(response(Some(id), synced, document))
        }
        protocol.Summarize -> {
          use outcome <- promise.await(watershed.summarize(document))
          promise.resolve(response(
            Some(id),
            map_result("summarize", outcome, json.string),
            document,
          ))
        }
        _ -> promise.resolve(response(Some(id), result, document))
      }
    }
  }
}

@target(javascript)
type ScopeFailure {
  RequestedAbort(protocol.TransactionObservation)
  EditFailed(protocol.ProtocolError)
}

@target(javascript)
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

@target(javascript)
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
      Error(RequestedAbort(protocol.TransactionObservation(
        "aborted",
        scope.constraints,
        applied,
        observed,
        nested,
      )))
  }
}

@target(javascript)
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

@target(javascript)
fn run_transaction(
  document: watershed.Document(a),
  tree: watershed.SharedTree,
  events: Cell(List(Json)),
  scope: protocol.TransactionScope,
) -> Result(Json, protocol.ProtocolError) {
  let before_events = transport_js.get_cell(events)
  let before_pending = observe(document).pending_tree_count
  let outcome = run_transaction_scope(tree, scope)
  let after_events = transport_js.get_cell(events)
  let emitted =
    after_events
    |> list.take(list.length(after_events) - list.length(before_events))
    |> list.reverse
  transport_js.set_cell(events, before_events)
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
    emitted,
    revision,
    outbound,
    final,
  ))
}

@target(javascript)
fn checkpoint(
  tree: watershed.SharedTree,
  events: Cell(List(Json)),
) -> Result(Json, protocol.ProtocolError) {
  use history <- result.try(
    watershed.tree_history_evidence(tree)
    |> result.map_error(fn(reason) { facade("checkpoint", reason) }),
  )
  let changes = list.reverse(transport_js.get_cell(events))
  transport_js.set_cell(events, [])
  case watershed.tree_get(tree, []) {
    Error(reason) ->
      Ok(protocol.encode_checkpoint(
        protocol.encode_read(None),
        [],
        changes,
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
            |> result.map_error(fn(reason) { facade("checkpoint", reason) }),
          )
          client_retained_evidence.encode(snapshot)
          |> result.map(Some)
          |> result.map_error(fn(reason) { facade("checkpoint", reason) })
        }
        _ -> Ok(None)
      })
      Ok(protocol.encode_checkpoint(
        root,
        values,
        changes,
        history,
        None,
        retained,
      ))
    }
  }
}

@target(javascript)
fn map_result(
  operation: String,
  outcome: Result(a, String),
  encode: fn(a) -> Json,
) -> Result(Json, protocol.ProtocolError) {
  case outcome {
    Ok(value) -> Ok(encode(value))
    Error(reason) -> Error(facade(operation, reason))
  }
}

@target(javascript)
fn await_synced(
  document: watershed.Document(a),
  watermark: Int,
  attempts: Int,
) -> Promise(Result(Json, protocol.ProtocolError)) {
  let state = observe(document)
  case
    state.error,
    state.phase == "ready",
    state.synced,
    state.sequence_number
  {
    Some(reason), _, _, _ ->
      promise.resolve(
        Error(protocol.ProtocolError(
          "connection-failed",
          "await-synced",
          reason,
        )),
      )
    None, True, True, Some(sequence) if sequence >= watermark ->
      promise.resolve(Ok(json.int(sequence)))
    None, _, _, _ if attempts <= 0 ->
      promise.resolve(
        Error(protocol.ProtocolError(
          "checkpoint-timeout",
          "await-synced",
          "connection did not reach the required sequenced watermark",
        )),
      )
    None, _, _, _ -> {
      use _ <- promise.await(wait(25))
      await_synced(document, watermark, attempts - 1)
    }
  }
}
