# Showcase composition plan — many demos, one document

**Status: shipped 2026-08-10.** SC0–SC8 all landed in `examples/showcase_lustre/`.

**Date:** 2026-08-08
**Builds on:** `2026-07-06-typed-layer-dx-plan.md` (the `ChildField` machinery this rests on), `2026-08-03-shared-textarea-component-plan.md` (the nested-MVU contract, shipped), `examples/text_lustre` + `examples/playlist_lustre` + `examples/sudoku_lustre` + `examples/pixel_canvas_lustre` (the panels).

**Amended 2026-08-10:** the fourth panel is the pixel canvas, not dice. Rationale in decision 6; dice and the drum machine are both deferred to v2 at the end of this plan, and the canvas's own hazards replace dice's destructive-clear hazard below.
**Benchmark:** the Liveblocks / PartyKit examples galleries. Both are *lists of separate apps*. A single document whose panels are separate apps sharing one connection and one presence roster is a stronger claim than either, and it is the claim watershed's typed layer is actually built to support.

**Prerequisite work: none required, one recommended.** Every API this needs exists on `watershed_js` and `watershed_lustre` today; the work is refactoring the examples, not extending the library. But this is the first app in the repo with more than one schema tag in play, which makes it the first place the untagged root does real damage — see `2026-08-08-document-root-tag-plan.md` (DR1–DR6), best landed before SC1. If it isn't, SC7's root-purity test is the stopgap.

## Decisions already made (flagged — confirm before SC1)

1. **Compose by nesting under `ChildField`, never by sharing the root.** `schema.child_field` (`src/watershed/schema.gleam:95`) declares a key whose value is a handle to a nested typed map carrying a *different* phantom tag; `ensure_child` (`src/watershed.gleam:1324`, effect form at `watershed_lustre/src/watershed_lustre.gleam:614`) bootstraps it. Each demo's existing `doc_schema.gleam` then works unchanged against its child map, because those fields were always scoped to the demo's own tag rather than to "the root".
2. **Only the showcase schema may touch the root map.** Today this is a discipline, not a type-system guarantee: `root_typed` is generic in the tag (`src/watershed.gleam:420`), so it will hand out a `TypedMap(PlaylistDoc)` *and* a `TypedMap(SudokuDoc)` for the same physical root map with no error. Two demos mounted at the root share one key namespace silently. `2026-08-08-document-root-tag-plan.md` makes it a compile error; until that lands, SC7's root-purity test is what catches a regression.
3. **Each demo becomes a nested MVU triple in its own package, and stays standalone-runnable.** `init(Document, TypedMap(Tag)) -> #(Model, Effect(Msg))`, `update`, `view` — the contract `watershed_lustre/textarea.gleam` already documents at its module head (lines 16–38) and already proves in production. Each example keeps its `main`, reduced to connect + `root_typed` + mount. The showcase depends on the demo packages by path, the way the examples already depend on `watershed` and `watershed_lustre` (`examples/playlist_lustre/gleam.toml`).
   *Rejected:* vendoring demo sources into one showcase package. It duplicates code, and it destroys the property that makes the examples useful — that each is a small readable app you can run on its own.
4. **One presence driver for the whole document, owned by the shell.** Not optional — see "Presence does not compose by itself" below. Panels receive their peers from the shell.
5. **Child maps are ensured eagerly; components are initialised lazily, and never torn down.** The shell batches every `ensure_child` on `GotHandle` so the document's shape is declarative in one place; a panel's `init` runs the first time that panel is opened, so an unopened panel holds no subscriptions. Once opened, a panel's `Model` is retained for the life of the session — switching away hides its `view`, it does not destroy it. That was incidental with dice; with the canvas it is essential, because the panel's `Model` owns the FFI pixel buffer (`canvas.gleam:48`) and dropping it would discard every painted cell the panel has seen.
6. **v1 panels: text, playlist, sudoku, pixel canvas.** Text first (its editor is already a component, so it tests the contract at the lowest risk), then playlist (sequence), then sudoku (the heaviest — claims, OR-set, counter, nested map, presence), then the pixel canvas. The canvas earns the fourth slot on four counts:
   - **It is the cheapest port in the repo.** One root-bound line — `root_typed` at `pixel_canvas_lustre.gleam:156` — and no presence driver to unwind, no `auto_summarize` call, no ripple type to namespace, no `clear(root)`. Its rung is a near-copy of SC3.
   - **It fills the one real gap in kernel coverage.** Text/playlist/sudoku cover Text, Sequence, Map, OrSet, Claims, and Counter between them. `OrMap` in register mode is the major family none of them touch, and `doc_schema.gleam:6–14` argues the choice explicitly against both `SharedMap` and `PactMap`.
   - **It is legible at a glance.** A showcase panel gets five seconds of attention, and a canvas filling in under someone else's cursor makes the convergence argument with no caption. Nothing else in the repo is as immediately readable.
   - **It is the best SC5 demo.** No driver exists here today, so the shell adding one is pure gain rather than an unwind, and per-peer cursors on a shared grid are the most vivid available form of "Tyler is in the canvas".

   `bench_book_lustre` is deliberately out: it is a benchmark harness, not a demo.

   *Cost of the swap, stated plainly:* v1 now has no consensus-gated panel and no untyped child. Neither claim is abandoned — both are recorded as v2 panels at the end of this plan, with the drum machine carrying consensus and dice carrying the untyped mount.
