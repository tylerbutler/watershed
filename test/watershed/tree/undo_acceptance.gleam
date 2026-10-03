import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import spillway/types as spillway_types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_document

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"Point\"]}}}},\"NamedMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"Point\"]}}},\"Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"featured\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"byKey\":{\"kind\":\"Value\",\"types\":[\"NamedMap\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const point_type = "Point"

const items_type = "Items"

const map_type = "NamedMap"

pub fn assert_object_set() {
  assert_local_case(
    types.SetField(["title"], types.StringValue("target")),
    types.SetField(["note"], types.StringValue("later")),
    root(
      "base",
      Some("later"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [right_a()],
      [#("seed", types.StringValue("value"))],
    ),
  )
}

pub fn assert_object_replacement() {
  assert_local_case(
    types.SetField(
      ["featured"],
      point("replacement", 9.0, "8f95be09-8376-4ff7-8755-ccd7e8124b0b"),
    ),
    types.SetField(["featured", "label"], types.StringValue("later-child-edit")),
    initial_root(),
  )
}

pub fn assert_map_set() {
  assert_local_case(
    types.MapSet(
      ["byKey"],
      "target",
      point("target", 4.0, "8f95be09-8376-4ff7-8755-ccd7e8124b0b"),
    ),
    types.MapSet(["byKey"], "later", types.StringValue("preserved")),
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [right_a()],
      [
        #("later", types.StringValue("preserved")),
        #("seed", types.StringValue("value")),
      ],
    ),
  )
}

pub fn assert_map_delete() {
  assert_local_case(
    types.MapDelete(["byKey"], "seed"),
    types.MapSet(["byKey"], "seed", types.StringValue("later")),
    initial_root(),
  )
}

pub fn assert_array_insert() {
  assert_local_case(
    types.ArrayInsert(["left"], 1, [
      point("target", 4.0, "8f95be09-8376-4ff7-8755-ccd7e8124b0b"),
    ]),
    types.ArrayInsert(["left"], 0, [types.StringValue("later")]),
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [types.StringValue("later"), left_a(), left_b()],
      [right_a()],
      [#("seed", types.StringValue("value"))],
    ),
  )
}

pub fn assert_array_remove() {
  assert_local_case(
    types.ArrayRemove(["left"], 0, 1),
    types.ArrayMove(["left"], 0, 1, ["right"], 1),
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a()],
      [right_a(), left_b()],
      [#("seed", types.StringValue("value"))],
    ),
  )
}

pub fn assert_same_array_move() {
  assert_local_case(
    types.ArrayMove(["left"], 0, 1, ["left"], 2),
    types.ArrayInsert(["left"], 1, [types.StringValue("later")]),
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b(), types.StringValue("later")],
      [right_a()],
      [#("seed", types.StringValue("value"))],
    ),
  )
}

pub fn assert_cross_array_move() {
  assert_local_case(
    types.ArrayMove(["left"], 0, 1, ["right"], 1),
    types.ArrayRemove(["right"], 0, 1),
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [],
      [#("seed", types.StringValue("value"))],
    ),
  )
}

