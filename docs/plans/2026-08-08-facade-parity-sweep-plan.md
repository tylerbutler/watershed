# Facade parity sweep plan — the gaps behind the demo backlog

**Status (2026-08-08):** the sweep is closed. FP0–FP6 all shipped; see "What is
left" below for the one thing deliberately not done.

| Rung | State |
|---|---|
| FP0 — system-message payload field | ✅ found during FP1; not in the original plan |
| FP1 — quorum roster | ✅ roster, real quorum, sluice membership, tests |
| FP2 — rich text on the JS facade | ✅ nine functions + demo rewritten against them |
| FP3 — the three subscribes | ✅ both facades + `watershed_lustre` |
| FP4 — PactMap pending details | ✅ `pact_map_pending_signoffs` / `pending` / `get_with_details` |
| FP5 — `watershed_lustre` fill-in | ✅ ten bindings; `lustre_gaps` is now empty |
| FP6 — naming decision | ✅ `runtime.gleam` adopted `task_manager_*` |

**Three corrections to this document**, all found by checking it against the
code rather than trusting it:

1. **The bug is worse than "accepts too early".** With three clients the
   fabricated quorum *panics* the runtime actor —
   `AckMismatch("client was not expected to sign off")` — because a peer's
   accept arrives for a pact whose frozen signoff list never named it.
   `PactMap` was not an ack-delayed LWW map; it was a crash waiting for a third
   participant. The own-op quorum was also `[self]` alone, not `[self, author]`.
2. **FP1's stated risk did not materialise.** Floodgate *does* emit sequenced
   `"join"` ops and *does* populate `initialClients`. No server change was
   needed.
3. **A prerequisite this document missed (FP0).** `handle_leave` decoded
   `msg.contents`, but the server carries system-message payloads in `msg.data`
   and leaves `contents` null. The leave path was dead against every real
   server, so PactMap signoff drain, OrderedCollection release, and
   TaskManager reclaim never fired. The tests passed only because a fixture
   fabricated the inverse shape. A roster that can be joined but not left is
   worse than no roster, so this had to land first.

**How FP5 and FP6 landed**

- **FP5** — the ten bindings for `directory`, `g_set`, `two_p_set`, `json_ot`,
  and `rich_text` are in, and `lustre_gaps` in
  `test/watershed/facade_parity_test.gleam` is now `[]`. The assertion around it
  is two-sided, so empty is an enforced invariant rather than a claim: a future
  kind that reaches the facades without Lustre bindings fails there.
