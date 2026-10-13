import gleam/option.{None, Some}
import gleeunit
import shared_tree_checklist_lustre
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/history
import shared_tree_checklist_lustre/lifecycle
import shared_tree_checklist_lustre/schema as document_schema
import shared_tree_checklist_lustre/typed_schema
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn typed_initial_tree_matches_the_unchanged_stored_schema_test() {
  let assert Ok(initial) =
    typed.build(typed_schema.builder(), typed_schema.initial())
  let assert True = initial == document_schema.initial()
  let assert Ok(Nil) = schema.validate_root(document_schema.stored(), initial)
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

pub fn typed_builders_trim_text_and_reject_empty_text_test() {
  let assert Ok(value) =
    typed.build(
      typed_schema.item_builder(),
      typed_schema.ItemInput("a", "  first  ", False),
    )
  let assert Ok(checklist.Item("a", "first", False)) =
    typed.decode_node(typed_schema.item_decoder(), value)
  let assert Error(typed.DecodeFailed("checklist item text is empty")) =
    typed.build(
      typed_schema.item_builder(),
      typed_schema.ItemInput("a", "  ", False),
    )
}

pub fn typed_decoder_rejects_duplicate_ids_and_malformed_items_test() {
  let duplicate =
    document_schema.checklist_value([
      #("same", "first", False),
      #("same", "second", True),
    ])
  let assert Error(typed.DecodeFailed("duplicate checklist item id same")) =
    typed.decode_node(typed_schema.decoder(), duplicate)
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
  let assert Error(_) = typed.decode_node(typed_schema.decoder(), malformed)
}

pub fn browser_configuration_and_creation_uncertainty_are_explicit_test() {
  let assert "http://example.test:4100" =
    shared_tree_checklist_lustre.base_url("example.test", "4100")
  let assert "ws://example.test:4100/socket/websocket?vsn=2.0.0" =
    shared_tree_checklist_lustre.socket_url("example.test", "4100")
  let assert "Creation failed. The service might have created a document whose ID this browser did not receive: lost response" =
    shared_tree_checklist_lustre.creation_error("lost response")
}
