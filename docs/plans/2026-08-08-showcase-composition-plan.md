# Showcase composition plan — many demos, one document

**Date:** 2026-08-08
**Builds on:** `2026-07-06-typed-layer-dx-plan.md` (the `ChildField` machinery this rests on), `2026-08-03-shared-textarea-component-plan.md` (the nested-MVU contract, shipped), `examples/text_lustre` + `examples/playlist_lustre` + `examples/sudoku_lustre` (the panels).
**Benchmark:** the Liveblocks / PartyKit examples galleries. Both are *lists of separate apps*. A single document whose panels are separate apps sharing one connection and one presence roster is a stronger claim than either, and it is the claim watershed's typed layer is actually built to support.

**Prerequisite work: none required, one recommended.** Every API this needs exists on `watershed_js` and `watershed_lustre` today; the work is refactoring the examples, not extending the library. But this is the first app in the repo with more than one schema tag in play, which makes it the first place the untagged root does real damage — see `2026-08-08-document-root-tag-plan.md` (DR1–DR6), best landed before SC1. If it isn't, SC7's root-purity test is the stopgap.

## Decisions already made (flagged — confirm before SC1)

1. **Compose by nesting under `ChildField`, never by sharing the root.** `schema.child_field` (`src/watershed/schema.gleam:95`) declares a key whose value is a handle to a nested typed map carrying a *different* phantom tag; `ensure_child` (`src/watershed.gleam:1324`, effect form at `watershed_lustre/src/watershed_lustre.gleam:614`) bootstraps it. Each demo's existing `doc_schema.gleam` then works unchanged against its child map, because those fields were always scoped to the demo's own tag rather than to "the root".
2. **Only the showcase schema may touch the root map.** Today this is a discipline, not a type-system guarantee: `root_typed` is generic in the tag (`src/watershed.gleam:420`), so it will hand out a `TypedMap(PlaylistDoc)` *and* a `TypedMap(SudokuDoc)` for the same physical root map with no error. Two demos mounted at the root share one key namespace silently. `2026-08-08-document-root-tag-plan.md` makes it a compile error; until that lands, SC7's root-purity test is what catches a regression.
3. **Each demo becomes a nested MVU triple in its own package, and stays standalone-runnable.** `init(Document, TypedMap(Tag)) -> #(Model, Effect(Msg))`, `update`, `view` — the contract `watershed_lustre/textarea.gleam` already documents at its module head (lines 16–38) and already proves in production. Each example keeps its `main`, reduced to connect + `root_typed` + mount. The showcase depends on the demo packages by path, the way the examples already depend on `watershed` and `watershed_lustre` (`examples/playlist_lustre/gleam.toml`).
   *Rejected:* vendoring demo sources into one showcase package. It duplicates code, and it destroys the property that makes the examples useful — that each is a small readable app you can run on its own.
