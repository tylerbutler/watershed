import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect

import watershed/schema.{Invalid}

// A schema tag: never constructed, only used as a phantom type parameter.
type Player

fn name() -> schema.Field(Player, String) {
  schema.field("name", json.string, decode.string)
}

fn total() -> schema.Field(Player, Int) {
  schema.field("total", json.int, decode.int)
}

fn active() -> schema.Field(Player, Bool) {
  schema.field("active", json.bool, decode.bool)
}

// A field whose value is a composite record, exercising decoder composition.
type Point {
  Point(x: Int, y: Int)
}

fn point_to_json(point: Point) -> json.Json {
  json.object([#("x", json.int(point.x)), #("y", json.int(point.y))])
}

fn point_decoder() -> decode.Decoder(Point) {
  use x <- decode.field("x", decode.int)
  use y <- decode.field("y", decode.int)
  decode.success(Point(x: x, y: y))
}

fn origin() -> schema.Field(Player, Point) {
  schema.field("origin", point_to_json, point_decoder())
}

// ── Accessors ────────────────────────────────────────────────────────────────

pub fn field_key_returns_key_test() {
  schema.field_key(name()) |> expect.to_equal("name")
}

pub fn child_key_returns_key_test() {
  let roster: schema.ChildField(Player, Player) = schema.child_field("roster")
  schema.child_key(roster) |> expect.to_equal("roster")
}

pub fn channel_field_key_returns_key_test() {
  let notes: schema.ChannelField(Player, schema.OrSetChannel) =
    schema.channel_field("notes")
  schema.channel_field_key(notes) |> expect.to_equal("notes")
}

pub fn channel_field_kind_is_phantom_test() {
  // The kind tag scopes a field to one resolver family at compile time:
  // passing this CounterChannel field to `resolve_or_set_field` would be a
  // type error (pinned here as documentation — it cannot be a runtime case).
  let score: schema.ChannelField(Player, schema.CounterChannel) =
    schema.channel_field("score")
  schema.channel_field_key(score) |> expect.to_equal("score")
}

// ── Round-trips: encode_value then decode_value ──────────────────────────────

pub fn string_round_trip_test() {
  let stored = schema.encode_value(name(), "ada")
  schema.decode_value(name(), stored) |> expect.to_equal(Ok("ada"))
}

pub fn int_round_trip_test() {
  let stored = schema.encode_value(total(), 42)
  schema.decode_value(total(), stored) |> expect.to_equal(Ok(42))
}

pub fn bool_round_trip_test() {
  let stored = schema.encode_value(active(), True)
  schema.decode_value(active(), stored) |> expect.to_equal(Ok(True))
}

pub fn record_round_trip_test() {
  let stored = schema.encode_value(origin(), Point(x: 3, y: 7))
  schema.decode_value(origin(), stored)
  |> expect.to_equal(Ok(Point(x: 3, y: 7)))
}

// ── Decode failures ──────────────────────────────────────────────────────────

pub fn decode_wrong_type_is_invalid_test() {
  // A String stored where an Int field expects a number.
  let stored = json.string("not a number")
  case schema.decode_value(total(), stored) {
    Error(Invalid(_)) -> Nil
    other -> panic as { "expected Invalid, got " <> string_of(other) }
  }
}

pub fn decode_missing_record_field_is_invalid_test() {
  // A partial object missing "y" should fail the Point decoder.
  let stored = json.object([#("x", json.int(1))])
  case schema.decode_value(origin(), stored) {
    Error(Invalid(_)) -> Nil
    other -> panic as { "expected Invalid, got " <> string_of(other) }
  }
}

// ── Optional decode boundary (subscribe_field payloads) ──────────────────────
//
// `subscribe_field` decodes each side of a change through `decode_optional`:
// an absent value is `Ok(None)`, a present value decodes, and a type-confused
// remote write surfaces as `Error(Invalid)` rather than crashing the fan-out.

pub fn decode_optional_absent_is_none_test() {
  schema.decode_optional(total(), None)
  |> expect.to_equal(Ok(None))
}

pub fn decode_optional_present_decodes_test() {
  schema.decode_optional(total(), Some(json.int(5)))
  |> expect.to_equal(Ok(Some(5)))
}

pub fn decode_optional_type_confused_is_invalid_test() {
  // A remote peer wrote a String where the field expects an Int.
  case schema.decode_optional(total(), Some(json.string("nope"))) {
    Error(Invalid(_)) -> Nil
    other -> panic as { "expected Invalid, got " <> string_of(other) }
  }
}

fn string_of(result: Result(a, schema.FieldError)) -> String {
  case result {
    Ok(_) -> "Ok(_)"
    Error(schema.Missing(key)) -> "Missing(" <> key <> ")"
    Error(Invalid(_)) -> "Invalid(_)"
    Error(schema.UnknownKeys(_)) -> "UnknownKeys(_)"
    Error(schema.SchemaMismatch(..)) -> "SchemaMismatch(_)"
  }
}

// ── Whole-map schemas: decode_entries / encode_entries / seal / version ──────

type Profile {
  Profile(name: String, score: Int, last: Option(Int))
}

fn profile_entries(profile: Profile) -> List(#(String, json.Json)) {
  [
    #("name", json.string(profile.name)),
    #("score", json.int(profile.score)),
    #("last", case profile.last {
      Some(n) -> json.int(n)
      None -> json.null()
    }),
  ]
}

fn profile_decoder() -> decode.Decoder(Profile) {
  use name <- decode.field("name", decode.string)
  use score <- decode.field("score", decode.int)
  use last <- decode.optional_field("last", None, decode.optional(decode.int))
  decode.success(Profile(name: name, score: score, last: last))
}

fn profile_schema() -> schema.Schema(Player, Profile) {
  schema.schema(profile_decoder(), profile_entries)
}

/// Apply write ops to an entries list, as a backend `write` would against a
/// map's current contents: `Put` upserts, `Delete` removes.
fn apply_ops(
  entries: List(#(String, json.Json)),
  ops: List(schema.WriteOp),
) -> List(#(String, json.Json)) {
  list.fold(ops, entries, fn(acc, op) {
    case op {
      schema.Put(key, value) -> list.key_set(acc, key, value)
      schema.Delete(key) -> list.filter(acc, fn(entry) { entry.0 != key })
    }
  })
}

pub fn decode_entries_round_trip_test() {
  let value = Profile(name: "ada", score: 3, last: Some(6))
  let entries = apply_ops([], schema.encode_ops(profile_schema(), value))
  schema.decode_entries(profile_schema(), entries)
  |> expect.to_equal(Ok(value))
}

pub fn raw_schema_ops_are_puts_test() {
  // The raw `schema(decoder, to_entries)` constructor wraps entries as Puts.
  let value = Profile(name: "ada", score: 3, last: None)
  schema.encode_ops(profile_schema(), value)
  |> expect.to_equal([
    schema.Put("name", json.string("ada")),
    schema.Put("score", json.int(3)),
    schema.Put("last", json.null()),
  ])
}

pub fn decode_entries_optional_absent_defaults_test() {
  // A map missing the optional "last" key still decodes.
  let entries = [#("name", json.string("grace")), #("score", json.int(9))]
  schema.decode_entries(profile_schema(), entries)
  |> expect.to_equal(Ok(Profile(name: "grace", score: 9, last: None)))
}

pub fn decode_entries_missing_required_is_invalid_test() {
  let entries = [#("name", json.string("no score"))]
  case schema.decode_entries(profile_schema(), entries) {
    Error(Invalid(_)) -> Nil
    other -> panic as { "expected Invalid, got " <> string_of(other) }
  }
}

pub fn sealed_rejects_unknown_key_test() {
  let sealed = schema.sealed(profile_schema(), ["name", "score", "last"])
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #("rogue", json.bool(True)),
  ]
  case schema.decode_entries(sealed, entries) {
    Error(schema.UnknownKeys(keys)) -> keys |> expect.to_equal(["rogue"])
    other -> panic as { "expected UnknownKeys, got " <> string_of(other) }
  }
}

pub fn open_schema_ignores_unknown_key_test() {
  // Without `sealed`, extra keys are tolerated (forward compat).
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #("rogue", json.bool(True)),
  ]
  schema.decode_entries(profile_schema(), entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 1, last: None)))
}

pub fn versioned_stamp_entry_test() {
  let versioned = schema.versioned(profile_schema(), 2)
  schema.stamp_entry(versioned)
  |> expect.to_equal(Some(#(schema.version_key, json.int(2))))
}

pub fn unversioned_stamp_entry_is_none_test() {
  schema.stamp_entry(profile_schema()) |> expect.to_equal(None)
}

pub fn versioned_matching_version_decodes_test() {
  let versioned = schema.versioned(profile_schema(), 2)
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #(schema.version_key, json.int(2)),
  ]
  schema.decode_entries(versioned, entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 1, last: None)))
}

