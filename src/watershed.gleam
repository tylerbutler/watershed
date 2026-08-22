//// Public JavaScript API: connect to a floodgate document and edit its root
//// SharedMap from the browser. The BEAM counterpart is `watershed_beam`.
////
//// ```gleam
//// use token <- promise.map(watershed.dev_token(
////   secret: "levee-dev-secret-change-in-production",
////   tenant: "dev-tenant", document: "dice", user_id: "user-1",
//// ))
//// let doc =
////   watershed.connect(
////     WatershedConfig(
////       url: "ws://localhost:4000/socket/websocket?vsn=2.0.0",
////       tenant: "dev-tenant", document: "dice",
////       token: token, user_id: "user-1",
////     ),
////     on_ready: fn(result) { ... },
////   )
//// let map = watershed.root(doc)
//// watershed.set(map, "die", json.int(4))
//// watershed.subscribe(map, fn(event) { ... })
//// ```
////
//// A read is optimistic: the local pending edits go over the sequenced state.
//// The server sequencing guarantees that the replicas converge.
////
//// `create_map` makes more maps beside the root map, and each one starts
//// detached. Store the handle of such a map, from `handle_of`, as a value, and
//// a peer can then call `resolve` on it. Nested collaborative structures work
//// that way.
////
//// For a view with a schema, `typed` wraps a map as a `TypedMap(s)` value. The
//// `set_field`, `get_field`, `read`, and `write` functions then read and write
//// through a `watershed/schema` declaration. The `ensure_*` family creates and
//// adopts a nested channel declaratively, and those channels are maps,
//// counters, OR-sets, claims, and the other kinds. `subscribe_field`,
//// `subscribe_counter`, and `subscribe_typed` deliver decoded events of one
//// kind only. See [`examples/sudoku_lustre`](../examples/sudoku_lustre) for
//// the full pattern.
////
//// JavaScript target only.

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
import watershed/ordered_collection_kernel
@target(javascript)
import watershed/pact_map_kernel
@target(javascript)
import watershed/pn_counter_kernel
@target(javascript)
import watershed/register_collection_kernel.{type ReadPolicy, Atomic}
@target(javascript)
import watershed/rich_text
@target(javascript)
import watershed/rich_text_kernel
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
  type FieldError,
}
@target(javascript)
import watershed/sequence_kernel
@target(javascript)
import watershed/summary_policy
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
/// The connection parameters of `connect`.
pub type WatershedConfig {
  WatershedConfig(
    /// The URL of the Phoenix socket, for example
    /// `"ws://localhost:4000/socket/websocket?vsn=2.0.0"`. The `vsn=2.0.0`
    /// query parameter selects the V2 serializer.
    url: String,
    tenant: String,
    document: String,
    token: String,
    user_id: String,
  )
}

@target(javascript)
pub opaque type Document(root) {
  Document(runtime: runtime.Runtime)
}

@target(javascript)
/// The connection state and the sequencing state, which you can read but not
/// change, for diagnostics and for the example interfaces.
pub type Diagnostics =
  runtime.Diagnostics

