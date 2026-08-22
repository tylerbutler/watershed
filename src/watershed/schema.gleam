//// Typed field vocabulary for SharedMaps.
////
//// Every field carries a phantom `schema` type, so you can use it only against
//// a `TypedMap(schema)` value of the same shape. See `watershed` and
//// `watershed_beam`. Three kinds of key cover every value that a map can
//// hold:
////
//// - `Field(schema, a)` is a plain value: a key with a JSON encoder and a
////   decoder.
//// - `ChildField(schema, child)` is a handle to a nested *typed map* of the
////   shape `child`. It gives typed nested collaborative structures.
//// - `ChannelField(schema, kind)` is a handle to a channel of any *other*
////   kind, for example a counter, an OR-set, or a claims channel. The `kind`
////   tag selects the facade functions of that kind at compile time, for
////   example `resolve_counter_field` and `ensure_or_set`. The typed layer thus
////   covers more than maps.
////
//// A schema is a bare phantom tag, which nothing constructs, with a set of
//// field definitions. A Gleam constant cannot hold a function call, so declare
//// each field as a function with no argument:
////
//// ```gleam
//// pub type Player
//// pub fn name() -> Field(Player, String) {
////   schema.field("name", json.string, decode.string)
//// }
//// pub fn total() -> Field(Player, Int) {
////   schema.field("total", json.int, decode.int)
//// }
//// ```
////
//// The root map carries a tag, the same as any other map. Its tag is on the
//// document, in `Document(root)`, so `root_typed` returns a `TypedMap(root)`
//// value and one document permits exactly one root schema. An application
//// whose root holds untyped keys only still declares a bare tag. That tag is
//// the identity of the document. It is not a promise about the contents.
////
//// For a *whole record* that several keys hold, build a `Schema` value with
//// the `record1` to `record9` codecs. Each `prop` declares a field one time,
//// and both the decoder and the per-key encoder come from that declaration, so
//// the two cannot drift apart. `sealed_known` then seals the schema to exactly
//// the declared keys, and you repeat no list by hand:
////
//// ```gleam
//// fn player_schema() -> Schema(Player, PlayerState) {
////   schema.record2(
////     PlayerState,
////     schema.prop(name(), fn(p: PlayerState) { p.name }),
////     schema.prop(total(), fn(p: PlayerState) { p.total }),
////   )
////   |> schema.sealed_known
//// }
//// ```
////
//// The types are a *decode boundary*, and not a closed schema. A remote peer
//// or an old summary can write any JSON to any key. A read thus decodes the
//// value, and it can fail with a `FieldError` value. This module is
//// target-agnostic: it runs on the BEAM and on JavaScript.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A typed key: its name, the encoder from its value to `Json`, and the decoder
/// back. `schema` is a phantom tag that limits the field to one map shape. `a`
/// is the value type. The type is opaque, so nothing can change the codec.
pub opaque type Field(schema, a) {
  Field(key: String, encode: fn(a) -> Json, decode: Decoder(a))
}

/// A typed key whose stored value is a handle to a nested map of the shape
/// `child`. It carries the key only. The backend encodes and resolves the
/// handle, with the `handle_of` and `resolve` functions.
pub opaque type ChildField(schema, child) {
  ChildField(key: String)
}

/// The reason that a typed read failed.
///
/// - `Missing`: a required single field was absent. See `get_required`.
/// - `Invalid`: a value was present, and it did not decode to the expected
///   type.
/// - `UnknownKeys`: a `sealed` schema found keys that it does not declare.
/// - `SchemaMismatch`: a `versioned` schema found a different stored
///   version.
pub type FieldError {
  Missing(key: String)
  Invalid(reason: json.DecodeError)
  UnknownKeys(keys: List(String))
  SchemaMismatch(expected: Int, found: Int)
}

/// Define a typed field.
pub fn field(
  key: String,
  encode: fn(a) -> Json,
  decode: Decoder(a),
) -> Field(schema, a) {
  Field(key: key, encode: encode, decode: decode)
}

/// Define a typed nested-map field.
pub fn child_field(key: String) -> ChildField(schema, child) {
  ChildField(key: key)
}