pub fn versioned_mismatch_is_schema_mismatch_test() {
  let versioned = schema.versioned(profile_schema(), 2)
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #(schema.version_key, json.int(1)),
  ]
  case schema.decode_entries(versioned, entries) {
    Error(schema.SchemaMismatch(expected: 2, found: 1)) -> Nil
    other -> panic as { "expected SchemaMismatch, got " <> string_of(other) }
  }
}

pub fn versioned_unstamped_is_accepted_test() {
  // A map written before versioning (no __schema key) is still readable.
  let versioned = schema.versioned(profile_schema(), 2)
  let entries = [#("name", json.string("ada")), #("score", json.int(1))]
  schema.decode_entries(versioned, entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 1, last: None)))
}

// ── Record builders: prop / optional_prop / record1..9 / sealed_known ────────

fn score_field() -> schema.Field(Player, Int) {
  schema.field("score", json.int, decode.int)
}

fn last_field() -> schema.Field(Player, Int) {
  schema.field("last", json.int, decode.int)
}

fn built_profile_schema() -> schema.Schema(Player, Profile) {
  schema.record3(
    Profile,
    schema.prop(name(), fn(p: Profile) { p.name }),
    schema.prop(score_field(), fn(p: Profile) { p.score }),
    schema.optional_prop(last_field(), fn(p: Profile) { p.last }),
  )
}

