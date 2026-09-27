import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import startest/expect
import watershed/canonical_json
import watershed/tree/array_fixture
import watershed/tree/array_forest_fixture
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/types

const items_type = "org.watershed.shared-tree.m3.Items"

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}

fn atom(local_id: Int) -> types.AtomId {
  types.AtomId(None, local_id)
}

fn empty_delta() -> forest.DeltaData {
  forest.DeltaData(None, [], [], [], [], [], [])
}

fn root_marks(marks: List(forest.Mark)) -> List(#(String, forest.FieldDelta)) {
  [
    #(
      "rootFieldKey",
      forest.FieldDelta([
        forest.Mark(1, None, None, [
          #("", forest.FieldDelta(marks)),
        ]),
      ]),
    ),
  ]
}

fn apply(state: forest.Forest, data: forest.DeltaData) -> forest.Forest {
  let assert Ok(delta) = forest.delta(data)
  let assert Ok(state) = forest.apply_delta(state, delta)
  state
}

pub fn shared_tree_array_forest_interleaved_counted_renames_match_atom_order_test() {
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(types.ArrayValue(items_type, [])),
    )
  let built =
    apply(
      initial,
      forest.DeltaData(..empty_delta(), build: [
        forest.Build(atom(0), [
          types.StringValue("A"),
          types.StringValue("B"),
        ]),
        forest.Build(atom(11), [
          types.StringValue("C"),
          types.StringValue("D"),
        ]),
      ]),
    )
  let assert Ok(a) = forest.locate_detached(built, atom(0))
  let assert Ok(b) = forest.locate_detached(built, atom(1))
  let assert Ok(c) = forest.locate_detached(built, atom(11))
  let assert Ok(d) = forest.locate_detached(built, atom(12))
  let renamed =
    apply(
      built,
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(0), atom(10), 2),
        forest.Rename(atom(11), atom(0), 2),
      ]),
    )
  forest.locate_detached(renamed, atom(10)) |> expect.to_equal(Ok(a))
  forest.locate_detached(renamed, atom(11)) |> expect.to_equal(Ok(b))
  forest.locate_detached(renamed, atom(0)) |> expect.to_equal(Ok(c))
  forest.locate_detached(renamed, atom(1)) |> expect.to_equal(Ok(d))
}

pub fn shared_tree_array_forest_counted_rename_keeps_source_allocation_order_test() {
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
          types.StringValue("D"),
        ]),
      ),
    )
  let assert Ok(retained) = forest.locate(initial, ["1"])
  let detached =
    apply(
      initial,
      forest.DeltaData(
        ..empty_delta(),
        fields: root_marks([
          forest.Mark(1, None, None, []),
          forest.Mark(3, None, Some(atom(3)), []),
        ]),
      ),
    )
  let renamed =
    apply(
      detached,
      forest.DeltaData(..empty_delta(), rename: [
        forest.Rename(atom(3), atom(10), 3),
      ]),
    )
  forest.locate_detached(renamed, atom(10))
  |> expect.to_equal(Ok(retained))
  let assert Ok(data) = forest.export_data(renamed)
  let assert Ok(entry) =
    list.find(data.detached, fn(entry) { entry.id == atom(10) })
  entry.forest_root_id |> expect.to_equal(3)
}

fn source_atom(major: Option(Int), minor: Int) -> Json {
  json.object([
    #("major", case major {
      None -> json.null()
      Some(major) -> json.int(major)
    }),
    #("minor", json.int(minor)),
  ])
}

fn source_string(value: String) -> Json {
  json.object([
    #("type", json.string("com.fluidframework.leaf.string")),
    #("value", json.string(value)),
    #("fields", array([])),
  ])
}

fn source_node(fields: List(#(String, List(Json)))) -> Json {
  json.object([
    #("type", json.string("org.watershed.shared-tree.m3.ForestNode")),
    #(
      "fields",
      array(
        list.map(fields, fn(field) {
          array([json.string(field.0), array(field.1)])
        }),
      ),
    ),
  ])
}

fn visible_node(fields: List(#(String, List(Json)))) -> Json {
  json.object([
    #("type", json.string("org.watershed.shared-tree.m3.ForestNode")),
    #(
      "fields",
      array(
        list.map(fields, fn(field) {
          array([json.string(field.0), array(field.1)])
        }),
      ),
    ),
  ])
}

