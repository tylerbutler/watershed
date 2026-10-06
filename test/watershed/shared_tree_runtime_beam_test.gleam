@target(erlang)
import gleam/dict
@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import signet/types as token
@target(erlang)
import spillway/message
@target(erlang)
import spillway/types
@target(erlang)
import startest/expect
@target(erlang)
import watershed/channel
@target(erlang)
import watershed/fluid_ids
@target(erlang)
import watershed/handle
@target(erlang)
import watershed/map_kernel
@target(erlang)
import watershed/ordered_collection_kernel
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice/frame
@target(erlang)
import watershed/summary_policy
@target(erlang)
import watershed/tree/fixtures
@target(erlang)
import watershed/tree/identifier_fixture
@target(erlang)
import watershed/tree/runtime_fixture
@target(erlang)
import watershed/tree/types as tree_types
@target(erlang)
import watershed/tree/undo_acceptance
@target(erlang)
import watershed/tree_kernel
@target(erlang)
import watershed/wire/fluid_container
@target(erlang)
import watershed/wire/op as wire_op
@target(erlang)
import watershed/wire/socket
@target(erlang)
import watershed_beam

@target(erlang)
@external(erlang, "settlement_trace", "start")
fn start_settlement_trace(
  runtime: process.Subject(runtime_beam.Msg),
  timeout_milliseconds: Int,
) -> Result(process.Pid, String)

@target(erlang)
@external(erlang, "settlement_trace", "seal")
fn seal_settlement_trace(
  trace: process.Pid,
  timeout_milliseconds: Int,
) -> Result(Nil, String)

@target(erlang)
@external(erlang, "settlement_trace", "await_idle")
fn await_settlement_trace(
  trace: process.Pid,
  timeout_milliseconds: Int,
) -> Result(Nil, String)

@target(erlang)
@external(erlang, "settlement_trace", "stop")
fn stop_settlement_trace(
  trace: process.Pid,
  timeout_milliseconds: Int,
) -> Result(Nil, String)

