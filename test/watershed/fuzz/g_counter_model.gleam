//// `KernelModel` for the grow-only counter kernel. It follows
//// `pn_counter_model` closely, with one difference: the kernel refuses a
//// negative amount, so the generator never produces one.
////
//// The generated operation is a slot-filling command: `gen_operation` leaves
//// `delta: None`, and `submit`/`apply_stashed` rewrite the operation with the
//// cumulative delta that the kernel computed at apply time.
////
//// ## Oracle soundness (independent of `merge`)
////
//// The oracle sums the sequenced operations' intent amounts. The merged value
//// of the kernel is the sum over replicas of the maximum cumulative count for
//// that replica. That equals the per-replica sum of amounts, and therefore the
//// oracle, if every sequenced delta for a replica is monotone and is computed
//// from a base that holds all of that replica's earlier deltas. The kernel
//// gives that by construction. It computes each delta from `optimistic`, the
//// order per client is first-in-first-out, and a rolled back operation never
//// reaches the log.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/g_counter.{type GCounter}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/g_counter_kernel.{type GCounterState, Increment, PendingDelta}

/// The generated operation. `delta` is a slot that `submit` and
/// `apply_stashed` fill. It is `None` until then, because an operation before
/// submission genuinely has no delta.
pub type GCommand {
  GCommand(amount: Int, delta: Option(GCounter))
}

/// Client identity is the harness index of the client, mapped to a stable
/// unique replica id.
fn client_replica_id(id: Int) -> ReplicaId {
  replica_id.new("client-" <> int.to_string(id))
}

/// `{"amount": Int, "delta": null | String}`. The delta is encoded twice, as a
/// JSON string that holds the lattice envelope, because lattice gives only a
/// string-based `from_json`.
fn operation_to_json(command: GCommand) -> json.Json {
  json.object([
    #("amount", json.int(command.amount)),
    #("delta", case command.delta {
      None -> json.null()
      Some(delta) -> json.string(json.to_string(g_counter.to_json(delta)))
    }),
  ])
}

fn operation_decoder() -> decode.Decoder(GCommand) {
  use amount <- decode.field("amount", decode.int)
  use delta <- decode.field(
    "delta",
    decode.optional(decode.string)
      |> decode.then(fn(maybe_encoded) {
        case maybe_encoded {
          None -> decode.success(None)
          Some(encoded) ->
            case g_counter.from_json(encoded) {
              Ok(delta) -> decode.success(Some(delta))
              Error(_) -> decode.failure(None, "GCounter")
            }
        }
      }),
  )
  decode.success(GCommand(amount, delta))
}

/// Small amounts that are never negative, so that shrinking stays useful and
/// the kernel never refuses a generated edit.
fn amount_from_int(n: Int) -> Int {
  n % 11
}

fn operation_generator() -> qcheck.Generator(GCommand) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { GCommand(amount_from_int(n), None) })
}

/// A routed operation must carry the delta that `submit` or `apply_stashed`
/// filled in. A `None` here is a fault in the model, not in the kernel.
fn command_to_kernel_operation(
  command: GCommand,
  context: String,
) -> g_counter_kernel.GCounterOperation {
  case command.delta {
    Some(delta) -> Increment(command.amount, delta)
    None ->
      panic as {
        context
        <> " received an op without a delta — submit/apply_stashed must rewrite ops before routing"
      }
  }
}

/// The generator makes only amounts that are not negative, so a refusal here
/// is a fault in the model.
fn expect_increment(
  state: GCounterState,
  amount: Int,
  context: String,
) -> #(GCounterState, g_counter_kernel.GCounterOperation) {
  case g_counter_kernel.increment(state, amount) {
    Ok(#(state, _events, operation, _message_id)) -> #(state, operation)
    Error(_) ->
      panic as { context <> " generated a negative amount for a g_counter" }
  }
}

/// Applies the edit optimistically, and rewrites the operation with the
/// cumulative delta that the kernel computed.
fn submit(
  state: GCounterState,
  command: GCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(GCounterState, Option(GCommand)) {
  let #(state, operation) = expect_increment(state, command.amount, "submit")
  let Increment(amount, delta) = operation
  #(state, Some(GCommand(amount, Some(delta))))
}

fn apply_remote(
  state: GCounterState,
  command: GCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(GCounterState, String) {
  let #(state, _events) =
    g_counter_kernel.apply_remote(
      state,
      command_to_kernel_operation(command, "apply_remote"),
    )
  Ok(state)
}

fn ack_local(
  state: GCounterState,
  command: GCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(GCounterState, String) {
  case
    g_counter_kernel.ack_local(
      state,
      command_to_kernel_operation(command, "ack_local"),
    )
  {
    Ok(state) -> Ok(state)
    Error(g_counter_kernel.UnexpectedAck(_, detail)) -> Error(detail)
    Error(g_counter_kernel.UnexpectedRollback(_, detail)) -> Error(detail)
  }
}

/// The sum of the sequenced intent amounts. The module doc explains why this
/// equals the merged value without any use of `merge`.
fn oracle(entries: List(LogEntry(GCommand))) -> Int {
  list.fold(kernel_fuzz.log_operations(entries), 0, fn(total, entry) {
    total + { entry.1 }.amount
  })
}

/// Rolls back the newest pending delta, with its message id taken from
/// `state.pending`. On a mismatch it leaves the state alone, so that a
/// regression shows up as a convergence failure and not as a panic.
fn rollback(state: GCounterState, command: GCommand) -> GCounterState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(PendingDelta(_, _, message_id)) ->
      case
        g_counter_kernel.rollback(
          state,
          command_to_kernel_operation(command, "rollback"),
          message_id,
        )
      {
        Ok(#(new_state, _events)) -> new_state
        Error(_) -> state
      }
  }
}

/// A generated stashed operation carries no delta, so build the next
/// cumulative one through the kernel's own edit path, and hand the rewritten
/// operation back for routing.
fn apply_stashed(
  state: GCounterState,
  command: GCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(GCounterState, GCommand) {
  let #(state, operation) =
    expect_increment(state, command.amount, "apply_stashed")
  let Increment(amount, delta) = operation
  #(state, GCommand(amount, Some(delta)))
}

/// A real summary round trip: encode to the JSON string that a stored summary
/// would hold, then load it under the identity of the joining client.
fn load_from_synced(state: GCounterState, id: Int) -> GCounterState {
  let summary_json = json.to_string(g_counter_kernel.summary(state))
  case g_counter_kernel.from_summary(summary_json, client_replica_id(id)) {
    Ok(loaded) -> loaded
    Error(_) ->
      panic as "load_from_synced could not decode the summary it just encoded"
  }
}

pub fn model() -> KernelModel(GCounterState, GCommand, Int) {
  KernelModel(
    name: "g_counter",
    init: fn(id) { g_counter_kernel.new(client_replica_id(id)) },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: g_counter_kernel.value,
    gen_operation: operation_generator(),
    check: Some(g_counter_kernel.check_cache_coherence),
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