@target(javascript)
pub opaque type SharedMap {
  SharedMap(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedCounter {
  SharedCounter(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type OrMap {
  OrMap(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type OrSet {
  OrSet(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type RegisterCollection {
  RegisterCollection(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type Claims {
  Claims(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type TaskManager {
  TaskManager(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type PnCounter {
  PnCounter(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type PactMap {
  PactMap(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type OrderedCollection {
  OrderedCollection(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedSequence {
  SharedSequence(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedText {
  SharedText(runtime: runtime.Runtime, address: String)
}

@target(javascript)
/// A stable position in the optimistic string of a `SharedText` value. It stays
/// correct across concurrent edits and merges. The type is opaque. Construct one
/// with `text_anchor_at`, `text_start_anchor`, or `text_end_anchor`, or decode
/// one with `text_anchor_from_json`.
pub type TextAnchor =
  text_kernel.TextAnchor

@target(javascript)
/// The grapheme that a `TextAnchor` value binds to across a concurrent insert
/// at its gap. `Before` binds it to the grapheme after the gap, so an insert at
/// the gap moves the anchor to the right. `After` binds it to the grapheme
/// before the gap, so an insert at the gap goes after the anchor. This type is
/// re-exported here, so a caller needs no direct dependency on
/// `lattice_sequence` to build an anchor.
pub type Bias =
  text_kernel.Bias

@target(javascript)
pub const bias_before: Bias = Before

@target(javascript)
pub const bias_after: Bias = After

@target(javascript)
pub opaque type JsonOt {
  JsonOt(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedRichText {
  SharedRichText(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type GSet {
  GSet(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type TwoPSet {
  TwoPSet(runtime: runtime.Runtime, address: String)
}

@target(javascript)
pub opaque type SharedDirectory {
  SharedDirectory(runtime: runtime.Runtime, address: String)
}

@target(javascript)
/// Connect to a document. The function returns the handle immediately. It calls
/// `on_ready` with `Ok(Nil)` after the handshake and the history replay
/// complete, or with `Error(reason)` when the server refuses the connection.
pub fn connect(
  config: WatershedConfig,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Document(root) {
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
    runtime.start(
      url: config.url,
      topic: topic,
      connect_message: connect_message,
      on_ready: on_ready,
    )
  Document(runtime: runtime)
}

@target(javascript)
/// Connect through an injected transport. The in-memory `sluice_js` test driver
/// uses this seam. `on_ready` still runs when the handshake completes, and the
/// driver causes that completion when it delivers the handshake frame on a
/// `settle` call. Do not use this function in production.
pub fn connect_via(
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
  transport transport: runtime.Transport,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Document(root) {
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
  Document(runtime: runtime.start_with_transport(
    http_base_url: "sluice",
    connect_message: connect_message,
    transport: transport,
    on_ready: on_ready,
  ))
}

@target(javascript)
/// The runtime behind a document. This function is public for the `sluice_js`
/// test driver, which uses the runtime as the key of a paused client. It is not
/// part of the API for an application.
pub fn runtime_of(document: Document(root)) -> runtime.Runtime {
  document.runtime
}

@target(javascript)
/// The root map of the document, at the channel address `"root"`.
pub fn root(document: Document(root)) -> SharedMap {
  SharedMap(runtime: document.runtime, address: "root")
}

@target(javascript)
/// Create a new map channel. The map starts *detached*, which means that it is
/// local only and its edits produce no op. It stays detached until a caller
/// stores its handle, from `handle_of`, into an attached map. The runtime then
/// attaches it, with its snapshot, and it starts to synchronize the edits of
/// that map. The connection must be ready, which `on_ready` reports.
pub fn create_map(document: Document(root)) -> Result(SharedMap, String) {
  runtime.create_map(document.runtime)
  |> result.map(fn(address) {
    SharedMap(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `map`. Store it as a value in
/// another map. Its shape is
/// `{"type": "__fluid_handle__", "url": "/<address>"}`.
pub fn handle_of(map: SharedMap) -> Json {
  handle.encode_handle(map.address)
}

@target(javascript)
/// Whether a value that you read from a map is a handle marker. See
/// `resolve`.
pub fn is_handle(value: Json) -> Bool {
  handle.parse_handle(value) != Error(Nil)
}

@target(javascript)
/// Resolve a handle value, from `get` or from `entries`, to the SharedMap that
/// it references. A caller can retry after an error. A handle from a remote
/// value can stay unresolved for a short time, while the attach op of the
/// channel that it references is still in flight.
pub fn resolve(
  document: Document(root),
  value: Json,
) -> Result(SharedMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedMap(runtime: document.runtime, address: address)
      })
  }
}

// ── Typed maps ───────────────────────────────────────────────────────────────
//
// An opt-in, phantom-typed view over a SharedMap. `schema` is constrained by
// inference the first time a `Field(schema, _)` is used against the map, so a
// field from one schema cannot be applied to a map of another. Typing is a
// decode boundary (remote peers may write anything), so reads return `Result`.
// See `watershed/schema` for defining fields.

@target(javascript)
/// A SharedMap value, viewed through a schema `s`.
pub opaque type TypedMap(s) {
  TypedMap(map: SharedMap)
}

@target(javascript)
/// View a raw map through a schema. The use of the result selects the schema,
/// and an annotation can also select it, for example
/// `let players: TypedMap(Roster) = typed(map)`.
pub fn typed(map: SharedMap) -> TypedMap(s) {
  TypedMap(map: map)
}

@target(javascript)
/// The raw map below the typed view, to return to the untyped API.
pub fn untyped(typed_map: TypedMap(s)) -> SharedMap {
  typed_map.map
}

@target(javascript)
/// The root map of the document, viewed through the schema of that document.
///
/// One document has one tag. The tag comes from the `Document(root)` value that
/// you pass, so it is fixed at the position where your application writes the
/// type concretely. That position is the `Msg` constructor that carries the
/// handle, or the `Model` field that holds it:
///
/// ```gleam
/// GotHandle(Document(doc_schema.Survey))
/// ```
///
/// Every `root_typed` call on that document then agrees. A second schema at the
/// root is a compile error, and not a key namespace that two schemas share
/// quietly.
///
/// A component that is generic in `root` can still call this function. But an
/// abstract tag has no field, so that component cannot read or write the root.
/// A nested panel is thus structurally unable to reach past its own child map.
///
/// `typed(root(document))` is still available, and it is still unchecked. It is
/// the deliberate way to view the root through a foreign schema. Unlike the old
/// signature, you must now write it explicitly.
pub fn root_typed(document: Document(root)) -> TypedMap(root) {
  typed(root(document))
}

@target(javascript)
/// Create a new detached map, viewed through a schema. The lifecycle is the
/// same as for `create_map`.
pub fn create_typed_map(
  document: Document(root),
) -> Result(TypedMap(s), String) {
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
/// Read a typed field. The result is `Ok(None)` when the key is absent, and
/// `Error(Invalid)` when the stored value does not decode to the type `a`.
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
/// Read a typed field that must exist. The result is `Error(Missing)` when the
/// key is absent.
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
/// Whether a typed field is present. The function does not check that the
/// value decodes.
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
/// Resolve the nested typed map that a child field references. The result is
/// `Ok(None)` when the key is absent. The function returns an error from
/// `resolve` without a change, and a caller can retry after it. That includes
/// the short-lived error for a channel that is not attached yet.
pub fn resolve_child(
  document: Document(root),
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
/// Read the whole map as a typed record, through a schema. The function returns
/// one `Result` value, after the version check and the seal check of that
/// schema. See `watershed/schema`.
pub fn read(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
) -> Result(record, FieldError) {
  schema.decode_entries(map_schema, entries(typed_map.map))
}

@target(javascript)
/// Write a whole record through a schema, as one op for each key. Concurrent
/// edits to two other keys thus still merge, and the record view never
/// overwrites the whole map. An optional prop with the value `None` deletes its
/// key.
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
/// Write the version marker of a schema that has a version, one time. The usual
/// position for this call is immediately after you create the map. The function
/// does nothing for a schema with no version.
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
/// Resolve every key whose value is a handle to a typed child map. This is the
/// typed view of a dynamic collection, which is a map whose keys the compiler
/// does not know, for example a roster keyed by id. The function skips a key
/// whose value is not a handle. It returns the `Result` value of each child,
/// and a caller can retry after the short-lived error for a channel that is not
/// attached yet.
pub fn typed_children(
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, kind),
  resolver: fn(Document(root), Json) -> Result(shared, String),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
) -> Result(Option(JsonOt), String) {
  get_channel_field(document, typed_map, field, resolve_json_ot)
}

@target(javascript)
/// Store a handle to `rich_text` under a typed channel field.
pub fn set_rich_text_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
  rich_text: SharedRichText,
) -> Nil {
  put_channel_field(typed_map, field, rich_text_handle_of(rich_text))
}

@target(javascript)
/// Resolve the rich-text channel referenced by a typed channel field.
pub fn resolve_rich_text_field(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
) -> Result(Option(SharedRichText), String) {
  get_channel_field(document, typed_map, field, resolve_rich_text)
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
@external(javascript, "./watershed_ffi.mjs", "set_timeout")
fn set_timeout(action: fn() -> Nil, ms: Int) -> Nil

@target(javascript)
const resolve_retry_ms = 200

@target(javascript)
const resolve_attempts = 25

@target(javascript)
/// Read `is_synced` at intervals until the confirmed root is stable, and then
/// call `next`. The resolve budget limits the number of reads.
fn await_synced(
  document: Document(root),
  attempts: Int,
  next: fn() -> Nil,
) -> Nil {
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
/// Resolve a field to its channel. The function tries again on a timer while the
/// handle is absent, and while the attach op of the channel that it references
/// is still in flight.
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
/// Adopt the channel under `key`. If the key holds a value, the function
/// resolves the sequenced winner. If the key is empty, the function calls `seed`
/// to create a candidate, waits for the synchronization, and then resolves the
/// channel that won.
fn ensure_channel(
  document: Document(root),
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
/// Make sure that a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document(root),
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
/// Make sure that a counter exists under `field`. If the slot is empty, the
/// function creates one.
pub fn ensure_counter(
  document: Document(root),
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
/// Make sure that an OR-map exists under `field`. If none exists, the function
/// creates one in `mode`.
pub fn ensure_or_map(
  document: Document(root),
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
/// Make sure that an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document(root),
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
  document: Document(root),
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
/// Make sure that a text channel exists under `field`. If the slot is empty,
/// the function creates one.
pub fn ensure_text(
  document: Document(root),
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
/// Make sure that a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document(root),
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
/// Make sure that a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document(root),
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
/// Make sure that a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document(root),
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
/// Make sure that a PN-counter exists under `field`. If the slot is empty, the
/// function creates one.
pub fn ensure_pn_counter(
  document: Document(root),
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
/// Make sure that a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document(root),
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
/// Make sure that an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document(root),
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
/// Make sure that a json0 channel exists under `field`. If none exists, the
/// function creates one.
pub fn ensure_json_ot(
  document: Document(root),
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
/// Make sure that a rich-text channel exists under `field`. If none exists,
/// the function creates one.
pub fn ensure_rich_text(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
  done: fn(Result(SharedRichText, String)) -> Nil,
) -> Nil {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use rich_text <- result.map(create_rich_text(document))
      set_rich_text_field(typed_map, field, rich_text)
    },
    fn() { resolve_rich_text_field(document, typed_map, field) },
    done,
  )
}

@target(javascript)
/// Make sure that a G-set exists under `field`. If none exists, the function
/// creates one.
pub fn ensure_g_set(
  document: Document(root),
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
/// Make sure that a 2P-set exists under `field`. If none exists, the function
/// creates one.
pub fn ensure_two_p_set(
  document: Document(root),
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
/// Make sure that a directory exists under `field`. If none exists, the
/// function creates one.
pub fn ensure_directory(
  document: Document(root),
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
/// Make sure that a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document(root),
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
/// Set a plain typed field to `default`, and only when its key is absent now.
/// Every client in a race writes the value, and the last-writer-wins rule on
/// that key settles one of them.
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
/// Create a new counter channel. The detached lifecycle is the same as for
/// `create_map`. The channel is local only, until a caller stores its handle,
/// from `counter_handle_of`, into an attached map. The connection must be
/// ready, which `on_ready` reports.
pub fn create_counter(
  document: Document(root),
) -> Result(SharedCounter, String) {
  runtime.create_counter(document.runtime)
  |> result.map(fn(address) {
    SharedCounter(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `counter`. Store it as a value in a
/// map. See `handle_of`.
pub fn counter_handle_of(counter: SharedCounter) -> Json {
  handle.encode_handle(counter.address)
}

@target(javascript)
/// Resolve a handle value to the SharedCounter that it references. The function
/// checks that the channel exists, and it does not check the channel type. To
/// resolve a channel that is not a counter gives a counter whose reads return
/// `None`. A caller can retry after an error, the same as for `resolve`.
pub fn resolve_counter(
  document: Document(root),
  value: Json,
) -> Result(SharedCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Increment the counter optimistically. A negative amount decrements it.
pub fn increment(counter: SharedCounter, amount: Int) -> Nil {
  runtime.increment(counter.runtime, counter.address, amount)
}

@target(javascript)
/// The current optimistic value of the counter. The result is `None` when the
/// address does not name a counter channel.
pub fn counter_value(counter: SharedCounter) -> Option(Int) {
  runtime.counter_value(counter.runtime, counter.address)
}

@target(javascript)
/// Register `handler` for the events of a channel. The function calls that
/// handler only for the events that `narrow` accepts, and it decodes each one to
/// the event type of that channel kind. A subscriber thus never sees the union
/// of 14 variants. The `subscribe_*` function of each kind uses this
/// function.
fn subscribe_narrowed(
  runtime: runtime.Runtime,
  address: String,
  handler: fn(a) -> Nil,
  narrow: fn(ChannelEvent) -> Option(a),
) -> Nil {
  runtime.subscribe(runtime, address, fn(event) {
    case narrow(event) {
      Some(inner) -> handler(inner)
      None -> Nil
    }
  })
}

@target(javascript)
/// Register a callback for every local change and remote change to this counter
/// channel. The handler receives a `counter_kernel.CounterEvent` value, and it
/// receives no other kind of event.
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
/// Create a new OR-map channel, in tally mode or in register mode. The detached
/// lifecycle is the same as for `create_map`.
pub fn create_or_map(
  document: Document(root),
  mode: OrMapMode,
) -> Result(OrMap, String) {
  runtime.create_or_map(document.runtime, mode)
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
  document: Document(root),
  value: Json,
) -> Result(OrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) { OrMap(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
pub fn or_map_increment(or_map: OrMap, key: String, amount: Int) -> Nil {
  runtime.or_map_increment(or_map.runtime, or_map.address, key, amount)
}

@target(javascript)
pub fn or_map_set(or_map: OrMap, key: String, value: String) -> Nil {
  runtime.or_map_set(or_map.runtime, or_map.address, key, value)
}

@target(javascript)
pub fn or_map_set_json(or_map: OrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(javascript)
pub fn or_map_remove(or_map: OrMap, key: String) -> Nil {
  runtime.or_map_remove(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_value(or_map: OrMap, key: String) -> Option(OrMapValue) {
  runtime.or_map_value(or_map.runtime, or_map.address, key)
}

@target(javascript)
pub fn or_map_entries(or_map: OrMap) -> List(#(String, OrMapValue)) {
  runtime.or_map_entries(or_map.runtime, or_map.address)
}

@target(javascript)
pub fn or_map_keys(or_map: OrMap) -> List(String) {
  runtime.or_map_keys(or_map.runtime, or_map.address)
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
/// Create a new observed-remove set channel, for string elements.
pub fn create_or_set(document: Document(root)) -> Result(OrSet, String) {
  runtime.create_or_set(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(OrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) { OrSet(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
pub fn or_set_add(or_set: OrSet, element: String) -> Nil {
  runtime.or_set_add(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_remove(or_set: OrSet, element: String) -> Nil {
  runtime.or_set_remove(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_contains(or_set: OrSet, element: String) -> Bool {
  runtime.or_set_contains(or_set.runtime, or_set.address, element)
}

@target(javascript)
pub fn or_set_values(or_set: OrSet) -> List(String) {
  runtime.or_set_values(or_set.runtime, or_set.address)
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
pub fn create_sequence(
  document: Document(root),
) -> Result(SharedSequence, String) {
  runtime.create_sequence(document.runtime)
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
  document: Document(root),
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

@target(javascript)
/// Insert `value` at `index`, counted from zero, in the range `0` to the length
/// of the sequence.
pub fn sequence_insert(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  runtime.sequence_insert(sequence.runtime, sequence.address, index, value)
}

@target(javascript)
/// Delete the value at `index`, counted from zero, in the range `0` to
/// `length - 1`.
pub fn sequence_delete(
  sequence: SharedSequence,
  index: Int,
) -> Result(Nil, String) {
  runtime.sequence_delete(sequence.runtime, sequence.address, index)
}

@target(javascript)
/// Move a value between two indexes, counted from zero. The function reads the
/// destination index after it removes the value from the source index.
pub fn sequence_move(
  sequence: SharedSequence,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String) {
  runtime.sequence_move(
    sequence.runtime,
    sequence.address,
    from_index,
    to_index,
  )
}

@target(javascript)
/// Replace the value at `index`, counted from zero, as one collaborative
/// operation.
pub fn sequence_replace(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  runtime.sequence_replace(sequence.runtime, sequence.address, index, value)
}

@target(javascript)
pub fn sequence_values(sequence: SharedSequence) -> List(Json) {
  runtime.sequence_values(sequence.runtime, sequence.address)
}

@target(javascript)
pub fn sequence_length(sequence: SharedSequence) -> Int {
  runtime.sequence_length(sequence.runtime, sequence.address)
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
pub fn create_text(document: Document(root)) -> Result(SharedText, String) {
  runtime.create_text(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(SharedText, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_text(document.runtime, address)
      |> result.map(fn(_) {
        SharedText(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Insert `value` at the optimistic grapheme `index`, in the range `0` to the
/// length of the text. An empty `value` at a valid index changes nothing.
pub fn text_insert(
  text: SharedText,
  index: Int,
  value: String,
) -> Result(Nil, String) {
  runtime.text_insert(text.runtime, text.address, index, value)
}

@target(javascript)
/// Delete the graphemes in `[start, end)`. An empty range with valid bounds
/// changes nothing.
pub fn text_delete_range(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(Nil, String) {
  runtime.text_delete_range(text.runtime, text.address, start, end)
}

@target(javascript)
/// Replace the graphemes in `[start, end)` with `value`, as one collaborative
/// operation. Only an empty range that you replace with `""` changes
/// nothing.
pub fn text_replace_range(
  text: SharedText,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String) {
  runtime.text_replace_range(text.runtime, text.address, start, end, value)
}

@target(javascript)
/// Insert `value` at the end of the text. An empty `value` changes nothing.
pub fn text_append(text: SharedText, value: String) -> Result(Nil, String) {
  runtime.text_append(text.runtime, text.address, value)
}

@target(javascript)
/// The current visible optimistic string of the text.
pub fn text_value(text: SharedText) -> String {
  runtime.text_value(text.runtime, text.address)
}

@target(javascript)
/// The current optimistic grapheme count of the text.
pub fn text_length(text: SharedText) -> Int {
  runtime.text_length(text.runtime, text.address)
}

@target(javascript)
/// The graphemes in `[start, end)` of the optimistic string of the text. The
/// result is an error string when the range `start..end` is invalid.
pub fn text_substring(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(String, String) {
  runtime.text_substring(text.runtime, text.address, start, end)
}

@target(javascript)
/// Create a stable anchor at the gap before the optimistic grapheme at `index`.
/// `bias_before` and `bias_after` set the bias. The result is an error string
/// when the index is out of bounds.
pub fn text_anchor_at(
  text: SharedText,
  index: Int,
  bias: Bias,
) -> Result(TextAnchor, String) {
  runtime.text_anchor_at(text.runtime, text.address, index, bias)
}

@target(javascript)
/// Resolve an anchor to a current optimistic grapheme index. The result is an
/// error string when the anchor target is stale or unknown.
pub fn text_resolve_anchor(
  text: SharedText,
  anchor: TextAnchor,
) -> Result(Int, String) {
  runtime.text_resolve_anchor(text.runtime, text.address, anchor)
}

@target(javascript)
/// An anchor at the start of the text. It always resolves to 0. The function is
/// pure. It needs no `SharedText` value, because the anchor carries no document
/// state.
pub fn text_start_anchor() -> TextAnchor {
  runtime.text_start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. It always resolves to the current grapheme
/// count, and it moves as the text becomes longer. The function is pure, the
/// same as `text_start_anchor`.
pub fn text_end_anchor() -> TextAnchor {
  runtime.text_end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value, for example to send it
/// through presence for a shared cursor.
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  runtime.text_anchor_to_json(anchor)
}

@target(javascript)
/// Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
/// result is an error string for malformed JSON.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(TextAnchor, String) {
  runtime.text_anchor_from_json(json_string)
}

@target(javascript)
/// Register a callback for every local change and remote change to this text
/// channel. The handler receives a `text_kernel.TextEvent` value, and it
/// receives no other kind of event.
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
  document: Document(root),
) -> Result(RegisterCollection, String) {
  runtime.create_register_collection(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(RegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
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
  runtime.register_write(collection.runtime, collection.address, key, value)
}

@target(javascript)
pub fn register_read(
  collection: RegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  runtime.register_read(collection.runtime, collection.address, key, policy)
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
  runtime.register_versions(collection.runtime, collection.address, key)
}

@target(javascript)
pub fn register_keys(collection: RegisterCollection) -> List(String) {
  runtime.register_keys(collection.runtime, collection.address)
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
pub fn create_claims(document: Document(root)) -> Result(Claims, String) {
  runtime.create_claims(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(Claims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
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
) -> runtime.ClaimSubmitReply {
  runtime.try_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn compare_and_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime.ClaimSubmitReply {
  runtime.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(javascript)
pub fn get_claim(claims: Claims, key: String) -> Option(Json) {
  runtime.get_claim(claims.runtime, claims.address, key)
}

@target(javascript)
pub fn has_claim(claims: Claims, key: String) -> Bool {
  runtime.has_claim(claims.runtime, claims.address, key)
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
pub fn create_task_manager(
  document: Document(root),
) -> Result(TaskManager, String) {
  runtime.create_task_manager(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(TaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
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
  runtime.task_manager_volunteer(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn abandon_task(manager: TaskManager, task_id: String) -> Nil {
  runtime.task_manager_abandon(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn complete_task(
  manager: TaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime.task_manager_complete(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_assigned(manager: TaskManager, task_id: String) -> Bool {
  runtime.task_manager_assigned(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queued(manager: TaskManager, task_id: String) -> Bool {
  runtime.task_manager_queued(manager.runtime, manager.address, task_id)
}

@target(javascript)
pub fn task_queues(manager: TaskManager) -> List(#(String, List(Int))) {
  runtime.task_manager_queues(manager.runtime, manager.address)
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
/// Create a new PN-counter channel. The detached lifecycle is the same as for
/// `create_map`.
pub fn create_pn_counter(
  document: Document(root),
) -> Result(PnCounter, String) {
  runtime.create_pn_counter(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(PnCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        PnCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Add `amount` optimistically. A negative amount decrements the counter.
pub fn pn_counter_update(pn_counter: PnCounter, amount: Int) -> Nil {
  runtime.pn_counter_update(pn_counter.runtime, pn_counter.address, amount)
}

@target(javascript)
/// The current optimistic value of the counter. The result is `None` when the
/// address does not name a PN-counter channel.
pub fn pn_counter_value(pn_counter: PnCounter) -> Option(Int) {
  runtime.pn_counter_value(pn_counter.runtime, pn_counter.address)
}

@target(javascript)
/// Register a callback for every local change and remote change to this
/// PN-counter.
pub fn subscribe_pn_counter(
  pn_counter: PnCounter,
  handler: fn(pn_counter_kernel.PnCounterEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(
    pn_counter.runtime,
    pn_counter.address,
    handler,
  )
  case event {
    channel.PnCounterEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── PactMaps ─────────────────────────────────────────────────────────────────

@target(javascript)
/// Create a new PactMap channel. The detached lifecycle is the same as for
/// `create_map`.
pub fn create_pact_map(document: Document(root)) -> Result(PactMap, String) {
  runtime.create_pact_map(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(PactMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        PactMap(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Propose `value` for `key`. This write is a consensus write, and it is not
/// optimistic. The value stays pending until the server sequencing accepts
/// it.
pub fn pact_map_set(pact_map: PactMap, key: String, value: Json) -> Nil {
  runtime.pact_map_set(pact_map.runtime, pact_map.address, key, value)
}

@target(javascript)
/// Propose a delete for `key`. A delete writes a tombstone.
pub fn pact_map_delete(pact_map: PactMap, key: String) -> Nil {
  runtime.pact_map_delete(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// The accepted value for `key`. The result is `None` when the value is
/// pending, when the key is absent, and when the address does not name a
/// PactMap channel.
pub fn pact_map_get(pact_map: PactMap, key: String) -> Option(Json) {
  runtime.pact_map_get(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// Every key with an accepted pact or a pending pact.
pub fn pact_map_keys(pact_map: PactMap) -> List(String) {
  runtime.pact_map_keys(pact_map.runtime, pact_map.address)
}

@target(javascript)
/// Register a callback for the consensus transitions of this PactMap. Those
/// transitions are `WentPending`, when a proposal sequences, and
/// `WentAccepted`, when its signoff list becomes empty.
///
/// Those two transitions *are* the protocol. Without this callback a PactMap
/// only accepts a write and answers a read. An application can then propose a
/// value and read a value, and it cannot learn that the proposal of a peer
/// arrived. That one difference separates a PactMap from a map.
pub fn subscribe_pact_map(
  pact_map: PactMap,
  handler: fn(pact_map_kernel.PactMapEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(pact_map.runtime, pact_map.address, handler)
  case event {
    channel.PactMapEvent(inner) -> Some(inner)
    _ -> None
  }
}

@target(javascript)
/// Whether `key` has a proposal now that no room has settled, which is a
/// pending proposal.
pub fn pact_map_is_pending(pact_map: PactMap, key: String) -> Bool {
  runtime.pact_map_is_pending(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// The clients whose agreement `key` still waits on. The result is `None` when
/// nothing is pending.
///
/// This list changes a progress indicator into an explanation.
/// `pact_map_is_pending` reports *that* a value is unsettled. This function
/// reports *which clients* it waits on. The kernel freezes the list from the
/// connected roster when the proposal sequences, so the list names the room at
/// that moment. A client that left after that moment leaves the list when its
/// `"leave"` message sequences, and not before.
pub fn pact_map_pending_signoffs(
  pact_map: PactMap,
  key: String,
) -> Option(List(Int)) {
  pact_map_pending(pact_map, key)
  |> option.map(fn(pending) { pending.expected_signoffs })
}

@target(javascript)
/// The full pending proposal for `key`, which is the value that waits for
/// agreement, with the signoff list that it waits on. The result is `None` when
/// nothing is pending.
pub fn pact_map_pending(
  pact_map: PactMap,
  key: String,
) -> Option(pact_map_kernel.Pending) {
  runtime.pact_map_pending(pact_map.runtime, pact_map.address, key)
}

@target(javascript)
/// The accepted entry for `key`: the agreed value, with the sequence number
/// that it settled at. The result is `None` when the key is absent, and when
/// the value is still pending.
pub fn pact_map_get_with_details(
  pact_map: PactMap,
  key: String,
) -> Option(pact_map_kernel.Accepted) {
  runtime.pact_map_get_with_details(pact_map.runtime, pact_map.address, key)
}

// ── Ordered collections ──────────────────────────────────────────────────────

@target(javascript)
/// Create a new ConsensusOrderedCollection channel. The detached lifecycle is
/// the same as for `create_map`.
pub fn create_ordered_collection(
  document: Document(root),
) -> Result(OrderedCollection, String) {
  runtime.create_ordered_collection(document.runtime)
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
  document: Document(root),
  value: Json,
) -> Result(OrderedCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        OrderedCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Add `value` at the end of the collection.
pub fn ordered_add(collection: OrderedCollection, value: Json) -> Nil {
  runtime.ordered_add(collection.runtime, collection.address, value)
}

@target(javascript)
/// Acquire the head item, and return the acquire id. A later `complete` call or
/// `release` call uses that id.
pub fn ordered_acquire(collection: OrderedCollection) -> String {
  runtime.ordered_acquire(collection.runtime, collection.address)
}

@target(javascript)
/// The same as `ordered_acquire`, and the function also reports the consensus
/// outcome of the acquire.
///
/// `on_outcome` runs exactly one time. It gives `AcquiredItem` when this client
/// won the head. It gives `QueueEmpty` when the queue became empty before the
/// op sequenced. An acquire that loses emits no event, so `QueueEmpty` is the
/// only signal that a loser receives. It gives `Aborted` when the document
/// closes while the acquire is still in flight.
pub fn ordered_acquire_with_outcome(
  collection: OrderedCollection,
  on_outcome: fn(ordered_collection_kernel.AcquireOutcome) -> Nil,
) -> String {
  runtime.ordered_acquire_with_outcome(
    collection.runtime,
    collection.address,
    on_outcome,
  )
}

@target(javascript)
/// Complete an acquired item, and remove it permanently.
pub fn ordered_complete(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  runtime.ordered_complete(
    collection.runtime,
    collection.address,
    acquire_id,
  )
}

@target(javascript)
/// Release an acquired item back to the collection, for another consumer.
pub fn ordered_release(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  runtime.ordered_release(collection.runtime, collection.address, acquire_id)
}

@target(javascript)
/// The number of items in the collection now. The result is `None` when the
/// address does not name an ordered-collection channel.
pub fn ordered_size(collection: OrderedCollection) -> Option(Int) {
  runtime.ordered_size(collection.runtime, collection.address)
}

@target(javascript)
/// The values in the queue, which no client acquired yet, front first.
pub fn ordered_queue(collection: OrderedCollection) -> List(Json) {
  runtime.ordered_queue(collection.runtime, collection.address)
}

@target(javascript)
/// The jobs that clients hold now, keyed by acquire id and sorted by that id.
pub fn ordered_jobs(
  collection: OrderedCollection,
) -> List(#(String, ordered_collection_kernel.JobEntry)) {
  runtime.ordered_jobs(collection.runtime, collection.address)
}

@target(javascript)
/// Register a callback for the queue events of this ordered collection. Those
/// events report an item that a client added, acquired, or completed, and an
/// item that the kernel released again after a client left.
pub fn subscribe_ordered_collection(
  collection: OrderedCollection,
  handler: fn(ordered_collection_kernel.OrderedEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(
    collection.runtime,
    collection.address,
    handler,
  )
  case event {
    channel.OrderedCollectionEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── JSON-OT (json0) ──────────────────────────────────────────────────────────

@target(javascript)
/// Create a new json0 channel. The detached lifecycle is the same as for
/// `create_map`. The channel is local only, until a caller stores its handle,
/// from `json_ot_handle_of`, into an attached container.
pub fn create_json_ot(document: Document(root)) -> Result(JsonOt, String) {
  runtime.create_json_ot(document.runtime)
  |> result.map(fn(address) {
    JsonOt(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `json_ot`. Store it as a value in a
/// map. See `handle_of`.
pub fn json_ot_handle_of(json_ot: JsonOt) -> Json {
  handle.encode_handle(json_ot.address)
}

@target(javascript)
/// Resolve a handle value to the JsonOt value that it references. A caller can
/// retry after an error, the same as for `resolve`.
pub fn resolve_json_ot(
  document: Document(root),
  value: Json,
) -> Result(JsonOt, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        JsonOt(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Submit a json0 op to the channel, optimistically. An op is a list of
/// components.
pub fn submit_json_ot(json_ot: JsonOt, op: json_ot.Op) -> Nil {
  runtime.submit_json_ot(json_ot.runtime, json_ot.address, op)
}

@target(javascript)
/// The current optimistic document of the json0 channel. The result is `None`
/// when the address does not name a json0 channel.
pub fn json_ot_view(json_ot: JsonOt) -> Option(json_ot.JsonValue) {
  runtime.json_ot_view(json_ot.runtime, json_ot.address)
}

@target(javascript)
/// Register a callback for every local change and remote change to this json0
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

// ── Shared rich text ─────────────────────────────────────────────────────────

@target(javascript)
/// Create a new rich-text channel. The detached lifecycle is the same as for
/// `create_map`. The channel is local only, until a caller stores its handle,
/// from `rich_text_handle_of`, into an attached container.
pub fn create_rich_text(
  document: Document(root),
) -> Result(SharedRichText, String) {
  runtime.create_rich_text(document.runtime)
  |> result.map(fn(address) {
    SharedRichText(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `rich_text`. Store it as a value in a
/// map. See `handle_of`.
pub fn rich_text_handle_of(rich_text: SharedRichText) -> Json {
  handle.encode_handle(rich_text.address)
}

@target(javascript)
/// Resolve a handle value to the SharedRichText value that it references. The
/// function checks that the channel exists, and it does not check the channel
/// type. A caller can retry after an error, the same as for `resolve`.
pub fn resolve_rich_text(
  document: Document(root),
  value: Json,
) -> Result(SharedRichText, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedRichText(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Submit a rich-text delta to the channel, optimistically.
pub fn submit_rich_text(
  rich_text: SharedRichText,
  delta: rich_text.Delta,
) -> Nil {
  runtime.submit_rich_text(rich_text.runtime, rich_text.address, delta)
}

@target(javascript)
/// The current optimistic rich-text document of the channel. The result is
/// `None` when the address does not name a rich-text channel.
pub fn rich_text_view(rich_text: SharedRichText) -> Option(rich_text.Document) {
  runtime.rich_text_view(rich_text.runtime, rich_text.address)
}

@target(javascript)
/// Register a callback for every local change and remote change to this
/// rich-text channel.
pub fn subscribe_rich_text(
  rich_text: SharedRichText,
  handler: fn(rich_text_kernel.RichTextEvent) -> Nil,
) -> Nil {
  use event <- subscribe_narrowed(rich_text.runtime, rich_text.address, handler)
  case event {
    channel.RichTextEvent(inner) -> Some(inner)
    _ -> None
  }
}

// ── Grow-only sets (G-Set) ───────────────────────────────────────────────────

@target(javascript)
/// Create a new grow-only set channel. The detached lifecycle is the same as
/// for `create_map`. The channel is local only, until a caller stores its
/// handle, from `g_set_handle_of`, into an attached container.
pub fn create_g_set(document: Document(root)) -> Result(GSet, String) {
  runtime.create_g_set(document.runtime)
  |> result.map(fn(address) {
    GSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `set`. Store it as a value in a map.
/// See `handle_of`.
pub fn g_set_handle_of(set: GSet) -> Json {
  handle.encode_handle(set.address)
}

@target(javascript)
/// Resolve a handle value to the GSet value that it references. A caller can
/// retry after an error, the same as for `resolve`.
pub fn resolve_g_set(
  document: Document(root),
  value: Json,
) -> Result(GSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) { GSet(runtime: document.runtime, address: address) })
  }
}

@target(javascript)
/// Add `element` to the set, optimistically.
pub fn g_set_add(set: GSet, element: String) -> Nil {
  runtime.g_set_add(set.runtime, set.address, element)
}

@target(javascript)
/// Whether `element` is in the current optimistic state of the set.
pub fn g_set_contains(set: GSet, element: String) -> Bool {
  runtime.g_set_contains(set.runtime, set.address, element)
}

@target(javascript)
/// The current optimistic members of the set.
pub fn g_set_values(set: GSet) -> List(String) {
  runtime.g_set_values(set.runtime, set.address)
}

@target(javascript)
/// Register a callback for every local change and remote change to this set.
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
/// Create a new two-phase set channel. The detached lifecycle is the same as
/// for `create_map`. The channel is local only, until a caller stores its
/// handle, from `two_p_set_handle_of`, into an attached map. A remove writes a
/// permanent tombstone, and a remove wins against a concurrent add.
pub fn create_two_p_set(document: Document(root)) -> Result(TwoPSet, String) {
  runtime.create_two_p_set(document.runtime)
  |> result.map(fn(address) {
    TwoPSet(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `set`. Store it as a value in a map.
/// See `handle_of`.
pub fn two_p_set_handle_of(set: TwoPSet) -> Json {
  handle.encode_handle(set.address)
}

@target(javascript)
/// Resolve a handle value to the TwoPSet value that it references. A caller can
/// retry after an error, the same as for `resolve`.
pub fn resolve_two_p_set(
  document: Document(root),
  value: Json,
) -> Result(TwoPSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        TwoPSet(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Add `element` to the set, optimistically. If you add an element that a client
/// removed before, the kernel records the add, and the element does not become
/// active again.
pub fn two_p_set_add(set: TwoPSet, element: String) -> Nil {
  runtime.two_p_set_add(set.runtime, set.address, element)
}

@target(javascript)
/// Remove `element` from the set, optimistically. A remove writes a permanent
/// tombstone.
pub fn two_p_set_remove(set: TwoPSet, element: String) -> Nil {
  runtime.two_p_set_remove(set.runtime, set.address, element)
}

@target(javascript)
/// Whether `element` is in the current optimistic state of the set.
pub fn two_p_set_contains(set: TwoPSet, element: String) -> Bool {
  runtime.two_p_set_contains(set.runtime, set.address, element)
}

@target(javascript)
/// The current optimistic members of the set.
pub fn two_p_set_values(set: TwoPSet) -> List(String) {
  runtime.two_p_set_values(set.runtime, set.address)
}

@target(javascript)
/// Register a callback for every local change and remote change to this set.
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
/// Create a new directory channel, which is a hierarchical map keyed by
/// absolute paths. The root path is `"/"`. The detached lifecycle is the same
/// as for `create_map`. The channel is local only, until a caller stores its
/// handle, from `directory_handle_of`, into an attached map.
pub fn create_directory(
  document: Document(root),
) -> Result(SharedDirectory, String) {
  runtime.create_directory(document.runtime)
  |> result.map(fn(address) {
    SharedDirectory(runtime: document.runtime, address: address)
  })
}

@target(javascript)
/// The Fluid handle marker that references `dir`. Store it as a value in a map.
/// See `handle_of`.
pub fn directory_handle_of(dir: SharedDirectory) -> Json {
  handle.encode_handle(dir.address)
}

@target(javascript)
/// Resolve a handle value to the SharedDirectory value that it references. A
/// caller can retry after an error, the same as for `resolve`.
pub fn resolve_directory(
  document: Document(root),
  value: Json,
) -> Result(SharedDirectory, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime.resolve_address(document.runtime, address)
      |> result.map(fn(_) {
        SharedDirectory(runtime: document.runtime, address: address)
      })
  }
}

@target(javascript)
/// Set `key` to `value` in the subdirectory at `path`, optimistically. The root
/// path is `"/"`.
pub fn directory_set(
  dir: SharedDirectory,
  path: String,
  key: String,
  value: Json,
) -> Nil {
  runtime.directory_set(dir.runtime, dir.address, path, key, value)
}

@target(javascript)
/// Remove `key` from the subdirectory at `path`, optimistically.
pub fn directory_delete(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Nil {
  runtime.directory_delete(dir.runtime, dir.address, path, key)
}

@target(javascript)
/// Remove every key from the subdirectory at `path`, optimistically.
pub fn directory_clear(dir: SharedDirectory, path: String) -> Nil {
  runtime.directory_clear(dir.runtime, dir.address, path)
}

@target(javascript)
/// Create a subdirectory named `name` under `path`, optimistically.
pub fn directory_create_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  runtime.directory_create_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// Delete the subdirectory named `name` under `path`, optimistically. The
/// delete also removes every value in that subdirectory.
pub fn directory_delete_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  runtime.directory_delete_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// The current optimistic value at `key`, in the subdirectory at `path`. The
/// result is `None` when the key is absent.
pub fn directory_get(
  dir: SharedDirectory,
  path: String,
  key: String,
) -> Option(Json) {
  runtime.directory_get(dir.runtime, dir.address, path, key)
}

@target(javascript)
/// The current optimistic `#(key, value)` entries in the subdirectory at
/// `path`.
pub fn directory_entries(
  dir: SharedDirectory,
  path: String,
) -> List(#(String, Json)) {
  runtime.directory_entries(dir.runtime, dir.address, path)
}

@target(javascript)
/// The names of the direct subdirectories under `path`.
pub fn directory_subdirectories(
  dir: SharedDirectory,
  path: String,
) -> List(String) {
  runtime.directory_subdirectories(dir.runtime, dir.address, path)
}

@target(javascript)
/// Whether a subdirectory named `name` exists under `path`.
pub fn directory_has_subdirectory(
  dir: SharedDirectory,
  path: String,
  name: String,
) -> Bool {
  runtime.directory_has_subdirectory(dir.runtime, dir.address, path, name)
}

@target(javascript)
/// Register a callback for every local change and remote change to this
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
pub fn close(document: Document(root)) -> Nil {
  runtime.close(document.runtime)
}

@target(javascript)
/// A hook that injects a fault, for a test or a demo. It closes the socket, so
/// that the client runs the reconnect and reconcile path. The pending edits and
/// the in-flight edits all stay.
pub fn force_reconnect(document: Document(root)) -> Nil {
  runtime.force_reconnect(document.runtime)
}

@target(javascript)
/// Go offline and stay offline. The document continues to answer a read and to
/// accept an edit. The edits queue as pending entries, and they go out when
/// `go_online` reconnects.
///
/// This function is `force_reconnect` with a pause. `force_reconnect` goes away
/// and comes back in one step, which leaves no interval to edit in. `close`
/// cannot replace it either, because `close` ends the runtime. To come back
/// after a `close` needs a new `connect` call, and the empty core of that
/// runtime holds none of the edits from the offline interval.
///
/// The function does nothing unless the document is connected, so an interface
/// can bind it directly to a toggle:
///
/// ```gleam
/// case offline {
///   True -> watershed.go_offline(doc)
///   False -> watershed.go_online(doc)
/// }
/// ```
///
/// While the document is offline, `diagnostics(doc).phase` is `"reconnecting"`,
/// and `in_flight_count` is the number of edits that wait to reach the server.
/// An indicator that reads "3 changes not yet saved" needs that count.
pub fn go_offline(document: Document(root)) -> Nil {
  runtime.go_offline(document.runtime)
}

@target(javascript)
/// Return from `go_offline`. The client replays the interval and sends the edits
/// from it. The function does nothing unless the document is offline now.
pub fn go_online(document: Document(root)) -> Nil {
  runtime.go_online(document.runtime)
}

@target(javascript)
/// The id that the server assigned to this client. The result is `None` until
/// the first handshake completes.
///
/// You need this id to find your own identity in a list from *another*
/// component. A consensus kernel reports its membership as the integer ids that
/// it uses to tie-break. `pact_map_pending_signoffs` of a `PactMap` is one
/// example. Without this id you cannot find the entry of your own tab. Convert
/// the id with `watershed/client_id.to_int`. That function performs the same
/// derivation as the runtime and the kernels, so the two results always
/// agree.
///
/// ```gleam
/// let mine = watershed.client_id(doc) |> option.map(client_id.to_int)
/// let waiting_on_me = case mine, pact_map_pending_signoffs(pact, "bpm") {
///   Some(me), Some(ids) -> list.contains(ids, me)
///   _, _ -> False
/// }
/// ```
///
/// Read this id again after a reconnect. Do not cache it. The new handshake can
/// assign a different id, and a stale id then matches nothing, and it reports
/// nothing.
pub fn client_id(document: Document(root)) -> Option(String) {
  runtime.client_id(document.runtime)
}

@target(javascript)
/// An inbound ephemeral ripple. A ripple belongs to one document, it does not
/// sequence, and no server stores it. Use a ripple for transient presence,
/// which is a cursor, a selection, or a typing indicator. Such data must
/// **not** go into a DDS.
pub type Ripple =
  SignalMessage

@target(javascript)
/// Broadcast an ephemeral ripple to every other connected client. A ripple has
/// a `type` tag and any JSON `content`. It expects no reply, and it has no
/// order, no ack, and no catch-up. The function does nothing until the first
/// handshake assigns a client id.
pub fn submit_ripple(
  document: Document(root),
  ripple_type ripple_type: String,
  content content: Json,
) -> Nil {
  runtime.send_ripple(document.runtime, ripple_type, content)
}

@target(javascript)
/// Register a callback for every inbound ripple on the document.
pub fn subscribe_ripples(
  document: Document(root),
  handler: fn(Ripple) -> Nil,
) -> Nil {
  runtime.subscribe_ripples(document.runtime, handler)
}

@target(javascript)
/// The `type` tag of the ripple, if the ripple has one.
pub fn ripple_type(ripple: Ripple) -> Option(String) {
  ripple.signal_type
}

@target(javascript)
/// The JSON payload of the ripple, as a `Dynamic` value, for the caller to
/// decode.
pub fn ripple_content(ripple: Ripple) -> Dynamic {
  ripple.content
}

@target(javascript)
/// The id of the client that sent the ripple, if the server stamped one. The
/// result is `None` for a ripple that the server produced.
pub fn ripple_client_id(ripple: Ripple) -> Option(String) {
  ripple.client_id
}

@target(javascript)
/// Whether the document is caught up, which is true when the server acked every
/// local edit. The confirmed state is then complete and stable. Use this
/// function to wait for a quiet document before you summarize it.
pub fn is_synced(document: Document(root)) -> Bool {
  runtime.is_synced(document.runtime)
}

@target(javascript)
/// Take a snapshot of the connection state and the sequencing state of the
/// document runtime.
pub fn diagnostics(document: Document(root)) -> Diagnostics {
  runtime.diagnostics(document.runtime)
}

@target(javascript)
/// Summarize the current confirmed state of the document to the storage of
/// floodgate. A later client can then start from that snapshot, and it does not
/// replay the full op history. The promise resolves with the summary handle,
/// which is a git tree SHA. The connection must be synchronized, and the token
/// must carry the `summary:write` scope.
pub fn summarize(document: Document(root)) -> Promise(Result(String, String)) {
  runtime.summarize(document.runtime)
}

@target(javascript)
/// Let this client summarize the document without a request, under `policy`.
///
/// Without this function nothing summarizes, and every client that joins
/// replays the whole log. You must then call `summarize` by hand. With this
/// function, the runtime writes a checkpoint after the document moves past the
/// threshold of the policy and this client is settled. A later join thus costs
/// the recent history, and not all of it.
///
/// It is safe to install the policy on every client in a room. The attempts
/// spread across a delay window, and the first summary that sequences stops the
/// other attempts. A lost race costs one unnecessary upload.
///
/// The token must carry the `summary:write` scope, which `connect` includes by
/// default. The policy applies from the next sequenced op.
pub fn auto_summarize(
  document: Document(root),
  policy: summary_policy.Policy,
) -> Nil {
  runtime.auto_summarize(document.runtime, Some(policy))
}

@target(javascript)
/// Stop the automatic summaries. An attempt that is already scheduled still
/// checks again before it acts, and it then finds no policy.
pub fn stop_auto_summarize(document: Document(root)) -> Nil {
  runtime.auto_summarize(document.runtime, None)
}

@target(javascript)
/// The number of ops that sequenced after the newest summary that this client
/// knows about. An automatic policy compares that number with its threshold,
/// and a client that joins replays those ops on top of the checkpoint.
///
/// On a document that no client has summarized, this number is the whole
/// log.
pub fn ops_since_summary(document: Document(root)) -> Int {
  runtime.ops_since_summary(document.runtime)
}

@target(javascript)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. Each `summarize` call
/// stores one version, and a new connection starts from the newest one. The
/// token must carry the `doc:read` scope.
pub fn get_versions(
  document: Document(root),
  count count: Int,
) -> Promise(Result(List(SummaryVersion), String)) {
  runtime.get_versions(document.runtime, count)
}

@target(javascript)
/// Read the confirmed state that a summary version captured, by the handle of
/// that version. `get_versions` and the resolution of `summarize` both give a
/// handle. The function returns the stored snapshot blob, which holds the
/// entries in insertion order with the sequence number that the writer captured
/// them at. The read is at one point in time, and it does not change the live
/// document.
pub fn load_version(
  document: Document(root),
  handle handle: String,
) -> Promise(Result(SummaryBlob, String)) {
  runtime.load_version(document.runtime, handle)
}

// ── Edits (optimistic) ───────────────────────────────────────────────────────

@target(javascript)
pub fn set(map: SharedMap, key: String, value: Json) -> Nil {
  runtime.set(map.runtime, map.address, key, value)
}

@target(javascript)
pub fn delete(map: SharedMap, key: String) -> Nil {
  runtime.delete(map.runtime, map.address, key)
}

@target(javascript)
pub fn clear(map: SharedMap) -> Nil {
  runtime.clear(map.runtime, map.address)
}

// ── Reads ────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn get(map: SharedMap, key: String) -> Option(Json) {
  runtime.get(map.runtime, map.address, key)
}

@target(javascript)
pub fn has(map: SharedMap, key: String) -> Bool {
  get(map, key) != None
}

@target(javascript)
pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  runtime.entries(map.runtime, map.address)
}

@target(javascript)
pub fn keys(map: SharedMap) -> List(String) {
  runtime.keys(map.runtime, map.address)
}

@target(javascript)
pub fn size(map: SharedMap) -> Int {
  runtime.size(map.runtime, map.address)
}

// ── Events ───────────────────────────────────────────────────────────────────

@target(javascript)
/// Register a callback for every local change and remote change to this map
/// channel. The handler receives a `map_kernel.MapEvent` value, and it receives
/// no other kind of event.
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
/// Subscribe to the whole-map events of a typed map, and stay in the typed API.
/// `handler` receives a `map_kernel.MapEvent` value and no other kind of event,
/// the same as in `subscribe`. Use `subscribe_field` instead to watch one typed
/// field.
pub fn subscribe_typed(
  typed_map: TypedMap(s),
  handler: fn(map_kernel.MapEvent) -> Nil,
) -> Nil {
  subscribe(typed_map.map, handler)
}

@target(javascript)
/// Convert a channel event from the fan-out into a typed change for `field`,
/// which is under `key`. The result is `None` when the event is for another
/// key, and when it is for another channel kind.
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
/// Subscribe to the changes of one typed field. Every local or remote write to
/// the key of `field` calls `handler` with a `FieldChange` value. That value
/// carries the new value and the previous value, both decoded at the boundary.
/// Each one is `Error(Invalid)` when a peer wrote a value that does not match
/// the field type. A `Cleared` event on the map arrives as
/// `FieldChange(Ok(None), Ok(None), local)`, because a clear carries no previous
/// value for each key.
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  handler: fn(FieldChange(a)) -> Nil,
) -> Nil {
  let key = schema.field_key(field)
  runtime.subscribe(typed_map.map.runtime, typed_map.map.address, fn(event) {
    case field_change(field, key, event) {
      Some(change) -> handler(change)
      None -> Nil
    }
  })
}

// ── Demo helpers ─────────────────────────────────────────────────────────────

@target(javascript)
/// Mint an HS256 development JWT for `just server`, which runs in development
/// mode. The function signs with Web Crypto, so the token resolves
/// asynchronously. Do not use this function in production. The tenant secret
/// must never reach the browser there.
pub fn dev_token(
  secret secret: String,
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
) -> Promise(String) {
  transport_js.mint_dev_token(secret, tenant, document, user_id)
}
