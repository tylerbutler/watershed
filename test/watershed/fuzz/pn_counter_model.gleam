//// `KernelModel` for the PN-counter kernel — the first lattice-backed
//// (delta-CRDT) model, and the reason the harness threads client identity
//// (H1): `init` maps the harness index to a unique `ReplicaId`, without
//// which concurrent updates from two clients would max-merge onto one
//// replica key and silently lose increments.
////
//// The generated op is a claims-style slot-filling command: `gen_op` leaves
//// `delta: None`, and `submit`/`apply_stashed` rewrite the op with the
//// cumulative delta the kernel computed at apply time (H2 exists so the
//// stash path can hand that rewrite back for routing).
////
//// ## Oracle soundness (independent of `merge`)
////
//// The oracle sums the sequenced ops' intent *amounts*. The kernel's merged
//// value is Σ over replicas of (max cumulative positive − max cumulative
//// negative), which equals the per-replica amount sums — and hence the
//// oracle — provided every sequenced delta's cumulative count is monotone
//// per replica half and computed off a base containing all of that
//// replica's prior sequenced-or-pending deltas. That holds by construction:
//// `update` computes deltas off `optimistic` inside the kernel, per-client
//// op order is FIFO through inbox → resend → log, and rolled-back ops never
//// reach the log (the rollback recompute rebases the next cumulative
//// correctly, so a rollback never breaks monotonicity of *routed* deltas).

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/pn_counter_kernel.{type PnCounterState, PendingDelta, Update}

/// The generated op. `delta` is a slot filled by `submit`/`apply_stashed`
/// (`None` until then): pre-submit ops genuinely have no delta, and a bogus
/// placeholder delta would be a live footgun under merge, unlike a bogus
/// int.
pub type PnCommand {
  PnCommand(amount: Int, delta: Option(PNCounter))
}

/// Client identity is the harness's `Int` index (H1), mapped to a stable
/// unique replica id. Joiner indices from `AddClient` are fresh and never
/// reused, so ids never collide.
fn client_replica_id(id: Int) -> ReplicaId {
  replica_id.new("client-" <> int.to_string(id))
}

/// `{"amount": Int, "delta": null | String}`. The delta is double-encoded
/// (a JSON string holding the lattice envelope) because lattice exposes
/// only string-based `from_json`, no composable `decode.Decoder(PNCounter)`.
/// Dumped scripts mostly contain pre-submit ops (`delta: null`), but
/// replayed `StashedOp`/`RollbackOp` fixtures must round-trip totally.
fn op_to_json(cmd: PnCommand) -> json.Json {
  json.object([
    #("amount", json.int(cmd.amount)),
    #("delta", case cmd.delta {
      None -> json.null()
      Some(delta) -> json.string(json.to_string(pn_counter.to_json(delta)))
    }),
  ])
}

fn op_decoder() -> decode.Decoder(PnCommand) {
  use amount <- decode.field("amount", decode.int)
  use delta <- decode.field(
    "delta",
    decode.optional(decode.string)
      |> decode.then(fn(maybe_encoded) {
        case maybe_encoded {
          None -> decode.success(None)
          Some(encoded) ->
            case pn_counter.from_json(encoded) {
              Ok(delta) -> decode.success(Some(delta))
              Error(_) -> decode.failure(None, "PNCounter")
            }
        }
      }),
  )
  decode.success(PnCommand(amount, delta))
}

/// Small signed amounts, counter parity, so shrinking stays effective.
fn amount_from_int(n: Int) -> Int {
  n % 21 - 10
}

fn op_generator() -> qcheck.Generator(PnCommand) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { PnCommand(amount_from_int(n), None) })
}

/// A routed op must carry the delta `submit`/`apply_stashed` filled in; a
/// `None` here is a model wiring bug, not a kernel bug — fail loudly.
fn to_kernel_op(
  cmd: PnCommand,
  context: String,
) -> pn_counter_kernel.PnCounterOp {
  case cmd.delta {
    Some(delta) -> Update(cmd.amount, delta)
    None ->
      panic as {
        context
        <> " received an op without a delta — submit/apply_stashed must rewrite ops before routing"
      }
  }
}

