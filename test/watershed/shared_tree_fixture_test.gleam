import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/json_ot.{NInt, VArray, VNumber, VObject, VString}
import watershed/tree/fixtures
import watershed/tree/transaction_fixture

const reference = "\"reference\":{\"package\":\"@fluidframework/tree\",\"version\":\"3.1.0\",\"commit\":\"c3c5bf0ecd313362e83fe8a02b7d39e7e0736960\"}"

fn manifest(cases: String) -> String {
  "{\"formatVersion\":1," <> reference <> ",\"cases\":" <> cases <> "}"
}

fn fixture(
  format_version: String,
  reference_value: String,
  input: String,
  expected: String,
) -> String {
  "{\"formatVersion\":"
  <> format_version
  <> ",\"reference\":"
  <> reference_value
  <> ",\"id\":\"independent-fields\",\"domain\":\"tree\",\"input\":"
  <> input
  <> ",\"expected\":"
  <> expected
  <> ",\"raw\":{}}"
}

fn reference_object() -> String {
  "{\"package\":\"@fluidframework/tree\",\"version\":\"3.1.0\",\"commit\":\"c3c5bf0ecd313362e83fe8a02b7d39e7e0736960\"}"
}

fn error_contains(result: Result(a, String), text: String) -> Nil {
  result
  |> expect.to_be_error
  |> string.contains(text)
  |> expect.to_be_true
}

