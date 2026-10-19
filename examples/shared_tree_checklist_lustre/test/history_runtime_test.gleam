import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleeunit
import lustre/effect.{type Effect}
import shared_tree_checklist_lustre
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/lifecycle
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed/tree/history_stack as history
import watershed/tree/schema_builder as builder
import watershed/wire/fluid_document
import watershed_lustre/tree

@external(javascript, "./history_runtime_test_ffi.mjs", "stringify")
fn stringify(value: value) -> String

@external(javascript, "./history_runtime_test_ffi.mjs", "invalidOperation")
fn invalid_operation(sequence_number: Int) -> String

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: shared_tree.Tree(checklist.Checklist),
    callbacks: runtime.TransportCallbacks,
    submissions: transport_js.Cell(Int),
    closes: transport_js.Cell(Int),
  )
}

type RuntimeMsg {
  ChangeSubscribed(Result(shared_tree.Subscription, tree_error.Error))
  Changed
  CommitSubscribed(Result(shared_tree.Subscription, tree_error.Error))
  Captured(Result(tree.CommitEvent, tree_error.Error))
  Settled(Result(shared_tree.CommitOutcome, tree_error.Error))
  Disposed(Result(Nil, tree_error.Error))
}

type CapturedAction {
  RenameAction
  ToggleAction
  DeleteAction
  MoveAction
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn complete_all_groups_latest_incomplete_items_into_one_undo_step_test() {
  let fixture =
    fixture([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let handles = transport_js.new_cell([])
  let commits = transport_js.new_cell(0)
  let assert Ok(subscription) =
    shared_tree.subscribe_commits(fixture.tree, fn(event) {
      let assert shared_tree.CommitEvent(_, True, Some(acquire), _) = event
      let assert Ok(handle) = acquire(fn(_) { Nil })
      transport_js.set_cell(handles, [handle, ..transport_js.get_cell(handles)])
      transport_js.set_cell(commits, transport_js.get_cell(commits) + 1)
    })

  let assert Ok(True) =
    shared_tree.transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", True),
      checklist.Item("b", "second", True),
    ],
    ..,
  )) = shared_tree.read_root(fixture.tree)

  let assert Ok(False) =
    shared_tree.transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)

  let assert [handle] = transport_js.get_cell(handles)
  let assert Ok(Nil) = shared_tree.revert(handle, shared_tree.DisposeRevertible)
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", False),
      checklist.Item("b", "second", False),
    ],
    ..,
  )) = shared_tree.read_root(fixture.tree)

  shared_tree.unsubscribe(subscription)
  watershed.close(fixture.document)
}

pub fn captured_actions_survive_peer_reorder_through_application_update_test() -> Promise(
  Nil,
) {
  test_reordered_actions([
    RenameAction,
    ToggleAction,
    DeleteAction,
    MoveAction,
  ])
}

fn test_reordered_actions(actions: List(CapturedAction)) -> Promise(Nil) {
  case actions {
    [] -> promise.resolve(Nil)
    [action, ..rest] -> {
      let fixture =
        fixture([
          #("a", "first", False),
          #("b", "second", False),
          #("c", "third", False),
        ])
      let assert Ok(root) = shared_tree.required_root(fixture.tree)
      let assert Ok(items) = shared_tree.child(root, document_schema.items())
      let assert Ok([first, target, third]) = checklist.nodes(items)
      let model = application_model(fixture.tree)
      let #(pending, lazy_action) =
        shared_tree_checklist_lustre.update(
          model,
          captured_message(action, target, Some(third)),
        )

      let assert Ok(Nil) =
        shared_tree.array_move_before(items, target, items, Some(first))
      let assert Ok([reordered_target, reordered_first, reordered_third]) =
        checklist.nodes(items)
      let assert Ok(checklist.Item("b", "second", False)) =
        shared_tree.read(reordered_target)
      let assert Ok(checklist.Item("a", "first", False)) =
        shared_tree.read(reordered_first)
      let assert Ok(checklist.Item("c", "third", False)) =
        shared_tree.read(reordered_third)

      use updated <- promise.await(finish_action(pending, lazy_action))
      assert_reordered_result(action, updated, target)
      watershed.close(fixture.document)
      test_reordered_actions(rest)
    }
  }
}