// ── Channel-kind fields ──────────────────────────────────────────────────────
//
// Phantom kind tags for keys whose value is a handle to a non-map channel.
// A `ChannelField(schema, kind)` carries only the key; the kind tag routes it
// to the matching per-kind facade functions (`set_counter_field`,
// `resolve_counter_field`, ...) at compile time — using a field with the
// wrong kind's resolver is a type error. `ChildField` remains the special
// case for nested *typed* maps (it carries the child schema tag).

/// An untyped nested `SharedMap`. Use `ChildField` for a typed one.
pub type MapChannel

pub type CounterChannel

pub type OrMapChannel

pub type OrSetChannel

pub type ClaimsChannel

pub type RegisterCollectionChannel

pub type TaskManagerChannel

/// A JSON document edited by json0 operational transform.
pub type JsonOtChannel

/// A rich-text document edited by Quill-style deltas.
pub type RichTextChannel

/// A grow-only set. The adds converge, and the set has no remove operation.
pub type GSetChannel

/// A two-phase set. You can remove an element one time, and you cannot add it
/// again.
pub type TwoPSetChannel

/// A hierarchical directory of nested maps and subdirectories.
pub type DirectoryChannel

/// A counter that supports an increment and a decrement.
pub type PnCounterChannel

/// A consensus map. Each write is a proposal, and the server sequencing
/// settles it.
pub type PactMapChannel

/// A consensus ordered collection, which is a sequenced work queue.
pub type OrderedCollectionChannel

/// A collaborative ordered sequence of arbitrary JSON values.
pub type SequenceChannel

/// A collaborative plain-text channel.
pub type TextChannel

/// A typed key whose stored value is a handle to a channel of `kind`.
pub opaque type ChannelField(schema, kind) {
  ChannelField(key: String)
}

/// Define a typed channel field. Write the kind in an annotation, or let the
/// inference find it:
/// `let notes: ChannelField(Doc, OrSetChannel) = channel_field("notes")`.
pub fn channel_field(key: String) -> ChannelField(schema, kind) {
  ChannelField(key: key)
}

/// The key of the channel field.
pub fn channel_field_key(field: ChannelField(schema, kind)) -> String {
  field.key
}

// ── Accessors used by the backends (fields are opaque) ───────────────────────

/// The key of the field.
pub fn field_key(field: Field(schema, a)) -> String {
  field.key
}

/// The key of the child field.
pub fn child_key(field: ChildField(schema, child)) -> String {
  field.key
}

/// Encode a value for storage under `field`.
pub fn encode_value(field: Field(schema, a), value: a) -> Json {
  field.encode(value)
}

/// Decode a stored `Json` value that a read gave for `field`. The function goes
/// through the JSON string form and back, the same as the decode pattern in
/// the rest of watershed. See `channel.gleam`.
pub fn decode_value(
  field: Field(schema, a),
  stored: Json,
) -> Result(a, FieldError) {
  case json.parse(json.to_string(stored), field.decode) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(Invalid(reason))
  }
}

/// Decode an optional stored value for `field`, in the form that the event
/// fan-out delivers. An absent value, which is `None`, decodes to `Ok(None)`. A
/// present value decodes to `Ok(Some(_))`, or to `Error(Invalid)` when it does
/// not match the field type.
pub fn decode_optional(
  field: Field(schema, a),
  stored: Option(Json),
) -> Result(Option(a), FieldError) {
  case stored {
    None -> Ok(None)
    Some(json) -> decode_value(field, json) |> result.map(Some)
  }
}

/// A typed change to one field, which `subscribe_field` delivers. `value` is
/// the new decoded value, and `previous` is the value before the change. Both
/// are `Ok(None)` for an absent key, and both are `Error(Invalid)` when a peer
/// wrote a value that does not decode to the field type. A `Cleared` event fans
/// out as `FieldChange(Ok(None), Ok(None), local)`, because a clear reports no
/// previous value for each key.
pub type FieldChange(a) {
  FieldChange(
    value: Result(Option(a), FieldError),
    previous: Result(Option(a), FieldError),
    local: Bool,
  )
}

