import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed/tree/schema_builder as builder
import watershed/wire/fluid_container
import watershed/wire/fluid_document
import watershed_lustre/tree

type CallbackProblem {
  Stop
}

type WiderRoot {
  TextValue(String)
  NumberValue(Float)
}

type Msg {
  Performed(Result(Nil, tree_error.Error))
  TypedPerformed(Result(String, tree_error.Error))
  Created(Result(String, tree_error.Error))
  Opened(Result(shared_tree.Tree(Option(String)), tree_error.Error))
  ReadRoot(Result(Option(String), tree_error.Error))
  TreeSubscribed(Result(shared_tree.Subscription, tree_error.Error))
  Changed(shared_tree.ChangeEvent)
  Subscribed(Result(shared_tree.Subscription, tree_error.Error))
  Committed(Result(tree.CommitEvent, tree_error.Error))
  Settled(Result(shared_tree.CommitOutcome, tree_error.Error))
  TransactionCompleted(Result(Int, shared_tree.TransactionError(String)))
  TransactionTyped(Result(Int, shared_tree.TransactionError(tree_error.Error)))
  TransactionText(Result(String, shared_tree.TransactionError(CallbackProblem)))
}

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: shared_tree.Tree(Option(String)),
    definition: builder.Root(Option(String)),
    callbacks: runtime.TransportCallbacks,
    submissions: transport_js.Cell(List(json.Json)),
  )
}

pub fn open_rejects_invalid_declaration_and_defers_dispatch_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let declaration =
    builder.object0(builder.factory(""), "Invalid")
    |> builder.optional_root
  let pending =
    tree.open(fixture.document, declaration, fn(outcome) {
      case outcome {
        Error(reason) -> Performed(Error(reason))
        Ok(_) -> panic as "invalid schema opened"
      }
    })
  let assert [] = messages(sink)
  run(pending, sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error(tree_error.InvalidSchema(_)))] = messages(sink)
  let assert Ok(Some("initial")) = shared_tree.read_root(fixture.tree)
  let assert [] = transport_js.get_cell(fixture.submissions)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn create_dev_rejects_schema_and_defers_dispatch_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let declaration =
    builder.lazy(builder.factory("effects"), "Invalid", fn() {
      transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
      builder.array(builder.factory(""), "Invalid", builder.string())
    })
    |> builder.root
  let pending =
    tree.create_dev(
      "http://127.0.0.1:1",
      "tenant",
      "not-a-secret",
      declaration,
      [],
      Created,
    )
  let assert 0 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Created(Error(tree_error.InvalidSchema(_)))] = messages(sink)
  promise.resolve(Nil)
}

pub fn open_is_lazy_and_resolves_on_perform_test() -> Promise(Nil) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.open(fixture.document, fixture.definition, fn(outcome) {
      transport_js.set_cell(
        constructors,
        transport_js.get_cell(constructors) + 1,
      )
      Opened(outcome)
    })

  let assert 0 = transport_js.get_cell(constructors)
  watershed.close(fixture.document)
  run(pending, sink)
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Opened(Error(tree_error.ClosedRuntime))] = messages(sink)
  let assert 1 = transport_js.get_cell(constructors)
  promise.resolve(Nil)
}

