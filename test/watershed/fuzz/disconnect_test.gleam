//// Unit tests for `Disconnect`/`Reconnect` (F3), using a toy model instead
//// of counter/map so failures here point at the harness, not at a
//// production kernel. Proves: (1) a disconnected client's in-flight inbox
//// entry moves to its resend queue and never reaches the log, (2) an
//// already-sequenced op stays in the log across a disconnect, (3)
//// `Reconnect` resubmits the resend queue to the inbox in order, and (4)
//// the F3 exit criterion — a schedule that disconnects mid-pending-window
//// and reconnects converges.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import watershed/counter_kernel.{Increment}
import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, ClientOp, Disconnect, KernelModel, Reconnect,
  Sequence, Synchronize,
}

/// State is an ordered log of ints applied so far (local or remote),
/// mirroring `add_client_test`'s toy model.
fn ordered_log_model() -> KernelModel(List(Int), Int, List(Int)) {
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
      load_from_synced: Some(fn(state) { state }),
      oracle: None,
      rollback: None,
      apply_stashed: None,
    ),
  )
}

fn expect_ok(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

/// A client disconnected while its op is still in the inbox (never
/// sequenced) must not have that op reach the log: with only client 1
/// authoring, if the op leaked into the log, client 2 would observe it via
/// `Synchronize` and diverge from client 1, which stays disconnected and
/// legitimately excluded from convergence.
pub fn disconnect_moves_inflight_inbox_entry_to_resend_test() {
  let script = [
    ClientOp(1, 10),
    Disconnect(1),
    // Nothing left in the inbox for anyone to sequence: client 2 should see
    // an empty log at the next Synchronize.
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(ordered_log_model(), 3, script))
}

/// An op that already made it into the log before the disconnect must stay
/// there — the disconnect only intercepts the inbox, not the log.
pub fn disconnect_does_not_unsequence_already_sequenced_ops_test() {
  let script = [
    ClientOp(1, 10),
    Sequence(1),
    Disconnect(1),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(ordered_log_model(), 3, script))
}

/// The F3 exit criterion: disconnect mid-pending-window (op submitted, not
/// yet sequenced), let other client traffic sequence and deliver while
/// disconnected, then reconnect — the resend queue must resubmit in order
/// and the whole simulation must converge. Uses `counter_model` (real
/// `counter_kernel`, sum is commutative) rather than the ordered-log toy
/// model: with two clients authoring concurrently, an order-sensitive toy
/// model would need real rebase/pending semantics to stay consistent
/// (exactly what `map_model`'s `check` hook exists for), which is out of
/// scope for this harness-only property.
pub fn disconnect_mid_pending_window_then_reconnect_converges_test() {
  let script = [
    ClientOp(1, Increment(1)),
    ClientOp(1, Increment(2)),
    // Disconnect while both increments are still sitting in the inbox.
    Disconnect(1),
    ClientOp(2, Increment(3)),
    Synchronize,
    Reconnect(1),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(counter_model.model(), 3, script))
}

/// Reconnect must resubmit the resend queue in the original order — reusing
/// the insertion-order toy model, a reordering bug is directly observable.
pub fn reconnect_resubmits_resend_queue_in_order_test() {
  let script = [
    ClientOp(1, 1),
    ClientOp(1, 2),
    ClientOp(1, 3),
    Disconnect(1),
    Reconnect(1),
    Synchronize,
  ]
  expect_ok(kernel_fuzz.try_run_script(ordered_log_model(), 3, script))
}

/// A disconnected client is legitimately excluded from convergence and must
/// not be compared against connected clients.
pub fn disconnected_client_excluded_from_convergence_test() {
  let script = [ClientOp(1, 10), Disconnect(1), Synchronize]
  // Client 1 still privately observes its own optimistic op even though it
  // never reached the server; that must not fail convergence.
  expect_ok(kernel_fuzz.try_run_script(ordered_log_model(), 3, script))
}
