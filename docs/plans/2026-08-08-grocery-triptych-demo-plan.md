# Grocery triptych demo plan — three set kinds, one interaction, three outcomes

**Date:** 2026-08-08
**Builds on:** `2026-07-06-lustre-integration-plan.md` (LU1–LU3), `docs/plans/2026-08-08-facade-parity-sweep-plan.md` (FP5 — the `watershed_lustre` fill-in this demo needs).
**Benchmark:** none, deliberately. Every other demo in `examples/` imitates a product. This one imitates a **textbook figure** — the side-by-side comparison that CRDT papers draw and that no CRDT library ever ships as running code.

**Prerequisite:** `watershed_lustre` lacks `ensure_g_set` / `subscribe_g_set` / `ensure_two_p_set` / `subscribe_two_p_set` (facade-parity plan, FP5). They exist on `watershed_js`, so the gap is one thin rung, carried here as GT1. An earlier note claimed this demo had zero prerequisites; that was wrong.

## Decisions already made (flagged — confirm before GT1)

1. **Three panels, one input, genuinely identical interaction.** A single "add item" field and a single item list rendered three times. Every user action is dispatched to **all three** channels simultaneously — one `Msg`, three writes. This is the whole design: if the panels diverge, it cannot be because they were driven differently. The panels are a controlled experiment, and the shared input is the control.
2. **Same document, three channels, not three documents.** `GSet`, `TwoPSet`, and `OrSet` channels on one root typed map. Same ordering, same connection, same reconnect behaviour — the *only* variable is the kind.
3. **Divergence is celebrated, not smoothed.** Where the panels differ they are visually marked (a badge on the item, a diff count in the panel header). The demo's output is the difference; hiding it with tasteful uniform styling would destroy the artifact.
4. **Every panel explains itself in place.** Each panel header states its kind's rule in one line, and each *blocked* action states why it was blocked at the moment it is attempted. A reader must never have to consult a legend to understand what they just saw.
5. **No presence, no ordering, no persistence beyond the document.** Every feature not in service of the comparison is a distraction. This is the smallest example in the repo and should stay that way.

## Why this demo

The three set kinds differ in exactly one dimension — what removal means — and that difference is invisible in any single-panel app. Read separately, each behaves sensibly, and a reader concludes the three are interchangeable and picks by name. The cost of that mistake is a production data model that cannot re-add a removed item, discovered months later.

Set side by side, the difference is a five-second demo:

> Add "milk" to all three. Remove it from all three. Add it back.
> **G-Set:** never removed it — it is still there, and the remove button was disabled with "grow-only sets have no remove".
> **2P-Set:** removed it, and *refuses to re-add it* — tombstoned forever.
> **OR-Set:** removed it, re-added it, present. Behaves the way you assumed all three would.

That is a complete education in observed-remove semantics with no prose and no diagram. And it earns trust by showing where the toolkit's own primitives will bite you — the "rigor is content" principle in `PRODUCT.md` applied to something less comfortable than a passing test count.

Secondarily: it clears three no-demo kinds in one small app, and it is the only planned demo where **concurrent add/remove of the same element** is the subject rather than an edge case.

## Screen

```
┌─ shared controls ───────────────────────────────────────────┐
│  [ item name          ]  (Add to all three)                 │
│  Preset scenarios:  [Tombstone]  [Concurrent add/remove]    │
└─────────────────────────────────────────────────────────────┘
┌── G-Set ─────────┐┌── 2P-Set ────────┐┌── OR-Set ──────────┐
│ add-only; remove ││ remove is        ││ remove affects only│
│ is not expressible││ permanent       ││ observed adds      │
│                  ││                  ││                    │
│ • milk           ││ • milk    [x]    ││ • milk      [x]    │
│ • eggs      ⚠    ││   (removed)      ││ • eggs             │
│ • bread          ││ • bread   [x]    ││ • bread     [x]    │
│                  ││                  ││                    │
│ 3 items          ││ 2 items  ·1 diff ││ 3 items            │
└──────────────────┘└──────────────────┘└────────────────────┘
```

The `⚠` marks an item whose presence differs from the other panels — the visual payload of decision 3. Remove buttons are per-panel and per-item, but the primary flow uses the shared control so all three receive the same op.

**Per-panel action feedback.** Attempting a blocked action reports the kind's rule inline and transiently:
- G-Set: the remove control is rendered disabled with "grow-only — remove is not expressible", not hidden. An absent button teaches nothing; a disabled one with a reason teaches the constraint.
- 2P-Set: re-adding a tombstoned element is accepted by the API and has no effect. The panel must detect this — compare `two_p_set_contains` after the add — and surface "re-add ignored: `milk` is tombstoned". **This is the single most important message in the demo**, because it is the only failure that is otherwise completely silent.
- OR-Set: no blocked actions. Its panel header notes it is the one you probably want.

## Data model

```gleam
pub type Pantry

pub const grow_only:  ChannelField(Pantry, schema.GSetChannel) = ...
pub const two_phase:  ChannelField(Pantry, schema.TwoPSetChannel) = ...
pub const observed:   ChannelField(Pantry, schema.OrSetChannel) = ...
```

All three kinds hold `String` elements, so the item name is the element — no encoding layer, which keeps the comparison free of anything that could be blamed for a difference.

