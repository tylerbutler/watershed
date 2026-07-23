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
//// nested collaborative structures.
////
//// For a schema-typed view, `typed` wraps a map as a `TypedMap(s)` and the
//// `set_field`/`get_field`/`read`/`write` functions read and write through a
//// `watershed/schema` declaration. `ensure_*` seeds and adopts nested channels
//// (maps, counters, OR-sets, claims, …) declaratively, and `subscribe_field` /
//// `subscribe_counter` / `subscribe_typed` deliver narrowed, decoded events.
//// See [`examples/sudoku_lustre`](../examples/sudoku_lustre) for the full
//// pattern. JavaScript target only.

@target(javascript)
import gleam/dict
@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import signet/types as token
@target(javascript)
import spillway/message.{type SignalMessage, ConnectMessage}
@target(javascript)
import spillway/types.{Client, ClientCapabilities, ClientDetails, WriteMode}

@target(javascript)
import gleam/result

@target(javascript)
import lattice_sequence/sequence.{After, Before}

@target(javascript)
import watershed/channel.{type ChannelEvent}
@target(javascript)
import watershed/claims_kernel
@target(javascript)
import watershed/counter_kernel
@target(javascript)
import watershed/directory_kernel
@target(javascript)
import watershed/g_set_kernel
@target(javascript)
import watershed/git_storage.{type SummaryVersion}
@target(javascript)
import watershed/handle
@target(javascript)
import watershed/json_ot
@target(javascript)
import watershed/json_ot_kernel
@target(javascript)
import watershed/map_kernel
@target(javascript)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(javascript)
import watershed/or_set_kernel
@target(javascript)
import watershed/register_collection_kernel.{type ReadPolicy, Atomic}
@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
  type FieldError,
}
@target(javascript)
import watershed/sequence_kernel
@target(javascript)
import watershed/task_manager_kernel
@target(javascript)
import watershed/text_kernel
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/two_p_set_kernel
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
/// Read-only connection and sequencing state for diagnostics and example UIs.
pub type Diagnostics =
  runtime_js.Diagnostics

