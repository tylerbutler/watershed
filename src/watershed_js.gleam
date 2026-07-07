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
import spillway/message.{type SignalMessage, ConnectMessage}
@target(javascript)
import spillway/types.{
  Client, ClientCapabilities, ClientDetails, User, WriteMode,
}

@target(javascript)
import gleam/result

@target(javascript)
import watershed/channel.{type ChannelEvent}
@target(javascript)
import watershed/claims_kernel
@target(javascript)
import watershed/counter_kernel
@target(javascript)
import watershed/git_storage.{type SummaryVersion}
@target(javascript)
import watershed/handle
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
import watershed/task_manager_kernel
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
pub opaque type SharedOrSet {
  SharedOrSet(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedRegisterCollection {
  SharedRegisterCollection(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedClaims {
  SharedClaims(runtime: runtime_js.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedTaskManager {
  SharedTaskManager(runtime: runtime_js.Runtime, address: String)
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
  or_map: SharedOrMap,
) -> Nil {
  put_channel_field(typed_map, field, or_map_handle_of(or_map))
}

@target(javascript)
/// Resolve the OR-map referenced by a typed channel field.
pub fn resolve_or_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
) -> Result(Option(SharedOrMap), String) {
  get_channel_field(document, typed_map, field, resolve_or_map)
}

@target(javascript)
/// Store a handle to `or_set` under a typed channel field.
pub fn set_or_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  or_set: SharedOrSet,
) -> Nil {
  put_channel_field(typed_map, field, or_set_handle_of(or_set))
}

@target(javascript)
/// Resolve the OR-set referenced by a typed channel field.
pub fn resolve_or_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
) -> Result(Option(SharedOrSet), String) {
  get_channel_field(document, typed_map, field, resolve_or_set)
}

@target(javascript)
/// Store a handle to `collection` under a typed channel field.
pub fn set_register_collection_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  collection: SharedRegisterCollection,
) -> Nil {
  put_channel_field(typed_map, field, register_collection_handle_of(collection))
}

@target(javascript)
/// Resolve the register collection referenced by a typed channel field.
pub fn resolve_register_collection_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
) -> Result(Option(SharedRegisterCollection), String) {
  get_channel_field(document, typed_map, field, resolve_register_collection)
}

@target(javascript)
/// Store a handle to `claims` under a typed channel field.
pub fn set_claims_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  claims: SharedClaims,
) -> Nil {
  put_channel_field(typed_map, field, claims_handle_of(claims))
}

@target(javascript)
/// Resolve the claims channel referenced by a typed channel field.
pub fn resolve_claims_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
) -> Result(Option(SharedClaims), String) {
  get_channel_field(document, typed_map, field, resolve_claims)
}

@target(javascript)
/// Store a handle to `manager` under a typed channel field.
pub fn set_task_manager_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  manager: SharedTaskManager,
) -> Nil {
  put_channel_field(typed_map, field, task_manager_handle_of(manager))
}

