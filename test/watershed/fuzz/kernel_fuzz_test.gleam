//// Unit tests for the pure fuzz harness itself (F1), using a tiny toy
//// "sum" model instead of counter/map so failures here point at the
//// harness, not at a production kernel.

import exception
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import simplifile
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, Capabilities, ClientOp, Deliver, Disconnect, KernelModel,
  Reconnect, Sequence, Synchronize,
}

fn config() -> qcheck.Config {
  qcheck.default_config() |> qcheck.with_test_count(200)
}

/// A trivial commutative kernel: state is the running sum of every op
/// (local or remote) applied so far; acking never changes it.
fn sum_model() -> KernelModel(Int, Int, Int) {
  KernelModel(
    name: "toy-sum",
    init: fn(_id) { 0 },
    submit: fn(state, op, _meta) { #(state + op, Some(op)) },
    apply_remote: fn(state, op, _meta) { Ok(state + op) },
    ack_local: fn(state, _op, _meta) { Ok(state) },
    observe: fn(state) { state },
    gen_op: qcheck.bounded_int(from: -5, to: 5),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: json.int,
    op_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: Some(fn(entries) {
        list.fold(kernel_fuzz.log_ops(entries), 0, fn(acc, item) {
          acc + item.1
        })
      }),
      rollback: None,
      apply_stashed: None,
      react: None,
      remove_member: None,
    ),
  )
}

/// Same toy model, but with a `check` hook flagging a negative running sum
/// — a stand-in for a per-model invariant like map's rebase equivalence.
/// Proves the harness actually calls `check` and fails the run when it does.
/// Public so `watershed/fuzz_replay_test` can replay the fixture this
/// model's planted failure dumps, without transcribing the model.
pub fn sum_model_with_check() -> KernelModel(Int, Int, Int) {
  KernelModel(
    ..sum_model(),
    check: Some(fn(state) {
      case state < 0 {
        True -> Error("sum went negative")
        False -> Ok(Nil)
      }
    }),
  )
}

pub fn check_hook_catches_planted_violation_test() {
  let script = [ClientOp(0, -1), Synchronize]
  case kernel_fuzz.try_run_script(sum_model_with_check(), 1, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected the check hook to reject a negative running sum"
  }
}

pub fn check_hook_passes_when_invariant_holds_test() {
  let script = [ClientOp(0, 1), Synchronize]
  kernel_fuzz.try_run_script(sum_model_with_check(), 1, script)
  |> expect.to_be_ok
}

// ─────────────────────────────────────────────────────────────────────────────
// PN0/H1: `init` receives each client's identity (its index), distinct and
// covering 0..n−1.
// ─────────────────────────────────────────────────────────────────────────────

