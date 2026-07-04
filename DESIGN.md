# Design

Visual system for the watershed website (`website/`). Register: brand.

## Theme: "Photorevised survey quadrangle"

The site is styled as a USGS-style survey sheet. The metaphor is load-bearing:
on photorevised quadrangles, magenta overprint marks revisions not yet
field-checked — on this site, magenta marks *pending, unsequenced* state, and
ink marks state the server has sequenced. The roadmap ledger uses the same
grammar: implemented work prints in ink; planned or researching work prints as
magenta overprint. Every decorative element maps to a real protocol concept
(contours labeled with server sequence numbers, the architecture drawn as a
geological cross-section, roadmap entries as a revision ledger).

## Color (OKLCH, light theme only)

| Token | Value | Role |
| --- | --- | --- |
| `--bg` | `oklch(100% 0 0)` | pure white sheet |
| `--surface` | `oklch(96.2% 0.005 340)` | alternate section band |
| `--ink` | `oklch(25% 0.02 260)` | body text, borders, sequenced state (16:1 on bg) |
| `--muted` | `oklch(44% 0.015 260)` | secondary text (7.8:1) |
| `--overprint` | `oklch(55% 0.21 340)` | magenta brand / pending fills, large text (5.5:1) |
| `--overprint-deep` | `oklch(44% 0.185 340)` | magenta at body sizes (8.6:1) |
| `--waterline` | `oklch(37% 0.095 240)` | blue ink: links, water linework, "converged" (10.2:1) |
| `--hairline` / `--hairline-faint` | ink at 22% / 11% | rules, strata boundaries |

Strategy: **Committed** — magenta carries the brand; white text on magenta
fills; no other hues. Semantics are strict: magenta = pending/unverified,
ink = sequenced/confirmed, waterline = linework and links.

## Typography

- **Archivo Variable** (`@fontsource-variable/archivo/wdth.css`): the width
  axis is the voice. Display/headings at `font-stretch` 115–122%,
  weight 620–650; body at normal width.
- **Fragment Mono**: code, data, and the `.annot` map-margin annotation style
  (uppercase, 0.07em tracking, 0.8125rem).
- Display: `clamp(2.7rem, 5vw + 1.35rem, 5.4rem)`, line-height 0.99,
  letter-spacing −0.025em. H2: `clamp(1.85rem, 2.2vw + 1.1rem, 2.9rem)`.
  Body 1.0625rem / 1.65, measure ≤62ch.

## Sheet grammar

The page is wrapped in a neatline border with registration crosses at the
corners and mono margin annotations above/below the frame (`Sheet.astro`).
This frame-level grammar is the *only* place kicker-style labels live;
sections themselves get plain headings — no per-section eyebrows.

## Motion

- Tokens: `--ease-out-quart`, `--ease-out-expo`; 130ms feedback / 240ms state
  / 700ms entrance.
- Hero contours draw in via `stroke-dashoffset` keyframes; headline rises.
- After draw-in the contour field keeps flexing slowly (`hero-drift.js`):
  path geometry is re-derived from the shared generator
  (`contour-field.js`) with a two-frequency ~5px vertical drift, amplitude
  ramped from zero so the JS takeover never jumps. ~26fps, paused
  off-screen via IntersectionObserver, skipped (and reset to static)
  under reduced motion.
- Scroll reveals (`src/scripts/motion.js`) animate *visible-by-default*
  content with WAAPI at trigger time — nothing is hidden if JS fails.
  Variants: `rise` (up) and `settle` (strata settle downward).
- Demo ops travel as dots (magenta toward the sequencer, ink outward). On
  first reveal the demo submits one scripted op so convergence is witnessed
  without interaction (skipped under reduced motion or after user input).
- Global `prefers-reduced-motion` rule collapses all CSS animation to end
  state; scripts return early.

## Components / conventions

- Panels and tables: 1px `--ink` borders, no border-radius, no shadows —
  everything sits flat on the sheet like printed linework.
- Architecture cross-section: keep target-specific facades/runtimes/transports
  in the left/right columns (`watershed`/`runtime`/`aquamarine` vs
  `watershed_js`/`runtime_js`/`transport_js`); keep `runtime_core`, `channel`,
  `wire`, and kernel modules in the shared bedrock layer.
- "Stamps" (`.stamp`, `.pure-stamp`): mono uppercase in a 1.5px
  `currentColor` box, rotated ~2deg, like a hand inspection stamp.
- Bedrock hatching: `repeating-linear-gradient(-45deg, …)` hairline diagonal.
- Astro scoped styles don't reach JS-created elements — use `:global()` for
  anything rendered from `demo.js`.
