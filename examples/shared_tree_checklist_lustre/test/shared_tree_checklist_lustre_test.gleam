import gleam/option.{None, Some}
import gleeunit
import shared_tree_checklist_lustre
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/history
import shared_tree_checklist_lustre/lifecycle
import shared_tree_checklist_lustre/schema as document_schema
import watershed/tree/schema
import watershed/tree/types

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn initial_tree_matches_the_stored_schema_test() {
  let assert Ok(Nil) =
    schema.validate_root(document_schema.stored(), document_schema.initial())
}

pub fn local_commit_kinds_route_handles_and_default_clears_redo_test() {
  let initial = history.new()
  let assert history.Routed(after_default, []) =
    history.route(initial, types.DefaultCommit, True, Some("A"))
  let assert history.History(["A"], []) = after_default

  let assert history.Routed(after_undo, []) =
    history.route(after_default, types.UndoCommit, True, Some("B"))
  let assert history.History(["A"], ["B"]) = after_undo

  let assert history.Routed(after_redo, []) =
    history.route(after_undo, types.RedoCommit, True, Some("C"))
  let assert history.History(["C", "A"], ["B"]) = after_redo

  let history.Routed(after_new_default, dispose) =
    history.route(after_redo, types.DefaultCommit, True, Some("D"))
  let assert history.History(["D", "C", "A"], []) = after_new_default
  let assert ["B"] = dispose

  let assert history.Routed(after_remote, []) =
    history.route(after_new_default, types.DefaultCommit, False, Some("remote"))
  let assert history.History(["D", "C", "A"], []) = after_remote
}

pub fn history_consumption_clear_and_disposed_pruning_keep_stack_order_test() {
  let value = history.History(["undo-new", "undo-old"], ["redo"])
  let assert Some("undo-new") = history.next_undo(value)
  let assert Some("redo") = history.next_redo(value)
  let assert history.History(["undo-old"], ["redo"]) =
    history.consume_undo(value)
  let assert history.History(["undo-new", "undo-old"], []) =
    history.consume_redo(value)
  let assert history.History(["undo-new"], ["redo"]) =
    history.prune(value, fn(entry) { entry != "undo-old" })
  let assert history.Routed(history.History([], []), dispose) =
    history.clear(value)
  let assert ["undo-new", "undo-old", "redo"] = dispose
}

pub fn failed_history_and_empty_requests_preserve_application_state_test() {
  let initial =
    lifecycle.State(
      history: history.History(["undo"], ["redo"]),
      action: None,
      pending: 0,
    )
  let assert #(after_empty_undo, None) =
    lifecycle.request(
      lifecycle.State(..initial, history: history.History([], ["redo"])),
      lifecycle.Undoing,
    )
  let assert lifecycle.State(history.History([], ["redo"]), None, 0) =
    after_empty_undo
  let assert #(after_empty_redo, None) =
    lifecycle.request(
      lifecycle.State(..initial, history: history.History(["undo"], [])),
      lifecycle.Redoing,
    )
  let assert lifecycle.State(history.History(["undo"], []), None, 0) =
    after_empty_redo

  let assert #(requested, Some("undo")) =
    lifecycle.request(initial, lifecycle.Undoing)
  let assert lifecycle.Transition(failed, [], Some(error)) =
    lifecycle.history_finished(requested, Error("revert refused"))
  let assert "History action failed: revert refused" = error
  let assert lifecycle.State(history.History(["undo"], ["redo"]), None, 0) =
    failed
}