/// State is `#(my_init_id, ops_applied_in_order)`. `submit` ignores the
/// generated op and routes the client's own init id instead, so the log —
/// and every converged view — is exactly the sequence of identities the
/// harness handed to `init`. The oracle maps the log to its *author
/// indices*, so each op (an init id) must equal the index of the client
/// that submitted it: any duplicate or shifted assignment fails.
fn id_echo_model() -> KernelModel(#(Int, List(Int)), Int, List(Int)) {
  KernelModel(
    name: "toy-id-echo",
    init: fn(id) { #(id, []) },
    submit: fn(state, _op, _meta) {
      #(#(state.0, list.append(state.1, [state.0])), Some(state.0))
    },
    apply_remote: fn(state, op, _meta) {
      Ok(#(state.0, list.append(state.1, [op])))
    },
    ack_local: fn(state, _op, _meta) { Ok(state) },
    observe: fn(state) { state.1 },
    gen_op: qcheck.constant(0),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: json.int,
    op_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: Some(fn(entries) {
        list.map(kernel_fuzz.log_ops(entries), fn(entry) { entry.0 })
      }),
      rollback: None,
      apply_stashed: None,
      react: None,
      remove_member: None,
    ),
  )
}

pub fn init_receives_distinct_client_indices_test() {
  // One op per client, synchronized between each so every client applies
  // them in the same (log) order.
  let script = [
    ClientOp(0, 0),
    Synchronize,
    ClientOp(1, 0),
    Synchronize,
    ClientOp(2, 0),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(id_echo_model(), 3, script)
  |> expect.to_be_ok
}

/// Teeth check: an `init` that ignores its identity (every client gets the
/// same replica id — precisely the pre-H1 world a lattice kernel cannot
/// survive) must be caught by the same script.
pub fn constant_init_identity_is_caught_test() {
  let model = KernelModel(..id_echo_model(), init: fn(_id) { #(7, []) })
  let script = [
    ClientOp(0, 0),
    Synchronize,
    ClientOp(1, 0),
    Synchronize,
    ClientOp(2, 0),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(model, 3, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected a constant init identity to fail the oracle"
  }
}

pub fn fixed_script_converges_test() {
  let script = [
    ClientOp(0, 3),
    ClientOp(1, 4),
    Synchronize,
    ClientOp(0, -2),
    Sequence(1),
    Deliver(0, 1),
    Deliver(1, 1),
    Synchronize,
  ]
  kernel_fuzz.run_script(sum_model(), 2, script)
}

pub fn random_scripts_converge_test() {
  qcheck.run(
    config(),
    qcheck.generic_list(
      qcheck.from_generators(
        qcheck.tuple2(
          qcheck.bounded_int(from: 0, to: 1),
          qcheck.bounded_int(from: -5, to: 5),
        )
          |> qcheck.map(fn(pair) { ClientOp(pair.0, pair.1) }),
        [
          qcheck.bounded_int(from: 0, to: 3) |> qcheck.map(Sequence),
          qcheck.tuple2(
            qcheck.bounded_int(from: 0, to: 1),
            qcheck.bounded_int(from: 0, to: 3),
          )
            |> qcheck.map(fn(pair) { Deliver(pair.0, pair.1) }),
          qcheck.constant(Synchronize),
        ],
      ),
      qcheck.small_non_negative_int(),
    ),
    fn(script) { kernel_fuzz.run_script(sum_model(), 2, script) },
  )
}

fn reactive_model() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    name: "toy-reactive",
    init: fn(_id) { [] },
    submit: fn(state, op, _meta) { #(state, Some(op)) },
    apply_remote: fn(state, op, _meta) { Ok(list.append(state, [op])) },
    ack_local: fn(state, op, _meta) { Ok(list.append(state, [op])) },
    observe: fn(state) { state },
    gen_op: qcheck.constant(1),
    check: None,
    canonicalize: None,
    ack_preserves_view: False,
    op_to_json: json.int,
    op_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: Some(fn(entries) {
        kernel_fuzz.log_ops(entries) |> list.map(fn(entry) { entry.1 })
      }),
      rollback: None,
      apply_stashed: None,
      react: Some(fn(_state, op, _meta, _self_id, is_local) {
        case op == 1 && is_local {
          True -> [2]
          False -> []
        }
      }),
      remove_member: None,
    ),
  )
}

pub fn synchronize_reaches_reactive_fixpoint_test() {
  let script = [ClientOp(1, 1), Synchronize]
  kernel_fuzz.try_run_script(reactive_model(), 2, script)
  |> expect.to_be_ok
}

fn leave_model() -> KernelModel(List(#(Int, Int)), Int, List(#(Int, Int))) {
  KernelModel(
    name: "toy-leave",
    init: fn(_id) { [] },
    submit: fn(state, op, _meta) { #(state, Some(op)) },
    apply_remote: fn(state, _op, _meta) { Ok(state) },
    ack_local: fn(state, _op, _meta) { Ok(state) },
    observe: fn(state) { state },
    gen_op: qcheck.constant(0),
    check: None,
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: json.int,
    op_decoder: decode.int,
    capabilities: Capabilities(
      load_from_synced: None,
      oracle: Some(fn(entries) {
        entries
        |> list.index_map(fn(entry, i) { #(entry, i) })
        |> list.filter_map(fn(pair) {
          let #(entry, i) = pair
          case entry {
            kernel_fuzz.LeaveEntry(client) -> Ok(#(client, i + 1))
            kernel_fuzz.OpEntry(_, _, _) -> Error(Nil)
          }
        })
      }),
      rollback: None,
      apply_stashed: None,
      react: None,
      remove_member: Some(fn(state, leaver, meta: kernel_fuzz.SequencedMeta) {
        list.append(state, [#(leaver, meta.sequence_number)])
      }),
    ),
  )
}

pub fn leave_entry_applies_remove_member_at_sequence_point_test() {
  let script = [Disconnect(1), Synchronize]
  kernel_fuzz.try_run_script(leave_model(), 3, script)
  |> expect.to_be_ok
}

fn non_terminating_reactive_model() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    ..reactive_model(),
    name: "toy-nonterminating-reactive",
    capabilities: Capabilities(
      ..reactive_model().capabilities,
      react: Some(fn(_state, op, _meta, _self_id, is_local) {
        case is_local {
          True -> [op]
          False -> []
        }
      }),
    ),
  )
}

pub fn synchronize_round_cap_fails_instead_of_hanging_test() {
  let script = [ClientOp(1, 1), Synchronize]
  case kernel_fuzz.try_run_script(non_terminating_reactive_model(), 2, script) {
    Error("did not reach quiescence") -> Nil
    Error(detail) -> panic as { "unexpected error: " <> detail }
    Ok(_) -> panic as "expected non-terminating reactions to hit the round cap"
  }
}

pub fn disconnected_reaction_routes_to_resend_and_replays_on_reconnect_test() {
  let script = [
    ClientOp(1, 1),
    Sequence(1),
    Disconnect(1),
    Deliver(1, 1),
    Reconnect(1),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(reactive_model(), 2, script)
  |> expect.to_be_ok
}

// ─────────────────────────────────────────────────────────────────────────────
// F4: failing scripts dump a JSON fixture, and it replays to the same
// failure (reproduction DX).
// ─────────────────────────────────────────────────────────────────────────────

/// `run_script` (unlike `try_run_script`) is what qcheck calls, so it's the
/// one that must dump the JSON fixture on failure. We use
/// `exception.rescue` only here, to assert on the fixture *after* the
/// expected panic — this is the one place the harness's own tests need to
/// observe a panic's side effect rather than treat it as a bare pass/fail.
pub fn failing_run_script_dumps_a_replayable_json_fixture_test() {
  let fixture_path = kernel_fuzz.fixture_path("toy-sum")
  let _ = simplifile.delete(fixture_path)

  let script = [ClientOp(0, -1), Synchronize]
  case
    exception.rescue(fn() {
      kernel_fuzz.run_script(sum_model_with_check(), 1, script)
    })
  {
    Ok(_) ->
      panic as "expected run_script to panic on a planted check violation"
    Error(_) -> Nil
  }

  let content = case simplifile.read(fixture_path) {
    Ok(content) -> content
    Error(_) ->
      panic as {
        "expected run_script to dump a JSON failure fixture to " <> fixture_path
      }
  }

  let decoder = {
    use model <- decode.field("model", decode.string)
    use client_count <- decode.field("client_count", decode.int)
    use detail <- decode.field("detail", decode.string)
    use replayed_script <- decode.field(
      "script",
      kernel_fuzz.script_decoder(decode.int),
    )
    decode.success(#(model, client_count, detail, replayed_script))
  }
  let assert Ok(#(model_name, client_count, original_detail, replayed_script)) =
    json.parse(content, decoder)

  model_name |> expect.to_equal("toy-sum")
  client_count |> expect.to_equal(1)
  replayed_script |> expect.to_equal(script)

  // Replaying the exact script decoded from the fixture reproduces the
  // exact same failure — the "kill a run, replay it, get an identical
  // failure" exit criterion, with no manual transcription of the script.
  case
    kernel_fuzz.try_run_script(
      sum_model_with_check(),
      client_count,
      replayed_script,
    )
  {
    Ok(Nil) -> panic as "expected the replayed script to still fail"
    Error(replayed_detail) ->
      replayed_detail |> expect.to_equal(original_detail)
  }
}
