import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/tree/fixtures
import watershed/tree/transaction_fixture
import watershed/wire/json_object

pub fn shared_tree_transaction_wire_requires_input_sections_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))

  ["messageBytes", "compressor", "context", "operands", "scenarios"]
  |> list.each(fn(key) {
    let changed =
      root
      |> list.filter(fn(entry) { entry.0 != key })
      |> VObject
      |> json_ot.to_json
    let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_transaction_wire_rejects_unknown_context_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(context)) = list.key_find(root, "context")
  let changed =
    root
    |> list.key_set(
      "context",
      VObject(list.key_set(context, "minVersionForCollab", VString("unknown"))),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_rejects_malformed_compressor_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(compressors)) = list.key_find(root, "compressor")
  let assert Ok(VObject(nonviolated)) =
    list.key_find(compressors, "nonviolated")
  let changed =
    root
    |> list.key_set(
      "compressor",
      VObject(list.key_set(
        compressors,
        "nonviolated",
        VObject(list.key_set(nonviolated, "serialized", VString("invalid"))),
      )),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_observes_constraints_and_exact_bytes_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(VString(nonviolated_bytes)) =
    list.key_find(message_bytes, "nonviolated")
  let assert Ok(VString(violated_bytes)) =
    list.key_find(message_bytes, "violated")
  let assert Ok(#(nonviolated_message, nonviolated_bytes)) =
    normalize_message(nonviolated_bytes)
  let assert Ok(#(violated_message, violated_bytes)) =
    normalize_message(violated_bytes)

  let original = case transaction_fixture.run_wire(input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(original)
  let assert Ok(nonviolated) = list.key_find(observation, "nonviolated")
  let assert Ok(violated) = list.key_find(observation, "violated")
  let assert Ok(VObject(encoded_messages)) =
    list.key_find(observation, "message")
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(encoded_nonviolated_message) =
    list.key_find(encoded_messages, "nonviolated")
  let assert Ok(encoded_violated_message) =
    list.key_find(encoded_messages, "violated")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  let assert Ok(VString(encoded_violated)) =
    list.key_find(encoded_bytes, "violated")
  nonviolated
  |> expect.to_equal(
    VObject([
      #("constraints", VArray([VObject([#("violated", json_ot.VBool(False))])])),
      #("violations", json_ot.VNumber(json_ot.NInt(0))),
    ]),
  )
  violated
  |> expect.to_equal(
    VObject([
      #("constraints", VArray([VObject([#("violated", json_ot.VBool(True))])])),
      #("violations", json_ot.VNumber(json_ot.NInt(1))),
    ]),
  )
  encoded_nonviolated_message |> expect.to_equal(nonviolated_message)
  encoded_violated_message |> expect.to_equal(violated_message)
  encoded_nonviolated |> expect.to_equal(nonviolated_bytes)
  encoded_violated |> expect.to_equal(violated_bytes)
}

pub fn shared_tree_transaction_wire_rejects_noncanonical_bytes_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(VString(nonviolated_bytes)) =
    list.key_find(message_bytes, "nonviolated")
  let assert Ok(#(_, expected_bytes)) = normalize_message(nonviolated_bytes)
  let changed_bytes =
    nonviolated_bytes
    |> string.replace("{\"revision\":4", "{ \"revision\":4")
  let changed =
    root
    |> list.key_set(
      "messageBytes",
      VObject(list.key_set(message_bytes, "nonviolated", VString(changed_bytes))),
    )
    |> VObject
    |> json_ot.to_json

  let encoded = case transaction_fixture.run_wire(changed) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(encoded)
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  encoded_nonviolated |> expect.to_equal(expected_bytes)
}

pub fn shared_tree_transaction_wire_observes_independent_input_mutations_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(original) = transaction_fixture.run_wire(input)

  [
    #(
      "nonviolated constraint flag",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"violated\":false",
        "\"violated\":true",
      ),
    ),
    #(
      "violated count",
      replace_nested_string(
        input,
        "messageBytes",
        "violated",
        "\"violations\":1",
        "\"violations\":0",
      ),
    ),
    #(
      "compressor session",
      replace_input(
        input,
        "989422b1-6ee8-49b7-bb0c-b27c95030135",
        "989422b1-6ee8-49b7-bb0c-b27c95030136",
      ),
    ),
    #(
      "modular version",
      replace_nested_integer(input, "context", "modularChange", 5, 4),
    ),
    #(
      "message byte",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"revision\":4",
        "\"revision\":3",
      ),
    ),
  ]
  |> list.each(fn(mutation) {
    case transaction_fixture.run_wire(mutation.1) {
      Error(_) -> Nil
      Ok(observation) ->
        case observation == original {
          False -> Nil
          True -> panic as { mutation.0 <> " mutation was not observed" }
        }
    }
  })
}

fn wire_observation(value: json.Json) -> Result(json_ot.JsonValue, Nil) {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([observation])) = list.key_find(root, "observations")
  Ok(observation)
}

fn normalize_message(bytes: String) -> Result(#(JsonValue, String), Nil) {
  let assert Ok(root) = json_object.members(bytes)
  let assert Ok(changeset) = list.key_find(root, "changeset")
  let assert Ok(change) =
    changeset
    |> string.trim
    |> string.drop_start(1)
    |> string.drop_end(1)
    |> json_object.members
  let assert Ok(data) = list.key_find(change, "data")
  let assert Ok(data) = json_object.members(data)
  let data =
    data
    |> list.filter(fn(member) {
      member.0 != "builds" && member.0 != "refreshers"
    })
    |> encode_object
  let change = change |> list.key_set("data", data) |> encode_object
  let normalized =
    root
    |> list.key_set("changeset", "[" <> change <> "]")
    |> encode_object
  let assert Ok(value) = json_ot.parse_json(normalized)
  Ok(#(value, normalized))
}

fn replace_nested_string(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: String,
  after: String,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(VString(value)) = list.key_find(parent, child_key)
  let changed = string.replace(value, before, after)
  expect.to_be_false(changed == value)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(parent, child_key, VString(changed))),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_nested_integer(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: Int,
  after: Int,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(json_ot.VNumber(json_ot.NInt(value))) =
    list.key_find(parent, child_key)
  value |> expect.to_equal(before)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(
      parent,
      child_key,
      json_ot.VNumber(json_ot.NInt(after)),
    )),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_input(input: json.Json, before: String, after: String) -> json.Json {
  let raw = json.to_string(input)
  let changed = string.replace(raw, before, after)
  expect.to_be_false(changed == raw)
  let assert Ok(value) = json_ot.parse_json(changed)
  json_ot.to_json(value)
}

fn encode_object(members: List(#(String, String))) -> String {
  let body =
    members
    |> list.map(fn(member) {
      json.to_string(json.string(member.0)) <> ":" <> member.1
    })
    |> string.join(",")
  "{" <> body <> "}"
}