pub fn assert_transaction() {
  let writer = core("writer", "30000000-0000-4000-8000-000000000003")
  let peer = core("peer", "50000000-0000-4000-8000-000000000005")
  let active =
    runtime_core.begin_tree_transaction(writer, "A/_C", view(), [])
    |> expect.to_be_ok()
  let #(active, edit_events, edit_outbound) =
    runtime_core.submit_tree_edits_view(active, "A/_C", view(), [
      types.SetField(["title"], types.StringValue("transaction")),
      types.SetField(["count"], types.NumberValue(2.0)),
      types.ArrayInsert(["left"], 2, [types.StringValue("transaction-item")]),
    ])
    |> expect.to_be_ok()
  edit_events |> expect.to_equal([])
  edit_outbound |> expect.to_equal([])
  let assert #(pending, events, [target_outbound]) =
    runtime_core.commit_tree_transaction(active, "A/_C")
    |> expect.to_be_ok()
  assert_applied(events, types.DefaultCommit)
  let target_revision = applied_revision(events)
  let target_message = message(pending, target_outbound, 1, 0)
  let #(settled, target_settlement) =
    runtime_core.handle_sequenced(pending, target_message)
    |> expect.to_be_ok()
  assert_settlement(target_settlement.events, target_revision)
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, target_message) |> expect.to_be_ok()
  let #(retained, handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let assert #(peer, _, [later_outbound]) =
    runtime_core.submit_tree_edits(peer, "A/_C", [
      types.MapSet(["byKey"], "remote", types.StringValue("preserved")),
    ])
    |> expect.to_be_ok()
  let later_message = message(peer, later_outbound, 2, 1)
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, later_message) |> expect.to_be_ok()
  let #(retained, _) =
    runtime_core.handle_sequenced(retained, later_message)
    |> expect.to_be_ok()
  let expected =
    root(
      "base",
      Some("seed"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [right_a()],
      [
        #("remote", types.StringValue("preserved")),
        #("seed", types.StringValue("value")),
      ],
    )
  let #(undone, events, undo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", handle) |> expect.to_be_ok()
  assert_applied(events, types.UndoCommit)
  assert_root(undone, expected)
  let undo_revision = applied_revision(events)
  let #(settled, settlement) =
    runtime_core.handle_sequenced(undone, message(undone, undo_outbound, 3, 2))
    |> expect.to_be_ok()
  assert_settlement(settlement.events, undo_revision)
  assert_root(settled, expected)
  runtime_core.tree_read(peer, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("transaction"))))
}

pub fn assert_identifier() {
  let writer = core("writer", "30000000-0000-4000-8000-000000000003")
  let peer = core("peer", "50000000-0000-4000-8000-000000000005")
  let assert #(pending, target_events, [target_outbound]) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.MapSet(
        ["byKey"],
        "generated",
        types.ObjectValue(point_type, [
          #("label", types.StringValue("generated")),
          #("x", types.NumberValue(7.0)),
        ]),
      ),
    ])
    |> expect.to_be_ok()
  assert_applied(target_events, types.DefaultCommit)
  let target_revision = applied_revision(target_events)
  let assert Ok(Some(types.StringValue(identifier))) =
    runtime_core.tree_read(pending, "A/_C", ["byKey", "generated", "id"])
  let target_message = message(pending, target_outbound, 1, 0)
  let #(settled, target_settlement) =
    runtime_core.handle_sequenced(pending, target_message)
    |> expect.to_be_ok()
  assert_settlement(target_settlement.events, target_revision)
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, target_message) |> expect.to_be_ok()
  let #(retained, target_handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let assert #(peer, _, [later_outbound]) =
    runtime_core.submit_tree_edits(peer, "A/_C", [
      types.SetField(["note"], types.StringValue("remote")),
    ])
    |> expect.to_be_ok()
  let later_message = message(peer, later_outbound, 2, 1)
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, later_message) |> expect.to_be_ok()
  let #(retained, _) =
    runtime_core.handle_sequenced(retained, later_message)
    |> expect.to_be_ok()
  let #(undone, undo_events, undo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", target_handle)
    |> expect.to_be_ok()
  assert_applied(undo_events, types.UndoCommit)
  let expected_undo =
    root(
      "base",
      Some("remote"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [right_a()],
      [#("seed", types.StringValue("value"))],
    )
  assert_root(undone, expected_undo)
  runtime_core.tree_read(undone, "A/_C", ["byKey", "generated"])
  |> expect.to_equal(Ok(None))
  runtime_core.tree_read(undone, "A/_C", ["note"])
  |> expect.to_equal(Ok(Some(types.StringValue("remote"))))
  let undo_revision = applied_revision(undo_events)
  let #(undone, undo_settlement) =
    runtime_core.handle_sequenced(undone, message(undone, undo_outbound, 3, 2))
    |> expect.to_be_ok()
  assert_settlement(undo_settlement.events, undo_revision)
  assert_root(undone, expected_undo)
  let #(retained, undo_handle) =
    runtime_core.retain_tree_revertible(
      undone,
      "A/_C",
      undo_revision,
      types.UndoCommit,
    )
    |> expect.to_be_ok()
  let #(redone, redo_events, redo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", undo_handle)
    |> expect.to_be_ok()
  assert_applied(redo_events, types.RedoCommit)
  let expected_redo =
    root(
      "base",
      Some("remote"),
      0.0,
      point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
      [left_a(), left_b()],
      [right_a()],
      [
        #(
          "generated",
          types.ObjectValue(point_type, [
            #("label", types.StringValue("generated")),
            #("x", types.NumberValue(7.0)),
            #("id", types.StringValue(identifier)),
          ]),
        ),
        #("seed", types.StringValue("value")),
      ],
    )
  assert_root(redone, expected_redo)
  runtime_core.tree_read(redone, "A/_C", ["byKey", "generated", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(identifier))))
  let redo_revision = applied_revision(redo_events)
  let #(redone, redo_settlement) =
    runtime_core.handle_sequenced(redone, message(redone, redo_outbound, 4, 3))
    |> expect.to_be_ok()
  assert_settlement(redo_settlement.events, redo_revision)
  assert_root(redone, expected_redo)
  runtime_core.tree_read(redone, "A/_C", ["note"])
  |> expect.to_equal(Ok(Some(types.StringValue("remote"))))
  runtime_core.tree_read(peer, "A/_C", ["byKey", "generated", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(identifier))))
}

