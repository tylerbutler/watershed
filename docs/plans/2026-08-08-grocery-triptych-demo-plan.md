# Grocery triptych demo plan: three set kinds, one interaction, three outcomes

**Status:** shipped on main in `examples/grocery_triptych_lustre/`. GT1–GT6 complete.
**Date:** 2026-08-08
**Builds on:** `2026-07-06-lustre-integration-plan.md` (LU1–LU3), `docs/plans/2026-08-08-facade-parity-sweep-plan.md` (FP5, which shipped before this example landed).
**Benchmark:** none, deliberately. Every other demo in `examples/` imitates a product. This one imitates a textbook figure, the side-by-side comparison CRDT papers draw and no CRDT library ships as running code.

**Prerequisite status:** none remaining. The `watershed_lustre` FP5 fill-in (`ensure_g_set` / `subscribe_g_set` / `ensure_two_p_set` / `subscribe_two_p_set`) shipped before the example implementation, so GT1 closed on main instead of staying blocked.

## As built (status + corrections)

- The shipped app uses one typed document and three channels on one root typed map.
- Removal is a shared control, not per-panel buttons. Each row names the panels that still contain the item, and GSet retains it.
- The tombstone flow uses **`"milk"`**. The concurrent scenario uses **`"eggs"`**.
- The two-tab scenario uses ripple invitation, acknowledgement, and targeted `go`. Ripples handle timing and peer selection only.
- Scenario lock and complete state come from the room's durable snapshots, so both automated scenarios are one-shot per room and need a fresh `?document=` URL.
- The UI smooths independently delivered channel frames with a **75ms generation debounce**. That is presentation glue, not cross-channel atomicity.
- Tests shipped as deterministic add-only convergence plus fixed remove/re-add/concurrent cases. No property-test dependency was added.
- The live smoke shipped as a callback/root-observation check: wait for both `on_ready` callbacks, ensure the channels on one client, observe root-field adoption on the other, then assert the `milk` and `eggs` outcomes end to end.

## Decisions already made (flagged: confirm before GT1)

1. **Three panels, one input, identical interaction.** A single "add item" field and a single item list rendered three times. Every user action goes to all three channels in one `Msg`.
2. **Same document, three channels, not three documents.** `GSet`, `TwoPSet`, and `OrSet` live on one root typed map. Same ordering, same connection, same reconnect behaviour. The kind is the only variable.
3. **Divergence stays visible.** Differences get a badge on the item and a diff count in the panel header. The output is the difference.
4. **Each panel explains itself in place.** Each header states the rule in one line, and each blocked action says why it was blocked when it is attempted.
5. **No presence, no ordering, no extra persistence.** Anything outside the comparison is a distraction. This should stay the smallest example in the repo.

## Why this demo

The three set kinds differ only in what removal means, and a single-panel app hides that difference. Read separately, each behaves sensibly, so the kinds look interchangeable. The cost of that mistake is a data model that cannot re-add a removed item.

Set side by side, the difference is a five-second demo:

> Add "milk" to all three. Remove it. Add it back.
> **G-Set:** still present. Shared remove says GSet retained it because grow-only removal is not expressible.
> **2P-Set:** tombstoned forever. Re-add is refused.
> **OR-Set:** present again.

That shows observed-remove semantics without a diagram. It also shows where the toolkit's primitives bite, which is the point of `PRODUCT.md`.

Secondarily, it clears three no-demo kinds in one small app. It is also the only planned demo where **concurrent add/remove of the same element** is the subject rather than an edge case.

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

The `⚠` marks an item whose presence differs from the other panels. As built, item removal lives in a shared **Shared remove actions** section so the UI can say which removable panels still hold the item while keeping the interaction controlled.

**Action feedback.** Attempting a blocked or partial action reports the kind's rule inline and transiently:
- G-Set: the shared remove feedback says GSet retained the item because grow-only removal is not expressible. The shared control stays visible.
- 2P-Set: re-adding a tombstoned element is accepted by the API and has no effect. The panel compares `two_p_set_contains` after the add and surfaces "re-add ignored: `milk` is tombstoned".
- OR-Set: no blocked actions. The header notes it is the one you probably want.

## Data model

```gleam
pub type Pantry

pub const grow_only:  ChannelField(Pantry, schema.GSetChannel) = ...
pub const two_phase:  ChannelField(Pantry, schema.TwoPSetChannel) = ...
pub const observed:   ChannelField(Pantry, schema.OrSetChannel) = ...
```

All three kinds hold `String` elements, so the item name is the element. There is no encoding layer to explain away a difference.

Available ops (all present on both facades):