@target(javascript)
/// Resolve the task manager referenced by a typed channel field.
pub fn resolve_task_manager_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
) -> Result(Option(SharedTaskManager), String) {
  get_channel_field(document, typed_map, field, resolve_task_manager)
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
pub fn create_or_set(document: Document) -> Result(SharedOrSet, String) {
  runtime_js.create_or_set(document.runtime)
  |> result.map(fn(address) {
    SharedOrSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn or_set_handle_of(or_set: SharedOrSet) -> Json {
  handle.encode_handle(or_set.address)
}

@target(javascript)
pub fn resolve_or_set(
  document: Document,
  value: Json,
) -> Result(SharedOrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedOrSet(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn or_set_add(or_set: SharedOrSet, element: String) -> Nil {
  runtime_js.or_set_add(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_remove(or_set: SharedOrSet, element: String) -> Nil {
  runtime_js.or_set_remove(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_contains(or_set: SharedOrSet, element: String) -> Bool {
  runtime_js.or_set_contains(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_values(or_set: SharedOrSet) -> List(String) {
  runtime_js.or_set_values(or_set.runtime, or_set.address)
}

@target(javascript)
pub fn subscribe_or_set(
  or_set: SharedOrSet,
  handler: fn(or_set_kernel.OrSetEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(or_set.runtime, or_set.address, handler)
  case event {
    channel.OrSetEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Register collections ─────────────────────────────────────────────────────

@target(javascript)
pub fn create_register_collection(
  document: Document,
) -> Result(SharedRegisterCollection, String) {
  runtime_js.create_register_collection(document.runtime)
  |> result.map(fn(address) {
    SharedRegisterCollection(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn register_collection_handle_of(
  collection: SharedRegisterCollection,
) -> Json {
  handle.encode_handle(collection.address)
}

@target(javascript)
pub fn resolve_register_collection(
  document: Document,
  value: Json,
) -> Result(SharedRegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedRegisterCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn register_write(
  collection: SharedRegisterCollection,
  key: String,
  value: Json,
) -> Nil {
  runtime_js.register_write(collection.runtime, collection.address, key, value)
}

@target(javascript)
pub fn register_read(
  collection: SharedRegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  runtime_js.register_read(collection.runtime, collection.address, key, policy)
}

@target(javascript)
pub fn register_get(
  collection: SharedRegisterCollection,
  key: String,
) -> Option(Json) {
  register_read(collection, key, Atomic)
}

@target(javascript)
pub fn register_versions(
  collection: SharedRegisterCollection,
  key: String,
) -> Option(List(Json)) {
  runtime_js.register_versions(collection.runtime, collection.address, key)
}

@target(javascript)
pub fn register_keys(collection: SharedRegisterCollection) -> List(String) {
  runtime_js.register_keys(collection.runtime, collection.address)
}

@target(javascript)
pub fn subscribe_register_collection(
  collection: SharedRegisterCollection,
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
pub fn create_claims(document: Document) -> Result(SharedClaims, String) {
  runtime_js.create_claims(document.runtime)
  |> result.map(fn(address) {
    SharedClaims(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn claims_handle_of(claims: SharedClaims) -> Json {
  handle.encode_handle(claims.address)
}

@target(javascript)
pub fn resolve_claims(
  document: Document,
  value: Json,
) -> Result(SharedClaims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedClaims(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn try_set_claim(
  claims: SharedClaims,
  key: String,
  value: Json,
) -> runtime_js.ClaimSubmitReply {
  runtime_js.try_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn compare_and_set_claim(
  claims: SharedClaims,
  key: String,
  value: Json,
) -> runtime_js.ClaimSubmitReply {
  runtime_js.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn get_claim(claims: SharedClaims, key: String) -> Option(Json) {
  runtime_js.get_claim(claims.runtime, claims.address, key)
}

@target(javascript)
pub fn has_claim(claims: SharedClaims, key: String) -> Bool {
  runtime_js.has_claim(claims.runtime, claims.address, key)
}

@target(javascript)
pub fn subscribe_claims(
  claims: SharedClaims,
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
pub fn create_task_manager(
  document: Document,
) -> Result(SharedTaskManager, String) {
  runtime_js.create_task_manager(document.runtime)
  |> result.map(fn(address) {
    SharedTaskManager(runtime: document.runtime, address: address)
  })
}

@target(javascript)
pub fn task_manager_handle_of(manager: SharedTaskManager) -> Json {
  handle.encode_handle(manager.address)
}

@target(javascript)
pub fn resolve_task_manager(
  document: Document,
  value: Json,
) -> Result(SharedTaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_js.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedTaskManager(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
pub fn volunteer_for_task(
  manager: SharedTaskManager,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  runtime_js.task_manager_volunteer(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn abandon_task(manager: SharedTaskManager, task_id: String) -> Nil {
  runtime_js.task_manager_abandon(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn complete_task(
  manager: SharedTaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime_js.task_manager_complete(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_assigned(manager: SharedTaskManager, task_id: String) -> Bool {
  runtime_js.task_manager_assigned(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queued(manager: SharedTaskManager, task_id: String) -> Bool {
  runtime_js.task_manager_queued(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queues(manager: SharedTaskManager) -> List(#(String, List(Int))) {
  runtime_js.task_manager_queues(manager.runtime, manager.address)
}

@target(javascript)
pub fn subscribe_task_manager(
  manager: SharedTaskManager,
  handler: fn(task_manager_kernel.TaskManagerEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(manager.runtime, manager.address, handler)
  case event {
    channel.TaskManagerEvent(inner) -> Some(inner)
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
/// An inbound ephemeral signal. Signals are document-scoped, non-sequenced,
/// and non-persisted — ideal for transient presence (cursors, selection,
/// typing indicators) that must NOT live in a DDS.
pub type Signal =
  SignalMessage

@target(javascript)
/// Broadcast an ephemeral signal to every other connected client: a `type`
/// tag plus arbitrary JSON `content`. Fire-and-forget — no ordering, ack, or
/// catch-up. No-op until the first handshake assigns a client id.
pub fn submit_signal(
  document: Document,
  signal_type signal_type: String,
  content content: Json,
) -> Nil {
  runtime_js.send_signal(document.runtime, signal_type, content)
}

@target(javascript)
/// Register a callback invoked for every inbound signal on the document.
pub fn subscribe_signals(
  document: Document,
  handler: fn(Signal) -> Nil,
) -> Nil {
  runtime_js.subscribe_signals(document.runtime, handler)
}

@target(javascript)
/// The signal's `type` tag, if present.
pub fn signal_type(signal: Signal) -> Option(String) {
  signal.signal_type
}

@target(javascript)
/// The signal's JSON payload, left as `Dynamic` for the caller to decode.
pub fn signal_content(signal: Signal) -> Dynamic {
  signal.content
}

@target(javascript)
/// The sending client's id, if the server stamped one (`None` for
/// server-originated signals).
pub fn signal_client_id(signal: Signal) -> Option(String) {
  signal.client_id
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
