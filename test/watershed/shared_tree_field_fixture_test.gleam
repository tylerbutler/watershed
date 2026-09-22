import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/json_ot.{VObject, VString}
import watershed/tree/field_fixture
import watershed/tree/fixtures

pub fn shared_tree_field_algebra_matches_upstream_test() {
  fixtures.assert_case("field-compose-invert-rebase", field_fixture.run)
}

pub fn shared_tree_field_fixture_runner_uses_operation_arguments_test() {
  let assert Ok(fixture) = fixtures.load("field-compose-invert-rebase")
  let assert Ok(VObject(fields)) =
    json.parse(json.to_string(fixture.input), json_ot.decoder())
  let changed =
    VObject(
      list.map(fields, fn(field) {
        case field {
          #("operations", VObject(operations)) -> #(
            "operations",
            VObject(
              list.map(operations, fn(operation) {
                case operation {
                  #("compose", VObject(arguments)) -> #(
                    "compose",
                    VObject(
                      list.map(arguments, fn(argument) {
                        case argument.0 {
                          "right" -> #("right", VString("swap"))
                          _ -> argument
                        }
                      }),
                    ),
                  )
                  _ -> operation
                }
              }),
            ),
          )
          _ -> field
        }
      }),
    )
    |> json_ot.to_json
  let assert Ok(actual) = field_fixture.run(changed)
  fixtures.first_difference(actual, fixture.expected) |> expect.to_be_error
  Nil
}

pub fn shared_tree_field_fixture_rejects_unknown_selectors_and_metadata_test() {
  [
    json.object([]),
    json.object([
      #("codecs", json.object([])),
      #("revisions", json.object([])),
      #("changes", json.object([])),
      #("operations", json.object([])),
      #("swapApplication", json.object([])),
      #("swapAlgebra", json.object([])),
      #("expected", json.object([])),
    ]),
  ]
  |> list.each(fn(input) { field_fixture.run(input) |> expect.to_be_error })
}

pub fn shared_tree_field_fixture_executes_expanded_operations_test() {
  let assert Ok(fixture) = fixtures.load("field-compose-invert-rebase")
  let assert Ok(VObject(fields)) =
    json.parse(json.to_string(fixture.input), json_ot.decoder())
  let expanded =
    "{\"changes\":{\"clearPresent\":{\"revision\":0,\"data\":{}},\"clearAbsent\":{\"revision\":0,\"data\":{}},\"activeSourceNoop\":{\"revision\":0,\"data\":{}},\"childThenClear\":{\"revision\":0,\"data\":{}},\"childOnClearedRegister\":{\"revision\":1,\"data\":{}},\"baseChildThenClear\":{\"revision\":0,\"data\":{}},\"authoredChild\":{\"revision\":1,\"data\":{}},\"richRevisionChange\":{\"revision\":1,\"data\":{}}},\"compose\":[{\"id\":\"compose-empty\",\"first\":{\"revision\":0,\"data\":{}},\"second\":{\"revision\":1,\"data\":{}},\"outputRevision\":1,\"childCallback\":{\"selector\":\"prefer-first-then-second\"}}],\"invert\":[{\"id\":\"invert-empty\",\"change\":{\"revision\":0,\"data\":{}},\"isRollback\":false,\"inverseRevision\":2,\"maxLocalId\":-1}],\"rebase\":[{\"id\":\"rebase-empty\",\"change\":{\"revision\":1,\"data\":{}},\"over\":{\"revision\":0,\"data\":{}},\"outputRevision\":1,\"childCallback\":{\"selector\":\"prefer-change-then-base\"}}],\"intoDelta\":{\"change\":{\"revision\":1,\"data\":{}},\"childDelta\":{\"selector\":\"local-id-count\",\"field\":\"child\"}},\"replaceRevisions\":{\"id\":\"replace-empty\",\"change\":{\"revision\":1,\"data\":{}},\"obsolete\":[0,1],\"updated\":3,\"outputRevision\":3},\"invalidMappings\":[{\"id\":\"duplicate-move-source\",\"change\":{\"moves\":[[{\"revision\":0,\"localId\":1},{\"revision\":0,\"localId\":2}],[{\"revision\":0,\"localId\":1},{\"revision\":0,\"localId\":3}]],\"childChanges\":[]}},{\"id\":\"duplicate-move-destination\",\"change\":{\"moves\":[[{\"revision\":0,\"localId\":4},{\"revision\":0,\"localId\":6}],[{\"revision\":0,\"localId\":5},{\"revision\":0,\"localId\":6}]],\"childChanges\":[]}},{\"id\":\"duplicate-child-register\",\"change\":{\"moves\":[],\"childChanges\":[[\"self\",{\"revision\":0,\"localId\":7}],[\"self\",{\"revision\":1,\"localId\":8}]]}}]}"
  let assert Ok(expanded) = json.parse(expanded, json_ot.decoder())
  let input = VObject([#("expanded", expanded), ..fields]) |> json_ot.to_json
  let assert Ok(actual) = field_fixture.run(input)
  let output = json.to_string(actual)
  string.contains(output, "\"operation\":\"compose-expanded\"")
  |> expect.to_be_true
  string.contains(output, "\"id\":\"invert-empty\"") |> expect.to_be_true
  string.contains(output, "\"operation\":\"into-delta-expanded\"")
  |> expect.to_be_true
}
