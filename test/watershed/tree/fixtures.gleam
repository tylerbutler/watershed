import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import simplifile
import watershed/canonical_json
import watershed/json_ot.{
  type JsonValue, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/types

const fixture_directory = "test/fixtures/shared_tree"

const manifest_path = "test/fixtures/shared_tree/manifest.json"

const reference_package = "@fluidframework/tree"

const reference_version = "3.1.0"

const reference_commit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960"

pub type Case {
  Case(
    id: String,
    domain: String,
    input: Json,
    expected: Json,
    reference_version: String,
  )
}

type Reference {
  Reference(package: String, version: String, commit: String)
}

type ManifestEntry {
  ManifestEntry(id: String, domain: String, file: String)
}

type Manifest {
  Manifest(reference: Reference, cases: List(ManifestEntry))
}

type RawCase {
  RawCase(
    format_version: Int,
    reference: Reference,
    id: String,
    domain: String,
    input: JsonValue,
    expected: JsonValue,
  )
}

pub fn load(name: String) -> Result(Case, String) {
  use manifest <- result.try(
    simplifile.read(manifest_path)
    |> result.map_error(fn(_) {
      "could not read " <> manifest_path <> " for case " <> name
    }),
  )
  use #(domain, file) <- result.try(manifest_case(manifest, name))
  let path = fixture_directory <> "/" <> file
  use raw <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) {
      "could not read case " <> name <> " at " <> path
    }),
  )
  use fixture <- result.try(
    decode_case(raw)
    |> result.map_error(fn(detail) {
      "could not decode case " <> name <> " at " <> path <> ": " <> detail
    }),
  )
  case fixture.id == name, fixture.domain == domain {
    False, _ ->
      Error("case " <> name <> " has id " <> fixture.id <> " in " <> path)
    _, False ->
      Error(
        "case "
        <> name
        <> " has domain "
        <> fixture.domain
        <> ", expected "
        <> domain,
      )
    True, True -> Ok(fixture)
  }
}

pub fn assert_case(name: String, run: fn(Json) -> Result(Json, String)) -> Nil {
  case load(name) {
    Error(detail) -> panic as { "SharedTree case " <> name <> ": " <> detail }
    Ok(fixture) ->
      case run(fixture.input) {
        Error(detail) ->
          panic as {
            "SharedTree case " <> fixture.id <> " runner error: " <> detail
          }
        Ok(actual) ->
          case first_difference(actual, fixture.expected) {
            Ok(Nil) -> Nil
            Error(path) ->
              panic as {
                "SharedTree case " <> fixture.id <> " differs at " <> path
              }
          }
      }
  }
}