pub fn assert_live_handle_reconnect() {
  let writer = core("writer", "30000000-0000-4000-8000-000000000003")
  let peer = core("peer", "50000000-0000-4000-8000-000000000005")
  let assert #(pending, events, [outbound]) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.SetField(["title"], types.StringValue("target")),
    ])
    |> expect.to_be_ok()
  let revision = applied_revision(events)
  let accepted = message(pending, outbound, 1, 0)
  let #(settled, settlement) =
    runtime_core.handle_sequenced(pending, accepted) |> expect.to_be_ok()
  assert_settlement(settlement.events, revision)
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, accepted) |> expect.to_be_ok()
  let #(retained, handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let assert #(peer, _, [later]) =
    runtime_core.submit_tree_edits(peer, "A/_C", [
      types.SetField(["note"], types.StringValue("remote")),
    ])
    |> expect.to_be_ok()
  let later = message(peer, later, 2, 1)
  let reconnected =
    runtime_core.adopt_reconnect(
      retained,
      runtime_fixture.connected("rejoined", [], 1),
    )
    |> expect.to_be_ok()
  let #(caught_up, _) =
    runtime_core.handle_sequenced(reconnected, later) |> expect.to_be_ok()
  let live = runtime_core.go_live(caught_up)
  runtime_core.tree_revertible_is_valid(live, "A/_C", handle)
  |> expect.to_be_true()
  let #(undone, events, outbound) =
    runtime_core.revert_tree(live, "A/_C", handle) |> expect.to_be_ok()
  assert_applied(events, types.UndoCommit)
  runtime_core.tree_read(undone, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
  runtime_core.tree_read(undone, "A/_C", ["note"])
  |> expect.to_equal(Ok(Some(types.StringValue("remote"))))
  let undo_revision = applied_revision(events)
  let #(settled, settlement) =
    runtime_core.handle_sequenced(undone, message(undone, outbound, 3, 2))
    |> expect.to_be_ok()
  assert_settlement(settlement.events, undo_revision)
  runtime_core.tree_read(settled, "A/_C", ["note"])
  |> expect.to_equal(Ok(Some(types.StringValue("remote"))))
}