pub fn removed_same_id_replacement_refuses_all_captured_actions_through_application_update_test() -> Promise(
  Nil,
) {
  test_replaced_actions([
    RenameAction,
    ToggleAction,
    DeleteAction,
    MoveAction,
  ])
}

fn test_replaced_actions(actions: List(CapturedAction)) -> Promise(Nil) {
  case actions {
    [] -> promise.resolve(Nil)
    [action, ..rest] -> {
      let fixture =
        fixture([
          #("a", "first", False),
          #("b", "second", False),
          #("c", "third", False),
        ])
      let assert Ok(root) = shared_tree.required_root(fixture.tree)
      let assert Ok(items) = shared_tree.child(root, document_schema.items())
      let assert Ok([first, removed, _]) = checklist.nodes(items)
      let model = application_model(fixture.tree)
      let #(pending, lazy_action) =
        shared_tree_checklist_lustre.update(
          model,
          captured_message(action, removed, Some(first)),
        )

      let assert Ok(Nil) = shared_tree.array_remove_node(items, removed)
      let assert Ok(Nil) =
        shared_tree.array_insert(items, 1, [
          checklist.Item("b", "replacement", False),
        ])
      let assert Ok([_, replacement, _]) = checklist.nodes(items)
      let assert Error(tree_error.InvalidReference(_)) =
        shared_tree.read(removed)

      use updated <- promise.await(finish_action(pending, lazy_action))
      let assert shared_tree_checklist_lustre.Model(
        checklist: displayed,
        item_nodes: [displayed_first, displayed_replacement, displayed_third],
        errors: [_],
        pending: 0,
        ..,
      ) = updated
      let assert checklist.Checklist(
        items: [
          checklist.Item("a", "first", False),
          checklist.Item("b", "replacement", False),
          checklist.Item("c", "third", False),
        ],
        ..,
      ) = displayed
      let assert Ok(checklist.Item("a", "first", False)) =
        shared_tree.read(displayed_first)
      let assert Ok(checklist.Item("b", "replacement", False)) =
        shared_tree.read(displayed_replacement)
      let assert Ok(checklist.Item("c", "third", False)) =
        shared_tree.read(displayed_third)
      let assert Ok(checklist.Item("b", "replacement", False)) =
        shared_tree.read(replacement)

      watershed.close(fixture.document)
      test_replaced_actions(rest)
    }
  }
}

fn captured_message(
  action: CapturedAction,
  target: shared_tree.Ref(checklist.Item),
  before: Option(shared_tree.Ref(checklist.Item)),
) -> shared_tree_checklist_lustre.Msg {
  case action {
    RenameAction ->
      shared_tree_checklist_lustre.EditCommitted(target, "renamed")
    ToggleAction -> shared_tree_checklist_lustre.ToggleClicked(target, False)
    DeleteAction -> shared_tree_checklist_lustre.DeleteClicked(target)
    MoveAction -> shared_tree_checklist_lustre.MoveClicked(target, before)
  }
}

fn assert_reordered_result(
  action: CapturedAction,
  model: shared_tree_checklist_lustre.Model,
  target: shared_tree.Ref(checklist.Item),
) -> Nil {
  let assert shared_tree_checklist_lustre.Model(
    checklist: checklist.Checklist(items: displayed, ..),
    item_nodes: nodes,
    errors: [],
    pending: 0,
    ..,
  ) = model
  case action {
    RenameAction -> {
      let assert [
        checklist.Item("b", "renamed", False),
        checklist.Item("a", "first", False),
        checklist.Item("c", "third", False),
      ] = displayed
      let assert [live_target, _, _] = nodes
      let assert Ok(checklist.Item("b", "renamed", False)) =
        shared_tree.read(target)
      let assert Ok(checklist.Item("b", "renamed", False)) =
        shared_tree.read(live_target)
      Nil
    }
    ToggleAction -> {
      let assert [
        checklist.Item("b", "second", True),
        checklist.Item("a", "first", False),
        checklist.Item("c", "third", False),
      ] = displayed
      let assert [live_target, _, _] = nodes
      let assert Ok(checklist.Item("b", "second", True)) =
        shared_tree.read(target)
      let assert Ok(checklist.Item("b", "second", True)) =
        shared_tree.read(live_target)
      Nil
    }
    DeleteAction -> {
      let assert [
        checklist.Item("a", "first", False),
        checklist.Item("c", "third", False),
      ] = displayed
      let assert [_, _] = nodes
      let assert Error(tree_error.InvalidReference(_)) =
        shared_tree.read(target)
      Nil
    }
    MoveAction -> {
      let assert [
        checklist.Item("a", "first", False),
        checklist.Item("b", "second", False),
        checklist.Item("c", "third", False),
      ] = displayed
      let assert [_, live_target, _] = nodes
      let assert Ok(checklist.Item("b", "second", False)) =
        shared_tree.read(target)
      let assert Ok(checklist.Item("b", "second", False)) =
        shared_tree.read(live_target)
      Nil
    }
  }
}

