@target(erlang)
import gleam/erlang/process
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
import watershed/tree/types.{ObjectValue}
@target(erlang)
import watershed/tree_kernel.{TreeChanged}
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
                      loop(document, tree, None, False)
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
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
) -> Nil {
  case read_line() {
    Error(_) -> Nil
    Ok(line) -> {
      let #(output, next_events, next_active, closing) =
        execute(line, document, tree, events, active)
      write_line(output)
      case closing {
        True -> Nil
        False -> loop(document, tree, next_events, next_active)
      }
    }
  }
}

@target(erlang)
fn execute(
  raw: String,
  document: watershed.Document(a),
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
) -> #(String, Option(process.Subject(tree_kernel.TreeEvent)), Bool, Bool) {
  case protocol.decode_request(raw) {
    Error(error) -> #(
      response(protocol.request_id(raw), Error(error), document),
      events,
      active,
      False,
    )
    Ok(protocol.Request(id, command)) -> {
      let #(outcome, next_events, next_active, closing) = case command {
        protocol.Read(path) -> #(
          map_result(
            "read",
            watershed.tree_get(tree, path),
            protocol.encode_read,
          ),
          events,
          active,
          False,
        )
        protocol.Set(path, value) -> #(
          map_result("set", watershed.tree_set(tree, path, value), fn(_) {
            json.null()
          }),
          events,
          active,
          False,
        )
        protocol.Clear(path) -> #(
          map_result("clear", watershed.tree_clear(tree, path), fn(_) {
            json.null()
          }),
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
          events,
          active,
          False,
        )
        protocol.Checkpoint -> #(
          checkpoint(tree, events, active),
          events,
          active,
          False,
        )
        protocol.Subscribe -> {
          let subscriber = case events {
            None -> Some(watershed.subscribe_tree(tree))
            Some(_) -> events
          }
          #(Ok(json.null()), subscriber, True, False)
        }
        protocol.Unsubscribe -> #(Ok(json.null()), events, False, False)
        protocol.Disconnect -> {
          watershed.force_reconnect(document)
          #(Ok(json.null()), events, active, False)
        }
        protocol.Reconnect -> {
          #(Ok(json.null()), events, active, False)
        }
        protocol.AwaitSynced(watermark) -> #(
          await_synced(document, watermark, 1200),
          events,
          active,
          False,
        )
        protocol.Summarize -> #(
          map_result("summarize", watershed.summarize(document), json.string),
          events,
          active,
          False,
        )
        protocol.Close -> #(Ok(json.null()), events, active, True)
      }
      #(
        response(Some(id), outcome, document),
        next_events,
        next_active,
        closing,
      )
    }
  }
}

@target(erlang)
fn checkpoint(
  tree: watershed.SharedTree,
  events: Option(process.Subject(tree_kernel.TreeEvent)),
  active: Bool,
) -> Result(Json, protocol.ProtocolError) {
  use root_value <- result.try(
    watershed.tree_get(tree, [])
    |> result.map_error(fn(reason) {
      protocol.ProtocolError("facade-error", "checkpoint", reason)
    }),
  )
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
    _ ->
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
      )
  })
  let changes = case events, active {
    Some(subject), True -> drain(subject, [])
    _, _ -> []
  }
  Ok(protocol.encode_checkpoint(root, values, changes))
}

@target(erlang)
fn drain(
  events: process.Subject(tree_kernel.TreeEvent),
  collected: List(Json),
) -> List(Json) {
  case process.receive(from: events, within: 0) {
    Error(_) -> list.reverse(collected)
    Ok(TreeChanged(local)) ->
      drain(events, [json.object([#("local", json.bool(local))]), ..collected])
  }
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
