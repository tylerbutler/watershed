# Kernel fuzz harness

Pure, model-based fuzzing for kernel convergence. See
`docs/plans/2026-07-03-kernel-fuzz-harness-plan.md` for the full design;
this file covers day-to-day reproduction and CI usage (F4).

## Running

- `gleam test` — fast profile, 200 iterations per suite (`counter_fuzz_test`,
  `map_fuzz_test`). Good for the inner dev loop and pre-commit checks.
- `just fuzz` — deep profile, 5000 iterations per suite. Use for CI/nightly
  runs or when chasing a suspected rare failure.

Both are driven by `kernel_fuzz.config_from_env`, which reads two env vars:

| Var               | Default | Effect                                   |
| ------------------ | ------- | ----------------------------------------- |
| `FUZZ_ITERATIONS`   | `200`   | Number of generated scripts per suite run |
| `FUZZ_SEED`         | random  | Pins qcheck's seed for a reproducible run |

```sh
FUZZ_ITERATIONS=10000 FUZZ_SEED=42 gleam test
```

## Reproducing a failure

qcheck 1.x's `Seed` type is opaque — there's no accessor to read back or
print the seed a random (unset `FUZZ_SEED`) run used, so "print the seed
and paste it back in" isn't available the way it is in some other
property-testing libraries. `FUZZ_SEED` still lets you pin a seed *before*
a run to make the whole run reproducible end to end, but it can't tell you
after the fact which seed produced a given failure.

Instead, the harness dumps the shrunk failing script itself:

- Every time `kernel_fuzz.run_script` fails, it writes a JSON fixture to
  `test/fixtures/fuzz_failures/<model-name>_failure.json` **before**
  panicking. Because qcheck's shrink loop keeps re-invoking the property
  on smaller and smaller failing candidates, the last write before the
  panic reaches the top of the test is the fully-shrunk, minimal script —
  no manual minimization needed.
- The fixture records the model name, client count, the exact failure
  message, and the script itself (as JSON, via `kernel_fuzz.script_to_json`
  / `kernel_fuzz.script_decoder`).
- `test/watershed/fuzz_replay_test.gleam` reads every `*.json` file in
  `test/fixtures/fuzz_failures/` on every `gleam test` run, decodes the
  script, and re-runs it through `kernel_fuzz.try_run_script`. It asserts
  the replay reproduces **the exact same failure message** that was
  recorded — this is the harness's "kill a run, re-run it, get an
  identical failure" guarantee.
- If a fixture's script stops failing (the underlying bug got fixed), the
  replay test fails loudly with a pointer to that fixture instead of
  silently starting to pass, so you know to update or delete it.

In short: `test/fixtures/fuzz_failures/` is checked in and every file there
is a permanent regression test, populated automatically the first time
`gleam test` or `just fuzz` hits a failure — no transcription into a new
test function required.

### Adding `op_to_json` / `op_decoder` to a new `KernelModel`

Every `KernelModel` must supply `op_to_json: fn(op) -> Json` and
`op_decoder: Decoder(op)` so its ops round-trip through the failure-fixture
JSON. See `counter_model.gleam` (a single-constructor op, encoded as a bare
int) and `map_model.gleam` (a multi-constructor op, encoded as a tagged
object) for the two shapes you're likely to need.