pub fn assert_pending_undo_accepted_before_drop() {
  let writer = core("writer", "30000000-0000-4000-8000-000000000003")
  let assert #(pending, events, [outbound]) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.SetField(["title"], types.StringValue("target")),
    ])
    |> expect.to_be_ok()
  let target_revision = applied_revision(events)
  let #(settled, _) =
    runtime_core.handle_sequenced(pending, message(pending, outbound, 1, 0))
    |> expect.to_be_ok()
  let #(retained, handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let #(undone, undo_events, undo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", handle)
    |> expect.to_be_ok()
  assert_applied(undo_events, types.UndoCommit)
  let undo_revision = applied_revision(undo_events)
  let accepted_message = message(undone, undo_outbound, 2, 1)
  let reconnected =
    runtime_core.adopt_reconnect(
      undone,
      runtime_fixture.connected("rejoined", [], 2),
    )
    |> expect.to_be_ok()
  let #(accepted, first) =
    runtime_core.handle_sequenced(reconnected, accepted_message)
    |> expect.to_be_ok()
  assert_settlement(first.events, undo_revision)
  runtime_core.tree_read(accepted, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
  let #(live, resent) =
    runtime_core.resubmit(runtime_core.go_live(accepted))
    |> expect.to_be_ok()
  resent |> expect.to_equal([])
  let #(duplicate, second) =
    runtime_core.handle_sequenced(live, accepted_message) |> expect.to_be_ok()
  second.events |> expect.to_equal([])
  runtime_core.tree_read(duplicate, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
}

pub fn assert_independent_history_pins() {
  let local = session("00000000-0000-4000-8000-000000000001")
  let revisions = [
    stable("00000000-0000-4000-8000-000000000101"),
    stable("00000000-0000-4000-8000-000000000102"),
    stable("00000000-0000-4000-8000-000000000103"),
    stable("00000000-0000-4000-8000-000000000104"),
    stable("00000000-0000-4000-8000-000000000105"),
  ]
  let assert [revision_a, revision_b, revision_c, undo_b, undo_c] = revisions
  let assert Ok(order) =
    change.identity_order(
      list.index_map(revisions, fn(revision, index) {
        #(revision, index - list.length(revisions))
      }),
    )
  let initial = initial_forest()
  let #(commit_a, after_a) =
    authored_commit(initial, revision_a, local, "a", order)
  let #(commit_b, after_b) =
    authored_commit(after_a, revision_b, local, "b", order)
  let #(commit_c, _) = authored_commit(after_b, revision_c, local, "c", order)
  let appended =
    [commit_a, commit_b, commit_c]
    |> list.fold(history.new(local), fn(state, commit) {
      history.append_local(state, commit)
      |> expect.to_be_ok()
      |> fn(result) { result.history }
    })
  let #(acked, Nil) =
    [#(commit_a, 1), #(commit_b, 2), #(commit_c, 3)]
    |> list.fold(#(appended, Nil), fn(acc, entry) {
      let #(update, state) =
        history.receive(
          acc.0,
          entry.0,
          types.SequencePoint(entry.1, 0),
          entry.1 - 1,
          0,
          Nil,
          no_mint,
        )
        |> expect.to_be_ok()
      #(update.history, state)
    })
  let #(retained, handle_b) =
    history.retain_revertible(acked, revision_b, types.DefaultCommit)
    |> expect.to_be_ok()
  let #(retained, handle_c) =
    history.retain_revertible(retained, revision_c, types.DefaultCommit)
    |> expect.to_be_ok()
  let #(pinned, Nil) =
    history.advance_minimum(retained, 3, 3, Nil, no_mint)
    |> expect.to_be_ok()
  pinned.trimmed_revisions |> expect.to_equal([revision_a])
  history.author_revert(pinned.history, handle_b, undo_b, order)
  |> expect.to_be_ok()
  history.author_revert(pinned.history, handle_c, undo_c, order)
  |> expect.to_be_ok()
  let released_b =
    history.dispose_revertible(pinned.history, handle_b)
    |> expect.to_be_ok()
  let #(trimmed_b, Nil) =
    history.advance_minimum(released_b, 3, 3, Nil, no_mint)
    |> expect.to_be_ok()
  trimmed_b.trimmed_revisions |> expect.to_equal([revision_b])
  history.revertible_is_valid(trimmed_b.history, handle_c)
  |> expect.to_be_true()
  history.author_revert(trimmed_b.history, handle_b, undo_b, order)
  |> expect.to_be_error()
  history.author_revert(trimmed_b.history, handle_c, undo_c, order)
  |> expect.to_be_ok()
  let released_c =
    history.dispose_revertible(trimmed_b.history, handle_c)
    |> expect.to_be_ok()
  let #(trimmed_c, Nil) =
    history.advance_minimum(released_c, 3, 3, Nil, no_mint)
    |> expect.to_be_ok()
  trimmed_c.trimmed_revisions |> expect.to_equal([revision_c])
  history.inspect(trimmed_c.history).sequenced.trunk |> expect.to_equal([])
}

pub fn assert_summary_reload_lifetime() {
  let writer =
    summary_core(
      "writer",
      "30000000-0000-4000-8000-000000000003",
      "40000000-0000-4000-8000-000000000004",
    )
  let assert #(pending, target_events, [target_outbound]) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.SetField(["title"], types.StringValue("target")),
    ])
    |> expect.to_be_ok()
  let target_revision = applied_revision(target_events)
  let #(settled, _) =
    runtime_core.handle_sequenced(
      pending,
      message(pending, target_outbound, 1, 0),
    )
    |> expect.to_be_ok()
  let #(retained, target_handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let #(undone, undo_events, undo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", target_handle)
    |> expect.to_be_ok()
  let undo_revision = applied_revision(undo_events)
  let #(undone, _) =
    runtime_core.handle_sequenced(undone, message(undone, undo_outbound, 2, 1))
    |> expect.to_be_ok()
  let #(retained, undo_handle) =
    runtime_core.retain_tree_revertible(
      undone,
      "A/_C",
      undo_revision,
      types.UndoCommit,
    )
    |> expect.to_be_ok()
  let after_undo =
    runtime_core.capture_summary(retained)
    |> expect.to_be_ok()
    |> load_summary(
      "undo-reader",
      "60000000-0000-4000-8000-000000000006",
      "70000000-0000-4000-8000-000000000007",
    )
  runtime_core.tree_read(after_undo, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
  runtime_core.tree_revertible_is_valid(after_undo, "A/_C", target_handle)
  |> expect.to_be_false()
  runtime_core.tree_revertible_is_valid(after_undo, "A/_C", undo_handle)
  |> expect.to_be_false()
  continue_editing(after_undo, 3, "after-undo")

  let #(redone, redo_events, redo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", undo_handle)
    |> expect.to_be_ok()
  let redo_revision = applied_revision(redo_events)
  let #(redone, _) =
    runtime_core.handle_sequenced(redone, message(redone, redo_outbound, 3, 2))
    |> expect.to_be_ok()
  let after_redo =
    runtime_core.capture_summary(redone)
    |> expect.to_be_ok()
    |> load_summary(
      "redo-reader",
      "80000000-0000-4000-8000-000000000008",
      "90000000-0000-4000-8000-000000000009",
    )
  runtime_core.tree_read(after_redo, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("target"))))
  runtime_core.tree_revertible_is_valid(after_redo, "A/_C", target_handle)
  |> expect.to_be_false()
  runtime_core.tree_revertible_is_valid(after_redo, "A/_C", undo_handle)
  |> expect.to_be_false()
  redo_revision |> expect.to_not_equal(target_revision)
  continue_editing(after_redo, 4, "after-redo")
}