@target(javascript)
pub opaque type SharedMap {
  SharedMap(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedCounter {
  SharedCounter(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type OrMap {
  OrMap(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type OrSet {
  OrSet(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type RegisterCollection {
  RegisterCollection(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type Claims {
  Claims(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type TaskManager {
  TaskManager(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type PnCounter {
  PnCounter(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type PactMap {
  PactMap(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type OrderedCollection {
  OrderedCollection(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedSequence {
  SharedSequence(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedText {
  SharedText(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
/// A stable position in a `SharedText`'s optimistic string that survives
/// concurrent edits and merges. Opaque — construct one with `text_anchor_at`,
/// `text_start_anchor`, or `text_end_anchor`, or decode one with
/// `text_anchor_from_json`.
pub type TextAnchor =
  text_kernel.TextAnchor

@target(javascript)
/// Which grapheme a `TextAnchor` binds to across concurrent inserts at its
/// gap. `Before` binds to the following grapheme (inserts at the gap push it
/// right); `After` binds to the preceding grapheme (inserts at the gap land
/// after it). Re-exported so callers don't need a direct `lattice_sequence`
/// dependency to build one.
pub type Bias =
  text_kernel.Bias

@target(javascript)
pub const bias_before: Bias = Before

@target(javascript)
pub const bias_after: Bias = After

@target(javascript)
pub opaque type JsonOt {
  JsonOt(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type GSet {
  GSet(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type TwoPSet {
  TwoPSet(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedDirectory {
  SharedDirectory(runtime: runtime_js.Runtime, address: String)
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
        user: token.User(id: config.user_id, properties: dict.new()),
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
/// Connect through an injected transport — the seam the in-memory `sluice_js`
/// test driver uses. `on_ready` still fires when the handshake completes, which
/// the driver triggers by delivering the handshake frame on `settle`. Not for
/// production use.
pub fn connect_via(
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
  transport transport: runtime_js.Transport,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Document {
  let connect_message =
    ConnectMessage(
      tenant_id: tenant,
      document_id: document,
      token: None,
      client: Client(
        mode: WriteMode,
        details: ClientDetails(
          capabilities: ClientCapabilities(interactive: True),
          client_type: Some("watershed-js"),
          environment: None,
          device: None,
        ),
        permission: [],
        user: token.User(id: user_id, properties: dict.new()),
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
  Document(runtime: runtime_js.start_with_transport(
    http_base_url: "sluice",
    connect_message: connect_message,
    transport: transport,
    on_ready: on_ready,
  ))
}

@target(javascript)
/// The runtime behind a document. Exposed for the `sluice_js` test driver, which
/// keys paused clients by their runtime. Not part of the app-facing API.
pub fn runtime_of(document: Document) -> runtime_js.Runtime {
  document.runtime
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

// ── Typed maps ───────────────────────────────────────────────────────────────
//
// An opt-in, phantom-typed view over a SharedMap. `schema` is pinned by
// inference the first time a `Field(schema, _)` is used against the map, so a
// field from one schema cannot be applied to a map of another. Typing is a
// decode boundary (remote peers may write anything), so reads return `Result`.
// See `watershed/schema` for defining fields.

@target(javascript)
/// A SharedMap viewed through a schema `s`.
pub opaque type TypedMap(s) {
  TypedMap(map: SharedMap)
}

@target(javascript)
/// View a raw map through a schema. The schema is chosen by how the result is
/// used (or by annotation): `let players: TypedMap(Roster) = typed(map)`.
pub fn typed(map: SharedMap) -> TypedMap(s) {
  TypedMap(map: map)
}

@target(javascript)
/// The underlying raw map, for dropping back to the untyped API.
pub fn untyped(typed_map: TypedMap(s)) -> SharedMap {
  typed_map.map
}

@target(javascript)
/// The document's root map, viewed through a schema.
pub fn root_typed(document: Document) -> TypedMap(s) {
  typed(root(document))
}

@target(javascript)
/// Create a new (detached) map, viewed through a schema. Same lifecycle as
/// `create_map`.
pub fn create_typed_map(document: Document) -> Result(TypedMap(s), String) {
  create_map(document) |> result.map(typed)
}

@target(javascript)
/// Optimistically write a typed field.
pub fn set_field(typed_map: TypedMap(s), field: Field(s, a), value: a) -> Nil {
  set(typed_map.map, schema.field_key(field), schema.encode_value(field, value))
}

@target(javascript)
/// Optimistically delete a typed field.
pub fn delete_field(typed_map: TypedMap(s), field: Field(s, a)) -> Nil {
  delete(typed_map.map, schema.field_key(field))
}

@target(javascript)
/// Read a typed field. `Ok(None)` when the key is absent; `Error(Invalid)`
/// when the stored value does not decode to `a`.
pub fn get_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
) -> Result(Option(a), FieldError) {
  case get(typed_map.map, schema.field_key(field)) {
    None -> Ok(None)
    Some(stored) -> schema.decode_value(field, stored) |> result.map(Some)
  }
}

@target(javascript)
/// Read a typed field that is expected to exist. `Error(Missing)` when absent.
pub fn get_required(
  typed_map: TypedMap(s),
  field: Field(s, a),
) -> Result(a, FieldError) {
  case get_field(typed_map, field) {
    Ok(Some(value)) -> Ok(value)
    Ok(None) -> Error(schema.Missing(schema.field_key(field)))
    Error(reason) -> Error(reason)
  }
}

@target(javascript)
/// Whether a typed field is present (does not check that it decodes).
pub fn has_field(typed_map: TypedMap(s), field: Field(s, a)) -> Bool {
  has(typed_map.map, schema.field_key(field))
}

@target(javascript)
/// Store a handle to a nested typed map under a child field.
pub fn set_child(
  typed_map: TypedMap(s),
  field: ChildField(s, c),
  child: TypedMap(c),
) -> Nil {
  set(typed_map.map, schema.child_key(field), handle_of(child.map))
}

@target(javascript)
/// Resolve the nested typed map referenced by a child field. `Ok(None)` when
/// the key is absent; errors from `resolve` (including transient
/// not-yet-attached ones) are surfaced as-is and are retryable.
pub fn resolve_child(
  document: Document,
  typed_map: TypedMap(s),
  field: ChildField(s, c),
) -> Result(Option(TypedMap(c)), String) {
  case get(typed_map.map, schema.child_key(field)) {
    None -> Ok(None)
    Some(value) ->
      resolve(document, value) |> result.map(fn(m) { Some(typed(m)) })
  }
}

@target(javascript)
/// Read the whole map as a typed record through a schema: one `Result`, after
/// the schema's version and seal checks. See `watershed/schema`.
pub fn read(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
) -> Result(record, FieldError) {
  schema.decode_entries(map_schema, entries(typed_map.map))
}

@target(javascript)
/// Write a whole record through a schema, as per-key ops — so concurrent
/// edits to sibling keys still merge (the record view is never a clobbering
/// blob). Optional props that are `None` delete their key.
pub fn write(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
  value: record,
) -> Nil {
  list.each(schema.encode_ops(map_schema, value), fn(op) {
    case op {
      schema.Put(key, entry_value) -> set(typed_map.map, key, entry_value)
      schema.Delete(key) -> delete(typed_map.map, key)
    }
  })
}

@target(javascript)
/// Stamp a versioned schema's version marker once (typically right after
/// creating the map). A no-op for unversioned schemas.
pub fn stamp(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
) -> Nil {
  case schema.stamp_entry(map_schema) {
    Some(entry) -> set(typed_map.map, entry.0, entry.1)
    None -> Nil
  }
}

@target(javascript)
/// Resolve every handle-valued key to a typed child map — the typed view of a
/// dynamic collection (a map whose keys are not statically known, e.g. a
/// roster keyed by id). Non-handle keys are skipped; each child's resolution
/// `Result` is surfaced (transient not-yet-attached errors are retryable).
pub fn typed_children(
  document: Document,
  typed_map: TypedMap(parent),
) -> List(#(String, Result(TypedMap(child), String))) {
  entries(typed_map.map)
  |> list.filter(fn(entry) { is_handle(entry.1) })
  |> list.map(fn(entry) {
    #(entry.0, resolve(document, entry.1) |> result.map(typed))
  })
}

// ── Typed channel fields ─────────────────────────────────────────────────────
//
// Per-kind set/resolve pairs for `schema.ChannelField(s, kind)` — keys whose
// value is a handle to a non-map channel. The phantom kind tag makes using a
// field with the wrong kind's resolver a compile error. Dispatch is per kind
// because each resolver is a different runtime call with a different return
// type. Resolvers return `Ok(None)` when the key is absent; resolve errors
// (including transient not-yet-attached ones) are surfaced as-is and are
// retryable.

@target(javascript)
fn put_channel_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, kind),
  handle_json: Json,
) -> Nil {
  set(typed_map.map, schema.channel_field_key(field), handle_json)
}

@target(javascript)
fn get_channel_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, kind),
  resolver: fn(Document, Json) -> Result(shared, String),
) -> Result(Option(shared), String) {
  case get(typed_map.map, schema.channel_field_key(field)) {
    None -> Ok(None)
    Some(value) -> resolver(document, value) |> result.map(Some)
  }
}

@target(javascript)
/// Store a handle to an (untyped) nested map under a typed channel field.
pub fn set_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
  map: SharedMap,
) -> Nil {
  put_channel_field(typed_map, field, handle_of(map))
}

@target(javascript)
/// Resolve the map referenced by a typed channel field.
pub fn resolve_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
) -> Result(Option(SharedMap), String) {
  get_channel_field(document, typed_map, field, resolve)
}

@target(javascript)
/// Store a handle to `counter` under a typed channel field.
pub fn set_counter_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
  counter: SharedCounter,
) -> Nil {
  put_channel_field(typed_map, field, counter_handle_of(counter))
}

@target(javascript)
/// Resolve the counter referenced by a typed channel field.
pub fn resolve_counter_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
) -> Result(Option(SharedCounter), String) {
  get_channel_field(document, typed_map, field, resolve_counter)
}

@target(javascript)
/// Store a handle to `or_map` under a typed channel field.
pub fn set_or_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  or_map: OrMap,
) -> Nil {
  put_channel_field(typed_map, field, or_map_handle_of(or_map))
}

@target(javascript)
/// Resolve the OR-map referenced by a typed channel field.
pub fn resolve_or_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
) -> Result(Option(OrMap), String) {
  get_channel_field(document, typed_map, field, resolve_or_map)
}

@target(javascript)
/// Store a handle to `or_set` under a typed channel field.
pub fn set_or_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  or_set: OrSet,
) -> Nil {
  put_channel_field(typed_map, field, or_set_handle_of(or_set))
}

@target(javascript)
/// Resolve the OR-set referenced by a typed channel field.
pub fn resolve_or_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
) -> Result(Option(OrSet), String) {
  get_channel_field(document, typed_map, field, resolve_or_set)
}

@target(javascript)
pub fn set_sequence_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  sequence: SharedSequence,
) -> Nil {
  put_channel_field(typed_map, field, sequence_handle_of(sequence))
}

@target(javascript)
pub fn resolve_sequence_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(Option(SharedSequence), String) {
  get_channel_field(document, typed_map, field, resolve_sequence)
}

@target(javascript)
/// Store a handle to `text` under a typed channel field.
pub fn set_text_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  text: SharedText,
) -> Nil {
  put_channel_field(typed_map, field, text_handle_of(text))
}

@target(javascript)
/// Resolve the text channel referenced by a typed channel field.
pub fn resolve_text_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
) -> Result(Option(SharedText), String) {
  get_channel_field(document, typed_map, field, resolve_text)
}

@target(javascript)
/// Store a handle to `collection` under a typed channel field.
pub fn set_register_collection_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  collection: RegisterCollection,
) -> Nil {
  put_channel_field(typed_map, field, register_collection_handle_of(collection))
}

@target(javascript)
/// Resolve the register collection referenced by a typed channel field.
pub fn resolve_register_collection_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
) -> Result(Option(RegisterCollection), String) {
  get_channel_field(document, typed_map, field, resolve_register_collection)
}

@target(javascript)
/// Store a handle to `claims` under a typed channel field.
pub fn set_claims_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  claims: Claims,
) -> Nil {
  put_channel_field(typed_map, field, claims_handle_of(claims))
}

@target(javascript)
/// Resolve the claims channel referenced by a typed channel field.
pub fn resolve_claims_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
) -> Result(Option(Claims), String) {
  get_channel_field(document, typed_map, field, resolve_claims)
}

@target(javascript)
/// Store a handle to `manager` under a typed channel field.
pub fn set_task_manager_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  manager: TaskManager,
) -> Nil {
  put_channel_field(typed_map, field, task_manager_handle_of(manager))
}

@target(javascript)
/// Resolve the task manager referenced by a typed channel field.
pub fn resolve_task_manager_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
) -> Result(Option(TaskManager), String) {
  get_channel_field(document, typed_map, field, resolve_task_manager)
}

@target(javascript)
/// Store a handle to `pn_counter` under a typed channel field.
pub fn set_pn_counter_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
  pn_counter: PnCounter,
) -> Nil {
  put_channel_field(typed_map, field, pn_counter_handle_of(pn_counter))
}

@target(javascript)
/// Resolve the PN-counter referenced by a typed channel field.
pub fn resolve_pn_counter_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
) -> Result(Option(PnCounter), String) {
  get_channel_field(document, typed_map, field, resolve_pn_counter)
}

@target(javascript)
/// Store a handle to `pact_map` under a typed channel field.
pub fn set_pact_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
  pact_map: PactMap,
) -> Nil {
  put_channel_field(typed_map, field, pact_map_handle_of(pact_map))
}

@target(javascript)
/// Resolve the PactMap referenced by a typed channel field.
pub fn resolve_pact_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
) -> Result(Option(PactMap), String) {
  get_channel_field(document, typed_map, field, resolve_pact_map)
}

@target(javascript)
/// Store a handle to `collection` under a typed channel field.
pub fn set_ordered_collection_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
  collection: OrderedCollection,
) -> Nil {
  put_channel_field(typed_map, field, ordered_collection_handle_of(collection))
}

@target(javascript)
/// Resolve the ordered collection referenced by a typed channel field.
pub fn resolve_ordered_collection_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
) -> Result(Option(OrderedCollection), String) {
  get_channel_field(document, typed_map, field, resolve_ordered_collection)
}

@target(javascript)
/// Store a handle to `json_ot` under a typed channel field.
pub fn set_json_ot_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
  json_ot: JsonOt,
) -> Nil {
  put_channel_field(typed_map, field, json_ot_handle_of(json_ot))
}

@target(javascript)
/// Resolve the json0 channel referenced by a typed channel field.
pub fn resolve_json_ot_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
) -> Result(Option(JsonOt), String) {
  get_channel_field(document, typed_map, field, resolve_json_ot)
}

@target(javascript)
/// Store a handle to `set` under a typed channel field.
pub fn set_g_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
  set: GSet,
) -> Nil {
  put_channel_field(typed_map, field, g_set_handle_of(set))
}

@target(javascript)
/// Resolve the G-set referenced by a typed channel field.
pub fn resolve_g_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
) -> Result(Option(GSet), String) {
  get_channel_field(document, typed_map, field, resolve_g_set)
}

@target(javascript)
/// Store a handle to `set` under a typed channel field.
pub fn set_two_p_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
  set: TwoPSet,
) -> Nil {
  put_channel_field(typed_map, field, two_p_set_handle_of(set))
}

@target(javascript)
/// Resolve the 2P-set referenced by a typed channel field.
pub fn resolve_two_p_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
) -> Result(Option(TwoPSet), String) {
  get_channel_field(document, typed_map, field, resolve_two_p_set)
}

@target(javascript)
/// Store a handle to `dir` under a typed channel field.
pub fn set_directory_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
  dir: SharedDirectory,
) -> Nil {
  put_channel_field(typed_map, field, directory_handle_of(dir))
}

