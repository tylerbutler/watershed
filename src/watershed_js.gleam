//// Public JavaScript API: connect to a levee document and edit its root
//// SharedMap from the browser. The BEAM counterpart is `watershed`.
////
//// ```gleam
//// use token <- promise.map(watershed_js.dev_token(
////   secret: "levee-dev-secret-change-in-production",
////   tenant: "dev-tenant", document: "dice", user_id: "user-1",
//// ))
//// let doc =
////   watershed_js.connect(
////     WatershedConfig(
////       url: "ws://localhost:4000/socket/websocket?vsn=2.0.0",
////       tenant: "dev-tenant", document: "dice",
////       token: token, user_id: "user-1",
////     ),
////     on_ready: fn(result) { ... },
////   )
//// let map = watershed_js.root(doc)
//// watershed_js.set(map, "die", json.int(4))
//// watershed_js.subscribe(map, fn(event) { ... })
//// ```
////
//// Reads are optimistic (local pending edits overlay the sequenced state);
//// convergence is guaranteed by server sequencing. Beyond the root map,
//// `create_map` makes additional (initially detached) maps whose handles
//// (`handle_of`) can be stored as values and `resolve`d by peers, enabling
//// nested collaborative structures. JavaScript target only.

@target(javascript)
import gleam/dict
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import spillway/message.{ConnectMessage}
@target(javascript)
import spillway/types.{
  Client, ClientCapabilities, ClientDetails, User, WriteMode,
}

@target(javascript)
import gleam/result

@target(javascript)
import watershed/channel.{type ChannelEvent}
@target(javascript)
import watershed/git_storage.{type SummaryVersion}
@target(javascript)
import watershed/handle
@target(javascript)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire/summary_blob.{type SummaryBlob}

@target(javascript)
/// Connection parameters for `connect`.
pub type WatershedConfig {
  WatershedConfig(
    /// Phoenix socket URL, e.g.
    /// `"ws://localhost:4000/socket/websocket?vsn=2.0.0"`. The `vsn=2.0.0`
    /// query selects the V2 serializer.
    url: String,
    tenant: String,
    document: String,
    token: String,
    user_id: String,
  )
}

@target(javascript)
pub opaque type Document {
  Document(runtime: runtime_js.Runtime)
}