// ── Whole-map schemas ────────────────────────────────────────────────────────
//
// A `Schema(tag, record)` is a bidirectional codec between a Gleam record and
// the map's per-key contents: a `Decoder` reads all keys into one record (a
// single `Result`, with construction the compiler forces you to keep total),
// and a `to_entries` function turns a record back into per-key writes. Writes
// stay per-key so concurrent edits to sibling keys still merge (LWW) — the
// record view never becomes a single clobbering blob.
//
// Optional, opt-in strictness:
// - `sealed` — reads reject keys the schema does not declare.
// - `versioned` — a reserved `__schema` key records an integer version;
//   reads fail with `SchemaMismatch` when it differs. The version is written
//   by the backend's `stamp`, not on every `write`.

/// The reserved key that a `versioned` schema stores its version under. The
/// `sealed` unknown-key check permits it, and a record decoder ignores it.
pub const version_key = "__schema"

/// One write to one key, from the encoding of a record. `Put` sets a key, and
/// `Delete` removes it. An optional prop with the value `None` encodes as a
/// `Delete`, so that the whole-record round-trip law holds. A key that the
/// encoder skipped would keep a stale value, and a read would then give
/// `Some`.
pub type WriteOp {
  Put(key: String, value: Json)
  Delete(key: String)
}

/// A codec for a whole map. It reads every key into a `record` value, and it
/// writes a `record` value back as one write op for each key. It carries the
/// same phantom `tag` as its `TypedMap` type.
pub opaque type Schema(tag, record) {
  Schema(
    decode: Decoder(record),
    to_ops: fn(record) -> List(WriteOp),
    known_keys: Option(List(String)),
    version: Option(Int),
    // Keys declared by the record builders; None for hand-rolled schemas.
    declared_keys: Option(List(String)),
  )
}

