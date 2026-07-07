//// Typed field vocabulary for SharedMaps.
////
//// A `Field(schema, a)` bundles a key with a JSON encoder and a decoder, and
//// is tagged with a phantom `schema` type so it can only be used against a
//// `TypedMap(schema)` of the matching shape (see `watershed`/`watershed_js`).
//// A `ChildField(schema, child)` is a key whose value is a handle to a nested
//// map of shape `child`, giving typed nested collaborative structures.
////
//// A schema is a bare phantom tag (never constructed) plus a set of
//// `field`/`child_field` definitions. Gleam constants cannot hold function
//// calls, so expose each field as a zero-argument function:
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

/// A whole-map codec: read all keys into `record`, write `record` back as
/// per-key entries. Tagged with the same phantom `tag` as its `TypedMap`.
pub opaque type Schema(tag, record) {
  Schema(
    decode: Decoder(record),
    to_entries: fn(record) -> List(#(String, Json)),
    known_keys: Option(List(String)),
    version: Option(Int),
  )
}

/// Define a whole-map schema from a record decoder and a record encoder. Open
/// (unknown keys allowed) and unversioned by default; add `sealed`/`versioned`.
pub fn schema(
  decode: Decoder(record),
  to_entries: fn(record) -> List(#(String, Json)),
) -> Schema(tag, record) {
  Schema(
    decode: decode,
    to_entries: to_entries,
    known_keys: None,
    version: None,
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

/// The per-key entries to write for `value`. The backend `write` sets each
/// individually (preserving per-key merge).
pub fn encode_entries(
  schema: Schema(tag, record),
  value: record,
) -> List(#(String, Json)) {
  schema.to_entries(value)
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