pub fn capture_settlement_and_disposal_failures_are_visible_and_drain_test() {
  let initial =
    lifecycle.State(history: history.new(), action: None, pending: 0)
  let assert lifecycle.Transition(
    after_capture,
    [],
    Some("Commit capture failed: acquisition refused"),
  ) = lifecycle.captured(initial, True, Error("acquisition refused"))
  let assert lifecycle.State(history.History([], []), None, 0) = after_capture

  let assert Some("Commit settlement failed: registration refused") =
    lifecycle.settled(Error("registration refused"))
  let assert Some("Commit settlement dropped the full change") =
    lifecycle.settled(Ok(types.FullyDropped))
  let assert Some("Commit settlement applied only new content") =
    lifecycle.settled(Ok(types.NewContentOnly))

  let closing =
    lifecycle.State(history: history.new(), action: None, pending: 2)
  let assert lifecycle.Disposal(
    after_first,
    Some("History disposal failed: dispose refused"),
    False,
  ) = lifecycle.disposal_finished(closing, Error("dispose refused"))
  let assert lifecycle.Disposal(after_second, None, True) =
    lifecycle.disposal_finished(after_first, Ok(Nil))
  let assert 0 = after_second.pending
}

pub fn decode_and_prepare_every_required_operation_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", True),
      #("c", "third", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(types.ArrayInsert(["items"], 3, [inserted])) =
    checklist.add(value, "d", "fourth")
  let assert True = inserted == document_schema.item_value("d", "fourth", False)
  let assert Ok(types.SetField(
    ["items", "1", "text"],
    types.StringValue("renamed"),
  )) = checklist.edit(value, "b", "renamed")
  let assert Ok(types.SetField(
    ["items", "1", "completed"],
    types.BooleanValue(False),
  )) = checklist.toggle(value, "b")
  let assert Ok(types.ArrayRemove(["items"], 1, 2)) =
    checklist.delete(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 0))) =
    checklist.move_up(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 3))) =
    checklist.move_down(value, "b")
}

pub fn boundary_moves_and_stale_ids_do_not_submit_edits_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(None) = checklist.move_up(value, "a")
  let assert Ok(None) = checklist.move_down(value, "b")
  let assert Error("checklist item missing is no longer present") =
    checklist.delete(value, "missing")
}

pub fn decoder_rejects_duplicate_ids_and_malformed_items_test() {
  let duplicate =
    document_schema.checklist_value([
      #("same", "first", False),
      #("same", "second", True),
    ])
  let assert Error("duplicate checklist item id same") =
    checklist.decode(duplicate)
  let malformed =
    types.ObjectValue("shared_tree_checklist.Checklist", [
      #("title", types.StringValue("SharedTree checklist")),
      #(
        "items",
        types.ArrayValue("shared_tree_checklist.Items", [
          types.ObjectValue("shared_tree_checklist.Item", [
            #("id", types.StringValue("a")),
            #("text", types.StringValue("missing completion")),
          ]),
        ]),
      ),
    ])
  let assert Error(_) = checklist.decode(malformed)
}

pub fn browser_configuration_and_creation_uncertainty_are_explicit_test() {
  let assert "http://example.test:4100" =
    shared_tree_checklist_lustre.base_url("example.test", "4100")
  let assert "ws://example.test:4100/socket/websocket?vsn=2.0.0" =
    shared_tree_checklist_lustre.socket_url("example.test", "4100")
  let assert "Creation failed. The service might have created a document whose ID this browser did not receive: lost response" =
    shared_tree_checklist_lustre.creation_error("lost response")
}

pub fn browser_actions_prepare_id_addressed_edits_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", True),
      #("c", "third", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(Some(types.ArrayInsert(["items"], 3, [_]))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.Add("d", "fourth"),
    )
  let assert Ok(Some(types.SetField(
    ["items", "1", "text"],
    types.StringValue("renamed"),
  ))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.Edit("b", "renamed"),
    )
  let assert Ok(Some(types.SetField(
    ["items", "1", "completed"],
    types.BooleanValue(False),
  ))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.Toggle("b"),
    )
  let assert Ok(Some(types.ArrayRemove(["items"], 1, 2))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.Delete("b"),
    )
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 0))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.MoveUp("b"),
    )
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 3))) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.MoveDown("b"),
    )
  let assert Ok(None) =
    shared_tree_checklist_lustre.prepare(
      value,
      shared_tree_checklist_lustre.MoveUp("a"),
    )
}
