# In-memory hub plan — deterministic multi-client documents without levee

**Status:** ✅ Complete (2026-07-07). Shipped as **`sluice`** — the working name
"hub" was bikeshed at review to the levee/spillway hydraulic register (a sluice
gate maps onto the explicit `step`/`pause` delivery control). HM1a/HM1b
(injectable transport, both targets), HM2 (`sluice/core` + `sluice/frames` with
round-trip tests), HM3 (erlang driver + ungated convergence subset: map LWW,
counter sum, claims first-writer, pause/step), HM4 (`sluice_js` + example app
test) all landed. HM5 = this doc + README "Testing your app" section + module
docs. Deferred within scope: `disconnect`/`reconnect` driver controls and
JS-side `pause` (needs runtime identity); summary joins (decision 5).

**Date:** 2026-07-06
**Builds on:** `2026-07-03-kernel-fuzz-harness-plan.md` (the pure `Sim`/`Client` inbox-log split this generalizes to the document level), `wire/socket.gleam` (the codec inventory), the `WATERSHED_INTEGRATION`-gated suite in `test/watershed/integration_test.gleam` (the tests this un-gates).
**Benchmark:** Fluid's `@fluidframework/test-utils` / mock runtimes — app authors write deterministic multi-client tests in their own test suite, no server required.

**Decisions already made (flagged — confirm before HM1):**

