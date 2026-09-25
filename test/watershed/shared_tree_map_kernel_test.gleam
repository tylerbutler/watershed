import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/types
import watershed/tree_kernel

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

fn session() -> fluid_ids.SessionId {
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  session
}

fn state_for(
  schema_name: String,
  root: types.TreeValue,
) -> tree_kernel.TreeState {
  let assert Ok(fixture) = fixtures.load("map-schema-content")
  let assert Ok(raw) =
    json.parse(json.to_string(fixture.input), {
      use raw <- decode.field("schemas", {
        use raw <- decode.field(schema_name, decode.string)
        decode.success(raw)
      })
      decode.success(raw)
    })
  let assert Ok(stored) = schema.stored_from_string(raw)
  let assert Ok(view) = schema.view_from_string(raw)
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(Some(root), [], 0),
      history.inspect(history.new(session())).sequenced,
    )
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id, session(), view)
  state
}

fn object_state(entries: List(#(String, types.TreeValue))) {
  state_for(
    "objectContainedMap",
    types.ObjectValue("org.watershed.shared-tree.m2.Root", [
      #("items", types.MapValue(map_type, entries)),
    ]),
  )
}

pub fn shared_tree_map_kernel_reads_root_and_empty_maps_test() {
  let state =
    state_for(
      "rootMap",
      types.MapValue(map_type, [#("a/b", types.StringValue("safe"))]),
    )
  tree_kernel.map_get(state, [], "a/b")
  |> expect.to_equal(Ok(Some(types.StringValue("safe"))))
  tree_kernel.map_get(state, [], "absent") |> expect.to_equal(Ok(None))
  tree_kernel.map_entries(state, [])
  |> expect.to_equal(Ok([#("a/b", types.StringValue("safe"))]))
  let empty = state_for("rootMap", types.MapValue(map_type, []))
  tree_kernel.map_entries(empty, []) |> expect.to_equal(Ok([]))
  tree_kernel.map_get(empty, [], "") |> expect.to_equal(Ok(None))
}

pub fn shared_tree_map_kernel_preserves_canonical_keys_test() {
  let keys = [
    "", "01", "10", "2", "__proto__", "\u{e9}", "\u{6c34}", "\u{fffd}",
    "\u{10000}",
  ]
  let entries = list.map(keys, fn(key) { #(key, types.StringValue(key)) })
  let state = object_state(list.reverse(entries))
  tree_kernel.map_entries(state, ["items"]) |> expect.to_equal(Ok(entries))
  list.each(entries, fn(entry) {
    tree_kernel.map_get(state, ["items"], entry.0)
    |> expect.to_equal(Ok(Some(entry.1)))
  })
}

pub fn shared_tree_map_kernel_checks_map_targets_test() {
  let state =
    object_state([
      #("leaf", types.StringValue("value")),
      #("nested", types.MapValue(map_type, [])),
    ])
  tree_kernel.map_entries(state, ["items", "nested"])
  |> expect.to_equal(Ok([]))
  [
    #([], "node is not a map"),
    #(["items", "leaf"], "node is not a map"),
    #(["items", "absent"], "field is absent"),
  ]
  |> list.each(fn(entry) {
    tree_kernel.map_get(state, entry.0, "key")
    |> expect.to_equal(Error(types.InvalidEdit(entry.0, entry.1)))
    tree_kernel.map_entries(state, entry.0)
    |> expect.to_equal(Error(types.InvalidEdit(entry.0, entry.1)))
  })
}

pub fn shared_tree_map_kernel_reads_pending_edits_not_snapshot_test() {
  let initial = object_state([])
  let #(edited, _) =
    list.fold(
      [
        #(types.MapSet(["items"], "key", types.StringValue("first")), True),
        #(types.MapSet(["items"], "key", types.StringValue("second")), True),
        #(types.MapDelete(["items"], "key"), True),
        #(types.MapDelete(["items"], "key"), False),
      ],
      #(initial, fluid_ids.new(session())),
      fn(acc, entry) {
        let assert Ok(#(next, _, events, compressor)) =
          tree_runtime.author_edit(acc.0, entry.0, acc.1)
        events
        |> expect.to_equal(case entry.1 {
          True -> [tree_kernel.TreeChanged(True)]
          False -> []
        })
        tree_kernel.snapshot(next)
        |> expect.to_equal(tree_kernel.snapshot(initial))
        #(next, compressor)
      },
    )
  tree_kernel.map_get(edited, ["items"], "key") |> expect.to_equal(Ok(None))
  tree_kernel.history_view(edited).pending |> list.length |> expect.to_equal(4)
  let assert Ok(data) = tree_kernel.visible_data(edited)
  data.detached |> list.length |> expect.to_equal(2)
  let assert Ok(commits) = tree_kernel.resubmit_commits(edited)
  list.length(commits) |> expect.to_equal(4)
}

pub fn shared_tree_map_kernel_reads_nested_local_edits_test() {
  let initial =
    object_state([
      #(
        "point",
        types.ObjectValue("org.watershed.shared-tree.m2.Point", [
          #("x", types.NumberValue(1.0)),
          #("y", types.NumberValue(2.0)),
        ]),
      ),
      #("nested", types.MapValue(map_type, [])),
    ])
  let assert Ok(#(edited, _, _, compressor)) =
    tree_runtime.author_edit(
      initial,
      types.SetField(["items", "point", "x"], types.NumberValue(3.0)),
      fluid_ids.new(session()),
    )
  let assert Ok(#(edited, _, _, _)) =
    tree_runtime.author_edit(
      edited,
      types.MapSet(["items", "nested"], "", types.StringValue("inside")),
      compressor,
    )
  tree_kernel.map_get(edited, ["items"], "point")
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("org.watershed.shared-tree.m2.Point", [
          #("x", types.NumberValue(3.0)),
          #("y", types.NumberValue(2.0)),
        ]),
      ),
    ),
  )
  tree_kernel.map_entries(edited, ["items", "nested"])
  |> expect.to_equal(Ok([#("", types.StringValue("inside"))]))
}
