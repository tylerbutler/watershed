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
import watershed/canonical_json
@target(erlang)
import watershed/id
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
@external(erlang, "client_io", "runtime_state_evidence")
fn runtime_state_evidence(runtime: process.Subject(runtime_beam.Msg)) -> String

@target(erlang)
pub fn main() -> Nil {
  case protocol.decode_descriptor(descriptor()) {
    Error(reason) ->
      fail(protocol.encode_startup_error(
        "descriptor-decode-failed",
        "descriptor",
        reason.message,
      ))
    Ok(config) -> {
      let outbound_store_ready = process.new_subject()
      process.spawn_unlinked(fn() {
        let outbound_store = process.new_subject()
        process.send(outbound_store_ready, outbound_store)
        outbound_store_loop(outbound_store, [], 0)
      })
      let outbound_store = process.receive_forever(from: outbound_store_ready)
      case
        watershed.connect_observing(
          host: config.host,
          port: config.port,
          tenant: config.tenant,
          document: config.document_id,
          token: token(),
          user_id: "shared-tree-client-beam",
          observe_push: fn(event, payload) {
            case event {
              "submitOp" ->
                process.send(outbound_store, RecordOutbound(payload))
              _ -> Nil
            }
          },
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
                      let object_store_ready = process.new_subject()
                      process.spawn_unlinked(fn() {
                        let object_store = process.new_subject()
                        process.send(object_store_ready, object_store)
                        object_store_loop(
                          object_store,
                          dict.new(),
                          dict.new(),
                          dict.from_list([#("main", tree)]),
                        )
                      })
                      let object_store =
                        process.receive_forever(from: object_store_ready)
                      let handle_store_ready = process.new_subject()
                      process.spawn_unlinked(fn() {
                        let handle_store = process.new_subject()
                        process.send(handle_store_ready, handle_store)
                        handle_store_loop(
                          handle_store,
                          dict.new(),
                          dict.new(),
                          dict.new(),
                          0,
                        )
                      })
                      let handle_store =
                        process.receive_forever(from: handle_store_ready)
                      let branch_store_ready = process.new_subject()
                      process.spawn_unlinked(fn() {
                        let branch_store = process.new_subject()
                        process.send(branch_store_ready, branch_store)
                        branch_store_loop(branch_store, dict.new())
                      })
                      let branch_store =
                        process.receive_forever(from: branch_store_ready)
                      let _ =
                        watershed.subscribe_tree_commits(tree, fn(event) {
                          observe_commit(
                            event,
                            protocol.Document("main"),
                            handle_store,
                          )
                        })
                      loop(
                        document,
                        handle,
                        config,
                        tree,
                        dict.new(),
                        False,
                        handle_store,
                        outbound_store,
                        branch_store,
                        object_store,
                      )
                      watershed.close(document)
                    }
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
  events: Dict(
    protocol.TreeOwner,
    #(process.Subject(tree_kernel.TreeEvent), Bool),
  ),
  active: Bool,
  handle_store: process.Subject(HandleMessage),
  outbound_store: process.Subject(OutboundMessage),
  branch_store: process.Subject(BranchMessage),
  object_store: process.Subject(ObjectMessage),
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
                outbound_store,
                branch_store,
                object_store,
              )
            write_line(output)
          })
          loop(
            document,
            handle,
            config,
            tree,
            events,
            active,
            handle_store,
            outbound_store,
            branch_store,
            object_store,
          )
        }
        _ -> {
          let #(output, next_tree, next_subscriptions, next_active, closing) =
            execute(
              line,
              document,
              handle,
              config,
              tree,
              events,
              active,
              handle_store,
              outbound_store,
              branch_store,
              object_store,
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
                next_subscriptions,
                next_active,
                handle_store,
                outbound_store,
                branch_store,
                object_store,
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
  events: Dict(
    protocol.TreeOwner,
    #(process.Subject(tree_kernel.TreeEvent), Bool),
  ),
  active: Bool,
  handle_store: process.Subject(HandleMessage),
  outbound_store: process.Subject(OutboundMessage),
  branch_store: process.Subject(BranchMessage),
  object_store: process.Subject(ObjectMessage),
) -> #(
  String,
  watershed.SharedTree,
  Dict(protocol.TreeOwner, #(process.Subject(tree_kernel.TreeEvent), Bool)),
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
      let #(selected, command) = selected_command(command)
      let owner = protocol.selected_owner(selected)
      let selected_tree = case selected {
        None -> Ok(tree)
        Some(name) ->
          process.call(object_store, waiting: 5000, sending: fn(reply) {
            LookupTree(name, reply)
          })
          |> result.map_error(fn(_) { facade("tree", "Unknown tree: " <> name) })
      }
      let #(outcome, next_tree, next_events, next_active, closing) = case
        selected_tree
      {
        Error(error) -> #(Error(error), tree, events, active, False)
        Ok(command_tree) ->
          case command {
            protocol.CreateDataStore(name) -> {
              let outcome = {
                use _ <- result.try(require_new_object_name(
                  object_store,
                  command,
                ))
                use store <- result.try(
                  watershed.create_data_store(document)
                  |> result.map_error(fn(reason) {
                    facade("create-data-store", reason)
                  }),
                )
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreDataStore(name, store, reply)
                  })
                  |> ensure_fresh("create-data-store", name),
                )
                use root <- result.try(
                  watershed.data_store_root(store)
                  |> result.map_error(fn(reason) {
                    facade("create-data-store", reason)
                  }),
                )
                Ok(watershed.handle_of(root))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.RootMap(name) -> {
              let outcome = {
                use map <- result.try(
                  watershed.resolve_root(document)
                  |> result.map_error(fn(reason) { facade("root-map", reason) }),
                )
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreMap(name, map, reply)
                  })
                  |> ensure_fresh("root-map", name),
                )
                Ok(watershed.handle_of(map))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.DataStoreRoot(store_name, name) -> {
              let outcome = {
                use store <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    LookupDataStore(store_name, reply)
                  })
                  |> result.map_error(fn(_) {
                    facade(
                      "data-store-root",
                      "Unknown data store: " <> store_name,
                    )
                  }),
                )
                use map <- result.try(
                  watershed.data_store_root(store)
                  |> result.map_error(fn(reason) {
                    facade("data-store-root", reason)
                  }),
                )
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreMap(name, map, reply)
                  })
                  |> ensure_fresh("data-store-root", name),
                )
                Ok(watershed.handle_of(map))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.CreateMap(name, store_name) -> {
              let outcome = {
                use _ <- result.try(require_new_object_name(
                  object_store,
                  command,
                ))
                use map <- result.try(case store_name {
                  None ->
                    watershed.create_map(document)
                    |> result.map_error(fn(reason) {
                      facade("create-map", reason)
                    })
                  Some(store_name) -> {
                    use store <- result.try(
                      process.call(
                        object_store,
                        waiting: 5000,
                        sending: fn(reply) {
                          LookupDataStore(store_name, reply)
                        },
                      )
                      |> result.map_error(fn(_) {
                        facade(
                          "create-map",
                          "Unknown data store: " <> store_name,
                        )
                      }),
                    )
                    watershed.create_map_in(document, store)
                    |> result.map_error(fn(reason) {
                      facade("create-map", reason)
                    })
                  }
                })
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreMap(name, map, reply)
                  })
                  |> ensure_fresh("create-map", name),
                )
                Ok(watershed.handle_of(map))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.OpenMap(name, marker) -> {
              let outcome = {
                use map <- result.try(
                  watershed.resolve(document, marker)
                  |> result.map_error(fn(reason) { facade("open-map", reason) }),
                )
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreMap(name, map, reply)
                  })
                  |> ensure_fresh("open-map", name),
                )
                Ok(watershed.handle_of(map))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.SharedMapGet(name, key) -> {
              let outcome = {
                use map <- result.try(named_map(
                  object_store,
                  name,
                  "shared-map-get",
                ))
                Ok(case watershed.get(map, key) {
                  Ok(value) ->
                    json.object([
                      #("present", json.bool(True)),
                      #("value", value),
                    ])
                  Error(_) -> json.object([#("present", json.bool(False))])
                })
              }
              #(outcome, tree, events, active, False)
            }
            protocol.SharedMapSet(name, key, value) -> {
              let outcome = {
                use map <- result.try(named_map(
                  object_store,
                  name,
                  "shared-map-set",
                ))
                map_result(
                  "shared-map-set",
                  watershed.set_checked(map, key, value),
                  fn(_) { json.null() },
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.SharedMapDelete(name, key) -> {
              let outcome = {
                use map <- result.try(named_map(
                  object_store,
                  name,
                  "shared-map-delete",
                ))
                map_result(
                  "shared-map-delete",
                  watershed.delete_checked(map, key),
                  fn(_) { json.null() },
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.SharedMapEntries(name) -> {
              let outcome = {
                use map <- result.try(named_map(
                  object_store,
                  name,
                  "shared-map-entries",
                ))
                Ok(encode_shared_map_entries(watershed.entries(map)))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.CreateTree(name, store_name, stored, initial, view) -> {
              let outcome = {
                use _ <- result.try(require_new_object_name(
                  object_store,
                  command,
                ))
                use created <- result.try(case store_name {
                  None ->
                    watershed.create_tree(document, stored, Some(initial), view)
                    |> result.map_error(fn(reason) {
                      facade("create-tree", reason)
                    })
                  Some(store_name) -> {
                    use store <- result.try(
                      process.call(
                        object_store,
                        waiting: 5000,
                        sending: fn(reply) {
                          LookupDataStore(store_name, reply)
                        },
                      )
                      |> result.map_error(fn(_) {
                        facade(
                          "create-tree",
                          "Unknown data store: " <> store_name,
                        )
                      }),
                    )
                    watershed.create_tree_in(
                      document,
                      store,
                      stored,
                      Some(initial),
                      view,
                    )
                    |> result.map_error(fn(reason) {
                      facade("create-tree", reason)
                    })
                  }
                })
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreTree(name, created, reply)
                  })
                  |> ensure_fresh("create-tree", name),
                )
                let _ =
                  watershed.subscribe_tree_commits(created, fn(event) {
                    observe_commit(event, protocol.Document(name), handle_store)
                  })
                Ok(watershed.tree_handle_of(created))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.OpenTree(name, marker, view) -> {
              let outcome = {
                use opened <- result.try(
                  watershed.resolve_tree(document, marker, view)
                  |> result.map_error(fn(reason) { facade("open-tree", reason) }),
                )
                use _ <- result.try(
                  process.call(object_store, waiting: 5000, sending: fn(reply) {
                    StoreTree(name, opened, reply)
                  })
                  |> ensure_fresh("open-tree", name),
                )
                let _ =
                  watershed.subscribe_tree_commits(opened, fn(event) {
                    observe_commit(event, protocol.Document(name), handle_store)
                  })
                Ok(watershed.tree_handle_of(opened))
              }
              #(outcome, tree, events, active, False)
            }
            protocol.SelectedTree(_, _) -> #(
              Error(facade("tree", "Nested tree selection is invalid")),
              tree,
              events,
              active,
              False,
            )
            protocol.Read(path) -> #(
              map_result(
                "read",
                watershed.tree_get(command_tree, path),
                protocol.encode_read,
              ),
              tree,
              events,
              active,
              False,
            )
            protocol.Set(path, value) -> #(
              map_result(
                "set",
                watershed.tree_set(command_tree, path, value),
                fn(_) { json.null() },
              ),
              tree,
              events,
              active,
              False,
            )
            protocol.Clear(path) -> #(
              map_result(
                "clear",
                watershed.tree_clear(command_tree, path),
                fn(_) { json.null() },
              ),
              tree,
              events,
              active,
              False,
            )
            protocol.MapGet(path, key) -> #(
              map_result(
                "map-get",
                watershed.tree_map_get(command_tree, path, key),
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
                watershed.tree_map_set(command_tree, path, key, value),
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
                watershed.tree_map_delete(command_tree, path, key),
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
                watershed.tree_map_keys(command_tree, path),
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
                watershed.tree_map_entries(command_tree, path),
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
                    watershed.open_tree(
                      document,
                      watershed.tree_handle_of(command_tree),
                      view,
                    )
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
                    watershed.open_tree(
                      document,
                      watershed.tree_handle_of(command_tree),
                      view,
                    )
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
                  case
                    watershed.open_tree(
                      document,
                      watershed.tree_handle_of(command_tree),
                      view,
                    )
                  {
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
                    Ok(opened) -> #(
                      Ok(json.null()),
                      case selected {
                        None -> {
                          process.send(
                            object_store,
                            ReplaceTree("main", opened),
                          )
                          opened
                        }
                        Some("main") -> {
                          process.send(
                            object_store,
                            ReplaceTree("main", opened),
                          )
                          opened
                        }
                        Some(name) -> {
                          process.send(object_store, ReplaceTree(name, opened))
                          tree
                        }
                      },
                      events,
                      active,
                      False,
                    )
                  }
              }
            protocol.ArrayGet(path, index) -> #(
              map_result(
                "array-get",
                watershed.tree_array_get(command_tree, path, index),
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
                watershed.tree_array_values(command_tree, path),
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
                watershed.tree_array_insert(command_tree, path, index, values),
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
                watershed.tree_array_remove(command_tree, path, start, end),
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
                  command_tree,
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
                  command_tree,
                  [watershed.NodeInDocument(target_path)],
                  fn(transaction_tree) {
                    watershed.tree_array_remove(
                      transaction_tree,
                      path,
                      start,
                      end,
                    )
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
              run_transaction(document, command_tree, owner, events, scope),
              tree,
              events,
              active,
              False,
            )
            protocol.Fork(source, name) -> {
              let outcome = {
                let branch_owner = protocol.local_branch_owner(owner, name)
                use _ <- result.try(
                  case
                    name == "main"
                    || result.is_ok(
                      process.call(
                        branch_store,
                        waiting: 5000,
                        sending: fn(reply) { LookupBranch(branch_owner, reply) },
                      ),
                    )
                  {
                    True ->
                      Error(facade(
                        "fork",
                        "Branch name already exists: " <> name,
                      ))
                    False -> Ok(Nil)
                  },
                )
                use source_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  source,
                  "fork",
                ))
                use branch <- result.try(
                  watershed.tree_fork(source_tree)
                  |> result.map_error(fn(reason) { facade("fork", reason) }),
                )
                let stored =
                  process.call(branch_store, waiting: 5000, sending: fn(reply) {
                    StoreBranch(branch_owner, branch, reply)
                  })
                use _ <- result.try(case stored {
                  True -> Ok(Nil)
                  False -> {
                    let _ = watershed.tree_dispose_branch(branch)
                    Error(facade("fork", "Branch name already exists: " <> name))
                  }
                })
                let _ =
                  watershed.subscribe_tree_commits(branch, fn(event) {
                    observe_commit(event, branch_owner, handle_store)
                  })
                Ok(
                  json.object([
                    #("name", json.string(name)),
                    #("source", json.string(source)),
                    #("status", json.string("BranchValid")),
                  ]),
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.BranchEditCommand(branch, edit) -> {
              let before = outbound_snapshot(outbound_store)
              let outcome = {
                use branch_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  branch,
                  "branchEdit",
                ))
                use observation <- result.try(run_branch_edit(
                  document,
                  branch_tree,
                  edit,
                ))
                let after = outbound_snapshot(outbound_store)
                Ok(
                  json.object([
                    #("branch", json.string(branch)),
                    #("authoredCount", json.int(1)),
                    #(
                      "outboundCount",
                      json.int(list.length(after) - list.length(before)),
                    ),
                    #("observation", observation),
                  ]),
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.RebaseBranch(source, target) -> {
              let outcome = {
                use source_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  source,
                  "rebaseBranch",
                ))
                use target_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  target,
                  "rebaseBranch",
                ))
                use _ <- result.try(
                  watershed.tree_rebase_onto(source_tree, target_tree)
                  |> result.map_error(fn(reason) {
                    facade("rebaseBranch", reason)
                  }),
                )
                Ok(
                  json.object([
                    #("source", json.string(source)),
                    #("target", json.string(target)),
                  ]),
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.MergeBranch(target, source, dispose) -> {
              let outcome = {
                use target_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  target,
                  "mergeBranch",
                ))
                use source_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  source,
                  "mergeBranch",
                ))
                use _ <- result.try(
                  watershed.tree_merge(target_tree, source_tree, dispose)
                  |> result.map_error(fn(reason) {
                    facade("mergeBranch", reason)
                  }),
                )
                case dispose && source != "main" {
                  True ->
                    process.send(
                      branch_store,
                      RemoveBranch(protocol.local_branch_owner(owner, source)),
                    )
                  False -> Nil
                }
                Ok(
                  json.object([
                    #("target", json.string(target)),
                    #("source", json.string(source)),
                    #("disposed", json.bool(dispose)),
                  ]),
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.DisposeBranch(name) -> {
              let outcome = {
                use branch <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  name,
                  "disposeBranch",
                ))
                use _ <- result.try(
                  watershed.tree_dispose_branch(branch)
                  |> result.map_error(fn(reason) {
                    facade("disposeBranch", reason)
                  }),
                )
                process.send(
                  branch_store,
                  RemoveBranch(protocol.local_branch_owner(owner, name)),
                )
                Ok(
                  json.object([
                    #("name", json.string(name)),
                    #("status", json.string("BranchDisposed")),
                  ]),
                )
              }
              #(outcome, tree, events, active, False)
            }
            protocol.RetainLastLocalCommit(name) -> #(
              process.call(handle_store, waiting: 1000, sending: fn(reply) {
                RetainHandle(
                  name,
                  owner,
                  fn() {
                    watershed.tree_history_evidence(command_tree)
                    |> result.map(protocol.history_commit_ids)
                    |> result.unwrap([])
                  },
                  fn() { outbound_snapshot(outbound_store) },
                  reply,
                )
              }),
              tree,
              events,
              active,
              False,
            )
            protocol.BranchRetainLastLocalCommit(branch, name) -> {
              let outcome = {
                use branch_tree <- result.try(named_branch_tree(
                  command_tree,
                  branch_store,
                  owner,
                  branch,
                  "retainLastLocalCommit",
                ))
                process.call(handle_store, waiting: 1000, sending: fn(reply) {
                  RetainHandle(
                    name,
                    protocol.checkout_owner(owner, branch),
                    fn() {
                      watershed.tree_history_evidence(branch_tree)
                      |> result.map(protocol.history_commit_ids)
                      |> result.unwrap([])
                    },
                    fn() { outbound_snapshot(outbound_store) },
                    reply,
                  )
                })
              }
              #(outcome, tree, events, active, False)
            }
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
                    watershed.tree_history_evidence(command_tree)
                    |> result.map(protocol.history_commit_ids)
                    |> result.unwrap([])
                  },
                  fn() { outbound_snapshot(outbound_store) },
                  reply,
                )
              }),
              tree,
              events,
              active,
              False,
            )
            protocol.Checkpoint -> #(
              checkpoint(document, command_tree, owner, events, handle_store),
              tree,
              events,
              active,
              False,
            )
            protocol.Subscribe -> {
              let next_events = case dict.get(events, owner) {
                Error(_) ->
                  dict.insert(events, owner, #(
                    watershed.subscribe_tree(command_tree),
                    True,
                  ))
                Ok(#(subject, _)) ->
                  dict.insert(events, owner, #(subject, True))
              }
              #(Ok(json.null()), tree, next_events, active, False)
            }
            protocol.Unsubscribe -> {
              let next_events = case dict.get(events, owner) {
                Error(_) -> events
                Ok(#(subject, _)) ->
                  dict.insert(events, owner, #(subject, False))
              }
              #(Ok(json.null()), tree, next_events, active, False)
            }
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
            protocol.Summarize -> {
              let snapshot_sequence_number = observe(document).sequence_number
              #(
                map_result(
                  "summarize",
                  watershed.summarize(document),
                  fn(version) {
                    json.object([
                      #("version", json.string(version)),
                      #(
                        "snapshotSequenceNumber",
                        optional_int(snapshot_sequence_number),
                      ),
                    ])
                  },
                ),
                tree,
                events,
                active,
                False,
              )
            }
            protocol.RuntimeStateEvidence -> #(
              Ok(
                json.string(
                  runtime_state_evidence(watershed.runtime_subject(document)),
                ),
              ),
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
fn selected_command(
  command: protocol.Command,
) -> #(Option(String), protocol.Command) {
  case command {
    protocol.SelectedTree(name, command) -> #(Some(name), command)
    _ -> #(None, command)
  }
}