pub fn assert_pending_undo_summary_tail() {
  let writer =
    summary_core(
      "writer",
      "30000000-0000-4000-8000-000000000003",
      "40000000-0000-4000-8000-000000000004",
    )
  let assert #(pending, target_events, [target_outbound]) =
    runtime_core.submit_tree_edits(writer, "A/_C", [
      types.SetField(["title"], types.StringValue("target")),
    ])
    |> expect.to_be_ok()
  let target_revision = applied_revision(target_events)
  let #(settled, _) =
    runtime_core.handle_sequenced(
      pending,
      message(pending, target_outbound, 1, 0),
    )
    |> expect.to_be_ok()
  let #(retained, handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let #(pending_undo, undo_events, undo_outbound) =
    runtime_core.revert_tree(retained, "A/_C", handle)
    |> expect.to_be_ok()
  assert_applied(undo_events, types.UndoCommit)
  runtime_core.tree_read(pending_undo, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
  let fresh =
    pending_summary(pending_undo)
    |> load_summary(
      "reader",
      "60000000-0000-4000-8000-000000000006",
      "70000000-0000-4000-8000-000000000007",
    )
  runtime_core.tree_read(fresh, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("target"))))
  let #(after_tail, received) =
    runtime_core.handle_sequenced(
      fresh,
      message(pending_undo, undo_outbound, 2, 1),
    )
    |> expect.to_be_ok()
  applied_revision(received.events)
  |> expect.to_equal(applied_revision(undo_events))
  tree_change_events(received.events)
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  runtime_core.tree_read(after_tail, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("base"))))
  continue_editing(after_tail, 3, "after-tail")
}

