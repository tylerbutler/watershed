//// Fuzz coverage for the PN-counter kernel: wires `pn_counter_model` into
//// the shared harness and script generator, plus the M5 planted-bug test —
//// the proof that H1 (client identity threading) was necessary at all.

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{ClientOp, KernelModel, Synchronize}
import watershed/fuzz/pn_counter_model.{PnCommand}
import watershed/fuzz/script_gen
import watershed/pn_counter_kernel.{Update}

const client_count = 3

/// PN-counter has both `rollback` and `apply_stashed` capabilities, so its
/// suite opts into generating those commands (defaults are 0).
fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = pn_counter_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

/// Fixture DX (PN6): ops round-trip through the model's JSON codec with and
/// without a filled delta slot. Generated scripts only ever dump `delta:
/// null` ops (they are captured pre-submit), so the delta branch — needed
/// for hand-crafted or future rewritten-op fixtures — is pinned here.
pub fn op_json_round_trips_with_and_without_delta_test() {
  let model = pn_counter_model.model()
  let #(_, _, op, _) =
    pn_counter_kernel.update(pn_counter_kernel.new(replica_id.new("a")), -6)
  let Update(amount, delta) = op

  [PnCommand(3, None), PnCommand(amount, Some(delta))]
  |> list.each(fn(cmd) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(cmd)), model.op_decoder)
    decoded |> expect.to_equal(cmd)
  })
}

/// M5, kept as a permanent planted-bug test: an `init` that ignores its
/// identity gives every client the same replica id — precisely the pre-H1
/// world. Concurrent updates from two clients then land under one replica
/// key and max-merge to the larger cumulative, so the converged value (5)
/// undercounts the oracle's sum of amounts (8).
pub fn shared_replica_id_loses_increments_test() {
  let model = pn_counter_model.model()
  let buggy =
    KernelModel(..model, init: fn(_id) {
      pn_counter_kernel.new(replica_id.new("client-0"))
    })
  let script = [
    ClientOp(1, PnCommand(3, None)),
    ClientOp(2, PnCommand(5, None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected a shared replica id to lose an increment and fail the oracle"
  }
}