fn application_model(
  tree: shared_tree.Tree(checklist.Checklist),
) -> shared_tree_checklist_lustre.Model {
  let assert Ok(checklist) = shared_tree.read_root(tree)
  let assert Ok(root) = shared_tree.required_root(tree)
  let assert Ok(items) = shared_tree.child(root, document_schema.items())
  let assert Ok(item_nodes) = checklist.nodes(items)
  shared_tree_checklist_lustre.Model(
    config: shared_tree_checklist_lustre.Config("", "", "", ""),
    phase: shared_tree_checklist_lustre.Ready,
    document_id: "checklist",
    document: None,
    tree: Some(tree),
    change_subscription: None,
    commit_subscription: None,
    checklist: checklist,
    item_nodes: item_nodes,
    history: history.new(),
    history_action: None,
    draft: "",
    pending: 0,
    errors: [],
  )
}

fn finish_action(
  model: shared_tree_checklist_lustre.Model,
  lazy_action: Effect(shared_tree_checklist_lustre.Msg),
) -> Promise(shared_tree_checklist_lustre.Model) {
  let action_messages = transport_js.new_cell([])
  run(lazy_action, action_messages)
  use _ <- promise.await(promise.wait(0))
  let assert [finished] = messages(action_messages)
  let #(model, read_effect) =
    shared_tree_checklist_lustre.update(model, finished)
  let read_messages = transport_js.new_cell([])
  run(read_effect, read_messages)
  use _ <- promise.await(promise.wait(0))
  let assert [read] = messages(read_messages)
  promise.resolve(shared_tree_checklist_lustre.update(model, read).0)
}

pub fn captured_target_survives_peer_reorder_by_physical_identity_test() {
  let fixture =
    fixture([
      #("a", "first", False),
      #("b", "second", False),
      #("c", "third", False),
    ])
  let assert Ok(root) = shared_tree.required_root(fixture.tree)
  let assert Ok(items) = shared_tree.child(root, document_schema.items())
  let assert Ok([first, target, third]) = checklist.nodes(items)

  let assert Ok(Nil) =
    shared_tree.array_move_before(items, target, items, Some(first))
  let assert Ok([reordered_target, reordered_first, reordered_third]) =
    checklist.nodes(items)
  let assert Ok(checklist.Item("b", "second", False)) =
    shared_tree.read(reordered_target)
  let assert Ok(checklist.Item("a", "first", False)) =
    shared_tree.read(reordered_first)
  let assert Ok(checklist.Item("c", "third", False)) =
    shared_tree.read(reordered_third)
  let assert Ok(checklist.Item("c", "third", False)) = shared_tree.read(third)

  let assert Ok(Nil) =
    shared_tree_checklist_lustre.rename_item(target, "renamed")
  let assert Ok(Nil) = shared_tree_checklist_lustre.toggle_item(target, False)
  let assert Ok(Nil) =
    shared_tree_checklist_lustre.move_item(items, target, Some(reordered_third))
  let assert Ok(checklist.Item("b", "renamed", True)) = shared_tree.read(target)
  let assert Ok([
    checklist.Item("a", "first", False),
    checklist.Item("b", "renamed", True),
    checklist.Item("c", "third", False),
  ]) = shared_tree.read(items)

  watershed.close(fixture.document)
}