Available ops (all present on both facades):

| | add | remove | contains | values | subscribe |
|---|---|---|---|---|---|
| `GSet` | `g_set_add` | — | `g_set_contains` | `g_set_values` | `subscribe_g_set` |
| `TwoPSet` | `two_p_set_add` | `two_p_set_remove` | `two_p_set_contains` | `two_p_set_values` | `subscribe_two_p_set` |
| `OrSet` | `or_set_add` | `or_set_remove` | `or_set_contains` | `or_set_values` | `subscribe_or_set` |

`GSet` having no `remove` **in the type system** is itself a teaching point: the constraint is not a runtime error, it is an absent function. Say so in the README.

Event shapes differ correspondingly — `g_set_kernel.GSetEvent` has only `ElementAdded`; the other two add `ElementRemoved`. The exhaustive match over `GSetEvent` is one case, and that is worth a comment in the source, because a reader skimming the code will notice it before they notice anything else.

## Message flow

```gleam
type Msg {
  GotDocument(watershed_js.Document)
  Connected(Result(Nil, String))
  EnsuredSets(Result(#(GSet, TwoPSet, OrSet), String))
  ItemDrafted(String)
  AddedToAll(String)
  RemovedFromAll(String)
  RemovedFrom(panel: Panel, item: String)
  RanScenario(Scenario)
  GSetChanged(g_set_kernel.GSetEvent)
  TwoPSetChanged(two_p_set_kernel.TwoPSetEvent)
  OrSetChanged(or_set_kernel.OrSetEvent)
}
```

`AddedToAll` issues `g_set_add`, `two_p_set_add`, `or_set_add` in one `update` and then — for the 2P-Set — re-reads `two_p_set_contains` to detect the silently-ignored re-add. That read must happen after the optimistic write lands; take it in the same `update` after the call, and let the subsequent `TwoPSetChanged` confirm.

The union of all three panels' items forms the row set, so an item present in one panel and absent from another still renders a row in both — the absence is the point and must be visible, not collapsed away.

## Preset scenarios

The demo must not depend on a reader improvising the right sequence, and two of the interesting behaviours need *timing* a human cannot produce solo.

- **Tombstone** — add "milk" to all three, remove from all three, re-add. Single-client, three steps, ~2s with visible pacing. This is the headline.
- **Concurrent add/remove** — the two-client scenario: client A removes "milk" while client B adds it, in the same tick. Requires a second participant, so the panel prints "open a second tab and press this there" and coordinates over a ripple. The outcomes are the deep content: `OrSet` is add-wins for *concurrent* add/remove (B's add was not observed by A's remove, so the element survives), while `TwoPSet` tombstones unconditionally and the element is gone. **Do not assert these outcomes in the plan text as final** — run the convergence test in GT5 first and write the README from what it actually does.

## Rungs

- **GT1 — `watershed_lustre` fill-in (FP5 slice).** `ensure_g_set`, `subscribe_g_set`, `ensure_two_p_set`, `subscribe_two_p_set`, on the `ensure_or_set` / `subscribe_or_set` template. Land this in `watershed_lustre` proper, not the example — it is the parity plan's rung and other apps need it. Gate: package compiles; a scratch app receives a `GSetEvent`.
- **GT2 — scaffold + connect.** `examples/grocery_triptych_lustre/` on the `playlist_lustre` template; `justfile` stanzas; all three channels ensured and subscribed; three empty panels. Gate: two tabs connect and render.
- **GT3 — add to all three.** Shared input, union row rendering, per-panel counts. Gate: adding in one tab appears in all three panels in both tabs.
- **GT4 — remove, and the three rules.** Per-panel remove, the disabled G-Set control with its reason, and the 2P-Set silent-re-add detection. Gate: the tombstone sequence performed by hand produces three visibly different panels.
- **GT5 — divergence marking + scenarios.** The `⚠` badge, per-panel diff counts, and both preset scenarios. Gate: the concurrent scenario runs across two tabs and its outcome is recorded — **the README is written from the observed result, not from this document's prediction.**
- **GT6 — README + smoke test.** Lead with the tombstone sequence. State plainly which kind to reach for by default (`OrSet`) and what the other two are actually for (`GSet` for genuinely monotonic facts; `TwoPSet` when permanent removal is a *requirement* rather than an accident).

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, two in-process clients over `sluice`) — one per kind for the concurrent add/remove race, asserting the outcome each kind's semantics require. These tests are the demo's actual claims and are what GT5's README is written from.
- **Tombstone test:** single client, `two_p_set_add` → `remove` → `add`, assert `contains` is `False` after the re-add. This is the behaviour the UI must detect and is worth pinning independently of the UI.
- **The triptych invariant:** after any sequence of adds with no removes, all three panels hold identical sets. A property test over random add-only sequences — if this ever fails, the comparison is not controlled and the entire demo is invalid.
- **Smoke test** on the `sudoku_lustre` pattern.

## A note on scope creep

The obvious next thought is "add `OrMap`, add `PnCounter`, make it a full kind comparison". Resist it. The triptych works because all three panels answer *one* question — what does removal mean — and a fourth kind that answers a different question turns a controlled experiment into a feature grid. If a broader comparison is wanted, it is a separate page on the website, not this app.
