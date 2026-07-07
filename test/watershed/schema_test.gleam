import gleam/dynamic/decode
import gleam/json
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

pub fn decode_entries_round_trip_test() {
  let value = Profile(name: "ada", score: 3, last: Some(6))
  let entries = schema.encode_entries(profile_schema(), value)
  schema.decode_entries(profile_schema(), entries)
  |> expect.to_equal(Ok(value))
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