7. **Document-scoped effects are shell-owned, without exception.** Presence (decision 4) was the first instance; the canvas's offline toggle is the one that forces the rule, and `auto_summarize` generalises it. Anything whose API takes a `Document` rather than a channel belongs to the shell, and a panel that calls one is a bug the same way `root_typed` in a panel is a bug.

## What composition actually buys

Four panels in four browser tabs is a gallery. Four panels in *one document* is an argument:

- **One connection, one handshake, four collaborative apps.** The panel switcher is instant because nothing reconnects.
- **One presence roster across all of them** — "Tyler is in the sudoku panel" is a thing you can only say once presence is document-wide, and it is the single most legible payoff here.
- **The document is a tree, and the tree is typed.** The root is a map of handles to sub-documents, each with its own schema and its own decode boundary. That is the pitch for the typed layer, demonstrated instead of asserted.

## Data model

```gleam
// examples/showcase_lustre/src/doc_schema.gleam
pub type Showcase

pub fn text() -> ChildField(Showcase, text_schema.TextDoc) {
  schema.child_field("text")
}
pub fn playlist() -> ChildField(Showcase, playlist_schema.PlaylistDoc) {
  schema.child_field("playlist")
}
pub fn sudoku() -> ChildField(Showcase, sudoku_schema.SudokuDoc) {
  schema.child_field("sudoku")
}
pub fn canvas() -> ChildField(Showcase, canvas_schema.CanvasDoc) {
  schema.child_field("canvas")
}
```

All four are `ChildField`s now — with dice deferred, v1 has no untyped slot, and the root is uniformly a map of handles to typed sub-documents.

The canvas's `pixels` `OrMapChannel` becomes a *grandchild* under its child map, the same depth claim SC4 makes for sudoku's nested `MapChannel`. The two panels now corroborate each other on it rather than only one carrying it, and they do it with different kinds, which is the stronger version of the claim.

Note the root cannot be described by a record `Schema`: `prop` takes a `Field(s, a)` (`src/watershed/schema.gleam:390`) and there is no `ChildField` equivalent, so `sealed_known` is unavailable here and `sealed` would need a hand-rolled `schema(...)` with an empty record. With every root key now a child field, there is no record to describe at all. SC7's test asserts root purity directly instead.

## Seven hazards, each verified in the code

**The canvas's offline toggle disconnects the whole showcase.** `watershed_lustre.go_offline` takes a `Document` (`:704`), not a channel, and the canvas wires a button straight to it (`pixel_canvas_lustre.gleam:217–222`, button at `:421`). Composed, "Go offline" stops sync for every panel at once — the same blast radius dice's `clear(root)` had, arriving through a completely different door. That symmetry is the point: the failure mode is not "dice was badly written", it is "a panel-level control with a document-level API".
The fix is *not* to scope it down, because it cannot be scoped down — the connection is per-document and always was. The fix is to promote it: the offline toggle moves into the shell chrome and is labelled as what it is, a document-wide control. This makes the demo better rather than merely safer. Standalone, the toggle proves that one `OrMap` converges by join after a partition (`pixel_canvas_lustre.gleam:16–20`); in the shell, one click partitions all four panels, and coming back online converges a text buffer, a sequence, a claims grid, and an OR-map together. Decision 7 exists mostly to make this move mandatory rather than clever.

**Diagnostics read the document, so they belong to the shell too.** `watershed_js.diagnostics(doc)` (`pixel_canvas_lustre.gleam:140`, `:203`) reports the runtime's phase and in-flight count for the *whole* document. The canvas footer renders it as "offline, N waiting" (`:446–451`), which composed would attribute every panel's queued ops to the canvas. Harmless — it is a read, not a write — but wrong on screen, and it moves to the chrome alongside the toggle it explains.