fn assert_local_case(
  target: types.Edit,
  later: types.Edit,
  expected: types.TreeValue,
) {
  let core = core("writer", "30000000-0000-4000-8000-000000000003")
  let #(pending, target_events, target_outbound) =
    runtime_core.submit_tree_edits(core, "A/_C", [target])
    |> expect.to_be_ok()
  let target_outbound = only_outbound(target_outbound)
  assert_applied(target_events, types.DefaultCommit)
  let target_revision = applied_revision(target_events)
  let #(settled, target_settlement) =
    runtime_core.handle_sequenced(
      pending,
      message(pending, target_outbound, 1, 0),
    )
    |> expect.to_be_ok()
  assert_settlement(target_settlement.events, target_revision)
  let #(retained, handle) =
    runtime_core.retain_tree_revertible(
      settled,
      "A/_C",
      target_revision,
      types.DefaultCommit,
    )
    |> expect.to_be_ok()
  let #(pending, later_events, later_outbound) =
    runtime_core.submit_tree_edits(retained, "A/_C", [later])
    |> expect.to_be_ok()
  let later_outbound = only_outbound(later_outbound)
  assert_applied(later_events, types.DefaultCommit)
  let later_revision = applied_revision(later_events)
  let #(settled, later_settlement) =
    runtime_core.handle_sequenced(
      pending,
      message(pending, later_outbound, 2, 1),
    )
    |> expect.to_be_ok()
  assert_settlement(later_settlement.events, later_revision)
  let #(undone, undo_events, undo_outbound) =
    runtime_core.revert_tree(settled, "A/_C", handle) |> expect.to_be_ok()
  assert_applied(undo_events, types.UndoCommit)
  assert_root(undone, expected)
  let undo_revision = applied_revision(undo_events)
  let #(settled, undo_settlement) =
    runtime_core.handle_sequenced(undone, message(undone, undo_outbound, 3, 2))
    |> expect.to_be_ok()
  assert_settlement(undo_settlement.events, undo_revision)
  assert_root(settled, expected)
}

