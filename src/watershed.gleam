//// Public API: connect to a levee document and edit its root SharedMap.
////
//// ```gleam
//// let assert Ok(doc) = watershed.connect(
////   host: "localhost", port: 4000,
////   tenant: "default", document: "dice",
////   token: jwt, user_id: "user-1",
//// )
//// let map = watershed.root(doc)
//// watershed.set(map, "die", json.int(4))
//// let value = watershed.get(map, "die")
//// let events = watershed.subscribe(map)
//// ```
////
//// Reads are optimistic (local pending edits overlay the sequenced state);
//// convergence is guaranteed by server sequencing. v1 exposes only the
//// root map; additional per-document maps ride the same `address`
//// mechanism later.

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import spillway/message.{ConnectMessage}
import spillway/types.{
  Client, ClientCapabilities, ClientDetails, User, WriteMode,
}

import watershed/map_kernel.{type MapEvent}
import watershed/runtime

/// The default Phoenix websocket mount for levee. `vsn=2.0.0` selects the
/// V2 array frame serializer that the roost codec speaks.
const socket_path = "/socket/websocket?vsn=2.0.0"

const call_timeout_ms = 5000

pub opaque type Document {
  Document(runtime: Subject(runtime.Msg))
}

pub opaque type SharedMap {
  SharedMap(runtime: Subject(runtime.Msg))
}

/// Connect to a document, blocking until the handshake completes and the
/// full op history has been replayed locally.
pub fn connect(
  host host: String,
  port port: Int,
  tenant tenant: String,
  document document: String,
  token token: String,
  user_id user_id: String,
) -> Result(Document, String) {
  let connect_message =
    ConnectMessage(
      tenant_id: tenant,
      document_id: document,
      token: Some(token),
      client: Client(
        mode: WriteMode,
        details: ClientDetails(
          capabilities: ClientCapabilities(interactive: True),
          client_type: Some("watershed"),
          environment: None,
          device: None,
        ),
        permission: [],
        user: User(id: user_id, properties: dict.new()),
        scopes: ["doc:read", "doc:write"],
        timestamp: None,
      ),
      versions: ["^0.1.0"],
      driver_version: None,
      mode: WriteMode,
      nonce: None,
      epoch: None,
      supported_features: None,
      relay_user_agent: None,
    )

  case
    runtime.start(
      host: host,
      port: port,
      path: socket_path,
      tenant: tenant,
      document: document,
      connect_message: connect_message,
    )
  {
    Error(_) -> Error("failed to start document runtime")
    Ok(subject) ->
      case runtime.await_ready(subject) {
        Ok(Nil) -> Ok(Document(runtime: subject))
        Error(reason) -> {
          process.send(subject, runtime.Shutdown)
          Error(reason)
        }
      }
  }
}

/// The document's root map (channel address `"root"`).
pub fn root(document: Document) -> SharedMap {
  SharedMap(runtime: document.runtime)
}

/// Close the connection and stop the runtime.
pub fn close(document: Document) -> Nil {
  process.send(document.runtime, runtime.Shutdown)
}

// ─────────────────────────────────────────────────────────────────────────────
// Edits (optimistic: applied locally immediately, sequenced by the server)
// ─────────────────────────────────────────────────────────────────────────────

pub fn set(map: SharedMap, key: String, value: Json) -> Nil {
  process.send(map.runtime, runtime.Put(key, value))
}

pub fn delete(map: SharedMap, key: String) -> Nil {
  process.send(map.runtime, runtime.Remove(key))
}

pub fn clear(map: SharedMap) -> Nil {
  process.send(map.runtime, runtime.RemoveAll)
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

pub fn get(map: SharedMap, key: String) -> Option(Json) {
  process.call(map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetValue(key, reply)
  })
}

pub fn has(map: SharedMap, key: String) -> Bool {
  get(map, key) != None
}

pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  process.call(
    map.runtime,
    waiting: call_timeout_ms,
    sending: runtime.GetEntries,
  )
}

pub fn keys(map: SharedMap) -> List(String) {
  process.call(map.runtime, waiting: call_timeout_ms, sending: runtime.GetKeys)
}

pub fn size(map: SharedMap) -> Int {
  process.call(map.runtime, waiting: call_timeout_ms, sending: runtime.GetSize)
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

/// Subscribe the calling process to map events. The returned subject
/// receives a `MapEvent` for every local and remote change.
pub fn subscribe(map: SharedMap) -> Subject(MapEvent) {
  let subscriber = process.new_subject()
  process.send(map.runtime, runtime.Subscribe(subscriber))
  subscriber
}
