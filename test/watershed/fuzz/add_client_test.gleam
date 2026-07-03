//// Unit tests for `AddClient` (F2), using toy models instead of
//// counter/map so failures here point at the harness, not at a production
//// kernel. Proves: (1) a client added via `load_from_synced` joins the
//// simulation and converges from then on, (2) `AddClient` is a hard error
//// when the model has no `load_from_synced` capability (silently
//// no-op-ing would hide the exact wiring gap F2 exists to close), and
//// (3) — the F2 exit criterion — a planted `load_from_synced`
//// insertion-order bug is caught via `AddClient`.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, AddClient, Capabilities, ClientOp, KernelModel, Synchronize,
}

/// State is an ordered log of ints applied so far (local or remote). This
/// stands in for map's `insertion_order`: a `load_from_synced` that
/// reorders it is exactly the class of bug the exit criterion targets.
/// `submit` appends optimistically and `ack_local` is a no-op (the op is
/// already in the log from `submit`), mirroring counter's ack-transparency
/// shape. Test scripts below only ever have one client's op in flight at a
/// time (submit immediately followed by `Synchronize`), so this toy model's
/// lack of a real pending/sequenced split never causes the reordering a
/// full kernel would otherwise have to guard against — that's exactly what
/// `map_model`'s rebase-equivalence `check` hook exists for, and is out of
/// scope for this harness-only test.
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
      // Correct summary join: a fresh client built from the log-so-far
      // observes exactly that log, in order.
      load_from_synced: Some(fn(state) { state }),
      oracle: None,
      rollback: None,
      apply_stashed: None,
    ),
  )
}

fn model_without_load_from_synced() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    ..ordered_log_model(),
    capabilities: Capabilities(
      ..ordered_log_model().capabilities,
      load_from_synced: None,
    ),
  )
}

/// Reverses the joined client's view of the log — a stand-in for a real
/// `from_sequenced` that gets insertion order backwards.
fn model_with_buggy_load_from_synced() -> KernelModel(List(Int), Int, List(Int)) {
  KernelModel(
    ..ordered_log_model(),
    capabilities: Capabilities(
      ..ordered_log_model().capabilities,
      load_from_synced: Some(fn(state) { list.reverse(state) }),
    ),
  )
}

pub fn add_client_joins_and_converges_test() {
  let script = [
    ClientOp(1, 1),
    Synchronize,
    ClientOp(2, 2),
    Synchronize,
    AddClient,
    ClientOp(1, 3),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(ordered_log_model(), 3, script)
  |> expect_ok
}

pub fn add_client_errors_without_load_from_synced_capability_test() {
  let script = [ClientOp(1, 1), Synchronize, AddClient]
  case kernel_fuzz.try_run_script(model_without_load_from_synced(), 3, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected AddClient to fail loudly without load_from_synced"
  }
}

pub fn add_client_catches_planted_insertion_order_bug_test() {
  // Two ops in a specific order land in the log; a correct summary join
  // must preserve that order. The buggy model reverses it, which two
  // distinct ops make observable via convergence.
  let script = [
    ClientOp(1, 10),
    Synchronize,
    ClientOp(2, 20),
    Synchronize,
    AddClient,
  ]
  case
    kernel_fuzz.try_run_script(model_with_buggy_load_from_synced(), 3, script)
  {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected the planted insertion-order bug to be caught by AddClient"
  }
}

fn expect_ok(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}
