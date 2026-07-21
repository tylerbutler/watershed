//// Typed field vocabulary for SharedMaps.
////
//// Every field is tagged with a phantom `schema` type, so it can only be used
//// against a `TypedMap(schema)` of the matching shape (see
//// `watershed`/`watershed_js`). Three kinds of key cover every value a map
//// can hold:
////
//// - `Field(schema, a)` — a plain value: a key with a JSON encoder and a
////   decoder.
//// - `ChildField(schema, child)` — a handle to a nested *typed map* of shape
////   `child`, giving typed nested collaborative structures.
//// - `ChannelField(schema, kind)` — a handle to any *other* channel kind
////   (counter, OR-set, claims, …). The `kind` tag routes it to the matching
////   per-kind facade functions at compile time (`resolve_counter_field`,
////   `ensure_or_set`, …); the typed layer is no longer maps-only.
////
//// A schema is a bare phantom tag (never constructed) plus a set of field
//// definitions. Gleam constants cannot hold function calls, so expose each
//// field as a zero-argument function:
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
//// For a *whole record* stored across several keys, build a `Schema` with the
//// `record1`..`record9` codecs: each `prop` declares a field once and both the
//// decoder and the per-key encoder derive from it, so they cannot drift.
//// `sealed_known` then seals the schema to exactly the declared keys with no
//// hand-repeated list:
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
//// Typing is a *decode boundary*, not a closed schema: remote peers (or old
//// summaries) can write any JSON to any key, so reads decode and can fail
//// with `FieldError`. This module is target-agnostic (BEAM and JavaScript).

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A typed key: its name, how to encode its value to Json, and how to decode
/// it back. `schema` is a phantom tag scoping the field to one map shape; `a`
/// is the value type. Opaque so the codec cannot be tampered with.
pub opaque type Field(schema, a) {
  Field(key: String, encode: fn(a) -> Json, decode: Decoder(a))
}

/// A typed key whose stored value is a handle to a nested map of shape
/// `child`. Carries only the key; encoding/resolution of the handle is done
/// by the backend using the existing `handle_of`/`resolve` machinery.
pub opaque type ChildField(schema, child) {
  ChildField(key: String)
}

/// Why a typed read failed.
///
/// - `Missing` — a required single field was absent (`get_required`).
/// - `Invalid` — a present value did not decode to the expected type.
/// - `UnknownKeys` — a `sealed` schema found keys it does not declare.
/// - `SchemaMismatch` — a `versioned` schema found a different stored version.
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

/// An untyped nested `SharedMap` (use `ChildField` for a typed one).
pub type MapChannel

pub type CounterChannel

pub type OrMapChannel

pub type OrSetChannel

pub type ClaimsChannel

pub type RegisterCollectionChannel

pub type TaskManagerChannel

/// BEAM-facade only until the kind gains a JS facade.
pub type JsonOtChannel

/// BEAM-facade only until the kind gains a JS facade.
pub type GSetChannel

/// BEAM-facade only until the kind gains a JS facade.
pub type TwoPSetChannel

/// BEAM-facade only until the kind gains a JS facade.
pub type DirectoryChannel

/// A positive/negative counter (increment and decrement).
pub type PnCounterChannel

/// A consensus map: writes are proposals settled by server sequencing.
pub type PactMapChannel

/// A consensus ordered collection (a sequenced work queue).
pub type OrderedCollectionChannel

/// A collaborative ordered sequence of arbitrary JSON values.
pub type SequenceChannel

/// A typed key whose stored value is a handle to a channel of `kind`.
pub opaque type ChannelField(schema, kind) {
  ChannelField(key: String)
}

/// Define a typed channel field. Annotate (or let inference pin) the kind:
/// `let notes: ChannelField(Doc, OrSetChannel) = channel_field("notes")`.
pub fn channel_field(key: String) -> ChannelField(schema, kind) {
  ChannelField(key: key)
}

/// The channel field's key.
pub fn channel_field_key(field: ChannelField(schema, kind)) -> String {
  field.key
}

// ── Accessors used by the backends (fields are opaque) ───────────────────────

/// The field's key.
pub fn field_key(field: Field(schema, a)) -> String {
  field.key
}

/// The child field's key.
pub fn child_key(field: ChildField(schema, child)) -> String {
  field.key
}

/// Encode a value for storage under `field`.
pub fn encode_value(field: Field(schema, a), value: a) -> Json {
  field.encode(value)
}

/// Decode a stored Json value read for `field`. Round-trips through the JSON
/// string form, matching the decode idiom used elsewhere in watershed
/// (`channel.gleam`).
pub fn decode_value(
  field: Field(schema, a),
  stored: Json,
) -> Result(a, FieldError) {
  case json.parse(json.to_string(stored), field.decode) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(Invalid(reason))
  }
}