pub fn shared_tree_fixture_positive_decode_keeps_complete_expected_test() -> Nil {
  let raw =
    fixture(
      "1",
      reference_object(),
      "{\"title\":\"start\"}",
      "{\"observations\":[{\"title\":\"end\"}],\"summary\":{\"sequence\":7}}",
    )

  let assert Ok(fixture_case) = fixtures.decode_case(raw)
  fixture_case.id |> expect.to_equal("independent-fields")
  fixture_case.domain |> expect.to_equal("tree")
  fixture_case.reference_version |> expect.to_equal("3.1.0")
  fixture_case.raw |> expect.to_equal(json.object([]))
  fixtures.first_difference(
    fixture_case.expected,
    json.object([
      #("summary", json.object([#("sequence", json.int(7))])),
      #(
        "observations",
        json.array([json.object([#("title", json.string("end"))])], fn(value) {
          value
        }),
      ),
    ]),
  )
  |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_fixture_absent_case_is_error_test() -> Nil {
  manifest(
    "[{\"id\":\"independent-fields\",\"domain\":\"tree\",\"file\":\"cases/independent-fields.json\"}]",
  )
  |> fixtures.manifest_case("not-a-real-case")
  |> error_contains("not-a-real-case")
}

pub fn shared_tree_fixture_missing_file_lookup_is_error_test() -> Nil {
  fixtures.load("not-a-real-case") |> error_contains("not-a-real-case")
}

pub fn shared_tree_fixture_wrong_format_version_is_error_test() -> Nil {
  fixture("2", reference_object(), "{}", "{\"observations\":[null]}")
  |> fixtures.decode_case
  |> error_contains("formatVersion")
}

pub fn shared_tree_fixture_wrong_reference_version_is_error_test() -> Nil {
  fixture(
    "1",
    "{\"package\":\"@fluidframework/tree\",\"version\":\"3.2.0\",\"commit\":\"c3c5bf0ecd313362e83fe8a02b7d39e7e0736960\"}",
    "{}",
    "{\"observations\":[null]}",
  )
  |> fixtures.decode_case
  |> error_contains("3.1.0")
}

pub fn shared_tree_fixture_wrong_reference_commit_is_error_test() -> Nil {
  fixture(
    "1",
    "{\"package\":\"@fluidframework/tree\",\"version\":\"3.1.0\",\"commit\":\"wrong\"}",
    "{}",
    "{\"observations\":[null]}",
  )
  |> fixtures.decode_case
  |> error_contains("c3c5bf0")
}

pub fn shared_tree_fixture_missing_observations_is_error_test() -> Nil {
  fixture("1", reference_object(), "{}", "{\"summary\":{}}")
  |> fixtures.decode_case
  |> error_contains("observations")
}

pub fn shared_tree_fixture_empty_observations_is_error_test() -> Nil {
  fixture("1", reference_object(), "{}", "{\"observations\":[]}")
  |> fixtures.decode_case
  |> error_contains("observations")
}

pub fn shared_tree_fixture_requires_input_and_expected_objects_test() -> Nil {
  fixture("1", reference_object(), "[]", "{\"observations\":[null]}")
  |> fixtures.decode_case
  |> error_contains("input")

  fixture("1", reference_object(), "{}", "[]")
  |> fixtures.decode_case
  |> error_contains("expected")
}

pub fn shared_tree_fixture_empty_manifest_is_error_test() -> Nil {
  manifest("[]")
  |> fixtures.manifest_case("independent-fields")
  |> error_contains("cases")
}

pub fn shared_tree_fixture_duplicate_manifest_ids_are_error_test() -> Nil {
  manifest(
    "[{\"id\":\"independent-fields\",\"domain\":\"tree\",\"file\":\"cases/independent-fields.json\"},{\"id\":\"independent-fields\",\"domain\":\"tree\",\"file\":\"cases/independent-fields.json\"}]",
  )
  |> fixtures.manifest_case("independent-fields")
  |> error_contains("duplicate")
}

pub fn shared_tree_fixture_manifest_requires_canonical_safe_path_test() -> Nil {
  manifest(
    "[{\"id\":\"independent-fields\",\"domain\":\"tree\",\"file\":\"cases/../independent-fields.json\"}]",
  )
  |> fixtures.manifest_case("independent-fields")
  |> error_contains("cases/independent-fields.json")
}

pub fn shared_tree_fixture_manifest_requires_safe_id_and_domain_test() -> Nil {
  manifest(
    "[{\"id\":\"independent_fields\",\"domain\":\"tree\",\"file\":\"cases/independent_fields.json\"}]",
  )
  |> fixtures.manifest_case("independent_fields")
  |> error_contains("id")

  manifest(
    "[{\"id\":\"independent-fields\",\"domain\":\"\",\"file\":\"cases/independent-fields.json\"}]",
  )
  |> fixtures.manifest_case("independent-fields")
  |> error_contains("domain")
}

pub fn shared_tree_fixture_malformed_json_is_error_test() -> Nil {
  fixtures.decode_case("{") |> error_contains("JSON")
}

pub fn shared_tree_fixture_object_order_does_not_differ_test() -> Nil {
  let left =
    json.object([
      #("alpha", json.int(1)),
      #("nested", json.object([#("x", json.bool(True))])),
    ])
  let right =
    json.object([
      #("nested", json.object([#("x", json.bool(True))])),
      #("alpha", json.float(1.0)),
    ])

  fixtures.first_difference(left, right) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_fixture_array_order_reports_first_index_test() -> Nil {
  let left =
    json.array([json.string("a"), json.string("b")], fn(value) { value })
  let right =
    json.array([json.string("b"), json.string("a")], fn(value) { value })

  fixtures.first_difference(left, right) |> expect.to_equal(Error("$[0]"))
}

pub fn shared_tree_fixture_map_value_codec_orders_keys_test() -> Nil {
  let raw =
    "{\"kind\":\"map\",\"schemaId\":\"org.watershed.shared-tree.m2.DynamicMap\",\"entries\":[[\"水\",{\"kind\":\"string\",\"value\":\"海\"}],[\"\",{\"kind\":\"null\"}],[\"a\",{\"kind\":\"boolean\",\"value\":true}]]}"
  let assert Ok(value) = json.parse(raw, fixtures.tree_value_decoder())
  value
  |> fixtures.tree_value_to_json
  |> expect.to_equal(
    json.object([
      #("kind", json.string("map")),
      #("schemaId", json.string("org.watershed.shared-tree.m2.DynamicMap")),
      #(
        "entries",
        json.array(
          [
            json.array(
              [json.string(""), json.object([#("kind", json.string("null"))])],
              fn(value) { value },
            ),
            json.array(
              [
                json.string("a"),
                json.object([
                  #("kind", json.string("boolean")),
                  #("value", json.bool(True)),
                ]),
              ],
              fn(value) { value },
            ),
            json.array(
              [
                json.string("水"),
                json.object([
                  #("kind", json.string("string")),
                  #("value", json.string("海")),
                ]),
              ],
              fn(value) { value },
            ),
          ],
          fn(value) { value },
        ),
      ),
    ]),
  )
}

pub fn shared_tree_fixture_map_value_decoder_rejects_bad_entries_test() -> Nil {
  [
    "{\"kind\":\"map\",\"schemaId\":\"Map\",\"entries\":[[\"same\",{\"kind\":\"null\"}],[\"same\",{\"kind\":\"string\",\"value\":\"second\"}]]}",
    "{\"kind\":\"map\",\"schemaId\":\"Map\",\"entries\":[[\"missing-value\"]]}",
    "{\"kind\":\"map\",\"schemaId\":\"Map\",\"entries\":[[1,{\"kind\":\"null\"}]]}",
  ]
  |> list.each(fn(raw) {
    json.parse(raw, fixtures.tree_value_decoder()) |> expect.to_be_error
  })
}

pub fn shared_tree_fixture_nested_difference_reports_first_path_test() -> Nil {
  let left =
    json.object([
      #(
        "observations",
        json.array(
          [
            json.object([
              #("title", json.string("same")),
              #("point", json.object([#("x", json.int(1))])),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let right =
    json.object([
      #(
        "observations",
        json.array(
          [
            json.object([
              #("title", json.string("same")),
              #("point", json.object([#("x", json.int(2))])),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])

  fixtures.first_difference(left, right)
  |> expect.to_equal(Error("$.observations[0].point.x"))
}

pub fn shared_tree_fixture_loads_all_required_corpus_ids_test() -> Nil {
  [
    #("schema-profile", "schema"),
    #("schema-validation", "schema"),
    #("bootstrap-map-handles", "container"),
    #("independent-fields", "tree"),
    #("same-field-both-orders", "tree"),
    #("optional-set-clear", "tree"),
    #("null-and-absence", "tree"),
    #("nested-independent", "tree"),
    #("parent-child-both-orders", "tree"),
    #("detached-child-edit", "tree"),
    #("multiple-pending", "history"),
    #("batched-commits", "runtime"),
    #("reconnect-before-ack", "history"),
    #("summary-tail", "summary"),
    #("summary-writer-matrix", "summary"),
    #("id-ranges", "ids"),
    #("field-compose-invert-rebase", "field"),
    #("modular-nested-algebra", "modular"),
    #("history-window", "history"),
    #("unicode-and-numbers", "values"),
    #("invalid-profile", "invalid"),
    #("forest-delta", "forest"),
    #("container-foundations", "container"),
    #("summary-foundations", "summary"),
    #("map-schema-content", "schema"),
    #("array-schema-content", "schema"),
    #("array-forest-delta", "forest"),
    #("identifier-schema", "schema"),
    #("identifier-values", "values"),
    #("identifier-field-batches", "codec"),
    #("identifier-persistence", "history"),
    #("transaction-callbacks", "tree"),
    #("transaction-constraints", "modular"),
    #("transaction-wire", "codec"),
    #("transaction-history", "history"),
  ]
  |> list.each(fn(required) {
    let #(id, domain) = required
    let assert Ok(fixture_case) = fixtures.load(id)
    fixture_case.id |> expect.to_equal(id)
    fixture_case.domain |> expect.to_equal(domain)
  })
}

pub fn shared_tree_transaction_callbacks_match_upstream_test() -> Nil {
  fixtures.assert_case(
    "transaction-callbacks",
    transaction_fixture.run_callbacks,
  )
}

pub fn shared_tree_transaction_constraints_match_upstream_test() -> Nil {
  fixtures.assert_case(
    "transaction-constraints",
    transaction_fixture.run_constraints,
  )
}

pub fn shared_tree_transaction_history_matches_upstream_test() -> Nil {
  fixtures.assert_case("transaction-history", transaction_fixture.run_history)
}

pub fn shared_tree_transaction_runners_reject_scenario_mutations_test() -> Nil {
  let assert Ok(fixtures.Case(input: callback_input, ..)) =
    fixtures.load("transaction-callbacks")
  let assert Ok(VObject(callback_root)) =
    json_ot.parse_json(json.to_string(callback_input))
  let assert Ok(VArray([VObject(first), ..rest])) =
    list.key_find(callback_root, "scenarios")
  callback_root
  |> list.key_set(
    "scenarios",
    VArray([VObject(list.key_set(first, "id", VString("unknown"))), ..rest]),
  )
  |> VObject
  |> json_ot.to_json
  |> transaction_fixture.run_callbacks
  |> expect.to_be_error

  let assert Ok(fixtures.Case(input: constraint_input, ..)) =
    fixtures.load("transaction-constraints")
  let assert Ok(VObject(constraint_root)) =
    json_ot.parse_json(json.to_string(constraint_input))
  let assert Ok(VArray([detached, same, cross, VObject(concurrent)])) =
    list.key_find(constraint_root, "scenarios")
  constraint_root
  |> list.key_set(
    "scenarios",
    VArray([
      detached,
      same,
      cross,
      VObject(list.key_set(
        concurrent,
        "constraints",
        VArray([VString("nodeInDocument")]),
      )),
    ]),
  )
  |> VObject
  |> json_ot.to_json
  |> transaction_fixture.run_constraints
  |> expect.to_be_error

  let assert Ok(fixtures.Case(input: history_input, ..)) =
    fixtures.load("transaction-history")
  let assert Ok(VObject(history_root)) =
    json_ot.parse_json(json.to_string(history_input))
  let assert Ok(VArray([VObject(history_scenario)])) =
    list.key_find(history_root, "scenarios")
  let assert Ok(VArray([VObject(first_action), ..actions])) =
    list.key_find(history_scenario, "actions")
  let _ =
    history_root
    |> list.key_set(
      "scenarios",
      VArray([
        VObject(list.key_set(
          history_scenario,
          "actions",
          VArray([
            VObject(list.key_set(first_action, "op", VString("unknown"))),
            ..actions
          ]),
        )),
      ]),
    )
    |> VObject
    |> json_ot.to_json
    |> transaction_fixture.run_history
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_history_rejects_replay_input_mutations_test() {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-history")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(compressor)) = list.key_find(root, "compressor")
  let assert Ok(VObject(tail)) = list.key_find(root, "tailEnvelope")
  let assert Ok(VObject(continuation)) = list.key_find(root, "continuation")

  [
    list.key_set(
      root,
      "compressor",
      VObject(list.key_set(compressor, "serialized", VString("invalid"))),
    ),
    list.key_set(root, "tailAllocationRanges", VArray([])),
    list.key_set(root, "summary", VObject([])),
    list.key_set(
      root,
      "tailEnvelope",
      VObject(list.key_set(tail, "contents", VObject([]))),
    ),
    list.key_set(
      root,
      "continuation",
      VObject(list.key_set(
        continuation,
        "envelope",
        VObject([
          #("clientId", VString("38bb634c-7159-4e8c-9025-d44c689aae45")),
          #("clientSequenceNumber", VNumber(NInt(1))),
          #("referenceSequenceNumber", VNumber(NInt(6))),
          #("sequenceNumber", VNumber(NInt(7))),
          #("minimumSequenceNumber", VNumber(NInt(2))),
          #("contents", VObject([])),
        ]),
      )),
    ),
  ]
  |> list.each(fn(changed) {
    changed
    |> VObject
    |> json_ot.to_json
    |> transaction_fixture.run_history
    |> expect.to_be_error
  })
}

pub fn shared_tree_transaction_history_observes_continuation_edit_test() {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-history")
  let original = transaction_fixture.run_history(input) |> expect.to_be_ok
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(continuation)) = list.key_find(root, "continuation")
  let assert Ok(VArray([VObject(edit)])) = list.key_find(continuation, "edits")
  let assert Ok(VArray([VObject(value)])) = list.key_find(edit, "values")
  let changed =
    root
    |> list.key_set(
      "continuation",
      VObject(list.key_set(
        continuation,
        "edits",
        VArray([
          VObject(list.key_set(
            edit,
            "values",
            VArray([
              VObject(list.key_set(
                value,
                "label",
                VString("mutated-continuation"),
              )),
            ]),
          )),
        ]),
      )),
    )
    |> VObject
    |> json_ot.to_json
    |> transaction_fixture.run_history
    |> expect.to_be_ok

  let unchanged = json.to_string(changed) == json.to_string(original)
  unchanged |> expect.to_be_false
}
