//// Fuzz coverage for the counter kernel: wires `counter_model` into the
//// shared harness and script generator. `counter_kernel_property_test.gleam`
//// was retired in F2 — this harness (convergence, oracle, ack transparency,
//// AddClient summary joins, and F3's Disconnect/Reconnect/RollbackOp/
//// StashedOp) strictly subsumes it.

import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz
import watershed/fuzz/script_gen

const client_count = 3

/// Counter has both `rollback` and `apply_stashed` capabilities (unlike
/// map today), so its suite opts into generating those commands on top of
/// `default_weights`' F1/F2 defaults.
fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = counter_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}