**`auto_summarize` is one policy per document, and the last caller wins.** `watershed_js.auto_summarize` (`src/watershed_js.gleam:3039`) calls `runtime_js.auto_summarize(runtime, Some(policy))` — a slot, not a list. No v1 panel calls it today, but two examples do (`drum_machine_lustre.gleam:299`, `retro_board_lustre.gleam:312`), so any future panel promoted from those would set the policy for the entire showcase, and with lazy init (decision 5) *which* policy wins would depend on the order the user happened to click panels. Non-deterministic behaviour driven by UI navigation is the worst kind to debug. The shell makes exactly one `auto_summarize` call and adopts the drum machine's threshold of 200: that number was chosen because a jam writes one op per step toggle, and the canvas — which `doc_schema.gleam:31–33` calls "the one example that emits ops by the thousand" — has strictly more reason to want it.

**The canvas sets the log's pace for every panel.** A painting session emits ops at a rate nothing else in v1 approaches, and the showcase puts those ops in the same log as the text buffer and the playlist. A joiner who only wants to read the playlist still replays the canvas's history to get there, which is exactly the cost the summary bootstrap work exists to bound (`2026-08-09-summary-bootstrap-plan.md`). Two consequences worth stating rather than discovering: the shell's `auto_summarize` is essential, not decorative; and the cold-join measurement in SC7 should be taken with the canvas painted, because a measurement on an empty canvas measures nothing.

**Presence does not compose by itself.** `watershed_lustre.presence` (`:681`) takes a `Document` and a single payload codec, with no topic parameter, and every driver broadcasts under the one global `presence.ripple_type = "presence"` (`src/watershed/presence.gleam:23`). Two panels each starting a driver means each receives the other's envelopes; the `kind` check passes because the constant is shared, and only the *payload* decoder rejects them — silently (`src/watershed/presence_js.gleam:114–140`). Best case each panel sees a partial roster; worst case a lenient decoder accepts a foreign payload and invents a peer. Hence decision 4: one driver, a `ShowcasePresence` sum type with a variant per panel, and the shell handing each panel its filtered peers. `textarea.set_peers` (`watershed_lustre/src/watershed_lustre/textarea.gleam:889`) is the precedent for pushing peers into a child component.

**Ripples are document-scoped.** `subscribe_ripples` takes a `Document`, not a channel (`src/watershed_js.gleam:2825` onward), so any panel subscribing gets every panel's ripples. Panels that use ripples directly must namespace their `type` tag (`showcase:sudoku:cursor`), which is what `presence.gleam:20–22` means by "multiple ripple uses per document coexist by `kind`".

**The cold-document ensure race gets N times more likely.** `ensure_channel` (`src/watershed.gleam:981–996`) checks for the key and, if absent, creates and sets — so two tabs opening a brand-new document both create a child map, and LWW settles one handle while the other is orphaned. This race exists in every current example; the showcase runs it four times per cold start at the root, and the grandchildren race too — sudoku ensures four channels of its own and the canvas one, though those only start once the parent handle has settled, so they are the same race one level down rather than a new one. It converges (all tabs agree afterwards), and the loss window is sub-second and before any user interaction, so the plan accepts it rather than inventing a bootstrap protocol — but the README should say so, and SC7's convergence test should assert that two clients racing a cold document land on the *same* four child handles.

## Component contract (SC2 defines it once, SC3–SC6 follow it)

```gleam
// in the shell's update:
PanelOpened(Text) -> {
  let #(panel, fx) = text_component.init(doc, model.text_map)
  #(Model(..model, text: Some(panel)), effect.map(fx, TextMsg))
}
TextMsg(inner) -> {
  let #(panel, fx) = text_component.update(panel, inner)
  #(Model(..model, text: Some(panel)), effect.map(fx, TextMsg))
}

// in the shell's view:
text_component.view(panel) |> element.map(TextMsg)
```

The demo's `main` keeps working by calling the same triple against `root_typed(doc)` — the standalone app is the showcase with one panel and no shell.

## Rungs

- **SC0 — namespace the example modules.** *Not in the original plan; discovered
  at the first `gleam build`.* Gleam requires globally unique module names
  across the whole dependency graph, and all four panels shipped
  `src/doc_schema.gleam` *and* `src/smoke.gleam`. A package depending on two of
  them fails with "the module `smoke` is defined multiple times", which blocks
  SC1 before it starts. Every shared-name module moved under `src/<package>/`
  (doc_schema, smoke + its FFI, track, puzzles, canvas + its FFI, grid), imports
  rewritten, and the two `build:smoke` esbuild paths moved down a directory.
  Nothing about the plan's design changed — it is a prerequisite, not a
  revision — but any future v2 panel needs the same move first.