- **FP6** — `runtime.gleam` adopted `task_manager_*`. **Six functions, not the
  four in the table below:** `task_queued` and `task_queues` were outliers too,
  under a prefix (`task_`) close enough to the target to read as compliant. All
  three layers — `runtime_core`, `runtime`, `runtime_js` — now spell the same
  six names. The facade names (`volunteer_for_task`, `abandon_task`,
  `complete_task`, `task_assigned`, `task_queued`, `task_queues`) did not move;
  `facade_parity_test` asserts that exact ops list.

  **The convention, for the next kind:** runtime functions are
  `<kind>_<verb>` — `or_map_set`, `pact_map_get`, `ordered_add`,
  `task_manager_volunteer`. Facade names are free to read better than that
  (`volunteer_for_task`), but the two facades must agree with each other, which
  `facades_agree_with_each_other_test` enforces.

  Error-label strings naming `complete_task` (`runtime.gleam:1971`,
  `runtime_js.gleam`'s panic text) were left alone on purpose: they name the
  *facade* function the user called, which is still `complete_task`.

**What is left**

- **`scrub_not_in_quorum` stays uncalled.** It has no production caller
  (`task_manager_kernel.gleam:282`; only the kernel test calls it). With FP0
  restoring `channel.on_leave`, the departure case is covered; wiring scrub as
  a roster reconciliation pass would be a TaskManager behaviour change beyond
  this sweep.

---

**Date:** 2026-08-08
**Builds on:** the 2026-07-07 parity work (commits `a06cb7e`, `142711c`) that closed *lifecycle* parity across all 14 kinds. This plan closes the axes that sweep did not cover.
**Found by:** scoping `docs/demo-ideas.md`. Three of the demos there are blocked on gaps here, and one gap is a correctness bug rather than an ergonomics one.

## The framing that let these hide

The 2026-07-07 milestone is recorded as "all 14 kinds have full typed-layer parity". That is true **for channel lifecycle** — `create_*`, `ensure_*`, `resolve_*`, `*_handle_of`, `schema.*Channel` tags, `set_*_field` / `resolve_*_field`. Lifecycle was swept exhaustively and is genuinely complete.

But a kind is usable only if four axes are covered, and only the first was ever checked:

1. **Lifecycle** — create / ensure / resolve / handle. ✅ complete
2. **Operations** — the verbs that mutate the kind. Mostly complete; one kind absent entirely.
3. **Subscriptions** — change notification. Three kinds missing on both facades.
4. **Runtime semantics** — the wiring actually implementing the kernel's contract. One kind is stubbed.

Axis 4 is the one worth internalising: a kind can have a complete, well-named, fully-typed facade and still not do what its kernel promises, because the facade only proves the *call* exists. `PactMap` is that case.

**Correction to an earlier draft of this analysis:** `ordered_add` / `ordered_acquire` / `ordered_complete` / `ordered_release` / `ordered_size` and `complete_task` **are** present on both facades. An earlier pass reported them missing; that was a bad grep (`ordered_collection_*` / `task_*` prefixes miss `ordered_*` and `complete_task`). The work-queue demo plan has been corrected accordingly. Audit by full `pub fn` inventory diff, not by prefix guess — the command is in "How to re-run this audit" below.

---

## FP1 (P0) — `PactMap` quorum is a placeholder

**The bug.** `pact_map_kernel` implements Fluid's quorum protocol correctly: a `Set` captures a frozen signoff list from the connected quorum at sequencing time and becomes accepted only when that list drains. The runtime hands it a **fabricated** quorum:

```gleam
// src/watershed/runtime_core.gleam:815–818  (remote ops)
quorum: [
  client_id_to_int(core.client_id),
  option.map(message_client_id, client_id_to_int) |> option.unwrap(0),
],

// src/watershed/runtime_core.gleam:962  (own sequenced ops)
quorum: [client_id_to_int(core.client_id)],
```

That is `[self, author]` — never the room. **The runtime tracks no membership roster at all.** `runtime_core` handles exactly two system message types, `"op"` and `"leave"` (`:600–606`); there is no `"join"` handler. The socket layer decodes `initial_clients` from the handshake (`src/watershed/wire/socket.gleam:238`, `:296`) and **nothing ever reads it** — verified: those two lines are the only occurrences in the tree.

**Consequence.** With three clients connected and A setting a key, the signoff list is `[A, B]` for B, `[A]` for A — C is never included, so C's agreement is never required and the pact accepts after roughly one round trip. `PactMap` currently behaves as an ack-delayed LWW map. Every kernel-level property test passes, because the kernel is not what is broken.

**Why it stayed hidden:** no demo, no facade subscribe (FP3), and no integration test asserting a three-client pending window. The kernel tests supply their own `connected` lists and are therefore blind to this by construction.

**The fix.**

- **FP1a — track the roster.** Add `members: Set(Int)` to `Core`. Seed it from `initial_clients` at handshake (wire it through from `socket.gleam`, where it is already decoded); add a `"join"` handler alongside `handle_leave` (`:613`); remove on leave in the existing fan-out. On reconnect, reseed from the fresh handshake rather than merging into stale state.
- **FP1b — feed the real quorum.** Replace both hardcoded lists with the roster. Keep `self` and `author` unioned in defensively: a sequenced op from a client not in the roster (join message lost, or ordering skew between join and op) must not produce a signoff list that can never drain.
- **FP1c — assert it.** A three-client integration test: A sets, assert pending at A **and** B **and** C, drain, assert accepted at all three. Then the failure mode that matters — A sets, C hard-disconnects without a clean leave, assert the pending entry drains via the leave path rather than wedging forever. That second test is the real question about this protocol in production.

**Risk.** If floodgate does not emit join messages at all, FP1a stalls at the handshake seed, which is enough for clients present at connect but not for late joiners. Check floodgate's system-message surface **first**; if joins are not emitted, this becomes a server-side plan and FP1 stops after documenting the limitation loudly in `schema.gleam` and the `PactMap` docs. Do not ship a `PactMap` demo before FP1 lands either way — see the drum machine plan.

**Aside:** the same roster fixes a second latent issue. `task_manager_kernel.scrub_not_in_quorum` and `channel.gleam:1002`'s quorum argument have the same fabricated input, so `TaskManager`'s quorum scrubbing is equally notional today. It is less visible because the leave path handles the common case, but it should be covered by FP1c's test matrix.

---

## FP2 (P0) — `SharedRichText` is absent from the JS facade

`rg -c 'rich_text' src/watershed_js.gleam` → **zero matches**. The BEAM facade has the full set (`create_rich_text`, `ensure_rich_text`, `resolve_rich_text`, `rich_text_handle_of`, `submit_rich_text`, `rich_text_view`, `subscribe_rich_text`, `set_rich_text_field`, `resolve_rich_text_field`). The JS facade has none of it, while `runtime_js.gleam` has `create_rich_text` (`:1233`), `submit_rich_text` (`:471`), and `rich_text_view` (`:484`) ready to delegate to. `schema.RichTextChannel` already exists (`schema.gleam:127`).

**The evidence this hurts.** The website's rich-text demo — a flagship, on the public site — reaches around the facade into internals:

```ts
// website/src/scripts/rich-text-demo.ts:34–39
import * as watershed from ".../watershed_js.mjs";
import * as runtime   from ".../watershed/runtime_js.mjs";
import * as richText  from ".../watershed/rich_text.mjs";
import * as channel   from ".../watershed/channel.mjs";
import * as handle    from ".../watershed/handle.mjs";
```

`runtime_js`, `channel`, and `handle` are not public API. The demo that exists to make watershed look credible is written against private modules because the public ones cannot express it. That is the strongest argument in this document.

**The fix.** Add the nine functions to `watershed_js.gleam` following the `json_ot_*` pattern (closest sibling: same submit/view shape). Then **rewrite the website demo against the facade** and confirm the `runtime_js` / `channel` / `handle` imports are gone — the rewrite is the acceptance test, not an optional follow-up. If any of those imports cannot be removed, that residue is a further gap and gets its own rung.

---

## FP3 (P1) — three kinds have no subscription

Missing from **both** facades and from `watershed_lustre`:

| Missing | Events already reach |
|---|---|
| `subscribe_pn_counter` | `runtime_core.gleam:3203` (`channel.PnCounterEvent`) |
| `subscribe_ordered_collection` | `runtime_core.gleam:3224` (ordered events) |
| `subscribe_pact_map` | `channel.gleam:228`, `:707`, `:714`, `:760` (`channel.PactMapEvent` → `WentPending` / `WentAccepted`) |

These kinds are **write-and-poll only**: an app can mutate and read but cannot learn that a peer changed anything. For `PactMap` this is acute, because `WentPending` → `WentAccepted` *is* the protocol — without the subscription, the one interesting thing about the kind is unobservable.

Mechanical work; the template is `subscribe_or_map` in each of the three modules. Note the per-target idiom: BEAM `subscribe_*` return a `Subject`, JS take a handler and return `Nil`, `watershed_lustre` takes a `to_msg` constructor and defers every callback to a microtask unconditionally.

## FP4 (P1) — `PactMap` pending details are not reachable

Facades expose `pact_map_set` / `delete` / `get` / `is_pending` / `keys`. Not exposed: `runtime_core.pact_map_get_with_details` (`:3362`, returns `Accepted(value, sequence_number)`) and the kernel's `get_pending` (returns the pending value) — and, most importantly, nothing surfaces `Pending.expected_signoffs`.

Any UI that explains *why* a value is still pending needs the outstanding signoff list. Without it, `is_pending` gives a boolean and the user watches a spinner with no model of what it is waiting for. Add `pact_map_pending_signoffs` (or expose `Pending` wholesale) alongside FP3's subscribe — they are only useful together, and FP1 must land first or the returned list is fiction.

## FP5 (P2) — `watershed_lustre` coverage holes

*Shipped. The diagnosis below is kept as written; `lustre_gaps` is now empty.*

`watershed_lustre` covers 14 of the kinds partially. Missing relative to `watershed_js`:

- **`ensure_*`:** `directory`, `g_set`, `two_p_set`, `json_ot` (+ `rich_text` once FP2 lands)
- **`subscribe_*`:** `directory`, `g_set`, `two_p_set`, `json_ot` (+ `rich_text`, and the three from FP3)

Any Lustre app using those kinds must hand-roll the microtask deferral that this package exists to own — which is exactly the mid-`update` dispatch clobber the package's module docs describe as "designed out rather than documented". A gap here silently reintroduces a bug class.

**This blocks the grocery triptych demo**, which needs `ensure_g_set` / `subscribe_g_set` / `ensure_two_p_set` / `subscribe_two_p_set`. That plan carries these as its first rung.

## FP6 (P3) — naming drift at the runtime layer

*Shipped. The middle column below is now `task_manager_*`, and the table missed
`task_queued` / `task_queues`, which were renamed too.*

Three names for one operation:

| Facade | `runtime.gleam` (BEAM) | `runtime_js.gleam` |
|---|---|---|
| `volunteer_for_task` | `volunteer_task` | `task_manager_volunteer` |
| `abandon_task` | `abandon_task` | `task_manager_abandon` |
| `complete_task` | `complete_task` | `task_manager_complete` |
| `task_assigned` | `task_assigned` | `task_manager_assigned` |

The facades agree with each other, which is what matters most, so this is cosmetic. But the two runtimes disagree on the convention (`<verb>_task` vs `task_manager_<verb>`) and `runtime_js` is the odd one out. Every other kind in `runtime_js` uses the `<kind>_<verb>` shape (`or_map_set`, `pact_map_get`, `ordered_add`), so `task_manager_*` is arguably the consistent one and `runtime.gleam` should move. Decide once, note it in the facade template, do not churn it twice.

---

## Rungs

Order matters: FP1 is a correctness fix and gates any honest `PactMap` work; FP2 is independent and can run in parallel.

- **FP1 — quorum roster.** a) track membership, b) feed the real quorum, c) three-client integration tests including the ungraceful-disconnect drain. **Investigate floodgate's join-message surface before starting.** Gate: a three-client test observes a genuine pending window that a two-client test cannot produce.
- **FP2 — rich text on the JS facade.** Nine functions, then rewrite `website/src/scripts/rich-text-demo.ts` against them. Gate: no `runtime_js` / `channel` / `handle` imports remain in the demo, and it still works in a browser.
- **FP3 — the three subscribes.** Both facades + `watershed_lustre`. Gate: a test per kind per target observes an event from a peer's mutation.
- **FP4 — PactMap pending details.** After FP1 and FP3. Gate: a test reads the outstanding signoff list mid-pend and it matches the actual connected roster.
- **FP5 — `watershed_lustre` fill-in.** ✅ Five `ensure_*` and five `subscribe_*` (the three from FP3 had already landed there). Gate met: package compiles, `lustre_gaps` is empty, the grocery triptych's first rung is unblocked.
- **FP6 — naming decision.** ✅ `task_manager_*`, applied to `runtime.gleam` — six functions, six call sites in `src/watershed.gleam`, nothing else in the tree. Done last, as planned.