4. **One presence driver for the whole document, owned by the shell.** Not optional — see "Presence does not compose by itself" below. Panels receive their peers from the shell.
5. **Child maps are ensured eagerly; components are initialised lazily.** The shell batches every `ensure_child` on `GotHandle` so the document's shape is declarative in one place; a panel's `init` runs the first time that panel is opened, so an unopened panel holds no subscriptions.
6. **v1 panels: text, playlist, sudoku, dice.** Text first (its editor is already a component, so it tests the contract at the lowest risk), then playlist (sequence), then sudoku (the heaviest — claims, OR-set, counter, nested map, presence), then dice (untyped `SharedMap`, the proof that composition is not a typed-layer-only trick). `bench_book_lustre` is deliberately out: it is a benchmark harness, not a demo.

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
pub fn dice() -> ChannelField(Showcase, schema.MapChannel) {
  schema.channel_field("dice")   // untyped — dice never had a schema
}
```

Note the root cannot be described by a record `Schema`: `prop` takes a `Field(s, a)` (`src/watershed/schema.gleam:390`) and there is no `ChildField` equivalent, so `sealed_known` is unavailable here and `sealed` would need a hand-rolled `schema(...)` with an empty record. Not worth it — SC7's test asserts root purity directly instead.

## Four hazards, each verified in the code

**Dice's clear button deletes the whole showcase.** `examples/dice_lustre/src/dice_lustre.gleam:182` calls `watershed_js.clear(watershed_js.root(doc))`. Composed, that wipes every child handle in the root map — all four panels, in one click. Dice's `snapshot` (`:198–212`) also renders `entries(root)` as an inspector table, which composed would display the showcase's own handles rather than dice's state. Both are fixed by the same change (take a `SharedMap`, don't reach for the root), and both are worth keeping in the README as the concrete illustration of why decision 2 exists.

**Presence does not compose by itself.** `watershed_lustre.presence` (`:681`) takes a `Document` and a single payload codec, with no topic parameter, and every driver broadcasts under the one global `presence.ripple_type = "presence"` (`src/watershed/presence.gleam:23`). Two panels each starting a driver means each receives the other's envelopes; the `kind` check passes because the constant is shared, and only the *payload* decoder rejects them — silently (`src/watershed/presence_js.gleam:114–140`). Best case each panel sees a partial roster; worst case a lenient decoder accepts a foreign payload and invents a peer. Hence decision 4: one driver, a `ShowcasePresence` sum type with a variant per panel, and the shell handing each panel its filtered peers. `textarea.set_peers` (`watershed_lustre/src/watershed_lustre/textarea.gleam:889`) is the precedent for pushing peers into a child component.

**Ripples are document-scoped.** `subscribe_ripples` takes a `Document`, not a channel (`src/watershed_js.gleam:2825` onward), so any panel subscribing gets every panel's ripples. Panels that use ripples directly must namespace their `type` tag (`showcase:sudoku:cursor`), which is what `presence.gleam:20–22` means by "multiple ripple uses per document coexist by `kind`".

**The cold-document ensure race gets N times more likely.** `ensure_channel` (`src/watershed.gleam:981–996`) checks for the key and, if absent, creates and sets — so two tabs opening a brand-new document both create a child map, and LWW settles one handle while the other is orphaned. This race exists in every current example; the showcase runs it four times per cold start. It converges (all tabs agree afterwards), and the loss window is sub-second and before any user interaction, so the plan accepts it rather than inventing a bootstrap protocol — but the README should say so, and SC7's convergence test should assert that two clients racing a cold document land on the *same* four child handles.

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

- **SC1 — the shell.** New `examples/showcase_lustre/` on the `playlist_lustre` template (its own `gleam.toml`, `package.json`, `build.mjs`, `index.html`; `justfile` install/build stanzas alongside the existing four). `doc_schema.gleam` as above; `connect_dev`; all four ensures batched on `GotHandle`; a panel switcher rendering placeholder panels. Gate: two tabs connect, and `entries(root)` on both is exactly the four declared keys, each resolving to a map.
- **SC2 — extract the text panel, and with it the contract.** Split `text_lustre.gleam` into `text_lustre/component.gleam` (the triple) and a thin `main`. Gate: the standalone example's build and smoke test pass **unchanged**, and the showcase's text panel converges across two tabs. This is the rung that can go wrong quietly — if the contract is wrong here, SC3–SC6 repeat the mistake four times, so do not start SC3 until the standalone smoke test is green.
- **SC3 — playlist panel.** Same split. `playlist_lustre.gleam:141`'s `root_typed` call is the only root-bound line. Gate: reorder in one tab, follows in the other, with the panel nested.
- **SC4 — sudoku panel.** The heaviest: claims, OR-set, counter, and a nested `MapChannel` under a child map (a grandchild — worth confirming explicitly that the depth works). Presence stays *disabled* in this rung; SC5 restores it. Gate: two tabs play the same puzzle from within the showcase.
- **SC5 — one presence driver.** `ShowcasePresence` sum type in the shell, one `watershed_lustre.presence` call, per-panel filtering, and a roster in the shell chrome showing who is in which panel. Text and sudoku lose their own drivers. Gate: two tabs on *different* panels each see the other in the roster, with the correct panel label — the thing four separate apps cannot do.
- **SC6 — dice panel, and the destructive-clear fix.** Re-point dice at its own `SharedMap`; `clear` now clears dice. Gate: dice's clear leaves the other three panels intact — assert it, don't eyeball it.
- **SC7 — root purity test + convergence test + README.** See below.
- **SC8 — standalone parity.** All four examples still build, run, and pass their smoke tests alone; `just build` covers the showcase. Regenerate each touched example's `manifest.toml` — per-package manifest drift silently breaks the path deps, and it has bitten this repo before.

## Testing strategy

- **Root purity test.** Read `entries(root)` after full bootstrap and assert the key set equals the four declared child keys. This is the mechanical detector for decision 2, and it is the test that fails the day someone reaches for `root_typed` inside a panel.
- **Cold-document race test.** Two in-process clients over `sluice`, both bootstrapping a fresh document simultaneously; assert both converge on an identical set of four child handles.
- **Per-panel convergence tests**, two clients, one per panel, exercising the same claim each standalone example already makes — run against the *nested* map, to prove nesting changed nothing.
- **Presence test.** Two clients on different panels; assert each sees the other with the correct panel variant. Add a negative case: a malformed foreign envelope produces no phantom peer.
- **Dice isolation test.** Clear dice; assert the other three child handles still resolve.
- **Unchanged per-example smoke tests**, which are the standalone-parity gate for SC8.

## What this does not do

No cross-panel *data* sharing — the panels share a connection, a roster, and a document tree, not state. A cell in sudoku does not affect the playlist, and pretending otherwise would need a story about cross-channel transactions that watershed does not have and this plan should not imply. The showcase's claim is composition of independent collaborative apps, which is a real and sufficient claim on its own.
