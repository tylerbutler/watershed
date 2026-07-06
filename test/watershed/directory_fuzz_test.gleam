//// Fuzz coverage for the directory kernel (SharedDirectory port): wires
//// `directory_model` into the shared harness and script generator. Exercises
//// convergence, the pure-remote oracle, ack transparency, `AddClient` summary
//// joins, and F3's Disconnect/Reconnect/RollbackOp/StashedOp over a bounded
//// tree of storage + subdirectory ops.
////
//// The instance-aliasing divergences deep sweeps used to find were closed by
//// porting FF's full subdirectory identity lifecycle (dispose-time
//// `clearSubDirectorySequencedData`, the create re-stamp guard, and
//// id-matched storage acks standing in for FF's `localOpMetadata` object
//// identity); see docs/plans/2026-07-04-shared-directory-kernel-plan.md.

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