pub fn read_root_reads_on_perform_and_dispatches_in_a_microtask_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.read_root(fixture.tree, fn(outcome) {
      transport_js.set_cell(
        constructors,
        transport_js.get_cell(constructors) + 1,
      )
      ReadRoot(outcome)
    })
  let assert 0 = transport_js.get_cell(constructors)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("latest"))
  run(pending, sink)
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  let assert Ok(Nil) =
    shared_tree.replace_root(fixture.tree, Some("after-perform"))
  use _ <- promise.await(promise.wait(0))
  let assert [ReadRoot(Ok(Some("latest")))] = messages(sink)
  let assert 1 = transport_js.get_cell(constructors)
  use _ <- promise.await(promise.wait(0))
  let assert [ReadRoot(Ok(Some("latest")))] = messages(sink)
  let assert 1 = transport_js.get_cell(constructors)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn observation_is_lazy_changes_only_and_defers_constructors_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.observe(fixture.tree, TreeSubscribed, fn(value) {
      transport_js.set_cell(
        constructors,
        transport_js.get_cell(constructors) + 1,
      )
      ReadRoot(value)
    })
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("before"))
  run(pending, sink)
  let assert [] = messages(sink)
  let assert 0 = transport_js.get_cell(constructors)
  use _ <- promise.await(promise.wait(0))
  let assert [TreeSubscribed(Ok(subscription))] = messages(sink)
  clear_messages(sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("after"))
  let assert [] = messages(sink)
  let assert 0 = transport_js.get_cell(constructors)
  use _ <- promise.await(promise.wait(0))
  let assert [ReadRoot(Ok(Some("after")))] = messages(sink)
  let assert 1 = transport_js.get_cell(constructors)
  clear_messages(sink)
  run(tree.unsubscribe(subscription), sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("ignored"))
  use _ <- promise.await(promise.wait(0))
  let assert [] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn disposal_is_lazy_deferred_and_does_not_close_the_document_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let assert Ok(other) =
    watershed.open_tree(fixture.document, fixture.definition)
  let sink = transport_js.new_cell([])
  let pending = tree.dispose(fixture.tree, Performed)
  let assert Ok(Some("initial")) = shared_tree.read_root(fixture.tree)
  run(pending, sink)
  let assert Error(tree_error.ClosedTree) = shared_tree.read_root(fixture.tree)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  let assert Ok(Some("initial")) = shared_tree.read_root(other)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn change_subscription_and_unsubscribe_are_lazy_and_deferred_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.subscribe_changes(
      fixture.tree,
      fn(token) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        TreeSubscribed(token)
      },
      fn(event) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Changed(event)
      },
    )
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("before"))
  run(pending, sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("after"))
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    TreeSubscribed(Ok(subscription)),
    Changed(shared_tree.TreeChanged(True)),
  ] = messages(sink)
  clear_messages(sink)

  let pending_unsubscribe = tree.unsubscribe(subscription)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("queued"))
  run(pending_unsubscribe, sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("ignored"))
  let assert 2 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Changed(shared_tree.TreeChanged(True))] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn commit_subscription_is_lazy_and_defers_captured_handles_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.subscribe_commits(
      fixture.tree,
      fn(token) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Subscribed(token)
      },
      fn(event) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Committed(event)
      },
      Settled,
    )

  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("before"))
  let assert [] = messages(sink)
  run(pending, sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("after"))
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Subscribed(Ok(_)),
    Committed(Ok(tree.CommitEvent(
      shared_tree.DefaultCommit,
      True,
      Some(revertible),
    ))),
  ] = messages(sink)
  let assert Ok(shared_tree.RevertibleValid) =
    shared_tree.revertible_status(revertible)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn commit_subscription_reports_default_undo_redo_and_settlement_test() -> Promise(
  Nil,
) {
  let fixture = fixture(True)
  let sink = transport_js.new_cell([])
  let constructors = transport_js.new_cell(0)
  run(
    tree.subscribe_commits(
      fixture.tree,
      Subscribed,
      fn(event) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Committed(event)
      },
      fn(outcome) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Settled(outcome)
      },
    ),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [Subscribed(Ok(subscription))] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("changed"))
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(
      shared_tree.DefaultCommit,
      True,
      Some(default_handle),
    ))),
    Settled(Ok(shared_tree.FullyApplied)),
  ] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) =
    shared_tree.revert(default_handle, shared_tree.KeepRevertible)
  let assert 2 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(
      shared_tree.UndoCommit,
      True,
      Some(undo_handle),
    ))),
    Settled(Ok(shared_tree.FullyApplied)),
  ] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) =
    shared_tree.revert(undo_handle, shared_tree.DisposeRevertible)
  let assert 4 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(
      shared_tree.RedoCommit,
      True,
      Some(redo_handle),
    ))),
    Settled(Ok(shared_tree.FullyApplied)),
  ] = messages(sink)
  let assert Ok(Nil) = shared_tree.dispose_revertible(default_handle)
  shared_tree.unsubscribe(subscription)
  watershed.close(fixture.document)
  let assert Ok(shared_tree.RevertibleDisposed) =
    shared_tree.revertible_status(redo_handle)
  promise.resolve(Nil)
}

pub fn commit_subscription_reports_remote_commits_without_handles_test() -> Promise(
  Nil,
) {
  let author =
    fixture_named("author", "30000000-0000-4000-8000-000000000003", False)
  let peer =
    fixture_named("peer", "50000000-0000-4000-8000-000000000005", False)
  let sink = transport_js.new_cell([])
  run(tree.subscribe_commits(peer.tree, Subscribed, Committed, Settled), sink)
  use _ <- promise.await(promise.wait(0))
  clear_messages(sink)

  let assert Ok(Nil) = shared_tree.replace_root(author.tree, Some("remote"))
  let assert [submitted] = transport_js.get_cell(author.submissions)
  peer.callbacks.on_event("op", acknowledgement(submitted) |> json.to_string)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(shared_tree.DefaultCommit, False, None))),
  ] = messages(sink)
  watershed.close(peer.document)
  watershed.close(author.document)
  promise.resolve(Nil)
}

