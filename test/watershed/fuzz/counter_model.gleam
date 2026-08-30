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
  type CounterOperation, type CounterState, Increment, PendingIncrement,
}
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}

/// `CounterOperation` has one constructor wrapping one `Int`, so the JSON shape
/// is just that int — no tag needed since `kernel_fuzz`'s `Command` wrapper
/// already tags at the command level.
fn operation_to_json(operation: CounterOperation) -> json.Json {
  case operation {
    Increment(amount) -> json.int(amount)
  }
}

fn operation_decoder() -> decode.Decoder(CounterOperation) {
  decode.map(decode.int, Increment)
}

/// Small integer amounts, same range as the existing property test, so
/// shrinking stays effective.
fn amount_from_int(n: Int) -> Int {
  n % 21 - 10
}

fn operation_generator() -> qcheck.Generator(CounterOperation) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { Increment(amount_from_int(n)) })
}

fn submit(
  state: CounterState,
  operation: CounterOperation,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(CounterState, option.Option(CounterOperation)) {
  case operation {
    Increment(amount) -> {
      let #(state, _, _, _) = counter_kernel.increment(state, amount)
      #(state, Some(operation))
    }
  }
}

fn apply_remote(
  state: CounterState,
  operation: CounterOperation,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(CounterState, String) {
  let #(state, _) = counter_kernel.apply_remote(state, operation)
  Ok(state)
}

fn ack_local(
  state: CounterState,
  operation: CounterOperation,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(CounterState, String) {
  case counter_kernel.ack_local(state, operation) {
    Ok(state) -> Ok(state)
    Error(counter_kernel.UnexpectedAck(_, detail)) -> Error(detail)
    Error(counter_kernel.UnexpectedRollback(_, detail)) -> Error(detail)
  }
}

fn oracle(entries: List(LogEntry(CounterOperation))) -> Int {
  list.fold(kernel_fuzz.log_operations(entries), 0, fn(total, item) {
    case item.1 {
      Increment(amount) -> total + amount
    }
  })
}

/// Rolls back the newest pending increment, using its message id from
/// `state.pending` (local-only bookkeeping the harness doesn't otherwise
/// track). On mismatch (should not happen given the harness's own
/// bookkeeping — see `rollback_operation` in `kernel_fuzz`) leaves state
/// untouched, so a real regression here surfaces as a convergence failure
/// rather than a harness panic.
fn rollback(state: CounterState, operation: CounterOperation) -> CounterState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(PendingIncrement(_, message_id)) ->
      case counter_kernel.rollback(state, operation, message_id) {
        Ok(#(new_state, _events)) -> new_state
        Error(_) -> state
      }
  }
}

/// Re-applies a stashed operation through `increment`'s path, becoming pending
/// and optimistically visible again — mirrors reconnect-time stash replay. The
/// routed operation is the generated one unchanged (counter operations carry no
/// apply-time-computed content).
fn apply_stashed(
  state: CounterState,
  operation: CounterOperation,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(CounterState, CounterOperation) {
  let #(state, _, _, _) =
    counter_kernel.apply_stashed_operation(state, operation)
  #(state, operation)
}

fn load_from_synced(state: CounterState, _id: Int) -> CounterState {
  counter_kernel.from_summary(counter_kernel.summary_value(state))
}

pub fn model() -> KernelModel(CounterState, CounterOperation, Int) {
  KernelModel(
    name: "counter",
    init: fn(_id) { counter_kernel.new() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: fn(state) { state.value },
    gen_operation: operation_generator(),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    operation_to_json: operation_to_json,
    operation_decoder: operation_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
