//// Public BEAM API: connect to a floodgate document and edit its root
//// SharedMap. The JavaScript counterpart is `watershed`.
////
//// ```gleam
//// use document <- result.try(watershed_beam.connect(
////   host: "localhost", port: 4000,
////   tenant: "default", document: "dice",
////   token: jwt, user_id: "user-1",
//// ))
//// let map = watershed_beam.root(document)
//// watershed_beam.set(map, "die", json.int(4))
//// let value = watershed_beam.get(map, "die")
//// let events = watershed_beam.subscribe(map)
//// ```
////
//// A read is optimistic: the local pending edits go over the sequenced state.
//// The server sequencing guarantees that the replicas converge.
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
import lattice_sequence/sequence.{After, Before}

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
import watershed/ordered_collection_kernel
@target(erlang)
import watershed/pact_map_kernel
@target(erlang)
import watershed/pn_counter_kernel
@target(erlang)
import watershed/register_collection_kernel.{type ReadPolicy, Atomic}
@target(erlang)
import watershed/rich_text
@target(erlang)
import watershed/rich_text_kernel
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
  type FieldError,
}
@target(erlang)
import watershed/sequence_kernel
@target(erlang)
import watershed/summary_policy
@target(erlang)
import watershed/task_manager_kernel
@target(erlang)
import watershed/text_kernel
@target(erlang)
import watershed/two_p_set_kernel
@target(erlang)
import watershed/wire
@target(erlang)
import watershed/wire/summary_blob.{type SummaryBlob}

@target(erlang)
/// The default Phoenix websocket mount for floodgate. `vsn=2.0.0` selects the
/// V2 array frame serializer that the roost codec speaks.
const socket_path = "/socket/websocket?vsn=2.0.0"

@target(erlang)
const call_timeout_milliseconds = 5000

@target(erlang)
pub opaque type Document(root) {
  Document(runtime: Subject(runtime_beam.Msg))
}