fn source_mark(
  count: Int,
  attach: Option(Json),
  detach: Option(Json),
  fields: List(Json),
) -> Json {
  let entries = [#("count", json.int(count))]
  let entries = case attach {
    None -> entries
    Some(attach) -> list.append(entries, [#("attach", attach)])
  }
  let entries = case detach {
    None -> entries
    Some(detach) -> list.append(entries, [#("detach", detach)])
  }
  let entries = case fields {
    [] -> entries
    fields -> list.append(entries, [#("fields", array(fields))])
  }
  json.object(entries)
}

fn source_field(key: String, marks: List(Json)) -> Json {
  array([
    json.string(key),
    json.object([#("marks", array(marks))]),
  ])
}

fn source_build(id: Json, trees: List(Json)) -> Json {
  json.object([#("id", id), #("trees", array(trees))])
}

fn source_destroy(id: Json, count: Int) -> Json {
  json.object([#("id", id), #("count", json.int(count))])
}

fn source_delta(
  fields: List(Json),
  build: List(Json),
  destroy: List(Json),
) -> Json {
  let entries = []
  let entries = case fields {
    [] -> entries
    fields -> [#("fields", array(fields)), ..entries]
  }
  let entries = case build {
    [] -> entries
    build -> [#("build", array(build)), ..entries]
  }
  let entries = case destroy {
    [] -> entries
    destroy -> [#("destroy", array(destroy)), ..entries]
  }
  json.object(list.reverse(entries))
}

fn apply_scenario(
  id: String,
  initial: List(Json),
  deltas: List(Json),
  retained: Option(Int),
  revisions: List(Int),
) -> Json {
  json.object([
    #("id", json.string(id)),
    #("operation", json.string("apply-deltas")),
    #("initialState", json.object([#("field", array(initial))])),
    #(
      "operands",
      json.object([
        #("deltas", array(deltas)),
        #("retainIndex", case retained {
          None -> json.null()
          Some(index) -> json.int(index)
        }),
      ]),
    ),
    #("revisions", array(list.map(revisions, json.int))),
  ])
}

fn move_scenario(
  initial: Json,
  source_path: List(Int),
  source_start: Int,
  source_end: Int,
  destination_path: List(Int),
  destination_gap: Int,
) -> Json {
  json.object([
    #("id", json.string("move")),
    #("operation", json.string("public-move-cycle")),
    #("initialState", initial),
    #(
      "operands",
      json.object([
        #(
          "move",
          json.object([
            #("sourcePath", array(list.map(source_path, json.int))),
            #("sourceStart", json.int(source_start)),
            #("sourceEnd", json.int(source_end)),
            #("destinationPath", array(list.map(destination_path, json.int))),
            #("destinationGap", json.int(destination_gap)),
          ]),
        ),
      ]),
    ),
    #("revisions", array([])),
  ])
}

fn runner_input(scenario: Json) -> Json {
  json.object([#("scenarios", array([scenario]))])
}

fn result_object(accepted: Bool, value: Json) -> Json {
  json.object([#("accepted", json.bool(accepted)), #("value", value)])
}

fn state(root: List(Json), detached: List(Json)) -> Json {
  json.object([#("root", array(root)), #("detached", array(detached))])
}

fn state_after(root: List(Json), detached: List(Json), identity: Json) -> Json {
  json.object([
    #("root", array(root)),
    #("detached", array(detached)),
    #("identity", identity),
  ])
}

fn detached(id: Json, values: List(Json)) -> Json {
  json.object([#("id", id), #("values", array(values))])
}

fn checkpoint(before: Json, delta: Json, after: Json) -> Json {
  json.object([
    #("before", before),
    #("delta", delta),
    #("result", result_object(True, json.object([]))),
    #("after", after),
  ])
}

fn observation(id: String, value: Json) -> Json {
  json.object([
    #("id", json.string(id)),
    #("executed", json.bool(True)),
    #("accepted", json.bool(True)),
    #("value", value),
    #("result", value),
  ])
}

fn expected(id: String, value: Json) -> Json {
  json.object([#("observations", array([observation(id, value)]))])
}

fn expect_run(scenario: Json, expected: Json) {
  let assert Ok(actual) = array_forest_fixture.run(runner_input(scenario))
  canonical(actual) |> expect.to_equal(canonical(expected))
}

fn canonical(value: Json) -> String {
  let assert Ok(value) = codec.parse(value)
  canonical_json.to_string(value)
}

pub fn shared_tree_array_forest_runner_uses_both_move_paths_test() {
  let scenario =
    move_scenario(
      array([
        array([json.string("A"), json.string("B")]),
        json.string("sibling"),
      ]),
      [0],
      0,
      1,
      [0],
      2,
    )
  let moved =
    array([array([json.string("B"), json.string("A")]), json.string("sibling")])
  let value =
    json.object([
      #(
        "before",
        array([
          array([json.string("A"), json.string("B")]),
          json.string("sibling"),
        ]),
      ),
      #("result", result_object(True, moved)),
      #("after", moved),
    ])
  expect_run(scenario, expected("move", value))
}

pub fn shared_tree_array_forest_runner_preserves_nested_sequence_fields_test() {
  let old = source_string("old")
  let old_two = source_string("old2")
  let new = source_string("new")
  let new_two = source_string("new2")
  let first = source_node([#("label", [source_string("A")])])
  let second = source_node([#("label", [source_string("B")])])
  let third =
    source_node([
      #("label", [source_string("C")]),
      #("child", [old, old_two]),
    ])
  let child_delta =
    source_field("child", [
      source_mark(
        2,
        Some(source_atom(Some(-4), 10)),
        Some(source_atom(Some(-4), 20)),
        [],
      ),
    ])
  let delta =
    source_delta(
      [
        source_field("rootFieldKey", [
          source_mark(2, None, None, []),
          source_mark(1, None, None, [child_delta]),
        ]),
      ],
      [source_build(source_atom(Some(-4), 10), [new, new_two])],
      [],
    )
  let scenario =
    apply_scenario("nested", [first, second, third], [delta], None, [-4])
  let first_node = visible_node([#("label", [json.string("A")])])
  let second_node = visible_node([#("label", [json.string("B")])])
  let before_third =
    visible_node([
      #("label", [json.string("C")]),
      #("child", [json.string("old"), json.string("old2")]),
    ])
  let after_third =
    visible_node([
      #("label", [json.string("C")]),
      #("child", [json.string("new"), json.string("new2")]),
    ])
  let before = state([first_node, second_node, before_third], [])
  let after =
    state_after(
      [first_node, second_node, after_third],
      [
        detached(source_atom(Some(-4), 20), [json.string("old")]),
        detached(source_atom(Some(-4), 21), [json.string("old2")]),
      ],
      json.null(),
    )
  expect_run(
    scenario,
    expected(
      "nested",
      array([
        checkpoint(before, delta, after),
      ]),
    ),
  )
}

pub fn shared_tree_array_forest_runner_observes_destroyed_reference_as_absent_test() {
  let detached_id = source_atom(Some(-2), 3)
  let detach_delta =
    source_delta(
      [
        source_field("rootFieldKey", [
          source_mark(1, None, None, []),
          source_mark(3, None, Some(detached_id), []),
        ]),
      ],
      [],
      [],
    )
  let destroy_delta = source_delta([], [], [source_destroy(detached_id, 3)])
  let scenario =
    apply_scenario(
      "destroyed",
      [
        source_string("A"),
        source_string("B"),
        source_string("C"),
        source_string("D"),
      ],
      [detach_delta, destroy_delta],
      Some(1),
      [-2],
    )
  let detached_b = detached(detached_id, [json.string("B")])
  let detached_c = detached(source_atom(Some(-2), 4), [json.string("C")])
  let detached_d = detached(source_atom(Some(-2), 5), [json.string("D")])
  let detached_values = [detached_b, detached_c, detached_d]
  let first =
    checkpoint(
      state(
        [
          json.string("A"),
          json.string("B"),
          json.string("C"),
          json.string("D"),
        ],
        [],
      ),
      detach_delta,
      state_after(
        [json.string("A")],
        detached_values,
        json.object([
          #("field", json.string("watershed-array-forest-0")),
          #("index", json.int(0)),
          #("parent", json.null()),
        ]),
      ),
    )
  let second =
    checkpoint(
      state([json.string("A")], detached_values),
      destroy_delta,
      state_after([json.string("A")], [], json.null()),
    )
  expect_run(scenario, expected("destroyed", array([first, second])))
}

pub fn shared_tree_array_forest_runner_preserves_detached_insertion_order_test() {
  let ten = source_atom(Some(-2), 10)
  let zero = source_atom(Some(-2), 0)
  let first_delta =
    source_delta([], [source_build(ten, [source_string("B")])], [])
  let second_delta =
    source_delta([], [source_build(zero, [source_string("A")])], [])
  let scenario =
    apply_scenario("order", [], [first_delta, second_delta], None, [-2])
  let detached_b = detached(ten, [json.string("B")])
  let detached_a = detached(zero, [json.string("A")])
  let first =
    checkpoint(
      state([], []),
      first_delta,
      state_after([], [detached_b], json.null()),
    )
  let second =
    checkpoint(
      state([], [detached_b]),
      second_delta,
      state_after([], [detached_b, detached_a], json.null()),
    )
  expect_run(scenario, expected("order", array([first, second])))
}

pub fn shared_tree_array_forest_runner_accepts_unrevisioned_atoms_test() {
  let id = source_atom(None, 0)
  let delta =
    source_delta(
      [
        source_field("rootFieldKey", [
          source_mark(3, Some(id), None, []),
        ]),
      ],
      [
        source_build(id, [
          source_string("A"),
          source_string("B"),
          source_string("C"),
        ]),
      ],
      [],
    )
  let scenario = apply_scenario("anonymous", [], [delta], None, [])
  let after =
    state_after(
      [json.string("A"), json.string("B"), json.string("C")],
      [],
      json.null(),
    )
  expect_run(
    scenario,
    expected(
      "anonymous",
      array([
        checkpoint(state([], []), delta, after),
      ]),
    ),
  )
}

pub fn shared_tree_array_forest_runner_does_not_relabel_other_move_errors_test() {
  let scenario =
    move_scenario(
      array([array([json.string("A")]), json.string("sibling")]),
      [0],
      0,
      2,
      [0],
      3,
    )
  let assert Ok(output) = array_forest_fixture.run(runner_input(scenario))
  let raw = json.to_string(output)
  string.contains(raw, "Invalid move operation") |> expect.to_be_false
  string.contains(raw, "\"accepted\":false") |> expect.to_be_true
}