/// Decode an optional stored value for `field`, as event fan-out delivers it:
/// an absent value (`None`) decodes to `Ok(None)`; a present value decodes to
/// `Ok(Some(_))` or `Error(Invalid)` when it does not match the field type.
pub fn decode_optional(
  field: Field(schema, a),
  stored: Option(Json),
) -> Result(Option(a), FieldError) {
  case stored {
    None -> Ok(None)
    Some(json) -> decode_value(field, json) |> result.map(Some)
  }
}

/// A typed, per-field change delivered by `subscribe_field`. `value` is the new
/// value (decoded), `previous` the value before the change; both are `Ok(None)`
/// for an absent key and `Error(Invalid)` when a peer wrote a value that does
/// not decode to the field type. A `Cleared` fans out as
/// `FieldChange(Ok(None), Ok(None), local)` — clears report no per-key previous.
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

/// The reserved key a `versioned` schema stores its version under. Excluded
/// from `sealed` unknown-key checks and ignored by record decoders.
pub const version_key = "__schema"

/// One per-key write produced by encoding a record: `Put` sets a key, `Delete`
/// removes it. An optional prop that is `None` encodes as a `Delete` so the
/// whole-record round-trip law holds (a skipped key would leave a stale value
/// that reads back as `Some`).
pub type WriteOp {
  Put(key: String, value: Json)
  Delete(key: String)
}

/// A whole-map codec: read all keys into `record`, write `record` back as
/// per-key write ops. Tagged with the same phantom `tag` as its `TypedMap`.
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

/// Define a whole-map schema from a record decoder and a record encoder. Open
/// (unknown keys allowed) and unversioned by default; add `sealed`/`versioned`.
/// Entries are written as `Put`s; prefer the `record1`..`record9` builders,
/// which derive both directions from a single prop list.
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

/// Reject reads whose map carries keys not in `keys` (the reserved version key
/// is always allowed). Makes the schema a closed set.
pub fn sealed(
  schema: Schema(tag, record),
  keys: List(String),
) -> Schema(tag, record) {
  Schema(..schema, known_keys: Some(keys))
}

/// Seal a record-builder schema to exactly the keys its props declare (the
/// reserved version key is always allowed). No hand-repeated key list to
/// drift out of sync. Panics when called on a hand-rolled `schema(...)` —
/// those don't declare their keys, so use `sealed(keys)` there instead.
pub fn sealed_known(schema: Schema(tag, record)) -> Schema(tag, record) {
  case schema.declared_keys {
    Some(keys) -> sealed(schema, keys)
    None ->
      panic as "sealed_known requires a record1..record9 schema; use sealed(keys) for hand-rolled schemas"
  }
}

/// Stamp and check an integer schema version. `stamp` writes it; `read` fails
/// with `SchemaMismatch` when the stored version differs.
pub fn versioned(
  schema: Schema(tag, record),
  version: Int,
) -> Schema(tag, record) {
  Schema(..schema, version: Some(version))
}

/// Decode a record from a map's `entries`, after the version and seal checks.
/// The backend `read` calls this with the map's current entries.
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

/// The per-key write ops for `value`. The backend `write` applies each
/// individually — `Put` as a set, `Delete` as a delete — preserving per-key
/// merge.
pub fn encode_ops(schema: Schema(tag, record), value: record) -> List(WriteOp) {
  schema.to_ops(value)
}

/// The version key/value to stamp, if the schema is versioned. The backend
/// `stamp` writes it once at creation rather than on every `write`.
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

/// One record property: a typed field plus how to get its value out of the
/// record. Built with `prop` (required) or `optional_prop` (absent when
/// `None`; writes a `Delete`). The last type parameter is the value as the
/// record constructor receives it — `a` for required, `Option(a)` for
/// optional.
pub opaque type Prop(s, record, a) {
  Prop(
    key: String,
    decoder: Decoder(a),
    // Some(default) → decode with optional_field; None → required field.
    fallback: Option(a),
    write: fn(record) -> WriteOp,
  )
}

/// A required property: decode fails when the key is absent; writes a `Put`.
pub fn prop(field: Field(s, a), get: fn(record) -> a) -> Prop(s, record, a) {
  Prop(key: field.key, decoder: field.decode, fallback: None, write: fn(value) {
    Put(field.key, field.encode(get(value)))
  })
}

/// An optional property: an absent key (or a stored JSON null, from legacy or
/// foreign writers) decodes as `None`; a `None` value writes a `Delete` so it
/// never reads back as stale `Some` (see `WriteOp`).
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

/// Decode one prop then continue — the `use`-style step the builders chain.
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
