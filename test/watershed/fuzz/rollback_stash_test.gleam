//// Unit tests for `RollbackOp`/`StashedOp` (F3), gated on the model's
//// `rollback`/`apply_stashed` capabilities. Uses a toy model to prove the
//// harness degrades gracefully (hard error, no silent no-op) when a
//// capability is `None` — exactly `AddClient`'s F2 pattern — and uses the
//// real `counter_model` (backed by `counter_kernel.rollback`) for the F3
//// exit criterion: a mutation planted in the rollback capability must be
//// caught by the harness.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import watershed/counter_kernel.{Increment}
import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, ClientOp, KernelModel, RollbackOp, StashedOp,
  Synchronize,
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
    init: fn() { [] },
    submit: fn(state, op, _meta) { list.append(state, [op]) },
    apply_remote: fn(state, op, _meta) { list.append(state, [op]) },
    ack_local: fn(state, _op, _meta) { Ok(state) },
    observe: fn(state) { state },
    gen_op: qcheck.bounded_int(from: 0, to: 5),
    check: None,
    canonicalize: None,
    op_to_json: json.int,
    op_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: None,
      rollback: None,
      apply_stashed: None,
    ),
  )
}

pub fn rollback_op_errors_without_rollback_capability_test() {
  let script = [RollbackOp(1, 7)]
  expect_error(
    kernel_fuzz.try_run_script(model_without_capabilities(), 2, script),
    because: "expected RollbackOp to fail loudly without a rollback capability",
  )
}

pub fn stashed_op_errors_without_apply_stashed_capability_test() {
  let script = [StashedOp(1, 7)]
  expect_error(
    kernel_fuzz.try_run_script(model_without_capabilities(), 2, script),
    because: "expected StashedOp to fail loudly without an apply_stashed capability",
  )
}

/// Rolling back a counter increment must leave every client's observed
/// value exactly where it started: `RollbackOp` submits then rolls back
/// in one step, so it never reaches the inbox/server and its optimistic
/// effect must be fully undone.
pub fn counter_rollback_undoes_optimistic_increment_and_converges_test() {
  let script = [
    ClientOp(2, Increment(100)),
    Synchronize,
    RollbackOp(1, Increment(9)),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(counter_model.model(), 3, script))
}

/// A stashed op re-enters as pending/optimistic exactly like a fresh
/// `submit`, and still reaches the server and converges.
pub fn counter_stashed_op_converges_test() {
  let script = [StashedOp(1, Increment(4)), Synchronize]
  expect_ok(kernel_fuzz.try_run_script(counter_model.model(), 3, script))
}

/// F3 exit criterion: mutation check on `counter_kernel.rollback`. A
/// capability wrapper that (bug: swallows the rollback and leaves the
/// optimistic increment applied) stands in for a real regression in
/// `counter_kernel.rollback` — e.g. a sign flip or dropped pending-pop.
/// `RollbackOp` must expose the divergence via convergence, proving the
/// harness would catch such a mutation.
fn counter_model_with_broken_rollback() -> KernelModel(
  counter_kernel.CounterState,
  counter_kernel.CounterOp,
  Int,
) {
  let model = counter_model.model()
  KernelModel(
    ..model,
    capabilities: Capabilities(
      ..model.capabilities,
      // Bug: returns the post-submit (still-incremented) state untouched,
      // instead of undoing the optimistic increment.
      rollback: Some(fn(state, _op) { state }),
    ),
  )
}

pub fn broken_rollback_capability_is_caught_by_harness_test() {
  let script = [
    ClientOp(2, Increment(100)),
    Synchronize,
    RollbackOp(1, Increment(9)),
    Synchronize,
  ]
  expect_error(
    kernel_fuzz.try_run_script(counter_model_with_broken_rollback(), 3, script),
    because: "expected the planted rollback mutation to be caught by convergence",
  )
}
