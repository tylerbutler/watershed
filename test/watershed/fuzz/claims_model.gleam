//// `KernelModel` for the claims kernel. Claims is non-optimistic and
//// consensus-flavoured, so it exercises the harness generalizations added for
//// consensus kernels:
////
//// - The model op is `ClaimCommand`, carrying the claim *kind* (write-once vs
////   CAS) plus a `ref_seq` slot. `gen_op` leaves `ref_seq` at 0; `submit`
////   computes the real `ref_seq` from `SubmitMeta.last_seen_seq` (via the
////   kernel) and returns the rewritten command for the harness to route. A
////   submit that sends no op — a write-once claim on a committed key, or a
////   duplicate suppressed to keep one pending claim per key — returns `None`.
//// - `ack_preserves_view` is `False`: acking a winning claim first makes it
////   visible (reads are committed-only), which is correct, not a bug.
////
//// The oracle is an INDEPENDENT reimplementation of the acceptance fold (it
//// does not call the kernel), so a kernel that forgot to advance an entry's
//// stored sequence number on accept would diverge from it and be caught at the
//// next `Synchronize`. The `>=`-vs-`==` acceptance mutation is NOT catchable
//// here: this is a single-DDS model, so a client's `ref_seq` (its channel
//// delivered cursor) can never exceed a key's committed sequence number at
//// sequencing time, making the two rules observationally equivalent on every
//// reachable schedule. In production `ref_seq` comes from the container-wide
//// last sequence number, which CAN exceed a key's SN — so the `==` choice is
//// pinned by the kernel unit test
//// `write_once_op_with_stale_high_ref_seq_is_rejected_test`.

import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/claims_kernel.{
  type ClaimsState, AlreadyClaimed, Claim, Submitted,
}
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}

pub type ClaimKind {
  TrySet
  Cas
}

/// The generated op. `ref_seq` is a slot filled by `submit` (0 until then) —
/// see the module note on why it is computed, never generated.
pub type ClaimCommand {
  ClaimCommand(kind: ClaimKind, key: String, value: Json, ref_seq: Int)
}

fn to_claim(cmd: ClaimCommand) -> claims_kernel.ClaimOp {
  Claim(cmd.key, cmd.value, cmd.ref_seq)
}

fn op_to_json(cmd: ClaimCommand) -> Json {
  json.object([
    #("kind", json.string(case cmd.kind {
      TrySet -> "try"
      Cas -> "cas"
    })),
    #("key", json.string(cmd.key)),
    #("value", cmd.value),
    #("ref_seq", json.int(cmd.ref_seq)),
  ])
}

fn op_decoder() -> decode.Decoder(ClaimCommand) {
  use kind <- decode.field("kind", decode.string)
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.int)
  use ref_seq <- decode.field("ref_seq", decode.int)
  let kind = case kind {
    "cas" -> Cas
    _ -> TrySet
  }
  decode.success(ClaimCommand(kind, key, json.int(value), ref_seq))
}

/// Two keys keep races frequent; small integer values shrink well.
fn op_generator() -> qcheck.Generator(ClaimCommand) {
  qcheck.tuple2(qcheck.small_non_negative_int(), qcheck.small_non_negative_int())
  |> qcheck.map(fn(pair) {
    let #(a, b) = pair
    let kind = case a % 2 {
      0 -> TrySet
      _ -> Cas
    }
    let key = case a / 2 % 2 {
      0 -> "a"
      _ -> "b"
    }
    ClaimCommand(kind, key, json.int(b % 5), 0)
  })
}

fn submit(
  state: ClaimsState,
  cmd: ClaimCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(ClaimsState, option.Option(ClaimCommand)) {
  // One pending claim per key: a second submit for a key already pending is a
  // kernel usage error, so drop it here (no op routed) rather than provoke one.
  case dict.has_key(state.pending, cmd.key) {
    True -> #(state, None)
    False -> {
      let result = case cmd.kind {
        TrySet ->
          claims_kernel.try_set_claim(
            state,
            cmd.key,
            cmd.value,
            meta.last_seen_seq,
          )
        Cas ->
          claims_kernel.compare_and_set_claim(
            state,
            cmd.key,
            cmd.value,
            meta.last_seen_seq,
          )
      }
      case result {
        Ok(Submitted(state, op)) -> #(
          state,
          Some(ClaimCommand(cmd.kind, op.key, op.value, op.ref_seq)),
        )
        // Write-once on a committed key: resolved synchronously, no op sent.
        Ok(AlreadyClaimed(_)) -> #(state, None)
        // Unreachable given the pending guard above.
        Error(_) -> #(state, None)
      }
    }
  }
}

fn apply_remote(
  state: ClaimsState,
  cmd: ClaimCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> ClaimsState {
  let #(state, _events) =
    claims_kernel.apply_remote(state, to_claim(cmd), meta.sequence_number)
  state
}

fn ack_local(
  state: ClaimsState,
  cmd: ClaimCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(ClaimsState, String) {
  case claims_kernel.ack_local(state, to_claim(cmd), meta.sequence_number) {
    Ok(#(state, _events, _outcome)) -> Ok(state)
    Error(claims_kernel.UnexpectedAck(_, detail)) -> Error(detail)
    Error(claims_kernel.UnexpectedRollback(_, detail)) -> Error(detail)
    Error(claims_kernel.AlreadyPendingLocally(key)) ->
      Error("unexpected AlreadyPendingLocally for key " <> key)
  }
}

/// Independent acceptance fold over the sequenced log (SN = 1-based position),
/// producing the same `(key, value, sequence_number)` view as
/// `claims_kernel.summary_entries`. Reimplemented here, NOT delegated to the
/// kernel, so a kernel bug in the accept/store step diverges from it.
fn oracle(log: List(#(Int, ClaimCommand))) -> List(#(String, Json, Int)) {
  list.index_fold(log, dict.new(), fn(claims, entry, i) {
    let cmd = entry.1
    let seq = i + 1
    let accepted = case dict.get(claims, cmd.key) {
      Error(_) -> True
      Ok(#(_value, entry_seq)) -> cmd.ref_seq == entry_seq
    }
    case accepted {
      True -> dict.insert(claims, cmd.key, #(cmd.value, seq))
      False -> claims
    }
  })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    let #(key, #(value, seq)) = entry
    #(key, value, seq)
  })
}

fn load_from_synced(state: ClaimsState) -> ClaimsState {
  claims_kernel.from_summary(claims_kernel.summary_entries(state))
}

pub fn model() -> KernelModel(ClaimsState, ClaimCommand, List(#(String, Json, Int))) {
  KernelModel(
    name: "claims",
    init: claims_kernel.new,
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: claims_kernel.summary_entries,
    gen_op: op_generator(),
    check: None,
    canonicalize: None,
    ack_preserves_view: False,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: None,
      apply_stashed: None,
    ),
  )
}
