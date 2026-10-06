import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import startest/expect
import watershed/channel
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VBool, VNumber, VObject, VString,
}
import watershed/runtime_core
import watershed/tree/branch
import watershed/tree/branch_fixture
import watershed/tree/fixtures
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/transaction_fixture
import watershed/tree/types as tree_types
import watershed/tree/undo_fixture
import watershed/tree_kernel

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

pub fn shared_tree_undo_redo_fields_match_native_observations_test() -> Nil {
  assert_undo_fixture("undo-redo-fields")
}

pub fn shared_tree_undo_redo_identifiers_survive_edit_undo_redo_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("undo-redo-fields")
  let assert Ok(actual) = undo_fixture.run_identifiers(fixture.input)
  let assert Ok(expected) = undo_fixture.project_identifiers(fixture.expected)
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_undo_redo_kinds_match_native_observations_test() -> Nil {
  assert_undo_fixture("undo-redo-kinds")
}

pub fn shared_tree_revertible_lifetime_matches_native_observations_test() -> Nil {
  assert_undo_fixture("revertible-lifetime")
}

pub fn shared_tree_undo_redo_constraints_match_native_observations_test() -> Nil {
  assert_undo_fixture("undo-redo-constraints")
}

fn assert_undo_fixture(name: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(name)
  let actual = case undo_fixture.run(name, fixture.input) {
    Ok(value) -> value
    Error(detail) -> panic as { name <> " native runner: " <> detail }
  }
  let expected = case undo_fixture.projection(name, fixture.expected) {
    Ok(value) -> value
    Error(detail) -> panic as { name <> " native projection: " <> detail }
  }
  case fixtures.first_difference(actual, expected) {
    Ok(Nil) -> Nil
    Error(path) -> panic as { name <> " native observations differ at " <> path }
  }
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

pub fn local_branch_merge_matches_pinned_observations_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-merge")
  let actual =
    branch_fixture.run("local-branch-merge", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-merge", fixture.expected)
    |> expect.to_be_ok
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn local_branch_isolation_matches_pinned_observations_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-isolation")
  let actual =
    branch_fixture.run("local-branch-isolation", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-isolation", fixture.expected)
    |> expect.to_be_ok
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn local_branch_rebase_matches_supported_rows_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-rebase")
  let actual =
    branch_fixture.run("local-branch-rebase", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-rebase", fixture.expected)
    |> expect.to_be_ok
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn local_branch_transactions_match_pinned_observations_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-transactions")
  let actual =
    branch_fixture.run("local-branch-transactions", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-transactions", fixture.expected)
    |> expect.to_be_ok
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn local_branch_allocation_matches_pinned_observations_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-allocation")
  let actual =
    branch_fixture.run("local-branch-allocation", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-allocation", fixture.expected)
    |> expect.to_be_ok
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}

pub fn local_branch_schema_source_evidence_and_native_refusal_are_required_test() {
  let assert Ok(fixtures.Case(expected: expected, ..)) =
    fixtures.load("local-branch-rebase")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(expected))
  let assert Ok(VArray([first, second, third, VObject(schema)])) =
    list.key_find(root, "observations")
  root
  |> list.key_set(
    "observations",
    VArray([
      first,
      second,
      third,
      VObject(list.filter(schema, fn(field) { field.0 != "forkHistory" })),
    ]),
  )
  |> VObject
  |> json_ot.to_json
  |> fn(expected) { branch_fixture.projection("local-branch-rebase", expected) }
  |> expect.to_be_error
  root
  |> list.key_set(
    "observations",
    VArray([
      first,
      second,
      third,
      VObject(list.key_set(schema, "forkHistory", VArray([]))),
    ]),
  )
  |> VObject
  |> json_ot.to_json
  |> fn(expected) { branch_fixture.projection("local-branch-rebase", expected) }
  |> expect.to_be_error
  [
    list.key_set(schema, "main", VArray([VString("wrong")])),
    list.key_set(schema, "main", VArray([VString("C"), VString("B")])),
    list.key_set(schema, "forkCanViewWideSchema", VBool(True)),
    list.key_set(
      schema,
      "forkHistory",
      VArray([
        VString("not-a-revision"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b09"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b07"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b08"),
      ]),
    ),
    list.key_set(
      schema,
      "forkHistory",
      VArray([
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b09"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b06"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b07"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b08"),
      ]),
    ),
    list.key_set(
      schema,
      "forkHistory",
      VArray([
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b06"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b09"),
        VString("8f95be09-8376-4ff7-8755-ccd7e8124b07"),
      ]),
    ),
  ]
  |> list.each(fn(mutated_schema) {
    root
    |> list.key_set(
      "observations",
      VArray([first, second, third, VObject(mutated_schema)]),
    )
    |> VObject
    |> json_ot.to_json
    |> fn(expected) {
      branch_fixture.projection("local-branch-rebase", expected)
    }
    |> expect.to_be_error
  })

  let assert Ok(core) = runtime_fixture.routed_core()
  let address = "A/_C"
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, address)
  let assert Ok(view) =
    tree_kernel.stored_schema(state)
    |> tree_schema.stored_to_json
    |> tree_schema.view_from_json
  let assert Ok(#(core, id)) =
    runtime_core.fork_tree(core, address, tree_types.DocumentCheckout, view)
  let branch = tree_types.LocalCheckout(id)
  let before_forest = core.tree_checkouts
  let before_channels = core.channels
  let before_compressor = core.compressor
  let before_in_flight = core.in_flight
  let before_publications = core.tree_publication_scopes
  let assert Ok(before_history) =
    runtime_core.tree_history_evidence(core, address)

  runtime_core.submit_tree_upgrade_on(core, address, branch, view)
  |> expect.to_equal(
    Error(runtime_core.TreeOperationFailed(
      address,
      tree_types.UnsupportedFeature(
        "branch schema",
        "schema authoring on a local checkout",
      ),
    )),
  )
  core.tree_checkouts |> expect.to_equal(before_forest)
  core.channels |> expect.to_equal(before_channels)
  core.compressor |> expect.to_equal(before_compressor)
  core.in_flight |> expect.to_equal(before_in_flight)
  core.tree_publication_scopes |> expect.to_equal(before_publications)
  runtime_core.tree_history_evidence(core, address)
  |> expect.to_equal(Ok(before_history))
  runtime_core.tree_branch_status(core, address, branch)
  |> expect.to_equal(runtime_core.BranchValid)
  let assert Ok(#(_, _)) =
    runtime_core.rebase_tree_onto(
      core,
      address,
      branch,
      tree_types.DocumentCheckout,
    )
  Nil
}

pub fn local_branch_merge_rejects_actual_event_mutations_test() {
  let assert Ok(fixture) = fixtures.load("local-branch-merge")
  let actual =
    branch_fixture.run("local-branch-merge", fixture.input)
    |> expect.to_be_ok
  let expected =
    branch_fixture.projection("local-branch-merge", fixture.expected)
    |> expect.to_be_ok

  [
    mutate_first_merge_event(actual, "kind", VString("Undo")),
    mutate_first_merge_event(actual, "factory", VBool(False)),
    mutate_first_merge_event(actual, "change", VString("changed-payload")),
    mutate_first_merge_change(actual, "revision", VNumber(NInt(999))),
  ]
  |> list.each(fn(mutated) {
    fixtures.first_difference(mutated, expected) |> expect.to_be_error
  })
}

pub fn local_branch_native_notifications_outbound_and_document_lifetime_test() {
  let assert Ok(core) = runtime_fixture.routed_core()
  let address = "A/_C"
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, address)
  let assert Ok(view) =
    tree_kernel.stored_schema(state)
    |> tree_schema.stored_to_json
    |> tree_schema.view_from_json
  let assert Ok(#(core, source_id)) =
    runtime_core.fork_tree(core, address, tree_types.DocumentCheckout, view)
  let source = tree_types.LocalCheckout(source_id)
  let assert Ok(#(core, source_events, [])) =
    runtime_core.submit_tree_edits_on(core, address, source, [
      tree_types.SetField(["title"], tree_types.StringValue("native-source")),
    ])
  let assert [
    #(
      "A/_C",
      tree_types.LocalCheckout(_),
      channel.TreeCommitApplied(
        source_revision,
        tree_types.DefaultCommit,
        True,
        True,
      ),
    ),
    ..
  ] = source_events
  let assert Ok(#(core, target_events, [outbound])) =
    runtime_core.merge_tree(
      core,
      address,
      tree_types.DocumentCheckout,
      source,
      False,
    )
  let assert [
    #(
      "A/_C",
      tree_types.DocumentCheckout,
      channel.TreeCommitApplied(
        target_revision,
        tree_types.DefaultCommit,
        True,
        True,
      ),
    ),
    ..
  ] = target_events
  target_revision |> expect.to_equal(source_revision)
  outbound.contents |> json.to_string |> string.is_empty |> expect.to_be_false

  let assert Ok(forest) = dict.get(core.tree_checkouts, address)
  let assert Ok(document) = branch.checkout(forest, tree_types.DocumentCheckout)
  let assert Ok(#(retained, revertible)) =
    branch.retain_revertible(
      forest,
      document,
      target_revision,
      tree_types.DefaultCommit,
    )
  branch.revertible_is_valid(retained, revertible) |> expect.to_be_true

  let before_channels = core.channels
  let before_checkouts = core.tree_checkouts
  runtime_core.dispose_tree_branch(core, address, tree_types.DocumentCheckout)
  |> expect.to_be_error
  core.channels |> expect.to_equal(before_channels)
  core.tree_checkouts |> expect.to_equal(before_checkouts)
  runtime_core.tree_read(core, address, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native-source"))))
}

pub fn local_branch_runner_rejects_input_and_expected_mutations_test() {
  let assert Ok(fixtures.Case(input: input, expected: expected, ..)) =
    fixtures.load("local-branch-merge")
  let assert Ok(VObject(input_root)) = json_ot.parse_json(json.to_string(input))
  let _ =
    input_root
    |> list.key_set("scenarios", VArray([VString("unknown")]))
    |> VObject
    |> json_ot.to_json
    |> fn(input) { branch_fixture.run("local-branch-merge", input) }
    |> expect.to_be_error

  let assert Ok(VObject(expected_root)) =
    json_ot.parse_json(json.to_string(expected))
  let assert Ok(VArray([VObject(boundaries), edge_cases])) =
    list.key_find(expected_root, "observations")
  let _ =
    expected_root
    |> list.key_set(
      "observations",
      VArray([
        VObject(
          list.filter(boundaries, fn(entry) { entry.0 != "sourceEvents" }),
        ),
        edge_cases,
      ]),
    )
    |> VObject
    |> json_ot.to_json
    |> fn(expected) {
      branch_fixture.projection("local-branch-merge", expected)
    }
    |> expect.to_be_error
  Nil
}

pub fn local_branch_new_runners_reject_scenario_and_row_mutations_test() {
  [
    "local-branch-isolation",
    "local-branch-rebase",
    "local-branch-transactions",
    "local-branch-allocation",
  ]
  |> list.each(fn(name) {
    let assert Ok(fixtures.Case(input: input, expected: expected, ..)) =
      fixtures.load(name)
    let assert Ok(VObject(input_root)) =
      json_ot.parse_json(json.to_string(input))
    input_root
    |> list.key_set("scenarios", VArray([VString("unknown")]))
    |> VObject
    |> json_ot.to_json
    |> fn(input) { branch_fixture.run(name, input) }
    |> expect.to_be_error

    let assert Ok(VObject(expected_root)) =
      json_ot.parse_json(json.to_string(expected))
    let assert Ok(VArray([_, ..observations])) =
      list.key_find(expected_root, "observations")
    expected_root
    |> list.key_set("observations", VArray(observations))
    |> VObject
    |> json_ot.to_json
    |> fn(expected) { branch_fixture.projection(name, expected) }
    |> expect.to_be_error
  })
}

fn mutate_first_merge_event(
  value: json.Json,
  field: String,
  replacement: JsonValue,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([VObject(boundaries), ..rest])) =
    list.key_find(root, "observations")
  let assert Ok(VArray([VObject(event), ..events])) =
    list.key_find(boundaries, "events")
  root
  |> list.key_set(
    "observations",
    VArray([
      VObject(list.key_set(
        boundaries,
        "events",
        VArray([VObject(list.key_set(event, field, replacement)), ..events]),
      )),
      ..rest
    ]),
  )
  |> VObject
  |> json_ot.to_json
}

fn mutate_first_merge_change(
  value: json.Json,
  field: String,
  replacement: JsonValue,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([VObject(boundaries), ..rest])) =
    list.key_find(root, "observations")
  let assert Ok(VArray([VObject(event), ..events])) =
    list.key_find(boundaries, "events")
  let assert Ok(VObject(change)) = list.key_find(event, "change")
  root
  |> list.key_set(
    "observations",
    VArray([
      VObject(list.key_set(
        boundaries,
        "events",
        VArray([
          VObject(list.key_set(
            event,
            "change",
            VObject(list.key_set(change, field, replacement)),
          )),
          ..events
        ]),
      )),
      ..rest
    ]),
  )
  |> VObject
  |> json_ot.to_json
}