@target(javascript)
/// Resolve the directory referenced by a typed channel field.
pub fn resolve_directory_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
) -> Result(Option(SharedDirectory), String) {
  get_channel_field(document, typed_map, field, resolve_directory)
}

// ── Declarative bootstrap (ensure_*) ─────────────────────────────────────────
//
// Each `ensure_*` gives a typed slot a guaranteed channel: adopt the sequenced
// LWW winner if the key is already set, otherwise seed a candidate channel,
// wait for sync, and adopt whichever handle the sequencer ordered first (losing
// candidates stay attached but unreferenced — orphan GC is out of scope). The
// browser cannot block, so each takes a `done` continuation and waits/retries
// on a library-owned timer; the BEAM facade blocks and returns instead.

@target(javascript)
@external(javascript, "./watershed_js_ffi.mjs", "set_timeout")
fn set_timeout(action: fn() -> Nil, ms: Int) -> Nil

@target(javascript)
const resolve_retry_ms = 200

@target(javascript)
const resolve_attempts = 25

@target(javascript)
/// Poll `is_synced` until the confirmed root is stable (bounded by the resolve
/// budget), then invoke `next`.
fn await_synced(document: Document, attempts: Int, next: fn() -> Nil) -> Nil {
  case attempts <= 0 || is_synced(document) {
    True -> next()
    False ->
      set_timeout(
        fn() { await_synced(document, attempts - 1, next) },
        resolve_retry_ms,
      )
  }
}

@target(javascript)
/// Resolve a field to its channel, retrying on a timer while the handle is
/// absent or the referenced channel's attach op is still in flight.
fn resolve_with_retry(
  resolve: fn() -> Result(Option(shared), String),
  attempts: Int,
  done: fn(Result(shared, String)) -> Nil,
) -> Nil {
  case resolve(), attempts {
    Ok(Some(shared)), _ -> done(Ok(shared))
    Ok(None), n if n <= 1 ->
      done(Error("ensure: no channel handle appeared under the field"))
    Error(reason), n if n <= 1 -> done(Error(reason))
    _, _ ->
      set_timeout(
        fn() { resolve_with_retry(resolve, attempts - 1, done) },
        resolve_retry_ms,
      )
  }
}

@target(javascript)
/// Adopt the channel under `key`: resolve the sequenced winner if the key is
/// set, else `seed` a candidate, wait for sync, and resolve whatever won.
fn ensure_channel(
  document: Document,
  typed_map: TypedMap(s),
  key: String,
  seed: fn() -> Result(Nil, String),
  resolve: fn() -> Result(Option(shared), String),
  done: fn(Result(shared, String)) -> Nil,
) -> Nil {
  case has(typed_map.map, key) {
    True -> resolve_with_retry(resolve, resolve_attempts, done)
    False ->
      case seed() {
        Error(reason) -> done(Error(reason))
        Ok(Nil) ->
          await_synced(document, resolve_attempts, fn() {
            resolve_with_retry(resolve, resolve_attempts, done)
          })
      }
  }
}