pub fn manifest_case(
  raw: String,
  name: String,
) -> Result(#(String, String), String) {
  use manifest <- result.try(decode_manifest(raw))
  case list.find(manifest.cases, fn(entry) { entry.id == name }) {
    Ok(entry) -> Ok(#(entry.domain, entry.file))
    Error(Nil) -> Error("case " <> name <> " is not in the manifest")
  }
}

pub fn decode_case(raw: String) -> Result(Case, String) {
  use decoded <- result.try(
    json.parse(raw, case_decoder())
    |> result.map_error(fn(_) { "invalid case JSON or required field" }),
  )
  use _ <- result.try(validate_format(decoded.format_version, "case"))
  use _ <- result.try(validate_reference(decoded.reference, "case"))
  use _ <- result.try(nonempty(decoded.id, "case id"))
  use _ <- result.try(nonempty(decoded.domain, "case domain"))
  use _ <- result.try(require_object(decoded.input, "input"))
  use _ <- result.try(validate_expected(decoded.expected))
  Ok(Case(
    id: decoded.id,
    domain: decoded.domain,
    input: json_ot.to_json(decoded.input),
    expected: json_ot.to_json(decoded.expected),
    reference_version: decoded.reference.version,
  ))
}

pub fn first_difference(actual: Json, expected: Json) -> Result(Nil, String) {
  use actual <- result.try(
    json.parse(json.to_string(actual), json_ot.decoder())
    |> result.map_error(fn(_) { "$" }),
  )
  use expected <- result.try(
    json.parse(json.to_string(expected), json_ot.decoder())
    |> result.map_error(fn(_) { "$" }),
  )
  difference(actual, expected, "$")
}

pub fn tree_value_decoder() -> Decoder(types.TreeValue) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use kind <- decode.field("kind", decode.string)
  case kind {
    "string" ->
      exact_decoder(fields, ["kind", "value"], types.NullValue, {
        use value <- decode.field("value", decode.string)
        decode.success(types.StringValue(value))
      })
    "boolean" ->
      exact_decoder(fields, ["kind", "value"], types.NullValue, {
        use value <- decode.field("value", decode.bool)
        decode.success(types.BooleanValue(value))
      })
    "number" ->
      exact_decoder(fields, ["kind", "value"], types.NullValue, {
        use value <- decode.field(
          "value",
          decode.one_of(decode.float, [
            {
              use value <- decode.then(decode.int)
              case float.parse(int.to_string(value) <> ".0") {
                Ok(value) -> decode.success(value)
                Error(Nil) -> decode.failure(0.0, "finite number")
              }
            },
          ]),
        )
        case
          value >=. -1.7976931348623157e308 && value <=. 1.7976931348623157e308
        {
          True -> decode.success(types.NumberValue(value))
          False -> decode.failure(types.NullValue, "finite number")
        }
      })
    "null" ->
      exact_decoder(
        fields,
        ["kind"],
        types.NullValue,
        decode.success(types.NullValue),
      )
    "object" ->
      exact_decoder(fields, ["kind", "type", "fields"], types.NullValue, {
        use identifier <- decode.field("type", decode.string)
        use fields <- decode.field(
          "fields",
          decode.list({
            use pair <- decode.then(decode.list(decode.dynamic))
            case pair {
              [_, _] -> {
                use key <- decode.field(0, decode.string)
                use value <- decode.field(
                  1,
                  decode.recursive(tree_value_decoder),
                )
                decode.success(#(key, value))
              }
              _ ->
                decode.failure(
                  #("", types.NullValue),
                  "two-element field entry",
                )
            }
          }),
        )
        decode.success(types.ObjectValue(identifier, fields))
      })
    "map" ->
      exact_decoder(fields, ["kind", "schemaId", "entries"], types.NullValue, {
        use identifier <- decode.field("schemaId", decode.string)
        use entries <- decode.field(
          "entries",
          decode.list({
            use pair <- decode.then(decode.list(decode.dynamic))
            case pair {
              [_, _] -> {
                use key <- decode.field(0, decode.string)
                use value <- decode.field(
                  1,
                  decode.recursive(tree_value_decoder),
                )
                decode.success(#(key, value))
              }
              _ ->
                decode.failure(#("", types.NullValue), "two-element map entry")
            }
          }),
        )
        case
          list.try_fold(entries, set.new(), fn(keys, entry) {
            case set.contains(keys, entry.0) {
              True -> Error(Nil)
              False -> Ok(set.insert(keys, entry.0))
            }
          })
        {
          Ok(_) -> decode.success(types.MapValue(identifier, entries))
          Error(Nil) -> decode.failure(types.NullValue, "unique map keys")
        }
      })
    _ -> decode.failure(types.NullValue, "known tree value kind")
  }
}

pub fn tree_value_to_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) ->
      json.object([
        #("kind", json.string("string")),
        #("value", json.string(value)),
      ])
    types.NumberValue(value) ->
      json.object([
        #("kind", json.string("number")),
        #("value", json.float(value)),
      ])
    types.BooleanValue(value) ->
      json.object([
        #("kind", json.string("boolean")),
        #("value", json.bool(value)),
      ])
    types.NullValue -> json.object([#("kind", json.string("null"))])
    types.ObjectValue(identifier, fields) ->
      json.object([
        #("kind", json.string("object")),
        #("type", json.string(identifier)),
        #(
          "fields",
          fields
            |> list.sort(fn(left, right) {
              canonical_json.compare(left.0, right.0)
            })
            |> json.array(fn(field) {
              json.array(
                [json.string(field.0), tree_value_to_json(field.1)],
                fn(value) { value },
              )
            }),
        ),
      ])
    types.MapValue(identifier, entries) ->
      json.object([
        #("kind", json.string("map")),
        #("schemaId", json.string(identifier)),
        #(
          "entries",
          entries
            |> list.sort(fn(left, right) {
              canonical_json.compare(left.0, right.0)
            })
            |> json.array(fn(entry) {
              json.array(
                [json.string(entry.0), tree_value_to_json(entry.1)],
                fn(value) { value },
              )
            }),
        ),
      ])
  }
}

