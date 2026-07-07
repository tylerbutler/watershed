# Typed presence plan — promote sudoku's presence into the library

**Date:** 2026-07-06
**Builds on:** `examples/sudoku_lustre/src/presence.gleam` (the prototype this plan promotes), commit `298490a` (`feat(runtime): add ephemeral signal broadcast`), `2026-07-06-typed-layer-dx-plan.md` (codec idiom; no hard dependency).
**Benchmark:** Fluid's `@fluidframework/presence` — typed per-user ephemeral state with liveness, as a package, not per-app boilerplate.

**Decisions already made (flagged — confirm before PS1):**

1. **The discriminator lives in the content envelope, not the signal `type`.** levee strips the signal `type` on broadcast (Fluid compat — documented in sudoku_lustre.gleam's `SignalReceived` arm), so presence signals are enveloped as `{"kind": "presence", "user": <id>, "payload": <app JSON>}`. We still stamp `signal_type = "presence"` on send for forward compat, but never rely on it inbound. Multiple signal uses per document coexist by `kind`.
2. **JS-first; the erlang runtime's signal gap stays open.** `runtime.gleam:1186` excludes signals from the erlang v1 surface, and presence consumers are browser apps. The core module (PS1) is target-agnostic so an erlang driver can slot in later; wiring signals through the erlang runtime is deferred, not designed here.
3. **The payload codec is a plain pair** (`encode: fn(a) -> Json`, `decode: Decoder(a)`), not a `schema.Field`/`Schema` — those are keyed map codecs; a signal payload is a whole value. If TX1's record builders land first they compose here for free (a record decoder is a `Decoder(a)`).
4. **Library-owned timer FFI.** Heartbeat/prune need `set_timeout`; today every example hand-rolls the FFI. This plan moves it into `watershed_js` (shared with the typed plan's TX4 retry loop — whichever lands first owns the FFI; the other rebases onto it).

## Why this rung

Presence is the first thing every collaborative app adds after shared state, and today it costs what sudoku paid: a 146-line app module (`presence.gleam`) plus wiring spread through the app — heartbeat scheduling in `update` (`Heartbeat` msg re-arming itself), prune-on-heartbeat, self-filtering by user id, the levee type-stripping workaround, and manual decode. The state machine (`observe`/`prune`/`roster`, TTL ≈ 3 missed heartbeats) is entirely generic; only the payload (`cell`, `editing`) is sudoku's. Fluid ships this as a dedicated package because every app needs it; watershed should too.

## PS1 — core module `src/watershed/presence.gleam` (target-agnostic, pure)

Generalize the prototype over an app payload `a`:

```gleam
pub type Peer(a) {
  Peer(user: String, payload: a, last_seen: Int)
}
pub opaque type Peers(a)                       // roster keyed by user id
pub type Config {
  Config(heartbeat_ms: Int, ttl_ms: Int)       // default: 2000 / 6500 (~3 missed beats)
}

pub fn new() -> Peers(a)
pub fn observe(peers: Peers(a), user: String, payload: a, now: Int) -> Peers(a)
pub fn prune(peers: Peers(a), config: Config, now: Int) -> Peers(a)
pub fn roster(peers: Peers(a)) -> List(Peer(a))            // sorted by user id (stable render)
pub fn find(peers: Peers(a), predicate: fn(a) -> Bool) -> List(Peer(a))  // subsumes sudoku's on_cell

// envelope codec (decision 1) — pure, so the erlang driver reuses it later
pub fn encode_envelope(user: String, encode: fn(a) -> Json, payload: a) -> Json
pub fn decode_envelope(decode: Decoder(a)) -> Decoder(#(String, a))  // Error = not a presence signal / foreign kind

// promoted utilities (used by both examples' renderers)
pub fn color_for(user: String) -> String
pub fn short_name(user: String) -> String
```

Tests (`test/watershed/presence_test.gleam`): observe replaces prior entry per user; prune drops exactly the peers past TTL; roster ordering stable; envelope round-trips; `decode_envelope` rejects a non-presence `kind` and malformed payloads (best-effort drop, never crash — signals are unsequenced garbage-tolerant input).

## PS2 — JS driver (`src/watershed/presence_js.gleam` + facade re-export)

Owns the full lifecycle the sudoku app currently spreads across `init`/`update`:

```gleam
pub opaque type Handle(a)

pub fn start(
  document: Document,
  user_id: String,
  config: presence.Config,
  encode encode: fn(a) -> Json,
  decode decode: Decoder(a),
  on_change on_change: fn(List(Peer(a))) -> Nil,
) -> Handle(a)

pub fn announce(handle: Handle(a), payload: a) -> Nil  // update own payload + broadcast now
pub fn stop(handle: Handle(a)) -> Nil                  // cancel timers, drop subscription
```

- `start` subscribes via `subscribe_signals`, decodes with `decode_envelope`, filters `user == user_id`, folds into `Peers(a)`, and calls `on_change` only when the roster actually changed (peers compare equal → silent, so callers can re-render unconditionally).
- Heartbeat timer rebroadcasts the last announced payload every `heartbeat_ms`; the same tick prunes and fires `on_change` on expiry. No announce yet → heartbeats are suppressed (nothing to say).
- Timer FFI (decision 4): `set_timeout`/`clear_timeout` land in `transport_js`'s FFI module (it already owns `nowMs`), exposed via `presence_js` internals — not public API.
- `on_change` is invoked directly (no microtask deferral) — deferral is the Lustre binding's job (`2026-07-06-lustre-integration-plan.md`, LU3), not the driver's.

Tests: driver-level tests need two connected documents — gated on `WATERSHED_INTEGRATION` like the existing integration suite (or ported to the in-memory hub when `2026-07-06-in-memory-hub-plan.md` HM4 lands, which un-gates them: two hub clients exchange presence, TTL expiry observed by advancing the hub clock).

## PS3 — sudoku rewrite (the proof)

`examples/sudoku_lustre` keeps only its payload type and rendering:

```gleam
pub type SudokuPresence {
  SudokuPresence(color: String, name: String, cell: Option(String), editing: Bool)
}
```

Deleted from the app: `presence.gleam`'s state machine + envelope handling, the `Heartbeat` self-rearming msg, `SignalReceived` decode/filter arm, prune wiring. Kept: `broadcast_presence` collapses to `presence_js.announce`; peer rendering reads the roster handed to `on_change`. Exit gate: two-tab manual script (cursors, typing indicator, peer expiry on tab close) matches today's behavior; `smoke.gleam` still passes.

## Deferred

- **Erlang runtime signal support** (decision 2) — small standalone effort when a BEAM consumer needs it: handle the `"signal"` socket event in `runtime.gleam`'s message loop, add `submit_signal` push, port `presence_js`'s driver shape onto a heartbeat process. The PS1 core is already target-agnostic.
- **Sub-presence keys / partial updates** (Fluid's `LatestMap`) — one payload per user is enough until an app outgrows it.
- **Presence over multiple signal kinds** — the `kind` envelope field already reserves the namespace.

## Milestones (one commit each)

| # | Milestone | Exit gate | Commit |
|---|---|---|---|
| PS0 | Plan doc | — | `docs: typed presence plan` |
| PS1 | Core module + unit tests | pure tests green on both targets | `feat(presence): generic peer roster and signal envelope` |
| PS2 | JS driver + timer FFI | gated integration test green | `feat(presence): heartbeat presence driver for the JS facade` |
| PS3 | Sudoku rewrite | manual two-tab script + smoke parity; net-negative app diff | `refactor(examples): sudoku presence on the library driver` |
| PS4 | Docs (module docs, website field-notes mention) | — | `docs: document the presence module` |