@target(javascript)
/// Ensure a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
  done: fn(Result(SharedMap, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use map <- result.map(create_map(document))
      set_map_field(typed_map, field, map)
    },
    fn() { resolve_map_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
  done: fn(Result(SharedCounter, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use counter <- result.map(create_counter(document))
      set_counter_field(typed_map, field, counter)
    },
    fn() { resolve_counter_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure an OR-map exists under `field`, seeding one in `mode` if absent.
pub fn ensure_or_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  mode: OrMapMode,
  done: fn(Result(OrMap, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use or_map <- result.map(create_or_map(document, mode))
      set_or_map_field(typed_map, field, or_map)
    },
    fn() { resolve_or_map_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  done: fn(Result(OrSet, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use or_set <- result.map(create_or_set(document))
      set_or_set_field(typed_map, field, or_set)
    },
    fn() { resolve_or_set_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
pub fn ensure_sequence(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  done: fn(Result(SharedSequence, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use sequence <- result.map(create_sequence(document))
      set_sequence_field(typed_map, field, sequence)
    },
    fn() { resolve_sequence_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a text channel exists under `field`, seeding one if the slot is
/// empty.
pub fn ensure_text(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  done: fn(Result(SharedText, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use text <- result.map(create_text(document))
      set_text_field(typed_map, field, text)
    },
    fn() { resolve_text_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  done: fn(Result(RegisterCollection, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use registers <- result.map(create_register_collection(document))
      set_register_collection_field(typed_map, field, registers)
    },
    fn() { resolve_register_collection_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  done: fn(Result(Claims, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use claims <- result.map(create_claims(document))
      set_claims_field(typed_map, field, claims)
    },
    fn() { resolve_claims_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  done: fn(Result(TaskManager, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use tasks <- result.map(create_task_manager(document))
      set_task_manager_field(typed_map, field, tasks)
    },
    fn() { resolve_task_manager_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a PN-counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_pn_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
  done: fn(Result(PnCounter, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use pn_counter <- result.map(create_pn_counter(document))
      set_pn_counter_field(typed_map, field, pn_counter)
    },
    fn() { resolve_pn_counter_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
  done: fn(Result(PactMap, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use pact_map <- result.map(create_pact_map(document))
      set_pact_map_field(typed_map, field, pact_map)
    },
    fn() { resolve_pact_map_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
  done: fn(Result(OrderedCollection, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use collection <- result.map(create_ordered_collection(document))
      set_ordered_collection_field(typed_map, field, collection)
    },
    fn() { resolve_ordered_collection_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a json0 channel exists under `field`, seeding one if absent.
pub fn ensure_json_ot(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
  done: fn(Result(JsonOt, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use json_ot <- result.map(create_json_ot(document))
      set_json_ot_field(typed_map, field, json_ot)
    },
    fn() { resolve_json_ot_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a G-set exists under `field`, seeding one if absent.
pub fn ensure_g_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
  done: fn(Result(GSet, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use set <- result.map(create_g_set(document))
      set_g_set_field(typed_map, field, set)
    },
    fn() { resolve_g_set_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a 2P-set exists under `field`, seeding one if absent.
pub fn ensure_two_p_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
  done: fn(Result(TwoPSet, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use set <- result.map(create_two_p_set(document))
      set_two_p_set_field(typed_map, field, set)
    },
    fn() { resolve_two_p_set_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a directory exists under `field`, seeding one if absent.
pub fn ensure_directory(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
  done: fn(Result(SharedDirectory, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use dir <- result.map(create_directory(document))
      set_directory_field(typed_map, field, dir)
    },
    fn() { resolve_directory_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Ensure a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document,
  typed_map: TypedMap(s),
  field: ChildField(s, c),
  done: fn(Result(TypedMap(c), String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.child_key(field),
    fn() {
      use child <- result.map(create_map(document))
      set_child(typed_map, field, typed(child))
    },
    fn() { resolve_child(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Set a plain typed field to `default` only if its key is currently absent.
/// Concurrent racers all set; last-writer-wins on the key settles one value.
pub fn ensure_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  default: a,
) -> Nil {
  case has_field(typed_map, field) {
    True -> Nil
    False -> set_field(typed_map, field, default)
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
/// Register `handler` for a channel's events, invoking it only for the events
/// `narrow` accepts — already decoded to the kind's own event type — so a
/// subscriber never sees the 14-variant union. The per-kind `subscribe_*`
/// functions wrap this.
fn subscribe_narrowed(
  runtime: runtime_js.Runtime,
  address: String,
  handler: fn(a) -> Nil,
  narrow: fn(ChannelEvent) -> Option(a),
) -> Nil {
  runtime_js.subscribe(runtime, address, fn(event) {
    case narrow(event) {
      Some(inner) -> handler(inner)
      None -> Nil
    }
  })
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this
/// counter channel. The handler receives `counter_kernel.CounterEvent` —
/// counter events only.
pub fn subscribe_counter(
  counter: SharedCounter,
  handler: fn(counter_kernel.CounterEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(counter.runtime, counter.address, handler)
  case event {
    channel.CounterEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── OR-maps ──────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new OR-map channel in tally or register mode. Same detached
/// lifecycle as `create_map`.
pub fn create_or_map(
  document: Document,
  mode: OrMapMode,
) -> Result(OrMap, String) {
  runtime_js.create_or_map(document.runtime, mode)
  |> result.map(fn(address) {
    OrMap(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn or_map_handle_of(or_map: OrMap) -> Json {
  handle.encode_handle(or_map.address)
}

@target(javascript)
pub fn resolve_or_map(
  document: Document,
  value: Json,
) -> Result(OrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) { OrMap(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
pub fn or_map_increment(or_map: OrMap, key: String, amount: Int) -> Nil {
  runtime_js.or_map_increment(or_map.runtime, or_map.address, key, amount)
}

@target(javascript)
pub fn or_map_set(or_map: OrMap, key: String, value: String) -> Nil {
  runtime_js.or_map_set(or_map.runtime, or_map.address, key, value)
}

@target(javascript)
pub fn or_map_set_json(or_map: OrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(javascript)
pub fn or_map_remove(or_map: OrMap, key: String) -> Nil {
  runtime_js.or_map_remove(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_value(or_map: OrMap, key: String) -> Option(OrMapValue) {
  runtime_js.or_map_value(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_entries(or_map: OrMap) -> List(#(String, OrMapValue)) {
  runtime_js.or_map_entries(or_map.runtime, or_map.address)
}

@target(javascript)
pub fn or_map_keys(or_map: OrMap) -> List(String) {
  runtime_js.or_map_keys(or_map.runtime, or_map.address)
}

@target(javascript)
pub fn subscribe_or_map(
  or_map: OrMap,
  handler: fn(or_map_kernel.OrMapEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(or_map.runtime, or_map.address, handler)
  case event {
    channel.OrMapEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── OR-sets ──────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new observed-remove set channel for string elements.
pub fn create_or_set(document: Document) -> Result(OrSet, String) {
  runtime_js.create_or_set(document.runtime)
  |> result.map(fn(address) {
    OrSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn or_set_handle_of(or_set: OrSet) -> Json {
  handle.encode_handle(or_set.address)
}

@target(javascript)
pub fn resolve_or_set(
  document: Document,
  value: Json,
) -> Result(OrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) { OrSet(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
pub fn or_set_add(or_set: OrSet, element: String) -> Nil {
  runtime_js.or_set_add(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_remove(or_set: OrSet, element: String) -> Nil {
  runtime_js.or_set_remove(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_contains(or_set: OrSet, element: String) -> Bool {
  runtime_js.or_set_contains(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_values(or_set: OrSet) -> List(String) {
  runtime_js.or_set_values(or_set.runtime, or_set.address)
}

@target(javascript)
pub fn subscribe_or_set(
  or_set: OrSet,
  handler: fn(or_set_kernel.OrSetEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(or_set.runtime, or_set.address, handler)
  case event {
    channel.OrSetEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Shared sequences ──────────────────────────────────────────────────────────

@target(javascript)
pub fn create_sequence(document: Document) -> Result(SharedSequence, String) {
  runtime_js.create_sequence(document.runtime)
  |> result.map(fn(address) {
    SharedSequence(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn sequence_handle_of(sequence: SharedSequence) -> Json {
  handle.encode_handle(sequence.address)
}

@target(javascript)
pub fn resolve_sequence(
  document: Document,
  value: Json,
) -> Result(SharedSequence, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_sequence(document.runtime, address)
      |> result.map(fn(_) {
        SharedSequence(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Insert `value` at zero-based `index`, from `0` through the sequence length.
pub fn sequence_insert(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  runtime_js.sequence_insert(sequence.runtime, sequence.address, index, value)
}

@target(javascript)
/// Delete the value at a zero-based `index`, from `0` through `length - 1`.
pub fn sequence_delete(
  sequence: SharedSequence,
  index: Int,
) -> Result(Nil, String) {
  runtime_js.sequence_delete(sequence.runtime, sequence.address, index)
}

@target(javascript)
/// Move a value between zero-based indexes; the destination is evaluated after
/// removing the source value.
pub fn sequence_move(
  sequence: SharedSequence,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String) {
  runtime_js.sequence_move(
    sequence.runtime,
    sequence.address,
    from_index,
    to_index,
  )
}

@target(javascript)
/// Replace the value at a zero-based `index` as one collaborative operation.
pub fn sequence_replace(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  runtime_js.sequence_replace(sequence.runtime, sequence.address, index, value)
}

@target(javascript)
pub fn sequence_values(sequence: SharedSequence) -> List(Json) {
  runtime_js.sequence_values(sequence.runtime, sequence.address)
}

@target(javascript)
pub fn sequence_length(sequence: SharedSequence) -> Int {
  runtime_js.sequence_length(sequence.runtime, sequence.address)
}

@target(javascript)
pub fn subscribe_sequence(
  sequence: SharedSequence,
  handler: fn(sequence_kernel.SequenceEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(sequence.runtime, sequence.address, handler)
  case event {
    channel.SequenceEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Shared text ───────────────────────────────────────────────────────────────

@target(javascript)
pub fn create_text(document: Document) -> Result(SharedText, String) {
  runtime_js.create_text(document.runtime)
  |> result.map(fn(address) {
    SharedText(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn text_handle_of(text: SharedText) -> Json {
  handle.encode_handle(text.address)
}

@target(javascript)
pub fn resolve_text(
  document: Document,
  value: Json,
) -> Result(SharedText, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_text(document.runtime, address)
      |> result.map(fn(_) {
        SharedText(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Insert `value` at the optimistic grapheme `index`, from `0` through the
/// text length. An empty `value` at a valid index is a no-op.
pub fn text_insert(
  text: SharedText,
  index: Int,
  value: String,
) -> Result(Nil, String) {
  runtime_js.text_insert(text.runtime, text.address, index, value)
}

@target(javascript)
/// Delete the graphemes in `[start, end)`. An empty range at valid bounds is
/// a no-op.
pub fn text_delete_range(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(Nil, String) {
  runtime_js.text_delete_range(text.runtime, text.address, start, end)
}

@target(javascript)
/// Replace the graphemes in `[start, end)` with `value` as one collaborative
/// operation. Only an empty range replaced with `""` is a no-op.
pub fn text_replace_range(
  text: SharedText,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String) {
  runtime_js.text_replace_range(text.runtime, text.address, start, end, value)
}

@target(javascript)
/// Insert `value` at the end of the text. An empty `value` is a no-op.
pub fn text_append(text: SharedText, value: String) -> Result(Nil, String) {
  runtime_js.text_append(text.runtime, text.address, value)
}

@target(javascript)
/// The text's current optimistic visible string.
pub fn text_value(text: SharedText) -> String {
  runtime_js.text_value(text.runtime, text.address)
}

@target(javascript)
/// The text's current optimistic grapheme count.
pub fn text_length(text: SharedText) -> Int {
  runtime_js.text_length(text.runtime, text.address)
}

@target(javascript)
/// The graphemes in `[start, end)` of the text's optimistic string. An
/// explicit error string when `start..end` is invalid.
pub fn text_substring(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(String, String) {
  runtime_js.text_substring(text.runtime, text.address, start, end)
}

@target(javascript)
/// Create a stable anchor at the gap before the optimistic grapheme at
/// `index`, biased with `bias_before`/`bias_after`. An explicit error string
/// on an out-of-bounds index.
pub fn text_anchor_at(
  text: SharedText,
  index: Int,
  bias: Bias,
) -> Result(TextAnchor, String) {
  runtime_js.text_anchor_at(text.runtime, text.address, index, bias)
}

@target(javascript)
/// Resolve an anchor to a current optimistic grapheme index. An explicit
/// error string on a stale/unknown anchor target.
pub fn text_resolve_anchor(
  text: SharedText,
  anchor: TextAnchor,
) -> Result(Int, String) {
  runtime_js.text_resolve_anchor(text.runtime, text.address, anchor)
}

@target(javascript)
/// An anchor at the start of the text. Always resolves to 0. Pure — doesn't
/// need a `SharedText` since it carries no document state.
pub fn text_start_anchor() -> TextAnchor {
  runtime_js.text_start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. Always resolves to the current grapheme
/// length, tracking growth. Pure, like `text_start_anchor`.
pub fn text_end_anchor() -> TextAnchor {
  runtime_js.text_end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value, for example to travel
/// through presence for shared cursors.
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  runtime_js.text_anchor_to_json(anchor)
}

@target(javascript)
/// Decode an anchor from a JSON string produced by `text_anchor_to_json`. An
/// explicit error string on malformed JSON.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(TextAnchor, String) {
  runtime_js.text_anchor_from_json(json_string)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this
/// text channel. The handler receives `text_kernel.TextEvent` — text events
/// only.
pub fn subscribe_text(
  text: SharedText,
  handler: fn(text_kernel.TextEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(text.runtime, text.address, handler)
  case event {
    channel.TextEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Register collections ─────────────────────────────────────────────────────

@target(javascript)
pub fn create_register_collection(
  document: Document,
) -> Result(RegisterCollection, String) {
  runtime_js.create_register_collection(document.runtime)
  |> result.map(fn(address) {
    RegisterCollection(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn register_collection_handle_of(collection: RegisterCollection) -> Json {
  handle.encode_handle(collection.address)
}

@target(javascript)
pub fn resolve_register_collection(
  document: Document,
  value: Json,
) -> Result(RegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        RegisterCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn register_write(
  collection: RegisterCollection,
  key: String,
  value: Json,
) -> Nil {
  runtime_js.register_write(collection.runtime, collection.address, key, value)
}

@target(javascript)
pub fn register_read(
  collection: RegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  runtime_js.register_read(collection.runtime, collection.address, key, policy)
}

@target(javascript)
pub fn register_get(
  collection: RegisterCollection,
  key: String,
) -> Option(Json) {
  register_read(collection, key, Atomic)
}

@target(javascript)
pub fn register_versions(
  collection: RegisterCollection,
  key: String,
) -> Option(List(Json)) {
  runtime_js.register_versions(collection.runtime, collection.address, key)
}

@target(javascript)
pub fn register_keys(collection: RegisterCollection) -> List(String) {
  runtime_js.register_keys(collection.runtime, collection.address)
}

@target(javascript)
pub fn subscribe_register_collection(
  collection: RegisterCollection,
  handler: fn(register_collection_kernel.RegisterEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(
    collection.runtime,
    collection.address,
    handler,
  )
  case event {
    channel.RegisterCollectionEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Claims ───────────────────────────────────────────────────────────────────

@target(javascript)
pub fn create_claims(document: Document) -> Result(Claims, String) {
  runtime_js.create_claims(document.runtime)
  |> result.map(fn(address) {
    Claims(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn claims_handle_of(claims: Claims) -> Json {
  handle.encode_handle(claims.address)
}

@target(javascript)
pub fn resolve_claims(
  document: Document,
  value: Json,
) -> Result(Claims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        Claims(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn try_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime_js.ClaimSubmitReply {
  runtime_js.try_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn compare_and_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime_js.ClaimSubmitReply {
  runtime_js.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn get_claim(claims: Claims, key: String) -> Option(Json) {
  runtime_js.get_claim(claims.runtime, claims.address, key)
}

@target(javascript)
pub fn has_claim(claims: Claims, key: String) -> Bool {
  runtime_js.has_claim(claims.runtime, claims.address, key)
}

@target(javascript)
pub fn subscribe_claims(
  claims: Claims,
  handler: fn(claims_kernel.ClaimEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(claims.runtime, claims.address, handler)
  case event {
    channel.ClaimsEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Task managers ─────────────────────────────────────────────────────────────

@target(javascript)
pub fn create_task_manager(document: Document) -> Result(TaskManager, String) {
  runtime_js.create_task_manager(document.runtime)
  |> result.map(fn(address) {
    TaskManager(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn task_manager_handle_of(manager: TaskManager) -> Json {
  handle.encode_handle(manager.address)
}

@target(javascript)
pub fn resolve_task_manager(
  document: Document,
  value: Json,
) -> Result(TaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        TaskManager(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn volunteer_for_task(
  manager: TaskManager,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  runtime_js.task_manager_volunteer(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn abandon_task(manager: TaskManager, task_id: String) -> Nil {
  runtime_js.task_manager_abandon(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn complete_task(
  manager: TaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime_js.task_manager_complete(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_assigned(manager: TaskManager, task_id: String) -> Bool {
  runtime_js.task_manager_assigned(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queued(manager: TaskManager, task_id: String) -> Bool {
  runtime_js.task_manager_queued(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queues(manager: TaskManager) -> List(#(String, List(Int))) {
  runtime_js.task_manager_queues(manager.runtime, manager.address)
}

@target(javascript)
pub fn subscribe_task_manager(
  manager: TaskManager,
  handler: fn(task_manager_kernel.TaskManagerEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(manager.runtime, manager.address, handler)
  case event {
    channel.TaskManagerEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── PN-counters ──────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new PN-counter channel. Same detached lifecycle as `create_map`.
pub fn create_pn_counter(document: Document) -> Result(PnCounter, String) {
  runtime_js.create_pn_counter(document.runtime)
  |> result.map(fn(address) {
    PnCounter(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn pn_counter_handle_of(pn_counter: PnCounter) -> Json {
  handle.encode_handle(pn_counter.address)
}

@target(javascript)
pub fn resolve_pn_counter(
  document: Document,
  value: Json,
) -> Result(PnCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        PnCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Optimistically add `amount` (negative amounts decrement).
pub fn pn_counter_update(pn_counter: PnCounter, amount: Int) -> Nil {
  runtime_js.pn_counter_update(pn_counter.runtime, pn_counter.address, amount)
}

@target(javascript)
/// The counter's current optimistic value, `None` when the address is not a
/// PN-counter channel.
pub fn pn_counter_value(pn_counter: PnCounter) -> Option(Int) {
  runtime_js.pn_counter_value(pn_counter.runtime, pn_counter.address)
}

// ── PactMaps ─────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new PactMap channel. Same detached lifecycle as `create_map`.
pub fn create_pact_map(document: Document) -> Result(PactMap, String) {
  runtime_js.create_pact_map(document.runtime)
  |> result.map(fn(address) {
    PactMap(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn pact_map_handle_of(pact_map: PactMap) -> Json {
  handle.encode_handle(pact_map.address)
}

@target(javascript)
pub fn resolve_pact_map(
  document: Document,
  value: Json,
) -> Result(PactMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        PactMap(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Propose `value` for `key`. Consensus, not optimistic: the value is `pending`
/// until server sequencing accepts it.
pub fn pact_map_set(pact_map: PactMap, key: String, value: Json) -> Nil {
  runtime_js.pact_map_set(pact_map.runtime, pact_map.address, key, value)
}

@target(javascript)
/// Propose a delete (tombstone) for `key`.
pub fn pact_map_delete(pact_map: PactMap, key: String) -> Nil {
  runtime_js.pact_map_delete(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// The accepted value for `key`, `None` when pending, absent, or not a PactMap
/// channel.
pub fn pact_map_get(pact_map: PactMap, key: String) -> Option(Json) {
  runtime_js.pact_map_get(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// All keys with an accepted or pending pact.
pub fn pact_map_keys(pact_map: PactMap) -> List(String) {
  runtime_js.pact_map_keys(pact_map.runtime, pact_map.address)
}

@target(javascript)
/// Whether `key` currently has an unsettled (pending) proposal.
pub fn pact_map_is_pending(pact_map: PactMap, key: String) -> Bool {
  runtime_js.pact_map_is_pending(pact_map.runtime, pact_map.address, key)
}

// ── Ordered collections ──────────────────────────────────────────────────────

@target(javascript)
/// Create a new ConsensusOrderedCollection channel. Same detached lifecycle as
/// `create_map`.
pub fn create_ordered_collection(
  document: Document,
) -> Result(OrderedCollection, String) {
  runtime_js.create_ordered_collection(document.runtime)
  |> result.map(fn(address) {
    OrderedCollection(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn ordered_collection_handle_of(collection: OrderedCollection) -> Json {
  handle.encode_handle(collection.address)
}

@target(javascript)
pub fn resolve_ordered_collection(
  document: Document,
  value: Json,
) -> Result(OrderedCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        OrderedCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Enqueue `value` at the tail of the collection.
pub fn ordered_add(collection: OrderedCollection, value: Json) -> Nil {
  runtime_js.ordered_add(collection.runtime, collection.address, value)
}

@target(javascript)
/// Acquire (lease) the head item, returning the acquire id used to `complete`
/// or `release` it.
pub fn ordered_acquire(collection: OrderedCollection) -> String {
  runtime_js.ordered_acquire(collection.runtime, collection.address)
}

@target(javascript)
/// Complete an acquired item, removing it permanently.
pub fn ordered_complete(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  runtime_js.ordered_complete(
    collection.runtime,
    collection.address,
    acquire_id,
  )
}

@target(javascript)
/// Release an acquired item back to the collection for another consumer.
pub fn ordered_release(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  runtime_js.ordered_release(collection.runtime, collection.address, acquire_id)
}

@target(javascript)
/// The number of items currently in the collection, `None` when the address is
/// not an ordered-collection channel.
pub fn ordered_size(collection: OrderedCollection) -> Option(Int) {
  runtime_js.ordered_size(collection.runtime, collection.address)
}

// ── JSON-OT (json0) ──────────────────────────────────────────────────────────

@target(javascript)
/// Create a new json0 channel. Same detached lifecycle as `create_map`:
/// local-only until its handle (`json_ot_handle_of`) is stored into an attached
/// container.
pub fn create_json_ot(document: Document) -> Result(JsonOt, String) {
  runtime_js.create_json_ot(document.runtime)
  |> result.map(fn(address) {
    JsonOt(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `json_ot`, suitable for storing as a
/// value in a map (see `handle_of`).
pub fn json_ot_handle_of(json_ot: JsonOt) -> Json {
  handle.encode_handle(json_ot.address)
}

@target(javascript)
/// Resolve a handle value to the JsonOt it references. Errors are retryable,
/// as with `resolve`.
pub fn resolve_json_ot(
  document: Document,
  value: Json,
) -> Result(JsonOt, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        JsonOt(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Optimistically submit a json0 op (a list of components) to the channel.
pub fn submit_json_ot(json_ot: JsonOt, op: json_ot.Op) -> Nil {
  runtime_js.submit_json_ot(json_ot.runtime, json_ot.address, op)
}

@target(javascript)
/// The json0 channel's current optimistic document, `None` when the address is
/// not a json0 channel.
pub fn json_ot_view(json_ot: JsonOt) -> Option(json_ot.JsonValue) {
  runtime_js.json_ot_view(json_ot.runtime, json_ot.address)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this json0
/// channel.
pub fn subscribe_json_ot(
  json_ot: JsonOt,
  handler: fn(json_ot_kernel.JsonOtEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(json_ot.runtime, json_ot.address, handler)
  case event {
    channel.JsonOtEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Grow-only sets (G-Set) ───────────────────────────────────────────────────

@target(javascript)
/// Create a new grow-only set channel. Same detached lifecycle as `create_map`:
/// local-only until its handle (`g_set_handle_of`) is stored into an attached
/// container.
pub fn create_g_set(document: Document) -> Result(GSet, String) {
  runtime_js.create_g_set(document.runtime)
  |> result.map(fn(address) {
    GSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn g_set_handle_of(set: GSet) -> Json {
  handle.encode_handle(set.address)
}

@target(javascript)
/// Resolve a handle value to the GSet it references. Errors are retryable, as
/// with `resolve`.
pub fn resolve_g_set(document: Document, value: Json) -> Result(GSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) { GSet(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
/// Optimistically add `element` to the set.
pub fn g_set_add(set: GSet, element: String) -> Nil {
  runtime_js.g_set_add(set.runtime, set.address, element)
}

@target(javascript)
/// Whether `element` is present in the set's current optimistic state.
pub fn g_set_contains(set: GSet, element: String) -> Bool {
  runtime_js.g_set_contains(set.runtime, set.address, element)
}

@target(javascript)
/// The set's current optimistic members.
pub fn g_set_values(set: GSet) -> List(String) {
  runtime_js.g_set_values(set.runtime, set.address)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this set.
pub fn subscribe_g_set(
  set: GSet,
  handler: fn(g_set_kernel.GSetEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(set.runtime, set.address, handler)
  case event {
    channel.GSetEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Two-phase sets (2P-Set) ──────────────────────────────────────────────────

@target(javascript)
/// Create a new two-phase set channel. Same detached lifecycle as `create_map`:
/// local-only until its handle (`two_p_set_handle_of`) is stored into an
/// attached map. A remove is a permanent tombstone: remove wins over a
/// concurrent (re-)add.
pub fn create_two_p_set(document: Document) -> Result(TwoPSet, String) {
  runtime_js.create_two_p_set(document.runtime)
  |> result.map(fn(address) {
    TwoPSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn two_p_set_handle_of(set: TwoPSet) -> Json {
  handle.encode_handle(set.address)
}

@target(javascript)
/// Resolve a handle value to the TwoPSet it references. Errors are retryable,
/// as with `resolve`.
pub fn resolve_two_p_set(
  document: Document,
  value: Json,
) -> Result(TwoPSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        TwoPSet(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Optimistically add `element` to the set. Adding a previously removed element
/// records the add but never reactivates it.
pub fn two_p_set_add(set: TwoPSet, element: String) -> Nil {
  runtime_js.two_p_set_add(set.runtime, set.address, element)
}

@target(javascript)
/// Optimistically remove `element` from the set. Removal is a permanent
/// tombstone.
pub fn two_p_set_remove(set: TwoPSet, element: String) -> Nil {
  runtime_js.two_p_set_remove(set.runtime, set.address, element)
}

@target(javascript)
/// Whether `element` is present in the set's current optimistic state.
pub fn two_p_set_contains(set: TwoPSet, element: String) -> Bool {
  runtime_js.two_p_set_contains(set.runtime, set.address, element)
}

@target(javascript)
/// The set's current optimistic members.
pub fn two_p_set_values(set: TwoPSet) -> List(String) {
  runtime_js.two_p_set_values(set.runtime, set.address)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this set.
pub fn subscribe_two_p_set(
  set: TwoPSet,
  handler: fn(two_p_set_kernel.TwoPSetEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(set.runtime, set.address, handler)
  case event {
    channel.TwoPSetEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Directories (hierarchical maps) ──────────────────────────────────────────

@target(javascript)
/// Create a new directory channel: a hierarchical map keyed by absolute paths
/// (the root is `"/"`). Same detached lifecycle as `create_map`: local-only
/// until its handle (`directory_handle_of`) is stored into an attached map.
pub fn create_directory(document: Document) -> Result(SharedDirectory, String) {
  runtime_js.create_directory(document.runtime)
  |> result.map(fn(address) {
    SharedDirectory(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker referencing `dir`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn directory_handle_of(dir: SharedDirectory) -> Json {
  handle.encode_handle(dir.address)
}

@target(javascript)
/// Resolve a handle value to the SharedDirectory it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_directory(
  document: Document,
  value: Json,
) -> Result(SharedDirectory, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedDirectory(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Optimistically set `key` to `value` in the subdirectory at `path` (root is
/// `"/"`).
pub fn directory_set(
  dir: SharedDirectory,
  path: String,
  key: String,
  value: Json,
) -> Nil {
  runtime_js.directory_set(dir.runtime, dir.address, path, key, value)
}

@target(javascript)
/// Optimistically remove `key` from the subdirectory at `path`.
pub fn directory_delete(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Nil {
  runtime_js.directory_delete(dir.runtime, dir.address, path, key)
}

@target(javascript)
/// Optimistically remove every key from the subdirectory at `path`.
pub fn directory_clear(dir: SharedDirectory, path: String) -> Nil {
  runtime_js.directory_clear(dir.runtime, dir.address, path)
}

@target(javascript)
/// Optimistically create a subdirectory named `name` under `path`.
pub fn directory_create_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  runtime_js.directory_create_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// Optimistically delete the subdirectory named `name` under `path` (and all
/// of its contents).
pub fn directory_delete_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  runtime_js.directory_delete_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// The current optimistic value at `key` in the subdirectory at `path`, `None`
/// when absent.
pub fn directory_get(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Option(Json) {
  runtime_js.directory_get(dir.runtime, dir.address, path, key)
}

@target(javascript)
/// The current optimistic `#(key, value)` entries in the subdirectory at
/// `path`.
pub fn directory_entries(
  dir: SharedDirectory,
  path: String,
) -> List(#(String, Json)) {
  runtime_js.directory_entries(dir.runtime, dir.address, path)
}

@target(javascript)
/// The names of the immediate subdirectories under `path`.
pub fn directory_subdirectories(
  dir: SharedDirectory,
  path: String,
) -> List(String) {
  runtime_js.directory_subdirectories(dir.runtime, dir.address, path)
}

@target(javascript)
/// Whether a subdirectory named `name` exists under `path`.
pub fn directory_has_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Bool {
  runtime_js.directory_has_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// Register a callback invoked for every local and remote change to this
/// directory.
pub fn subscribe_directory(
  dir: SharedDirectory,
  handler: fn(directory_kernel.DirectoryEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(dir.runtime, dir.address, handler)
  case event {
    channel.DirectoryEvent(inner) -> Some(inner)
    _ -> None
  }
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
/// An inbound ephemeral ripple. Ripples are document-scoped, non-sequenced,
/// and non-persisted — ideal for transient presence (cursors, selection,
/// typing indicators) that must NOT live in a DDS.
pub type Ripple =
  SignalMessage

@target(javascript)
/// Broadcast an ephemeral ripple to every other connected client: a `type`
/// tag plus arbitrary JSON `content`. Fire-and-forget — no ordering, ack, or
/// catch-up. No-op until the first handshake assigns a client id.
pub fn submit_ripple(
  document: Document,
  ripple_type ripple_type: String,
  content content: Json,
) -> Nil {
  runtime_js.send_ripple(document.runtime, ripple_type, content)
}

@target(javascript)
/// Register a callback invoked for every inbound ripple on the document.
pub fn subscribe_ripples(
  document: Document,
  handler: fn(Ripple) -> Nil,
) -> Nil {
  runtime_js.subscribe_ripples(document.runtime, handler)
}

@target(javascript)
/// The ripple's `type` tag, if present.
pub fn ripple_type(ripple: Ripple) -> Option(String) {
  ripple.signal_type
}

@target(javascript)
/// The ripple's JSON payload, left as `Dynamic` for the caller to decode.
pub fn ripple_content(ripple: Ripple) -> Dynamic {
  ripple.content
}

@target(javascript)
/// The sending client's id, if the server stamped one (`None` for
/// server-originated ripples).
pub fn ripple_client_id(ripple: Ripple) -> Option(String) {
  ripple.client_id
}

@target(javascript)
/// Whether the document is fully caught up: every local edit has been
/// acknowledged by the server, so the confirmed state is complete and stable.
/// Useful to wait for quiescence before summarizing.
pub fn is_synced(document: Document) -> Bool {
  runtime_js.is_synced(document.runtime)
}

@target(javascript)
/// Snapshot the document runtime's connection and sequencing state.
pub fn diagnostics(document: Document) -> Diagnostics {
  runtime_js.diagnostics(document.runtime)
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
/// channel. The handler receives `map_kernel.MapEvent` — map events only.
pub fn subscribe(
  map: SharedMap,
  handler: fn(map_kernel.MapEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(map.runtime, map.address, handler)
  case event {
    channel.MapEvent(inner) -> Some(inner)
    _ -> None
  }
}

@target(javascript)
/// Subscribe to a typed map's whole-map events without dropping to the untyped
/// API. Like `subscribe`, `handler` receives narrowed `map_kernel.MapEvent`s;
/// use `subscribe_field` instead to watch a single typed field.
pub fn subscribe_typed(
  typed_map: TypedMap(s),
  handler: fn(map_kernel.MapEvent) -> Nil,
) -> Nil {
  subscribe(typed_map.map, handler)
}

@target(javascript)
/// Map a fanned-out channel event to a typed change for `field` (under `key`),
/// or `None` when the event is for another key or channel kind.
fn field_change(
  field: Field(s, a),
  key: String,
  event: ChannelEvent,
) -> Option(FieldChange(a)) {
  case event {
    channel.MapEvent(map_kernel.ValueChanged(k, previous, value, local))
      if k == key
    ->
      Some(schema.FieldChange(
        value: schema.decode_optional(field, value),
        previous: schema.decode_optional(field, previous),
        local: local,
      ))
    channel.MapEvent(map_kernel.Cleared(local)) ->
      Some(schema.FieldChange(Ok(None), Ok(None), local))
    _ -> None
  }
}

@target(javascript)
/// Subscribe to changes of a single typed field. Each local or remote write to
/// `field`'s key invokes `handler` with a `FieldChange` carrying the new and
/// previous values decoded at the boundary — `Error(Invalid)` when a peer wrote
/// a value that does not match the field type. A `Cleared` on the map fans out
/// as `FieldChange(Ok(None), Ok(None), local)`; clears carry no per-key
/// previous.
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  handler: fn(FieldChange(a)) -> Nil,
) -> Nil {
  let key = schema.field_key(field)
  runtime_js.subscribe(typed_map.map.runtime, typed_map.map.address, fn(event) {
    case field_change(field, key, event) {
      Some(change) -> handler(change)
      None -> Nil
    }
  })
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
