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
import watershed/tree_kernel.{TreeChanged}

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
                      let events = transport_js.new_cell([])
                      let subscription = transport_js.new_cell(None)
                      lines(
                        fn(raw) {
                          execute(raw, document, tree, events, subscription)
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
  tree: watershed.SharedTree,
  events: Cell(List(Json)),
  subscription: Cell(Option(watershed.SubscriptionToken)),
) -> Promise(String) {
  case protocol.decode_request(raw) {
    Error(error) ->
      promise.resolve(response(protocol.request_id(raw), Error(error), document))
    Ok(protocol.Request(id, command)) -> {
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
                    TreeChanged(local) -> {
                      let previous = transport_js.get_cell(events)
                      transport_js.set_cell(events, [
                        json.object([#("local", json.bool(local))]),
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
fn checkpoint(
  tree: watershed.SharedTree,
  events: Cell(List(Json)),
) -> Result(Json, protocol.ProtocolError) {
  use root <- result.try(map_result(
    "checkpoint",
    watershed.tree_get(tree, []),
    protocol.encode_read,
  ))
  use values <- result.try(
    list.try_map(
      [
        #("title", ["title"]),
        #("enabled", ["enabled"]),
        #("rating", ["rating"]),
        #("marker", ["marker"]),
        #("note", ["note"]),
        #("point", ["point"]),
        #("x", ["point", "x"]),
        #("y", ["point", "y"]),
      ],
      fn(entry) {
        map_result(
          "checkpoint",
          watershed.tree_get(tree, entry.1),
          protocol.encode_read,
        )
        |> result.map(fn(value) { #(entry.0, value) })
      },
    ),
  )
  let changes = list.reverse(transport_js.get_cell(events))
  transport_js.set_cell(events, [])
  Ok(protocol.encode_checkpoint(root, values, changes))
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