pub fn commit_subscription_reports_factory_and_registration_errors_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, Subscribed, Committed, Settled),
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
      fixture.callbacks.on_event("op", invalid_operation(1) |> json.to_string)
      Nil
    })

  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("changed"))
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Committed(Error(_)), Settled(Error(_))] = messages(sink)
  shared_tree.unsubscribe(thief)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn commit_subscription_omits_factories_for_schema_commits_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let assert Ok(root) = watershed.resolve_root(fixture.document)
  let assert Ok(marker) = watershed.get(root, "tree")
  let upgraded_schema =
    builder.union([
      builder.variant(text_node(), TextValue, fn(value) {
        case value {
          TextValue(value) -> Some(value)
          NumberValue(_) -> None
        }
      }),
      builder.variant(builder.number(), NumberValue, fn(value) {
        case value {
          NumberValue(value) -> Some(value)
          TextValue(_) -> None
        }
      }),
    ])
    |> builder.optional_root
  let assert Ok(upgraded_tree) =
    watershed.inspect_tree(fixture.document, marker, upgraded_schema)
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, Subscribed, Committed, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [Subscribed(Ok(subscription))] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) = shared_tree.upgrade_schema(upgraded_tree)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(shared_tree.DefaultCommit, True, None))),
  ] = messages(sink)
  shared_tree.unsubscribe(subscription)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn unsubscribe_stops_future_commits_but_keeps_queued_messages_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, Subscribed, Committed, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  let assert [Subscribed(Ok(subscription))] = messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("queued"))
  run(tree.unsubscribe(subscription), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Committed(Ok(tree.CommitEvent(_, True, Some(_))))] =
    messages(sink)
  clear_messages(sink)

  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("ignored"))
  use _ <- promise.await(promise.wait(0))
  let assert [] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn revert_is_lazy_mutates_on_perform_and_defers_errors_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, Subscribed, Committed, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  clear_messages(sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("changed"))
  use _ <- promise.await(promise.wait(0))
  let assert [Committed(Ok(tree.CommitEvent(_, True, Some(revertible))))] =
    messages(sink)
  clear_messages(sink)

  let pending =
    tree.revert(revertible, shared_tree.DisposeRevertible, Performed)
  let assert Ok(Some("changed")) = shared_tree.read_root(fixture.tree)
  let assert Ok(shared_tree.RevertibleValid) =
    shared_tree.revertible_status(revertible)
  run(pending, sink)
  let assert Ok(Some("initial")) = shared_tree.read_root(fixture.tree)
  let assert Ok(shared_tree.RevertibleDisposed) =
    shared_tree.revertible_status(revertible)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Committed(Ok(tree.CommitEvent(shared_tree.UndoCommit, True, Some(_)))),
    Performed(Ok(Nil)),
  ] = messages(sink)
  clear_messages(sink)

  run(tree.revert(revertible, shared_tree.DisposeRevertible, Performed), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error(_))] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn dispose_revertible_is_lazy_deferred_and_idempotent_test() -> Promise(Nil) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.subscribe_commits(fixture.tree, Subscribed, Committed, Settled),
    sink,
  )
  use _ <- promise.await(promise.wait(0))
  clear_messages(sink)
  let assert Ok(Nil) = shared_tree.replace_root(fixture.tree, Some("changed"))
  use _ <- promise.await(promise.wait(0))
  let assert [Committed(Ok(tree.CommitEvent(_, True, Some(revertible))))] =
    messages(sink)
  clear_messages(sink)

  let pending = tree.dispose_revertible(revertible, Performed)
  let assert Ok(shared_tree.RevertibleValid) =
    shared_tree.revertible_status(revertible)
  run(pending, sink)
  let assert Ok(shared_tree.RevertibleDisposed) =
    shared_tree.revertible_status(revertible)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  clear_messages(sink)

  run(tree.dispose_revertible(revertible, Performed), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_runs_lazily_and_defers_the_typed_result_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let constructors = transport_js.new_cell(0)
  let pending =
    tree.transaction(
      fixture.tree,
      [],
      fn(_) {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        Ok(42)
      },
      fn(outcome) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        TransactionCompleted(outcome)
      },
    )

  let assert 0 = transport_js.get_cell(calls)
  let assert 0 = transport_js.get_cell(constructors)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Ok(42))] = messages(sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert 1 = transport_js.get_cell(constructors)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Ok(42))] = messages(sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert 1 = transport_js.get_cell(constructors)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_aborts_real_edits_and_preserves_callback_errors_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  run(
    tree.transaction(
      fixture.tree,
      [],
      fn(tree) {
        let assert Ok(Nil) = shared_tree.replace_root(tree, Some("temporary"))
        Error(Stop)
      },
      TransactionText,
    ),
    sink,
  )

  let assert Ok(Some("initial")) = shared_tree.read_root(fixture.tree)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionText(Error(shared_tree.Aborted(Stop)))] =
    messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_rejects_invalid_constraints_without_running_callback_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let assert Ok(Some(root)) = shared_tree.optional_root(fixture.tree)
  let assert Ok(Nil) =
    shared_tree.replace_root(fixture.tree, Some("replacement"))
  run(
    tree.transaction(
      fixture.tree,
      [shared_tree.node_in_document(root)],
      fn(_) {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        Ok(1)
      },
      TransactionCompleted,
    ),
    sink,
  )

  let assert 0 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionCompleted(Error(shared_tree.TransactionFailed(_)))] =
    messages(sink)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn transaction_composes_two_real_edits_into_one_commit_test() -> Promise(
  Nil,
) {
  let fixture = fixture(False)
  let sink = transport_js.new_cell([])
  let commits = transport_js.new_cell(0)
  let assert Ok(subscription) =
    shared_tree.subscribe_commits(fixture.tree, fn(_) {
      transport_js.set_cell(commits, transport_js.get_cell(commits) + 1)
    })
  run(
    tree.transaction(
      fixture.tree,
      [],
      fn(tree) {
        use _ <- result.try(shared_tree.replace_root(tree, Some("first")))
        use _ <- result.try(shared_tree.replace_root(tree, Some("second")))
        Ok(7)
      },
      TransactionTyped,
    ),
    sink,
  )

  let assert 1 = transport_js.get_cell(commits)
  let assert [_] = transport_js.get_cell(fixture.submissions)
  let assert Ok(Some("second")) = shared_tree.read_root(fixture.tree)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TransactionTyped(Ok(7))] = messages(sink)
  shared_tree.unsubscribe(subscription)
  watershed.close(fixture.document)
  promise.resolve(Nil)
}

