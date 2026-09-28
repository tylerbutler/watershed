import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/array_fixture
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/types
import watershed/tree_kernel

const items_type = "org.watershed.shared-tree.m3.Items"

fn core() -> runtime_core.Core {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [view] = input.tree_views
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view.view_id,
      array_fixture.stored("rootArray"),
      forest.ForestData(
        Some(
          types.ArrayValue(items_type, [
            types.StringValue("A"),
            types.StringValue("B"),
          ]),
        ),
        [],
        0,
      ),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        sequence_number: 0,
        minimum_sequence_number: 0,
        tree_views: [
          runtime_core.TreeViewSeed(
            ..view,
            view: array_fixture.view("rootArray"),
          ),
        ],
        channels: list.map(input.channels, fn(seed) {
          case seed.route == view.route {
            True ->
              runtime_core.ChannelSeed(
                ..seed,
                snapshot: channel.TreeSnapshot(snapshot),
              )
            False -> seed
          }
        }),
      ),
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("array-writer", [], 0),
      seed,
    )
  core
}

pub fn shared_tree_array_empty_edits_preserve_runtime_submission_test() {
  let before = core()
  let edits = [
    types.ArrayInsert([], 2, []),
    types.ArrayRemove([], 1, 1),
    types.ArrayMove([], 1, 1, [], 0),
  ]
  list.each(edits, fn(edit) {
    runtime_core.submit_tree_edits(before, "A/_C", [edit])
    |> expect.to_equal(Ok(#(before, [], [])))
  })
  runtime_core.submit_tree_edits(before, "A/_C", edits)
  |> expect.to_equal(Ok(#(before, [], [])))
}

pub fn shared_tree_array_empty_authoring_does_not_allocate_revision_test() {
  let core = core()
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  let assert Some(compressor) = core.compressor
  let assert Ok(#(after, commit, events, allocated)) =
    tree_runtime.author_edit(state, types.ArrayInsert([], 0, []), compressor)
  after |> expect.to_equal(state)
  commit |> expect.to_equal(None)
  events |> expect.to_equal([])
  allocated |> expect.to_equal(compressor)
}

pub fn shared_tree_array_empty_invalid_batch_is_atomic_test() {
  let original = core()
  let real = types.ArrayInsert([], 0, [types.StringValue("C")])
  let invalid = [
    types.ArrayInsert([], 4, []),
    types.ArrayRemove([], 4, 4),
    types.ArrayMove([], 0, 0, [], 4),
    types.ArrayMove([], 0, 0, ["0"], 0),
    types.ArrayInsert(["missing"], 0, []),
    types.ArrayRemove([], 0, 9_007_199_254_740_992),
  ]
  list.each(invalid, fn(edit) {
    runtime_core.submit_tree_edits(original, "A/_C", [real, edit])
    |> expect.to_be_error()
    runtime_core.submit_tree_edits(original, "A/_C", [real])
    |> expect.to_equal(runtime_core.submit_tree_edits(core(), "A/_C", [real]))
  })
}

pub fn shared_tree_array_mixed_noops_preserve_real_commit_order_test() {
  let before = core()
  let insert = types.ArrayInsert([], 0, [types.StringValue("C")])
  let remove = types.ArrayRemove([], 2, 3)
  runtime_core.submit_tree_edits(before, "A/_C", [
    types.ArrayRemove([], 1, 1),
    insert,
    types.ArrayInsert([], 3, []),
    remove,
    types.ArrayMove([], 0, 0, [], 2),
  ])
  |> expect.to_equal(
    runtime_core.submit_tree_edits(before, "A/_C", [insert, remove]),
  )
}

pub fn shared_tree_array_empty_edits_leave_compressor_creation_range_test() {
  let core = core()
  let assert Some(compressor) = core.compressor
  let assert Ok(#(compressor, _)) = fluid_ids.generate(compressor)
  let before = runtime_core.Core(..core, compressor: Some(compressor))
  runtime_core.submit_tree_edits(before, "A/_C", [types.ArrayRemove([], 0, 0)])
  |> expect.to_equal(Ok(#(before, [], [])))
}