## Testing strategy

- **Parity is a test, not a habit.** The recurring failure here is a sweep that covered one axis and got recorded as covering all of them. Add a test that enumerates expected `pub fn` names per kind per axis and fails when a kind is missing one — a table of `#(kind, [lifecycle], [ops], [subscribe])` compared against the module's exports. If reflection over exports is not available on both targets, a checked-in inventory file plus a CI diff against the `rg` command below is a workable substitute. Without something mechanical, axis 4 will regrow.
- **Integration tests gated on `WATERSHED_INTEGRATION=1`** with a live floodgate on :4000, following `integration_test.gleam`. FP1's assertions genuinely need three clients — do not approximate with two, because the two-client case is exactly the case the current bug satisfies.
- **Note:** `summary_versions_test` fails against both floodgate and levee and is a known pre-existing failure, not a regression from this work.

## How to re-run this audit

```sh
for f in src/watershed.gleam src/watershed_js.gleam \
         watershed_lustre/src/watershed_lustre.gleam \
         src/watershed/runtime.gleam src/watershed/runtime_js.gleam; do
  echo "## $f"
  rg -oIN 'pub fn [a-z_]+' "$f" | sd 'pub fn ' '' | sort -u | tr '\n' ' '; echo
done
```

Diff the two facade lines against each other. Do not grep by prefix guess — that is how the `ordered_*` false positive happened.
