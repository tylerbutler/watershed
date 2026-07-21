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
////
//// For a schema-typed view, `typed` wraps a map as a `TypedMap(s)` and the
//// `set_field`/`get_field`/`read`/`write` functions read and write through a
//// `watershed/schema` declaration. `ensure_*` seeds and adopts nested channels
//// (maps, counters, OR-sets, claims, …) declaratively, and `subscribe_field` /
//// `subscribe_counter` / `subscribe_typed` deliver narrowed, decoded events.
//// See the "Typed maps" and "Typed channel fields" sections below.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/crypto
@target(erlang)
import gleam/dict
@target(erlang)
import gleam/dynamic.{type Dynamic}
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
import signet/types as token
@target(erlang)
import spillway/message.{type ConnectMessage, type SignalMessage, ConnectMessage}
@target(erlang)
import spillway/types.{Client, ClientCapabilities, ClientDetails, WriteMode}

@target(erlang)
import watershed/channel.{type ChannelEvent}
@target(erlang)
import watershed/claims_kernel
@target(erlang)
import watershed/counter_kernel
@target(erlang)
import watershed/directory_kernel
@target(erlang)
import watershed/g_set_kernel
@target(erlang)
import watershed/git_storage.{type SummaryVersion}
@target(erlang)
import watershed/handle
@target(erlang)
import watershed/json_ot
@target(erlang)
import watershed/json_ot_kernel
@target(erlang)
import watershed/map_kernel
@target(erlang)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(erlang)
import watershed/or_set_kernel
@target(erlang)
import watershed/register_collection_kernel.{type ReadPolicy, Atomic}
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
  type FieldError,
}
@target(erlang)
import watershed/sequence_kernel
@target(erlang)
import watershed/task_manager_kernel
@target(erlang)
import watershed/two_p_set_kernel
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
pub opaque type JsonOt {
  JsonOt(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type OrMap {
  OrMap(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type OrSet {
  OrSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type RegisterCollection {
  RegisterCollection(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type Claims {
  Claims(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type TaskManager {
  TaskManager(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type GSet {
  GSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type TwoPSet {
  TwoPSet(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedDirectory {
  SharedDirectory(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type PnCounter {
  PnCounter(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type PactMap {
  PactMap(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type OrderedCollection {
  OrderedCollection(runtime: Subject(runtime.Msg), address: String)
}

@target(erlang)
pub opaque type SharedSequence {
  SharedSequence(runtime: Subject(runtime.Msg), address: String)
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
    build_connect_message(tenant, document, user_id, Some(token))

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
fn build_connect_message(
  tenant: String,
  document: String,
  user_id: String,
  token: option.Option(String),
) -> ConnectMessage {
  ConnectMessage(
    tenant_id: tenant,
    document_id: document,
    token: token,
    client: Client(
      mode: WriteMode,
      details: ClientDetails(
        capabilities: ClientCapabilities(interactive: True),
        client_type: Some("watershed"),
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
}

@target(erlang)
/// Connect through an injected transport — the seam the in-memory `sluice`
/// test driver uses. Unlike `connect`, this does *not* block on the handshake:
/// the sluice completes it on the first `settle`. Not for production use.
pub fn connect_via(
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
  transport transport: runtime.Transport,
) -> Result(Document, String) {
  let connect_message = build_connect_message(tenant, document, user_id, None)
  case
    runtime.start_with_transport(
      host: "sluice",
      port: 0,
      connect_message: connect_message,
      transport: transport,
    )
  {
    Error(_) -> Error("failed to start document runtime")
    Ok(subject) -> Ok(Document(runtime: subject))
  }
}

@target(erlang)
/// The runtime actor behind a document. Exposed for the `sluice` test driver,
/// which barriers the actor (a synchronous call flushes its mailbox) to make
/// delivery deterministic. Not part of the app-facing API.
pub fn runtime_subject(document: Document) -> Subject(runtime.Msg) {
  document.runtime
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
// Typed channel fields
//
// Per-kind set/resolve pairs for `schema.ChannelField(s, kind)` — keys whose
// value is a handle to a non-map channel. The phantom kind tag makes using a
// field with the wrong kind's resolver a compile error. Dispatch is per kind
// because each resolver is a different runtime call with a different return
// type. Resolvers return `Ok(None)` when the key is absent; resolve errors
// (including transient not-yet-attached ones) are surfaced as-is and are
// retryable.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn put_channel_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, kind),
  handle_json: Json,
) -> Nil {
  set(typed_map.map, schema.channel_field_key(field), handle_json)
}

@target(erlang)
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

@target(erlang)
/// Store a handle to an (untyped) nested map under a typed channel field.
pub fn set_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
  map: SharedMap,
) -> Nil {
  put_channel_field(typed_map, field, handle_of(map))
}

@target(erlang)
/// Resolve the map referenced by a typed channel field.
pub fn resolve_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
) -> Result(Option(SharedMap), String) {
  get_channel_field(document, typed_map, field, resolve)
}

@target(erlang)
/// Store a handle to `counter` under a typed channel field.
pub fn set_counter_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
  counter: SharedCounter,
) -> Nil {
  put_channel_field(typed_map, field, counter_handle_of(counter))
}

@target(erlang)
/// Resolve the counter referenced by a typed channel field.
pub fn resolve_counter_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
) -> Result(Option(SharedCounter), String) {
  get_channel_field(document, typed_map, field, resolve_counter)
}

@target(erlang)
/// Store a handle to `json_ot` under a typed channel field.
pub fn set_json_ot_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
  json_ot: JsonOt,
) -> Nil {
  put_channel_field(typed_map, field, json_ot_handle_of(json_ot))
}

@target(erlang)
/// Resolve the json0 channel referenced by a typed channel field.
pub fn resolve_json_ot_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
) -> Result(Option(JsonOt), String) {
  get_channel_field(document, typed_map, field, resolve_json_ot)
}

@target(erlang)
/// Store a handle to `or_map` under a typed channel field.
pub fn set_or_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  or_map: OrMap,
) -> Nil {
  put_channel_field(typed_map, field, or_map_handle_of(or_map))
}

@target(erlang)
/// Resolve the OR-map referenced by a typed channel field.
pub fn resolve_or_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
) -> Result(Option(OrMap), String) {
  get_channel_field(document, typed_map, field, resolve_or_map)
}

@target(erlang)
/// Store a handle to `or_set` under a typed channel field.
pub fn set_or_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  or_set: OrSet,
) -> Nil {
  put_channel_field(typed_map, field, or_set_handle_of(or_set))
}

@target(erlang)
/// Resolve the OR-set referenced by a typed channel field.
pub fn resolve_or_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
) -> Result(Option(OrSet), String) {
  get_channel_field(document, typed_map, field, resolve_or_set)
}

@target(erlang)
pub fn set_sequence_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  sequence: SharedSequence,
) -> Nil {
  put_channel_field(typed_map, field, sequence_handle_of(sequence))
}

@target(erlang)
pub fn resolve_sequence_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(Option(SharedSequence), String) {
  get_channel_field(document, typed_map, field, resolve_sequence)
}

@target(erlang)
/// Store a handle to `collection` under a typed channel field.
pub fn set_register_collection_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  collection: RegisterCollection,
) -> Nil {
  put_channel_field(typed_map, field, register_collection_handle_of(collection))
}

@target(erlang)
/// Resolve the register collection referenced by a typed channel field.
pub fn resolve_register_collection_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
) -> Result(Option(RegisterCollection), String) {
  get_channel_field(document, typed_map, field, resolve_register_collection)
}

@target(erlang)
/// Store a handle to `claims` under a typed channel field.
pub fn set_claims_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  claims: Claims,
) -> Nil {
  put_channel_field(typed_map, field, claims_handle_of(claims))
}

@target(erlang)
/// Resolve the claims channel referenced by a typed channel field.
pub fn resolve_claims_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
) -> Result(Option(Claims), String) {
  get_channel_field(document, typed_map, field, resolve_claims)
}

@target(erlang)
/// Store a handle to `manager` under a typed channel field.
pub fn set_task_manager_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  manager: TaskManager,
) -> Nil {
  put_channel_field(typed_map, field, task_manager_handle_of(manager))
}

@target(erlang)
/// Resolve the task manager referenced by a typed channel field.
pub fn resolve_task_manager_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
) -> Result(Option(TaskManager), String) {
  get_channel_field(document, typed_map, field, resolve_task_manager)
}

@target(erlang)
/// Store a handle to `set` under a typed channel field.
pub fn set_g_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
  set: GSet,
) -> Nil {
  put_channel_field(typed_map, field, g_set_handle_of(set))
}

@target(erlang)
/// Resolve the G-set referenced by a typed channel field.
pub fn resolve_g_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
) -> Result(Option(GSet), String) {
  get_channel_field(document, typed_map, field, resolve_g_set)
}

@target(erlang)
/// Store a handle to `set` under a typed channel field.
pub fn set_two_p_set_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
  set: TwoPSet,
) -> Nil {
  put_channel_field(typed_map, field, two_p_set_handle_of(set))
}

@target(erlang)
/// Resolve the 2P-set referenced by a typed channel field.
pub fn resolve_two_p_set_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
) -> Result(Option(TwoPSet), String) {
  get_channel_field(document, typed_map, field, resolve_two_p_set)
}

@target(erlang)
/// Store a handle to `dir` under a typed channel field.
pub fn set_directory_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
  dir: SharedDirectory,
) -> Nil {
  put_channel_field(typed_map, field, directory_handle_of(dir))
}

@target(erlang)
/// Resolve the directory referenced by a typed channel field.
pub fn resolve_directory_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
) -> Result(Option(SharedDirectory), String) {
  get_channel_field(document, typed_map, field, resolve_directory)
}

@target(erlang)
/// Store a handle to `pn_counter` under a typed channel field.
pub fn set_pn_counter_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
  pn_counter: PnCounter,
) -> Nil {
  put_channel_field(typed_map, field, pn_counter_handle_of(pn_counter))
}