- The demo imports the real compiled kernels from
  `../../../build/dev/javascript/watershed/watershed/{map_kernel,pn_counter_kernel,or_map_kernel,or_set_kernel,claims_kernel,register_collection_kernel,ordered_collection_kernel,pact_map_kernel}.mjs`
  plus the runtime counter channel and lattice modules
  (`lattice_counters/{pn_counter,g_counter}`, `lattice_core/replica_id`)
  (`gleam build --target javascript` runs via `predev`/`prebuild`).
- The demo hosts all nine DDS/CRDT sheets on one sequencer/SN stream, like DDSes
  sharing a container. A segmented picker (`.dds-picker`, radios styled as
  printed cells; checked cell = solid ink; stacks into a legend column below
  640px) swaps the replica view between the shared map (gauge table), the
  shared counter, the PN counter, the OR-map stockpile ledger, OR-set markers,
  claims, registers, ordered collection, and pact map; all kernels stay live
  regardless of which is shown. Counter-family pending state is a *delta*,
  annotated in magenta beside the value
  (`Δ +8 unsequenced`). The race button relabels per structure — map races
  show last-write-wins, counter races converge on the sum, PN races converge
  on fill − cut, OR-map/OR-set races show add-wins observed-remove, claims
  races resolve first-writer-wins, register races preserve LWW versions,
  ordered races give the first acquire the queued item, and pact races accept
  the first quorum proposal — and counter/PN/OR-map reset is compensating CRDT
  growth rather than an overwrite.
- The PN counter is framed as an **earthwork balance** (cut & fill, yd³):
  the CRDT's two monotone tallies print as a `fill Σ / cut Σ` ledger under
  the signed net value, with mono `cut`/`fill` margin labels flanking the
  buttons. Each client is replica-identified (`client-a`/`client-b`) and
  boots from a baseline summary built under a `survey-baseline` replica —
  the same `from_summary` path a reconnecting client takes. PN mode adds a
  **Re-deliver last delta** button (hidden in other modes, disabled until a
  PN delta is sequenced): the sequencer re-sends the last sequenced delta
  with no new SN, the merge absorbs it, and the op log prints the duplicate
  as an italic muted non-event (`#04 again cut −5 yd³ · absorbed`) —
  idempotency witnessed live, which the op-based counter could not survive.
- The OR-map is framed as a **stockpile & borrow-pit ledger**:
  `spoil-north`, `borrow-pit-7`, and `wash-fill` rows carry signed yd³
  tallies. Striking a row hides it with muted strikethrough linework; re-open
  submits a `+0` delta, making the retained tally visible again. Its race is
  the add-wins proof: A strikes an observed pile while B logs a concurrent
  delivery, and the row survives with every logged yard. OR-map mode also
  shares the duplicate-delta replay affordance with PN mode.
- Claims are framed as **duty stations** (`north-levee`, `spillway-gate`,
  `pump-house`) on a claim sheet: first writer wins, write-once
  (`try_set_claim` only — CAS re-claim is an explicit non-goal for the demo).
  Reads are **non-optimistic**, so the holder cell always prints in ink and
  a filed claim never shows as the holder — magenta annotates only the op in
  flight (`claim filed · outcome unknown`, dashed underline on the `—`),
  the inverse of the other views where magenta marks an optimistic value.
  Claiming a committed slot is refused locally and synchronously (`already
  claimed — nothing sent`: no dot, no SN, note self-clears). The deferred
  outcome resolves at `ack_local`: a losing claim leaves a persistent
  magenta margin note (`lost — A holds it`) and logs an overprint-italic
  non-event (`#06 rejected — spillway-gate held · first writer wins`). Ops
  print their `ref_seq` in the log (`claim north-levee → A (ref 0)`), fed
  from a per-client last-delivered SN. Baseline pre-claims `pump-house` by
  `Survey` via `from_summary` (persisted seq numbers keep CAS honest after
  load). Claims have no unclaim op, so reset tears off a fresh sheet — both
  replicas reload the baseline summary locally — guarded by an epoch counter
  that makes the sequencer drop claims still in flight (otherwise a reset
  mid-flight would commit on one replica and fail to ack on the other).
- The ordered collection is framed as a **task queue**: queued work prints in
  FIFO order, acquired jobs move into a held-job row with their owner (`A`/`B`),
  and add/acquire/complete/release are non-optimistic until sequenced. Its race
  reloads a one-item queue, then both clients acquire; the first SN holds the
  task and the second resolves `QueueEmpty` on every replica.
- The pact map is framed as a **quorum pact board**: accepted values print in
  ink, pending proposals print in magenta with an `awaiting A + B` signoff
  annotation, and every sequenced set auto-submits the accept ops each connected
  client owes. Its race files two concurrent proposals for the same pact; the
  first sequenced set freezes the signoff list and the competing set is dropped
  while the accepted value converges after both accepts.