fn assert_applied(
  events: List(#(String, channel.ChannelEvent)),
  kind: types.TreeCommitKind,
) {
  events |> list.length |> expect.to_equal(2)
  events
  |> list.filter_map(fn(event) {
    case event.1 {
      channel.TreeCommitApplied(_, found, _, _) -> Ok(found)
      _ -> Error(Nil)
    }
  })
  |> expect.to_equal([kind])
}

fn only_outbound(
  outbounds: List(wire.OutboundOperation),
) -> wire.OutboundOperation {
  outbounds |> list.length |> expect.to_equal(1)
  outbounds |> list.first |> expect.to_be_ok()
}

fn applied_revision(
  events: List(#(String, channel.ChannelEvent)),
) -> fluid_ids.StableId {
  events
  |> list.find_map(fn(event) {
    case event.1 {
      channel.TreeCommitApplied(revision, _, _, _) -> Ok(revision)
      _ -> Error(Nil)
    }
  })
  |> expect.to_be_ok()
}

fn assert_settlement(
  events: List(#(String, channel.ChannelEvent)),
  revision: fluid_ids.StableId,
) {
  events
  |> expect.to_equal([
    #("A/_C", channel.TreeCommitSettled(revision, types.FullyApplied)),
  ])
}

fn assert_root(core: runtime_core.Core, expected: types.TreeValue) {
  runtime_core.tree_read(core, "A/_C", [])
  |> expect.to_equal(Ok(Some(expected)))
}

fn pending_summary(core: runtime_core.Core) -> fluid_document.DocumentSummary {
  let channels = runtime_core.summary_channels(core) |> expect.to_be_ok()
  case core.persistence {
    Some(previous) ->
      fluid_document.capture(
        previous,
        channels,
        core.compressor,
        fluid_document.CaptureRouting(
          dict.to_list(core.routing.aliases),
          dict.to_list(core.routing.datastores),
          dict.to_list(core.routing.channel_attributes),
        ),
      )
      |> expect.to_be_ok()
    None ->
      fluid_document.native(
        core.last_seen_sequence_number,
        core.minimum_sequence_number,
        runtime_core.summary_members(core),
        channels,
      )
      |> expect.to_be_ok()
  }
}

fn load_summary(
  summary: fluid_document.DocumentSummary,
  client_id: String,
  session_id: String,
  view_id: String,
) -> runtime_core.Core {
  let encoded = fluid_document.encode(summary) |> expect.to_be_ok()
  let session = session(session_id)
  let view_id = stable(view_id)
  let decoded =
    fluid_document.decode(encoded, None, session, view_id)
    |> expect.to_be_ok()
  case
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        client_id,
        [],
        fluid_document.sequence_number(decoded),
      ),
      decoded,
    )
  {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "summary reload requested a missing prefix"
    Error(error) ->
      panic as { "summary reload failed: " <> string.inspect(error) }
  }
}

fn continue_editing(
  core: runtime_core.Core,
  sequence_number: Int,
  value: String,
) {
  let assert #(pending, events, [outbound]) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      types.SetField(["note"], types.StringValue(value)),
    ])
    |> expect.to_be_ok()
  assert_applied(events, types.DefaultCommit)
  let revision = applied_revision(events)
  let #(settled, settlement) =
    runtime_core.handle_sequenced(
      pending,
      message(pending, outbound, sequence_number, sequence_number - 1),
    )
    |> expect.to_be_ok()
  assert_settlement(settlement.events, revision)
  runtime_core.tree_read(settled, "A/_C", ["note"])
  |> expect.to_equal(Ok(Some(types.StringValue(value))))
}

fn tree_change_events(
  events: List(#(String, channel.ChannelEvent)),
) -> List(#(String, channel.ChannelEvent)) {
  list.filter(events, fn(event) {
    case event.1 {
      channel.TreeEvent(_) -> True
      _ -> False
    }
  })
}

fn initial_forest() -> forest.Forest {
  forest.new(
    stable("00000000-0000-4000-8000-000000000099"),
    stored(),
    Some(initial_root()),
  )
  |> expect.to_be_ok()
}

fn authored_commit(
  state: forest.Forest,
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  title: String,
  order: change.IdentityOrder,
) -> #(history.Commit, forest.Forest) {
  let authored =
    change.edit(
      stored(),
      state,
      revision,
      types.SetField(["title"], types.StringValue(title)),
      order,
    )
    |> expect.to_be_ok()
  let commit =
    history.Commit(revision, originator, shared_change.from_data(authored))
  let effects =
    shared_change.effects(shared_change.TaggedChange(
      Some(revision),
      None,
      commit.change,
    ))
    |> expect.to_be_ok()
  let state =
    effects
    |> list.fold(state, fn(state, effect) {
      case effect {
        shared_change.DataDelta(delta) ->
          forest.apply_delta(state, delta) |> expect.to_be_ok()
        shared_change.SchemaDelta(_, _, _) -> state
      }
    })
  #(commit, state)
}

fn no_mint(
  _state: Nil,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Nil), types.TreeError) {
  Error(types.InvalidHistory("unexpected rollback allocation"))
}

