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
//// convergence is guaranteed by server sequencing. Beyond the root map,
//// `create_map` makes additional (initially detached) maps whose handles
//// (`handle_of`) can be stored as values and `resolve`d by peers, enabling
//// nested collaborative structures.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/dict
@target(erlang)
import gleam/erlang/process.{type Subject}
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/result

@target(erlang)
import spillway/message.{ConnectMessage}
@target(erlang)
import spillway/types.{
  Client, ClientCapabilities, ClientDetails, User, WriteMode,
}

@target(erlang)
import watershed/channel.{type ChannelEvent}
@target(erlang)
import watershed/git_storage.{type SummaryVersion}
@target(erlang)
import watershed/handle
@target(erlang)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/wire/summary_blob.{type SummaryBlob}

@target(erlang)
/// The default Phoenix websocket mount for levee. `vsn=2.0.0` selects the
/// V2 array frame serializer that the roost codec speaks.
const socket_path = "/socket/websocket?vsn=2.0.0"

@target(erlang)
const call_timeout_ms = 5000

@target(erlang)
pub opaque type Document {
  Document(runtime: Subject(runtime.Msg))
}

@target(erlang)
pub opaque type SharedMap {
  SharedMap(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedCounter {
  SharedCounter(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedOrMap {
  SharedOrMap(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
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
        scopes: ["doc:read", "doc:write", "summary:write"],
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

@target(erlang)
/// The document's root map (channel address `"root"`).
pub fn root(document: Document) -> SharedMap {
  SharedMap(runtime: document.runtime, address: "root")
}

@target(erlang)
/// Create a new map channel. The map starts *detached* — local-only, its
/// edits produce no ops — until its handle (`handle_of`) is first stored into
/// an attached map, at which point the runtime attaches it (snapshot and all)
/// and starts syncing its edits.
pub fn create_map(document: Document) -> Result(SharedMap, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateMap,
  )
  |> result.map(fn(address) {
    SharedMap(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `map`, suitable for storing as a value
/// in another map: `{"type": "__fluid_handle__", "url": "/<address>"}`.
pub fn handle_of(map: SharedMap) -> Json {
  handle.encode_handle(map.address)
}

@target(erlang)
/// Whether a value read from a map is a handle marker (see `resolve`).
pub fn is_handle(value: Json) -> Bool {
  handle.parse_handle(value) != Error(Nil)
}

@target(erlang)
/// Resolve a handle value (from `get`/`entries`) to the SharedMap it
/// references. Errors are retryable: a handle read from a remote value can be
/// transiently unresolved while the referenced channel's attach op is still
/// in flight.
pub fn resolve(document: Document, value: Json) -> Result(SharedMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedMap(runtime: document.runtime, address: address)
      })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Counters
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new counter channel. Same detached lifecycle as `create_map`:
/// local-only until its handle (`counter_handle_of`) is first stored into an
/// attached map.
pub fn create_counter(document: Document) -> Result(SharedCounter, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateCounter,
  )
  |> result.map(fn(address) {
    SharedCounter(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `counter`, suitable for storing as a
/// value in a map (see `handle_of`).
pub fn counter_handle_of(counter: SharedCounter) -> Json {
  handle.encode_handle(counter.address)
}

@target(erlang)
/// Resolve a handle value to the SharedCounter it references. Existence is
/// checked, not channel type: resolving a non-counter yields a counter whose
/// reads return `None`. Errors are retryable, as with `resolve`.
pub fn resolve_counter(
  document: Document,
  value: Json,
) -> Result(SharedCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically increment the counter (negative amounts decrement).
pub fn increment(counter: SharedCounter, amount: Int) -> Nil {
  process.send(
    counter.runtime,
    runtime.IncrementCounter(counter.address, amount),
  )
}

@target(erlang)
/// The counter's current optimistic value, `None` when the address is not a
/// counter channel.
pub fn counter_value(counter: SharedCounter) -> Option(Int) {
  process.call(counter.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetCounterValue(counter.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this counter's events
/// (`channel.CounterEvent(..)`), local and remote alike.
pub fn subscribe_counter(counter: SharedCounter) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(counter.runtime, runtime.Subscribe(counter.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-maps
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new OR-map channel in tally or register mode. Same detached
/// lifecycle as `create_map`: local-only until its handle is stored into an
/// attached container.
pub fn create_or_map(
  document: Document,
  mode: OrMapMode,
) -> Result(SharedOrMap, String) {
  process.call(document.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.CreateOrMap(mode, reply)
  })
  |> result.map(fn(address) {
    SharedOrMap(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn or_map_handle_of(or_map: SharedOrMap) -> Json {
  handle.encode_handle(or_map.address)
}

@target(erlang)
pub fn resolve_or_map(
  document: Document,
  value: Json,
) -> Result(SharedOrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedOrMap(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn or_map_increment(or_map: SharedOrMap, key: String, amount: Int) -> Nil {
  process.send(
    or_map.runtime,
    runtime.IncrementOrMap(or_map.address, key, amount),
  )
}

@target(erlang)
pub fn or_map_set(or_map: SharedOrMap, key: String, value: String) -> Nil {
  process.send(or_map.runtime, runtime.SetOrMapKey(or_map.address, key, value))
}

@target(erlang)
pub fn or_map_set_json(or_map: SharedOrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(erlang)
pub fn or_map_remove(or_map: SharedOrMap, key: String) -> Nil {
  process.send(or_map.runtime, runtime.RemoveOrMapKey(or_map.address, key))
}

@target(erlang)
pub fn or_map_value(or_map: SharedOrMap, key: String) -> Option(OrMapValue) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapValue(or_map.address, key, reply)
  })
}

@target(erlang)
pub fn or_map_entries(or_map: SharedOrMap) -> List(#(String, OrMapValue)) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapEntries(or_map.address, reply)
  })
}

@target(erlang)
pub fn or_map_keys(or_map: SharedOrMap) -> List(String) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapKeys(or_map.address, reply)
  })
}

@target(erlang)
pub fn subscribe_or_map(or_map: SharedOrMap) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(or_map.runtime, runtime.Subscribe(or_map.address, subscriber))
  subscriber
}

@target(erlang)
/// Close the connection and stop the runtime.
pub fn close(document: Document) -> Nil {
  process.send(document.runtime, runtime.Shutdown)
}

@target(erlang)
/// Fault-injection hook (primarily for tests): drop the current transport
/// channel, forcing the runtime through its reconnect/reconcile path. Pending
/// and in-flight edits are preserved and resubmitted after the reconnect.
pub fn force_reconnect(document: Document) -> Nil {
  process.send(document.runtime, runtime.DropChannel)
}

@target(erlang)
/// Summarize the document's current confirmed state to levee storage so future
/// clients can bootstrap from the snapshot instead of replaying the full op
/// history. Returns the summary handle (git tree SHA). Requires the connection
/// to be fully synced and the token to carry the `summary:write` scope.
pub fn summarize(document: Document) -> Result(String, String) {
  runtime.summarize(document.runtime)
}

@target(erlang)
/// Whether the document is fully caught up: every local edit has been
/// acknowledged by the server, so the confirmed state is complete and stable.
/// Useful to wait for quiescence before summarizing or handing off.
pub fn is_synced(document: Document) -> Bool {
  runtime.is_synced(document.runtime)
}

@target(erlang)
/// List the document's stored summary versions, newest first — the client
/// half of Fluid's `getVersions`. Each `summarize` call stores one version;
/// the newest is what a fresh connection bootstraps from. Requires the token
/// to carry `doc:read`.
pub fn get_versions(
  document: Document,
  count count: Int,
) -> Result(List(SummaryVersion), String) {
  runtime.get_versions(document.runtime, count)
}

@target(erlang)
/// Read the historical confirmed state a summary version captured, by its
/// handle (from `get_versions` or a `summarize` return). Returns the stored
/// snapshot blob — entries in insertion order plus the sequence number they
/// were captured at. A point-in-time read: the live document is unaffected.
pub fn load_version(
  document: Document,
  handle handle: String,
) -> Result(SummaryBlob, String) {
  runtime.load_version(document.runtime, handle)
}

// ─────────────────────────────────────────────────────────────────────────────
// Edits (optimistic: applied locally immediately, sequenced by the server)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn set(map: SharedMap, key: String, value: Json) -> Nil {
  process.send(map.runtime, runtime.Put(map.address, key, value))
}

@target(erlang)
pub fn delete(map: SharedMap, key: String) -> Nil {
  process.send(map.runtime, runtime.Remove(map.address, key))
}

@target(erlang)
pub fn clear(map: SharedMap) -> Nil {
  process.send(map.runtime, runtime.RemoveAll(map.address))
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn get(map: SharedMap, key: String) -> Option(Json) {
  process.call(map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetValue(map.address, key, reply)
  })
}

@target(erlang)
pub fn has(map: SharedMap, key: String) -> Bool {
  get(map, key) != None
}

@target(erlang)
pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  process.call(map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetEntries(map.address, reply)
  })
}

@target(erlang)
pub fn keys(map: SharedMap) -> List(String) {
  process.call(map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetKeys(map.address, reply)
  })
}

@target(erlang)
pub fn size(map: SharedMap) -> Int {
  process.call(map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetSize(map.address, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Subscribe the calling process to this map's events. The returned subject
/// receives a `ChannelEvent` (a `channel.MapEvent(..)` for map channels) for
/// every local and remote change to this channel.
pub fn subscribe(map: SharedMap) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(map.runtime, runtime.Subscribe(map.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Dev JWT helper
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Mint an HS256 dev JWT for a levee server running in dev mode (`just server`).
/// Matches the signature that `watershed_js.dev_token` produces on the JS
/// target. **Do not use in production** — the secret must never be embedded in
/// a deployed binary.
///
/// ```gleam
/// let token = watershed.dev_token(
///   secret: "levee-dev-secret-change-in-production",
///   tenant: "dev-tenant", document: "dice", user_id: "user-1",
/// )
/// ```
pub fn dev_token(
  secret secret: String,
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
) -> String {
  let now = system_time(Second)
  let header =
    json.object([
      #("alg", json.string("HS256")),
      #("typ", json.string("JWT")),
    ])
  let payload =
    json.object([
      #("documentId", json.string(document)),
      #("tenantId", json.string(tenant)),
      #(
        "scopes",
        json.array(["doc:read", "doc:write", "summary:write"], json.string),
      ),
      #("user", json.object([#("id", json.string(user_id))])),
      #("iat", json.int(now)),
      #("exp", json.int(now + 3600)),
      #("ver", json.string("1.0")),
    ])
  let signing_input =
    base64url(<<json.to_string(header):utf8>>)
    <> "."
    <> base64url(<<json.to_string(payload):utf8>>)
  let signature =
    crypto.hmac(<<signing_input:utf8>>, crypto.Sha256, <<secret:utf8>>)
  signing_input <> "." <> base64url(signature)
}

@target(erlang)
fn base64url(data: BitArray) -> String {
  bit_array.base64_url_encode(data, False)
}

@target(erlang)
type TimeUnit {
  Second
}

@target(erlang)
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int