@target(erlang)
pub fn settlement_trace_dead_runtime_returns_error_test() {
  let dead_runtimes = process.new_subject()
  let owner =
    process.spawn_unlinked(fn() {
      let dead_runtime: process.Subject(runtime_beam.Msg) =
        process.new_subject()
      process.send(dead_runtimes, dead_runtime)
    })
  let dead_runtime = process.receive(dead_runtimes, 1000) |> expect.to_be_ok()
  let owner_monitor = process.monitor(owner)
  process.new_selector()
  |> process.select_specific_monitor(owner_monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(owner_monitor)
  start_settlement_trace(dead_runtime, 100)
  |> expect.to_equal(Error("settlement trace runtime is not alive"))
}

@target(erlang)
fn connect_message() -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "default",
    document_id: "tree",
    token: Some("test"),
    client: types.Client(
      mode: types.WriteMode,
      details: types.ClientDetails(
        capabilities: types.ClientCapabilities(interactive: True),
        client_type: None,
        environment: None,
        device: None,
      ),
      permission: [],
      user: token.User("reader", dict.new()),
      scopes: ["doc:read", "doc:write"],
      timestamp: None,
    ),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

@target(erlang)
fn ready_tree_actor(push: fn(String, json.Json) -> Result(Nil, String)) {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(push: push, close: fn() { Nil }, drop: fn() {
      Nil
    }),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  #(actor, callbacks, view.view)
}

@target(erlang)
fn ready_identifier_actor(push: fn(String, json.Json) -> Result(Nil, String)) {
  let assert Ok(seed) =
    identifier_fixture.seed_input()
    |> runtime_core.bootstrap_seed
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(push: push, close: fn() { Nil }, drop: fn() {
      Nil
    }),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  actor
}

@target(erlang)
pub fn beam_branch_actor_fork_edit_isolation_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let selector =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    selector,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("fork")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["title"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.tree_read_view_on(actor, "A/_C", selector, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("fork"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_actor_scopes_events_and_independent_transaction_edits_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let branch =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let main_events = process.new_subject()
  let branch_events = process.new_subject()
  runtime_beam.subscribe_tree_events_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    fn(event) { process.send(main_events, event) },
  )
  runtime_beam.subscribe_tree_events_on(actor, "A/_C", branch, fn(event) {
    process.send(branch_events, event)
  })
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("temporary")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(branch_events, 1000) |> expect.to_be_ok()
  process.receive(main_events, 0) |> expect.to_equal(Error(Nil))

  runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_dispose_branch(actor, "A/_C", branch)
  |> expect.to_be_error()
  runtime_beam.tree_fork(actor, "A/_C", branch, view)
  |> expect.to_be_error()
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("rolled-back")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("main-survives")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.abort_tree_transaction_on(actor, "A/_C", branch)
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["title"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("main-survives"))))
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("temporary"))))
  process.receive(main_events, 1000) |> expect.to_be_ok()

  runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("committed")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("main-also-survives")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction_on(actor, "A/_C", branch)
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("committed"))))
  runtime_beam.tree_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["title"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("main-also-survives"))))

  runtime_beam.begin_tree_transaction_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    [],
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("fork-survives")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.abort_tree_transaction_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("fork-survives"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_commit_delivery_rejects_reentrant_lifecycle_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let branch =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let observed = process.new_subject()
  let later_called = process.new_subject()
  let later =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
      process.send(later_called, Nil)
    })
  let token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(event) {
      let assert runtime_beam.TreeCommitEvent(_, True, Some(factory), _) = event
      runtime_beam.unsubscribe(later)
      let first = factory()
      let duplicate = factory()
      let fork = runtime_beam.tree_fork(actor, "A/_C", branch, view)
      let rebase =
        runtime_beam.tree_rebase_onto(
          actor,
          "A/_C",
          branch,
          tree_types.DocumentCheckout,
        )
      let merge =
        runtime_beam.tree_merge(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          branch,
          False,
        )
      let transaction =
        runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
      process.send(observed, #(
        first,
        result.is_error(duplicate),
        result.is_error(fork),
        result.is_error(rebase),
        result.is_error(merge),
        result.is_error(transaction),
      ))
    })
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("branch")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(#(first, True, True, True, True, True)) =
    process.receive(observed, 1000)
  let handle = first |> expect.to_be_ok()
  process.receive(later_called, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.unsubscribe(token)
  let inverse_subject = process.new_subject()
  let inverse_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(event) {
      let assert runtime_beam.TreeCommitEvent(_, True, Some(factory), _) = event
      process.send(inverse_subject, factory())
    })
  runtime_beam.tree_revert(handle, False) |> expect.to_equal(Ok(Nil))
  let inverse =
    process.receive(inverse_subject, 1000)
    |> expect.to_be_ok()
    |> expect.to_be_ok()
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.tree_revert(inverse, True) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch"))))
  runtime_beam.unsubscribe(inverse_token)
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("after")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(observed, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_transaction_owner_waits_for_independent_delivery_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let branch =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let entered = process.new_subject()
  let outcomes = process.new_subject()
  let queued = process.new_subject()
  let release_waits = process.new_subject()
  let main_token =
    runtime_beam.subscribe_tree_commits_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      fn(_) {
        let release = process.new_subject()
        process.send(entered, #("main", release))
        process.send(release_waits, #("main", process.receive(release, 1000)))
        Nil
      },
    )
  let owner =
    process.spawn_unlinked(fn() {
      let assert Ok(Nil) =
        runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
      let assert Ok(Nil) =
        runtime_beam.tree_edit_view_on(
          actor,
          "A/_C",
          branch,
          view,
          tree_types.SetField(["title"], tree_types.StringValue("branch-owner")),
        )
      let assert Ok(Nil) =
        runtime_beam.tree_edit_view_on(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          view,
          tree_types.SetField(["title"], tree_types.StringValue("main-edit")),
        )
      let reply = process.new_subject()
      process.send(
        actor,
        runtime_beam.TreeTransactionCommit("A/_C", branch, reply),
      )
      runtime_beam.tree_branch_status(actor, "A/_C", branch)
      |> expect.to_equal(tree_types.BranchValid)
      process.send(queued, "commit")
      process.send(outcomes, case process.receive(reply, 1000) {
        Ok(outcome) -> outcome
        Error(_) -> Error("transaction commit reply timed out")
      })
    })
  let assert Ok(#("main", release)) = process.receive(entered, 1000)
  process.receive(queued, 1000) |> expect.to_equal(Ok("commit"))
  process.send(release, Nil)
  process.receive(release_waits, 1000)
  |> expect.to_equal(Ok(#("main", Ok(Nil))))
  process.receive(outcomes, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  let owner_monitor = process.monitor(owner)
  process.new_selector()
  |> process.select_specific_monitor(owner_monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(owner_monitor)
  runtime_beam.unsubscribe(main_token)

  let branch_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
      let release = process.new_subject()
      process.send(entered, #("branch", release))
      process.send(release_waits, #("branch", process.receive(release, 1000)))
      Nil
    })
  let owner =
    process.spawn_unlinked(fn() {
      let assert Ok(Nil) =
        runtime_beam.begin_tree_transaction_on(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          view,
          [],
        )
      let assert Ok(Nil) =
        runtime_beam.tree_edit_view_on(
          actor,
          "A/_C",
          branch,
          view,
          tree_types.SetField(["title"], tree_types.StringValue("fork-edit")),
        )
      let reply = process.new_subject()
      process.send(
        actor,
        runtime_beam.TreeTransactionAbort(
          "A/_C",
          tree_types.DocumentCheckout,
          reply,
        ),
      )
      runtime_beam.tree_branch_status(
        actor,
        "A/_C",
        tree_types.DocumentCheckout,
      )
      |> expect.to_equal(tree_types.DocumentBranch)
      process.send(queued, "abort")
      process.send(outcomes, case process.receive(reply, 1000) {
        Ok(outcome) -> outcome
        Error(_) -> Error("transaction abort reply timed out")
      })
    })
  let assert Ok(#("branch", release)) = process.receive(entered, 1000)
  process.receive(queued, 1000) |> expect.to_equal(Ok("abort"))
  process.send(release, Nil)
  process.receive(release_waits, 1000)
  |> expect.to_equal(Ok(#("branch", Ok(Nil))))
  process.receive(outcomes, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  let owner_monitor = process.monitor(owner)
  process.new_selector()
  |> process.select_specific_monitor(owner_monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(owner_monitor)
  runtime_beam.unsubscribe(branch_token)
  runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.abort_tree_transaction_on(actor, "A/_C", branch)
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_delivery_services_safe_bookkeeping_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let branch =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let saved = process.new_subject()
  let first_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(event) {
      let assert runtime_beam.TreeCommitEvent(
        _,
        True,
        Some(factory),
        Some(on_settled),
      ) = event
      process.send(saved, #(factory, on_settled))
    })
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("first")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(#(stale_factory, stale_settlement)) =
    process.receive(saved, 1000)
  runtime_beam.unsubscribe(first_token)

  let observed = process.new_subject()
  let second_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
      let factory_result = stale_factory()
      let settlement_result = stale_settlement(fn(_) { Nil })
      let status = runtime_beam.tree_branch_status(actor, "A/_C", branch)
      let token =
        runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
          Nil
        })
      process.send(observed, #(
        result.is_error(factory_result),
        result.is_error(settlement_result),
        status,
        token,
      ))
    })
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("second")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(#(True, True, tree_types.BranchValid, added_token)) =
    process.receive(observed, 1000)
  runtime_beam.unsubscribe(second_token)
  runtime_beam.unsubscribe(added_token)
  runtime_beam.tree_read_view_on(actor, "A/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("second"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_delivery_shutdown_cancels_later_callbacks_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let branch =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let called = process.new_subject()
  let closing_calls = process.new_subject()
  let ordered_close = process.new_subject()
  let later =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
      process.send(called, "later")
    })
  let _closer =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(event) {
      let assert runtime_beam.TreeCommitEvent(
        _,
        True,
        Some(factory),
        Some(on_settled),
      ) = event
      process.send(actor, runtime_beam.Shutdown)
      let factory_result = factory()
      let settlement_result = on_settled(fn(_) { Nil })
      runtime_beam.unsubscribe(later)
      let dispose_result =
        runtime_beam.tree_dispose_branch(actor, "A/_C", branch)
      let fork_result = runtime_beam.tree_fork(actor, "A/_C", branch, view)
      let rebase_result =
        runtime_beam.tree_rebase_onto(
          actor,
          "A/_C",
          branch,
          tree_types.DocumentCheckout,
        )
      let merge_result =
        runtime_beam.tree_merge(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          branch,
          False,
        )
      let begin_result =
        runtime_beam.begin_tree_transaction_on(actor, "A/_C", branch, view, [])
      let commit_result =
        runtime_beam.commit_tree_transaction_on(actor, "A/_C", branch)
      let abort_result =
        runtime_beam.abort_tree_transaction_on(actor, "A/_C", branch)
      let edit_result =
        runtime_beam.tree_edit_view_on(
          actor,
          "A/_C",
          branch,
          view,
          tree_types.SetField(["title"], tree_types.StringValue("rejected")),
        )
      let schema_result =
        runtime_beam.tree_upgrade_schema_on(actor, "A/_C", branch, view)
      let inactive =
        runtime_beam.subscribe_tree_commits_on(actor, "A/_C", branch, fn(_) {
          Nil
        })
      let inactive_status =
        runtime_beam.tree_commit_subscription_active(inactive, "A/_C", branch)
      let ordered_outcome = process.new_subject()
      let acquire_id =
        process.call(actor, waiting: 500, sending: fn(reply) {
          runtime_beam.AcquireOrderedItemWithOutcome(
            "closing-queue",
            ordered_outcome,
            reply,
          )
        })
      process.send(ordered_close, #(
        acquire_id,
        process.receive(ordered_outcome, 500),
        process.receive(ordered_outcome, 0),
      ))
      process.send(closing_calls, [
        result.is_error(factory_result),
        result.is_error(settlement_result),
        result.is_error(dispose_result),
        result.is_error(fork_result),
        result.is_error(rebase_result),
        result.is_error(merge_result),
        result.is_error(begin_result),
        result.is_error(commit_result),
        result.is_error(abort_result),
        result.is_error(edit_result),
        result.is_error(schema_result),
        inactive_status == False,
      ])
      process.send(called, "closer")
    })
  let owner = process.subject_owner(actor) |> expect.to_be_ok()
  let monitor = process.monitor(owner)
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("close")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(closing_calls, 1000)
  |> expect.to_equal(
    Ok([
      True,
      True,
      True,
      True,
      True,
      True,
      True,
      True,
      True,
      True,
      True,
      True,
    ]),
  )
  process.receive(ordered_close, 1000)
  |> expect.to_equal(
    Ok(#("", Ok(ordered_collection_kernel.Aborted), Error(Nil))),
  )
  process.receive(called, 1000) |> expect.to_equal(Ok("closer"))
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)
  process.receive(called, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_branch_status(actor, "A/_C", branch)
  |> expect.to_equal(tree_types.BranchDisposed)
}

@target(erlang)
pub fn beam_delivery_shutdown_rejects_both_replay_queues_test() {
  let submissions = process.new_subject()
  let #(actor, _, view) =
    ready_tree_actor(fn(event, _) {
      case event {
        "submitOp" -> process.send(submissions, Nil)
        _ -> Nil
      }
      Ok(Nil)
    })
  let entered = process.new_subject()
  let closing_status = process.new_subject()
  let _token =
    runtime_beam.subscribe_tree_commits_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      fn(_) {
        let command = process.new_subject()
        let release = process.new_subject()
        process.send(entered, #(command, release))
        let assert Ok(action) = process.receive(command, 1000)
        case action {
          "close" -> {
            process.send(actor, runtime_beam.Shutdown)
            process.send(
              closing_status,
              runtime_beam.tree_branch_status(
                actor,
                "A/_C",
                tree_types.DocumentCheckout,
              ),
            )
          }
          _ -> Nil
        }
        process.receive(release, 1000) |> expect.to_equal(Ok(Nil))
      },
    )
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("a")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(#(first_command, first_release)) =
    process.receive(entered, 1000)
  let second_reply = process.new_subject()
  let third_reply = process.new_subject()
  process.send(
    actor,
    runtime_beam.TreeEditView(
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      tree_types.SetField(["title"], tree_types.StringValue("b")),
      second_reply,
    ),
  )
  process.send(
    actor,
    runtime_beam.TreeEditView(
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      tree_types.SetField(["title"], tree_types.StringValue("c")),
      third_reply,
    ),
  )
  process.send(first_command, "continue")
  process.send(first_release, Nil)
  let assert Ok(#(second_command, second_release)) =
    process.receive(entered, 1000)
  process.send(second_command, "close")
  process.receive(closing_status, 1000)
  |> expect.to_equal(Ok(tree_types.BranchDisposed))
  process.send(second_release, Nil)
  process.receive(second_reply, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(third_reply, 1000)
  |> expect.to_be_ok()
  |> expect.to_be_error()
  process.receive(submissions, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(submissions, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
}

@target(erlang)
pub fn beam_branch_merge_disposal_cleans_only_source_scope_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let source =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let descendant =
    runtime_beam.tree_fork(actor, "A/_C", source, view)
    |> expect.to_be_ok()
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    source,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("merged")),
  )
  |> expect.to_equal(Ok(Nil))
  let source_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", source, fn(_) { Nil })
  let target_token =
    runtime_beam.subscribe_tree_commits_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      fn(_) { Nil },
    )
  let descendant_token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", descendant, fn(_) {
      Nil
    })
  runtime_beam.tree_merge(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    source,
    True,
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_commit_subscription_active(source_token, "A/_C", source)
  |> expect.to_be_false()
  runtime_beam.tree_commit_subscription_active(
    target_token,
    "A/_C",
    tree_types.DocumentCheckout,
  )
  |> expect.to_be_true()
  runtime_beam.tree_commit_subscription_active(
    descendant_token,
    "A/_C",
    descendant,
  )
  |> expect.to_be_true()
  process.send(actor, runtime_beam.Shutdown)

  let #(empty_actor, _, empty_view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let empty =
    runtime_beam.tree_fork(
      empty_actor,
      "A/_C",
      tree_types.DocumentCheckout,
      empty_view,
    )
    |> expect.to_be_ok()
  let empty_token =
    runtime_beam.subscribe_tree_commits_on(empty_actor, "A/_C", empty, fn(_) {
      Nil
    })
  runtime_beam.tree_merge(
    empty_actor,
    "A/_C",
    tree_types.DocumentCheckout,
    empty,
    True,
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_commit_subscription_active(empty_token, "A/_C", empty)
  |> expect.to_be_false()
  process.send(empty_actor, runtime_beam.Shutdown)

  let #(self_actor, _, self_view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let self =
    runtime_beam.tree_fork(
      self_actor,
      "A/_C",
      tree_types.DocumentCheckout,
      self_view,
    )
    |> expect.to_be_ok()
  let self_token =
    runtime_beam.subscribe_tree_commits_on(self_actor, "A/_C", self, fn(_) {
      Nil
    })
  runtime_beam.tree_merge(self_actor, "A/_C", self, self, True)
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_commit_subscription_active(self_token, "A/_C", self)
  |> expect.to_be_false()
  process.send(self_actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_branch_registered_source_settlement_survives_unsubscribe_until_merge_ack_test() {
  let submissions = process.new_subject()
  let #(actor, callbacks, view) =
    ready_tree_actor(fn(event, payload) {
      case event {
        "submitOp" -> {
          let assert Ok(dynamic) =
            json.parse(json.to_string(payload), decode.dynamic)
          let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
            frame.decode_submit_operation(dynamic)
          process.send(submissions, submitted)
        }
        _ -> Nil
      }
      Ok(Nil)
    })
  let source =
    runtime_beam.tree_fork(actor, "A/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  let registered = process.new_subject()
  let settled = process.new_subject()
  let token =
    runtime_beam.subscribe_tree_commits_on(actor, "A/_C", source, fn(event) {
      let assert runtime_beam.TreeCommitEvent(_, True, _, Some(on_settled)) =
        event
      process.send(
        registered,
        on_settled(fn(outcome) { process.send(settled, outcome) }),
      )
    })
  runtime_beam.tree_edit_view_on(
    actor,
    "A/_C",
    source,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("merged")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  runtime_beam.unsubscribe(token)
  runtime_beam.tree_read_view_on(actor, "A/_C", source, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("merged"))))
  runtime_beam.tree_merge(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    source,
    False,
  )
  |> expect.to_equal(Ok(Nil))
  let submitted = process.receive(submissions, 1000) |> expect.to_be_ok()
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("reader"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: submitted.contents,
        metadata: submitted.metadata,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  process.receive(settled, 1000)
  |> expect.to_equal(Ok(tree_types.FullyApplied))
  process.receive(settled, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_shutdown_cancels_captured_settlements_during_other_delivery_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let actor = watershed_beam.runtime_subject(document)
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  let source = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let other_scope = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let blocked = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let registered = process.new_subject()
  let first_started = process.new_subject()
  let close_processed = process.new_subject()
  let wait_results = process.new_subject()
  let later_started = process.new_subject()
  let _ =
    watershed_beam.subscribe_tree_commits(source, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, _, on_settled) = event
      process.send(
        registered,
        #("source-first", local, case on_settled {
          Some(on_settled) ->
            on_settled(fn(_) {
              let close_command = process.new_subject()
              process.send(first_started, close_command)
              process.send(wait_results, #(
                "source-release",
                process.receive(close_command, 1000),
              ))
              watershed_beam.close(document)
              process.send(
                close_processed,
                watershed_beam.tree_branch_status(source),
              )
            })
          None -> Error("missing source settlement registration")
        }),
      )
      process.send(
        registered,
        #("source-later", local, case on_settled {
          Some(on_settled) ->
            on_settled(fn(_) { process.send(later_started, "source") })
          None -> Error("missing source settlement registration")
        }),
      )
    })
  let _ =
    watershed_beam.subscribe_tree_commits(other_scope, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, _, on_settled) = event
      process.send(
        registered,
        #("other", local, case on_settled {
          Some(on_settled) ->
            on_settled(fn(_) { process.send(later_started, "other") })
          None -> Error("missing other settlement registration")
        }),
      )
    })
  watershed_beam.tree_set(
    source,
    ["child", "label"],
    tree_types.StringValue("settle"),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(registered, 1000)
  |> expect.to_equal(Ok(#("source-first", True, Ok(Nil))))
  process.receive(registered, 1000)
  |> expect.to_equal(Ok(#("source-later", True, Ok(Nil))))
  watershed_beam.tree_merge(main, source, False) |> expect.to_equal(Ok(Nil))
  let source_payload = process.receive(submissions, 1000) |> expect.to_be_ok()
  watershed_beam.tree_set(
    other_scope,
    ["child", "label"],
    tree_types.StringValue("other"),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(registered, 1000)
  |> expect.to_equal(Ok(#("other", True, Ok(Nil))))
  watershed_beam.tree_merge(main, other_scope, False)
  |> expect.to_equal(Ok(Nil))
  let other_payload = process.receive(submissions, 1000) |> expect.to_be_ok()
  let source_dynamic =
    json.parse(json.to_string(source_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(client_id, [[source_submission]]) =
    frame.decode_submit_operation(source_dynamic)
    |> expect.to_be_ok()
  client_id |> expect.to_equal("reader")
  let owner = process.subject_owner(actor) |> expect.to_be_ok()
  let owner_monitor = process.monitor(owner)
  let settlement_trace =
    start_settlement_trace(actor, 1000) |> expect.to_be_ok()
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(source_submission, client_id, 1),
    ]),
  )
  let close_command = process.receive(first_started, 1000) |> expect.to_be_ok()
  seal_settlement_trace(settlement_trace, 1000) |> expect.to_equal(Ok(Nil))

  let delivery_entered = process.new_subject()
  let _other_token =
    watershed_beam.subscribe_tree_commits(blocked, fn(_) {
      let release = process.new_subject()
      process.send(delivery_entered, release)
      process.send(wait_results, #(
        "blocked-release",
        process.receive(release, 1000),
      ))
    })
  watershed_beam.tree_set(
    blocked,
    ["child", "label"],
    tree_types.StringValue("held"),
  )
  |> expect.to_equal(Ok(Nil))
  let release = process.receive(delivery_entered, 1000) |> expect.to_be_ok()
  process.send(close_command, Nil)
  process.receive(close_processed, 1000)
  |> expect.to_equal(Ok(watershed_beam.BranchDisposed))
  process.receive(wait_results, 1000)
  |> expect.to_equal(Ok(#("source-release", Ok(Nil))))
  await_settlement_trace(settlement_trace, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(later_started, 0) |> expect.to_equal(Error(Nil))
  stop_settlement_trace(settlement_trace, 1000) |> expect.to_equal(Ok(Nil))
  process.send(release, Nil)
  process.receive(wait_results, 1000)
  |> expect.to_equal(Ok(#("blocked-release", Ok(Nil))))
  process.new_selector()
  |> process.select_specific_monitor(owner_monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(owner_monitor)
  let other_dynamic =
    json.parse(json.to_string(other_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(other_client_id, [[other_submission]]) =
    frame.decode_submit_operation(other_dynamic)
    |> expect.to_be_ok()
  other_client_id |> expect.to_equal(client_id)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(other_submission, other_client_id, 2),
    ]),
  )
  process.receive(later_started, 0) |> expect.to_equal(Error(Nil))
}

@target(erlang)
pub fn beam_facade_merge_ack_disposal_cancels_only_disposed_settlement_scopes_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let callbacks = process.receive(connections, 1000) |> expect.to_be_ok()
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let actor = watershed_beam.runtime_subject(document)
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  let source = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let target = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let descendant = watershed_beam.tree_fork(target) |> expect.to_be_ok()
  let registered = process.new_subject()
  let factories = process.new_subject()
  let localities = process.new_subject()
  let source_outcomes = process.new_subject()
  let target_outcomes = process.new_subject()
  let descendant_outcomes = process.new_subject()
  let main_outcomes = process.new_subject()
  let completed = process.new_subject()
  let _ =
    watershed_beam.subscribe_tree_commits(source, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, factory, on_settled) = event
      process.send(localities, #("source", local))
      process.send(factories, case factory {
        Some(factory) -> factory()
        None -> Error("missing source revertible factory")
      })
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) { process.send(source_outcomes, outcome) })
        None -> Error("missing source settlement registration")
      })
    })
  let _ =
    watershed_beam.subscribe_tree_commits(target, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, _, on_settled) = event
      process.send(localities, #("target", local))
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            process.send(target_outcomes, #(
              outcome,
              watershed_beam.tree_dispose_branch(target),
            ))
          })
        None -> Error("missing target settlement registration")
      })
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            process.send(target_outcomes, #(outcome, Ok(Nil)))
          })
        None -> Error("missing target settlement registration")
      })
    })
  let _ =
    watershed_beam.subscribe_tree_commits(descendant, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, _, on_settled) = event
      process.send(localities, #("descendant", local))
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) { process.send(descendant_outcomes, outcome) })
        None -> Error("missing descendant settlement registration")
      })
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(_) { process.send(completed, "descendant") })
        None -> Error("missing descendant settlement completion")
      })
    })
  let _ =
    watershed_beam.subscribe_tree_commits(main, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, factory, on_settled) = event
      process.send(localities, #("main", local))
      process.send(factories, case factory {
        Some(factory) -> factory()
        None -> Error("missing main revertible factory")
      })
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) { process.send(main_outcomes, outcome) })
        None -> Error("missing main settlement registration")
      })
      process.send(registered, case on_settled {
        Some(on_settled) ->
          on_settled(fn(_) { process.send(completed, "main") })
        None -> Error("missing main settlement completion")
      })
    })
  watershed_beam.tree_set(
    source,
    ["child", "label"],
    tree_types.StringValue("settled"),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(localities, 1000) |> expect.to_equal(Ok(#("source", True)))
  process.receive(factories, 1000) |> expect.to_be_ok() |> expect.to_be_ok()
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  watershed_beam.tree_merge(target, source, False) |> expect.to_equal(Ok(Nil))
  process.receive(localities, 1000) |> expect.to_equal(Ok(#("target", True)))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  watershed_beam.tree_merge(descendant, target, False)
  |> expect.to_equal(Ok(Nil))
  process.receive(localities, 1000)
  |> expect.to_equal(Ok(#("descendant", True)))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  watershed_beam.tree_merge(main, source, True) |> expect.to_equal(Ok(Nil))
  process.receive(localities, 1000) |> expect.to_equal(Ok(#("main", True)))
  process.receive(factories, 1000) |> expect.to_be_ok() |> expect.to_be_ok()
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(registered, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  let submitted = process.receive(submissions, 1000) |> expect.to_be_ok()
  process.receive(source_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(target_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(descendant_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(main_outcomes, 0) |> expect.to_equal(Error(Nil))
  let settlement_trace =
    start_settlement_trace(actor, 1000) |> expect.to_be_ok()
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "reader", 1),
    ]),
  )
  process.receive(target_outcomes, 1000)
  |> expect.to_equal(Ok(#(tree_types.FullyApplied, Ok(Nil))))
  process.receive(descendant_outcomes, 1000)
  |> expect.to_equal(Ok(tree_types.FullyApplied))
  process.receive(main_outcomes, 1000)
  |> expect.to_equal(Ok(tree_types.FullyApplied))
  let completion_one = process.receive(completed, 1000) |> expect.to_be_ok()
  let completion_two = process.receive(completed, 1000) |> expect.to_be_ok()
  [completion_one, completion_two]
  |> list.contains("descendant")
  |> expect.to_be_true()
  [completion_one, completion_two]
  |> list.contains("main")
  |> expect.to_be_true()
  watershed_beam.tree_branch_status(source)
  |> expect.to_equal(watershed_beam.BranchDisposed)
  watershed_beam.tree_branch_status(target)
  |> expect.to_equal(watershed_beam.BranchDisposed)
  watershed_beam.tree_branch_status(descendant)
  |> expect.to_equal(watershed_beam.BranchValid)
  seal_settlement_trace(settlement_trace, 1000) |> expect.to_equal(Ok(Nil))
  await_settlement_trace(settlement_trace, 1000)
  |> expect.to_equal(Ok(Nil))
  stop_settlement_trace(settlement_trace, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(source_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(target_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(descendant_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(main_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(completed, 0) |> expect.to_equal(Error(Nil))
  let duplicate_trace = start_settlement_trace(actor, 1000) |> expect.to_be_ok()
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "reader", 1),
    ]),
  )
  watershed_beam.tree_branch_status(descendant)
  |> expect.to_equal(watershed_beam.BranchValid)
  seal_settlement_trace(duplicate_trace, 1000) |> expect.to_equal(Ok(Nil))
  await_settlement_trace(duplicate_trace, 1000)
  |> expect.to_equal(Ok(Nil))
  stop_settlement_trace(duplicate_trace, 1000) |> expect.to_equal(Ok(Nil))
  process.receive(source_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(target_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(descendant_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(main_outcomes, 0) |> expect.to_equal(Error(Nil))
  process.receive(completed, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn beam_facade_branch_settlement_survives_unsubscribe_and_reconnect_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let connections = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let first = process.receive(connections, 1000) |> expect.to_be_ok()
  first.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  first.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let actor = watershed_beam.runtime_subject(document)
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let root = watershed_beam.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed_beam.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    watershed_beam.resolve_tree(document, marker, view.view)
    |> expect.to_be_ok()
  let source = watershed_beam.tree_fork(main) |> expect.to_be_ok()
  let registered = process.new_subject()
  let outcomes = process.new_subject()
  let token =
    watershed_beam.subscribe_tree_commits(source, fn(event) {
      let watershed_beam.TreeCommitEvent(_, local, _, on_settled) = event
      process.send(
        registered,
        #(local, case on_settled {
          Some(on_settled) ->
            on_settled(fn(outcome) { process.send(outcomes, outcome) })
          None -> Error("missing reconnect settlement registration")
        }),
      )
    })
  watershed_beam.tree_set(
    source,
    ["child", "label"],
    tree_types.StringValue("reconnect"),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(registered, 1000)
  |> expect.to_equal(Ok(#(True, Ok(Nil))))
  watershed_beam.unsubscribe(token)
  watershed_beam.tree_merge(main, source, False) |> expect.to_equal(Ok(Nil))
  let original_payload = process.receive(submissions, 1000) |> expect.to_be_ok()
  let original_dynamic =
    json.parse(json.to_string(original_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(original_client, [[original]]) =
    frame.decode_submit_operation(original_dynamic)
    |> expect.to_be_ok()
  original_client |> expect.to_equal("reader")
  original.client_sequence_number |> expect.to_equal(1)
  original.reference_sequence_number |> expect.to_equal(0)
  process.receive(outcomes, 0) |> expect.to_equal(Error(Nil))
  first.on_close("transport lost")
  let second = process.receive(connections, 1000) |> expect.to_be_ok()
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  second.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
      membership_frame(2, "leave", "\"reader\""),
    ]),
  )
  let resent_payload = process.receive(submissions, 1000) |> expect.to_be_ok()
  let resent_dynamic =
    json.parse(json.to_string(resent_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(resent_client, [[resent]]) =
    frame.decode_submit_operation(resent_dynamic)
    |> expect.to_be_ok()
  resent_client |> expect.to_equal("reader-2")
  resent.client_sequence_number
  |> expect.to_equal(original.client_sequence_number + 1)
  resent.client_sequence_number |> expect.to_equal(2)
  resent.reference_sequence_number |> expect.to_equal(2)
  resent.contents |> expect.to_equal(original.contents)
  resent.metadata |> expect.to_equal(original.metadata)
  let original_envelope =
    fluid_container.decode(original.contents, original.metadata)
    |> expect.to_be_ok()
  let resent_envelope =
    fluid_container.decode(resent.contents, resent.metadata)
    |> expect.to_be_ok()
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(original_range),
      0,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = original_envelope.messages
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(resent_range),
      0,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = resent_envelope.messages
  resent_range |> expect.to_equal(original_range)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader-2"))
  second.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, resent_client, 3),
    ]),
  )
  process.receive(outcomes, 1000)
  |> expect.to_equal(Ok(tree_types.FullyApplied))
  watershed_beam.tree_branch_status(source)
  |> expect.to_equal(watershed_beam.BranchValid)
  process.receive(outcomes, 100) |> expect.to_equal(Error(Nil))
  process.receive(submissions, 100) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn identifier_refusals_preserve_installed_runtime_test() {
  let submissions = process.new_subject()
  let actor =
    ready_identifier_actor(fn(event, payload) {
      case event {
        "submitOp" -> process.send(submissions, payload)
        _ -> Nil
      }
      Ok(Nil)
    })
  let events = process.new_subject()
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )

  [
    tree_types.SetField(["id"], tree_types.StringValue("replacement")),
    tree_types.SetField(["id"], tree_types.StringValue("literal-custom-id")),
    tree_types.ClearField(["id"]),
  ]
  |> list.each(fn(edit) {
    runtime_beam.tree_edit(actor, "A/_C", edit) |> expect.to_be_error
    runtime_beam.tree_read(actor, "A/_C", ["id"])
    |> expect.to_equal(Ok(Some(tree_types.StringValue("literal-custom-id"))))
    process.receive(events, 0) |> expect.to_equal(Error(Nil))
    process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  })
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
fn membership_frame(
  sequence_number: Int,
  operation_type: String,
  data: String,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: None,
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: 0,
    operation_type: operation_type,
    contents: json.null(),
    metadata: None,
    timestamp: 0,
    data: Some(data),
  )
}

@target(erlang)
fn identifier_seed() -> runtime_core.BootstrapSeed {
  identifier_fixture.full_seed_input(
    identifier_fixture.full_root(
      identifier_fixture.point("child", "child"),
      [identifier_fixture.point("existing", "existing")],
      [],
      [],
    ),
  )
  |> runtime_core.bootstrap_seed
  |> expect.to_be_ok()
}

@target(erlang)
fn history_count(
  actor: process.Subject(runtime_beam.Msg),
  field: String,
) -> Int {
  runtime_beam.tree_history_evidence(actor, "A/_C")
  |> expect.to_be_ok()
  |> json.to_string
  |> json.parse(decode.at([field], decode.list(decode.dynamic)))
  |> expect.to_be_ok()
  |> list.length
}

@target(erlang)
fn sequenced_submission(
  submitted: frame.SubmittedOperation,
  client_id: String,
  sequence_number: Int,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: submitted.client_sequence_number,
    reference_sequence_number: submitted.reference_sequence_number,
    operation_type: submitted.operation_type,
    contents: submitted.contents,
    metadata: submitted.metadata,
    timestamp: 0,
    data: None,
  )
}

@target(erlang)
pub fn assert_pending_multi_edit_transaction_resubmit() {
  let sender_connections = process.new_subject()
  let receiver_connections = process.new_subject()
  let submissions = process.new_subject()
  let sender_events = process.new_subject()
  let receiver_events = process.new_subject()
  let assert Ok(sender) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(sender_connections, callbacks)
      }),
    )
  let assert Ok(receiver) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(receiver_connections, callbacks)
      }),
    )
  let assert Ok(sender_transport) = process.receive(sender_connections, 1000)
  let assert Ok(receiver_transport) =
    process.receive(receiver_connections, 1000)
  sender_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  receiver_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["writer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  receiver_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "receiver",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["receiver"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(sender) |> expect.to_equal(Ok(Nil))
  runtime_beam.await_ready(receiver) |> expect.to_equal(Ok(Nil))
  process.send(
    sender,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(sender_events, event)
    }),
  )
  process.send(
    receiver,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(receiver_events, event)
    }),
  )
  let view = identifier_fixture.full_view()
  runtime_beam.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.ArrayInsert(["left"], 1, [
      tree_types.ObjectValue(identifier_fixture.point_type, [
        #("label", tree_types.StringValue("pending")),
      ]),
    ]),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("pending-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert Ok(original) = process.receive(submissions, 1000)
  let identifier =
    runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  process.receive(sender_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))

  sender_transport.on_close("transport lost")
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("reconnecting")
  let assert Ok(rejoined) = process.receive(sender_connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["writer-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"writer\""),
    ]),
  )
  let assert Ok(resent) = process.receive(submissions, 1000)
  runtime_beam.connection_observation(sender).phase |> expect.to_equal("ready")
  resent.client_sequence_number
  |> expect.to_equal(original.client_sequence_number + 1)
  let assert Ok(batch) =
    fluid_container.decode(resent.contents, resent.metadata)
  batch.messages
  |> list.count(fn(message) {
    case message.kind {
      fluid_container.ChannelOperation(_, _) -> True
      _ -> False
    }
  })
  |> expect.to_equal(1)

  receiver_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
      membership_frame(2, "leave", "\"writer\""),
      sequenced_submission(resent, "writer-2", 3),
    ]),
  )
  process.receive(receiver_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(False))))
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime_beam.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending-final"))))
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, "writer-2", 3),
    ]),
  )
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  process.receive(sender_events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  process.send(sender, runtime_beam.Shutdown)
  process.send(receiver, runtime_beam.Shutdown)
}