/// Applies optimistically and rewrites the op with the kernel-computed
/// cumulative delta (claims precedent). Never returns `None`.
fn submit(
  state: PnCounterState,
  cmd: PnCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(PnCounterState, Option(PnCommand)) {
  let #(state, _events, op, _message_id) =
    pn_counter_kernel.update(state, cmd.amount)
  let Update(amount, delta) = op
  #(state, Some(PnCommand(amount, Some(delta))))
}

fn apply_remote(
  state: PnCounterState,
  cmd: PnCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(PnCounterState, String) {
  let #(state, _events) =
    pn_counter_kernel.apply_remote(state, to_kernel_op(cmd, "apply_remote"))
  Ok(state)
}

fn ack_local(
  state: PnCounterState,
  cmd: PnCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(PnCounterState, String) {
  case pn_counter_kernel.ack_local(state, to_kernel_op(cmd, "ack_local")) {
    Ok(state) -> Ok(state)
    Error(pn_counter_kernel.UnexpectedAck(_, detail)) -> Error(detail)
    Error(pn_counter_kernel.UnexpectedRollback(_, detail)) -> Error(detail)
  }
}

/// Sum of sequenced intent amounts — see the module doc for why this equals
/// the merged CRDT value without touching `merge`.
fn oracle(entries: List(LogEntry(PnCommand))) -> Int {
  list.fold(kernel_fuzz.log_ops(entries), 0, fn(total, entry) {
    total + { entry.1 }.amount
  })
}

/// Rolls back the newest pending delta, using its message id from
/// `state.pending` (local-only bookkeeping the harness doesn't track). On
/// mismatch leaves state untouched, so a regression surfaces as a
/// convergence failure rather than a harness panic.
fn rollback(state: PnCounterState, cmd: PnCommand) -> PnCounterState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(PendingDelta(_, _, message_id)) ->
      case
        pn_counter_kernel.rollback(
          state,
          to_kernel_op(cmd, "rollback"),
          message_id,
        )
      {
        Ok(#(new_state, _events)) -> new_state
        Error(_) -> state
      }
  }
}

/// A generated stashed op has no delta, so fabricate the next cumulative
/// one through the kernel's own update path — state-identical to a genuine
/// merge-based `apply_stashed_op` of that delta (whose duplicate-idempotence
/// is pinned by unit tests) — and hand the rewritten op back for routing
/// (H2), keeping it valid for every peer's `apply_remote`/`ack_local`.
fn apply_stashed(
  state: PnCounterState,
  cmd: PnCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(PnCounterState, PnCommand) {
  let #(state, _events, op, _message_id) =
    pn_counter_kernel.update(state, cmd.amount)
  let Update(amount, delta) = op
  #(state, PnCommand(amount, Some(delta)))
}

/// Real summary round trip (PN6): encode to the JSON string a stored
/// summary would hold, then load it under the JOINING client's identity.
fn load_from_synced(state: PnCounterState, id: Int) -> PnCounterState {
  let summary_json = json.to_string(pn_counter_kernel.summary(state))
  case pn_counter_kernel.from_summary(summary_json, client_replica_id(id)) {
    Ok(loaded) -> loaded
    Error(_) ->
      panic as "load_from_synced could not decode the summary it just encoded"
  }
}

pub fn model() -> KernelModel(PnCounterState, PnCommand, Int) {
  KernelModel(
    name: "pn_counter",
    init: fn(id) { pn_counter_kernel.new(client_replica_id(id)) },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: pn_counter_kernel.value,
    gen_op: op_generator(),
    // The strongest per-step probe in the suite: cache coherence checked
    // after every command on every client.
    check: Some(pn_counter_kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