- **SC1 — the shell.** New `examples/showcase_lustre/` on the `playlist_lustre` template (its own `gleam.toml`, `package.json`, `build.mjs`, `index.html`; `justfile` install/build stanzas alongside the existing examples). `doc_schema.gleam` as above; `connect_dev`; all four ensures batched on `GotHandle`; a panel switcher rendering placeholder panels. Gate: two tabs connect, and `entries(root)` on both is exactly the four declared keys, each resolving to a map.
- **SC2 — extract the text panel, and with it the contract.** Split `text_lustre.gleam` into `text_lustre/component.gleam` (the triple) and a thin `main`. Gate: the standalone example's build and smoke test pass **unchanged**, and the showcase's text panel converges across two tabs. This is the rung that can go wrong quietly — if the contract is wrong here, SC3–SC6 repeat the mistake four times, so do not start SC3 until the standalone smoke test is green.
- **SC3 — playlist panel.** Same split. `playlist_lustre.gleam:141`'s `root_typed` call is the only root-bound line. Gate: reorder in one tab, follows in the other, with the panel nested.
- **SC4 — sudoku panel.** The heaviest: claims, OR-set, counter, and a nested `MapChannel` under a child map (a grandchild — worth confirming explicitly that the depth works). Presence stays *disabled* in this rung; SC5 restores it. Gate: two tabs play the same puzzle from within the showcase.
  *As built:* sudoku had **two** root-bound lines, not one. Besides bootstrap, `puzzle_from_root` re-read the puzzle id off `root_typed` on every snapshot — composed, that would look the id up in a map holding four panel handles. Worth checking every panel for reads as well as writes, not just for its `ensure_*` batch.
- **SC5 — one presence driver.** `ShowcasePresence` sum type in the shell, one `watershed_lustre.presence` call, per-panel filtering, and a roster in the shell chrome showing who is in which panel. Text and sudoku lose their own drivers. The `ShowcasePresence` variant for the canvas carries a cursor cell and the peer's current palette index, which is what SC6 renders. Gate: two tabs on *different* panels each see the other in the roster, with the correct panel label — the thing four separate apps cannot do.
- **SC6 — canvas panel, and the offline toggle's promotion.** The mechanical split is the smallest of the four: `root_typed` (`pixel_canvas_lustre.gleam:156`) is the only root-bound line, and the `OrMap` bootstrap under it moves down unchanged. What is not mechanical is subtraction — the offline toggle (`:217–222`, `:421`) and the diagnostics footer (`:140`, `:203`, `:446–451`) leave the panel for the shell chrome, because both describe the document and neither can be scoped to a channel. The panel keeps the palette, the grid, and the FFI buffer; it gains peer cursors from SC5. Gate: paint in two tabs and both converge, with the panel nested. Second gate, and the one worth demoing: go offline from the chrome, paint in one tab while reordering the playlist in the other, come back — all four panels converge, and the canvas converges by join with no rebase.
- **SC7 — root purity test + convergence tests + cold-join measurement + README.** See below. The measurement: paint the canvas heavily, then time a fresh client's join with and without the shell's `auto_summarize` policy in force. It is one number, it is the number that justifies the policy, and taking it on an empty canvas would measure nothing.
- **SC8 — standalone parity.** All four examples still build, run, and pass their smoke tests alone; `just build` covers the showcase. Regenerate each touched example's `manifest.toml` — per-package manifest drift silently breaks the path deps, and it has bitten this repo before.

## Testing strategy

- **Root purity test.** Read `entries(root)` after full bootstrap and assert the key set equals the four declared child keys. This is the mechanical detector for decision 2, and it is the test that fails when someone uses `root_typed` inside a panel.
- **Cold-document race test.** Two in-process clients over `sluice`, both bootstrapping a fresh document simultaneously; assert both converge on an identical set of four child handles.
- **Per-panel convergence tests**, two clients, one per panel, exercising the same claim each standalone example already makes — run against the *nested* map, to prove nesting changed nothing.
- **Presence test.** Two clients on different panels; assert each sees the other with the correct panel variant. Add a negative case: a malformed foreign envelope produces no phantom peer.
- **Partition-convergence test.** Two clients; take one offline through the shell control, then write to *every* panel on both sides — text, playlist, sudoku, canvas — and reconnect. Assert all four converge. This is the test the canvas earns its slot with: standalone it would only cover one `OrMap`, and composed it covers four kernels crossing one partition in a single scenario. Assert the blast radius explicitly too, so that a future panel-local offline button fails here: while one client is offline, its *other* panels must also stop receiving.
- **Summarize-ownership test.** Open the panels in both orders and assert the document's effective policy is identical — the assertion that no panel installs its own.
- **Unchanged per-example smoke tests**, which are the standalone-parity gate for SC8. The canvas's smoke test (`examples/pixel_canvas_lustre/src/smoke.gleam`) drives the offline path itself against two documents, so it keeps passing untouched; the control it exercises simply no longer has a button inside the component.