@target(erlang)
pub fn assert_accepted_transaction_before_drop() {
  let sender_connections = process.new_subject()
  let receiver_connections = process.new_subject()
  let submissions = process.new_subject()
  let sender_events = process.new_subject()
  let receiver_events = process.new_subject()
  let assert Ok(sender) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(sender_connections, callbacks)
      }),
    )
  let assert Ok(receiver) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(receiver_connections, callbacks)
      }),
    )
  let assert Ok(sender_transport) = process.receive(sender_connections, 1000)
  let assert Ok(receiver_transport) =
    process.receive(receiver_connections, 1000)
  sender_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  receiver_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["writer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  receiver_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "receiver",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["receiver"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(sender) |> expect.to_equal(Ok(Nil))
  runtime_beam.await_ready(receiver) |> expect.to_equal(Ok(Nil))
  process.send(
    sender,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(sender_events, event)
    }),
  )
  process.send(
    receiver,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(receiver_events, event)
    }),
  )
  let view = identifier_fixture.full_view()
  runtime_beam.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.ArrayInsert(["left"], 1, [
      tree_types.ObjectValue(identifier_fixture.point_type, [
        #("label", tree_types.StringValue("accepted")),
      ]),
    ]),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("accepted-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert Ok(submitted) = process.receive(submissions, 1000)
  let identifier =
    runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  process.receive(sender_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  receiver_transport.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
    ]),
  )
  process.receive(receiver_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(False))))
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime_beam.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("accepted-final"))))
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  sender_transport.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(sender_connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[resent]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, resent)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["writer-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
      membership_frame(2, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(3, "leave", "\"writer\""),
    ]),
  )
  runtime_beam.connection_observation(sender).phase |> expect.to_equal("ready")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  process.receive(sender_events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  process.send(sender, runtime_beam.Shutdown)
  process.send(receiver, runtime_beam.Shutdown)
}

