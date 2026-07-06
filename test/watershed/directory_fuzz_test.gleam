//// Fuzz coverage for the directory kernel (SharedDirectory port): wires
//// `directory_model` into the shared harness and script generator. Exercises
//// convergence, the pure-remote oracle, ack transparency, `AddClient` summary
//// joins, and F3's Disconnect/Reconnect/RollbackOp/StashedOp over a bounded
//// tree of storage + subdirectory ops.
////
//// KNOWN LIMITATION (SD3 partial): at the default fuzz depth this suite is
//// green, but a deep sweep (`FUZZ_ITERATIONS=5000 gleam test`) still surfaces
//// rare convergence divergences in a single class — subdirectory *instance
//// aliasing* under stash + disconnect + concurrent create/delete/recreate of
//// the same subdir name. Root cause: storage pending is held inside per-instance
//// node copies (pending-create nodes and sequenced nodes) and gets moved/split/
//// dropped across instance transitions, whereas observers always apply remote
//// ops to the single sequenced node per path. The faithful fix is the FF
//// single-`SubDirectory`-object-per-path model (one node per path carrying both
//// sequenced and pending storage, with create/delete lifecycle as flags/creator
//// ids on that same node — never copying storage between instances). Tracked as
//// a follow-up refactor; see docs/plans/2026-07-04-shared-directory-kernel-plan.md.

import watershed/fuzz/directory_model
import watershed/fuzz/kernel_fuzz
import watershed/fuzz/script_gen

const client_count = 3

/// The directory kernel has both `rollback` and `apply_stashed`, so its suite
/// opts into generating those commands on top of `default_weights`.
fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = directory_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}