@target(erlang)
pub opaque type SharedMap {
  SharedMap(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type SharedCounter {
  SharedCounter(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type JsonOt {
  JsonOt(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type SharedRichText {
  SharedRichText(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type OrMap {
  OrMap(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type OrSet {
  OrSet(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type RegisterCollection {
  RegisterCollection(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type Claims {
  Claims(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type TaskManager {
  TaskManager(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type GSet {
  GSet(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type TwoPSet {
  TwoPSet(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type SharedDirectory {
  SharedDirectory(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type PnCounter {
  PnCounter(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type PactMap {
  PactMap(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type OrderedCollection {
  OrderedCollection(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type SharedSequence {
  SharedSequence(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
pub opaque type SharedText {
  SharedText(runtime: Subject(runtime_beam.Msg), address: String)
}

@target(erlang)
/// A stable position in the optimistic string of a `SharedText` value. It stays
/// correct across concurrent edits and merges. The type is opaque, so a caller
/// must use `text_anchor_at`, `text_start_anchor`, `text_end_anchor`, or
/// `text_anchor_from_json` to construct one.
pub type TextAnchor =
  text_kernel.TextAnchor

@target(erlang)
/// The grapheme that a `TextAnchor` value binds to across a concurrent insert
/// at its gap. `bias_before` binds it to the grapheme after the gap, so an
/// insert at the gap moves the anchor to the right. `bias_after` binds it to
/// the grapheme before the gap, so an insert at the gap goes after the anchor.
/// This type is re-exported here, so a caller needs no direct dependency on
/// `lattice_sequence` to build an anchor.
pub type Bias =
  text_kernel.Bias

@target(erlang)
pub const bias_before: Bias = Before

@target(erlang)
pub const bias_after: Bias = After

@target(erlang)
/// Connect to a document. The function waits until the handshake completes and
/// the client replays the full operation history.
pub fn connect(
  host host: String,
  port port: Int,
  tenant tenant: String,
  document document: String,
  token token: String,
  user_id user_id: String,
) -> Result(Document(root), String) {
  let connect_message =
    build_connect_message(tenant, document, user_id, Some(token))

  case
    runtime_beam.start(
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
      case runtime_beam.await_ready(subject) {
        Ok(Nil) -> Ok(Document(runtime: subject))
        Error(reason) -> {
          process.send(subject, runtime_beam.Shutdown)
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
/// Connect through an injected transport. The in-memory `sluice` test driver
/// uses this seam. Unlike `connect`, this function does *not* wait for the
/// handshake. The sluice completes that handshake on the first `settle` call.
/// Do not use this function in production.
pub fn connect_via(
  tenant tenant: String,
  document document: String,
  user_id user_id: String,
  transport transport: runtime_beam.Transport,
) -> Result(Document(root), String) {
  let connect_message = build_connect_message(tenant, document, user_id, None)
  case
    runtime_beam.start_with_transport(
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
/// The runtime actor behind a document. This function is public for the
/// `sluice` test driver, which applies a barrier to that actor. A synchronous
/// call empties the mailbox of the actor, and the delivery is thus
/// deterministic. This function is not part of the API for an application.
pub fn runtime_subject(document: Document(root)) -> Subject(runtime_beam.Msg) {
  document.runtime
}

@target(erlang)
/// The root map of the document, at the channel address `"root"`.
pub fn root(document: Document(root)) -> SharedMap {
  SharedMap(runtime: document.runtime, address: "root")
}

@target(erlang)
/// Create a new map channel. The map starts *detached*, which means that it is
/// local only and its edits produce no operation. It stays detached until a
/// caller stores its handle, from `handle_of`, into an attached map. The
/// runtime then attaches it, with its snapshot, and it starts to synchronize
/// the edits of that map.
pub fn create_map(document: Document(root)) -> Result(SharedMap, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateMap,
  )
  |> result.map(fn(address) {
    SharedMap(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `map`. Store it as a value in
/// another map. Its shape is
/// `{"type": "__fluid_handle__", "url": "/<address>"}`.
pub fn handle_of(map: SharedMap) -> Json {
  handle.encode_handle(map.address)
}

@target(erlang)
/// Whether a value that you read from a map is a handle marker. See
/// `resolve`.
pub fn is_handle(value: Json) -> Bool {
  handle.parse_handle(value) != Error(Nil)
}

@target(erlang)
/// Resolve a handle value, from `get` or from `entries`, to the SharedMap that
/// it references. A caller can retry after an error. A handle from a remote
/// value can stay unresolved for a short time, while the attach operation of
/// the channel that it references is still in flight.
pub fn resolve(
  document: Document(root),
  value: Json,
) -> Result(SharedMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedMap(runtime: document.runtime, address: address)
      })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed maps
//
// An opt-in, phantom-typed view over a SharedMap. `schema` is constrained by
// inference the first time a `Field(schema, _)` is used against the map, so a
// field from one schema cannot be applied to a map of another. Typing is a
// decode boundary (remote peers may write anything), so reads return `Result`.
// See `watershed/schema` for defining fields.
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// A SharedMap value, viewed through a schema `s`.
pub opaque type TypedMap(s) {
  TypedMap(map: SharedMap)
}

@target(erlang)
/// View a raw map through a schema. The use of the result selects the schema,
/// and an annotation can also select it, for example
/// `let players: TypedMap(Roster) = typed(map)`.
pub fn typed(map: SharedMap) -> TypedMap(s) {
  TypedMap(map: map)
}

@target(erlang)
/// The raw map below the typed view, to return to the untyped API.
pub fn untyped(typed_map: TypedMap(s)) -> SharedMap {
  typed_map.map
}

@target(erlang)
/// The root map of the document, viewed through the schema of that document.
///
/// One document has one tag. The tag comes from the `Document(root)` value that
/// you pass, so it is fixed at the position where your application writes the
/// type concretely. That position is the function that receives the connected
/// document, or the state record that holds it:
///
/// ```gleam
/// fn run(document: watershed_beam.Document(GameRoot)) -> Nil
/// ```
///
/// Every `root_typed` call on that document then agrees. A second schema at the
/// root is a compile error, and not a key namespace that two schemas share
/// quietly.
///
/// A caller that is generic in `root` can still call this function. But an
/// abstract tag has no field, so that caller cannot read or write the root.
///
/// `typed(root(document))` is still available, and it is still unchecked. It is
/// the deliberate way to view the root through a foreign schema. Unlike the old
/// signature, you must now write it explicitly.
pub fn root_typed(document: Document(root)) -> TypedMap(root) {
  typed(root(document))
}

@target(erlang)
/// Create a new detached map, viewed through a schema. The lifecycle is the
/// same as for `create_map`.
pub fn create_typed_map(
  document: Document(root),
) -> Result(TypedMap(s), String) {
  create_map(document) |> result.map(typed)
}

@target(erlang)
/// Write a typed field optimistically.
pub fn set_field(typed_map: TypedMap(s), field: Field(s, a), value: a) -> Nil {
  set(typed_map.map, schema.field_key(field), schema.encode_value(field, value))
}

@target(erlang)
/// Delete a typed field optimistically.
pub fn delete_field(typed_map: TypedMap(s), field: Field(s, a)) -> Nil {
  delete(typed_map.map, schema.field_key(field))
}

@target(erlang)
/// Read a typed field. The result is `Ok(None)` when the key is absent, and
/// `Error(Invalid)` when the stored value does not decode to the type `a`.
pub fn get_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
) -> Result(Option(a), FieldError) {
  case get(typed_map.map, schema.field_key(field)) {
    Error(Nil) -> Ok(None)
    Ok(stored) -> schema.decode_value(field, stored) |> result.map(Some)
  }
}

@target(erlang)
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

@target(erlang)
/// Whether a typed field is present. The function does not check that the
/// value decodes.
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
    Error(Nil) -> Ok(None)
    Ok(value) ->
      resolve(document, value)
      |> result.map(fn(resolved) { Some(typed(resolved)) })
  }
}

@target(erlang)
/// Read the whole map as a typed record, through a schema. The function returns
/// one `Result` value, after the version check and the seal check of that
/// schema. See `watershed/schema`.
pub fn read(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
) -> Result(record, FieldError) {
  schema.decode_entries(map_schema, entries(typed_map.map))
}

@target(erlang)
/// Write a whole record through a schema, as one operation for each key.
/// Concurrent edits to two other keys thus still merge, and the record view
/// never overwrites the whole map. An optional prop with the value `None`
/// deletes its key.
pub fn write(
  typed_map: TypedMap(s),
  map_schema: schema.Schema(s, record),
  value: record,
) -> Nil {
  list.each(schema.encode_operations(map_schema, value), fn(operation) {
    case operation {
      schema.Put(key, entry_value) -> set(typed_map.map, key, entry_value)
      schema.Delete(key) -> delete(typed_map.map, key)
    }
  })
}

@target(erlang)
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

@target(erlang)
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, kind),
  resolver: fn(Document(root), Json) -> Result(shared, String),
) -> Result(Option(shared), String) {
  case get(typed_map.map, schema.channel_field_key(field)) {
    Error(Nil) -> Ok(None)
    Ok(value) -> resolver(document, value) |> result.map(Some)
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
) -> Result(Option(JsonOt), String) {
  get_channel_field(document, typed_map, field, resolve_json_ot)
}

@target(erlang)
/// Store a handle to `rich_text` under a typed channel field.
pub fn set_rich_text_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
  rich_text: SharedRichText,
) -> Nil {
  put_channel_field(typed_map, field, rich_text_handle_of(rich_text))
}

@target(erlang)
/// Resolve the rich-text channel referenced by a typed channel field.
pub fn resolve_rich_text_field(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
) -> Result(Option(SharedRichText), String) {
  get_channel_field(document, typed_map, field, resolve_rich_text)
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
) -> Result(Option(SharedSequence), String) {
  get_channel_field(document, typed_map, field, resolve_sequence)
}

@target(erlang)
/// Store a handle to `text` under a typed channel field.
pub fn set_text_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  text: SharedText,
) -> Nil {
  put_channel_field(typed_map, field, text_handle_of(text))
}

@target(erlang)
/// Resolve the text channel referenced by a typed channel field.
pub fn resolve_text_field(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
) -> Result(Option(SharedText), String) {
  get_channel_field(document, typed_map, field, resolve_text)
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
) -> Result(Option(TwoPSet), String) {
  get_channel_field(document, typed_map, field, resolve_two_p_set)
}

@target(erlang)
/// Store a handle to `directory` under a typed channel field.
pub fn set_directory_field(
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
  directory: SharedDirectory,
) -> Nil {
  put_channel_field(typed_map, field, directory_handle_of(directory))
}

@target(erlang)
/// Resolve the directory referenced by a typed channel field.
pub fn resolve_directory_field(
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
const resolve_retry_milliseconds = 200

@target(erlang)
const resolve_attempts = 25

@target(erlang)
/// Block until every local edit is acked (the confirmed root is stable),
/// bounded by the resolve budget, then return regardless.
fn await_synced(document: Document(root), attempts: Int) -> Nil {
  case attempts <= 0 || is_synced(document) {
    True -> Nil
    False -> {
      process.sleep(resolve_retry_milliseconds)
      await_synced(document, attempts - 1)
    }
  }
}

@target(erlang)
/// Resolve a field to its channel, retrying while the handle is absent or the
/// referenced channel's attach operation is still in flight.
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
      process.sleep(resolve_retry_milliseconds)
      resolve_with_retry(resolve, attempts - 1)
    }
  }
}

@target(erlang)
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
/// Make sure that a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document(root),
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
/// Make sure that a counter exists under `field`. If the slot is empty, the
/// function creates one.
pub fn ensure_counter(
  document: Document(root),
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
  document: Document(root),
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
/// Ensure a rich-text channel exists under `field`.
pub fn ensure_rich_text(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
) -> Result(SharedRichText, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use rich_text <- result.map(create_rich_text(document))
      set_rich_text_field(typed_map, field, rich_text)
    },
    fn() { resolve_rich_text_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Make sure that an OR-map exists under `field`. If none exists, the function
/// creates one in `mode`.
pub fn ensure_or_map(
  document: Document(root),
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
/// Make sure that an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document(root),
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
  document: Document(root),
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
/// Ensure a text channel exists under `field`, seeding an empty one if the
/// slot is empty.
pub fn ensure_text(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
) -> Result(SharedText, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use text <- result.map(create_text(document))
      set_text_field(typed_map, field, text)
    },
    fn() { resolve_text_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Make sure that a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document(root),
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
/// Make sure that a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document(root),
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
/// Make sure that a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
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
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
) -> Result(SharedDirectory, String) {
  ensure_channel(
    document,
    typed_map,
    schema.channel_field_key(field),
    fn() {
      use directory <- result.map(create_directory(document))
      set_directory_field(typed_map, field, directory)
    },
    fn() { resolve_directory_field(document, typed_map, field) },
  )
}

@target(erlang)
/// Make sure that a PN-counter exists under `field`. If the slot is empty, the
/// function creates one.
pub fn ensure_pn_counter(
  document: Document(root),
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
/// Make sure that a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document(root),
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
/// Make sure that an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document(root),
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
/// Make sure that a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document(root),
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

// ─────────────────────────────────────────────────────────────────────────────
// Counters
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new counter channel. The detached lifecycle is the same as for
/// `create_map`. The channel is local only, until a caller stores its handle,
/// from `counter_handle_of`, into an attached map.
pub fn create_counter(
  document: Document(root),
) -> Result(SharedCounter, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateCounter,
  )
  |> result.map(fn(address) {
    SharedCounter(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `counter`. Store it as a value in a
/// map. See `handle_of`.
pub fn counter_handle_of(counter: SharedCounter) -> Json {
  handle.encode_handle(counter.address)
}

@target(erlang)
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
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Increment the counter optimistically. A negative amount decrements it.
pub fn increment(counter: SharedCounter, amount: Int) -> Nil {
  process.send(
    counter.runtime,
    runtime_beam.IncrementCounter(counter.address, amount),
  )
}

@target(erlang)
/// The current optimistic value of the counter. The result is `Error(Nil)` when the
/// address does not name a counter channel.
pub fn counter_value(counter: SharedCounter) -> Result(Int, Nil) {
  process.call(
    counter.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetCounterValue(counter.address, reply) },
  )
}

@target(erlang)
/// Subscribe to the events of a channel, and forward only the events that
/// `narrow` accepts to a new subject that the caller owns. The function decodes
/// each one to the event type of that channel kind. The `subscribe_*` function
/// of each kind uses this function, so a subscriber sees the events of its own
/// channel only, and never the union of 14 variants.
fn subscribe_narrowed(
  runtime_subject: Subject(runtime_beam.Msg),
  address: String,
  narrow: fn(ChannelEvent) -> Option(a),
) -> Subject(a) {
  let subject = process.new_subject()
  process.send(
    runtime_subject,
    runtime_beam.Subscribe(address, fn(event) {
      case narrow(event) {
        Some(inner) -> process.send(subject, inner)
        None -> Nil
      }
    }),
  )
  subject
}

@target(erlang)
/// Subscribe the calling process to the events of this counter, both local and
/// remote. The subject carries a `counter_kernel.CounterEvent` value, and it
/// carries no other kind of event.
pub fn subscribe_counter(
  counter: SharedCounter,
) -> Subject(counter_kernel.CounterEvent) {
  use event <- subscribe_narrowed(counter.runtime, counter.address)
  case event {
    channel.CounterEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON-OT (json0)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new json0 channel, which uses JSON operational transform. The
/// detached lifecycle is the same as for `create_map`. The channel is local
/// only, until a caller stores its handle, from `json_ot_handle_of`, into an
/// attached map.
pub fn create_json_ot(document: Document(root)) -> Result(JsonOt, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateJsonOt,
  )
  |> result.map(fn(address) {
    JsonOt(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `json_ot`. Store it as a value in a
/// map. See `handle_of`.
pub fn json_ot_handle_of(json_ot: JsonOt) -> Json {
  handle.encode_handle(json_ot.address)
}

@target(erlang)
/// Resolve a handle value to the JsonOt value that it references. The function
/// checks that the channel exists, and it does not check the channel type. A
/// caller can retry after an error, the same as for `resolve`.
pub fn resolve_json_ot(
  document: Document(root),
  value: Json,
) -> Result(JsonOt, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        JsonOt(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Submit a json0 operation to the channel, optimistically. An operation is a
/// list of components.
pub fn submit_json_ot(json_ot: JsonOt, operation: json_ot.Operation) -> Nil {
  process.send(
    json_ot.runtime,
    runtime_beam.SubmitJsonOt(json_ot.address, operation),
  )
}

@target(erlang)
/// The current optimistic document of the json0 channel. The result is `Error(Nil)`
/// when the address does not name a json0 channel.
pub fn json_ot_view(json_ot: JsonOt) -> Result(json_ot.JsonValue, Nil) {
  process.call(
    json_ot.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetJsonOtView(json_ot.address, reply) },
  )
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
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared rich text
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new rich-text channel. The detached lifecycle is the same as for
/// `create_map`.
pub fn create_rich_text(
  document: Document(root),
) -> Result(SharedRichText, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateRichText,
  )
  |> result.map(fn(address) {
    SharedRichText(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `rich_text`. Store it as a value in a
/// map. See `handle_of`.
pub fn rich_text_handle_of(rich_text: SharedRichText) -> Json {
  handle.encode_handle(rich_text.address)
}

@target(erlang)
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
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedRichText(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Submit a rich-text delta to the channel, optimistically.
pub fn submit_rich_text(
  rich_text: SharedRichText,
  delta: rich_text.Delta,
) -> Nil {
  process.send(
    rich_text.runtime,
    runtime_beam.SubmitRichText(rich_text.address, delta),
  )
}

@target(erlang)
/// The current optimistic rich-text document of the channel. The result is
/// `Error(Nil)` when the address does not name a rich-text channel.
pub fn rich_text_view(
  rich_text: SharedRichText,
) -> Result(rich_text.Document, Nil) {
  process.call(
    rich_text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetRichTextView(rich_text.address, reply)
    },
  )
}

@target(erlang)
/// Subscribe the calling process to this rich-text channel's local and remote
/// change events.
pub fn subscribe_rich_text(
  rich_text: SharedRichText,
) -> Subject(rich_text_kernel.RichTextEvent) {
  use event <- subscribe_narrowed(rich_text.runtime, rich_text.address)
  case event {
    channel.RichTextEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-maps
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new OR-map channel, in tally mode or in register mode. The detached
/// lifecycle is the same as for `create_map`. The channel is local only, until
/// a caller stores its handle into an attached container.
pub fn create_or_map(
  document: Document(root),
  mode: OrMapMode,
) -> Result(OrMap, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.CreateOrMap(mode, reply) },
  )
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
  document: Document(root),
  value: Json,
) -> Result(OrMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { OrMap(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
pub fn or_map_increment(or_map: OrMap, key: String, amount: Int) -> Nil {
  process.send(
    or_map.runtime,
    runtime_beam.IncrementOrMap(or_map.address, key, amount),
  )
}

@target(erlang)
pub fn or_map_set(or_map: OrMap, key: String, value: String) -> Nil {
  process.send(
    or_map.runtime,
    runtime_beam.SetOrMapKey(or_map.address, key, value),
  )
}

@target(erlang)
pub fn or_map_set_json(or_map: OrMap, key: String, value: Json) -> Nil {
  or_map_set(or_map, key, json.to_string(value))
}

@target(erlang)
pub fn or_map_remove(or_map: OrMap, key: String) -> Nil {
  process.send(or_map.runtime, runtime_beam.RemoveOrMapKey(or_map.address, key))
}

@target(erlang)
pub fn or_map_value(or_map: OrMap, key: String) -> Result(OrMapValue, Nil) {
  process.call(
    or_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetOrMapValue(or_map.address, key, reply)
    },
  )
}

@target(erlang)
pub fn or_map_entries(or_map: OrMap) -> List(#(String, OrMapValue)) {
  process.call(
    or_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetOrMapEntries(or_map.address, reply) },
  )
}

@target(erlang)
pub fn or_map_keys(or_map: OrMap) -> List(String) {
  process.call(
    or_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetOrMapKeys(or_map.address, reply) },
  )
}

@target(erlang)
pub fn subscribe_or_map(or_map: OrMap) -> Subject(or_map_kernel.OrMapEvent) {
  use event <- subscribe_narrowed(or_map.runtime, or_map.address)
  case event {
    channel.OrMapEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-sets
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new observed-remove set channel, for string elements.
pub fn create_or_set(document: Document(root)) -> Result(OrSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateOrSet,
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
  document: Document(root),
  value: Json,
) -> Result(OrSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { OrSet(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
pub fn or_set_add(or_set: OrSet, element: String) -> Nil {
  process.send(
    or_set.runtime,
    runtime_beam.AddOrSetElement(or_set.address, element),
  )
}

@target(erlang)
pub fn or_set_remove(or_set: OrSet, element: String) -> Nil {
  process.send(
    or_set.runtime,
    runtime_beam.RemoveOrSetElement(or_set.address, element),
  )
}

@target(erlang)
pub fn or_set_contains(or_set: OrSet, element: String) -> Bool {
  process.call(
    or_set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.OrSetContains(or_set.address, element, reply)
    },
  )
}

@target(erlang)
pub fn or_set_values(or_set: OrSet) -> List(String) {
  process.call(
    or_set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetOrSetValues(or_set.address, reply) },
  )
}

@target(erlang)
pub fn subscribe_or_set(or_set: OrSet) -> Subject(or_set_kernel.OrSetEvent) {
  use event <- subscribe_narrowed(or_set.runtime, or_set.address)
  case event {
    channel.OrSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sequences
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_sequence(
  document: Document(root),
) -> Result(SharedSequence, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateSequence,
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
  document: Document(root),
  value: Json,
) -> Result(SharedSequence, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_beam.resolve_sequence(document.runtime, address)
      |> result.map(fn(_) {
        SharedSequence(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Insert `value` at `index`, counted from zero, in the range `0` to the length
/// of the sequence.
pub fn sequence_insert(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.InsertSequenceItem(sequence.address, index, value, reply)
    },
  )
}

@target(erlang)
/// Delete the value at `index`, counted from zero, in the range `0` to
/// `length - 1`.
pub fn sequence_delete(
  sequence: SharedSequence,
  index: Int,
) -> Result(Nil, String) {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DeleteSequenceItem(sequence.address, index, reply)
    },
  )
}

@target(erlang)
/// Move a value between two indexes, counted from zero. The function reads the
/// destination index after it removes the value from the source index.
pub fn sequence_move(
  sequence: SharedSequence,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String) {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.MoveSequenceItem(
        sequence.address,
        from_index,
        to_index,
        reply,
      )
    },
  )
}

@target(erlang)
/// Replace the value at `index`, counted from zero, as one collaborative
/// operation.
pub fn sequence_replace(
  sequence: SharedSequence,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.ReplaceSequenceItem(sequence.address, index, value, reply)
    },
  )
}

@target(erlang)
pub fn sequence_values(sequence: SharedSequence) -> List(Json) {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetSequenceValues(sequence.address, reply)
    },
  )
}

@target(erlang)
pub fn sequence_length(sequence: SharedSequence) -> Int {
  process.call(
    sequence.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetSequenceLength(sequence.address, reply)
    },
  )
}

@target(erlang)
pub fn subscribe_sequence(
  sequence: SharedSequence,
) -> Subject(sequence_kernel.SequenceEvent) {
  use event <- subscribe_narrowed(sequence.runtime, sequence.address)
  case event {
    channel.SequenceEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared text
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_text(document: Document(root)) -> Result(SharedText, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateText,
  )
  |> result.map(fn(address) {
    SharedText(runtime: document.runtime, address: address)
  })
}

@target(erlang)
pub fn text_handle_of(text: SharedText) -> Json {
  handle.encode_handle(text.address)
}

@target(erlang)
pub fn resolve_text(
  document: Document(root),
  value: Json,
) -> Result(SharedText, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      runtime_beam.resolve_text(document.runtime, address)
      |> result.map(fn(_) {
        SharedText(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Insert `value` at the grapheme `index`, counted from zero, in the range `0`
/// to the length of the text. To insert `""` changes nothing. The function then
/// returns `Ok(Nil)`, and it emits no event and submits no channel operation.
pub fn text_insert(
  text: SharedText,
  index: Int,
  value: String,
) -> Result(Nil, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.InsertText(text.address, index, value, reply)
    },
  )
}

@target(erlang)
/// Delete the graphemes in `[start, end)`. An empty range, where
/// `start == end`, changes nothing.
pub fn text_delete_range(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(Nil, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DeleteRangeText(text.address, start, end, reply)
    },
  )
}

@target(erlang)
/// Replace the graphemes in `[start, end)` with `value`, as one collaborative
/// operation. To replace an empty range with `""` changes nothing.
pub fn text_replace_range(
  text: SharedText,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.ReplaceRangeText(text.address, start, end, value, reply)
    },
  )
}

@target(erlang)
/// Append `value` to the end of the text. To append `""` changes nothing.
pub fn text_append(text: SharedText, value: String) -> Result(Nil, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.AppendText(text.address, value, reply) },
  )
}

@target(erlang)
/// The current visible optimistic string of the text.
pub fn text_value(text: SharedText) -> String {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetTextValue(text.address, reply) },
  )
}

@target(erlang)
/// The current optimistic grapheme count of the text.
pub fn text_length(text: SharedText) -> Int {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetTextLength(text.address, reply) },
  )
}

@target(erlang)
/// The graphemes in `[start, end)` of the optimistic string of the text. The
/// result is an error string when the range `start..end` is invalid.
pub fn text_substring(
  text: SharedText,
  start: Int,
  end: Int,
) -> Result(String, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetTextSubstring(text.address, start, end, reply)
    },
  )
}

@target(erlang)
/// Create a stable anchor at the gap before/after the optimistic grapheme
/// at `index`, per `bias` (see `bias_before`/`bias_after`). An explicit
/// error string on an out-of-bounds index.
pub fn text_anchor_at(
  text: SharedText,
  index: Int,
  bias: Bias,
) -> Result(TextAnchor, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.TextAnchorAt(text.address, index, bias, reply)
    },
  )
}

@target(erlang)
/// Resolve an anchor to its current optimistic grapheme index. An explicit
/// error string on a stale/unknown anchor target (the holder should
/// re-anchor).
pub fn text_resolve_anchor(
  text: SharedText,
  anchor: TextAnchor,
) -> Result(Int, String) {
  process.call(
    text.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.TextResolveAnchor(text.address, anchor, reply)
    },
  )
}

@target(erlang)
/// An anchor at the start of the text. Always resolves to `0`.
pub fn text_start_anchor() -> TextAnchor {
  runtime_beam.text_start_anchor()
}

@target(erlang)
/// An anchor at the end of the text. Always resolves to the current
/// grapheme length, tracking growth.
pub fn text_end_anchor() -> TextAnchor {
  runtime_beam.text_end_anchor()
}

@target(erlang)
/// Encode an anchor as a self-describing JSON value, for example to send it
/// through presence for a shared cursor.
pub fn text_anchor_to_json(anchor: TextAnchor) -> Json {
  runtime_beam.text_anchor_to_json(anchor)
}

@target(erlang)
/// Decode an anchor from a JSON string produced by `text_anchor_to_json`.
/// An explicit error string on malformed JSON.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(TextAnchor, String) {
  runtime_beam.text_anchor_from_json(json_string)
}

@target(erlang)
/// Subscribe the calling process to the events of this text channel, both local
/// and remote. The subject carries a `text_kernel.TextEvent` value, and it
/// carries no other kind of event.
pub fn subscribe_text(text: SharedText) -> Subject(text_kernel.TextEvent) {
  use event <- subscribe_narrowed(text.runtime, text.address)
  case event {
    channel.TextEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register collections
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new consensus register collection. Like other non-root channels it
/// starts detached until its handle is stored in an attached map.
pub fn create_register_collection(
  document: Document(root),
) -> Result(RegisterCollection, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateRegisterCollection,
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
  document: Document(root),
  value: Json,
) -> Result(RegisterCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
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
    runtime_beam.WriteRegister(collection.address, key, value),
  )
}

@target(erlang)
pub fn register_read(
  collection: RegisterCollection,
  key: String,
  policy: ReadPolicy,
) -> Result(Json, Nil) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetRegisterValue(collection.address, key, policy, reply)
    },
  )
}

@target(erlang)
pub fn register_get(
  collection: RegisterCollection,
  key: String,
) -> Result(Json, Nil) {
  register_read(collection, key, Atomic)
}

@target(erlang)
pub fn register_versions(
  collection: RegisterCollection,
  key: String,
) -> Result(List(Json), Nil) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetRegisterVersions(collection.address, key, reply)
    },
  )
}

@target(erlang)
pub fn register_keys(collection: RegisterCollection) -> List(String) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetRegisterKeys(collection.address, reply)
    },
  )
}

@target(erlang)
pub fn subscribe_register_collection(
  collection: RegisterCollection,
) -> Subject(register_collection_kernel.RegisterEvent) {
  use event <- subscribe_narrowed(collection.runtime, collection.address)
  case event {
    channel.RegisterCollectionEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_claims(document: Document(root)) -> Result(Claims, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateClaims,
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
  document: Document(root),
  value: Json,
) -> Result(Claims, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        Claims(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
pub fn claim_once(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime_beam.ClaimSubmitReply {
  runtime_beam.claim_once(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn compare_and_set_claim(
  claims: Claims,
  key: String,
  value: Json,
) -> runtime_beam.ClaimSubmitReply {
  runtime_beam.compare_and_set_claim(claims.runtime, claims.address, key, value)
}

@target(erlang)
pub fn get_claim(claims: Claims, key: String) -> Result(Json, Nil) {
  runtime_beam.get_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn has_claim(claims: Claims, key: String) -> Bool {
  runtime_beam.has_claim(claims.runtime, claims.address, key)
}

@target(erlang)
pub fn subscribe_claims(claims: Claims) -> Subject(claims_kernel.ClaimEvent) {
  use event <- subscribe_narrowed(claims.runtime, claims.address)
  case event {
    channel.ClaimsEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task managers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn create_task_manager(
  document: Document(root),
) -> Result(TaskManager, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateTaskManager,
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
  document: Document(root),
  value: Json,
) -> Result(TaskManager, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
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
  runtime_beam.task_manager_volunteer(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn abandon_task(manager: TaskManager, task_id: String) -> Nil {
  runtime_beam.task_manager_abandon(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn complete_task(
  manager: TaskManager,
  task_id: String,
) -> Result(Nil, String) {
  runtime_beam.task_manager_complete(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_assigned(manager: TaskManager, task_id: String) -> Bool {
  runtime_beam.task_manager_assigned(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queued(manager: TaskManager, task_id: String) -> Bool {
  runtime_beam.task_manager_queued(manager.runtime, manager.address, task_id)
}

@target(erlang)
pub fn task_queues(manager: TaskManager) -> List(#(String, List(Int))) {
  runtime_beam.task_manager_queues(manager.runtime, manager.address)
}

@target(erlang)
pub fn subscribe_task_manager(
  manager: TaskManager,
) -> Subject(task_manager_kernel.TaskManagerEvent) {
  use event <- subscribe_narrowed(manager.runtime, manager.address)
  case event {
    channel.TaskManagerEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grow-only sets (G-Set)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new grow-only set channel. The detached lifecycle is the same as
/// for `create_map`. The channel is local only, until a caller stores its
/// handle, from `g_set_handle_of`, into an attached map. You can add an
/// element, and you cannot remove one. Two concurrent adds always converge to
/// the union of the two sets.
pub fn create_g_set(document: Document(root)) -> Result(GSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateGSet,
  )
  |> result.map(fn(address) {
    GSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `set`. Store it as a value in a map.
/// See `handle_of`.
pub fn g_set_handle_of(set: GSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the GSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_g_set(
  document: Document(root),
  value: Json,
) -> Result(GSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) { GSet(runtime: document.runtime, address: address) })
  }
}

@target(erlang)
/// Add `element` to the set, optimistically.
pub fn g_set_add(set: GSet, element: String) -> Nil {
  process.send(set.runtime, runtime_beam.AddGSetElement(set.address, element))
}

@target(erlang)
/// Whether `element` is in the current optimistic state of the set.
pub fn g_set_contains(set: GSet, element: String) -> Bool {
  process.call(
    set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GSetContains(set.address, element, reply)
    },
  )
}

@target(erlang)
/// The current optimistic members of the set.
pub fn g_set_values(set: GSet) -> List(String) {
  process.call(
    set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetGSetValues(set.address, reply) },
  )
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_g_set(set: GSet) -> Subject(g_set_kernel.GSetEvent) {
  use event <- subscribe_narrowed(set.runtime, set.address)
  case event {
    channel.GSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Two-phase sets (2P-Set)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new two-phase set channel. The detached lifecycle is the same as
/// for `create_map`. The channel is local only, until a caller stores its
/// handle, from `two_p_set_handle_of`, into an attached map. A remove writes a
/// permanent tombstone. An element that you remove can never become active
/// again, so a remove wins against a concurrent add.
pub fn create_two_p_set(document: Document(root)) -> Result(TwoPSet, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateTwoPSet,
  )
  |> result.map(fn(address) {
    TwoPSet(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `set`. Store it as a value in a map.
/// See `handle_of`.
pub fn two_p_set_handle_of(set: TwoPSet) -> Json {
  handle.encode_handle(set.address)
}

@target(erlang)
/// Resolve a handle value to the TwoPSet it references. Errors are
/// retryable, as with `resolve`.
pub fn resolve_two_p_set(
  document: Document(root),
  value: Json,
) -> Result(TwoPSet, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        TwoPSet(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Add `element` to the set, optimistically. Adding a previously removed
/// element records the add but never reactivates it.
pub fn two_p_set_add(set: TwoPSet, element: String) -> Nil {
  process.send(
    set.runtime,
    runtime_beam.AddTwoPSetElement(set.address, element),
  )
}

@target(erlang)
/// Remove `element` from the set, optimistically. A remove writes a permanent
/// tombstone.
pub fn two_p_set_remove(set: TwoPSet, element: String) -> Nil {
  process.send(
    set.runtime,
    runtime_beam.RemoveTwoPSetElement(set.address, element),
  )
}

@target(erlang)
/// Whether `element` is in the current optimistic state of the set.
pub fn two_p_set_contains(set: TwoPSet, element: String) -> Bool {
  process.call(
    set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.TwoPSetContains(set.address, element, reply)
    },
  )
}

@target(erlang)
/// The current optimistic members of the set.
pub fn two_p_set_values(set: TwoPSet) -> List(String) {
  process.call(
    set.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetTwoPSetValues(set.address, reply) },
  )
}

@target(erlang)
/// Subscribe the calling process to this set's events, local and remote alike.
pub fn subscribe_two_p_set(
  set: TwoPSet,
) -> Subject(two_p_set_kernel.TwoPSetEvent) {
  use event <- subscribe_narrowed(set.runtime, set.address)
  case event {
    channel.TwoPSetEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Directories (hierarchical maps)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new directory channel, which is a hierarchical map keyed by
/// absolute paths. The root path is `"/"`. The detached lifecycle is the same
/// as for `create_map`. The channel is local only, until a caller stores its
/// handle, from `directory_handle_of`, into an attached map.
pub fn create_directory(
  document: Document(root),
) -> Result(SharedDirectory, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateDirectory,
  )
  |> result.map(fn(address) {
    SharedDirectory(runtime: document.runtime, address: address)
  })
}

@target(erlang)
/// The Fluid handle marker that references `directory`. Store it as a value in
/// a map. See `handle_of`.
pub fn directory_handle_of(directory: SharedDirectory) -> Json {
  handle.encode_handle(directory.address)
}

@target(erlang)
/// Resolve a handle value to the SharedDirectory value that it references. A
/// caller can retry after an error, the same as for `resolve`.
pub fn resolve_directory(
  document: Document(root),
  value: Json,
) -> Result(SharedDirectory, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        SharedDirectory(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Set `key` to `value` in the subdirectory at `path`, optimistically. The root
/// path is `"/"`. This function attaches each detached channel referenced by
/// `value` before it submits the directory operation.
pub fn directory_set(
  directory: SharedDirectory,
  path: String,
  key: String,
  value: Json,
) -> Nil {
  process.send(
    directory.runtime,
    runtime_beam.DirectorySet(directory.address, path, key, value),
  )
}

@target(erlang)
/// Remove `key` from the subdirectory at `path`, optimistically.
pub fn directory_delete(
  directory: SharedDirectory,
  path: String,
  key: String,
) -> Nil {
  process.send(
    directory.runtime,
    runtime_beam.DirectoryDelete(directory.address, path, key),
  )
}

@target(erlang)
/// Remove every key from the subdirectory at `path`, optimistically.
pub fn directory_clear(directory: SharedDirectory, path: String) -> Nil {
  process.send(
    directory.runtime,
    runtime_beam.DirectoryClear(directory.address, path),
  )
}

@target(erlang)
/// Create a subdirectory named `name` under `path`, optimistically.
pub fn directory_create_subdirectory(
  directory: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  process.send(
    directory.runtime,
    runtime_beam.DirectoryCreateSubdirectory(directory.address, path, name),
  )
}

@target(erlang)
/// Delete the subdirectory named `name` under `path`, optimistically. The
/// delete also removes every value in that subdirectory.
pub fn directory_delete_subdirectory(
  directory: SharedDirectory,
  path: String,
  name: String,
) -> Nil {
  process.send(
    directory.runtime,
    runtime_beam.DirectoryDeleteSubdirectory(directory.address, path, name),
  )
}

@target(erlang)
/// The current optimistic value at `key`, in the subdirectory at `path`. The
/// result is `Error(Nil)` when the key is absent.
pub fn directory_get(
  directory: SharedDirectory,
  path: String,
  key: String,
) -> Result(Json, Nil) {
  process.call(
    directory.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DirectoryGet(directory.address, path, key, reply)
    },
  )
}

@target(erlang)
/// The current optimistic `#(key, value)` entries in the subdirectory at
/// `path`.
pub fn directory_entries(
  directory: SharedDirectory,
  path: String,
) -> List(#(String, Json)) {
  process.call(
    directory.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DirectoryEntries(directory.address, path, reply)
    },
  )
}

@target(erlang)
/// The names of the direct subdirectories under `path`.
pub fn directory_subdirectories(
  directory: SharedDirectory,
  path: String,
) -> List(String) {
  process.call(
    directory.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DirectorySubdirectories(directory.address, path, reply)
    },
  )
}

@target(erlang)
/// Whether a subdirectory named `name` exists under `path`.
pub fn directory_has_subdirectory(
  directory: SharedDirectory,
  path: String,
  name: String,
) -> Bool {
  process.call(
    directory.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.DirectoryHasSubdirectory(
        directory.address,
        path,
        name,
        reply,
      )
    },
  )
}

@target(erlang)
/// Subscribe the calling process to this directory's events, local and remote
/// alike.
pub fn subscribe_directory(
  directory: SharedDirectory,
) -> Subject(directory_kernel.DirectoryEvent) {
  use event <- subscribe_narrowed(directory.runtime, directory.address)
  case event {
    channel.DirectoryEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PN-counters (increment and decrement)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new PN-counter channel. The detached lifecycle is the same as for
/// `create_map`. The channel is local only, until a caller stores its handle
/// into an attached container.
pub fn create_pn_counter(
  document: Document(root),
) -> Result(PnCounter, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreatePnCounter,
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
  document: Document(root),
  value: Json,
) -> Result(PnCounter, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        PnCounter(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Add `amount` optimistically. A negative amount decrements the counter.
pub fn pn_counter_update(pn_counter: PnCounter, amount: Int) -> Nil {
  process.send(
    pn_counter.runtime,
    runtime_beam.UpdatePnCounter(pn_counter.address, amount),
  )
}

@target(erlang)
/// The current optimistic value of the counter. The result is `Error(Nil)` when the
/// address does not name a PN-counter channel.
pub fn pn_counter_value(pn_counter: PnCounter) -> Result(Int, Nil) {
  process.call(
    pn_counter.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetPnCounterValue(pn_counter.address, reply)
    },
  )
}

@target(erlang)
/// Subscribe the calling process to this PN-counter's local and remote change
/// events.
pub fn subscribe_pn_counter(
  pn_counter: PnCounter,
) -> Subject(pn_counter_kernel.PnCounterEvent) {
  use event <- subscribe_narrowed(pn_counter.runtime, pn_counter.address)
  case event {
    channel.PnCounterEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PactMaps (consensus map: writes are proposals settled by sequencing)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new PactMap channel. The detached lifecycle is the same as for
/// `create_map`.
pub fn create_pact_map(document: Document(root)) -> Result(PactMap, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreatePactMap,
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
  document: Document(root),
  value: Json,
) -> Result(PactMap, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        PactMap(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Propose `value` for `key`. This write is a consensus write, and it is not
/// optimistic. The value stays pending until the server sequencing accepts
/// it.
pub fn pact_map_set(pact_map: PactMap, key: String, value: Json) -> Nil {
  process.send(
    pact_map.runtime,
    runtime_beam.SetPactMap(pact_map.address, key, value),
  )
}

@target(erlang)
/// Propose a delete for `key`. A delete writes a tombstone.
pub fn pact_map_delete(pact_map: PactMap, key: String) -> Nil {
  process.send(
    pact_map.runtime,
    runtime_beam.DeletePactMap(pact_map.address, key),
  )
}

@target(erlang)
/// The accepted value for `key`. The result is `Error(Nil)` when the value is
/// pending, when the key is absent, and when the address does not name a
/// PactMap channel.
pub fn pact_map_get(pact_map: PactMap, key: String) -> Result(Json, Nil) {
  process.call(
    pact_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetPactMapValue(pact_map.address, key, reply)
    },
  )
}

@target(erlang)
/// Every key with an accepted pact or a pending pact.
pub fn pact_map_keys(pact_map: PactMap) -> List(String) {
  process.call(
    pact_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetPactMapKeys(pact_map.address, reply) },
  )
}

@target(erlang)
/// Subscribe the calling process to this PactMap's consensus transitions:
/// `WentPending` when a proposal is sequenced and `WentAccepted` when its
/// signoff list drains.
///
/// Those two transitions *are* the protocol. Without this callback a PactMap
/// only accepts a write and answers a read. An application can then propose a
/// value and read a value, and it cannot learn that the proposal of a peer
/// arrived. That one difference separates a PactMap from a map.
pub fn subscribe_pact_map(
  pact_map: PactMap,
) -> Subject(pact_map_kernel.PactMapEvent) {
  use event <- subscribe_narrowed(pact_map.runtime, pact_map.address)
  case event {
    channel.PactMapEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(erlang)
/// Whether `key` has a proposal now that no room has settled, which is a
/// pending proposal.
pub fn pact_map_is_pending(pact_map: PactMap, key: String) -> Bool {
  process.call(
    pact_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetPactMapPending(pact_map.address, key, reply)
    },
  )
}

@target(erlang)
/// The clients whose agreement `key` still waits on. The result is `Error(Nil)` when
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
) -> Result(List(Int), Nil) {
  pact_map_pending(pact_map, key)
  |> result.map(fn(pending) { pending.expected_signoffs })
}

@target(erlang)
/// The full pending proposal for `key`, which is the value that waits for
/// agreement, with the signoff list that it waits on. The result is `Error(Nil)` when
/// nothing is pending.
pub fn pact_map_pending(
  pact_map: PactMap,
  key: String,
) -> Result(pact_map_kernel.Pending, Nil) {
  process.call(
    pact_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetPactMapPendingDetails(pact_map.address, key, reply)
    },
  )
}

@target(erlang)
/// The accepted entry for `key`: the agreed value, with the sequence number
/// that it settled at. The result is `Error(Nil)` when the key is absent, and when
/// the value is still pending.
pub fn pact_map_get_with_details(
  pact_map: PactMap,
  key: String,
) -> Result(pact_map_kernel.Accepted, Nil) {
  process.call(
    pact_map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetPactMapAccepted(pact_map.address, key, reply)
    },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Ordered collections (consensus work queue)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Create a new ConsensusOrderedCollection channel. The detached lifecycle is
/// the same as for `create_map`.
pub fn create_ordered_collection(
  document: Document(root),
) -> Result(OrderedCollection, String) {
  process.call(
    document.runtime,
    waiting: call_timeout_milliseconds,
    sending: runtime_beam.CreateOrderedCollection,
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
  document: Document(root),
  value: Json,
) -> Result(OrderedCollection, String) {
  case handle.parse_handle(value) {
    Error(Nil) -> Error("value is not a handle marker")
    Ok(address) ->
      process.call(
        document.runtime,
        waiting: call_timeout_milliseconds,
        sending: fn(reply) { runtime_beam.ResolveAddress(address, reply) },
      )
      |> result.map(fn(_) {
        OrderedCollection(runtime: document.runtime, address: address)
      })
  }
}

@target(erlang)
/// Add `value` at the end of the collection.
pub fn ordered_add(collection: OrderedCollection, value: Json) -> Nil {
  process.send(
    collection.runtime,
    runtime_beam.AddOrderedItem(collection.address, value),
  )
}

@target(erlang)
/// Acquire the head item, and return the acquire id. A later `complete` call or
/// `release` call uses that id.
pub fn ordered_acquire(collection: OrderedCollection) -> String {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.AcquireOrderedItem(collection.address, reply)
    },
  )
}

@target(erlang)
/// Like `ordered_acquire`, but also reports the acquire's consensus outcome on
/// the returned `Subject`, exactly once: `AcquiredItem` when this client won
/// the head, `QueueEmpty` when the queue had drained by the time the operation
/// sequenced (a losing acquire emits no event, so this is the loser's only
/// signal), or `Aborted` when the document closes with the acquire in flight.
pub fn ordered_acquire_with_outcome(
  collection: OrderedCollection,
) -> #(String, Subject(ordered_collection_kernel.AcquireOutcome)) {
  let outcome = process.new_subject()
  let acquire_id =
    process.call(
      collection.runtime,
      waiting: call_timeout_milliseconds,
      sending: fn(reply) {
        runtime_beam.AcquireOrderedItemWithOutcome(
          collection.address,
          outcome,
          reply,
        )
      },
    )
  #(acquire_id, outcome)
}

@target(erlang)
/// Complete an acquired item, and remove it permanently.
pub fn ordered_complete(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  process.send(
    collection.runtime,
    runtime_beam.CompleteOrderedItem(collection.address, acquire_id),
  )
}

@target(erlang)
/// Release an acquired item back to the collection, for another consumer.
pub fn ordered_release(
  collection: OrderedCollection,
  acquire_id: String,
) -> Nil {
  process.send(
    collection.runtime,
    runtime_beam.ReleaseOrderedItem(collection.address, acquire_id),
  )
}

@target(erlang)
/// The number of items in the collection now. The result is `Error(Nil)` when the
/// address does not name an ordered-collection channel.
pub fn ordered_size(collection: OrderedCollection) -> Result(Int, Nil) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetOrderedSize(collection.address, reply)
    },
  )
}

@target(erlang)
/// The values in the queue, which no client acquired yet, front first.
pub fn ordered_queue(collection: OrderedCollection) -> List(Json) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetOrderedQueue(collection.address, reply)
    },
  )
}

@target(erlang)
/// The jobs that clients hold now, keyed by acquire id and sorted by that id.
pub fn ordered_jobs(
  collection: OrderedCollection,
) -> List(#(String, ordered_collection_kernel.JobEntry)) {
  process.call(
    collection.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) {
      runtime_beam.GetOrderedJobs(collection.address, reply)
    },
  )
}

@target(erlang)
/// Subscribe the calling process to the queue events of this ordered
/// collection. Those events report an item that a client added, acquired, or
/// completed, and an item that the kernel released again after a client
/// left.
pub fn subscribe_ordered_collection(
  collection: OrderedCollection,
) -> Subject(ordered_collection_kernel.OrderedEvent) {
  use event <- subscribe_narrowed(collection.runtime, collection.address)
  case event {
    channel.OrderedCollectionEvent(inner) -> Some(inner)
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

// ── Ripples (ephemeral presence signals) ─────────────────────────────────────

@target(erlang)
/// A ripple that this client received. A ripple is an ephemeral broadcast that
/// belongs to one document. It does not sequence, and no server stores it. Use
/// a ripple for transient presence, which is a cursor, a selection, or a typing
/// indicator. Such data must **not** go into a DDS.
pub opaque type Ripple {
  Ripple(signal: SignalMessage)
}

@target(erlang)
/// Broadcast an ephemeral ripple to every other connected client. A ripple has
/// a `type` tag and any JSON `content`. It expects no reply, and it has no
/// order, no ack, and no catch-up. The function does nothing until the first
/// handshake assigns a client id.
pub fn submit_ripple(
  document: Document(root),
  ripple_type ripple_type: String,
  content content: Json,
) -> Nil {
  process.send(
    document.runtime,
    runtime_beam.SubmitRipple(ripple_type, content),
  )
}

@target(erlang)
/// Subscribe the calling process to every inbound ripple on the document. The
/// returned subject carries `Ripple` values, mirroring the per-channel
/// `subscribe_*` functions.
pub fn subscribe_ripples(document: Document(root)) -> Subject(Ripple) {
  let subject = process.new_subject()
  process.send(
    document.runtime,
    runtime_beam.SubscribeRipple(fn(signal) {
      process.send(subject, Ripple(signal))
    }),
  )
  subject
}

@target(erlang)
/// The `type` tag of the ripple, if the ripple has one.
pub fn ripple_type(ripple: Ripple) -> Option(String) {
  ripple.signal.signal_type
}

@target(erlang)
/// The JSON payload of the ripple. The wire carries only JSON in this field.
/// The function gives the payload as `Json`, and the caller decodes it with
/// `gleam/json`.
pub fn ripple_content(ripple: Ripple) -> Json {
  wire.dynamic_to_json(ripple.signal.content)
}

@target(erlang)
/// The id of the client that sent the ripple, if the server stamped one. The
/// result is `None` for a ripple that the server produced.
pub fn ripple_client_id(ripple: Ripple) -> Option(String) {
  ripple.signal.client_id
}

@target(erlang)
/// Close the connection and stop the runtime_beam.
pub fn close(document: Document(root)) -> Nil {
  process.send(document.runtime, runtime_beam.Shutdown)
}

@target(erlang)
/// Fault-injection hook (primarily for tests): drop the current transport
/// channel, forcing the runtime through its reconnect/reconcile path. Pending
/// and in-flight edits are preserved and resubmitted after the reconnect.
pub fn force_reconnect(document: Document(root)) -> Nil {
  process.send(document.runtime, runtime_beam.DropChannel)
}

@target(erlang)
/// The id that the server assigned to this client. The result is `None` until
/// the first handshake completes.
///
/// You need this id to find your own identity in a list from *another*
/// component. A consensus kernel reports its membership as the integer ids that
/// it uses to tie-break. `pact_map_pending_signoffs` of a `PactMap` is one
/// example. Without this id you cannot find the entry of your own client.
/// Convert the id with `watershed/client_id.to_int`. That function performs the
/// same derivation as the runtime and the kernels, so the two results always
/// agree.
///
/// ```gleam
/// let mine =
///   watershed_beam.client_id(document) |> option.map(client_id.to_int)
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
  runtime_beam.client_id(document.runtime)
}

@target(erlang)
/// Summarize the current confirmed state of the document to the storage of
/// floodgate. A later client can then start from that snapshot, and it does not
/// replay the full operation history. The function returns the summary handle,
/// which is a git tree SHA. The connection must be synchronized, and the token
/// must carry the `summary:write` scope.
pub fn summarize(document: Document(root)) -> Result(String, String) {
  runtime_beam.summarize(document.runtime)
}

@target(erlang)
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
/// default. The policy applies from the next sequenced operation.
pub fn auto_summarize(
  document: Document(root),
  policy: summary_policy.Policy,
) -> Nil {
  runtime_beam.auto_summarize(document.runtime, Some(policy))
}

@target(erlang)
/// Stop the automatic summaries. An attempt that is already scheduled still
/// checks again before it acts, and it then finds no policy.
pub fn stop_auto_summarize(document: Document(root)) -> Nil {
  runtime_beam.auto_summarize(document.runtime, None)
}

@target(erlang)
/// The number of operations that sequenced after the newest summary that this
/// client knows about. An automatic policy compares that number with its
/// threshold, and a client that joins replays those operations on top of the
/// checkpoint.
///
/// On a document that no client has summarized, this number is the whole
/// log.
pub fn operations_since_summary(document: Document(root)) -> Int {
  runtime_beam.operations_since_summary(document.runtime)
}

@target(erlang)
/// Whether the document is caught up, which is true when the server acked every
/// local edit. The confirmed state is then complete and stable.
/// Useful to wait for quiescence before summarizing or handing off.
pub fn is_synced(document: Document(root)) -> Bool {
  runtime_beam.is_synced(document.runtime)
}

@target(erlang)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. Each `summarize` call
/// stores one version, and a new connection starts from the newest one. The
/// token must carry the `doc:read` scope.
pub fn get_versions(
  document: Document(root),
  count count: Int,
) -> Result(List(SummaryVersion), String) {
  runtime_beam.get_versions(document.runtime, count)
}

@target(erlang)
/// Read the confirmed state that a summary version captured, by the handle of
/// that version. `get_versions` and the return value of `summarize` both give a
/// handle. The function returns the stored snapshot blob, which holds the
/// entries in insertion order with the sequence number that the writer captured
/// them at. The read is at one point in time, and it does not change the live
/// document.
pub fn load_version(
  document: Document(root),
  handle handle: String,
) -> Result(SummaryBlob, String) {
  runtime_beam.load_version(document.runtime, handle)
}

// ─────────────────────────────────────────────────────────────────────────────
// Edits (optimistic: applied locally immediately, sequenced by the server)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn set(map: SharedMap, key: String, value: Json) -> Nil {
  process.send(map.runtime, runtime_beam.Put(map.address, key, value))
}

@target(erlang)
pub fn delete(map: SharedMap, key: String) -> Nil {
  process.send(map.runtime, runtime_beam.Remove(map.address, key))
}

@target(erlang)
pub fn clear(map: SharedMap) -> Nil {
  process.send(map.runtime, runtime_beam.RemoveAll(map.address))
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn get(map: SharedMap, key: String) -> Result(Json, Nil) {
  process.call(
    map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetValue(map.address, key, reply) },
  )
}

@target(erlang)
pub fn has(map: SharedMap, key: String) -> Bool {
  result.is_ok(get(map, key))
}

@target(erlang)
pub fn entries(map: SharedMap) -> List(#(String, Json)) {
  process.call(
    map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetEntries(map.address, reply) },
  )
}

@target(erlang)
pub fn keys(map: SharedMap) -> List(String) {
  process.call(
    map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetKeys(map.address, reply) },
  )
}

@target(erlang)
pub fn size(map: SharedMap) -> Int {
  process.call(
    map.runtime,
    waiting: call_timeout_milliseconds,
    sending: fn(reply) { runtime_beam.GetSize(map.address, reply) },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// Subscribe the calling process to the events of this map. The subject that
/// the function returns receives a `map_kernel.MapEvent` value for every local
/// change and remote change to this channel. It receives no other kind of
/// event.
pub fn subscribe(map: SharedMap) -> Subject(map_kernel.MapEvent) {
  use event <- subscribe_narrowed(map.runtime, map.address)
  case event {
    channel.MapEvent(inner) -> Some(inner)
    channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
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
    channel.MapEvent(_)
    | channel.CounterEvent(_)
    | channel.PnCounterEvent(_)
    | channel.OrMapEvent(_)
    | channel.OrSetEvent(_)
    | channel.GSetEvent(_)
    | channel.TwoPSetEvent(_)
    | channel.RegisterCollectionEvent(_)
    | channel.ClaimsEvent(_)
    | channel.TaskManagerEvent(_)
    | channel.PactMapEvent(_)
    | channel.JsonOtEvent(_)
    | channel.DirectoryEvent(_)
    | channel.OrderedCollectionEvent(_)
    | channel.SequenceEvent(_)
    | channel.RichTextEvent(_)
    | channel.TextEvent(_) -> None
  }
}

@target(erlang)
/// Subscribe to the changes of one typed field. Every local or remote write to
/// the key of `field` delivers a `FieldChange` value. That value carries the new
/// value and the previous value, both decoded at the boundary. Each one is
/// `Error(Invalid)` when a peer wrote a value that does not match the field
/// type. A `Cleared` event on the map arrives as
/// `FieldChange(Ok(None), Ok(None), local)`, because a clear carries no previous
/// value for each key.
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
) -> Subject(FieldChange(a)) {
  let key = schema.field_key(field)
  let subject = process.new_subject()
  process.send(
    typed_map.map.runtime,
    runtime_beam.Subscribe(typed_map.map.address, fn(event) {
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
/// Mint an HS256 development JWT for a floodgate server that runs in
/// development mode, with `just server`. The signature is the same as the
/// signature that `watershed.dev_token` produces on the JavaScript target. **Do
/// not use this function in production.** A deployed binary must never contain
/// the secret.
///
/// ```gleam
/// let token = watershed_beam.dev_token(
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
