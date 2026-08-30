//// Unit tests for `RollbackOperation`/`StashedOperation` (F3), gated on the
//// model's `rollback`/`apply_stashed` capabilities. Uses a toy model to prove
//// the harness degrades gracefully (hard error, no silent no-operation) when a
//// capability is `None` — exactly `AddClient`'s F2 pattern — and uses the real
//// `counter_model` (backed by `counter_kernel.rollback`) for the F3 exit
//// criterion: a mutation planted in the rollback capability must be caught by
//// the harness.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import watershed/counter_kernel.{Increment}
import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, ClientOperation, KernelModel,
  RollbackOperation, StashedOperation, Synchronize,
}

fn expect_ok(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn expect_error(result: Result(Nil, String), because message: String) -> Nil {
  case result {
    Error(_) -> Nil
    Ok(_) -> panic as message
  }
}

/// Toy ordered-log model, same shape as `add_client_test`'s, with no
/// rollback/apply_stashed capability — the "map today" case.
fn model_without_capabilities() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    name: "toy-ordered-log",
    init: fn(_id) { [] },
    submit: fn(state, operation, _meta) {
      #(list.append(state, [operation]), Some(operation))
    },
    apply_remote: fn(state, operation, _meta) {
      Ok(list.append(state, [operation]))
    },
    ack_local: fn(state, _operation, _meta) { Ok(state) },
    observe: fn(state) { state },
    gen_operation: qcheck.bounded_int(from: 0, to: 5),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    operation_to_json: json.int,
    operation_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: None,
      rollback: None,
      resubmit: None,
      apply_stashed: None,
      react: None,
      remove_member: None,
    ),
  )
}

pub fn rollback_operation_errors_without_rollback_capability_test() -> Nil {
  let script = [RollbackOperation(1, 7)]
  expect_error(
    kernel_fuzz.try_run_script(model_without_capabilities(), 2, script),
    because: "expected RollbackOp to fail loudly without a rollback capability",
  )
}

pub fn stashed_operation_errors_without_apply_stashed_capability_test() -> Nil {
  let script = [StashedOperation(1, 7)]
  expect_error(
    kernel_fuzz.try_run_script(model_without_capabilities(), 2, script),
    because: "expected StashedOp to fail loudly without an apply_stashed capability",
  )
}

/// PN0/H2: `apply_stashed` rewrites the routed operation (`operation + 1000`),
/// standing in for a kernel whose wire operations carry apply-time-computed
/// content (a pn_counter delta). The applying client records the rewritten
/// operation, so the script converges only if the harness routes the *returned*
/// operation to the inbox — routing the generated one leaves peers with
/// `operation` while the author holds `operation + 1000`. The oracle
/// additionally pins the log itself to the rewritten operation.
fn rewriting_stash_model() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    ..model_without_capabilities(),
    name: "toy-stash-rewrite",
    capabilities: Capabilities(
      ..model_without_capabilities().capabilities,
      oracle: Some(fn(entries) {
        list.map(kernel_fuzz.log_operations(entries), fn(entry) { entry.1 })
      }),
      resubmit: None,
      apply_stashed: Some(fn(state, operation, _meta) {
        let rewritten = operation + 1000
        #(list.append(state, [rewritten]), rewritten)
      }),
    ),
  )
}

pub fn stashed_operation_routes_the_rewritten_operation_test() -> Nil {
  let script = [StashedOperation(0, 5), Synchronize]
  expect_ok(kernel_fuzz.try_run_script(rewriting_stash_model(), 3, script))
}

fn apply_stashed_recording_meta(
  state: List(Int),
  operation: Int,
  meta: kernel_fuzz.SubmitMeta,
) -> #(List(Int), Int) {
  #(list.append(state, [meta.last_seen_seq]), operation)
}

/// H3: `apply_stashed` gets the submitting client's delivered cursor, same
/// as `submit`. The stash handler records that meta in local state but routes
/// the generated operation unchanged; passing the wrong cursor would diverge
/// from peers, which apply the routed operation.
fn stash_meta_model() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    ..model_without_capabilities(),
    name: "toy-stash-meta",
    capabilities: Capabilities(
      ..model_without_capabilities().capabilities,
      oracle: Some(fn(entries) {
        list.map(kernel_fuzz.log_operations(entries), fn(entry) { entry.1 })
      }),
      resubmit: None,
      apply_stashed: Some(apply_stashed_recording_meta),
    ),
  )
}

pub fn stashed_operation_receives_submit_meta_test() -> Nil {
  let script = [
    ClientOperation(0, 10),
    Synchronize,
    StashedOperation(1, 1),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(stash_meta_model(), 3, script))
}

/// Rolling back a counter increment must leave every client's observed
/// value exactly where it started: `RollbackOperation` submits then rolls back
/// in one step, so it never reaches the inbox/server and its optimistic
/// effect must be fully undone.
pub fn counter_rollback_undoes_optimistic_increment_and_converges_test() -> Nil {
  let script = [
    ClientOperation(2, Increment(100)),
    Synchronize,
    RollbackOperation(1, Increment(9)),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(counter_model.model(), 3, script))
}

/// A stashed operation re-enters as pending/optimistic exactly like a fresh
/// `submit`, and still reaches the server and converges.
pub fn counter_stashed_operation_converges_test() -> Nil {
  let script = [StashedOperation(1, Increment(4)), Synchronize]
  expect_ok(kernel_fuzz.try_run_script(counter_model.model(), 3, script))
}

/// F3 exit criterion: mutation check on `counter_kernel.rollback`. A
/// capability wrapper that (bug: swallows the rollback and leaves the
/// optimistic increment applied) stands in for a real regression in
/// `counter_kernel.rollback` — e.g. a sign flip or dropped pending-pop.
/// `RollbackOperation` must expose the divergence via convergence, proving the
/// harness would catch such a mutation.
fn counter_model_with_broken_rollback() -> KernelModel(
  counter_kernel.CounterState,
  counter_kernel.CounterOperation,
  Int,
) {
  let model = counter_model.model()
  KernelModel(
    ..model,
    capabilities: Capabilities(
      ..model.capabilities,
      // Bug: returns the post-submit (still-incremented) state untouched,
      // instead of undoing the optimistic increment.
      rollback: Some(fn(state, _operation) { state }),
    ),
  )
}

pub fn broken_rollback_capability_is_caught_by_harness_test() -> Nil {
  let script = [
    ClientOperation(2, Increment(100)),
    Synchronize,
    RollbackOperation(1, Increment(9)),
    Synchronize,
  ]
  expect_error(
    kernel_fuzz.try_run_script(counter_model_with_broken_rollback(), 3, script),
    because: "expected the planted rollback mutation to be caught by convergence",
  )
}