pub fn builder_round_trip_some_test() {
  let value = Profile(name: "ada", score: 3, last: Some(6))
  let entries = apply_ops([], schema.encode_ops(built_profile_schema(), value))
  schema.decode_entries(built_profile_schema(), entries)
  |> expect.to_equal(Ok(value))
}

pub fn builder_round_trip_none_test() {
  let value = Profile(name: "grace", score: 9, last: None)
  let entries = apply_ops([], schema.encode_ops(built_profile_schema(), value))
  schema.decode_entries(built_profile_schema(), entries)
  |> expect.to_equal(Ok(value))
}

pub fn optional_none_writes_delete_test() {
  // Decision 1: an absent optional removes the key. Writing a `None` record
  // over stale entries must not read back as `Some`.
  let stale = [
    #("name", json.string("ada")),
    #("score", json.int(3)),
    #("last", json.int(6)),
  ]
  let value = Profile(name: "ada", score: 4, last: None)
  let ops = schema.encode_ops(built_profile_schema(), value)
  ops
  |> list.contains(schema.Delete("last"))
  |> expect.to_equal(True)
  schema.decode_entries(built_profile_schema(), apply_ops(stale, ops))
  |> expect.to_equal(Ok(value))
}

pub fn optional_some_writes_put_test() {
  let value = Profile(name: "ada", score: 3, last: Some(6))
  schema.encode_ops(built_profile_schema(), value)
  |> list.contains(schema.Put("last", json.int(6)))
  |> expect.to_equal(True)
}

pub fn optional_stored_null_reads_as_none_test() {
  // Legacy/foreign writers may store an explicit null; read it as None
  // rather than a decode failure.
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(3)),
    #("last", json.null()),
  ]
  schema.decode_entries(built_profile_schema(), entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 3, last: None)))
}

pub fn sealed_known_rejects_undeclared_key_test() {
  let sealed = schema.sealed_known(built_profile_schema())
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #("rogue", json.bool(True)),
  ]
  case schema.decode_entries(sealed, entries) {
    Error(schema.UnknownKeys(keys)) -> keys |> expect.to_equal(["rogue"])
    other -> panic as { "expected UnknownKeys, got " <> string_of(other) }
  }
}

pub fn sealed_known_admits_version_key_test() {
  let s =
    built_profile_schema()
    |> schema.versioned(1)
    |> schema.sealed_known
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #(schema.version_key, json.int(1)),
  ]
  schema.decode_entries(s, entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 1, last: None)))
}

type Solo {
  Solo(name: String)
}

pub fn record1_round_trip_test() {
  let s = schema.record1(Solo, schema.prop(name(), fn(s: Solo) { s.name }))
  let value = Solo(name: "lin")
  let entries = apply_ops([], schema.encode_ops(s, value))
  schema.decode_entries(s, entries) |> expect.to_equal(Ok(value))
}

type Nine {
  Nine(
    f1: Int,
    f2: Int,
    f3: Int,
    f4: Int,
    f5: Int,
    f6: Int,
    f7: Int,
    f8: Int,
    f9: Option(Int),
  )
}

fn int_field(key: String) -> schema.Field(Player, Int) {
  schema.field(key, json.int, decode.int)
}

pub fn record9_round_trip_test() {
  let s =
    schema.record9(
      Nine,
      schema.prop(int_field("f1"), fn(n: Nine) { n.f1 }),
      schema.prop(int_field("f2"), fn(n: Nine) { n.f2 }),
      schema.prop(int_field("f3"), fn(n: Nine) { n.f3 }),
      schema.prop(int_field("f4"), fn(n: Nine) { n.f4 }),
      schema.prop(int_field("f5"), fn(n: Nine) { n.f5 }),
      schema.prop(int_field("f6"), fn(n: Nine) { n.f6 }),
      schema.prop(int_field("f7"), fn(n: Nine) { n.f7 }),
      schema.prop(int_field("f8"), fn(n: Nine) { n.f8 }),
      schema.optional_prop(int_field("f9"), fn(n: Nine) { n.f9 }),
    )
  let value = Nine(1, 2, 3, 4, 5, 6, 7, 8, None)
  let entries = apply_ops([], schema.encode_ops(s, value))
  schema.decode_entries(s, entries) |> expect.to_equal(Ok(value))
}

pub fn sealed_allows_version_key_test() {
  // The reserved version key must not trip the seal check.
  let s =
    profile_schema()
    |> schema.versioned(1)
    |> schema.sealed(["name", "score", "last"])
  let entries = [
    #("name", json.string("ada")),
    #("score", json.int(1)),
    #(schema.version_key, json.int(1)),
  ]
  schema.decode_entries(s, entries)
  |> expect.to_equal(Ok(Profile(name: "ada", score: 1, last: None)))
}