/// Define a whole-map schema from a record decoder and a record encoder. The
/// schema is open, so it permits unknown keys, and it has no version. Add
/// `sealed` or `versioned` to change that. The function writes each entry as a
/// `Put` op. Prefer the `record1` to `record9` builders, which derive both
/// directions from one list of props.
pub fn schema(
  decode: Decoder(record),
  to_entries: fn(record) -> List(#(String, Json)),
) -> Schema(tag, record) {
  Schema(
    decode: decode,
    to_ops: fn(value) {
      list.map(to_entries(value), fn(entry) { Put(entry.0, entry.1) })
    },
    known_keys: None,
    version: None,
    declared_keys: None,
  )
}

/// Refuse a read whose map holds a key that is not in `keys`. The reserved
/// version key is always permitted. This function makes the schema a closed
/// set.
pub fn sealed(
  schema: Schema(tag, record),
  keys: List(String),
) -> Schema(tag, record) {
  Schema(..schema, known_keys: Some(keys))
}

/// Seal a record-builder schema to exactly the keys that its props declare.
/// The reserved version key is always permitted. You repeat no key list by
/// hand, so no list can drift out of agreement. The function panics for a
/// schema that you built with `schema(...)`, because such a schema does not
/// declare its keys. Use `sealed(keys)` for that schema instead.
pub fn sealed_known(schema: Schema(tag, record)) -> Schema(tag, record) {
  case schema.declared_keys {
    Some(keys) -> sealed(schema, keys)
    None ->
      panic as "sealed_known requires a record1..record9 schema; use sealed(keys) for hand-rolled schemas"
  }
}

/// Stamp and check an integer schema version. `stamp` writes the version.
/// `read` fails with `SchemaMismatch` when the stored version differs.
pub fn versioned(
  schema: Schema(tag, record),
  version: Int,
) -> Schema(tag, record) {
  Schema(..schema, version: Some(version))
}

/// Decode a record from the `entries` of a map, after the version check and
/// the seal check. The `read` function of the backend calls this function with
/// the current entries of the map.
pub fn decode_entries(
  schema: Schema(tag, record),
  entries: List(#(String, Json)),
) -> Result(record, FieldError) {
  use _ <- result.try(check_version(schema, entries))
  use _ <- result.try(check_sealed(schema, entries))
  json.object(entries)
  |> json.to_string
  |> json.parse(schema.decode)
  |> result.map_error(Invalid)
}

/// The write op for each key of `value`. The `write` function of the backend
/// applies each op separately: a `Put` as a set, and a `Delete` as a delete.
/// The per-key merge thus stays correct.
pub fn encode_ops(schema: Schema(tag, record), value: record) -> List(WriteOp) {
  schema.to_ops(value)
}

/// The version key and value to stamp, if the schema has a version. The `stamp`
/// function of the backend writes it one time, at creation, and not on every
/// `write`.
pub fn stamp_entry(schema: Schema(tag, record)) -> Option(#(String, Json)) {
  case schema.version {
    None -> None
    Some(version) -> Some(#(version_key, json.int(version)))
  }
}

fn check_version(
  schema: Schema(tag, record),
  entries: List(#(String, Json)),
) -> Result(Nil, FieldError) {
  case schema.version {
    None -> Ok(Nil)
    Some(expected) ->
      case list.key_find(entries, version_key) {
        // Unstamped (e.g. legacy or not-yet-stamped) maps are accepted.
        Error(Nil) -> Ok(Nil)
        Ok(stored) ->
          case json.parse(json.to_string(stored), decode.int) {
            Ok(found) if found == expected -> Ok(Nil)
            Ok(found) -> Error(SchemaMismatch(expected: expected, found: found))
            // A malformed version marker is ignored rather than fatal.
            Error(_) -> Ok(Nil)
          }
      }
  }
}

// ── Record builders ──────────────────────────────────────────────────────────
//
// A `Prop` pairs a `Field` with a getter; each field is declared once and
// both codec directions derive from it, so encoder/decoder drift becomes
// unrepresentable. `record1`..`record9` mirror the stdlib `decode.decodeN`
// precedent; wider records nest a child map or fall back to the raw
// `schema(decoder, to_entries)` constructor.

/// One property of a record: a typed field with the function that reads its
/// value out of the record. Build one with `prop` for a required property, or
/// with `optional_prop` for an optional property. An optional property is
/// absent when the value is `None`, and it then writes a `Delete` op. The last
/// type parameter is the value in the form that the record constructor
/// receives: `a` for a required property, and `Option(a)` for an optional
/// one.
pub opaque type Prop(s, record, a) {
  Prop(
    key: String,
    decoder: Decoder(a),
    // Some(default) → decode with optional_field; None → required field.
    fallback: Option(a),
    write: fn(record) -> WriteOp,
  )
}

/// A required property. The decode fails when the key is absent, and the
/// encode writes a `Put` op.
pub fn prop(field: Field(s, a), get: fn(record) -> a) -> Prop(s, record, a) {
  Prop(key: field.key, decoder: field.decode, fallback: None, write: fn(value) {
    Put(field.key, field.encode(get(value)))
  })
}

/// An optional property. An absent key decodes as `None`, and so does a stored
/// JSON null, which an old writer or a foreign writer can produce. A value of
/// `None` writes a `Delete` op, so a read never gives a stale `Some`. See
/// `WriteOp`.
pub fn optional_prop(
  field: Field(s, a),
  get: fn(record) -> Option(a),
) -> Prop(s, record, Option(a)) {
  Prop(
    key: field.key,
    decoder: decode.optional(field.decode),
    fallback: Some(None),
    write: fn(value) {
      case get(value) {
        Some(inner) -> Put(field.key, field.encode(inner))
        None -> Delete(field.key)
      }
    },
  )
}

/// Decode one prop and then continue. The builders chain this step with
/// `use`.
fn prop_step(
  prop: Prop(s, record, a),
  next: fn(a) -> Decoder(final),
) -> Decoder(final) {
  case prop.fallback {
    None -> decode.field(prop.key, prop.decoder, next)
    Some(default) ->
      decode.optional_field(prop.key, default, prop.decoder, next)
  }
}

fn from_props(
  decoder: Decoder(record),
  props: List(#(String, fn(record) -> WriteOp)),
) -> Schema(tag, record) {
  Schema(
    decode: decoder,
    to_ops: fn(value) { list.map(props, fn(prop) { prop.1(value) }) },
    known_keys: None,
    version: None,
    declared_keys: Some(list.map(props, fn(prop) { prop.0 })),
  )
}

pub fn record1(
  ctor: fn(a) -> record,
  p1: Prop(s, record, a),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    decode.success(ctor(v1))
  }
  from_props(decoder, [#(p1.key, p1.write)])
}

pub fn record2(
  ctor: fn(a, b) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    decode.success(ctor(v1, v2))
  }
  from_props(decoder, [#(p1.key, p1.write), #(p2.key, p2.write)])
}

pub fn record3(
  ctor: fn(a, b, c) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    decode.success(ctor(v1, v2, v3))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
  ])
}

pub fn record4(
  ctor: fn(a, b, c, d) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    decode.success(ctor(v1, v2, v3, v4))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
  ])
}

pub fn record5(
  ctor: fn(a, b, c, d, e) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
  p5: Prop(s, record, e),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    use v5 <- prop_step(p5)
    decode.success(ctor(v1, v2, v3, v4, v5))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
    #(p5.key, p5.write),
  ])
}

pub fn record6(
  ctor: fn(a, b, c, d, e, f) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
  p5: Prop(s, record, e),
  p6: Prop(s, record, f),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    use v5 <- prop_step(p5)
    use v6 <- prop_step(p6)
    decode.success(ctor(v1, v2, v3, v4, v5, v6))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
    #(p5.key, p5.write),
    #(p6.key, p6.write),
  ])
}