@target(erlang)
fn ensure_fresh(
  fresh: Bool,
  operation: String,
  name: String,
) -> Result(Nil, protocol.ProtocolError) {
  case fresh {
    True -> Ok(Nil)
    False -> Error(facade(operation, "Object name already exists: " <> name))
  }
}

@target(erlang)
fn require_new_object_name(
  store: process.Subject(ObjectMessage),
  command: protocol.Command,
) -> Result(Nil, protocol.ProtocolError) {
  case command {
    protocol.CreateDataStore(name) ->
      process.call(store, waiting: 5000, sending: fn(reply) {
        LookupDataStore(name, reply)
      })
      |> result.is_error
      |> ensure_fresh("create-data-store", name)
    protocol.CreateMap(name, _) ->
      process.call(store, waiting: 5000, sending: fn(reply) {
        LookupMap(name, reply)
      })
      |> result.is_error
      |> ensure_fresh("create-map", name)
    protocol.CreateTree(name, _, _, _, _) ->
      process.call(store, waiting: 5000, sending: fn(reply) {
        LookupTree(name, reply)
      })
      |> result.is_error
      |> ensure_fresh("create-tree", name)
    _ -> Ok(Nil)
  }
}

@target(erlang)
fn named_map(
  store: process.Subject(ObjectMessage),
  name: String,
  operation: String,
) -> Result(watershed.SharedMap, protocol.ProtocolError) {
  process.call(store, waiting: 5000, sending: fn(reply) {
    LookupMap(name, reply)
  })
  |> result.map_error(fn(_) {
    facade(operation, "Unknown shared map: " <> name)
  })
}