Rendering has no automated gate. The pixel buffer is FFI-owned (`canvas.gleam:1–9`) and the canvas element is drawn to rather than diffed, so "the pixels are right" is not assertable from a smoke test — what the tests can assert is the `OrMap` state behind them, which is what the convergence tests do. SC6's visual check is manual and should say so in the README.

## Deferred: v2 panels

Each of these carries a claim v1 does not make. They are recorded rather than dropped, and each is one root key plus one rung — the contract SC2 defines does not change for any of them.

**Dice — the untyped child.** The one example with no `doc_schema.gleam`, mounted on a bare `SharedMap`, which is what proves composition is not a typed-layer-only trick:

```gleam
pub fn dice() -> ChannelField(Showcase, schema.MapChannel) {
  schema.channel_field("dice")   // untyped — dice never had a schema
}
```

Its rung is a bug fix, not a port. `examples/dice_lustre/src/dice_lustre.gleam:182` calls `watershed_js.clear(watershed_js.root(doc))`: composed, that wipes every child handle in the root map — every panel, in one click. Its `snapshot` (`:198–212`) renders `entries(root)` as an inspector table, which composed would show the showcase's own handles rather than dice's state. One change fixes both (take a `SharedMap`, never access the root), and the isolation test is obvious: clear dice, assert the other child handles still resolve. It remains the sharpest illustration of why decision 2 exists.

**Drum machine — the consensus panel.** The only example whose state is quorum-gated, and therefore the only one where composition changes semantics rather than wiring. Three things follow from nesting it, all verified:

- The quorum silently becomes document-wide. `pact_map_kernel` emits an owed `Accept` (`src/watershed/pact_map_kernel.gleam:170`), `channel.gleam:743` turns it into a follow-up op, and `runtime_core.collect_released_ops` (`:844`) drains it inside the actor loop — a path driven by op application alone, needing no subscription, no handle, and no open panel. So every client in the showcase auto-signs the BPM proposal, including people who only ever opened the text panel. The pact still settles; what breaks is the copy at `drum_machine_lustre.gleam:880–890`, where "waiting on 1 of 3 clients" now counts the whole document.
- A wedged tab in another panel delays a tempo change until it acks or the roster drops it (`drum_machine_lustre.gleam:165–169`). This is the one place composition genuinely costs something.
- Its signoff list renders hashed client ids (`:594–605`), which do not match the presence roster's user ids — two disagreeing "who is here" lists side by side. The fix is also the payoff: carry `watershed_js.client_id` in the presence payload and the shell can hand the panel a client-id → name map, turning "not yet acknowledged: client 274880073" into "not yet acknowledged: Tyler". No standalone panel can do that.

Its `audio.Engine` and `#playhead` subtree also make decision 5's retention rule essential in a second way — a dropped panel would leak an `AudioContext` and a `requestAnimationFrame` loop with no handle to stop either.

**Work queue — the most kernel coverage per panel.** `OrderedCollection` + `TaskManager` (consensus dispatch) + `Sequence`, plus the "what happens when a worker dies" story. Its presence use is only the pure `short_name`/`color_for` helpers, so there is no driver to unwind. The runner-up for the v1 slot; it lost on legibility, not on substance.

**Retro board — the highest port cost, the least new ground.** Two `OrMap`s and three `Sequence`s, so it duplicates playlist's kind three times and the canvas's once, and it brings both a real presence driver to fold into `ShowcasePresence` and an `auto_summarize` call to surrender. Worth doing once the shell's presence machinery has settled, not before.

**Grocery triptych — ruled out, not deferred.** It is a teaching exhibit rather than an app: it drives scripted scenarios over its own ripple protocol (`scenario_protocol.gleam:6`), which lands directly on the document-scoped ripple hazard above, and its `OrSet` is already covered by sudoku. GSet and TwoPSet are contrast material, not something anyone sits inside.

## What this does not do

No cross-panel *data* sharing — the panels share a connection, a roster, and a document tree, not state. A cell in sudoku does not affect the playlist, and pretending otherwise would need a story about cross-channel transactions that watershed does not have and this plan should not imply. The showcase's claim is composition of independent collaborative apps, which is a real and sufficient claim on its own.