pub fn record7(
  ctor: fn(a, b, c, d, e, f, g) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
  p5: Prop(s, record, e),
  p6: Prop(s, record, f),
  p7: Prop(s, record, g),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    use v5 <- prop_step(p5)
    use v6 <- prop_step(p6)
    use v7 <- prop_step(p7)
    decode.success(ctor(v1, v2, v3, v4, v5, v6, v7))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
    #(p5.key, p5.write),
    #(p6.key, p6.write),
    #(p7.key, p7.write),
  ])
}

pub fn record8(
  ctor: fn(a, b, c, d, e, f, g, h) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
  p5: Prop(s, record, e),
  p6: Prop(s, record, f),
  p7: Prop(s, record, g),
  p8: Prop(s, record, h),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    use v5 <- prop_step(p5)
    use v6 <- prop_step(p6)
    use v7 <- prop_step(p7)
    use v8 <- prop_step(p8)
    decode.success(ctor(v1, v2, v3, v4, v5, v6, v7, v8))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
    #(p5.key, p5.write),
    #(p6.key, p6.write),
    #(p7.key, p7.write),
    #(p8.key, p8.write),
  ])
}

pub fn record9(
  ctor: fn(a, b, c, d, e, f, g, h, i) -> record,
  p1: Prop(s, record, a),
  p2: Prop(s, record, b),
  p3: Prop(s, record, c),
  p4: Prop(s, record, d),
  p5: Prop(s, record, e),
  p6: Prop(s, record, f),
  p7: Prop(s, record, g),
  p8: Prop(s, record, h),
  p9: Prop(s, record, i),
) -> Schema(s, record) {
  let decoder = {
    use v1 <- prop_step(p1)
    use v2 <- prop_step(p2)
    use v3 <- prop_step(p3)
    use v4 <- prop_step(p4)
    use v5 <- prop_step(p5)
    use v6 <- prop_step(p6)
    use v7 <- prop_step(p7)
    use v8 <- prop_step(p8)
    use v9 <- prop_step(p9)
    decode.success(ctor(v1, v2, v3, v4, v5, v6, v7, v8, v9))
  }
  from_props(decoder, [
    #(p1.key, p1.write),
    #(p2.key, p2.write),
    #(p3.key, p3.write),
    #(p4.key, p4.write),
    #(p5.key, p5.write),
    #(p6.key, p6.write),
    #(p7.key, p7.write),
    #(p8.key, p8.write),
    #(p9.key, p9.write),
  ])
}

fn check_sealed(
  schema: Schema(tag, record),
  entries: List(#(String, Json)),
) -> Result(Nil, FieldError) {
  case schema.known_keys {
    None -> Ok(Nil)
    Some(keys) -> {
      let extra =
        entries
        |> list.map(fn(entry) { entry.0 })
        |> list.filter(fn(key) {
          key != version_key && !list.contains(keys, key)
        })
      case extra {
        [] -> Ok(Nil)
        _ -> Error(UnknownKeys(extra))
      }
    }
  }
}
