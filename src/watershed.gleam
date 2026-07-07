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
import gleam/list
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
import watershed/json_ot
@target(erlang)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(erlang)
import watershed/register_collection_kernel.{type ReadPolicy, Atomic}
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/schema.{type ChildField, type Field, type FieldError}
@target(erlang)
import watershed/task_manager_kernel
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
pub opaque type SharedJsonOt {
  SharedJsonOt(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedOrMap {
  SharedOrMap(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedOrSet {
  SharedOrSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedRegisterCollection {
  SharedRegisterCollection(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedClaims {
  SharedClaims(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedTaskManager {
  SharedTaskManager(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedGSet {
  SharedGSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedTwoPSet {
  SharedTwoPSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedDirectory {
  SharedDirectory(runtime: Subject(runtime.Msg), address: String)
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
// Typed maps
//
// An opt-in, phantom-typed view over a SharedMap. `schema` is pinned by
// inference the first time a `Field(schema, _)` is used against the map, so a
// field from one schema cannot be applied to a map of another. Typing is a
// decode boundary (remote peers may write anything), so reads return `Result`.
// See `watershed/schema` for defining fields.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// A SharedMap viewed through a schema `s`.
pub opaque type TypedMap(s) {
  TypedMap(map: SharedMap)
}

@target(erlang)
/// View a raw map through a schema. The schema is chosen by how the result is
/// used (or by annotation): `let players: TypedMap(Roster) = typed(map)`.
pub fn typed(map: SharedMap) -> TypedMap(s) {
  TypedMap(map: map)
}

@target(erlang)
/// The underlying raw map, for dropping back to the untyped API.
pub fn untyped(typed_map: TypedMap(s)) -> SharedMap {
  typed_map.map
}

@target(erlang)
/// The document's root map, viewed through a schema.
pub fn root_typed(document: Document) -> TypedMap(s) {
  typed(root(document))
}

@target(erlang)
/// Create a new (detached) map, viewed through a schema. Same lifecycle as
/// `create_map`.
pub fn create_typed_map(document: Document) -> Result(TypedMap(s), String) {
  create_map(document) |> result.map(typed)
}

@target(erlang)
/// Optimistically write a typed field.
pub fn set_field(typed_map: TypedMap(s), field: Field(s, a), value: a) -> Nil {
  set(typed_map.map, schema.field_key(field), schema.encode_value(field, value))
}

@target(erlang)
/// Optimistically delete a typed field.
pub fn delete_field(typed_map: TypedMap(s), field: Field(s, a)) -> Nil {
  delete(typed_map.map, schema.field_key(field))
}

@target(erlang)
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

@target(erlang)
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

@target(erlang)
/// Whether a typed field is present (does not check that it decodes).
pub fn has_field(typed_map: TypedMap(s), field: Field(s, a)) -> Bool {
  has(typed_map.map, schema.field_key(field))
}

@target(erlang)
/// Store a handle to a nested typed map under a child field.
pub fn set_child(
  typed_map: TypedMap(s),
  field: ChildField(s, c),
  child: TypedMap(c),
) -> Nil {
  set(typed_map.map, schema.child_key(field), handle_of(child.map))
}

@target(erlang)
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

@target(erlang)
/// Read the whole map as a typed record through a schema: one `Result`, after
/// the schema's version and seal checks. See `watershed/schema`.
pub fn read(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
) -> Result(record, FieldError) {
  schema.decode_entries(map_schema, entries(typed_map.map))
}

@target(erlang)
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

@target(erlang)
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

@target(erlang)
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
// JSON-OT (json0)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new json0 (JSON-OT) channel. Same detached lifecycle as
/// `create_map`: local-only until its handle (`json_ot_handle_of`) is first
/// stored into an attached map.
pub fn create_json_ot(document: Document) -> Result(SharedJsonOt, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateJsonOt,
  )
  |> result.map(fn(address) {
    SharedJsonOt(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `json_ot`, suitable for storing as a
/// value in a map (see `handle_of`).
pub fn json_ot_handle_of(json_ot: SharedJsonOt) -> Json {
  handle.encode_handle(json_ot.address)
}

@target(erlang)
/// Resolve a handle value to the SharedJsonOt it references. Existence is
/// checked, not channel type. Errors are retryable, as with `resolve`.
pub fn resolve_json_ot(
  document: Document,
  value: Json,
) -> Result(SharedJsonOt, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedJsonOt(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically submit a json0 op (a list of components) to the channel.
pub fn submit_json_ot(json_ot: SharedJsonOt, op: json_ot.Op) -> Nil {
  process.send(json_ot.runtime, runtime.SubmitJsonOt(json_ot.address, op))
}

@target(erlang)
/// The json0 channel's current optimistic document, `None` when the address is
/// not a json0 channel.
pub fn json_ot_view(json_ot: SharedJsonOt) -> Option(json_ot.JsonValue) {
  process.call(json_ot.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetJsonOtView(json_ot.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this json0 channel's events, local and
/// remote alike.
pub fn subscribe_json_ot(json_ot: SharedJsonOt) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(json_ot.runtime, runtime.Subscribe(json_ot.address, subscriber))
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

// ─────────────────────────────────────────────────────────────────────────────
// OR-sets
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new observed-remove set channel for string elements.
pub fn create_or_set(document: Document) -> Result(SharedOrSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateOrSet,
  )
  |> result.map(fn(address) {
    SharedOrSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn or_set_handle_of(or_set: SharedOrSet) -> Json {
  handle.encode_handle(or_set.address)
}

@target(erlang)
pub fn resolve_or_set(
  document: Document,
  value: Json,
) -> Result(SharedOrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedOrSet(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn or_set_add(or_set: SharedOrSet, element: String) -> Nil {
  process.send(or_set.runtime, runtime.AddOrSetElement(or_set.address, element))
}

@target(erlang)
pub fn or_set_remove(or_set: SharedOrSet, element: String) -> Nil {
  process.send(
    or_set.runtime,
    runtime.RemoveOrSetElement(or_set.address, element),
  )
}

@target(erlang)
pub fn or_set_contains(or_set: SharedOrSet, element: String) -> Bool {
  process.call(or_set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.OrSetContains(or_set.address, element, reply)
  })
}

@target(erlang)
pub fn or_set_values(or_set: SharedOrSet) -> List(String) {
  process.call(or_set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrSetValues(or_set.address, reply)
  })
}

@target(erlang)
pub fn subscribe_or_set(or_set: SharedOrSet) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(or_set.runtime, runtime.Subscribe(or_set.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Register collections
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new consensus register collection. Like other non-root channels it
/// starts detached until its handle is stored in an attached map.
pub fn create_register_collection(
  document: Document,
) -> Result(SharedRegisterCollection, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateRegisterCollection,
  )
  |> result.map(fn(address) {
    SharedRegisterCollection(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn register_collection_handle_of(
  collection: SharedRegisterCollection,
) -> Json {
  handle.encode_handle(collection.address)
}

@target(erlang)
pub fn resolve_register_collection(
  document: Document,
  value: Json,
) -> Result(SharedRegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedRegisterCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn register_write(
  collection: SharedRegisterCollection,
  key: String,
  value: Json,
) -> Nil {
  process.send(
    collection.runtime,
    runtime.WriteRegister(collection.address, key, value),
  )
}

@target(erlang)
pub fn register_read(
  collection: SharedRegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterValue(collection.address, key, policy, reply)
  })
}

@target(erlang)
pub fn register_get(
  collection: SharedRegisterCollection,
  key: String,
) -> Option(Json) {
  register_read(collection, key, Atomic)
}

@target(erlang)
pub fn register_versions(
  collection: SharedRegisterCollection,
  key: String,
) -> Option(List(Json)) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterVersions(collection.address, key, reply)
  })
}

@target(erlang)
pub fn register_keys(collection: SharedRegisterCollection) -> List(String) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterKeys(collection.address, reply)
  })
}

@target(erlang)
pub fn subscribe_register_collection(
  collection: SharedRegisterCollection,
) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(
    collection.runtime,
    runtime.Subscribe(collection.address, subscriber),
  )
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_claims(document: Document) -> Result(SharedClaims, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateClaims,
  )
  |> result.map(fn(address) {
    SharedClaims(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn claims_handle_of(claims: SharedClaims) -> Json {
  handle.encode_handle(claims.address)
}

@target(erlang)
pub fn resolve_claims(
  document: Document,
  value: Json,
) -> Result(SharedClaims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedClaims(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn try_set_claim(
  claims: SharedClaims,
  key: String,
  value: Json,
) -> runtime.ClaimSubmitReply {
  runtime.try_set_claim(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn compare_and_set_claim(
  claims: SharedClaims,
  key: String,
  value: Json,
) -> runtime.ClaimSubmitReply {
  runtime.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn get_claim(claims: SharedClaims, key: String) -> Option(Json) {
  runtime.get_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn has_claim(claims: SharedClaims, key: String) -> Bool {
  runtime.has_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn subscribe_claims(claims: SharedClaims) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(claims.runtime, runtime.Subscribe(claims.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Task managers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_task_manager(
  document: Document,
) -> Result(SharedTaskManager, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateTaskManager,
  )
  |> result.map(fn(address) {
    SharedTaskManager(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn task_manager_handle_of(manager: SharedTaskManager) -> Json {
  handle.encode_handle(manager.address)
}

@target(erlang)
pub fn resolve_task_manager(
  document: Document,
  value: Json,
) -> Result(SharedTaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedTaskManager(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn volunteer_for_task(
  manager: SharedTaskManager,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  runtime.volunteer_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn abandon_task(manager: SharedTaskManager, task_id: String) -> Nil {
  runtime.abandon_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn complete_task(
  manager: SharedTaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime.complete_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_assigned(manager: SharedTaskManager, task_id: String) -> Bool {
  runtime.task_assigned(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queued(manager: SharedTaskManager, task_id: String) -> Bool {
  runtime.task_queued(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queues(manager: SharedTaskManager) -> List(#(String, List(Int))) {
  runtime.task_queues(manager.runtime, manager.address)
}

@target(erlang)
pub fn subscribe_task_manager(
  manager: SharedTaskManager,
) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(manager.runtime, runtime.Subscribe(manager.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Grow-only sets (G-Set)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new grow-only set channel. Same detached lifecycle as
/// `create_map`: local-only until its handle (`g_set_handle_of`) is first
/// stored into an attached map. Elements can only be added, never removed;
/// concurrent adds always converge to the union.
pub fn create_g_set(document: Document) -> Result(SharedGSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateGSet,
  )
  |> result.map(fn(address) {
    SharedGSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn g_set_handle_of(set: SharedGSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the SharedGSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_g_set(
  document: Document,
  value: Json,
) -> Result(SharedGSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedGSet(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically add `element` to the set.
pub fn g_set_add(set: SharedGSet, element: String) -> Nil {
  process.send(set.runtime, runtime.AddGSetElement(set.address, element))
}

@target(erlang)
/// Whether `element` is present in the set's current optimistic state.
pub fn g_set_contains(set: SharedGSet, element: String) -> Bool {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GSetContains(set.address, element, reply)
  })
}

@target(erlang)
/// The set's current optimistic members.
pub fn g_set_values(set: SharedGSet) -> List(String) {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetGSetValues(set.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_g_set(set: SharedGSet) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(set.runtime, runtime.Subscribe(set.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Two-phase sets (2P-Set)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new two-phase set channel. Same detached lifecycle as
/// `create_map`: local-only until its handle (`two_p_set_handle_of`) is first
/// stored into an attached map. A remove is a permanent tombstone: a removed
/// element can never be made active again, so remove wins over a concurrent
/// (re-)add.
pub fn create_two_p_set(document: Document) -> Result(SharedTwoPSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateTwoPSet,
  )
  |> result.map(fn(address) {
    SharedTwoPSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn two_p_set_handle_of(set: SharedTwoPSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the SharedTwoPSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_two_p_set(
  document: Document,
  value: Json,
) -> Result(SharedTwoPSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedTwoPSet(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically add `element` to the set. Adding a previously removed
/// element records the add but never reactivates it.
pub fn two_p_set_add(set: SharedTwoPSet, element: String) -> Nil {
  process.send(set.runtime, runtime.AddTwoPSetElement(set.address, element))
}

@target(erlang)
/// Optimistically remove `element` from the set. Removal is a permanent
/// tombstone.
pub fn two_p_set_remove(set: SharedTwoPSet, element: String) -> Nil {
  process.send(set.runtime, runtime.RemoveTwoPSetElement(set.address, element))
}

@target(erlang)
/// Whether `element` is present in the set's current optimistic state.
pub fn two_p_set_contains(set: SharedTwoPSet, element: String) -> Bool {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.TwoPSetContains(set.address, element, reply)
  })
}

@target(erlang)
/// The set's current optimistic members.
pub fn two_p_set_values(set: SharedTwoPSet) -> List(String) {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetTwoPSetValues(set.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_two_p_set(set: SharedTwoPSet) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(set.runtime, runtime.Subscribe(set.address, subscriber))
  subscriber
}

// ─────────────────────────────────────────────────────────────────────────────
// Directories (hierarchical maps)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new directory channel: a hierarchical map keyed by absolute paths
/// (the root is `"/"`). Same detached lifecycle as `create_map`: local-only
/// until its handle (`directory_handle_of`) is first stored into an attached
/// map.
pub fn create_directory(document: Document) -> Result(SharedDirectory, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateDirectory,
  )
  |> result.map(fn(address) {
    SharedDirectory(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `dir`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn directory_handle_of(dir: SharedDirectory) -> Json {
  handle.encode_handle(dir.address)
}

@target(erlang)
/// Resolve a handle value to the SharedDirectory it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_directory(
  document: Document,
  value: Json,
) -> Result(SharedDirectory, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedDirectory(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically set `key` to `value` in the subdirectory at `path` (root is
/// `"/"`).
pub fn directory_set(
  dir: SharedDirectory,
  path: String,
  key: String,
  value: Json,
) -> Nil {
  process.send(dir.runtime, runtime.DirectorySet(dir.address, path, key, value))
}

@target(erlang)
/// Optimistically remove `key` from the subdirectory at `path`.
pub fn directory_delete(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Nil {
  process.send(dir.runtime, runtime.DirectoryDelete(dir.address, path, key))
}

@target(erlang)
/// Optimistically remove every key from the subdirectory at `path`.
pub fn directory_clear(dir: SharedDirectory, path: String) -> Nil {
  process.send(dir.runtime, runtime.DirectoryClear(dir.address, path))
}

@target(erlang)
/// Optimistically create a subdirectory named `name` under `path`.
pub fn directory_create_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  process.send(
    dir.runtime,
    runtime.DirectoryCreateSubdirectory(dir.address, path, name),
  )
}

@target(erlang)
/// Optimistically delete the subdirectory named `name` under `path` (and all
/// of its contents).
pub fn directory_delete_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  process.send(
    dir.runtime,
    runtime.DirectoryDeleteSubdirectory(dir.address, path, name),
  )
}

@target(erlang)
/// The current optimistic value at `key` in the subdirectory at `path`, `None`
/// when absent.
pub fn directory_get(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Option(Json) {
  process.call(dir.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.DirectoryGet(dir.address, path, key, reply)
  })
}

@target(erlang)
/// The current optimistic `#(key, value)` entries in the subdirectory at
/// `path`.
pub fn directory_entries(
  dir: SharedDirectory,
  path: String,
) -> List(#(String, Json)) {
  process.call(dir.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.DirectoryEntries(dir.address, path, reply)
  })
}

@target(erlang)
/// The names of the immediate subdirectories under `path`.
pub fn directory_subdirectories(
  dir: SharedDirectory,
  path: String,
) -> List(String) {
  process.call(dir.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.DirectorySubdirectories(dir.address, path, reply)
  })
}

@target(erlang)
/// Whether a subdirectory named `name` exists under `path`.
pub fn directory_has_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Bool {
  process.call(dir.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.DirectoryHasSubdirectory(dir.address, path, name, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this directory's events, local and remote
/// alike.
pub fn subscribe_directory(dir: SharedDirectory) -> Subject(ChannelEvent) {
  let subscriber = process.new_subject()
  process.send(dir.runtime, runtime.Subscribe(dir.address, subscriber))
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