@target(erlang)
fn encode_shared_map_entries(entries: List(#(String, Json))) -> Json {
  entries
  |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
  |> list.map(fn(entry) {
    json.preprocessed_array([json.string(entry.0), entry.1])
  })
  |> json.preprocessed_array
}

@target(erlang)
fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

@target(erlang)
fn optional_int(value: Option(Int)) -> Json {
  case value {
    Some(value) -> json.int(value)
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
fn named_branch_tree(
  main: watershed.SharedTree,
  branch_store: process.Subject(BranchMessage),
  owner: protocol.TreeOwner,
  name: String,
  operation: String,
) -> Result(watershed.SharedTree, protocol.ProtocolError) {
  case name {
    "main" -> Ok(main)
    _ ->
      process.call(branch_store, waiting: 5000, sending: fn(reply) {
        LookupBranch(protocol.local_branch_owner(owner, name), reply)
      })
      |> result.map_error(fn(_) {
        facade(operation, "Unknown branch: " <> name)
      })
  }
}

@target(erlang)
fn run_branch_edit(
  document: watershed.Document(a),
  tree: watershed.SharedTree,
  edit: protocol.BranchEdit,
) -> Result(Json, protocol.ProtocolError) {
  case edit {
    protocol.BranchSet(path, value) ->
      map_result("branchEdit", watershed.tree_set(tree, path, value), fn(_) {
        json.null()
      })
    protocol.BranchClear(path) ->
      map_result("branchEdit", watershed.tree_clear(tree, path), fn(_) {
        json.null()
      })
    protocol.BranchMapSet(path, key, value) ->
      map_result(
        "branchEdit",
        watershed.tree_map_set(tree, path, key, value),
        fn(_) { json.null() },
      )
    protocol.BranchMapDelete(path, key) ->
      map_result(
        "branchEdit",
        watershed.tree_map_delete(tree, path, key),
        fn(_) { json.null() },
      )
    protocol.BranchArrayInsert(path, index, values) ->
      map_result(
        "branchEdit",
        watershed.tree_array_insert(tree, path, index, values),
        fn(_) { json.null() },
      )
    protocol.BranchArrayRemove(path, start, end) ->
      map_result(
        "branchEdit",
        watershed.tree_array_remove(tree, path, start, end),
        fn(_) { json.null() },
      )
    protocol.BranchArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ) ->
      map_result(
        "branchEdit",
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
    protocol.BranchTransaction(scope) ->
      run_transaction(
        document,
        tree,
        protocol.Document("main"),
        dict.new(),
        scope,
      )
  }
}

@target(erlang)
fn await_submitted_revisions(
  revisions: fn() -> List(#(String, String)),
  before: List(#(String, String)),
  retained_revision: Option(String),
  attempts: Int,
) -> Result(List(String), protocol.ProtocolError) {
  case retained_revision {
    None -> Ok([])
    Some(_) ->
      await_submitted_revisions_for_originator(
        revisions,
        before,
        retained_revision,
        attempts,
      )
  }
}

@target(erlang)
fn await_submitted_revisions_for_originator(
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
      await_submitted_revisions_for_originator(
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
  owner: protocol.TreeOwner,
  events: Dict(
    protocol.TreeOwner,
    #(process.Subject(tree_kernel.TreeEvent), Bool),
  ),
  scope: protocol.TransactionScope,
) -> Result(Json, protocol.ProtocolError) {
  // The mailbox holds the events of earlier commands. Take them out, run the
  // transaction, then put them back so that the next checkpoint still sees
  // them. The transaction reports only the events that it emitted.
  let subject = case dict.get(events, owner) {
    Ok(#(subject, True)) -> Some(subject)
    _ -> None
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
  let revision = case observation.outcome {
    "aborted" -> None
    _ ->
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
  document: watershed.Document(a),
  tree: watershed.SharedTree,
  owner: protocol.TreeOwner,
  events: Dict(
    protocol.TreeOwner,
    #(process.Subject(tree_kernel.TreeEvent), Bool),
  ),
  handle_store: process.Subject(HandleMessage),
) -> Result(Json, protocol.ProtocolError) {
  use history <- result.try(
    watershed.tree_history_evidence(tree)
    |> result.map_error(fn(reason) {
      protocol.ProtocolError("facade-error", "checkpoint", reason)
    }),
  )
  let changes = case dict.get(events, owner) {
    Ok(#(subject, True)) -> drain(subject, [])
    _ -> []
  }
  let commits =
    process.call(handle_store, waiting: 1000, sending: fn(reply) {
      DrainTreeCommits(owner, reply)
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
        summary_sequence_number(document),
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
        summary_sequence_number(document),
      ))
    }
  }
}

@target(erlang)
fn summary_sequence_number(document: watershed.Document(a)) -> Option(Int) {
  option.map(observe(document).sequence_number, fn(sequence_number) {
    sequence_number - watershed.operations_since_summary(document)
  })
}

@target(erlang)
type HandleMessage {
  CaptureCommit(
    TreeCommitKind,
    Bool,
    Bool,
    Option(watershed.TreeRevertible),
    Option(String),
    String,
    protocol.TreeOwner,
  )
  SettleCommit(TreeCommitKind, TreeCommitOutcome, String, protocol.TreeOwner)
  RetainHandle(
    String,
    protocol.TreeOwner,
    fn() -> List(#(String, String)),
    fn() -> List(Json),
    process.Subject(Result(Json, protocol.ProtocolError)),
  )
  HandleStatus(String, process.Subject(Result(Json, protocol.ProtocolError)))
  DisposeHandle(String, process.Subject(Result(Json, protocol.ProtocolError)))
  RevertHandle(
    String,
    Bool,
    fn() -> List(#(String, String)),
    fn() -> List(Json),
    process.Subject(Result(Json, protocol.ProtocolError)),
  )
  DrainTreeCommits(protocol.TreeOwner, process.Subject(List(Json)))
}

@target(erlang)
type OutboundMessage {
  RecordOutbound(Json)
  SnapshotOutbound(process.Subject(List(Json)))
}

@target(erlang)
type BranchMessage {
  LookupBranch(
    protocol.TreeOwner,
    process.Subject(Result(watershed.SharedTree, Nil)),
  )
  StoreBranch(protocol.TreeOwner, watershed.SharedTree, process.Subject(Bool))
  RemoveBranch(protocol.TreeOwner)
}

@target(erlang)
type ObjectMessage {
  LookupDataStore(String, process.Subject(Result(watershed.DataStore, Nil)))
  StoreDataStore(String, watershed.DataStore, process.Subject(Bool))
  LookupMap(String, process.Subject(Result(watershed.SharedMap, Nil)))
  StoreMap(String, watershed.SharedMap, process.Subject(Bool))
  LookupTree(String, process.Subject(Result(watershed.SharedTree, Nil)))
  StoreTree(String, watershed.SharedTree, process.Subject(Bool))
  ReplaceTree(String, watershed.SharedTree)
}

@target(erlang)
fn object_store_loop(
  subject: process.Subject(ObjectMessage),
  data_stores: Dict(String, watershed.DataStore),
  maps: Dict(String, watershed.SharedMap),
  trees: Dict(String, watershed.SharedTree),
) -> Nil {
  case process.receive_forever(from: subject) {
    LookupDataStore(name, reply) -> {
      process.send(reply, dict.get(data_stores, name))
      object_store_loop(subject, data_stores, maps, trees)
    }
    StoreDataStore(name, store, reply) -> {
      let fresh = !dict.has_key(data_stores, name)
      process.send(reply, fresh)
      object_store_loop(
        subject,
        case fresh {
          True -> dict.insert(data_stores, name, store)
          False -> data_stores
        },
        maps,
        trees,
      )
    }
    LookupMap(name, reply) -> {
      process.send(reply, dict.get(maps, name))
      object_store_loop(subject, data_stores, maps, trees)
    }
    StoreMap(name, map, reply) -> {
      let fresh = !dict.has_key(maps, name)
      process.send(reply, fresh)
      object_store_loop(
        subject,
        data_stores,
        case fresh {
          True -> dict.insert(maps, name, map)
          False -> maps
        },
        trees,
      )
    }
    LookupTree(name, reply) -> {
      process.send(reply, dict.get(trees, name))
      object_store_loop(subject, data_stores, maps, trees)
    }
    StoreTree(name, tree, reply) -> {
      let fresh = !dict.has_key(trees, name) && name != "main"
      process.send(reply, fresh)
      object_store_loop(subject, data_stores, maps, case fresh {
        True -> dict.insert(trees, name, tree)
        False -> trees
      })
    }
    ReplaceTree(name, tree) ->
      object_store_loop(
        subject,
        data_stores,
        maps,
        dict.insert(trees, name, tree),
      )
  }
}

@target(erlang)
fn branch_store_loop(
  subject: process.Subject(BranchMessage),
  branches: Dict(protocol.TreeOwner, watershed.SharedTree),
) -> Nil {
  case process.receive_forever(from: subject) {
    LookupBranch(name, reply) -> {
      process.send(reply, dict.get(branches, name))
      branch_store_loop(subject, branches)
    }
    StoreBranch(name, tree, reply) -> {
      let fresh = !dict.has_key(branches, name)
      process.send(reply, fresh)
      branch_store_loop(subject, case fresh {
        True -> dict.insert(branches, name, tree)
        False -> branches
      })
    }
    RemoveBranch(name) ->
      branch_store_loop(subject, dict.delete(branches, name))
  }
}

@target(erlang)
fn outbound_store_loop(
  subject: process.Subject(OutboundMessage),
  records: List(Json),
  next_send_id: Int,
) -> Nil {
  case process.receive_forever(from: subject) {
    RecordOutbound(payload) -> {
      let send_id = next_send_id + 1
      outbound_store_loop(
        subject,
        [
          json.object([
            #("sendId", json.int(send_id)),
            #("payload", payload),
          ]),
          ..records
        ],
        send_id,
      )
    }
    SnapshotOutbound(reply) -> {
      process.send(reply, list.reverse(records))
      outbound_store_loop(subject, records, next_send_id)
    }
  }
}

@target(erlang)
fn outbound_snapshot(subject: process.Subject(OutboundMessage)) -> List(Json) {
  process.call(subject, waiting: 1000, sending: SnapshotOutbound)
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
  owner: protocol.TreeOwner,
  handle_store: process.Subject(HandleMessage),
) -> Nil {
  let watershed.TreeCommitEvent(kind, local, factory, settlement) = event
  let action_id = id.uuid_v4()
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
    CaptureCommit(
      kind,
      local,
      option.is_some(factory),
      acquired,
      None,
      action_id,
      owner,
    ),
  )
  case settlement {
    None -> Nil
    Some(on_settled) -> {
      let _ =
        on_settled(fn(outcome) {
          process.send(
            handle_store,
            SettleCommit(kind, outcome, action_id, owner),
          )
        })
      Nil
    }
  }
}

@target(erlang)
fn owner_commits(
  commits: Dict(protocol.TreeOwner, List(Json)),
  owner: protocol.TreeOwner,
) -> List(Json) {
  dict.get(commits, owner) |> result.unwrap([])
}

@target(erlang)
fn push_owner_commit(
  commits: Dict(protocol.TreeOwner, List(Json)),
  owner: protocol.TreeOwner,
  event: Json,
) -> Dict(protocol.TreeOwner, List(Json)) {
  dict.insert(commits, owner, [event, ..owner_commits(commits, owner)])
}

@target(erlang)
fn owner_event_fields(owner: protocol.TreeOwner) -> List(#(String, Json)) {
  case owner {
    protocol.Document("main") -> []
    protocol.Document(tree) -> [#("tree", json.string(tree))]
    protocol.LocalBranch("main", branch) -> [#("branch", json.string(branch))]
    protocol.LocalBranch(tree, branch) -> [
      #("branch", json.string(branch)),
      #("tree", json.string(tree)),
    ]
  }
}

@target(erlang)
fn await_revert_commit(
  subject: process.Subject(HandleMessage),
  owner: protocol.TreeOwner,
  commits: Dict(protocol.TreeOwner, List(Json)),
  next_event_id: Int,
) -> Result(
  #(
    TreeCommitKind,
    Option(watershed.TreeRevertible),
    Json,
    Dict(protocol.TreeOwner, List(Json)),
    Int,
    Option(String),
    String,
  ),
  protocol.ProtocolError,
) {
  case process.receive(subject, 1000) {
    Error(_) -> Error(facade("revert", "Revert authored no local commit event"))
    Ok(SettleCommit(kind, outcome, action_id, event_owner)) ->
      await_revert_commit(
        subject,
        owner,
        push_owner_commit(
          commits,
          event_owner,
          json.object(list.append(
            [
              #("type", json.string("settlement")),
              #("kind", json.string(commit_kind(kind))),
              #("outcome", json.string(commit_outcome(outcome))),
              #("actionId", json.string(action_id)),
            ],
            owner_event_fields(event_owner),
          )),
        ),
        next_event_id,
      )
    Ok(CaptureCommit(
      kind,
      local,
      factory_available,
      acquired,
      revision,
      action_id,
      event_owner,
    )) -> {
      let event_id = next_event_id + 1
      let commit =
        json.object(list.append(
          [
            #("type", json.string("commit")),
            #("kind", json.string(commit_kind(kind))),
            #("local", json.bool(local)),
            #("factoryAvailable", json.bool(factory_available)),
            #("handleAcquired", json.bool(option.is_some(acquired))),
            #("eventId", json.int(event_id)),
            #("actionId", json.string(action_id)),
            #("revision", optional_string(revision)),
          ],
          owner_event_fields(event_owner),
        ))
      case local && event_owner == owner {
        True ->
          Ok(#(kind, acquired, commit, commits, event_id, revision, action_id))
        False ->
          await_revert_commit(
            subject,
            owner,
            push_owner_commit(commits, event_owner, commit),
            event_id,
          )
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
    #(
      watershed.TreeRevertible,
      TreeCommitKind,
      Option(String),
      fn() -> List(#(String, String)),
      protocol.TreeOwner,
      Bool,
    ),
  ),
  last_local: Dict(
    protocol.TreeOwner,
    #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String), String),
  ),
  commits: Dict(protocol.TreeOwner, List(Json)),
  next_event_id: Int,
) -> Nil {
  let message = process.receive_forever(from: subject)
  case message {
    CaptureCommit(
      kind,
      local,
      factory_available,
      acquired,
      revision,
      action_id,
      owner,
    ) -> {
      let event_id = next_event_id + 1
      let commit =
        json.object(list.append(
          [
            #("type", json.string("commit")),
            #("kind", json.string(commit_kind(kind))),
            #("local", json.bool(local)),
            #("factoryAvailable", json.bool(factory_available)),
            #("handleAcquired", json.bool(option.is_some(acquired))),
            #("eventId", json.int(event_id)),
            #("actionId", json.string(action_id)),
            #("revision", optional_string(revision)),
          ],
          owner_event_fields(owner),
        ))
      let next = case acquired {
        Some(handle) ->
          dict.insert(last_local, owner, #(
            handle,
            kind,
            event_id,
            revision,
            action_id,
          ))
        None -> last_local
      }
      handle_store_loop(
        subject,
        handles,
        next,
        push_owner_commit(commits, owner, commit),
        event_id,
      )
    }
    SettleCommit(kind, outcome, action_id, owner) ->
      handle_store_loop(
        subject,
        handles,
        last_local,
        push_owner_commit(
          commits,
          owner,
          json.object(list.append(
            [
              #("type", json.string("settlement")),
              #("kind", json.string(commit_kind(kind))),
              #("outcome", json.string(commit_outcome(outcome))),
              #("actionId", json.string(action_id)),
            ],
            owner_event_fields(owner),
          )),
        ),
        next_event_id,
      )
    RetainHandle(name, owner, revisions, outbound, reply) ->
      case dict.get(last_local, owner) {
        Error(_) -> {
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
        Ok(entry) -> {
          let publishes = protocol.owner_publishes(owner)
          let revision = case publishes, entry.3 {
            False, _ -> None
            True, Some(_) -> entry.3
            True, None ->
              revisions()
              |> list.map(fn(entry) { entry.0 })
              |> list.last
              |> option.from_result
          }
          let outbound_records =
            outbound()
            |> list.last
            |> result.map(fn(record) { [record] })
            |> result.unwrap([])
          process.send(
            reply,
            Ok(
              json.object([
                #("name", json.string(name)),
                #("kind", json.string(commit_kind(entry.1))),
                #("factoryAvailable", json.bool(True)),
                #("status", json.string(revertible_status(entry.0))),
                #("eventId", json.int(entry.2)),
                #("actionId", json.string(entry.4)),
                #("revision", optional_string(revision)),
                #(
                  "outboundRecords",
                  json.array(outbound_records, fn(record) { record }),
                ),
              ]),
            ),
          )
          handle_store_loop(
            subject,
            dict.insert(handles, name, #(
              entry.0,
              entry.1,
              revision,
              revisions,
              owner,
              publishes,
            )),
            dict.delete(last_local, owner),
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
    RevertHandle(name, dispose, _revisions, outbound, reply) ->
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
          let before_revisions = entry.3()
          let before_outbound = outbound()
          let outcome = case watershed.tree_revert(entry.0, dispose) {
            Error(reason) -> Error(facade("revert", reason))
            Ok(_) ->
              case
                await_revert_commit(subject, entry.4, commits, next_event_id)
              {
                Error(error) -> Error(error)
                Ok(#(
                  authored_kind,
                  acquired,
                  commit,
                  observed_commits,
                  event_id,
                  _revision,
                  action_id,
                )) -> {
                  use submitted_revisions <- result.try(
                    await_submitted_revisions(
                      entry.3,
                      before_revisions,
                      case entry.5 {
                        True -> entry.2
                        False -> None
                      },
                      40,
                    ),
                  )
                  let authored_event_ids = [event_id]
                  use _ <- result.try(require_revert_evidence(
                    list.length(authored_event_ids) == 1,
                    "Revert authored another local commit count",
                  ))
                  use _ <- result.try(require_revert_evidence(
                    list.length(submitted_revisions)
                      == case entry.5 {
                      True -> 1
                      False -> 0
                    },
                    "Revert submitted another operation count",
                  ))
                  let submitted_revision =
                    list.first(submitted_revisions) |> option.from_result
                  let outbound_records =
                    outbound()
                    |> list.drop(list.length(before_outbound))
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
                      #("actionId", json.string(action_id)),
                      #(
                        "submittedRevisions",
                        json.array(submitted_revisions, json.string),
                      ),
                      #(
                        "outboundRecords",
                        json.array(outbound_records, fn(record) { record }),
                      ),
                    ]),
                    authored_kind,
                    acquired,
                    commit,
                    observed_commits,
                    event_id,
                    submitted_revision,
                    action_id,
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
              action_id,
            )) -> {
              process.send(reply, Ok(value))
              let next = case acquired {
                Some(handle) ->
                  dict.insert(last_local, entry.4, #(
                    handle,
                    authored_kind,
                    event_id,
                    revision,
                    action_id,
                  ))
                None -> last_local
              }
              handle_store_loop(
                subject,
                handles,
                next,
                push_owner_commit(observed_commits, entry.4, commit),
                event_id,
              )
            }
          }
        }
      }
    DrainTreeCommits(owner, reply) -> {
      let tree = protocol.owner_tree(owner)
      let #(drained, remaining) =
        dict.fold(commits, #([], dict.new()), fn(state, candidate, events) {
          case protocol.owner_tree(candidate) == tree {
            True -> #(list.append(state.0, list.reverse(events)), state.1)
            False -> #(state.0, dict.insert(state.1, candidate, events))
          }
        })
      process.send(reply, drained)
      handle_store_loop(subject, handles, last_local, remaining, next_event_id)
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
