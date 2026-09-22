import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/tree/fixtures
import watershed/tree/forest_fixture
import watershed/tree/types

const optional_string_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

fn array(values: List(json.Json)) -> json.Json {
  json.array(values, fn(value) { value })
}

fn tagged_string(value: String) -> json.Json {
  json.object([
    #("kind", json.string("string")),
    #("value", json.string(value)),
  ])
}

fn atom(revision: String, local_id: Int) -> json.Json {
  json.object([
    #("revision", json.string(revision)),
    #("localId", json.int(local_id)),
  ])
}

fn set_root_action(id: String, value: String) -> json.Json {
  let source = atom("770f093f-f030-486b-ace6-af6d9c30b25e", 0)
  json.object([
    #("id", json.string(id)),
    #("op", json.string("apply")),
    #(
      "delta",
      json.object([
        #("latestRevision", json.string("770f093f-f030-486b-ace6-af6d9c30b25e")),
        #(
          "fields",
          array([
            array([
              json.string("rootFieldKey"),
              json.object([
                #(
                  "marks",
                  array([
                    json.object([
                      #("count", json.int(1)),
                      #("attach", source),
                      #("detach", json.null()),
                      #("fields", array([])),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ]),
        ),
        #(
          "build",
          array([
            json.object([
              #("id", source),
              #("trees", array([tagged_string(value)])),
            ]),
          ]),
        ),
        #("refreshers", array([])),
        #("global", array([])),
        #("rename", array([])),
        #("destroy", array([])),
      ]),
    ),
  ])
}

fn observe_action(id: String) -> json.Json {
  json.object([
    #("id", json.string(id)),
    #("op", json.string("observe")),
  ])
}

fn scenario(
  id: String,
  root: json.Json,
  actions: List(json.Json),
) -> json.Json {
  json.object([
    #("id", json.string(id)),
    #("schema", json.string(optional_string_schema)),
    #("root", root),
    #("actions", array(actions)),
  ])
}

fn runner_input(scenarios: List(json.Json)) -> json.Json {
  json.object([#("scenarios", array(scenarios))])
}

fn error_contains(result: Result(a, String), text: String) -> Nil {
  result
  |> expect.to_be_error
  |> string.contains(text)
  |> expect.to_be_true
}

pub fn shared_tree_forest_fixture_tagged_value_codec_test() -> Nil {
  let value =
    types.ObjectValue("KeyProbe", [
      #("水", types.StringValue("海")),
      #("", types.StringValue("")),
    ])
  let encoded = fixtures.tree_value_to_json(value)
  let assert Ok(decoded) =
    json.parse(json.to_string(encoded), fixtures.tree_value_decoder())
  decoded
  |> expect.to_equal(
    types.ObjectValue("KeyProbe", [
      #("", types.StringValue("")),
      #("水", types.StringValue("海")),
    ]),
  )
  encoded
  |> expect.to_equal(
    json.object([
      #("kind", json.string("object")),
      #("type", json.string("KeyProbe")),
      #(
        "fields",
        array([
          array([json.string(""), tagged_string("")]),
          array([json.string("水"), tagged_string("海")]),
        ]),
      ),
    ]),
  )
}

pub fn shared_tree_forest_fixture_build_content_changes_output_test() -> Nil {
  let assert Ok(first) =
    forest_fixture.run(
      runner_input([
        scenario("changed-build", json.null(), [set_root_action("apply", "one")]),
      ]),
    )
  let assert Ok(second) =
    forest_fixture.run(
      runner_input([
        scenario("changed-build", json.null(), [set_root_action("apply", "two")]),
      ]),
    )
  fixtures.first_difference(first, second) |> expect.to_be_error
  Nil
}

pub fn shared_tree_forest_fixture_truncated_script_changes_output_test() -> Nil {
  let apply = set_root_action("apply", "one")
  let assert Ok(full) =
    forest_fixture.run(
      runner_input([
        scenario("truncated", json.null(), [apply, observe_action("observe")]),
      ]),
    )
  let assert Ok(truncated) =
    forest_fixture.run(
      runner_input([
        scenario("truncated", json.null(), [apply]),
      ]),
    )
  fixtures.first_difference(full, truncated) |> expect.to_be_error
  Nil
}

pub fn shared_tree_forest_fixture_rejects_malformed_scripts_test() -> Nil {
  let valid = scenario("valid", json.null(), [observe_action("observe")])
  let duplicate_action =
    scenario("duplicate-action", json.null(), [
      observe_action("same"),
      observe_action("same"),
    ])
  let duplicate_reference =
    scenario("duplicate-reference", tagged_string("root"), [
      json.object([
        #("id", json.string("retain-a")),
        #("op", json.string("retain")),
        #("name", json.string("same")),
        #("path", array([])),
      ]),
      json.object([
        #("id", json.string("retain-b")),
        #("op", json.string("retain")),
        #("name", json.string("same")),
        #("path", array([])),
      ]),
    ])
  let refusal_before_end =
    json.object([
      #("id", json.string("refusal-before-end")),
      #("schema", json.string(optional_string_schema)),
      #("root", json.null()),
      #(
        "actions",
        array([
          json.object([
            #("id", json.string("refuse")),
            #("op", json.string("apply")),
            #(
              "delta",
              json.object([
                #("latestRevision", json.null()),
                #(
                  "fields",
                  array([
                    array([
                      json.string("rootFieldKey"),
                      json.object([
                        #(
                          "marks",
                          array([
                            json.object([
                              #("count", json.int(1)),
                              #(
                                "attach",
                                atom("770f093f-f030-486b-ace6-af6d9c30b25e", 9),
                              ),
                              #("detach", json.null()),
                              #("fields", array([])),
                            ]),
                          ]),
                        ),
                      ]),
                    ]),
                  ]),
                ),
                #("build", array([])),
                #("refreshers", array([])),
                #("global", array([])),
                #("rename", array([])),
                #("destroy", array([])),
              ]),
            ),
          ]),
          observe_action("after"),
        ]),
      ),
    ])
  let duplicate_field =
    json.object([
      #("id", json.string("duplicate-field")),
      #("schema", json.string(optional_string_schema)),
      #("root", json.null()),
      #(
        "actions",
        array([
          json.object([
            #("id", json.string("apply")),
            #("op", json.string("apply")),
            #(
              "delta",
              json.object([
                #("latestRevision", json.null()),
                #(
                  "fields",
                  array([
                    array([
                      json.string("rootFieldKey"),
                      json.object([#("marks", array([]))]),
                    ]),
                    array([
                      json.string("rootFieldKey"),
                      json.object([#("marks", array([]))]),
                    ]),
                  ]),
                ),
                #("build", array([])),
                #("refreshers", array([])),
                #("global", array([])),
                #("rename", array([])),
                #("destroy", array([])),
              ]),
            ),
          ]),
        ]),
      ),
    ])
  [
    #(json.null(), "forest fixture"),
    #(json.object([]), "forest fixture"),
    #(
      json.object([
        #("scenarios", array([valid])),
        #("future", json.bool(True)),
      ]),
      "forest fixture",
    ),
    #(runner_input([]), "scenarios"),
    #(runner_input([valid, valid]), "scenario id"),
    #(runner_input([duplicate_action]), "action id"),
    #(runner_input([duplicate_reference]), "reference name"),
    #(runner_input([duplicate_field]), "field"),
    #(runner_input([refusal_before_end]), "must end"),
    #(
      runner_input([
        scenario("", json.null(), [observe_action("observe")]),
      ]),
      "scenario id",
    ),
    #(
      runner_input([
        scenario("empty-action", json.null(), [observe_action("")]),
      ]),
      "action id",
    ),
    #(
      runner_input([
        scenario("empty-reference", tagged_string("root"), [
          json.object([
            #("id", json.string("retain")),
            #("op", json.string("retain")),
            #("name", json.string("")),
            #("path", array([])),
          ]),
        ]),
      ]),
      "reference name",
    ),
    #(
      runner_input([
        scenario("unknown-action", json.null(), [
          json.object([
            #("id", json.string("future")),
            #("op", json.string("future")),
          ]),
        ]),
      ]),
      "known forest action",
    ),
    #(
      runner_input([
        json.object([
          #("id", json.string("extra-scenario-field")),
          #("schema", json.string(optional_string_schema)),
          #("root", json.null()),
          #("actions", array([observe_action("observe")])),
          #("future", json.bool(True)),
        ]),
      ]),
      "forest fixture",
    ),
    #(
      runner_input([
        scenario("extra-action-field", json.null(), [
          json.object([
            #("id", json.string("observe")),
            #("op", json.string("observe")),
            #("future", json.bool(True)),
          ]),
        ]),
      ]),
      "forest fixture",
    ),
    #(
      runner_input([
        scenario(
          "extra-value-field",
          json.object([
            #("kind", json.string("string")),
            #("value", json.string("root")),
            #("future", json.bool(True)),
          ]),
          [observe_action("observe")],
        ),
      ]),
      "forest fixture",
    ),
    #(
      runner_input([
        json.object([
          #("id", json.string("bad-revision")),
          #("schema", json.string(optional_string_schema)),
          #("root", json.null()),
          #(
            "actions",
            array([
              json.object([
                #("id", json.string("retain")),
                #("op", json.string("retainDetached")),
                #("name", json.string("node")),
                #(
                  "atom",
                  json.object([
                    #("revision", json.string("not-a-revision")),
                    #("localId", json.int(0)),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ]),
      "forest fixture",
    ),
    #(
      runner_input([
        json.object([
          #("id", json.string("bad-schema")),
          #("schema", json.string("{}")),
          #("root", json.null()),
          #("actions", array([observe_action("observe")])),
        ]),
      ]),
      "schema",
    ),
    #(
      runner_input([
        json.object([
          #("id", json.string("bad-value")),
          #("schema", json.string(optional_string_schema)),
          #("root", json.object([#("kind", json.string("future"))])),
          #("actions", array([observe_action("observe")])),
        ]),
      ]),
      "forest fixture",
    ),
  ]
  |> list.each(fn(item) { forest_fixture.run(item.0) |> error_contains(item.1) })
}

pub fn shared_tree_forest_fixture_copy_invalidates_real_references_test() -> Nil {
  let input =
    runner_input([
      scenario("copy-scope", tagged_string("root"), [
        json.object([
          #("id", json.string("retain")),
          #("op", json.string("retain")),
          #("name", json.string("root")),
          #("path", array([])),
        ]),
        json.object([
          #("id", json.string("copy")),
          #("op", json.string("copy")),
        ]),
      ]),
    ])
  let state = fn(status: String, value: json.Json) {
    json.object([
      #("root", tagged_string("root")),
      #(
        "references",
        array([
          json.object([
            #("name", json.string("root")),
            #("status", json.string(status)),
            #("value", value),
          ]),
        ]),
      ),
      #("detached", array([])),
      #("nextDetachedRootId", json.int(0)),
    ])
  }
  let expected =
    json.object([
      #(
        "observations",
        array([
          json.object([
            #("id", json.string("copy-scope")),
            #(
              "checkpoints",
              array([
                json.object([
                  #("id", json.string("retain")),
                  #("accepted", json.bool(True)),
                  #("state", state("attached", tagged_string("root"))),
                ]),
                json.object([
                  #("id", json.string("copy")),
                  #("accepted", json.bool(True)),
                  #("state", state("invalidated-by-copy", json.null())),
                ]),
              ]),
            ),
          ]),
        ]),
      ),
    ])
  let assert Ok(actual) = forest_fixture.run(input)
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
}
