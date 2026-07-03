//// `KernelModel` for the counter kernel: the oracle is the sum of every
//// sequenced increment, which the kernel itself computes incrementally
//// (`apply_remote`/`ack_local`), giving an independent check that
//// convergence landed on the *correct* value, not just the same one.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import watershed/counter_kernel.{
  type CounterOp, type CounterState, Increment, PendingIncrement,
}
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}

/// `CounterOp` has one constructor wrapping one `Int`, so the JSON shape is
/// just that int — no tag needed since `kernel_fuzz`'s `Command` wrapper
/// already tags at the command level.
fn op_to_json(op: CounterOp) -> json.Json {
  case op {
    Increment(amount) -> json.int(amount)
  }
}

fn op_decoder() -> decode.Decoder(CounterOp) {
  decode.map(decode.int, Increment)
}

/// Small integer amounts, same range as the existing property test, so
/// shrinking stays effective.
fn amount_from_int(n: Int) -> Int {
  n % 21 - 10
}

fn op_generator() -> qcheck.Generator(CounterOp) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { Increment(amount_from_int(n)) })
}

fn submit(
  state: CounterState,
  op: CounterOp,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(CounterState, option.Option(CounterOp)) {
  case op {
    Increment(amount) -> {
      let #(state, _, _, _) = counter_kernel.increment(state, amount)
      #(state, Some(op))
    }
  }
}

fn apply_remote(
  state: CounterState,
  op: CounterOp,
  _meta: kernel_fuzz.SequencedMeta,
) -> CounterState {
  let #(state, _) = counter_kernel.apply_remote(state, op)
  state
}

fn ack_local(
  state: CounterState,
  op: CounterOp,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(CounterState, String) {
  case counter_kernel.ack_local(state, op) {
    Ok(state) -> Ok(state)
    Error(counter_kernel.UnexpectedAck(_, detail)) -> Error(detail)
    Error(counter_kernel.UnexpectedRollback(_, detail)) -> Error(detail)
  }
}

fn oracle(log: List(#(Int, CounterOp))) -> Int {
  list.fold(log, 0, fn(total, item) {
    case item.1 {
      Increment(amount) -> total + amount
    }
  })
}

/// Rolls back the newest pending increment, using its message id from
/// `state.pending` (local-only bookkeeping the harness doesn't otherwise
/// track). On mismatch (should not happen given the harness's own
/// bookkeeping — see `rollback_op` in `kernel_fuzz`) leaves state
/// untouched, so a real regression here surfaces as a convergence failure
/// rather than a harness panic.
fn rollback(state: CounterState, op: CounterOp) -> CounterState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(PendingIncrement(_, message_id)) ->
      case counter_kernel.rollback(state, op, message_id) {
        Ok(#(new_state, _events)) -> new_state
        Error(_) -> state
      }
  }
}

/// Re-applies a stashed op through `increment`'s path, becoming pending and
/// optimistically visible again — mirrors reconnect-time stash replay. The
/// routed op is the generated one unchanged (counter ops carry no
/// apply-time-computed content).
fn apply_stashed(
  state: CounterState,
  op: CounterOp,
) -> #(CounterState, CounterOp) {
  let #(state, _, _, _) = counter_kernel.apply_stashed_op(state, op)
  #(state, op)
}

fn load_from_synced(state: CounterState, _id: Int) -> CounterState {
  counter_kernel.from_summary(counter_kernel.summary_value(state))
}

pub fn model() -> KernelModel(CounterState, CounterOp, Int) {
  KernelModel(
    name: "counter",
    init: fn(_id) { counter_kernel.new() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: fn(state) { state.value },
    gen_op: op_generator(),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      apply_stashed: Some(apply_stashed),
    ),
  )
}