1. **The hub sits behind a transport seam and speaks real wire JSON.** Both runtimes are hard-wired today (erlang → aquamarine/Phoenix, JS → `transport_ffi.mjs`); HM1 introduces an injectable transport record and the hub exchanges the same JSON strings levee does. Fidelity over convenience: the runtime under test runs byte-identical code paths (codecs, pending queues, resubmit, reconnect), and the inverse codecs the hub needs double as executable protocol documentation. The rejected alternative — a fake `Document` implementing the facade API directly — would test nothing below the facade.
2. **The live suite stays authoritative.** The hub models levee; it is not levee. `WATERSHED_INTEGRATION` tests keep running against the real server in CI; hub tests cover logic (races, convergence, reconnect choreography) that today can't run at all without infrastructure. A semantic divergence between hub and levee is a bug in the hub, pinned by keeping mirrored assertions in both suites for a core subset.
3. **Delivery is explicit, never eager.** Ops sequence on submit but deliver only on `settle`/`step` calls (the fuzz harness's `Deliver`/`Synchronize` split, promoted). This is what makes races *scriptable*: "A and B both claim the cell, deliver B first" is a test you can write. An auto-delivering convenience mode is one `settle` call, not a second code path.
4. **The hub ships in `src/` (module `watershed/hub`), not `test/`** — app authors must be able to import it from their own test suites. Naming follows the house watery register (levee, spillway, aquamarine); `hub` is the working name — bikeshed at HM0 review if a better sheet-name exists (millpond?).
5. **Summary-based joins are out of v1.** The hub keeps the full op log, so late joiners replay history (the path `connect` already takes). Join-from-summary needs the hub to run summarization; defer until a consumer needs it.

## Why this rung

Watershed apps currently cannot be tested. Every convergence test in the repo is either kernel-level (pure fuzz harness — inaccessible to app authors, single-kernel, no facade) or gated on a live levee (`WATERSHED_INTEGRATION` + `just server`). The examples verify by *manual two-tab scripts* — that's the state of the art for anyone building on watershed today, and it caps how seriously the framework can be adopted. The typed plan's TX4 (`ensure_*` races) and presence PS2 both had to write "gated integration test" as their exit gates for want of this harness.

The fuzz plan already proved the hard part — a deterministic sequencer with explicit submitted-but-not-sequenced state. This plan promotes that shape from one kernel to a whole document behind the real runtime.

## HM1 — transport seams (zero behavior change, one commit per target)

**Erlang** (`runtime.gleam`): `start` gains a transport argument; the default wraps today's aquamarine calls so `watershed.connect` is unchanged.

```gleam
pub type Transport {
  Transport(
    connect: fn(TransportCallbacks) -> Result(TransportLink, String),
    push: fn(TransportLink, String, String) -> Nil,   // event, JSON payload
    close: fn(TransportLink) -> Nil,
    drop: fn(TransportLink) -> Nil,                   // force-reconnect path
  )
}
pub type TransportCallbacks {
  TransportCallbacks(on_event: fn(String, Dynamic) -> Nil, on_join: fn() -> Nil, on_close: fn() -> Nil)
}
```

**JS** (`runtime_js.gleam`): the same record shape over `transport_js`'s existing signatures (`connect`/`push`/`close`/`drop_socket` — the callbacks already have exactly this form).

Exit gate: full suite + gated integration green on both targets with the default transport; the diff is mechanical injection only.

## HM2 — hub core (`src/watershed/hub.gleam`, pure + target-agnostic)

A levee-shaped state machine over parsed frames:

- **Connection lifecycle**: decode `connect_document` payloads, assign client ids, emit `ConnectedMessage` (+ join/leave `signal`-style client announcements as levee sends them).
- **Sequencing**: assign monotone SNs to submitted ops, broadcast to every client *including the author* (that echo is the ack path the kernels' `ack_local` depends on); per-client delivery cursors so `last_seen_sequence_number` reconnect catch-up works.
- **Signals**: fan out to all other clients, `type` stripped — reproducing the levee quirk the presence plan codes against (decision 2 of that plan gets a pinned test here).
- **Clock**: the hub owns a logical `now_ms` the erlang driver can advance (`advance(hub, ms)`) so TTL logic (presence prune) is testable without sleeping.
- **Inverse codecs**: the hub decodes what clients encode and encodes what clients decode. `wire/socket.gleam` already has both directions for some frames (it decodes sequenced messages for the client); the genuinely new pieces are decoding client→server `connect_document`/op-submission payloads and encoding server→client `connected`/sequenced-op frames. They live in `watershed/hub/frames.gleam` with round-trip tests against the client-side codecs — mismatches surface as test failures here rather than as protocol drift in production.

Pure-core tests: sequencing monotone per document; author echo carries the client's `clientSequenceNumber`; catch-up from a cursor replays exactly the gap; signal fan-out excludes the author and strips `type`.

## HM3 — erlang driver + un-gating proof

```gleam
pub fn start() -> Hub                                    // hub actor
pub fn connect(hub: Hub, user_id: String) -> Result(watershed.Document, String)
pub fn settle(hub: Hub) -> Nil                           // deliver until quiescent
pub fn step(hub: Hub) -> Bool                            // deliver one frame; False = drained
pub fn pause(hub: Hub, doc: Document) / resume(...)      // hold one client's inbound frames
pub fn disconnect(hub: Hub, doc: Document) / reconnect(...)  // exercise resend/catch-up
pub fn advance(hub: Hub, ms: Int) -> Nil
```

`hub.connect` calls `watershed.connect`'s internals with the hub transport — the returned `Document` is the real facade type; every existing API works on it.

**Proof:** port the core convergence subset of `integration_test.gleam` (map LWW race, counter sum, claims first-writer, or-set add-wins) to run **ungated** against the hub, keeping the live-gated originals (decision 2). Plus new tests only the hub makes possible: deterministic delivery-order races via `pause`/`step`, reconnect-with-pending-ops choreography.

## HM4 — JS driver

Same API over a shared mutable hub cell (single-threaded JS makes determinism free; `settle` drains synchronously). This is what lets *app authors* — whose apps are JS/Lustre — write gleeunit tests on `--target javascript`, and lets presence PS2's driver tests run ungated (two hub clients, `advance` past TTL, assert expiry).

**Proof:** a real app test in an example package — e.g. `sudoku_lustre` gets `test/convergence_test.gleam`: two hub clients race a cell claim, assert both converge on the winner. The examples graduate from manual-two-tab verification to actual tests.

## Deferred

- **Summary joins / in-memory summary store** (decision 5).
- **Fault injection** (frame corruption, reorder beyond pause/step, nack paths) — the seam makes it possible; add when a bug class demands it.
- **Latency simulation** — explicit `step` scripting covers the semantic races; wall-clock latency adds nothing deterministic.
- **Replacing the fuzz harness** — non-goal; the kernel-level harness is faster and shrinks. The hub may later *host* a document-level fuzz (random scripts over `step`/`pause`), as its own plan.

## Milestones (one commit each)

| # | Milestone | Exit gate | Commit |
|---|---|---|---|
| HM0 | Plan doc | — | `docs: in-memory hub plan` |
| HM1a | Erlang transport seam | zero behavior change; full + gated suites green | `refactor(runtime): injectable transport` |
| HM1b | JS transport seam | same, JS target | `refactor(runtime): injectable transport for the js runtime` |
| HM2 | Hub core + inverse codecs + round-trip tests | pure tests green both targets | `feat(hub): in-memory sequencer core and wire frame codecs` |
| HM3 | Erlang driver + ungated integration subset | ported tests green with no env gate; originals untouched | `feat(hub): erlang test driver with deterministic delivery controls` |
| HM4 | JS driver + example app test | sudoku convergence test green on --target javascript | `feat(hub): js test driver` |
| HM5 | Docs (module docs, "testing your app" website page) | — | `docs: document testing against the hub` |

Ordering: independent of the typed-layer plan, but HM1 touches `runtime.gleam`/`runtime_js.gleam` where TX3 also lands — sequence HM1 before or after TX3, not interleaved. HM4 unblocks better exit gates for typed TX4 and presence PS2 tests; if this plan runs first, those plans' "gated" tests are written against the hub instead.