| | add | remove | contains | values | subscribe |
|---|---|---|---|---|---|
| `GSet` | `g_set_add` |  | `g_set_contains` | `g_set_values` | `subscribe_g_set` |
| `TwoPSet` | `two_p_set_add` | `two_p_set_remove` | `two_p_set_contains` | `two_p_set_values` | `subscribe_two_p_set` |
| `OrSet` | `or_set_add` | `or_set_remove` | `or_set_contains` | `or_set_values` | `subscribe_or_set` |

`GSet` having no `remove` **in the type system** is a teaching point. The constraint is an absent function, not a runtime error.

Event shapes differ accordingly. `g_set_kernel.GSetEvent` has only `ElementAdded`; the other two add `ElementRemoved`. The one-case match over `GSetEvent` is worth a comment in source.

## Message flow

```gleam
type Msg {
  GotHandle(watershed_js.Document)
  Connected(Result(Nil, String))
  EnsuredGrowOnly(Result(GSet, String))
  EnsuredTwoPhase(Result(TwoPSet, String))
  EnsuredObserved(Result(OrSet, String))
  DraftChanged(String)
  AddSubmitted
  RemoveRequested(String)
  ScenarioRequested(ScenarioName)
  ScenarioRippleReceived(Ripple)
  TombstoneStepDue(TombstoneStep)
  ConcurrentInvitePeers(String)
  ConcurrentInviteTimedOut(String)
  ConcurrentPeerGoTimedOut(String)
  ConcurrentInitiatorRemove(String, String)
  VerifyConcurrent(String)
  GrowOnlyChanged(g_set_kernel.GSetEvent)
  TwoPhaseChanged(two_p_set_kernel.TwoPSetEvent)
  ObservedChanged(or_set_kernel.OrSetEvent)
  FlushSharedRefresh(Int)
}
```

`AddedToAll` issues `g_set_add`, `two_p_set_add`, `or_set_add` in one `update`, then re-reads `two_p_set_contains` to detect the silently ignored re-add. Take that read after the optimistic write lands, and let the next `TwoPSetChanged` confirm it.

The union of all three panels' items forms the row set. An item present in one panel and absent from another still renders a row in both, and the absence stays visible.

## Preset scenarios

The demo must not depend on a reader improvising the right sequence, and two of the interesting behaviours need *timing* a human cannot produce solo.

- **Tombstone:** add "milk" to all three, remove from all three, re-add. Single client, three steps, about 2s with visible pacing.
- **Concurrent add/remove:** the shipped two-client scenario seeds `"eggs"`, then has client A remove while client B re-adds in the same coordinated window. It requires a second participant, coordinates over a ripple invitation, acknowledgement, and targeted-go handshake, and records the observed converged result from tests: `GSet` present, `TwoPSet` absent, `OrSet` present.

## Rungs

- **GT1:** `watershed_lustre` fill-in (FP5 slice). ✅ shipped before the example landed: `ensure_g_set`, `subscribe_g_set`, `ensure_two_p_set`, `subscribe_two_p_set`.
- **GT2:** scaffold + connect. ✅ shipped in `examples/grocery_triptych_lustre/`: three channels ensured and subscribed, shared document routing, two tabs connect and render.
- **GT3:** add to all three. ✅ shipped: shared input, union row rendering, per-panel counts, deterministic convergence checks.
- **GT4:** remove, and the three rules. ✅ shipped with a shared remove control, explicit GSet retention messaging, and TwoPSet silent re-add detection.
- **GT5:** divergence marking + scenarios. ✅ shipped: `⚠` marker, diff counts, tombstone automation, and the two-tab concurrent scenario with recorded observed outcome.
- **GT6:** README + smoke test. ✅ shipped: the README leads with the tombstone sequence, and the smoke path validates ready callbacks, adoption, and both semantic outcomes.

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, two in-process clients over `sluice`): one per kind for the concurrent add/remove race, asserting the outcome each kind's semantics require.
- **Tombstone test:** single client, `two_p_set_add` → `remove` → `add`, assert `contains` is `False` after the re-add. This is the behaviour the UI must detect.
- **The triptych invariant:** after add-only sequences, all three panels hold identical sets. It ships as a deterministic multi-client add-only test with duplicates and interleaving from both sides, enough to prove the controlled-comparison claim without a new property-test dependency.
- **Smoke test:** on the `sudoku_lustre` pattern, hardened to wait for both `on_ready` callbacks and root-field adoption before asserting the `milk` and `eggs` outcomes.

## A note on scope creep

The obvious next thought is "add `OrMap`, add `PnCounter`, make it a full kind comparison". Resist it. The triptych works because all three panels answer one question: what does removal mean. A fourth kind would turn a controlled experiment into a feature grid. If a broader comparison is wanted, make it a separate page on the website.
