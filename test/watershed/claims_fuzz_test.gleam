//// Fuzz coverage for the claims kernel: wires `claims_model` into the shared
//// harness. Uses `default_weights` (no `rollback_op`/`stashed_op`, which the
//// claims model does not yet expose as capabilities). Convergence and the
//// independent oracle validate at every generated `Synchronize`.
////
//// Mutation coverage (fuzz plan doctrine): planting "forget to advance the
//// stored sequence number on accept" in `claims_kernel` diverges the kernel
//// from `claims_model`'s independent oracle and is caught + shrunk here. The
//// `>=`-vs-`==` acceptance mutation is observationally equivalent in this
//// single-DDS model (see `claims_model`) and is instead pinned by the kernel
//// unit test `write_once_op_with_stale_high_ref_seq_is_rejected_test`.

import watershed/fuzz/claims_model
import watershed/fuzz/kernel_fuzz
import watershed/fuzz/script_gen

const client_count = 3

pub fn converges_and_matches_oracle_test() {
  let model = claims_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(
      model.gen_op,
      client_count,
      script_gen.default_weights(),
    ),
  )
}
