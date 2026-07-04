//// Fuzz coverage for ConsensusRegisterCollection. The independent oracle
//// reimplements atomic CAS, unconditional version append, and version pruning.

import watershed/fuzz/kernel_fuzz
import watershed/fuzz/register_collection_model
import watershed/fuzz/script_gen

const client_count = 3

pub fn converges_and_matches_oracle_test() {
  let model = register_collection_model.model()
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