pub fn perform_runs_lazily_and_defers_the_outcome_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let operation = fn() {
    transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
    Ok(Nil)
  }
  let pending = tree.perform(operation, Performed)
  let assert 0 = transport_js.get_cell(calls)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  promise.resolve(Nil)
}

pub fn perform_preserves_errors_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  run(
    tree.perform(
      fn() { Error(tree_error.RuntimeFailure("refused")) },
      Performed,
    ),
    sink,
  )
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error(tree_error.RuntimeFailure("refused")))] =
    messages(sink)
  promise.resolve(Nil)
}

pub fn typed_perform_is_lazy_and_dispatches_once_test() -> Promise(Nil) {
  let calls = transport_js.new_cell(0)
  let sink = transport_js.new_cell([])
  let pending =
    tree.perform(
      fn() {
        transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
        Ok("read")
      },
      TypedPerformed,
    )
  let assert 0 = transport_js.get_cell(calls)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [TypedPerformed(Ok("read"))] = messages(sink)
  let assert 1 = transport_js.get_cell(calls)
  promise.resolve(Nil)
}

pub fn create_preserves_invalid_configuration_and_defers_dispatch_test() -> Promise(
  Nil,
) {
  let calls = transport_js.new_cell(0)
  let constructors = transport_js.new_cell(0)
  let compiled = counting_declaration(calls)
  let sink = transport_js.new_cell([])
  let pending =
    tree.create(
      container.CreateConfig("ftp://invalid", "dev-tenant", "token"),
      compiled,
      "initial",
      fn(outcome) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Created(outcome)
      },
    )
  let assert 0 = transport_js.get_cell(calls)
  let assert 0 = transport_js.get_cell(constructors)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Created(Error(tree_error.CreationFailed(container.InvalidConfiguration(
      detail,
    )))),
  ] = messages(sink)
  let assert True = detail != ""
  let assert 1 = transport_js.get_cell(constructors)
  promise.resolve(Nil)
}

