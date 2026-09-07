# Durable document persistence plan — snapshots in IndexedDB, offline-first for real

**Date:** 2026-08-19
**Status (2026-09-06):** shipped in `0614c09`, with later recovery and durability
improvements. DP1-DP5 are implemented: `crdt_js.merge_snapshot`, detached editing,
`persist_js`, `persist_controller_js`, the Lustre `crdt.open` and save effects,
and the notes app integration. DP6 is partially complete: the root, Lustre, and
notes READMEs document the shipped storage model. The current site has no
`structures/offline` page, and `runtime/p2p.astro` does not explain IndexedDB
persistence. That website documentation remains open under the current layout.

**As built:** `persist_js.Storage` provides `get` and an atomic `update`, not
independent get/put calls. Join-before-save runs inside one IndexedDB read-write
transaction, closing the lost-update window accepted by the original decision
5. The boot helper lives in `watershed_lustre/crdt.gleam`. Saving preserves
unreadable bytes; only the explicit `persist_js.replace` recovery operation
overwrites them. The notes app supplies the recovery UI.

DP1-DP5 below record the original design, not pending implementation work.
Snapshot migration, encryption at rest, and sequenced-runtime client persistence
remain outside this plan.

**Builds on:** `2026-08-12-webrtc-p2p-plan.md` (shipped — `export_snapshot`, `import_snapshot`, `attach`, the canonical snapshot format, and the rtc test seam), `2026-08-19-markdown-notes-demo-plan.md` (the consuming app and the PWA shell this completes), `crdt_core.import_snapshot`'s own doc comment ("a snapshot loaded from disk faces exactly the same checks as one that" arrives from a peer — the design already expected this plan).
**Benchmark:** open the notes PWA in airplane mode, edit, close the tab, reopen — the edits are there. Land later, and everything converges.

**Prerequisite work: the notes app's p2p port** (the other follow-on in the notes plan). Persistence ships on the crdt runtime only (decision 1), so the app must be on `crdt_js` before it can use any of this. The runtime-side rungs (DP1–DP4) have no prerequisite and can proceed in parallel with that port.

## What already exists (read before disagreeing with the decisions)

The p2p work built almost the whole loop:

- `crdt_js.export_snapshot(document) -> Result(Json, P2pError)` — the whole document, every channel's full CRDT state, authoring cursors included, in canonical order.
- `crdt_js.import_snapshot(config, snapshot) -> Result(CrdtDocument(root), P2pError)` — rebuilds a document from an exported snapshot, checking size, protocol version, room, compatibility, root type, and per-channel eligibility first. The result is **detached**.
- `crdt_js.attach(document, ...)` — documented as "the way an `import_snapshot` result is put back online." Handles and subscriptions taken before the attach stay valid; the snapshot's channels broadcast to peers through the ordinary `state` exchange.
- `crdt_core.import_snapshot(document, raw)` — the live-document merge, a **join**: local channels and local edits survive it. Not yet exposed on the facade for an already-running document.
- The relay driver (`with_relay_driver`, `RelayPhase`) — the durable online lane once connectivity returns.

At planning time, storage, save triggers, facade-level live merge, and disk-first
boot did not exist. All four now ship in the modules listed above.

## Decisions already made (flagged — confirm before DP1)

1. **Persistence ships on the crdt runtime only.** A snapshot on disk is just another replica: il kinds merge ack-free, so state loaded from IndexedDB and edited offline reconciles like any concurrent peer, and `import_snapshot` is already a join. The sequenced DDS runtime is explicitly out: persisting it means replaying unacked ops against a server order that moved on, and re-deriving LWW outcomes for `SharedMap` roots — a different, much larger plan that may never be worth writing, since the relay plus summaries already give sequenced documents server-side durability. Consequence, stated plainly: durable offline requires the app to be on `crdt_js`. For the notes app that folds the two follow-ons into one sequence — p2p port first, then this — and it dissolves the notes plan's open question about the root `SharedMap` bootstrap slot, because in crdt mode the OR-Map *is* the root and no `SharedMap` exists anywhere.
2. **Storage is IndexedDB behind one small FFI, shipped as an optional watershed module (`watershed/persist_js`).** Two operations: get and put of one string blob keyed by `(room, compatibility)`. Not localStorage — synchronous writes on the UI thread and a ~5MB ceiling against a format whose per-channel cap is already 4MB. No wrapper library; raw IndexedDB at this surface is a few dozen lines of FFI. Shipped in watershed rather than left to app code because the PWA story is a product claim, and every crdt app should get it by adding two calls, not by copying FFI between examples.
3. **Whole snapshots, not op journals.** Each save writes `export_snapshot`'s output entire. `ponytail:` O(document) bytes per save, debounced; an incremental journal is the upgrade path if a real document ever profiles as too large to write in one piece.
4. **The save trigger is app-observable state, not new runtime surface.** Save = debounce after local edits, plus a periodic sweep that fires only when `digest(document)` moved (the digest is cached per document state, so the guard is a string comparison), plus `pagehide`. The sweep is what captures remote edits that arrive while the user idles. No new `on_change` hook in the runtime until something outside this pattern needs one.
5. **Multi-tab safety is atomic join-before-save.** `save` reads the stored blob,
   merges it into the live document via `merge_snapshot`, then exports and writes
   inside one IndexedDB read-write transaction. This supersedes the original
   split read/write sketch: a tab could otherwise overwrite another tab's only
   saved edits and then close before a later merge recovered them. No Web Locks
   or BroadcastChannel is needed for this storage transaction.
