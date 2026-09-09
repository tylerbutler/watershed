//// Fuzz coverage for the grow-only counter kernel. It wires `g_counter_model`
//// into the shared harness and the script generator, and it plants two faults
//// to prove that the harness and the oracle can see them.

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/g_counter_model.{GCommand}
import watershed/fuzz/kernel_fuzz.{ClientOperation, KernelModel, Synchronize}
import watershed/fuzz/script_gen
import watershed/g_counter_kernel.{Increment}

const client_count = 3

/// The grow-only counter has both `rollback` and `apply_stashed`, so its suite
/// asks the generator for those commands. The defaults are zero.
fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_operation: 8,
    stashed_operation: 8,
  )
}

pub fn converges_and_matches_oracle_test() -> Nil {
  let model = g_counter_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    client_count,
    script_gen.script_generator(model.gen_operation, client_count, weights()),
  )
}

/// Operations round-trip through the model codec with an empty delta slot and
/// with a filled one. A generated script dumps only `delta: null` operations,
/// so the filled branch is pinned here.
pub fn operation_json_round_trips_with_and_without_delta_test() -> Nil {
  let model = g_counter_model.model()
  let assert Ok(#(_, _, operation, _)) =
    g_counter_kernel.increment(g_counter_kernel.new(replica_id.new("a")), 6)
  let Increment(amount, delta) = operation

  [GCommand(3, None), GCommand(amount, Some(delta))]
  |> list.each(fn(command) {
    let assert Ok(decoded) =
      json.parse(
        json.to_string(model.operation_to_json(command)),
        model.operation_decoder,
      )
    decoded |> expect.to_equal(command)
  })
}

/// A planted fault: a `submit` that keeps the state but still routes the
/// operation drops the local increment of the author. The author then
/// disagrees with its peers, and the converged value is below the sum of the
/// oracle.
pub fn a_dropped_increment_fails_the_oracle_test() -> Nil {
  let model = g_counter_model.model()
  let buggy =
    KernelModel(..model, submit: fn(state, command, meta) {
      let #(_applied, routed) = model.submit(state, command, meta)
      #(state, routed)
    })
  let script = [
    ClientOperation(1, GCommand(3, None)),
    ClientOperation(2, GCommand(5, None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected a dropped increment to fail the harness"
  }
}

/// A planted fault: a `submit` that applies the same intent twice counts every
/// local edit two times. A merge is idempotent, so a duplicate delivery is
/// safe, but a duplicate *intent* is not. The oracle sees the difference.
pub fn a_replayed_increment_fails_the_oracle_test() -> Nil {
  let model = g_counter_model.model()
  let buggy =
    KernelModel(..model, submit: fn(state, command, meta) {
      let #(state, _first) = model.submit(state, command, meta)
      model.submit(state, command, meta)
    })
  let script = [
    ClientOperation(1, GCommand(3, None)),
    ClientOperation(2, GCommand(5, None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected a replayed increment to fail the harness"
  }
}