@target(erlang)
fn pending_reconnect_actor() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let connections = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let assert Ok(first) = process.receive(connections, 1000)
  first.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  first.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  first.on_close("transport lost")
  #(actor, connections)
}

@target(erlang)
pub fn failed_reconnect_request_does_not_restore_stale_phase_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "requestOps" -> Error("history request refused")
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let assert Ok(third) = process.receive(connections, 1000)
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("reconnecting")
  observation.pending_tree_count |> expect.to_equal(1)
  third.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  third.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-3",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-3"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.connection_observation(actor).client_id
  |> expect.to_equal(Some("reader-3"))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_gap_request_does_not_restore_old_catching_up_core_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case
          event == "requestOps"
          && json.to_string(payload)
          == json.to_string(socket.encode_request_operations(from: 1))
        {
          True -> Error("gap request refused")
          False -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  second.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  second.on_event(
    "op",
    frame.encode_operation_event([membership_frame(3, "leave", "\"other\"")]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("reconnecting")
  observation.error |> expect.to_equal(Some("gap request refused"))
  observation.pending_tree_count |> expect.to_equal(1)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn permanent_reconnect_rejection_retains_pending_without_retry_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_error",
    json.object([
      #("code", json.int(401)),
      #("message", json.string("authorization revoked")),
    ]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.error |> expect.to_equal(Some("authorization revoked"))
  observation.pending_tree_count |> expect.to_equal(1)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  second.on_event(
    "connect_document_error",
    json.object([
      #("code", json.int(401)),
      #("message", json.string("authorization revoked")),
    ]),
  )
  process.receive(connections, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn repeated_reconnect_server_failures_stop_with_observable_reason_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let error =
    json.object([
      #("code", json.int(503)),
      #("message", json.string("service unavailable")),
    ])
  list.each([Nil, Nil, Nil], fn(_) {
    let assert Ok(callbacks) = process.receive(connections, 1000)
    callbacks.on_ready(
      runtime_beam.TransportHandle(
        push: fn(_, _) { Ok(Nil) },
        close: fn() { Nil },
        drop: fn() { Nil },
      ),
    )
    callbacks.on_event("connect_document_error", error)
    let observation = runtime_beam.connection_observation(actor)
    observation.phase |> expect.to_equal("reconnecting")
    observation.error |> expect.to_equal(Some("service unavailable"))
    observation.pending_tree_count |> expect.to_equal(1)
    process.receive(connections, 0) |> expect.to_equal(Error(Nil))
  })
  let assert Ok(last) = process.receive(connections, 1000)
  last.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  last.on_event("connect_document_error", error)
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.error |> expect.to_equal(Some("service unavailable"))
  process.receive(connections, 500) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn bad_replayed_operation_suspends_without_killing_actor_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          0,
          None,
        ),
      ]),
    )
  second.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.pending_tree_count |> expect.to_equal(1)
  observation.error |> expect.to_not_equal(None)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn bad_live_operation_fails_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          0,
          None,
        ),
      ]),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_not_equal(None)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn deferred_bad_operation_fails_transaction_abort_explicitly_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          0,
          None,
        ),
      ]),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.abort_tree_transaction(actor, "A/_C") |> expect.to_be_error()
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_not_equal(None)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
fn deferred_gap_request_failure(
  finish: fn(process.Subject(runtime_beam.Msg), String) -> Result(Nil, String),
) {
  let #(actor, callbacks, view) =
    ready_tree_actor(fn(event, _) {
      case event {
        "requestOps" -> Error("gap request refused")
        _ -> Ok(Nil)
      }
    })
  runtime_beam.begin_tree_transaction(actor, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"other\""),
    ]),
  )
  finish(actor, "A/_C")
  |> expect.to_equal(Error("gap request refused"))
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_equal(Some("gap request refused"))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn deferred_gap_request_failure_returns_from_abort_test() {
  deferred_gap_request_failure(runtime_beam.abort_tree_transaction)
}

