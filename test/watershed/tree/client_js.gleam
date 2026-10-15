@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/dynamic/decode
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
import watershed/canonical_json
@target(javascript)
import watershed/fluid_ids
@target(javascript)
import watershed/handle
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
import watershed/tree/facade_fixture
@target(javascript)
import watershed/tree/types.{
  type TreeCommitKind, type TreeCommitOutcome, DefaultCommit, FullyApplied,
  FullyDropped, HandleValue, NewContentOnly, ObjectValue, RedoCommit, UndoCommit,
}
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
@external(javascript, "./client_io.mjs", "runtimeStateEvidence")
fn runtime_state_evidence(runtime: runtime.Runtime) -> String

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
      let outbound_sends = transport_js.new_cell([])
      let outbound_send_count = transport_js.new_cell(0)
      let connection = case config.pending_checkpoint {
        None ->
          Ok(watershed.connect_observing(
            watershed.WatershedConfig(
              url: config.socket_url,
              tenant: config.tenant,
              document: config.document_id,
              token: token(),
              user_id: "shared-tree-client-js",
            ),
            observe_push: fn(event, payload) {
              case event {
                "submitOp" -> {
                  let send_id = transport_js.get_cell(outbound_send_count) + 1
                  transport_js.set_cell(outbound_send_count, send_id)
                  push_json(
                    outbound_sends,
                    json.object([
                      #("sendId", json.int(send_id)),
                      #("payload", payload),
                    ]),
                  )
                }
                _ -> Nil
              }
            },
            on_ready: signal,
          ))
        Some(checkpoint) ->
          watershed.connect_resuming(
            watershed.WatershedConfig(
              url: config.socket_url,
              tenant: config.tenant,
              document: config.document_id,
              token: token(),
              user_id: "shared-tree-client-js",
            ),
            checkpoint: checkpoint,
            on_ready: signal,
          )
      }
      case connection {
        Error(reason) -> {
          fail(protocol.encode_startup_error(
            "recovery-failed",
            "connect",
            reason,
          ))
          promise.resolve(Nil)
        }
        Ok(document) -> {
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
                      case
                        facade_fixture.resolve_javascript(
                          document,
                          handle,
                          config.view,
                        )
                      {
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
                          let data_stores = transport_js.new_cell(dict.new())
                          let maps = transport_js.new_cell(dict.new())
                          let trees =
                            transport_js.new_cell(
                              dict.from_list([#("main", tree)]),
                            )
                          let branches = transport_js.new_cell(dict.new())
                          let branch_subscriptions =
                            transport_js.new_cell(dict.new())
                          let events = transport_js.new_cell(dict.new())
                          let commits = transport_js.new_cell(dict.new())
                          let handles = transport_js.new_cell(dict.new())
                          let last_local = transport_js.new_cell(dict.new())
                          let commit_event_count = transport_js.new_cell(0)
                          let subscriptions = transport_js.new_cell(dict.new())
                          let _ =
                            watershed.subscribe_tree_commits(tree, fn(event) {
                              observe_commit(
                                event,
                                tree,
                                protocol.Document("main"),
                                commits,
                                last_local,
                                commit_event_count,
                              )
                            })
                          lines(
                            fn(raw) {
                              execute(
                                raw,
                                document,
                                handle,
                                config,
                                active_tree,
                                data_stores,
                                maps,
                                trees,
                                branches,
                                branch_subscriptions,
                                events,
                                commits,
                                handles,
                                last_local,
                                commit_event_count,
                                outbound_sends,
                                outbound_send_count,
                                subscriptions,
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
fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

@target(javascript)
fn optional_int(value: Option(Int)) -> Json {
  case value {
    Some(value) -> json.int(value)
    None -> json.null()
  }
}

@target(javascript)
fn require_revert_evidence(
  condition: Bool,
  message: String,
) -> Result(Nil, protocol.ProtocolError) {
  case condition {
    True -> Ok(Nil)
    False -> Error(facade("revert", message))
  }
}

@target(javascript)
fn named_tree(
  main: facade_fixture.JavascriptTree,
  branches: Cell(Dict(protocol.TreeOwner, facade_fixture.JavascriptTree)),
  owner: protocol.TreeOwner,
  name: String,
  operation: String,
) -> Result(facade_fixture.JavascriptTree, protocol.ProtocolError) {
  case name {
    "main" -> Ok(main)
    _ ->
      dict.get(
        transport_js.get_cell(branches),
        protocol.local_branch_owner(owner, name),
      )
      |> result.map_error(fn(_) {
        facade(operation, "Unknown branch: " <> name)
      })
  }
}

@target(javascript)
fn selected_command(
  command: protocol.Command,
) -> #(Option(String), protocol.Command) {
  case command {
    protocol.SelectedTree(name, command) -> #(Some(name), command)
    _ -> #(None, command)
  }
}

@target(javascript)
fn selected_tree(
  active: facade_fixture.JavascriptTree,
  trees: Cell(Dict(String, facade_fixture.JavascriptTree)),
  selected: Option(String),
  operation: String,
) -> Result(facade_fixture.JavascriptTree, protocol.ProtocolError) {
  case selected {
    None -> Ok(active)
    Some(name) ->
      dict.get(transport_js.get_cell(trees), name)
      |> result.map_error(fn(_) { facade(operation, "Unknown tree: " <> name) })
  }
}

@target(javascript)
fn insert_named(
  objects: Cell(Dict(String, a)),
  name: String,
  value: a,
  operation: String,
) -> Result(Nil, protocol.ProtocolError) {
  case dict.has_key(transport_js.get_cell(objects), name) {
    True -> Error(facade(operation, "Object name already exists: " <> name))
    False -> {
      transport_js.set_cell(
        objects,
        dict.insert(transport_js.get_cell(objects), name, value),
      )
      Ok(Nil)
    }
  }
}

@target(javascript)
fn require_new_name(
  objects: Cell(Dict(String, a)),
  name: String,
  operation: String,
) -> Result(Nil, protocol.ProtocolError) {
  case dict.has_key(transport_js.get_cell(objects), name) {
    True -> Error(facade(operation, "Object name already exists: " <> name))
    False -> Ok(Nil)
  }
}

@target(javascript)
fn named_object(
  objects: Cell(Dict(String, a)),
  name: String,
  kind: String,
  operation: String,
) -> Result(a, protocol.ProtocolError) {
  dict.get(transport_js.get_cell(objects), name)
  |> result.map_error(fn(_) {
    facade(operation, "Unknown " <> kind <> ": " <> name)
  })
}

@target(javascript)
fn encode_shared_map_entries(entries: List(#(String, Json))) -> Json {
  entries
  |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
  |> list.map(fn(entry) {
    json.preprocessed_array([json.string(entry.0), entry.1])
  })
  |> json.preprocessed_array
}

@target(javascript)
fn remove_branch(
  owner: protocol.TreeOwner,
  branches: Cell(Dict(protocol.TreeOwner, facade_fixture.JavascriptTree)),
  subscriptions: Cell(Dict(protocol.TreeOwner, watershed.SubscriptionToken)),
) -> Nil {
  case dict.get(transport_js.get_cell(subscriptions), owner) {
    Ok(subscription) -> watershed.unsubscribe(subscription)
    Error(_) -> Nil
  }
  transport_js.set_cell(
    branches,
    dict.delete(transport_js.get_cell(branches), owner),
  )
  transport_js.set_cell(
    subscriptions,
    dict.delete(transport_js.get_cell(subscriptions), owner),
  )
}

@target(javascript)
fn run_branch_edit(
  document: watershed.Document(a),
  tree: facade_fixture.JavascriptTree,
  owner: protocol.TreeOwner,
  events: Cell(Dict(protocol.TreeOwner, List(Json))),
  edit: protocol.BranchEdit,
) -> Result(Json, protocol.ProtocolError) {
  case edit {
    protocol.BranchSet(path, value) ->
      map_result(
        "branchEdit",
        facade_fixture.set_javascript(tree, path, value),
        fn(_) { json.null() },
      )
    protocol.BranchClear(path) ->
      map_result(
        "branchEdit",
        facade_fixture.clear_javascript(tree, path),
        fn(_) { json.null() },
      )
    protocol.BranchMapSet(path, key, value) ->
      map_result(
        "branchEdit",
        facade_fixture.map_set_javascript(tree, path, key, value),
        fn(_) { json.null() },
      )
    protocol.BranchMapDelete(path, key) ->
      map_result(
        "branchEdit",
        facade_fixture.map_delete_javascript(tree, path, key),
        fn(_) { json.null() },
      )
    protocol.BranchArrayInsert(path, index, values) ->
      map_result(
        "branchEdit",
        facade_fixture.array_insert_javascript(tree, path, index, values),
        fn(_) { json.null() },
      )
    protocol.BranchArrayRemove(path, start, end) ->
      map_result(
        "branchEdit",
        facade_fixture.array_remove_javascript(tree, path, start, end),
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
        facade_fixture.array_move_javascript(
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
      run_transaction(document, tree, owner, events, scope)
  }
}

@target(javascript)
fn execute(
  raw: String,
  document: watershed.Document(a),
  _handle: Json,
  config: protocol.Descriptor,
  active_tree: Cell(facade_fixture.JavascriptTree),
  data_stores: Cell(Dict(String, watershed.DataStore)),
  maps: Cell(Dict(String, watershed.SharedMap)),
  trees: Cell(Dict(String, facade_fixture.JavascriptTree)),
  branches: Cell(Dict(protocol.TreeOwner, facade_fixture.JavascriptTree)),
  branch_subscriptions: Cell(
    Dict(protocol.TreeOwner, watershed.SubscriptionToken),
  ),
  events: Cell(Dict(protocol.TreeOwner, List(Json))),
  commits: Cell(Dict(protocol.TreeOwner, List(Json))),
  handles: Cell(
    Dict(
      String,
      #(
        watershed.TreeRevertible,
        TreeCommitKind,
        Option(String),
        facade_fixture.JavascriptTree,
        protocol.TreeOwner,
        Bool,
      ),
    ),
  ),
  last_local: Cell(
    Dict(
      protocol.TreeOwner,
      #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String)),
    ),
  ),
  commit_event_count: Cell(Int),
  outbound_sends: Cell(List(Json)),
  outbound_send_count: Cell(Int),
  subscriptions: Cell(Dict(protocol.TreeOwner, watershed.SubscriptionToken)),
) -> Promise(String) {
  case protocol.decode_request(raw) {
    Error(error) ->
      promise.resolve(response(protocol.request_id(raw), Error(error), document))
    Ok(protocol.Request(id, command)) -> {
      let #(selected, command) = selected_command(command)
      let owner = protocol.selected_owner(selected)
      let operation = case selected {
        Some(_) -> "tree"
        None -> "command"
      }
      let result = {
        use tree <- result.try(selected_tree(
          transport_js.get_cell(active_tree),
          trees,
          selected,
          operation,
        ))
        case command {
          protocol.CreateDataStore(name) -> {
            use _ <- result.try(require_new_name(
              data_stores,
              name,
              "create-data-store",
            ))
            use store <- result.try(
              watershed.create_data_store(document)
              |> result.map_error(fn(reason) {
                facade("create-data-store", reason)
              }),
            )
            use _ <- result.try(insert_named(
              data_stores,
              name,
              store,
              "create-data-store",
            ))
            use root <- result.try(
              watershed.data_store_root(store)
              |> result.map_error(fn(reason) {
                facade("create-data-store", reason)
              }),
            )
            Ok(watershed.handle_of(root))
          }
          protocol.RootMap(name) -> {
            use map <- result.try(
              watershed.resolve_root(document)
              |> result.map_error(fn(reason) { facade("root-map", reason) }),
            )
            use _ <- result.try(insert_named(maps, name, map, "root-map"))
            Ok(watershed.handle_of(map))
          }
          protocol.DataStoreRoot(store_name, name) -> {
            use store <- result.try(named_object(
              data_stores,
              store_name,
              "data store",
              "data-store-root",
            ))
            use map <- result.try(
              watershed.data_store_root(store)
              |> result.map_error(fn(reason) {
                facade("data-store-root", reason)
              }),
            )
            use _ <- result.try(insert_named(maps, name, map, "data-store-root"))
            Ok(watershed.handle_of(map))
          }
          protocol.CreateMap(name, store_name) -> {
            use _ <- result.try(require_new_name(maps, name, "create-map"))
            use map <- result.try(case store_name {
              None ->
                watershed.create_map(document)
                |> result.map_error(fn(reason) { facade("create-map", reason) })
              Some(store_name) -> {
                use store <- result.try(named_object(
                  data_stores,
                  store_name,
                  "data store",
                  "create-map",
                ))
                watershed.create_map_in(document, store)
                |> result.map_error(fn(reason) { facade("create-map", reason) })
              }
            })
            use _ <- result.try(insert_named(maps, name, map, "create-map"))
            Ok(watershed.handle_of(map))
          }
          protocol.OpenMap(name, marker) -> {
            use map <- result.try(
              watershed.resolve(document, marker)
              |> result.map_error(fn(reason) { facade("open-map", reason) }),
            )
            use _ <- result.try(insert_named(maps, name, map, "open-map"))
            Ok(watershed.handle_of(map))
          }
          protocol.SharedMapGet(name, key) -> {
            use map <- result.try(named_object(
              maps,
              name,
              "shared map",
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
          protocol.SharedMapSet(name, key, value) -> {
            use map <- result.try(named_object(
              maps,
              name,
              "shared map",
              "shared-map-set",
            ))
            map_result(
              "shared-map-set",
              watershed.set_checked(map, key, value),
              fn(_) { json.null() },
            )
          }
          protocol.SharedMapDelete(name, key) -> {
            use map <- result.try(named_object(
              maps,
              name,
              "shared map",
              "shared-map-delete",
            ))
            map_result(
              "shared-map-delete",
              watershed.delete_checked(map, key),
              fn(_) { json.null() },
            )
          }
          protocol.SharedMapEntries(name) -> {
            use map <- result.try(named_object(
              maps,
              name,
              "shared map",
              "shared-map-entries",
            ))
            Ok(encode_shared_map_entries(watershed.entries(map)))
          }
          protocol.CreateTree(name, store_name, stored, initial, view) -> {
            use _ <- result.try(require_new_name(trees, name, "create-tree"))
            use created <- result.try(case store_name {
              None ->
                facade_fixture.create_from_parts_javascript(
                  document,
                  stored,
                  Some(initial),
                  view,
                )
                |> result.map_error(fn(reason) { facade("create-tree", reason) })
              Some(store_name) -> {
                use store <- result.try(named_object(
                  data_stores,
                  store_name,
                  "data store",
                  "create-tree",
                ))
                facade_fixture.create_in_from_parts_javascript(
                  document,
                  store,
                  stored,
                  Some(initial),
                  view,
                )
                |> result.map_error(fn(reason) { facade("create-tree", reason) })
              }
            })
            use _ <- result.try(insert_named(
              trees,
              name,
              created,
              "create-tree",
            ))
            let _ =
              watershed.subscribe_tree_commits(created, fn(event) {
                observe_commit(
                  event,
                  created,
                  protocol.Document(name),
                  commits,
                  last_local,
                  commit_event_count,
                )
              })
            Ok(watershed.tree_handle_of(created))
          }
          protocol.OpenTree(name, marker, view) -> {
            use opened <- result.try(
              facade_fixture.resolve_javascript(document, marker, view)
              |> result.map_error(fn(reason) { facade("open-tree", reason) }),
            )
            use _ <- result.try(insert_named(trees, name, opened, "open-tree"))
            let _ =
              watershed.subscribe_tree_commits(opened, fn(event) {
                observe_commit(
                  event,
                  opened,
                  protocol.Document(name),
                  commits,
                  last_local,
                  commit_event_count,
                )
              })
            Ok(watershed.tree_handle_of(opened))
          }
          protocol.SelectedTree(_, _) ->
            Error(facade("tree", "Nested tree selection is invalid"))
          protocol.Read(path) ->
            map_result(
              "read",
              facade_fixture.get_javascript(tree, path),
              protocol.encode_read,
            )
          protocol.Set(path, value) ->
            map_result(
              "set",
              facade_fixture.set_javascript(tree, path, value),
              fn(_) { json.null() },
            )
          protocol.Clear(path) ->
            map_result(
              "clear",
              facade_fixture.clear_javascript(tree, path),
              fn(_) { json.null() },
            )
          protocol.MapGet(path, key) ->
            map_result(
              "map-get",
              facade_fixture.map_get_javascript(tree, path, key),
              protocol.encode_read,
            )
          protocol.MapSet(path, key, value) ->
            map_result(
              "map-set",
              facade_fixture.map_set_javascript(tree, path, key, value),
              fn(_) { json.null() },
            )
          protocol.MapDelete(path, key) ->
            map_result(
              "map-delete",
              facade_fixture.map_delete_javascript(tree, path, key),
              fn(_) { json.null() },
            )
          protocol.MapKeys(path) ->
            map_result(
              "map-keys",
              facade_fixture.map_keys_javascript(tree, path),
              protocol.encode_map_keys,
            )
          protocol.MapEntries(path) ->
            map_result(
              "map-entries",
              facade_fixture.map_entries_javascript(tree, path),
              protocol.encode_map_entries,
            )
          protocol.SchemaCompatibility(label) ->
            case protocol.descriptor_view(config, label) {
              Error(error) -> Error(error)
              Ok(view) -> {
                use opened <- result.try(
                  facade_fixture.open_javascript(
                    document,
                    watershed.tree_handle_of(tree),
                    view,
                  )
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
                  facade_fixture.open_javascript(
                    document,
                    watershed.tree_handle_of(tree),
                    view,
                  )
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
                  facade_fixture.open_javascript(
                    document,
                    watershed.tree_handle_of(tree),
                    view,
                  )
                  |> result.map_error(fn(reason) { facade("open-view", reason) }),
                )
                case selected {
                  None -> {
                    transport_js.set_cell(active_tree, opened)
                    transport_js.set_cell(
                      trees,
                      dict.insert(transport_js.get_cell(trees), "main", opened),
                    )
                  }
                  Some("main") -> {
                    transport_js.set_cell(active_tree, opened)
                    transport_js.set_cell(
                      trees,
                      dict.insert(transport_js.get_cell(trees), "main", opened),
                    )
                  }
                  Some(name) ->
                    transport_js.set_cell(
                      trees,
                      dict.insert(transport_js.get_cell(trees), name, opened),
                    )
                }
                Ok(json.null())
              }
            }
          protocol.ArrayGet(path, index) ->
            map_result(
              "array-get",
              facade_fixture.array_get_javascript(tree, path, index),
              protocol.encode_read,
            )
          protocol.ArrayValues(path) ->
            map_result(
              "array-values",
              facade_fixture.array_values_javascript(tree, path),
              protocol.encode_array_values,
            )
          protocol.ArrayInsert(path, index, values) ->
            map_result(
              "array-insert",
              facade_fixture.array_insert_javascript(tree, path, index, values),
              fn(_) { json.null() },
            )
          protocol.ArrayRemove(path, start, end) ->
            map_result(
              "array-remove",
              facade_fixture.array_remove_javascript(tree, path, start, end),
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
              facade_fixture.array_move_javascript(
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
                  facade_fixture.array_remove_javascript(
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
                Error(facade("constrained-array-remove", reason))
              Error(watershed.Aborted(reason)) ->
                Error(facade("constrained-array-remove", reason))
            }
          protocol.Transaction(scope) ->
            run_transaction(document, tree, owner, events, scope)
          protocol.ActiveTargetPreflight(target_name) -> {
            use target <- result.try(selected_tree(
              transport_js.get_cell(active_tree),
              trees,
              Some(target_name),
              "active-target-preflight",
            ))
            use target_reference <- result.try(
              handle.reference_from_json(watershed.tree_handle_of(target), "")
              |> result.map_error(fn(_) {
                facade("active-target-preflight", "invalid target handle")
              }),
            )
            case
              watershed.tree_transaction(target, [], fn(_) {
                let before =
                  runtime_state_evidence(watershed.runtime_of(document))
                case
                  facade_fixture.set_javascript(
                    tree,
                    ["link"],
                    HandleValue(target_reference),
                  )
                {
                  Error(reason) ->
                    Error(
                      Ok(
                        json.object([
                          #("refused", json.bool(True)),
                          #("error", json.string(reason)),
                          #("before", json.string(before)),
                          #(
                            "after",
                            json.string(
                              runtime_state_evidence(watershed.runtime_of(
                                document,
                              )),
                            ),
                          ),
                        ]),
                      ),
                    )
                  Ok(_) ->
                    Error(
                      Error(
                        EditFailed(facade(
                          "active-target-preflight",
                          "active target attachment unexpectedly succeeded",
                        )),
                      ),
                    )
                }
              })
            {
              Error(watershed.Aborted(Ok(evidence))) -> Ok(evidence)
              Error(watershed.Aborted(Error(EditFailed(error)))) -> Error(error)
              Error(watershed.Aborted(Error(RequestedAbort(_)))) ->
                Error(facade(
                  "active-target-preflight",
                  "active target attachment returned another abort",
                ))
              Ok(_) ->
                Error(facade(
                  "active-target-preflight",
                  "active target attachment committed without its refusal",
                ))
              Error(watershed.TransactionFailed(reason)) ->
                Error(facade("active-target-preflight", reason))
            }
          }
          protocol.Fork(source, name) -> {
            let branch_owner = protocol.local_branch_owner(owner, name)
            use _ <- result.try(
              case
                name == "main"
                || dict.has_key(transport_js.get_cell(branches), branch_owner)
              {
                True ->
                  Error(facade("fork", "Branch name already exists: " <> name))
                False -> Ok(Nil)
              },
            )
            use source_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              source,
              "fork",
            ))
            use branch <- result.try(
              watershed.tree_fork(source_tree)
              |> result.map_error(fn(reason) { facade("fork", reason) }),
            )
            let subscriber =
              watershed.subscribe_tree_commits(branch, fn(event) {
                observe_commit(
                  event,
                  branch,
                  branch_owner,
                  commits,
                  last_local,
                  commit_event_count,
                )
              })
            transport_js.set_cell(
              branches,
              dict.insert(transport_js.get_cell(branches), branch_owner, branch),
            )
            transport_js.set_cell(
              branch_subscriptions,
              dict.insert(
                transport_js.get_cell(branch_subscriptions),
                branch_owner,
                subscriber,
              ),
            )
            Ok(
              json.object([
                #("name", json.string(name)),
                #("source", json.string(source)),
                #("status", json.string("BranchValid")),
              ]),
            )
          }
          protocol.BranchEditCommand(branch, edit) -> {
            use branch_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              branch,
              "branchEdit",
            ))
            let branch_owner = protocol.checkout_owner(owner, branch)
            let before_commits = list.length(owned_json(commits, branch_owner))
            let before_sends = transport_js.get_cell(outbound_send_count)
            use observation <- result.try(run_branch_edit(
              document,
              branch_tree,
              branch_owner,
              events,
              edit,
            ))
            Ok(
              json.object([
                #("branch", json.string(branch)),
                #(
                  "authoredCount",
                  json.int(
                    list.length(owned_json(commits, branch_owner))
                    - before_commits,
                  ),
                ),
                #(
                  "outboundCount",
                  json.int(
                    transport_js.get_cell(outbound_send_count) - before_sends,
                  ),
                ),
                #("observation", observation),
              ]),
            )
          }
          protocol.RebaseBranch(source, target) -> {
            use source_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              source,
              "rebaseBranch",
            ))
            use target_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              target,
              "rebaseBranch",
            ))
            use _ <- result.try(
              watershed.tree_rebase_onto(source_tree, target_tree)
              |> result.map_error(fn(reason) { facade("rebaseBranch", reason) }),
            )
            Ok(
              json.object([
                #("source", json.string(source)),
                #("target", json.string(target)),
              ]),
            )
          }
          protocol.MergeBranch(target, source, dispose) -> {
            use target_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              target,
              "mergeBranch",
            ))
            use source_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              source,
              "mergeBranch",
            ))
            use _ <- result.try(
              watershed.tree_merge(target_tree, source_tree, dispose)
              |> result.map_error(fn(reason) { facade("mergeBranch", reason) }),
            )
            case dispose && source != "main" {
              True ->
                remove_branch(
                  protocol.local_branch_owner(owner, source),
                  branches,
                  branch_subscriptions,
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
          protocol.DisposeBranch(name) -> {
            use branch <- result.try(named_tree(
              tree,
              branches,
              owner,
              name,
              "disposeBranch",
            ))
            use _ <- result.try(
              watershed.tree_dispose_branch(branch)
              |> result.map_error(fn(reason) { facade("disposeBranch", reason) }),
            )
            remove_branch(
              protocol.local_branch_owner(owner, name),
              branches,
              branch_subscriptions,
            )
            Ok(
              json.object([
                #("name", json.string(name)),
                #("status", json.string("BranchDisposed")),
              ]),
            )
          }
          protocol.RetainLastLocalCommit(name) ->
            retain_last_local_commit(
              tree,
              owner,
              name,
              handles,
              last_local,
              outbound_sends,
            )
          protocol.BranchRetainLastLocalCommit(branch, name) -> {
            use branch_tree <- result.try(named_tree(
              tree,
              branches,
              owner,
              branch,
              "retainLastLocalCommit",
            ))
            retain_last_local_commit(
              branch_tree,
              protocol.checkout_owner(owner, branch),
              name,
              handles,
              last_local,
              outbound_sends,
            )
          }
          protocol.RevertibleStatus(name) ->
            revertible_status_for_name(name, handles)
          protocol.DisposeRevertible(name) -> dispose_revertible(name, handles)
          protocol.Revert(name, dispose) ->
            revert_handle(
              name,
              dispose,
              handles,
              last_local,
              commit_event_count,
              outbound_sends,
              outbound_send_count,
            )
          protocol.Checkpoint ->
            checkpoint(document, tree, owner, events, commits)
          protocol.PendingCheckpoint ->
            watershed.pending_checkpoint(document)
            |> result.map_error(fn(reason) {
              facade("pending-checkpoint", reason)
            })
          protocol.RuntimeStateEvidence ->
            Ok(
              json.string(
                runtime_state_evidence(watershed.runtime_of(document)),
              ),
            )
          protocol.Disconnect -> {
            watershed.go_offline(document)
            Ok(json.null())
          }
          protocol.Reconnect -> {
            watershed.go_online(document)
            Ok(json.null())
          }
          protocol.Subscribe -> {
            case dict.has_key(transport_js.get_cell(subscriptions), owner) {
              True -> Ok(json.null())
              False -> {
                let subscriber =
                  watershed.subscribe_tree(tree, fn(event) {
                    case event {
                      SchemaChanged(local) -> {
                        push_owned_json(
                          events,
                          owner,
                          json.object([
                            #("kind", json.string("schema")),
                            #("local", json.bool(local)),
                          ]),
                        )
                      }
                      TreeChanged(local) -> {
                        push_owned_json(
                          events,
                          owner,
                          json.object([
                            #("kind", json.string("data")),
                            #("local", json.bool(local)),
                          ]),
                        )
                      }
                    }
                  })
                transport_js.set_cell(
                  subscriptions,
                  dict.insert(
                    transport_js.get_cell(subscriptions),
                    owner,
                    subscriber,
                  ),
                )
                Ok(json.null())
              }
            }
          }
          protocol.Unsubscribe -> {
            case dict.get(transport_js.get_cell(subscriptions), owner) {
              Error(_) -> Nil
              Ok(subscriber) -> watershed.unsubscribe(subscriber)
            }
            transport_js.set_cell(
              subscriptions,
              dict.delete(transport_js.get_cell(subscriptions), owner),
            )
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
          protocol.AwaitSynced(_)
          | protocol.Summarize
          | protocol.TrySetAlias(_, _) -> Ok(json.null())
        }
      }
      case command {
        protocol.TrySetAlias(store_name, alias) ->
          case
            named_object(data_stores, store_name, "data store", "try-set-alias")
          {
            Error(error) ->
              promise.resolve(response(Some(id), Error(error), document))
            Ok(store) -> {
              use outcome <- promise.await(watershed.try_set_alias(store, alias))
              promise.resolve(response(
                Some(id),
                map_result(
                  "try-set-alias",
                  outcome,
                  protocol.encode_alias_result,
                ),
                document,
              ))
            }
          }
        protocol.AwaitSynced(watermark) -> {
          use synced <- promise.await(await_synced(document, watermark, 1200))
          promise.resolve(response(Some(id), synced, document))
        }
        protocol.Summarize -> {
          let snapshot_sequence_number = observe(document).sequence_number
          use outcome <- promise.await(watershed.summarize(document))
          promise.resolve(response(
            Some(id),
            map_result("summarize", outcome, fn(version) {
              json.object([
                #("version", json.string(version)),
                #(
                  "snapshotSequenceNumber",
                  optional_int(snapshot_sequence_number),
                ),
              ])
            }),
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
  tree: facade_fixture.JavascriptTree,
  edit: protocol.TransactionEdit,
) -> Result(Nil, protocol.ProtocolError) {
  let outcome = case edit {
    protocol.TransactionSet(path, value) ->
      facade_fixture.set_javascript(tree, path, value)
    protocol.TransactionClear(path) ->
      facade_fixture.clear_javascript(tree, path)
    protocol.TransactionMapSet(path, key, value) ->
      facade_fixture.map_set_javascript(tree, path, key, value)
    protocol.TransactionMapDelete(path, key) ->
      facade_fixture.map_delete_javascript(tree, path, key)
    protocol.TransactionArrayInsert(path, index, values) ->
      facade_fixture.array_insert_javascript(tree, path, index, values)
    protocol.TransactionArrayRemove(path, start, end) ->
      facade_fixture.array_remove_javascript(tree, path, start, end)
    protocol.TransactionArrayMove(
      source_path,
      source_start,
      source_end,
      destination_path,
      destination_gap,
    ) ->
      facade_fixture.array_move_javascript(
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
  tree: facade_fixture.JavascriptTree,
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
  let observed = case facade_fixture.get_javascript(tree, []) {
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

@target(javascript)
fn run_transaction_scope(
  tree: facade_fixture.JavascriptTree,
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
  tree: facade_fixture.JavascriptTree,
  owner: protocol.TreeOwner,
  events: Cell(Dict(protocol.TreeOwner, List(Json))),
  scope: protocol.TransactionScope,
) -> Result(Json, protocol.ProtocolError) {
  let before_events = owned_json(events, owner)
  let before_pending = observe(document).pending_tree_count
  let outcome = run_transaction_scope(tree, scope)
  let after_events = owned_json(events, owner)
  let emitted =
    after_events
    |> list.take(list.length(after_events) - list.length(before_events))
    |> list.reverse
  set_owned_json(events, owner, before_events)
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
  let final = case facade_fixture.get_javascript(tree, []) {
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
  document: watershed.Document(a),
  tree: facade_fixture.JavascriptTree,
  owner: protocol.TreeOwner,
  events: Cell(Dict(protocol.TreeOwner, List(Json))),
  commits: Cell(Dict(protocol.TreeOwner, List(Json))),
) -> Result(Json, protocol.ProtocolError) {
  use history <- result.try(
    watershed.tree_history_evidence(tree)
    |> result.map_error(fn(reason) { facade("checkpoint", reason) }),
  )
  let changes = list.reverse(owned_json(events, owner))
  set_owned_json(events, owner, [])
  let commit_events = drain_tree_commits(commits, owner)
  case facade_fixture.get_javascript(tree, []) {
    Error(reason) ->
      Ok(protocol.encode_checkpoint(
        protocol.encode_read(None),
        [],
        changes,
        commit_events,
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
            facade_fixture.map_keys_javascript(tree, ["items"]),
            protocol.encode_map_keys,
          ))
          use entries <- result.try(map_result(
            "checkpoint",
            facade_fixture.map_entries_javascript(tree, ["items"]),
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
              case facade_fixture.get_javascript(tree, entry.1) {
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
        commit_events,
        history,
        None,
        retained,
        summary_sequence_number(document),
      ))
    }
  }
}

@target(javascript)
fn drain_tree_commits(
  commits: Cell(Dict(protocol.TreeOwner, List(Json))),
  owner: protocol.TreeOwner,
) -> List(Json) {
  let tree = protocol.owner_tree(owner)
  let #(drained, remaining) =
    dict.fold(
      transport_js.get_cell(commits),
      #([], dict.new()),
      fn(state, candidate, events) {
        case protocol.owner_tree(candidate) == tree {
          True -> #(list.append(state.0, list.reverse(events)), state.1)
          False -> #(state.0, dict.insert(state.1, candidate, events))
        }
      },
    )
  transport_js.set_cell(commits, remaining)
  drained
}

@target(javascript)
fn summary_sequence_number(document: watershed.Document(a)) -> Option(Int) {
  option.map(observe(document).sequence_number, fn(sequence_number) {
    sequence_number - watershed.operations_since_summary(document)
  })
}

@target(javascript)
fn commit_kind(kind: TreeCommitKind) -> String {
  case kind {
    DefaultCommit -> "Default"
    UndoCommit -> "Undo"
    RedoCommit -> "Redo"
  }
}

@target(javascript)
fn commit_outcome(outcome: TreeCommitOutcome) -> String {
  case outcome {
    FullyApplied -> "FullyApplied"
    FullyDropped -> "FullyDropped"
    NewContentOnly -> "NewContentOnly"
  }
}

@target(javascript)
fn revertible_status(handle: watershed.TreeRevertible) -> String {
  case watershed.tree_revertible_status(handle) {
    watershed.RevertibleValid -> "Valid"
    watershed.RevertibleDisposed -> "Disposed"
  }
}

@target(javascript)
fn push_json(cell: Cell(List(Json)), value: Json) -> Nil {
  transport_js.set_cell(cell, [value, ..transport_js.get_cell(cell)])
}

@target(javascript)
fn owned_json(
  cell: Cell(Dict(protocol.TreeOwner, List(Json))),
  owner: protocol.TreeOwner,
) -> List(Json) {
  dict.get(transport_js.get_cell(cell), owner) |> result.unwrap([])
}

@target(javascript)
fn set_owned_json(
  cell: Cell(Dict(protocol.TreeOwner, List(Json))),
  owner: protocol.TreeOwner,
  values: List(Json),
) -> Nil {
  transport_js.set_cell(
    cell,
    dict.insert(transport_js.get_cell(cell), owner, values),
  )
}

@target(javascript)
fn push_owned_json(
  cell: Cell(Dict(protocol.TreeOwner, List(Json))),
  owner: protocol.TreeOwner,
  value: Json,
) -> Nil {
  set_owned_json(cell, owner, [value, ..owned_json(cell, owner)])
}

@target(javascript)
fn owner_tree_field(owner: protocol.TreeOwner) -> List(#(String, Json)) {
  case owner {
    protocol.Document("main") | protocol.LocalBranch("main", _) -> []
    protocol.Document(tree) | protocol.LocalBranch(tree, _) -> [
      #("tree", json.string(tree)),
    ]
  }
}

@target(javascript)
fn observe_commit(
  event: watershed.TreeCommitEvent,
  tree: facade_fixture.JavascriptTree,
  owner: protocol.TreeOwner,
  commits: Cell(Dict(protocol.TreeOwner, List(Json))),
  last_local: Cell(
    Dict(
      protocol.TreeOwner,
      #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String)),
    ),
  ),
  commit_event_count: Cell(Int),
) -> Nil {
  let watershed.TreeCommitEvent(kind, local, factory, settlement) = event
  let event_id = transport_js.get_cell(commit_event_count) + 1
  let action_id = "event-" <> int.to_string(event_id)
  transport_js.set_cell(commit_event_count, event_id)
  let history_revision =
    watershed.tree_history_evidence(tree)
    |> result.map(protocol.history_revisions)
    |> result.unwrap([])
    |> list.last
    |> option.from_result
  let factory_available = option.is_some(factory)
  let #(acquired, revision) = case local, factory {
    True, Some(get_revertible) ->
      case get_revertible() {
        Ok(handle) -> {
          let revision =
            Some(
              watershed.tree_revertible_revision(handle)
              |> fluid_ids.stable_id_to_string,
            )
          transport_js.set_cell(
            last_local,
            transport_js.get_cell(last_local)
              |> dict.insert(owner, #(handle, kind, event_id, revision)),
          )
          #(True, revision)
        }
        Error(_) -> #(False, history_revision)
      }
    _, _ -> #(False, history_revision)
  }
  push_owned_json(
    commits,
    owner,
    json.object(list.append(
      [
        #("type", json.string("commit")),
        #("kind", json.string(commit_kind(kind))),
        #("local", json.bool(local)),
        #("factoryAvailable", json.bool(factory_available)),
        #("handleAcquired", json.bool(acquired)),
        #("eventId", json.int(event_id)),
        #("actionId", json.string(action_id)),
        #("branch", json.string(protocol.owner_label(owner))),
        #("revision", optional_string(revision)),
      ],
      owner_tree_field(owner),
    )),
  )
  case settlement {
    None -> Nil
    Some(on_settled) -> {
      let _ =
        on_settled(fn(outcome) {
          push_owned_json(
            commits,
            owner,
            json.object(list.append(
              [
                #("type", json.string("settlement")),
                #("kind", json.string(commit_kind(kind))),
                #("outcome", json.string(commit_outcome(outcome))),
                #("eventId", json.int(event_id)),
                #("actionId", json.string(action_id)),
                #("revision", optional_string(revision)),
              ],
              settlement_owner_fields(owner),
            )),
          )
        })
      Nil
    }
  }
}

@target(javascript)
fn settlement_owner_fields(owner: protocol.TreeOwner) -> List(#(String, Json)) {
  case owner {
    protocol.Document(_) -> owner_tree_field(owner)
    protocol.LocalBranch("main", branch) -> [
      #("branch", json.string(branch)),
    ]
    protocol.LocalBranch(tree, branch) -> [
      #("branch", json.string(branch)),
      #("tree", json.string(tree)),
    ]
  }
}

@target(javascript)
fn retain_last_local_commit(
  tree: facade_fixture.JavascriptTree,
  owner: protocol.TreeOwner,
  name: String,
  handles: Cell(
    Dict(
      String,
      #(
        watershed.TreeRevertible,
        TreeCommitKind,
        Option(String),
        facade_fixture.JavascriptTree,
        protocol.TreeOwner,
        Bool,
      ),
    ),
  ),
  last_local: Cell(
    Dict(
      protocol.TreeOwner,
      #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String)),
    ),
  ),
  outbound_sends: Cell(List(Json)),
) -> Result(Json, protocol.ProtocolError) {
  case dict.get(transport_js.get_cell(last_local), owner) {
    Error(_) ->
      Error(facade(
        "retainLastLocalCommit",
        "No unretained local commit is available",
      ))
    Ok(entry) -> {
      let publishes = protocol.owner_publishes(owner)
      transport_js.set_cell(
        handles,
        transport_js.get_cell(handles)
          |> dict.insert(name, #(
            entry.0,
            entry.1,
            entry.3,
            tree,
            owner,
            publishes,
          )),
      )
      transport_js.set_cell(
        last_local,
        dict.delete(transport_js.get_cell(last_local), owner),
      )
      let outbound_records =
        transport_js.get_cell(outbound_sends)
        |> list.first
        |> result.map(fn(record) { [record] })
        |> result.unwrap([])
      Ok(
        json.object([
          #("name", json.string(name)),
          #("kind", json.string(commit_kind(entry.1))),
          #("factoryAvailable", json.bool(True)),
          #("status", json.string(revertible_status(entry.0))),
          #("eventId", json.int(entry.2)),
          #("actionId", json.string("event-" <> int.to_string(entry.2))),
          #("revision", optional_string(entry.3)),
          #(
            "outboundRecords",
            json.array(outbound_records, fn(record) { record }),
          ),
        ]),
      )
    }
  }
}

@target(javascript)
fn revertible_status_for_name(
  name: String,
  handles: Cell(
    Dict(
      String,
      #(
        watershed.TreeRevertible,
        TreeCommitKind,
        Option(String),
        facade_fixture.JavascriptTree,
        protocol.TreeOwner,
        Bool,
      ),
    ),
  ),
) -> Result(Json, protocol.ProtocolError) {
  use entry <- result.try(
    transport_js.get_cell(handles)
    |> dict.get(name)
    |> result.map_error(fn(_) {
      facade("revertibleStatus", "Unknown revertible handle: " <> name)
    }),
  )
  Ok(
    json.object([
      #("name", json.string(name)),
      #("status", json.string(revertible_status(entry.0))),
    ]),
  )
}

@target(javascript)
fn dispose_revertible(
  name: String,
  handles: Cell(
    Dict(
      String,
      #(
        watershed.TreeRevertible,
        TreeCommitKind,
        Option(String),
        facade_fixture.JavascriptTree,
        protocol.TreeOwner,
        Bool,
      ),
    ),
  ),
) -> Result(Json, protocol.ProtocolError) {
  use entry <- result.try(
    transport_js.get_cell(handles)
    |> dict.get(name)
    |> result.map_error(fn(_) {
      facade("disposeRevertible", "Unknown revertible handle: " <> name)
    }),
  )
  use _ <- result.try(
    watershed.tree_dispose_revertible(entry.0)
    |> result.map_error(fn(reason) { facade("disposeRevertible", reason) }),
  )
  Ok(
    json.object([
      #("name", json.string(name)),
      #("status", json.string(revertible_status(entry.0))),
    ]),
  )
}

@target(javascript)
fn revert_handle(
  name: String,
  dispose: Bool,
  handles: Cell(
    Dict(
      String,
      #(
        watershed.TreeRevertible,
        TreeCommitKind,
        Option(String),
        facade_fixture.JavascriptTree,
        protocol.TreeOwner,
        Bool,
      ),
    ),
  ),
  last_local: Cell(
    Dict(
      protocol.TreeOwner,
      #(watershed.TreeRevertible, TreeCommitKind, Int, Option(String)),
    ),
  ),
  commit_event_count: Cell(Int),
  outbound_sends: Cell(List(Json)),
  outbound_send_count: Cell(Int),
) -> Result(Json, protocol.ProtocolError) {
  use entry <- result.try(
    transport_js.get_cell(handles)
    |> dict.get(name)
    |> result.map_error(fn(_) {
      facade("revert", "Unknown revertible handle: " <> name)
    }),
  )
  let before_event_count = transport_js.get_cell(commit_event_count)
  let before_send_count = transport_js.get_cell(outbound_send_count)
  let before_commits =
    watershed.tree_history_evidence(entry.3)
    |> result.map(protocol.history_commit_ids)
    |> result.unwrap([])
  use originator <- result.try(case entry.5, entry.2 {
    False, _ -> Ok(None)
    True, Some(revision) ->
      list.find(before_commits, fn(commit) { commit.0 == revision })
      |> result.map(fn(commit) { Some(commit.1) })
      |> result.map_error(fn(_) {
        facade("revert", "Revert target lacks an originator")
      })
    True, None -> Error(facade("revert", "Revert target lacks a revision"))
  })
  use _ <- result.try(
    watershed.tree_revert(entry.0, dispose)
    |> result.map_error(fn(reason) { facade("revert", reason) }),
  )
  use authored <- result.try(
    case dict.get(transport_js.get_cell(last_local), entry.4) {
      Ok(authored) if authored.2 > before_event_count -> Ok(authored)
      Error(_) ->
        Error(facade("revert", "Revert authored no local commit event"))
      _ -> Error(facade("revert", "Revert authored no new local commit event"))
    },
  )
  let before_revisions = list.map(before_commits, fn(commit) { commit.0 })
  let submitted_revisions =
    watershed.tree_history_evidence(entry.3)
    |> result.map(protocol.history_commit_ids)
    |> result.unwrap([])
    |> list.filter(fn(commit) {
      Some(commit.1) == originator && !list.contains(before_revisions, commit.0)
    })
    |> list.map(fn(commit) { commit.0 })
  let authored_event_ids = [authored.2]
  let outbound_records =
    transport_js.get_cell(outbound_sends)
    |> list.filter(fn(record) {
      json.parse(json.to_string(record), decode.at(["sendId"], decode.int))
      |> result.map(fn(send_id) { send_id > before_send_count })
      |> result.unwrap(False)
    })
    |> list.reverse
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
  let status = revertible_status(entry.0)
  Ok(
    json.object([
      #("name", json.string(name)),
      #("authoredKind", json.string(commit_kind(authored.1))),
      #("status", json.string(status)),
      #("settlement", json.string("Pending")),
      #("authoredCount", json.int(list.length(authored_event_ids))),
      #("outboundCount", json.int(list.length(submitted_revisions))),
      #("authoredEventIds", json.array(authored_event_ids, json.int)),
      #("actionId", json.string("event-" <> int.to_string(authored.2))),
      #("submittedRevisions", json.array(submitted_revisions, json.string)),
      #("outboundRecords", json.array(outbound_records, fn(record) { record })),
    ]),
  )
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