fn decode_manifest(raw: String) -> Result(Manifest, String) {
  use decoded <- result.try(
    json.parse(raw, manifest_decoder())
    |> result.map_error(fn(_) { "invalid manifest JSON or required field" }),
  )
  use _ <- result.try(validate_format(decoded.0, "manifest"))
  use _ <- result.try(validate_reference(decoded.1.reference, "manifest"))
  use _ <- result.try(validate_manifest_entries(decoded.1.cases))
  Ok(decoded.1)
}

fn manifest_decoder() -> Decoder(#(Int, Manifest)) {
  use format_version <- decode.field("formatVersion", decode.int)
  use reference <- decode.field("reference", reference_decoder())
  use cases <- decode.field("cases", decode.list(manifest_entry_decoder()))
  decode.success(#(format_version, Manifest(reference:, cases:)))
}

fn manifest_entry_decoder() -> Decoder(ManifestEntry) {
  use id <- decode.field("id", decode.string)
  use domain <- decode.field("domain", decode.string)
  use file <- decode.field("file", decode.string)
  decode.success(ManifestEntry(id:, domain:, file:))
}

fn case_decoder() -> Decoder(RawCase) {
  use format_version <- decode.field("formatVersion", decode.int)
  use reference <- decode.field("reference", reference_decoder())
  use id <- decode.field("id", decode.string)
  use domain <- decode.field("domain", decode.string)
  use input <- decode.field("input", json_ot.decoder())
  use expected <- decode.field("expected", json_ot.decoder())
  decode.success(RawCase(
    format_version:,
    reference:,
    id:,
    domain:,
    input:,
    expected:,
  ))
}

fn reference_decoder() -> Decoder(Reference) {
  use package <- decode.field("package", decode.string)
  use version <- decode.field("version", decode.string)
  use commit <- decode.field("commit", decode.string)
  decode.success(Reference(package:, version:, commit:))
}

fn validate_format(version: Int, source: String) -> Result(Nil, String) {
  case version {
    1 -> Ok(Nil)
    _ -> Error(source <> " formatVersion must be 1")
  }
}

fn validate_reference(
  reference: Reference,
  source: String,
) -> Result(Nil, String) {
  case reference.package == reference_package {
    False -> Error(source <> " reference package must be " <> reference_package)
    True ->
      case reference.version == reference_version {
        False ->
          Error(source <> " reference version must be " <> reference_version)
        True ->
          case reference.commit == reference_commit {
            True -> Ok(Nil)
            False ->
              Error(source <> " reference commit must be " <> reference_commit)
          }
      }
  }
}

fn validate_manifest_entries(
  entries: List(ManifestEntry),
) -> Result(Nil, String) {
  case entries {
    [] -> Error("manifest cases must not be empty")
    _ -> validate_manifest_entries_loop(entries, [])
  }
}

fn validate_manifest_entries_loop(
  entries: List(ManifestEntry),
  seen: List(String),
) -> Result(Nil, String) {
  case entries {
    [] -> Ok(Nil)
    [entry, ..rest] -> {
      use _ <- result.try(validate_manifest_entry(entry))
      case list.contains(seen, entry.id) {
        True -> Error("manifest has duplicate case id " <> entry.id)
        False -> validate_manifest_entries_loop(rest, [entry.id, ..seen])
      }
    }
  }
}

fn validate_manifest_entry(entry: ManifestEntry) -> Result(Nil, String) {
  use _ <- result.try(nonempty(entry.id, "manifest case id"))
  use _ <- result.try(nonempty(entry.domain, "manifest case domain"))
  case safe_id(entry.id) {
    False ->
      Error(
        "manifest case id "
        <> entry.id
        <> " must use ASCII letters, digits, or hyphens",
      )
    True -> {
      let expected_path = "cases/" <> entry.id <> ".json"
      case entry.file == expected_path {
        True -> Ok(Nil)
        False ->
          Error(
            "manifest case " <> entry.id <> " file must be " <> expected_path,
          )
      }
    }
  }
}

fn nonempty(value: String, field: String) -> Result(Nil, String) {
  case value {
    "" -> Error(field <> " must not be empty")
    _ -> Ok(Nil)
  }
}

fn safe_id(value: String) -> Bool {
  value
  |> string.to_utf_codepoints
  |> list.all(fn(point) {
    let code = string.utf_codepoint_to_int(point)
    code == 45
    || code >= 48
    && code <= 57
    || code >= 65
    && code <= 90
    || code >= 97
    && code <= 122
  })
}

fn require_object(value: JsonValue, field: String) -> Result(Nil, String) {
  case value {
    VObject(_) -> Ok(Nil)
    _ -> Error(field <> " must be a JSON object")
  }
}

fn validate_expected(expected: JsonValue) -> Result(Nil, String) {
  case expected {
    VObject(fields) ->
      case list.find(fields, fn(field) { field.0 == "observations" }) {
        Error(Nil) -> Error("expected observations are required")
        Ok(#(_, VArray([_, ..]))) -> Ok(Nil)
        Ok(#(_, VArray([]))) -> Error("expected observations must not be empty")
        Ok(_) -> Error("expected observations must be a JSON array")
      }
    _ -> Error("expected must be a JSON object")
  }
}

fn difference(
  actual: JsonValue,
  expected: JsonValue,
  path: String,
) -> Result(Nil, String) {
  case actual, expected {
    VNull, VNull -> Ok(Nil)
    VBool(left), VBool(right) if left == right -> Ok(Nil)
    VString(left), VString(right) if left == right -> Ok(Nil)
    VNumber(left), VNumber(right) ->
      case numbers_equal(left, right) {
        True -> Ok(Nil)
        False -> Error(path)
      }
    VArray(left), VArray(right) -> array_difference(left, right, path, 0)
    VObject(left), VObject(right) ->
      object_difference(
        list.sort(left, member_order),
        list.sort(right, member_order),
        path,
      )
    _, _ -> Error(path)
  }
}

fn numbers_equal(left: json_ot.Number, right: json_ot.Number) -> Bool {
  canonical_json.to_string(VNumber(left))
  == canonical_json.to_string(VNumber(right))
}

fn array_difference(
  actual: List(JsonValue),
  expected: List(JsonValue),
  path: String,
  index: Int,
) -> Result(Nil, String) {
  case actual, expected {
    [], [] -> Ok(Nil)
    [], [_, ..] -> Error(path <> "[" <> int.to_string(index) <> "]")
    [_, ..], [] -> Error(path <> "[" <> int.to_string(index) <> "]")
    [actual, ..actual_rest], [expected, ..expected_rest] ->
      case
        difference(actual, expected, path <> "[" <> int.to_string(index) <> "]")
      {
        Error(path) -> Error(path)
        Ok(Nil) -> array_difference(actual_rest, expected_rest, path, index + 1)
      }
  }
}

fn object_difference(
  actual: List(#(String, JsonValue)),
  expected: List(#(String, JsonValue)),
  path: String,
) -> Result(Nil, String) {
  case actual, expected {
    [], [] -> Ok(Nil)
    [actual, ..], [] -> Error(member_path(path, actual.0))
    [], [expected, ..] -> Error(member_path(path, expected.0))
    [actual, ..actual_rest], [expected, ..expected_rest] ->
      case canonical_json.compare(actual.0, expected.0) {
        order.Lt -> Error(member_path(path, actual.0))
        order.Gt -> Error(member_path(path, expected.0))
        order.Eq ->
          case difference(actual.1, expected.1, member_path(path, actual.0)) {
            Error(path) -> Error(path)
            Ok(Nil) -> object_difference(actual_rest, expected_rest, path)
          }
      }
  }
}

fn member_order(
  left: #(String, JsonValue),
  right: #(String, JsonValue),
) -> order.Order {
  canonical_json.compare(left.0, right.0)
}

fn member_path(path: String, key: String) -> String {
  case path_name(key) {
    True -> path <> "." <> key
    False -> path <> "[" <> json.to_string(json.string(key)) <> "]"
  }
}

fn path_name(value: String) -> Bool {
  case string.to_utf_codepoints(value) {
    [] -> False
    [first, ..rest] ->
      path_name_start(first)
      && list.all(rest, fn(point) {
        path_name_start(point)
        || {
          let code = string.utf_codepoint_to_int(point)
          code >= 48 && code <= 57
        }
      })
  }
}

fn path_name_start(point: UtfCodepoint) -> Bool {
  let code = string.utf_codepoint_to_int(point)
  code == 95 || code >= 65 && code <= 90 || code >= 97 && code <= 122
}

fn exact_fields(fields: Dict(String, Dynamic), expected: List(String)) -> Bool {
  dict.size(fields) == list.length(expected)
  && list.all(expected, fn(field) { dict.has_key(fields, field) })
}

fn exact_decoder(
  fields: Dict(String, Dynamic),
  expected: List(String),
  placeholder: a,
  decoder: Decoder(a),
) -> Decoder(a) {
  case exact_fields(fields, expected) {
    True -> decoder
    False -> decode.failure(placeholder, "object with exact fields")
  }
}