@target(erlang)
pub fn deferred_gap_request_failure_returns_from_noop_commit_test() {
  deferred_gap_request_failure(runtime_beam.commit_tree_transaction)
}

@target(erlang)
pub fn transaction_transport_failure_is_not_reported_as_commit_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "submitOp" -> Error("submission refused")
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    actor,
    "A/_C",
    view.view,
    tree_types.SetField(["title"], tree_types.StringValue("pending")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(actor, "A/_C") |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn dead_transaction_caller_does_not_strand_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let begun = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
      |> expect.to_equal(Ok(Nil))
      runtime_beam.tree_edit_view(
        actor,
        "A/_C",
        view.view,
        tree_types.SetField(["title"], tree_types.StringValue("discarded")),
      )
      |> expect.to_equal(Ok(Nil))
      process.send(begun, Nil)
    })
  let monitor = process.monitor(caller)
  process.receive(begun, 1000) |> expect.to_equal(Ok(Nil))
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)

  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.abort_tree_transaction(actor, "A/_C")
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn active_transaction_rejects_nonowner_tree_access_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let begun = process.new_subject()
  let owner_results = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let continue = process.new_subject()
      runtime_beam.begin_tree_transaction(actor, "A/_C", view, [])
      |> expect.to_equal(Ok(Nil))
      runtime_beam.tree_edit_view(
        actor,
        "A/_C",
        view,
        tree_types.SetField(["title"], tree_types.StringValue("owner")),
      )
      |> expect.to_equal(Ok(Nil))
      process.send(begun, continue)
      process.receive(continue, 1000) |> expect.to_equal(Ok(Nil))
      let read = runtime_beam.tree_read(actor, "A/_C", ["title"])
      let edit =
        runtime_beam.tree_edit(
          actor,
          "A/_C",
          tree_types.SetField(["title"], tree_types.StringValue("owner-two")),
        )
      let abort = runtime_beam.abort_tree_transaction(actor, "A/_C")
      process.send(owner_results, #(read, edit, abort))
    })
  let continue = process.receive(begun, 1000) |> expect.to_be_ok()

  runtime_beam.tree_read_view(actor, "A/_C", view, ["title"])
  |> expect.to_equal(Error("tree transaction uses another caller"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("nonowner")),
  )
  |> expect.to_equal(Error("tree transaction uses another caller"))

  process.send(continue, Nil)
  process.receive(owner_results, 1000)
  |> expect.to_equal(
    Ok(#(Ok(Some(tree_types.StringValue("owner"))), Ok(Nil), Ok(Nil))),
  )
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("after"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn seeded_actor_resolves_routed_root_before_publication_test() {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let before =
    process.call(actor, waiting: 1000, sending: runtime_beam.ResolveRoot)
  before |> expect.to_be_error()
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["reader"],
      initial_messages: list.map(prefix, runtime_fixture.sequenced_frame),
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.operations_since_summary(actor) |> expect.to_equal(2)
  runtime_beam.tree_read(actor, "A/_C", []) |> expect.to_be_ok()
  let events = process.new_subject()
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = input.compressor
  let assert Ok(captured) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = captured.operations
  callbacks.on_event(
    "op",
    frame.encode_operation_event([runtime_fixture.sequenced_frame(group)]),
  )
  runtime_beam.operations_since_summary(actor) |> expect.to_equal(3)
  process.receive(events, 1000) |> expect.to_be_ok()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.summarize(actor)
  |> expect.to_equal(Error("tree summary publication is not supported"))
  callbacks.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader-2"))
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.is_synced(actor) |> expect.to_equal(True)
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("pending")),
  )
  |> expect.to_equal(Ok(Nil))
  rejoined.on_event(
    "nack",
    json.object([
      #(
        "nacks",
        json.preprocessed_array([
          json.object([
            #("sequenceNumber", json.int(1)),
            #(
              "content",
              json.object([
                #("code", json.int(400)),
                #("type", json.string("BadRequestError")),
                #("message", json.string("retry")),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_bootstrap_history_read_reports_error_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: message.ConnectMessage(..connect_message(), token: None),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(pid) = process.subject_owner(actor)
  process.unlink(pid)
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["reader"],
      initial_messages: [membership_frame(3, "leave", "\"departed\"")],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Error(
    "history catch-up failed: history catch-up requires an auth token",
  ))
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn invalid_bootstrap_message_fails_ready_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader"],
      initial_messages: [
        membership_frame(1, "unsupported-required-message", ""),
      ],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn routed_beam_facade_root_serializes_absolute_handle_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        datastores: list.append(input.datastores, [
          runtime_core.DatastoreSeed("B", ["test"]),
        ]),
        channels: list.append(input.channels, [
          runtime_core.ChannelSeed(
            fluid_container.Route("B", "root"),
            channel.fluid_attributes(channel.MapChannel),
            channel.MapSnapshot([]),
          ),
        ]),
      ),
    )
  let callbacks_subject = process.new_subject()
  let assert Ok(document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  watershed_beam.resolve_root(document) |> expect.to_be_error()
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let actor = watershed_beam.runtime_subject(document)
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let assert Ok(root) = watershed_beam.resolve_root(document)
  let assert [view] = input.tree_views
  let assert Ok(marker) = watershed_beam.get(root, "tree")
  let assert Ok(tree) = watershed_beam.resolve_tree(document, marker, view.view)
  watershed_beam.tree_handle_of(tree)
  |> expect.to_equal(handle.encode_handle("A/_C"))
  let typed = watershed_beam.typed(root)
  watershed_beam.resolve_tree_field(
    document,
    typed,
    schema.channel_field("tree"),
    view.view,
  )
  |> result.map(fn(value) { option.map(value, watershed_beam.tree_handle_of) })
  |> expect.to_equal(Ok(Some(marker)))
  watershed_beam.resolve_tree_field(
    document,
    typed,
    schema.channel_field("absent-tree"),
    view.view,
  )
  |> expect.to_equal(Ok(None))
  watershed_beam.set_tree_field(typed, schema.channel_field("tree"), tree)
  watershed_beam.get(root, "tree") |> expect.to_equal(Ok(marker))
  let events = watershed_beam.subscribe_tree(tree)
  runtime_beam.resolve_root(actor) |> expect.to_be_ok()
  watershed_beam.tree_set(tree, ["unknown"], tree_types.StringValue("invalid"))
  |> expect.to_be_error()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  watershed_beam.tree_set(tree, ["title"], tree_types.StringValue("native"))
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(tree_kernel.TreeChanged(True)))
  watershed_beam.tree_clear(tree, ["title"]) |> expect.to_be_error()
  watershed_beam.resolve_tree(
    document,
    watershed_beam.handle_of(root),
    view.view,
  )
  |> expect.to_be_error()
  watershed_beam.handle_of(root)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/A/root\"}")
  let assert Ok(other) =
    watershed_beam.resolve(document, handle.encode_handle("B/root"))
  watershed_beam.handle_of(other)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/B/root\"}")
  let assert Ok(fork) = watershed_beam.tree_fork(tree)
  watershed_beam.tree_branch_status(tree)
  |> expect.to_equal(watershed_beam.DocumentBranch)
  watershed_beam.tree_branch_status(fork)
  |> expect.to_equal(watershed_beam.BranchValid)
  watershed_beam.tree_set(fork, ["title"], tree_types.StringValue("fork-only"))
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  let assert Ok(nested) = watershed_beam.tree_fork(fork)
  watershed_beam.tree_dispose_branch(fork) |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_dispose_branch(fork) |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_branch_status(fork)
  |> expect.to_equal(watershed_beam.BranchDisposed)
  watershed_beam.tree_set(nested, ["title"], tree_types.StringValue("nested"))
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_rebase_onto(nested, tree) |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  watershed_beam.tree_merge(tree, nested, True) |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("nested"))))
  watershed_beam.tree_branch_status(nested)
  |> expect.to_equal(watershed_beam.BranchDisposed)
  watershed_beam.tree_dispose_branch(tree) |> expect.to_be_error()
  let other_callbacks_subject = process.new_subject()
  let assert Ok(other_document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "other-tree",
      user_id: "other-reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(other_callbacks) {
        process.send(other_callbacks_subject, other_callbacks)
      }),
    )
  let assert Ok(other_callbacks) =
    process.receive(other_callbacks_subject, 1000)
  other_callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  other_callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "other-reader",
      tenant_id: "default",
      document_id: "other-tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["other-reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  let other_actor = watershed_beam.runtime_subject(other_document)
  runtime_beam.await_ready(other_actor) |> expect.to_equal(Ok(Nil))
  let other_root =
    watershed_beam.resolve_root(other_document) |> expect.to_be_ok()
  let other_marker = watershed_beam.get(other_root, "tree") |> expect.to_be_ok()
  let other_tree =
    watershed_beam.resolve_tree(other_document, other_marker, view.view)
    |> expect.to_be_ok()
  watershed_beam.tree_merge(tree, other_tree, False) |> expect.to_be_error()
  process.send(other_actor, runtime_beam.Shutdown)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn actor_tree_echo_installs_state_before_next_command_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(handlers) {
        process.send(callbacks_subject, handlers)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
            callbacks.on_event(
              "op",
              frame.encode_operation_event([
                frame.Sequenced(
                  client_id: Some("reader"),
                  sequence_number: 1,
                  minimum_sequence_number: 0,
                  client_sequence_number: submitted.client_sequence_number,
                  reference_sequence_number: submitted.reference_sequence_number,
                  operation_type: submitted.operation_type,
                  contents: submitted.contents,
                  metadata: submitted.metadata,
                  timestamp: 0,
                  data: None,
                ),
              ]),
            )
          }

          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.auto_summarize(
    actor,
    Some(summary_policy.with_threshold(summary_policy.policy(), 1)),
  )
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["unknown"], tree_types.StringValue("bad")),
  )
  |> expect.to_be_error()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("native")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(submitted) = process.receive(submissions, 1000)
  let assert Ok(batch) =
    fluid_container.decode(submitted.contents, submitted.metadata)
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(range), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = batch.messages
  let assert Some(snapshot_compressor) = input.compressor
  range.session_id
  |> expect.to_not_equal(fluid_ids.local_session(snapshot_compressor))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  runtime_beam.is_synced(actor) |> expect.to_equal(True)
  process.send(actor, runtime_beam.MaybeSummarize)
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  callbacks.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader-2"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after reconnect")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(next) = process.receive(submissions, 1000)
  let assert Ok(next_batch) =
    fluid_container.decode(next.contents, next.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(next_range),
      0,
      _,
    ),
    _,
  ] = next_batch.messages
  next_range.session_id |> expect.to_equal(range.session_id)
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn commit_delivery_exit_invalidates_factory_and_replays_messages_test() {
  let #(actor, _, _) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let factories = process.new_subject()
  let started = process.new_subject()
  let releases = process.new_subject()
  let token =
    runtime_beam.subscribe_tree_commits(actor, "A/_C", fn(event) {
      let assert runtime_beam.TreeCommitEvent(_, True, Some(factory), Some(_)) =
        event
      let release = process.new_subject()
      process.send(factories, factory)
      process.send(releases, release)
      process.send(started, Nil)
      process.receive(release, 1000) |> expect.to_equal(Ok(Nil))
      process.kill(process.self())
    })

  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("native")),
  )
  |> expect.to_equal(Ok(Nil))
  let factory = process.receive(factories, 1000) |> expect.to_be_ok()
  let release = process.receive(releases, 1000) |> expect.to_be_ok()
  process.receive(started, 1000) |> expect.to_equal(Ok(Nil))
  let before = process.new_subject()
  let edit = process.new_subject()
  let after = process.new_subject()
  runtime_beam.unsubscribe(token)
  process.send(
    actor,
    runtime_beam.TreeRead(
      "A/_C",
      tree_types.DocumentCheckout,
      ["title"],
      before,
    ),
  )
  process.send(
    actor,
    runtime_beam.TreeEdit(
      "A/_C",
      tree_types.DocumentCheckout,
      tree_types.SetField(["title"], tree_types.StringValue("queued")),
      edit,
    ),
  )
  process.send(
    actor,
    runtime_beam.TreeRead("A/_C", tree_types.DocumentCheckout, ["title"], after),
  )
  process.send(release, Nil)
  process.receive(before, 1000)
  |> expect.to_equal(Ok(Ok(Some(tree_types.StringValue("native")))))
  process.receive(edit, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(after, 1000)
  |> expect.to_equal(Ok(Ok(Some(tree_types.StringValue("queued")))))
  factory() |> expect.to_be_error()
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn summary_reload_emits_no_historical_commit_factory_and_new_edit_does_test() {
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let factory_results = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: undo_acceptance.summary_reload_seed_after_undo(),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  let _ =
    runtime_beam.subscribe_tree_commits(actor, "A/_C", fn(event) {
      let runtime_beam.TreeCommitEvent(kind, local, factory, settlement) = event
      process.send(
        events,
        #(
          kind,
          local,
          case factory {
            Some(_) -> True
            None -> False
          },
          case settlement {
            Some(_) -> True
            None -> False
          },
        ),
      )
      process.send(factory_results, case factory {
        Some(factory) -> Some(factory())
        None -> None
      })
    })
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.receive(factory_results, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["note"], tree_types.StringValue("after reload")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(#(tree_types.DefaultCommit, True, True, True)))
  let assert Ok(Some(Ok(handle))) = process.receive(factory_results, 1000)
  runtime_beam.tree_revertible_status(handle)
  |> expect.to_equal(runtime_beam.RevertibleValid)
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.receive(factory_results, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn pending_tree_actor_retains_content_after_transport_loss_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(submissions, 1000) |> expect.to_be_ok()
  callbacks.on_close("transport lost")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.connection_observation(actor).pending_tree_count
  |> expect.to_equal(1)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"reader\""),
    ]),
  )
  let assert Ok(payload) = process.receive(submissions, 1000)
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation("reader-2", [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  submitted.reference_sequence_number |> expect.to_equal(2)
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("reader-2"),
        sequence_number: 3,
        minimum_sequence_number: 0,
        client_sequence_number: submitted.client_sequence_number,
        reference_sequence_number: submitted.reference_sequence_number,
        operation_type: submitted.operation_type,
        contents: submitted.contents,
        metadata: submitted.metadata,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  runtime_beam.connection_observation(actor).synced |> expect.to_equal(True)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn suspended_pending_tree_can_restart_reconnect_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))

  callbacks.on_fail("first failure")
  let assert Ok(first_retry) = process.receive(callbacks_subject, 1000)
  first_retry.on_fail("second failure")
  let assert Ok(second_retry) = process.receive(callbacks_subject, 1000)
  second_retry.on_fail("third failure")
  let assert Ok(third_retry) = process.receive(callbacks_subject, 1000)
  third_retry.on_fail("fourth failure")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("suspended")

  process.send(actor, runtime_beam.DropChannel)
  process.receive(callbacks_subject, 1000) |> expect.to_be_ok()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn suspended_reconnect_closes_live_transport_before_restart_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let closed = process.new_subject()
  let assert Ok(rejoined) = process.receive(connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { process.send(closed, Nil) },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("catching-up")

  process.send(actor, runtime_beam.ReconnectTimedOut("reader-2"))
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("suspended")
  process.send(actor, runtime_beam.DropChannel)

  process.receive(closed, 1000) |> expect.to_be_ok()
  process.receive(connections, 1000) |> expect.to_be_ok()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_tree_send_retains_candidate_and_refuses_more_edits_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            process.send(submissions, payload)
            Error("send refused")
          }
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(payload) = process.receive(submissions, 1000)
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  let assert Ok(batch) =
    fluid_container.decode(submitted.contents, submitted.metadata)
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(range), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = batch.messages
  let assert Some(snapshot_compressor) = input.compressor
  range.session_id
  |> expect.to_not_equal(fluid_ids.local_session(snapshot_compressor))
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_heartbeat_with_pending_tree_keeps_actor_and_core_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let sends = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "noop" -> {
            process.send(sends, event)
            Error("heartbeat send refused")
          }
          "submitOp" -> Ok(Nil)
          _ -> {
            process.send(sends, event)
            Ok(Nil)
          }
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000)
  |> expect.to_equal(Ok("connect_document"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Heartbeat)
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000) |> expect.to_equal(Ok("noop"))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("discarded")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  process.send(actor, runtime_beam.Put("A/root", "ignored", json.int(1)))
  process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
  process.send(actor, runtime_beam.SubmitPresence("presence", json.null()))
  process.send(actor, runtime_beam.Heartbeat)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        process.send(sends, event)
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_fail("late failure")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  process.receive(sends, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
fn failed_sibling_send_with_pending_tree(event: String) -> Nil {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let sends = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(pushed, payload) {
        let failed = case pushed, event {
          "submitSignal", "submitSignal" -> True
          "submitOp", "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            let assert Ok(batch) =
              fluid_container.decode(submitted.contents, submitted.metadata)
            case batch.messages {
              [
                fluid_container.ContainerMessage(
                  fluid_container.ChannelOperation(
                    fluid_container.Route("A", "root"),
                    _,
                  ),
                  _,
                  _,
                ),
                ..
              ] -> True
              _ -> False
            }
          }
          _, _ -> False
        }
        case failed {
          True -> {
            process.send(sends, pushed)
            Error("sibling send refused")
          }
          False -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  case event {
    "submitSignal" ->
      process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
    "submitOp" ->
      process.send(
        actor,
        runtime_beam.Put("A/root", "after", json.string("kept")),
      )
    _ -> panic as "invalid sibling send test event"
  }
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000) |> expect.to_equal(Ok(event))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  case event {
    "submitOp" ->
      process.call(actor, waiting: 1000, sending: fn(reply) {
        runtime_beam.GetValue("A/root", "after", reply)
      })
      |> expect.to_equal(Ok(json.string("kept")))
    _ -> Nil
  }
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  process.send(actor, runtime_beam.Put("A/root", "ignored", json.int(1)))
  process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
  process.send(actor, runtime_beam.Heartbeat)
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.receive(sends, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_map_send_with_pending_tree_retains_both_edits_test() {
  failed_sibling_send_with_pending_tree("submitOp")
}

@target(erlang)
pub fn failed_signal_with_pending_tree_retains_core_test() {
  failed_sibling_send_with_pending_tree("submitSignal")
}

@target(erlang)
pub fn bad_last_group_child_fails_without_notifying_beam_subscribers_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/root", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("A", "root"),
            wire_op.encode_map_operation(map_kernel.Set(
              "name",
              json.string("wrong"),
            )),
          ),
          0,
          None,
        ),
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          1,
          None,
        ),
      ]),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}