pub fn removed_or_replaced_captured_target_refuses_without_retargeting_test() {
  let fixture =
    fixture([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let assert Ok(root) = shared_tree.required_root(fixture.tree)
  let assert Ok(items) = shared_tree.child(root, document_schema.items())
  let assert Ok([removed, _]) = checklist.nodes(items)
  let assert Ok(Nil) = shared_tree.array_remove_node(items, removed)
  let assert Ok(Nil) =
    shared_tree.array_insert(items, 0, [
      checklist.Item("a", "replacement", False),
    ])
  let assert Ok([replacement, _]) = checklist.nodes(items)
  let assert Error(tree_error.InvalidReference(_)) = shared_tree.read(removed)

  let assert Error(tree_error.InvalidReference(_)) =
    shared_tree_checklist_lustre.rename_item(removed, "wrong target")
  let assert Error(tree_error.InvalidReference(_)) =
    shared_tree_checklist_lustre.toggle_item(removed, False)
  let assert Error(tree_error.InvalidReference(_)) =
    shared_tree_checklist_lustre.delete_item(items, removed)
  let assert Error(tree_error.InvalidReference(_)) =
    shared_tree_checklist_lustre.move_item(items, removed, None)
  let assert Ok(checklist.Item("a", "replacement", False)) =
    shared_tree.read(replacement)
  let assert Ok([
    checklist.Item("a", "replacement", False),
    checklist.Item("b", "second", False),
  ]) = shared_tree.read(items)

  watershed.close(fixture.document)
}

pub fn application_lifecycle_surfaces_native_subscription_errors_test() -> Promise(
  Nil,
) {
  let fixture = fixture([#("a", "first", False)])
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, CommitSubscribed, Captured, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  clear_messages(sink)
  let assert Ok(thief) =
    shared_tree.subscribe_commits(fixture.tree, fn(event) {
      let assert shared_tree.CommitEvent(_, True, Some(acquire), Some(register)) =
        event
      let assert Ok(_) = acquire(fn(_) { Nil })
      let assert Ok(Nil) = register(fn(_) { Nil })
      fixture.callbacks.on_event("op", invalid_operation(1))
    })

  let assert Ok(Nil) = set_title(fixture.tree, "changed")
  use _ <- promise.await(promise.wait(0))
  let assert [Captured(Error(acquisition)), Settled(Error(registration))] =
    messages(sink)
  let state: lifecycle.State(shared_tree.Revertible) =
    lifecycle.State(history.new(), None, 0)
  let assert lifecycle.Transition(_, [], Some(capture_error)) =
    lifecycle.captured(state, True, Error(tree_error.to_string(acquisition)))
  let assert True = capture_error != ""
  let assert Some(settlement_error) =
    lifecycle.settled(Error(tree_error.to_string(registration)))
  let assert True = settlement_error != ""

  shared_tree.unsubscribe(thief)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn close_unsubscribes_disposes_idempotently_and_orders_close_test() -> Promise(
  Nil,
) {
  let fixture = fixture([#("a", "first", False)])
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_changes(fixture.tree, ChangeSubscribed, fn(_) { Changed }),
    sink,
  )
  run(
    tree.subscribe_commits(fixture.tree, CommitSubscribed, Captured, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [
    ChangeSubscribed(Ok(change_subscription)),
    CommitSubscribed(Ok(commit_subscription)),
  ] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) = set_title(fixture.tree, "changed")
  use _ <- promise.await(promise.wait(0))
  let assert [
    Captured(Ok(tree.CommitEvent(shared_tree.DefaultCommit, True, Some(handle)))),
    Changed,
  ] = messages(sink)
  clear_messages(sink)

  let assert #(requested, Some(requested_handle)) =
    lifecycle.request(
      lifecycle.State(history.History([handle], []), None, 0),
      lifecycle.Undoing,
    )
  let assert lifecycle.Transition(
    lifecycle.State(history.History([retained], []), None, 0),
    [],
    Some("History action failed: revert refused"),
  ) = lifecycle.history_finished(requested, Error("revert refused"))
  let assert True = retained == requested_handle
  let assert Ok(shared_tree.RevertibleValid) =
    shared_tree.revertible_status(retained)

  let initial =
    lifecycle.State(
      history: history.History([handle, handle], []),
      action: None,
      pending: 0,
    )
  let lifecycle.Close(closing, unsubscribe, dispose) =
    lifecycle.close(
      initial,
      Some(change_subscription),
      Some(commit_subscription),
    )
  let assert 2 = closing.pending
  let assert 2 = list.length(unsubscribe)
  let assert 2 = list.length(dispose)
  let effects =
    list.append(
      list.map(unsubscribe, tree.unsubscribe),
      list.map(dispose, fn(entry) { tree.dispose_revertible(entry, Disposed) }),
    )
  run(effect.batch(effects), sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Disposed(first), Disposed(second)] = messages(sink)
  let assert 0 = transport_js.get_cell(fixture.closes)
  let assert lifecycle.Disposal(after_first, first_error, False) =
    lifecycle.disposal_finished(
      closing,
      result.map_error(first, tree_error.to_string),
    )
  let assert lifecycle.Disposal(after_second, second_error, True) =
    lifecycle.disposal_finished(
      after_first,
      result.map_error(second, tree_error.to_string),
    )
  let assert None = first_error
  let assert None = second_error
  let assert 0 = after_second.pending
  clear_messages(sink)
  let assert Ok(Nil) = set_title(fixture.tree, "ignored")
  use _ <- promise.await(promise.wait(0))
  let assert [] = messages(sink)
  watershed.close(fixture.document)
  let assert 1 = transport_js.get_cell(fixture.closes)
  promise.resolve(Nil)
}

pub fn queued_tokens_and_handles_after_close_are_released_test() -> Promise(Nil) {
  let token_fixture = fixture([#("a", "first", False)])
  let token_sink = transport_js.new_cell([])
  run(
    tree.subscribe_changes(token_fixture.tree, ChangeSubscribed, fn(_) {
      Changed
    }),
    token_sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [ChangeSubscribed(Ok(token))] = messages(token_sink)
  let assert lifecycle.Unsubscribe(token) = lifecycle.subscription(False, token)
  run(tree.unsubscribe(token), token_sink)
  let assert Ok(Nil) = set_title(token_fixture.tree, "ignored")
  use _ <- promise.await(promise.wait(0))
  let assert [ChangeSubscribed(_)] = messages(token_sink)
  watershed.close(token_fixture.document)

  let handle_fixture = fixture([#("a", "first", False)])
  let handle_sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(
      handle_fixture.tree,
      CommitSubscribed,
      Captured,
      Settled,
    ),
    handle_sink,
  )
  use _ <- promise.await(promise.wait(0))
  clear_messages(handle_sink)
  let assert Ok(Nil) = set_title(handle_fixture.tree, "changed")
  use _ <- promise.await(promise.wait(0))
  let assert [Captured(Ok(tree.CommitEvent(kind, local, Some(handle))))] =
    messages(handle_sink)
  let state: lifecycle.State(shared_tree.Revertible) =
    lifecycle.State(history.new(), None, 0)
  let assert lifecycle.Transition(_, [late_handle], None) =
    lifecycle.captured(state, False, Ok(#(kind, local, Some(handle))))
  run(tree.dispose_revertible(late_handle, Disposed), handle_sink)
  use _ <- promise.await(promise.wait(0))
  let assert Ok(shared_tree.RevertibleDisposed) =
    shared_tree.revertible_status(handle)
  watershed.close(handle_fixture.document)
  promise.resolve(Nil)
}

fn fixture(items: List(#(String, String, Bool))) -> Fixture(root) {
  let declaration = document_schema.configuration()
  let assert Ok(compiled) = builder.compile(declaration)
  let stored = builder.stored(compiled)
  let input =
    checklist.Checklist(
      "SharedTree checklist",
      list.map(items, fn(item) { checklist.Item(item.0, item.1, item.2) }),
    )
  let assert Ok(initial) = builder.encode_new(compiled, input)
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(stored, initial, session, view_id)
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks: transport_js.Cell(Option(runtime.TransportCallbacks)) =
    transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let closes = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "checklist",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
              _ -> Nil
            }
          },
          close: fn() {
            transport_js.set_cell(closes, transport_js.get_cell(closes) + 1)
          },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "checklist",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> stringify,
  )
  let assert Ok(tree) = watershed.open_tree(document, declaration)
  Fixture(document:, tree:, callbacks:, submissions:, closes:)
}

fn set_title(
  tree: shared_tree.Tree(checklist.Checklist),
  title: String,
) -> Result(Nil, tree_error.Error) {
  use root <- result.try(shared_tree.required_root(tree))
  shared_tree.set(root, document_schema.title(), title)
}

fn run(
  effect_to_run: Effect(message),
  sink: transport_js.Cell(List(message)),
) -> Nil {
  effect.perform(
    effect_to_run,
    fn(message) {
      transport_js.set_cell(sink, [message, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

fn messages(sink: transport_js.Cell(List(message))) -> List(message) {
  transport_js.get_cell(sink) |> list.reverse
}

fn clear_messages(sink: transport_js.Cell(List(message))) -> Nil {
  transport_js.set_cell(sink, [])
}