pub fn create_dev_is_lazy_and_defers_dispatch_test() -> Promise(Nil) {
  let calls = transport_js.new_cell(0)
  let constructors = transport_js.new_cell(0)
  let sink = transport_js.new_cell([])
  let pending =
    tree.create_dev(
      "ftp://invalid",
      "dev-tenant",
      "secret",
      counting_declaration(calls),
      "initial",
      fn(outcome) {
        transport_js.set_cell(
          constructors,
          transport_js.get_cell(constructors) + 1,
        )
        Created(outcome)
      },
    )
  let assert 0 = transport_js.get_cell(calls)
  let assert 0 = transport_js.get_cell(constructors)
  run(pending, sink)
  let assert 0 = transport_js.get_cell(constructors)
  let assert [] = messages(sink)
  use completed <- promise.await(
    wait_until(100, fn() {
      transport_js.get_cell(constructors) == 1 && messages(sink) != []
    }),
  )
  let assert True = completed
  let assert 1 = transport_js.get_cell(calls)
  let assert [
    Created(Error(tree_error.CreationFailed(container.InvalidConfiguration(_)))),
  ] = messages(sink)
  let assert 1 = transport_js.get_cell(constructors)
  promise.resolve(Nil)
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

fn wait_until(attempts: Int, check: fn() -> Bool) -> Promise(Bool) {
  case check(), attempts <= 0 {
    True, _ -> promise.resolve(True)
    False, True -> promise.resolve(False)
    False, False -> {
      use _ <- promise.await(promise.wait(0))
      wait_until(attempts - 1, check)
    }
  }
}

fn clear_messages(sink: transport_js.Cell(List(Msg))) -> Nil {
  transport_js.set_cell(sink, [])
}

fn fixture(inline_ack: Bool) -> Fixture(root) {
  fixture_named("reader", "30000000-0000-4000-8000-000000000003", inline_ack)
}

fn fixture_named(
  user_id: String,
  session_id: String,
  inline_ack: Bool,
) -> Fixture(root) {
  let definition = text_definition()
  let assert Ok(compiled) = builder.compile(definition)
  let stored = builder.stored(compiled)
  let assert Ok(session) = fluid_ids.session_id(session_id)
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(initial_root) = builder.encode_new(compiled, Some("initial"))
  let assert Ok(summary) =
    fluid_document.initial_tree(stored, initial_root, session, view_id)
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks: transport_js.Cell(Option(runtime.TransportCallbacks)) =
    transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: user_id,
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event, inline_ack {
              "submitOp", True ->
                handlers.on_event(
                  "op",
                  acknowledgement(payload) |> json.to_string,
                )
              "submitOp", False ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
              _, _ -> Nil
            }
          },
          close: fn() { Nil },
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
      client_id: user_id,
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: [user_id],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Ok(root) = watershed.resolve_root(document)
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(tree) = watershed.resolve_tree(document, marker, definition)
  Fixture(document:, tree:, definition:, callbacks:, submissions:)
}

fn counting_declaration(calls: transport_js.Cell(Int)) -> builder.Root(String) {
  let property =
    builder.required("value", builder.string(), fn(value: String) {
      transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
      value
    })
  builder.object1(
    builder.factory("effects"),
    "Created",
    fn(value) { value },
    property,
  )
  |> builder.root
}

fn text_node() -> builder.Node(String) {
  builder.object1(
    builder.factory("effects"),
    "Text",
    fn(value) { value },
    builder.required("value", builder.string(), fn(value: String) { value }),
  )
}

fn text_definition() -> builder.Root(Option(String)) {
  text_node() |> builder.optional_root
}

fn acknowledgement(payload: json.Json) -> json.Json {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  frame.encode_operation_event([
    frame.Sequenced(
      client_id: Some(sender),
      sequence_number: submitted.client_sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: submitted.client_sequence_number,
      reference_sequence_number: submitted.reference_sequence_number,
      operation_type: submitted.operation_type,
      contents: submitted.contents,
      metadata: submitted.metadata,
      timestamp: 0,
      data: None,
      compression: None,
    ),
  ])
}

fn invalid_operation(sequence_number: Int) -> json.Json {
  let assert Ok(contents) =
    fluid_container.DecodedBatch(True, None, [
      fluid_container.ContainerMessage(
        fluid_container.ChannelOperation(
          fluid_container.Route("missing", "root"),
          json.null(),
        ),
        0,
        None,
      ),
    ])
    |> fluid_container.encode_batch
  frame.encode_operation_event([
    frame.Sequenced(
      client_id: Some("other"),
      sequence_number: sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: sequence_number,
      reference_sequence_number: 0,
      operation_type: "op",
      contents: contents,
      metadata: None,
      timestamp: 0,
      data: None,
      compression: None,
    ),
  ])
}