@target(erlang)
/// Resolve the PN-counter referenced by a typed channel field.
pub fn resolve_pn_counter_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
) -> Result(Option(PnCounter), String) {
  get_channel_field(document, typed_map, field, resolve_pn_counter)
}

@target(erlang)
/// Store a handle to `pact_map` under a typed channel field.
pub fn set_pact_map_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
  pact_map: PactMap,
) -> Nil {
  put_channel_field(typed_map, field, pact_map_handle_of(pact_map))
}

@target(erlang)
/// Resolve the PactMap referenced by a typed channel field.
pub fn resolve_pact_map_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
) -> Result(Option(PactMap), String) {
  get_channel_field(document, typed_map, field, resolve_pact_map)
}

@target(erlang)
/// Store a handle to `collection` under a typed channel field.
pub fn set_ordered_collection_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
  collection: OrderedCollection,
) -> Nil {
  put_channel_field(typed_map, field, ordered_collection_handle_of(collection))
}

@target(erlang)
/// Resolve the ordered collection referenced by a typed channel field.
pub fn resolve_ordered_collection_field(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
) -> Result(Option(OrderedCollection), String) {
  get_channel_field(document, typed_map, field, resolve_ordered_collection)
}

// ─────────────────────────────────────────────────────────────────────────────
// Declarative bootstrap (ensure_*)
//
// Each `ensure_*` gives a typed slot a guaranteed channel: adopt the sequenced
// LWW winner if the key is already set, otherwise seed a candidate channel,
// wait for sync, and adopt whichever handle the sequencer ordered first (losing
// candidates stay attached but unreferenced — orphan GC is out of scope). This
// subsumes the seed + wait-synced + bounded-retry-resolve loop every app used
// to hand-roll. `ensure_field` is the set-if-absent primitive for plain values.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
const resolve_retry_ms = 200

