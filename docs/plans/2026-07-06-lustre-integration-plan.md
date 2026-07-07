# Lustre integration plan — `watershed_lustre`, the framework-native binding

**Date:** 2026-07-06
**Builds on:** `2026-07-06-typed-layer-dx-plan.md` (TX3 typed subscriptions, TX4 `ensure_*` — LU2 wraps them), `2026-07-06-typed-presence-plan.md` (PS2 driver — LU3 wraps it), the repeated glue in `examples/dice_lustre` and `examples/sudoku_lustre` (the evidence and the proof).
**Benchmark:** Fluid's React bindings — the shared-state framework meets the UI framework in a package, so apps declare instead of wire.

**Decisions already made (flagged — confirm before LU1):**

1. **A new top-level package `watershed_lustre/`** with its own `gleam.toml` (`target = "javascript"`, deps: `lustre >= 5.0.0 and < 6.0.0`, `watershed = { path = ".." }`), mirroring how examples already path-dep on watershed. Publishing to hex is deferred until watershed itself publishes; the path dep is the monorepo idiom. Core watershed gains no lustre dependency.
2. **No opinionated `Msg` type.** Every effect takes a caller-supplied `fn(...) -> msg` constructor, exactly how `lustre/event` handlers work. The package owns *scheduling* (microtask deferral, timer FFI), the app owns its message vocabulary.
3. **All inbound callbacks are unconditionally microtask-deferred.** dice_lustre.gleam:113 documents the bug class: watershed delivers events synchronously (possibly mid-`update`), and a `dispatch` nested in a running update is clobbered. Both examples independently discovered and patched this with hand-rolled `queue_microtask` FFI. Uniform deferral (even where not strictly needed) makes the semantics of every binding identical and deletes the bug class rather than documenting it.
4. **LU1 ships against today's untyped API** (connect/subscribe/after are useful now); LU2 adds the typed wrappers once TX3/TX4 land. This plan does not block on the typed plan.

## Why this rung

Both Lustre examples repeat identical glue, character for character in places:

- `connect_effect`: `effect.from`, mint a dev token, `watershed_js.connect` with `on_ready` bridged to `dispatch`, hand the `Document` back through a `GotHandle(doc)` msg (dice_lustre.gleam:89-118, sudoku_lustre.gleam:~160-180).
- `subscribe` → `queue_microtask` → `dispatch(Msg)` with a local FFI file per example (`dice_lustre_ffi.mjs`, `sudoku_ffi.mjs` — each exporting the same `queue_microtask`/`set_timeout`).
- `after(ms, msg)` timer effects for heartbeats and debounces.

Lustre is *the* Gleam frontend framework; if watershed's pitch is Gleam-end-to-end collaboration, this glue is the first thing every adopter writes and the first place they hit the mid-update dispatch bug. The package makes the TX3/TX4 primitives feel native rather than merely available, and it is where the presence driver becomes a one-liner.

## LU1 — package skeleton + untyped effects + dice proof

`watershed_lustre/src/watershed_lustre.gleam`:

```gleam
/// Connect and hand the Document back immediately; `connected` fires when the
/// handshake + replay complete. Owns the deferral of both callbacks.
pub fn connect(
  config: WatershedConfig,
  got_document got_document: fn(Document) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg)

/// Dev-mode variant: mints the HS256 dev token (async) before connecting —
/// absorbs the promise dance both examples do around `dev_token`.
pub fn connect_dev(
  url url: String, tenant tenant: String, secret secret: String,
  document document: String, user_id user_id: String,
  got_document got_document: fn(Document) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg)

pub fn subscribe(map: SharedMap, to_msg: fn(ChannelEvent) -> msg) -> Effect(msg)
// + subscribe_counter / subscribe_or_set / subscribe_claims / ... (per kind, today's ChannelEvent;
//   signatures narrow for free when TX3 lands — the wrappers absorb that break, apps don't)

pub fn after(ms: Int, msg: msg) -> Effect(msg)
pub fn force_reconnect(document: Document) -> Effect(msg)
```

One FFI module (`watershed_lustre/src/watershed_lustre_ffi.mjs`) owns `queue_microtask`/`set_timeout`; if the typed plan's TX4 or presence PS2 has already moved timers into `watershed_js`, re-export instead of duplicating.

**Proof:** rewrite `dice_lustre` on LU1 — `connect_effect` and its FFI file delete; `init`/`update` keep only app logic. Exit gate: `just server` two-tab manual script unchanged, `smoke.gleam` passes, net-negative diff.

## LU2 — typed effects (needs TX3 + TX4)

```gleam
pub fn subscribe_field(
  tm: TypedMap(s), field: Field(s, a),
  to_msg: fn(FieldChange(a)) -> msg,
) -> Effect(msg)

// ensure_* wrapped as effects, one per channel kind — bootstrap becomes declarative in `init`:
pub fn ensure_counter(
  doc: Document, tm: TypedMap(s), field: ChannelField(s, CounterChannel),
  to_msg: fn(Result(SharedCounter, String)) -> msg,
) -> Effect(msg)
// + ensure_map / ensure_child / ensure_or_set / ensure_claims / ... / ensure_field
```

**Proof:** the sudoku rewrite (typed plan TX5) moves onto these — its `bootstrap_effect`, retry constants, and per-channel subscribe wiring become `effect.batch([ensure_*..., subscribe_field(...)...])` in `init`. If TX5 has already landed, this is a follow-up simplification commit to the same example; coordinate so TX5's exit gate ("net-negative diff") is measured once, here.

## LU3 — presence effect (needs PS2)

```gleam
pub fn presence(
  document: Document, user_id: String, config: presence.Config,
  encode encode: fn(a) -> Json, decode decode: Decoder(a),
  on_peers on_peers: fn(List(Peer(a))) -> msg,
) -> Effect(msg)                                   // starts the driver; roster changes arrive as msgs

pub fn announce(handle: Handle(a), payload: a) -> Effect(msg)
```

The driver's `on_change` gets the same microtask deferral as every other inbound callback (decision 3 — this is exactly the deferral PS2 deliberately left out). Sudoku's presence wiring (`SignalReceived`, `Heartbeat` re-arm) reduces to one `presence(...)` in `init` plus `announce` effects on selection/typing changes.

## Deferred

- **Hex publication** — with watershed itself, not before.
- **A `watershed_lustre` server-components story** (Lustre's erlang target) — blocked on erlang signals and appetite; nothing here precludes it.
- **Selector/memoization helpers** (Fluid React's fine-grained re-render tooling) — Lustre's vdom diffing makes this less pressing; revisit if a real app shows render-cost pain.

## Milestones (one commit each)

| # | Milestone | Exit gate | Commit |
|---|---|---|---|
| LU0 | Plan doc | — | `docs: lustre integration plan` |
| LU1 | Package + connect/subscribe/after + dice rewrite | dice smoke + manual script; example FFI file deleted | `feat(lustre): watershed_lustre package with connect and subscription effects` |
| LU2 | Typed field/ensure effects + sudoku adoption | sudoku smoke; bootstrap is declarative in `init` | `feat(lustre): typed field subscriptions and ensure effects` |
| LU3 | Presence effect + sudoku presence adoption | two-tab presence script | `feat(lustre): presence effect` |
| LU4 | Docs (package README, website quickstart snippet) | — | `docs: document watershed_lustre` |

Ordering: LU1 lands any time. LU2 after typed-plan TX3/TX4; LU3 after presence PS2. LU2/LU3 are independent of each other.
