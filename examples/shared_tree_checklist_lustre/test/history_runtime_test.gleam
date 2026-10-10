import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import lustre/effect.{type Effect}
import shared_tree_checklist_lustre
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/history
import shared_tree_checklist_lustre/lifecycle
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree/schema
import watershed/tree/types
import watershed/wire/fluid_document
import watershed_lustre/tree

@external(javascript, "./history_runtime_test_ffi.mjs", "stringify")
fn stringify(value: value) -> String

@external(javascript, "./history_runtime_test_ffi.mjs", "invalidOperation")
fn invalid_operation(sequence_number: Int) -> String

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: watershed.SharedTree,
    callbacks: runtime.TransportCallbacks,
    submissions: transport_js.Cell(Int),
    closes: transport_js.Cell(Int),
  )
}

type Msg {
  ChangeSubscribed(watershed.SubscriptionToken)
  Changed
  CommitSubscribed(watershed.SubscriptionToken)
  Captured(Result(tree.CommitEvent, String))
  Settled(Result(types.TreeCommitOutcome, String))
  Disposed(Result(Nil, String))
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
  let subscription =
    watershed.subscribe_tree_commits(fixture.tree, fn(event) {
      let assert watershed.TreeCommitEvent(_, True, Some(acquire), _) = event
      let assert Ok(handle) = acquire()
      transport_js.set_cell(handles, [handle, ..transport_js.get_cell(handles)])
      transport_js.set_cell(commits, transport_js.get_cell(commits) + 1)
    })

  let assert Ok(True) =
    watershed.tree_transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)
  let assert Ok(Some(snapshot)) = watershed.tree_get(fixture.tree, [])
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", True),
      checklist.Item("b", "second", True),
    ],
    ..,
  )) = checklist.decode(snapshot)

  let assert Ok(False) =
    watershed.tree_transaction(fixture.tree, [], fn(tree) {
      shared_tree_checklist_lustre.complete_all(tree)
    })
  let assert 1 = transport_js.get_cell(commits)
  let assert 1 = transport_js.get_cell(fixture.submissions)

  let assert [handle] = transport_js.get_cell(handles)
  let assert Ok(Nil) = watershed.tree_revert(handle, True)
  let assert Ok(Some(restored)) = watershed.tree_get(fixture.tree, [])
  let assert Ok(checklist.Checklist(
    items: [
      checklist.Item("a", "first", False),
      checklist.Item("b", "second", False),
    ],
    ..,
  )) = checklist.decode(restored)

  watershed.unsubscribe(subscription)
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
  let thief =
    watershed.subscribe_tree_commits(fixture.tree, fn(event) {
      let assert watershed.TreeCommitEvent(
        _,
        True,
        Some(acquire),
        Some(register),
      ) = event
      let assert Ok(_) = acquire()
      let assert Ok(Nil) = register(fn(_) { Nil })
      fixture.callbacks.on_event("op", invalid_operation(1))
    })

  let assert Ok(Nil) =
    watershed.tree_set(fixture.tree, ["title"], types.StringValue("changed"))
  use _ <- promise.await(promise.wait(0))
  let assert [Captured(Error(acquisition)), Settled(Error(registration))] =
    messages(sink)
  let state: lifecycle.State(watershed.TreeRevertible) =
    lifecycle.State(history.new(), None, 0)
  let assert lifecycle.Transition(_, [], Some(capture_error)) =
    lifecycle.captured(state, True, Error(acquisition))
  let assert True = capture_error != ""
  let assert Some(settlement_error) = lifecycle.settled(Error(registration))
  let assert True = settlement_error != ""

  watershed.unsubscribe(thief)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn close_unsubscribes_disposes_reports_failure_and_orders_close_test() -> Promise(
  Nil,
) {
  let fixture = fixture([#("a", "first", False)])
  let sink = transport_js.new_cell([])
  run(tree.subscribe(fixture.tree, ChangeSubscribed, fn(_) { Changed }), sink)
  run(
    tree.subscribe_commits(fixture.tree, CommitSubscribed, Captured, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [
    ChangeSubscribed(change_subscription),
    CommitSubscribed(commit_subscription),
  ] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) =
    watershed.tree_set(fixture.tree, ["title"], types.StringValue("changed"))
  use _ <- promise.await(promise.wait(0))
  let assert [
    Captured(Ok(tree.CommitEvent(types.DefaultCommit, True, Some(handle)))),
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
  let assert watershed.RevertibleValid =
    watershed.tree_revertible_status(retained)

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
    lifecycle.disposal_finished(closing, first)
  let assert lifecycle.Disposal(after_second, second_error, True) =
    lifecycle.disposal_finished(after_first, second)
  case first_error, second_error {
    Some(_), None | None, Some(_) -> Nil
    _, _ -> panic as "one duplicate disposal must fail"
  }
  let assert 0 = after_second.pending
  clear_messages(sink)
  let assert Ok(Nil) =
    watershed.tree_set(fixture.tree, ["title"], types.StringValue("ignored"))
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
    tree.subscribe(token_fixture.tree, ChangeSubscribed, fn(_) { Changed }),
    token_sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [ChangeSubscribed(token)] = messages(token_sink)
  let assert lifecycle.Unsubscribe(token) = lifecycle.subscription(False, token)
  run(tree.unsubscribe(token), token_sink)
  let assert Ok(Nil) =
    watershed.tree_set(
      token_fixture.tree,
      ["title"],
      types.StringValue("ignored"),
    )
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
  let assert Ok(Nil) =
    watershed.tree_set(
      handle_fixture.tree,
      ["title"],
      types.StringValue("changed"),
    )
  use _ <- promise.await(promise.wait(0))
  let assert [Captured(Ok(tree.CommitEvent(kind, local, Some(handle))))] =
    messages(handle_sink)
  let state: lifecycle.State(watershed.TreeRevertible) =
    lifecycle.State(history.new(), None, 0)
  let assert lifecycle.Transition(_, [late_handle], None) =
    lifecycle.captured(state, False, Ok(#(kind, local, Some(handle))))
  run(tree.dispose_revertible(late_handle, Disposed), handle_sink)
  use _ <- promise.await(promise.wait(0))
  let assert watershed.RevertibleDisposed =
    watershed.tree_revertible_status(handle)
  watershed.close(handle_fixture.document)
  promise.resolve(Nil)
}

fn fixture(items: List(#(String, String, Bool))) -> Fixture(root) {
  let stored = document_schema.stored()
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      stored,
      Some(document_schema.checklist_value(items)),
      session,
      view_id,
    )
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
  let assert Ok(root) = watershed.resolve_root(document)
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(view) =
    schema.view_from_json(schema.stored_to_json(document_schema.stored()))
  let assert Ok(tree) = watershed.resolve_tree(document, marker, view)
  Fixture(document:, tree:, callbacks:, submissions:, closes:)
}

fn run(effect_to_run: Effect(Msg), sink: transport_js.Cell(List(Msg))) -> Nil {
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

fn messages(sink: transport_js.Cell(List(Msg))) -> List(Msg) {
  transport_js.get_cell(sink) |> list.reverse
}

fn clear_messages(sink: transport_js.Cell(List(Msg))) -> Nil {
  transport_js.set_cell(sink, [])
}