@target(erlang)
const resolve_attempts = 25

@target(erlang)
/// Block until every local edit is acked (the confirmed root is stable),
/// bounded by the resolve budget, then return regardless.
fn await_synced(document: Document, attempts: Int) -> Nil {
  case attempts <= 0 || is_synced(document) {
    True -> Nil
    False -> {
      process.sleep(resolve_retry_ms)
      await_synced(document, attempts - 1)
    }
  }
}

@target(erlang)
/// Resolve a field to its channel, retrying while the handle is absent or the
/// referenced channel's attach op is still in flight.
fn resolve_with_retry(
  resolve: fn() -> Result(Option(shared), String),
  attempts: Int,
) -> Result(shared, String) {
  case resolve(), attempts {
    Ok(Some(shared)), _ -> Ok(shared)
    Ok(None), n if n <= 1 ->
      Error("ensure: no channel handle appeared under the field")
    Error(reason), n if n <= 1 -> Error(reason)
    _, _ -> {
      process.sleep(resolve_retry_ms)
      resolve_with_retry(resolve, attempts - 1)
    }
  }
}

@target(erlang)
/// Adopt the channel under `key`: resolve the sequenced winner if the key is
/// set, else `seed` a candidate, wait for sync, and resolve whatever won.
fn ensure_channel(
  document: Document,
  typed_map: TypedMap(s),
  key: String,
  seed: fn() -> Result(Nil, String),
  resolve: fn() -> Result(Option(shared), String),
) -> Result(shared, String) {
  case has(typed_map.map, key) {
    True -> resolve_with_retry(resolve, resolve_attempts)
    False -> {
      use _ <- result.try(seed())
      await_synced(document, resolve_attempts)
      resolve_with_retry(resolve, resolve_attempts)
    }
  }
}

@target(erlang)
/// Ensure a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
) -> Result(SharedMap, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use map <- result.map(create_map(document))
      set_map_field(typed_map, field, map)
    },
    fn() { resolve_map_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
) -> Result(SharedCounter, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use counter <- result.map(create_counter(document))
      set_counter_field(typed_map, field, counter)
    },
    fn() { resolve_counter_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a json0 channel exists under `field`.
pub fn ensure_json_ot(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
) -> Result(JsonOt, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use json_ot <- result.map(create_json_ot(document))
      set_json_ot_field(typed_map, field, json_ot)
    },
    fn() { resolve_json_ot_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure an OR-map exists under `field`, seeding one in `mode` if absent.
pub fn ensure_or_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  mode: OrMapMode,
) -> Result(OrMap, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use or_map <- result.map(create_or_map(document, mode))
      set_or_map_field(typed_map, field, or_map)
    },
    fn() { resolve_or_map_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
) -> Result(OrSet, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use or_set <- result.map(create_or_set(document))
      set_or_set_field(typed_map, field, or_set)
    },
    fn() { resolve_or_set_field(document, typed_map, field) },
  )
}

