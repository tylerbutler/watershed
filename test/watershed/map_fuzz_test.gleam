//// Fuzz coverage for the map kernel: wires `map_model` into the shared
//// harness and script generator. `map_kernel_property_test.gleam` was
//// retired in F2 — this harness (convergence, oracle, ack transparency,
//// rebase equivalence via the `check` hook, AddClient summary joins, and
//// F3's Disconnect/Reconnect) strictly subsumes it.
//// `map_kernel_corpus_test.gleam` stays: it validates semantics + events
//// against the TS oracle, which is complementary. Map has neither a
//// `rollback` nor an `apply_stashed` capability today, so `default_weights`'
//// 0 weights for `rollback_op`/`stashed_op` keep the generator from ever
//// producing a command this model can't service.

import watershed/fuzz/kernel_fuzz
import watershed/fuzz/map_model
import watershed/fuzz/script_gen

const client_count = 3

pub fn converges_and_matches_oracle_test() {
  let model = map_model.model()
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
