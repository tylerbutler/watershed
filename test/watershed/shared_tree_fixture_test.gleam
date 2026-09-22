import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/tree/fixtures

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
  <> "}"
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
  ]
  |> list.each(fn(required) {
    let #(id, domain) = required
    let assert Ok(fixture_case) = fixtures.load(id)
    fixture_case.id |> expect.to_equal(id)
    fixture_case.domain |> expect.to_equal(domain)
  })
}