@target(erlang)
pub fn ensure_sequence(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(SharedSequence, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use sequence <- result.map(create_sequence(document))
      set_sequence_field(typed_map, field, sequence)
    },
    fn() { resolve_sequence_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
) -> Result(RegisterCollection, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use registers <- result.map(create_register_collection(document))
      set_register_collection_field(typed_map, field, registers)
    },
    fn() { resolve_register_collection_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
) -> Result(Claims, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use claims <- result.map(create_claims(document))
      set_claims_field(typed_map, field, claims)
    },
    fn() { resolve_claims_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
) -> Result(TaskManager, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use tasks <- result.map(create_task_manager(document))
      set_task_manager_field(typed_map, field, tasks)
    },
    fn() { resolve_task_manager_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a grow-only set exists under `field`.
pub fn ensure_g_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
) -> Result(GSet, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use g_set <- result.map(create_g_set(document))
      set_g_set_field(typed_map, field, g_set)
    },
    fn() { resolve_g_set_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a two-phase set exists under `field`.
pub fn ensure_two_p_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
) -> Result(TwoPSet, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use two_p_set <- result.map(create_two_p_set(document))
      set_two_p_set_field(typed_map, field, two_p_set)
    },
    fn() { resolve_two_p_set_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a directory exists under `field`.
pub fn ensure_directory(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
) -> Result(SharedDirectory, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use dir <- result.map(create_directory(document))
      set_directory_field(typed_map, field, dir)
    },
    fn() { resolve_directory_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a PN-counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_pn_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
) -> Result(PnCounter, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use pn_counter <- result.map(create_pn_counter(document))
      set_pn_counter_field(typed_map, field, pn_counter)
    },
    fn() { resolve_pn_counter_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
) -> Result(PactMap, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use pact_map <- result.map(create_pact_map(document))
      set_pact_map_field(typed_map, field, pact_map)
    },
    fn() { resolve_pact_map_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
) -> Result(OrderedCollection, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use collection <- result.map(create_ordered_collection(document))
      set_ordered_collection_field(typed_map, field, collection)
    },
    fn() { resolve_ordered_collection_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Ensure a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document,
  typed_map: TypedMap(s),
  field: ChildField(s, c),
) -> Result(TypedMap(c), String) {
  ensure_channel(
    document,
    typed_map,
    schema.child_key(field),
    fn() {
      use child <- result.map(create_map(document))
      set_child(typed_map, field, typed(child))
    },
    fn() { resolve_child(document, typed_map, field) },
  )
}

@target(erlang)
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
/// Subscribe to a channel's events, forwarding only the events `narrow`
/// accepts — already decoded to the kind's own event type — to a fresh
/// caller-owned subject. The per-kind `subscribe_*` functions wrap this so a
/// subscriber sees only its channel's events, never the 14-variant union.
fn subscribe_narrowed(
  runtime_subject: Subject(runtime.Msg),
  address: String,
  narrow: fn(ChannelEvent) -> Option(a),
) -> Subject(a) {
  let subject = process.new_subject()
  process.send(
    runtime_subject,
    runtime.Subscribe(address, fn(event) {
      case narrow(event) {
        Some(inner) -> process.send(subject, inner)
        None -> Nil
      }
    }),
  )
  subject
}

@target(erlang)
/// Subscribe the calling process to this counter's events, local and remote
/// alike. The subject carries `counter_kernel.CounterEvent` — counter events
/// only.
pub fn subscribe_counter(
  counter: SharedCounter,
) -> Subject(counter_kernel.CounterEvent) {
  use event <- subscribe_narrowed(counter.runtime, counter.address)
  case event {
    channel.CounterEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON-OT (json0)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new json0 (JSON-OT) channel. Same detached lifecycle as
/// `create_map`: local-only until its handle (`json_ot_handle_of`) is first
/// stored into an attached map.
pub fn create_json_ot(document: Document) -> Result(JsonOt, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateJsonOt,
  )
  |> result.map(fn(address) {
    JsonOt(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `json_ot`, suitable for storing as a
/// value in a map (see `handle_of`).
pub fn json_ot_handle_of(json_ot: JsonOt) -> Json {
  handle.encode_handle(json_ot.address)
}

@target(erlang)
/// Resolve a handle value to the JsonOt it references. Existence is
/// checked, not channel type. Errors are retryable, as with `resolve`.
pub fn resolve_json_ot(
  document: Document,
  value: Json,
) -> Result(JsonOt, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        JsonOt(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically submit a json0 op (a list of components) to the channel.
pub fn submit_json_ot(json_ot: JsonOt, op: json_ot.Op) -> Nil {
  process.send(json_ot.runtime, runtime.SubmitJsonOt(json_ot.address, op))
}

@target(erlang)
/// The json0 channel's current optimistic document, `None` when the address is
/// not a json0 channel.
pub fn json_ot_view(json_ot: JsonOt) -> Option(json_ot.JsonValue) {
  process.call(json_ot.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetJsonOtView(json_ot.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this json0 channel's events, local and
/// remote alike.
pub fn subscribe_json_ot(
  json_ot: JsonOt,
) -> Subject(json_ot_kernel.JsonOtEvent) {
  use event <- subscribe_narrowed(json_ot.runtime, json_ot.address)
  case event {
    channel.JsonOtEvent(inner) -> Some(inner)
    _ -> None
  }
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
) -> Result(OrMap, String) {
  process.call(document.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.CreateOrMap(mode, reply)
  })
  |> result.map(fn(address) {
    OrMap(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn or_map_handle_of(or_map: OrMap) -> Json {
  handle.encode_handle(or_map.address)
}

@target(erlang)
pub fn resolve_or_map(
  document: Document,
  value: Json,
) -> Result(OrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { OrMap(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
pub fn or_map_increment(or_map: OrMap, key: String, amount: Int) -> Nil {
  process.send(
    or_map.runtime,
    runtime.IncrementOrMap(or_map.address, key, amount),
  )
}

@target(erlang)
pub fn or_map_set(or_map: OrMap, key: String, value: String) -> Nil {
  process.send(or_map.runtime, runtime.SetOrMapKey(or_map.address, key, value))
}

@target(erlang)
pub fn or_map_set_json(or_map: OrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(erlang)
pub fn or_map_remove(or_map: OrMap, key: String) -> Nil {
  process.send(or_map.runtime, runtime.RemoveOrMapKey(or_map.address, key))
}

@target(erlang)
pub fn or_map_value(or_map: OrMap, key: String) -> Option(OrMapValue) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapValue(or_map.address, key, reply)
  })
}

@target(erlang)
pub fn or_map_entries(or_map: OrMap) -> List(#(String, OrMapValue)) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapEntries(or_map.address, reply)
  })
}

@target(erlang)
pub fn or_map_keys(or_map: OrMap) -> List(String) {
  process.call(or_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrMapKeys(or_map.address, reply)
  })
}

@target(erlang)
pub fn subscribe_or_map(or_map: OrMap) -> Subject(or_map_kernel.OrMapEvent) {
  use event <- subscribe_narrowed(or_map.runtime, or_map.address)
  case event {
    channel.OrMapEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-sets
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new observed-remove set channel for string elements.
pub fn create_or_set(document: Document) -> Result(OrSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateOrSet,
  )
  |> result.map(fn(address) {
    OrSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn or_set_handle_of(or_set: OrSet) -> Json {
  handle.encode_handle(or_set.address)
}

@target(erlang)
pub fn resolve_or_set(
  document: Document,
  value: Json,
) -> Result(OrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { OrSet(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
pub fn or_set_add(or_set: OrSet, element: String) -> Nil {
  process.send(or_set.runtime, runtime.AddOrSetElement(or_set.address, element))
}

@target(erlang)
pub fn or_set_remove(or_set: OrSet, element: String) -> Nil {
  process.send(
    or_set.runtime,
    runtime.RemoveOrSetElement(or_set.address, element),
  )
}

@target(erlang)
pub fn or_set_contains(or_set: OrSet, element: String) -> Bool {
  process.call(or_set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.OrSetContains(or_set.address, element, reply)
  })
}

@target(erlang)
pub fn or_set_values(or_set: OrSet) -> List(String) {
  process.call(or_set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrSetValues(or_set.address, reply)
  })
}

@target(erlang)
pub fn subscribe_or_set(or_set: OrSet) -> Subject(or_set_kernel.OrSetEvent) {
  use event <- subscribe_narrowed(or_set.runtime, or_set.address)
  case event {
    channel.OrSetEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sequences
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_sequence(document: Document) -> Result(SharedSequence, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateSequence,
  )
  |> result.map(fn(address) {
    SharedSequence(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn sequence_handle_of(sequence: SharedSequence) -> Json {
  handle.encode_handle(sequence.address)
}

@target(erlang)
pub fn resolve_sequence(
  document: Document,
  value: Json,
) -> Result(SharedSequence, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_sequence(document.runtime, address)
      |> result.map(fn(_) {
        SharedSequence(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Insert `value` at zero-based `index`, from `0` through the sequence length.
pub fn sequence_insert(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.InsertSequenceItem(sequence.address, index, value, reply)
  })
}

@target(erlang)
/// Delete the value at a zero-based `index`, from `0` through `length - 1`.
pub fn sequence_delete(
  sequence: SharedSequence,
  index: Int,
) -> Result(Nil, String) {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.DeleteSequenceItem(sequence.address, index, reply)
  })
}

@target(erlang)
/// Move a value between zero-based indexes; the destination is evaluated after
/// removing the source value.
pub fn sequence_move(
  sequence: SharedSequence,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String) {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.MoveSequenceItem(sequence.address, from_index, to_index, reply)
  })
}

@target(erlang)
/// Replace the value at a zero-based `index` as one collaborative operation.
pub fn sequence_replace(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.ReplaceSequenceItem(sequence.address, index, value, reply)
  })
}

@target(erlang)
pub fn sequence_values(sequence: SharedSequence) -> List(Json) {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetSequenceValues(sequence.address, reply)
  })
}

@target(erlang)
pub fn sequence_length(sequence: SharedSequence) -> Int {
  process.call(sequence.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetSequenceLength(sequence.address, reply)
  })
}

@target(erlang)
pub fn subscribe_sequence(
  sequence: SharedSequence,
) -> Subject(sequence_kernel.SequenceEvent) {
  use event <- subscribe_narrowed(sequence.runtime, sequence.address)
  case event {
    channel.SequenceEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register collections
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new consensus register collection. Like other non-root channels it
/// starts detached until its handle is stored in an attached map.
pub fn create_register_collection(
  document: Document,
) -> Result(RegisterCollection, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateRegisterCollection,
  )
  |> result.map(fn(address) {
    RegisterCollection(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn register_collection_handle_of(collection: RegisterCollection) -> Json {
  handle.encode_handle(collection.address)
}

@target(erlang)
pub fn resolve_register_collection(
  document: Document,
  value: Json,
) -> Result(RegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        RegisterCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn register_write(
  collection: RegisterCollection,
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
  collection: RegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterValue(collection.address, key, policy, reply)
  })
}

@target(erlang)
pub fn register_get(
  collection: RegisterCollection,
  key: String,
) -> Option(Json) {
  register_read(collection, key, Atomic)
}

@target(erlang)
pub fn register_versions(
  collection: RegisterCollection,
  key: String,
) -> Option(List(Json)) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterVersions(collection.address, key, reply)
  })
}

@target(erlang)
pub fn register_keys(collection: RegisterCollection) -> List(String) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetRegisterKeys(collection.address, reply)
  })
}

@target(erlang)
pub fn subscribe_register_collection(
  collection: RegisterCollection,
) -> Subject(register_collection_kernel.RegisterEvent) {
  use event <- subscribe_narrowed(collection.runtime, collection.address)
  case event {
    channel.RegisterCollectionEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_claims(document: Document) -> Result(Claims, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateClaims,
  )
  |> result.map(fn(address) {
    Claims(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn claims_handle_of(claims: Claims) -> Json {
  handle.encode_handle(claims.address)
}

@target(erlang)
pub fn resolve_claims(
  document: Document,
  value: Json,
) -> Result(Claims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        Claims(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn try_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime.ClaimSubmitReply {
  runtime.try_set_claim(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn compare_and_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime.ClaimSubmitReply {
  runtime.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn get_claim(claims: Claims, key: String) -> Option(Json) {
  runtime.get_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn has_claim(claims: Claims, key: String) -> Bool {
  runtime.has_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn subscribe_claims(claims: Claims) -> Subject(claims_kernel.ClaimEvent) {
  use event <- subscribe_narrowed(claims.runtime, claims.address)
  case event {
    channel.ClaimsEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task managers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_task_manager(document: Document) -> Result(TaskManager, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateTaskManager,
  )
  |> result.map(fn(address) {
    TaskManager(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn task_manager_handle_of(manager: TaskManager) -> Json {
  handle.encode_handle(manager.address)
}

@target(erlang)
pub fn resolve_task_manager(
  document: Document,
  value: Json,
) -> Result(TaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        TaskManager(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn volunteer_for_task(
  manager: TaskManager,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  runtime.volunteer_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn abandon_task(manager: TaskManager, task_id: String) -> Nil {
  runtime.abandon_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn complete_task(
  manager: TaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime.complete_task(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_assigned(manager: TaskManager, task_id: String) -> Bool {
  runtime.task_assigned(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queued(manager: TaskManager, task_id: String) -> Bool {
  runtime.task_queued(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queues(manager: TaskManager) -> List(#(String, List(Int))) {
  runtime.task_queues(manager.runtime, manager.address)
}

@target(erlang)
pub fn subscribe_task_manager(
  manager: TaskManager,
) -> Subject(task_manager_kernel.TaskManagerEvent) {
  use event <- subscribe_narrowed(manager.runtime, manager.address)
  case event {
    channel.TaskManagerEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grow-only sets (G-Set)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new grow-only set channel. Same detached lifecycle as
/// `create_map`: local-only until its handle (`g_set_handle_of`) is first
/// stored into an attached map. Elements can only be added, never removed;
/// concurrent adds always converge to the union.
pub fn create_g_set(document: Document) -> Result(GSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateGSet,
  )
  |> result.map(fn(address) {
    GSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn g_set_handle_of(set: GSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the GSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_g_set(document: Document, value: Json) -> Result(GSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { GSet(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
/// Optimistically add `element` to the set.
pub fn g_set_add(set: GSet, element: String) -> Nil {
  process.send(set.runtime, runtime.AddGSetElement(set.address, element))
}

@target(erlang)
/// Whether `element` is present in the set's current optimistic state.
pub fn g_set_contains(set: GSet, element: String) -> Bool {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GSetContains(set.address, element, reply)
  })
}

@target(erlang)
/// The set's current optimistic members.
pub fn g_set_values(set: GSet) -> List(String) {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetGSetValues(set.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_g_set(set: GSet) -> Subject(g_set_kernel.GSetEvent) {
  use event <- subscribe_narrowed(set.runtime, set.address)
  case event {
    channel.GSetEvent(inner) -> Some(inner)
    _ -> None
  }
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
pub fn create_two_p_set(document: Document) -> Result(TwoPSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateTwoPSet,
  )
  |> result.map(fn(address) {
    TwoPSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker referencing `set`, suitable for storing as a value
/// in a map (see `handle_of`).
pub fn two_p_set_handle_of(set: TwoPSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the TwoPSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_two_p_set(
  document: Document,
  value: Json,
) -> Result(TwoPSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        TwoPSet(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically add `element` to the set. Adding a previously removed
/// element records the add but never reactivates it.
pub fn two_p_set_add(set: TwoPSet, element: String) -> Nil {
  process.send(set.runtime, runtime.AddTwoPSetElement(set.address, element))
}

@target(erlang)
/// Optimistically remove `element` from the set. Removal is a permanent
/// tombstone.
pub fn two_p_set_remove(set: TwoPSet, element: String) -> Nil {
  process.send(set.runtime, runtime.RemoveTwoPSetElement(set.address, element))
}

@target(erlang)
/// Whether `element` is present in the set's current optimistic state.
pub fn two_p_set_contains(set: TwoPSet, element: String) -> Bool {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.TwoPSetContains(set.address, element, reply)
  })
}

@target(erlang)
/// The set's current optimistic members.
pub fn two_p_set_values(set: TwoPSet) -> List(String) {
  process.call(set.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetTwoPSetValues(set.address, reply)
  })
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_two_p_set(
  set: TwoPSet,
) -> Subject(two_p_set_kernel.TwoPSetEvent) {
  use event <- subscribe_narrowed(set.runtime, set.address)
  case event {
    channel.TwoPSetEvent(inner) -> Some(inner)
    _ -> None
  }
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
pub fn subscribe_directory(
  dir: SharedDirectory,
) -> Subject(directory_kernel.DirectoryEvent) {
  use event <- subscribe_narrowed(dir.runtime, dir.address)
  case event {
    channel.DirectoryEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PN-counters (increment and decrement)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new PN-counter channel. Same detached lifecycle as `create_map`:
/// local-only until its handle is stored into an attached container.
pub fn create_pn_counter(document: Document) -> Result(PnCounter, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreatePnCounter,
  )
  |> result.map(fn(address) {
    PnCounter(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn pn_counter_handle_of(pn_counter: PnCounter) -> Json {
  handle.encode_handle(pn_counter.address)
}

@target(erlang)
pub fn resolve_pn_counter(
  document: Document,
  value: Json,
) -> Result(PnCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        PnCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Optimistically add `amount` (negative amounts decrement).
pub fn pn_counter_update(pn_counter: PnCounter, amount: Int) -> Nil {
  process.send(
    pn_counter.runtime,
    runtime.UpdatePnCounter(pn_counter.address, amount),
  )
}

@target(erlang)
/// The counter's current optimistic value, `None` when the address is not a
/// PN-counter channel.
pub fn pn_counter_value(pn_counter: PnCounter) -> Option(Int) {
  process.call(pn_counter.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetPnCounterValue(pn_counter.address, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// PactMaps (consensus map: writes are proposals settled by sequencing)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new PactMap channel. Same detached lifecycle as `create_map`.
pub fn create_pact_map(document: Document) -> Result(PactMap, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreatePactMap,
  )
  |> result.map(fn(address) {
    PactMap(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn pact_map_handle_of(pact_map: PactMap) -> Json {
  handle.encode_handle(pact_map.address)
}

@target(erlang)
pub fn resolve_pact_map(
  document: Document,
  value: Json,
) -> Result(PactMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        PactMap(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Propose `value` for `key`. Consensus, not optimistic: the value is `pending`
/// until server sequencing accepts it.
pub fn pact_map_set(pact_map: PactMap, key: String, value: Json) -> Nil {
  process.send(
    pact_map.runtime,
    runtime.SetPactMap(pact_map.address, key, value),
  )
}

@target(erlang)
/// Propose a delete (tombstone) for `key`.
pub fn pact_map_delete(pact_map: PactMap, key: String) -> Nil {
  process.send(pact_map.runtime, runtime.DeletePactMap(pact_map.address, key))
}

@target(erlang)
/// The accepted value for `key`, `None` when pending, absent, or not a PactMap
/// channel.
pub fn pact_map_get(pact_map: PactMap, key: String) -> Option(Json) {
  process.call(pact_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetPactMapValue(pact_map.address, key, reply)
  })
}

@target(erlang)
/// All keys with an accepted or pending pact.
pub fn pact_map_keys(pact_map: PactMap) -> List(String) {
  process.call(pact_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetPactMapKeys(pact_map.address, reply)
  })
}

@target(erlang)
/// Whether `key` currently has an unsettled (pending) proposal.
pub fn pact_map_is_pending(pact_map: PactMap, key: String) -> Bool {
  process.call(pact_map.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetPactMapPending(pact_map.address, key, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Ordered collections (consensus work queue)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new ConsensusOrderedCollection channel. Same detached lifecycle as
/// `create_map`.
pub fn create_ordered_collection(
  document: Document,
) -> Result(OrderedCollection, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_ms,
    sending: runtime.CreateOrderedCollection,
  )
  |> result.map(fn(address) {
    OrderedCollection(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn ordered_collection_handle_of(collection: OrderedCollection) -> Json {
  handle.encode_handle(collection.address)
}

@target(erlang)
pub fn resolve_ordered_collection(
  document: Document,
  value: Json,
) -> Result(OrderedCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_ms,
        sending: fn(reply) { runtime.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        OrderedCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Enqueue `value` at the tail of the collection.
pub fn ordered_add(collection: OrderedCollection, value: Json) -> Nil {
  process.send(
    collection.runtime,
    runtime.AddOrderedItem(collection.address, value),
  )
}

@target(erlang)
/// Acquire (lease) the head item, returning the acquire id used to `complete`
/// or `release` it.
pub fn ordered_acquire(collection: OrderedCollection) -> String {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.AcquireOrderedItem(collection.address, reply)
  })
}

@target(erlang)
/// Complete an acquired item, removing it permanently.
pub fn ordered_complete(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  process.send(
    collection.runtime,
    runtime.CompleteOrderedItem(collection.address, acquire_id),
  )
}

@target(erlang)
/// Release an acquired item back to the collection for another consumer.
pub fn ordered_release(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  process.send(
    collection.runtime,
    runtime.ReleaseOrderedItem(collection.address, acquire_id),
  )
}

@target(erlang)
/// The number of items currently in the collection, `None` when the address is
/// not an ordered-collection channel.
pub fn ordered_size(collection: OrderedCollection) -> Option(Int) {
  process.call(collection.runtime, waiting: call_timeout_ms, sending: fn(reply) {
    runtime.GetOrderedSize(collection.address, reply)
  })
}

// ── Ripples (ephemeral presence signals) ─────────────────────────────────────

@target(erlang)
/// A received ripple: an ephemeral, document-scoped broadcast. Non-sequenced
/// and non-persisted — ideal for transient presence (cursors, selection,
/// typing indicators) that must NOT live in a DDS.
pub type Ripple =
  SignalMessage

@target(erlang)
/// Broadcast an ephemeral ripple to every other connected client: a `type`
/// tag plus arbitrary JSON `content`. Fire-and-forget — no ordering, ack, or
/// catch-up. No-op until the first handshake assigns a client id.
pub fn submit_ripple(
  document: Document,
  ripple_type ripple_type: String,
  content content: Json,
) -> Nil {
  process.send(document.runtime, runtime.SubmitRipple(ripple_type, content))
}

@target(erlang)
/// Subscribe the calling process to every inbound ripple on the document. The
/// returned subject carries `Ripple` values, mirroring the per-channel
/// `subscribe_*` functions.
pub fn subscribe_ripples(document: Document) -> Subject(Ripple) {
  let subject = process.new_subject()
  process.send(
    document.runtime,
    runtime.SubscribeRipple(fn(ripple) { process.send(subject, ripple) }),
  )
  subject
}

@target(erlang)
/// The ripple's `type` tag, if present.
pub fn ripple_type(ripple: Ripple) -> Option(String) {
  ripple.signal_type
}

@target(erlang)
/// The ripple's JSON payload, left as `Dynamic` for the caller to decode.
pub fn ripple_content(ripple: Ripple) -> Dynamic {
  ripple.content
}

@target(erlang)
/// The sending client's id, if the server stamped one (`None` for
/// server-originated ripples).
pub fn ripple_client_id(ripple: Ripple) -> Option(String) {
  ripple.client_id
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
/// receives a `map_kernel.MapEvent` — map events only — for every local and
/// remote change to this channel.
pub fn subscribe(map: SharedMap) -> Subject(map_kernel.MapEvent) {
  use event <- subscribe_narrowed(map.runtime, map.address)
  case event {
    channel.MapEvent(inner) -> Some(inner)
    _ -> None
  }
}

@target(erlang)
/// Subscribe to a typed map's whole-map events without dropping to the untyped
/// API. Like `subscribe`, the subject receives narrowed `map_kernel.MapEvent`s;
/// use `subscribe_field` instead to watch a single typed field.
pub fn subscribe_typed(typed_map: TypedMap(s)) -> Subject(map_kernel.MapEvent) {
  subscribe(typed_map.map)
}

@target(erlang)
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

@target(erlang)
/// Subscribe to changes of a single typed field. Each local or remote write to
/// `field`'s key delivers a `FieldChange` with the new and previous values
/// decoded at the boundary — `Error(Invalid)` when a peer wrote a value that
/// does not match the field type. A `Cleared` on the map fans out as
/// `FieldChange(Ok(None), Ok(None), local)`; clears carry no per-key previous.
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
) -> Subject(FieldChange(a)) {
  let key = schema.field_key(field)
  let subject = process.new_subject()
  process.send(
    typed_map.map.runtime,
    runtime.Subscribe(typed_map.map.address, fn(event) {
      case field_change(field, key, event) {
        Some(change) -> process.send(subject, change)
        None -> Nil
      }
    }),
  )
  subject
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