fn session(value: String) -> fluid_ids.SessionId {
  fluid_ids.session_id(value) |> expect.to_be_ok()
}

fn stable(value: String) -> fluid_ids.StableId {
  fluid_ids.stable_id(value) |> expect.to_be_ok()
}

fn summary_core(
  client_id: String,
  session_id: String,
  view_id: String,
) -> runtime_core.Core {
  let session = session(session_id)
  let view_id = stable(view_id)
  let summary =
    fluid_document.initial_tree(
      stored(),
      Some(initial_root()),
      session,
      view_id,
    )
    |> expect.to_be_ok()
  case
    runtime_core.bootstrap_document(
      runtime_fixture.connected(client_id, [], 0),
      summary,
    )
  {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "initial summary requested a missing prefix"
    Error(error) ->
      panic as { "initial summary failed: " <> string.inspect(error) }
  }
}

fn core(client: String, session_id: String) -> runtime_core.Core {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [tree_view] = input.tree_views
  let assert Some(compressor) = input.compressor
  let assert Ok(serialized) = fluid_ids.serialize(compressor, False)
  let assert Ok(session) = fluid_ids.session_id(session_id)
  let assert Ok(compressor) = fluid_ids.deserialize(serialized, session)
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      tree_view.view_id,
      stored(),
      forest.ForestData(Some(initial_root()), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        sequence_number: 0,
        minimum_sequence_number: 0,
        compressor: Some(compressor),
        tree_views: [runtime_core.TreeViewSeed(..tree_view, view: view())],
        channels: list.map(input.channels, fn(seed) {
          case seed.route == tree_view.route {
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
      runtime_fixture.connected(client, [], 0),
      seed,
    )
  core
}

fn message(
  sender: runtime_core.Core,
  outbound: wire.OutboundOperation,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
  }
  spillway_types.SequencedDocumentMessage(
    client_id: Some(sender.client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: minimum_sequence_number,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: outbound.operation_type,
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn stored() -> schema.StoredSchema {
  schema.stored_from_string(tree_schema) |> expect.to_be_ok()
}

fn view() -> schema.ViewSchema {
  schema.view_from_string(tree_schema) |> expect.to_be_ok()
}

fn initial_root() -> types.TreeValue {
  root(
    "base",
    Some("seed"),
    0.0,
    point("featured", 0.0, "8f95be09-8376-4ff7-8755-ccd7e8124b09"),
    [left_a(), left_b()],
    [right_a()],
    [#("seed", types.StringValue("value"))],
  )
}

fn root(
  title: String,
  note: Option(String),
  count: Float,
  featured: types.TreeValue,
  left: List(types.TreeValue),
  right: List(types.TreeValue),
  by_key: List(#(String, types.TreeValue)),
) -> types.TreeValue {
  let note = case note {
    Some(note) -> [#("note", types.StringValue(note))]
    None -> []
  }
  types.ObjectValue(
    "Root",
    list.append(
      [#("title", types.StringValue(title))],
      list.append(note, [
        #("count", types.NumberValue(count)),
        #("featured", featured),
        #("left", types.ArrayValue(items_type, left)),
        #("right", types.ArrayValue(items_type, right)),
        #("byKey", types.MapValue(map_type, by_key)),
      ]),
    ),
  )
}

fn left_a() -> types.TreeValue {
  point("left-a", 1.0, "8f95be09-8376-4ff7-8755-ccd7e8124b08")
}

fn left_b() -> types.TreeValue {
  point("left-b", 2.0, "8f95be09-8376-4ff7-8755-ccd7e8124b07")
}

fn right_a() -> types.TreeValue {
  point("right-a", 3.0, "8f95be09-8376-4ff7-8755-ccd7e8124b06")
}

fn point(label: String, x: Float, identifier: String) -> types.TreeValue {
  types.ObjectValue(point_type, [
    #("id", types.StringValue(identifier)),
    #("label", types.StringValue(label)),
    #("x", types.NumberValue(x)),
  ])
}