@target(javascript)
pub opaque type SharedMap {
  SharedMap(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedCounter {
  SharedCounter(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedOrMap {
  SharedOrMap(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
/// Connect to a document. Returns the handle immediately and invokes
/// `on_ready` once the handshake and history replay complete (`Ok(Nil)`) or
/// the connection is rejected (`Error(reason)`).
pub fn connect(
  config: WatershedConfig,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Document {
  let topic = "document:" <> config.tenant <> ":" <> config.document
  let connect_message =
    ConnectMessage(
      tenant_id: config.tenant,
      document_id: config.document,
      token: Some(config.token),
      client: Client(
        mode: WriteMode,
        details: ClientDetails(
          capabilities: ClientCapabilities(interactive: True),
          client_type: Some("watershed-js"),
          environment: None,
          device: None,
        ),
        permission: [],
        user: User(id: config.user_id, properties: dict.new()),
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

  let runtime =
    runtime_js.start(
      url: config.url,
      topic: topic,
      connect_message: connect_message,
      on_ready: on_ready,
    )
  Document(runtime: runtime)
}

@target(javascript)
/// The document's root map (channel address `"root"`).
pub fn root(document: Document) -> SharedMap {
  SharedMap(runtime: document.runtime, address: "root")
}

@target(javascript)
/// Create a new map channel. The map starts *detached* — local-only, its
/// edits produce no ops — until its handle (`handle_of`) is first stored into
/// an attached map, at which point the runtime attaches it (snapshot and all)
/// and starts syncing its edits. Requires a ready connection (`on_ready`).
pub fn create_map(document: Document) -> Result(SharedMap, String) {
  runtime_js.create_map(document.runtime)
  |> result.map(fn(address) {
    SharedMap(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `map`, suitable for storing as a value
/// in another map: `{"type": "__fluid_handle__", "url": "/<address>"}`.
pub fn handle_of(map: SharedMap) -> Json {
  handle.encode_handle(map.address)
}

@target(javascript)
/// Whether a value read from a map is a handle marker (see `resolve`).
pub fn is_handle(value: Json) -> Bool {
  handle.parse_handle(value) != Error(Nil)
}

@target(javascript)
/// Resolve a handle value (from `get`/`entries`) to the SharedMap it
/// references. Errors are retryable: a handle read from a remote value can be
/// transiently unresolved while the referenced channel's attach op is still
/// in flight.
pub fn resolve(document: Document, value: Json) -> Result(SharedMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedMap(runtime: document.runtime, address: address)
      })
  }
}

// ── Counters ─────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new counter channel. Same detached lifecycle as `create_map`:
/// local-only until its handle (`counter_handle_of`) is first stored into an
/// attached map. Requires a ready connection (`on_ready`).
pub fn create_counter(document: Document) -> Result(SharedCounter, String) {
  runtime_js.create_counter(document.runtime)
  |> result.map(fn(address) {
    SharedCounter(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `counter`, suitable for storing as a
/// value in a map (see `handle_of`).
pub fn counter_handle_of(counter: SharedCounter) -> Json {
  handle.encode_handle(counter.address)
}

@target(javascript)
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
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Optimistically increment the counter (negative amounts decrement).
pub fn increment(counter: SharedCounter, amount: Int) -> Nil {
  runtime_js.increment(counter.runtime, counter.address, amount)
}

@target(javascript)
/// The counter's current optimistic value, `None` when the address is not a
/// counter channel.
pub fn counter_value(counter: SharedCounter) -> Option(Int) {
  runtime_js.counter_value(counter.runtime, counter.address)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this
/// counter channel (`channel.CounterEvent(..)`).
pub fn subscribe_counter(
  counter: SharedCounter,
  handler: fn(ChannelEvent) -> Nil,
) -> Nil {
  runtime_js.subscribe(counter.runtime, counter.address, handler)
}

// ── OR-maps ──────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new OR-map channel in tally or register mode. Same detached
/// lifecycle as `create_map`.
pub fn create_or_map(
  document: Document,
  mode: OrMapMode,
) -> Result(SharedOrMap, String) {
  runtime_js.create_or_map(document.runtime, mode)
  |> result.map(fn(address) {
    SharedOrMap(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn or_map_handle_of(or_map: SharedOrMap) -> Json {
  handle.encode_handle(or_map.address)
}

@target(javascript)
pub fn resolve_or_map(
  document: Document,
  value: Json,
) -> Result(SharedOrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedOrMap(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn or_map_increment(or_map: SharedOrMap, key: String, amount: Int) -> Nil {
  runtime_js.or_map_increment(or_map.runtime, or_map.address, key, amount)
}

@target(javascript)
pub fn or_map_set(or_map: SharedOrMap, key: String, value: String) -> Nil {
  runtime_js.or_map_set(or_map.runtime, or_map.address, key, value)
}

@target(javascript)
pub fn or_map_set_json(or_map: SharedOrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(javascript)
pub fn or_map_remove(or_map: SharedOrMap, key: String) -> Nil {
  runtime_js.or_map_remove(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_value(or_map: SharedOrMap, key: String) -> Option(OrMapValue) {
  runtime_js.or_map_value(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_entries(or_map: SharedOrMap) -> List(#(String, OrMapValue)) {
  runtime_js.or_map_entries(or_map.runtime, or_map.address)
}

@target(javascript)
pub fn or_map_keys(or_map: SharedOrMap) -> List(String) {
  runtime_js.or_map_keys(or_map.runtime, or_map.address)
}

@target(javascript)
pub fn subscribe_or_map(
  or_map: SharedOrMap,
  handler: fn(ChannelEvent) -> Nil,
) -> Nil {
  runtime_js.subscribe(or_map.runtime, or_map.address, handler)
}

@target(javascript)
pub fn close(document: Document) -> Nil {
  runtime_js.close(document.runtime)
}

@target(javascript)
/// Fault-injection hook (tests/demos): drop the socket to force the
/// reconnect/reconcile path. Pending and in-flight edits are preserved.
pub fn force_reconnect(document: Document) -> Nil {
  runtime_js.force_reconnect(document.runtime)
}

@target(javascript)
/// Whether the document is fully caught up: every local edit has been
/// acknowledged by the server, so the confirmed state is complete and stable.
/// Useful to wait for quiescence before summarizing.
pub fn is_synced(document: Document) -> Bool {
  runtime_js.is_synced(document.runtime)
}

@target(javascript)
/// Summarize the document's current confirmed state to levee storage so future
/// clients can bootstrap from the snapshot instead of replaying the full op
/// history. Resolves with the summary handle (git tree SHA). Requires the
/// connection to be fully synced and the token to carry `summary:write`.
pub fn summarize(document: Document) -> Promise(Result(String, String)) {
  runtime_js.summarize(document.runtime)
}

@target(javascript)
/// List the document's stored summary versions, newest first — the client
/// half of Fluid's `getVersions`. Each `summarize` call stores one version;
/// the newest is what a fresh connection bootstraps from. Requires the token
/// to carry `doc:read`.
pub fn get_versions(
  document: Document,
  count count: Int,
) -> Promise(Result(List(SummaryVersion), String)) {
  runtime_js.get_versions(document.runtime, count)
}

@target(javascript)
/// Read the historical confirmed state a summary version captured, by its
/// handle (from `get_versions` or a `summarize` resolution). Returns the
/// stored snapshot blob — entries in insertion order plus the sequence number
/// they were captured at. A point-in-time read: the live document is
/// unaffected.
pub fn load_version(
  document: Document,
  handle handle: String,
) -> Promise(Result(SummaryBlob, String)) {
  runtime_js.load_version(document.runtime, handle)
}

// ── Edits (optimistic) ───────────────────────────────────────────────────────

@target(javascript)
pub fn set(map: SharedMap, key: String, value: Json) -> Nil {
  runtime_js.set(map.runtime, map.address, key, value)
}

@target(javascript)
pub fn delete(map: SharedMap, key: String) -> Nil {
  runtime_js.delete(map.runtime, map.address, key)
}

@target(javascript)
pub fn clear(map: SharedMap) -> Nil {
  runtime_js.clear(map.runtime, map.address)
}

// ── Reads ────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn get(map: SharedMap, key: String) -> Option(Json) {
  runtime_js.get(map.runtime, map.address, key)
}

@target(javascript)
pub fn has(map: SharedMap, key: String) -> Bool {
  get(map, key) != None
}

@target(javascript)
pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  runtime_js.entries(map.runtime, map.address)
}

@target(javascript)
pub fn keys(map: SharedMap) -> List(String) {
  runtime_js.keys(map.runtime, map.address)
}

@target(javascript)
pub fn size(map: SharedMap) -> Int {
  runtime_js.size(map.runtime, map.address)
}

// ── Events ───────────────────────────────────────────────────────────────────

@target(javascript)
/// Register a callback invoked for every local and remote change to this map
/// channel. The handler receives a `ChannelEvent` (a `channel.MapEvent(..)`
/// for map channels).
pub fn subscribe(map: SharedMap, handler: fn(ChannelEvent) -> Nil) -> Nil {
  runtime_js.subscribe(map.runtime, map.address, handler)
}

// ── Demo helpers ─────────────────────────────────────────────────────────────

@target(javascript)
/// Mint an HS256 dev JWT for `just server` (dev mode). Signed with Web
/// Crypto, so the token resolves asynchronously. Do not use in production —
/// the tenant secret must never reach the browser there.
pub fn dev_token(
  secret secret: String,
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
) -> Promise(String) {
  transport_js.mint_dev_token(secret, tenant, document, user_id)
}
