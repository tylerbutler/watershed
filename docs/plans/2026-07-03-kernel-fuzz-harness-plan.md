# Kernel fuzz harness plan

**Date:** 2026-07-03
**Builds on:** `2026-07-03-dds-porting-complexity.md` (which flagged
test-dds-utils' fuzz model as "worth stealing") and the M1/M2 test strategy in
`2026-07-01-gleam-sharedmap-client-plan.md`.
**Reference source:** `../FluidFramework/packages/dds/test-dds-utils/src/ddsFuzzHarness.ts`

## Why a shared harness now

Today each kernel gets hand-rolled qcheck properties
(`counter_kernel_property_test.gleam`, `map_kernel_property_test.gleam`) that
simulate exactly three client behaviors — *eager* (submit everything, then
process the stream), *lazy* (submit just before ack), and *observer* (apply
everything remotely). That covers the two extreme submission timings but
misses everything in between, and each new kernel re-implements the same
`submit_local` / `ack_or_panic` / fold scaffolding.

What the current tests cannot express:

- **Arbitrary interleavings** — a client that submits mid-stream, with some
  ops sequenced and others still pending while remote ops arrive.
- **Partial delivery** — clients at different positions in the server log
  (the corpus replayer always delivers globally, in lockstep).
- **Submitted-but-not-sequenced windows** — the gap between "sent to the
  server" and "sequenced", which is where resubmit/reconnect bugs live.
- **Clients joining mid-session from a summary** (`from_sequenced` /
  `from_summary` are only exercised by unit tests).
- **Disconnect → resubmit**, **rollback**, and **stashed-op** paths
  (`counter_kernel.rollback`, `apply_stashed_op` have no property coverage).

The porting ladder adds six more kernels (cell, claims, register-collection,
pact-map, ordered-collection, task-manager) before the hard ones. Every rung
needs exactly this class of testing — "any sequenced interleaving converges" —
so the harness should be built once, now, and each kernel should only supply a
small model.

## What to steal from `ddsFuzzHarness.ts` — and what to drop

**Steal:**

| Upstream concept | Watershed equivalent |
|---|---|
| `DDSFuzzModel` (factory + generator + reducer + `validateConsistency`) | `KernelModel` record of functions (Gleam has no typeclasses; records of closures are the idiom) |
| Harness ops interleaved with DDS ops (`synchronize`, `addClient`, `changeConnectionState`, `applyThenRollback`) | A `Command` ADT interpreted by a pure simulator |
| Read-only **summarizer client** used as the consistency reference ("eventual consistency bugs are easier to reason about when one client was readonly") | Client 0 never authors ops; it doubles as the observer and the summary source for `AddClient` |
| Validation strategy knobs (random probability / fixed interval) | Generator weights for the `Synchronize` command |
| Seed reproducibility, `only`/`skip`, failure files, minimization | qcheck's integrated shrinking + seed config; failure-script JSON dump in a later milestone |

**Drop / replace:**

- **The mixin pattern.** Upstream composes eight `mixin*` wrappers because
  generators/reducers are mutation-based and async. In Gleam the whole thing
  collapses to one command ADT and one fold — dramatically simpler, same
  coverage.
- **Mock container runtime / attach / rehydrate / stashClient plumbing.**
  That layer tests Fluid's container lifecycle. Watershed's equivalent layer
  is `runtime_core`, which has its own tests; the kernel harness only needs a
  tiny pure "server" (inbox → total-order log → per-client cursors).
- **Async everything.** Kernels are pure; the interpreter is a pure fold.
  Determinism comes for free, which upstream works hard to retrofit
  (per-op seeds, `forceGlobalSeed` back-compat).

## Architecture

Three pieces, all under `test/watershed/fuzz/`:

### 1. `KernelModel` — what each kernel supplies

```gleam
pub type KernelModel(state, op, view) {
  KernelModel(
    name: String,
    init: fn() -> state,
    // Local optimistic apply. The op was produced by gen_op; the kernel's
    // named entry points (set/delete/clear, increment) are dispatched here,
    // mirroring submit_local in the current property tests.
    submit: fn(state, op) -> state,
    apply_remote: fn(state, op, SequencedMeta) -> state,
    ack_local: fn(state, op, SequencedMeta) -> Result(state, String),
    // Canonical comparable projection: entries() for map, .value for counter.
    observe: fn(state) -> view,
    // Op generator, state-independent, built from small ints so qcheck
    // shrinking stays effective (same key-space-of-4 trick as today).
    gen_op: qcheck.Generator(op),
    capabilities: Capabilities(state, op, view),
  )
}

pub type Capabilities(state, op, view) {
  Capabilities(
    // Summary round-trip: build a fresh client from a fully-synced client's
    // sequenced state (map: from_sequenced(sequenced_entries(s))).
    load_from_synced: Option(fn(state) -> state),
    // Semantic oracle: expected view from the sequenced op log alone
    // (counter: sum of increments; map: LWW fold). Cross-client convergence
    // is checked regardless; the oracle catches "converged on the wrong
    // answer" bugs.
    oracle: Option(fn(List(#(Int, op))) -> view),
    rollback: Option(fn(state, op) -> state),
    apply_stashed: Option(fn(state, op) -> state),
  )
}
```

`SequencedMeta` (author client index, sequence number, min sequence number,
connected-client set) is threaded through `apply_remote`/`ack_local` from day
one even though counter/map ignore it: **pact-map and ordered-collection
resolve ops against the connected-client quorum**, and retrofitting the
signature later means touching every model. This is the one place the harness
consciously pays forward for the porting ladder.

### 2. The simulator — a pure server + clients

```gleam
type Sim(state, op) {
  Sim(
    inbox: List(#(Int, op)),   // submitted, not yet sequenced (arrival order)
    log: List(#(Int, op)),     // the server's total order
    clients: List(Client(state, op)),
  )
}

type Client(state, op) {
  Client(
    state: state,
    connected: Bool,
    resend: List(op),   // in-flight ops returned to us by a disconnect
    delivered: Int,     // cursor into log
  )
}
```

The **inbox/log split** is the key upgrade over the current tests: it models
the "sent but not yet sequenced" window explicitly. Eager and lazy become two
degenerate schedules of the same machine, and everything between them becomes
reachable.

Delivery discipline: delivering `log[i]` to a client calls `ack_local` if the
client authored it, else `apply_remote`. Per-client submission order is
preserved through inbox → log → delivery, so the kernels' FIFO-ack assumption
(the TS reference-identity asserts) holds by construction; an `ack_local`
error is therefore always a real kernel bug and fails the test with the
shrunk script.

### 3. The command language — what the fuzzer generates

Scripts are **data** (lists of commands built from small ints), interpreted by
a fold. This is deliberate: qcheck shrinks data, not execution traces, so a
failing 80-command script minimizes to the shortest prefix/subset that still
fails — upstream needs bespoke `MinimizationTransform`s for the same effect.

| Command | Semantics | Milestone |
|---|---|---|
| `ClientOp(client, op)` | `submit` locally; push op to inbox if connected, else to `resend` | F1 |
| `Sequence(n)` | Move n ops inbox → log | F1 |
| `Deliver(client, n)` | Advance one client's cursor n ops | F1 |
| `Synchronize` | Sequence all, deliver all to connected clients, **validate** | F1 |
| `AddClient` | New client from `load_from_synced(client 0)` after fully delivering to client 0; cursor starts at log end | F2 |
| `Disconnect(client)` | Client's inbox entries move to its `resend` queue (they never reached sequencing); already-sequenced ops stay in the log | F3 |
| `Reconnect(client)` | Re-submit `resend` to inbox in order | F3 |
| `RollbackOp(client, op)` | `submit` then `capabilities.rollback` — never reaches the server | F3 |

Client indices are generated as `Int % client_count` so any shrunk integer
stays valid. Command weights (op-heavy, sync ~5%, matching upstream's default
`probability: 0.05`) live in one config record per suite.

### Validation

At every `Synchronize` (and at end-of-script, which appends a final
`Synchronize`):

1. **Convergence:** every connected, fully-delivered client's `observe`
   equals client 0's. Failure message names both client indices, like
   upstream's `validateConsistency` wrapper.
2. **Oracle** (if provided): client 0's view equals `oracle(log)`.
   After a full sync client 0 has no pending state, so this is well-defined.
3. Disconnected clients are excluded (their pending/resend state legitimately
   diverges) — same rule as upstream.

Per-command invariants (config-gated, default on; these subsume and retire
the bespoke properties in the current `*_property_test` files):

- **Ack transparency:** `observe` is compared before/after every `ack_local`.
- **Rebase equivalence** (map-style kernels): optimistic view ≡ sequenced
  state + pending replayed. Exposed as an optional per-model invariant hook
  `check: Option(fn(state) -> Result(Nil, String))` rather than hardcoded.

### Determinism and reproduction

- One qcheck seed drives script generation; the interpreter is pure, so
  seed → identical run. Support `FUZZ_SEED` / `FUZZ_ITERATIONS` env vars via
  `envoy` (already a dev dependency) with defaults of (random, 1000).
- On failure, qcheck reports the shrunk script (`string.inspect` of the
  command list is paste-able into a regression test).
- F4 adds upstream's `saveFailures` idea: dump the shrunk script as JSON to
  `test/fixtures/fuzz_failures/` and a replay test that runs every file found
  there — failure files become permanent regression tests, no transcription.

## File layout

```
test/watershed/fuzz/
  kernel_fuzz.gleam        # KernelModel, Capabilities, SequencedMeta,
                           # Sim, Command, interpreter, validation, run()
  script_gen.gleam         # command-script generators + weight config
  counter_model.gleam      # KernelModel for counter_kernel (+ oracle: sum)
  map_model.gleam          # KernelModel for map_kernel (+ oracle: LWW fold,
                           #   rebase-equivalence check hook)
test/watershed/
  counter_fuzz_test.gleam  # wires model + config into qcheck/startest
  map_fuzz_test.gleam
```

Two harness modules, not one per concern — keep it proportional to the ~400
lines this should be. The corpus tests (`map_kernel_corpus_test.gleam`) stay
as-is: they validate *semantics + events against the TS oracle*; the fuzz
harness validates *convergence under schedules the corpus can't enumerate*.
They are complementary, not redundant.

## Milestones

**F1 — Harness core + counter/map models (2–3 days).**
`KernelModel`, `Sim`, commands `ClientOp`/`Sequence`/`Deliver`/`Synchronize`,
convergence validation, script generator with weights. Port counter and map
onto it; keep the existing property tests until F2 proves parity.
Exit: 1000 seeded runs pass for both kernels, **and** mutation checks pass —
deliberately broken kernels (e.g. `ack_local` clear handling dropping the
wrong pending entry; `apply_remote` set not preserving insertion order) are
each caught and shrunk to a script of ≤ ~10 commands. A fuzz harness that
can't catch a planted bug is decoration; this is the real exit bar.

**F2 — Summary joins, oracles, invariant hooks (1–2 days).**
`AddClient` via `load_from_synced`, semantic oracles for both kernels,
ack-transparency + per-model invariant hooks. Retire
`counter_kernel_property_test.gleam` / `map_kernel_property_test.gleam`
(the harness now strictly subsumes them — delete, don't skip).
Exit: a planted `from_sequenced` insertion-order bug is caught via `AddClient`.

**F3 — Disconnect/resubmit, rollback, stashed ops (2–3 days).**
`Disconnect`/`Reconnect` with the resend-queue semantics above;
`RollbackOp` and stashed-op commands gated on capabilities (counter has both
today; map gets them only if/when the kernel grows the entry points — the
harness must degrade gracefully when a capability is `None`).
Exit: mutation check on `counter_kernel.rollback`; a schedule that
disconnects mid-pending-window and reconnects converges.

**F4 — Reproduction DX + CI profile (1–2 days).**
`FUZZ_SEED`/`FUZZ_ITERATIONS`, failure-script JSON dump + fixtures replay
test, `justfile` targets (`just fuzz` deep run, default `gleam test` runs a
fast profile, e.g. 200 iterations), short README section in the fuzz dir.
Exit: kill a run, re-run with printed seed, get the identical failure.

**F5 — Ladder onboarding (as each kernel lands, ~½ day per kernel).**
Each new port (cell, claims, register-collection, …) ships with a
`*_model.gleam` + fuzz test in the same PR as the kernel. `SequencedMeta`
gains real consumers at pact-map/ordered-collection; if the quorum modeling
needs more than the connected-client set (e.g. per-client ack tracking),
extend the meta record then — the signature is already threaded.

Total: **~1.5 weeks** for F1–F4, after which fuzz coverage is a fixed
per-kernel cost instead of a rewrite.

## Open questions / risks

- **qcheck seed API.** Verify at implementation time how qcheck 1.x pins a
  seed (`Config` accepts a seed; exact constructor TBD) — the `FUZZ_SEED`
  design depends on it. Fallback: generate the seed ourselves and derive all
  script ints from a splittable PRNG, using qcheck only as the runner.
- **Script length vs. runtime.** `map_kernel.entries` is O(n·pending) and the
  interpreter re-observes per command when invariants are on; 1000 iterations
  × long scripts could get slow on BEAM. Start with scripts ≤ ~60 commands
  and invariants sampled (every k commands) if profiling demands it.
- **Event-log validation is out of scope.** Which events are masked by
  pending state differs legitimately across schedules; equality of event
  logs is not a sound property. Events stay the corpus tests' job
  (oracle-checked, fixed schedules).
- **Disconnect semantics are a modeling choice.** The resend-queue model
  ("inbox ops never reached the server") matches levee's websocket reality
  but is one point in the space — it does not model duplicate-delivery on
  reconnect (levee dedups via client_id/csn in `runtime_core`, below the
  kernel). If a kernel ever needs at-least-once tolerance, that's a new
  command, not a rework.
- **Fuzzing `runtime_core` with the same command language** (routing,
  wire-codec round-trip per op, reconnect client_id remap) is a natural
  follow-on — the sim's server is deliberately shaped like levee's sequencer
  — but explicitly out of scope here; the kernel harness must not grow
  runtime dependencies.
