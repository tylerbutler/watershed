import gleam/json
import gleam/list
import startest/expect
import watershed/json_ot.{VArray, VObject, VString}
import watershed/tree/fixtures
import watershed/tree/transaction_fixture

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

  let assert Ok(original) = transaction_fixture.run_wire(input)
  let assert Ok(VObject(observation)) = wire_observation(original)
  let assert Ok(nonviolated) = list.key_find(observation, "nonviolated")
  let assert Ok(violated) = list.key_find(observation, "violated")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(observation, "messageBytes")
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
  encoded_nonviolated |> expect.to_equal(nonviolated_bytes)

  let assert Ok(swapped) = transaction_fixture.run_wire(swap_nonviolated(root))
  let assert Ok(VObject(observation)) = wire_observation(swapped)
  let assert Ok(VString(encoded_violated)) =
    list.key_find(observation, "messageBytes")
  encoded_violated |> expect.to_equal(violated_bytes)
}

fn wire_observation(value: json.Json) -> Result(json_ot.JsonValue, Nil) {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([observation])) = list.key_find(root, "observations")
  Ok(observation)
}

fn swap_nonviolated(root: List(#(String, json_ot.JsonValue))) -> json.Json {
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(violated_bytes) = list.key_find(message_bytes, "violated")
  let assert Ok(VObject(compressors)) = list.key_find(root, "compressor")
  let assert Ok(violated_compressor) = list.key_find(compressors, "violated")
  VObject(
    root
    |> list.key_set(
      "messageBytes",
      VObject(list.key_set(message_bytes, "nonviolated", violated_bytes)),
    )
    |> list.key_set(
      "compressor",
      VObject(list.key_set(compressors, "nonviolated", violated_compressor)),
    ),
  )
  |> json_ot.to_json
}
