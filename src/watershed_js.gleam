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
//// convergence is guaranteed by server sequencing. v1 exposes only the root
//// map. JavaScript target only.

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
import watershed/git_storage.{type SummaryVersion}
@target(javascript)
import watershed/map_kernel.{type MapEvent}
@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire.{type SummaryBlob}

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
  SharedMap(runtime: runtime_js.Runtime)
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
  SharedMap(runtime: document.runtime)
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
  runtime_js.set(map.runtime, key, value)
}

@target(javascript)
pub fn delete(map: SharedMap, key: String) -> Nil {
  runtime_js.delete(map.runtime, key)
}

@target(javascript)
pub fn clear(map: SharedMap) -> Nil {
  runtime_js.clear(map.runtime)
}

// ── Reads ────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn get(map: SharedMap, key: String) -> Option(Json) {
  runtime_js.get(map.runtime, key)
}

@target(javascript)
pub fn has(map: SharedMap, key: String) -> Bool {
  get(map, key) != None
}

@target(javascript)
pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  runtime_js.entries(map.runtime)
}

@target(javascript)
pub fn keys(map: SharedMap) -> List(String) {
  runtime_js.keys(map.runtime)
}

@target(javascript)
pub fn size(map: SharedMap) -> Int {
  runtime_js.size(map.runtime)
}

// ── Events ───────────────────────────────────────────────────────────────────

@target(javascript)
/// Register a callback invoked for every local and remote map event.
pub fn subscribe(map: SharedMap, handler: fn(MapEvent) -> Nil) -> Nil {
  runtime_js.subscribe(map.runtime, handler)
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