6. **Boot order inverts: disk first, network as enhancement.** `load(config)` returning a snapshot yields a ready, editable, detached document immediately — the UI is fully usable before any socket opens. `attach` runs behind it when signaling is reachable, and the relay lane joins when it is. No snapshot on disk and no network is the only state that cannot open a document, and it is the state v1 of the notes app showed for *every* offline reload. This is the sentence that makes "offline first" true rather than aspirational.
7. **Never delete user data automatically.** A stored blob that fails import (protocol mismatch after an upgrade, corrupt read) is kept and the error surfaced; the app decides. Silent eviction of the only copy of someone's offline edits is the one unforgivable failure mode of this feature. Quota errors on write likewise surface to the status callback rather than retry-looping.

## Feature rungs

- **DP1 — `merge_snapshot`.** Facade function over the existing `crdt_core.import_snapshot` for an already-running document: `merge_snapshot(document, snapshot) -> Result(Outcome, P2pError)`, events fanned out to subscribers like any remote merge. Core exists; this is exposure plus tests. Gate: export from replica A, edit replica B, merge A's snapshot into B — both edits present, subscribers fired, digest equal to A-merged-into-B computed the other way around.
- **DP2 — pin detached-document behaviour.** Tests, not code (expected to already work): edits, `create_channel`, and subscriptions on an `import_snapshot` result that was never attached; then `attach` via the rtc seam and assert the detached-era edits broadcast in the `state` exchange. Per house discipline: observe before documenting; whatever fails becomes a fix inside this rung.
- **DP3 — `persist_js`.** The IndexedDB FFI behind a storage seam (an in-memory fake for tests, real IndexedDB in the browser), `load(config)` and `save(document)` with decision 5's join-before-save, keyed per decision 2. Gate: unit tests over the fake covering load-empty, save/load round-trip, join-before-save with a concurrent blob, import-failure surfacing (decision 7); one browser smoke against real IndexedDB.
- **DP4 — the boot helper and Lustre effect.** `open(config, signaling, on_ready, on_status)`: load → ready (detached) → attach in background → relay lane when reachable; falls through to plain `connect` when disk is empty. Plus the `watershed_lustre/crdt.gleam` effect wrapping it, and the save trigger from decision 4 packaged as an effect so Lustre apps get the whole story declaratively. Gate: a sluice-style deterministic test scripting load-offline → edit → attach → converge.
- **DP5 — notes app integration.** After the p2p port: wire `open` and the save effect into `markdown_notes_lustre`, delete the "notes need a connection to open" state the notes plan's MN6 shipped. Gate — the benchmark, verbatim: service worker cache warm, snapshot in IndexedDB, network and relay fully off; reload, edit, reload again, the edit is there; bring the relay up, both an old peer and a fresh one converge, digests equal.
- **DP6 — docs.** The structures/offline page and both READMEs state the new line: crdt documents are durable offline; sequenced documents are durable at the relay. The notes README's three-layer offline story loses its third-layer caveat.

## Testing strategy

- **Deterministic first.** Every behaviour above except real-IndexedDB writes runs under the existing seams: `attach_with_rtc` for transport, the DP3 storage fake for persistence. The reload is simulated by dropping the document and re-`load`ing from the fake — no browser, no timing.
- **Convergence with a reload in the middle** is the headline test: A and B in a room; A saves, "closes" (document dropped), B keeps editing; A re-loads from disk detached, edits offline, attaches; assert both replicas' digests equal and both edit sets present. That single test exercises export, import, detached editing, attach, and join semantics end to end.
- **Digest as the oracle.** Every convergence assertion compares `digest()` across replicas rather than hand-picked values — it is what the anti-entropy protocol itself trusts, and it catches causal-metadata divergence a value comparison would miss.
- **Browser smoke** (DP3/DP5) covers only what the fakes cannot: real IndexedDB, `pagehide`, and the service worker interaction.

## Non-goals

Sequenced-runtime persistence (decision 1). Encryption at rest — IndexedDB inherits the profile's protections; a threat model that needs more needs its own plan. Quota management beyond surfacing errors. Snapshot migration across protocol versions — decision 7 keeps the bytes; converting them is future work when a version bump actually happens. Cross-device sync through storage — that is the relay's job, not the disk's.
