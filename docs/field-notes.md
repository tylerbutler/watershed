# Field notes — the demo annotation system

"Field notes" is the opt-in tutorial mode on the live DDS demos. When the
**Field notes** checkbox is on, hand-drawn [rough-notation](https://roughnotation.com)
marks annotate the active structure so a reader can *see* its merge rule while
the op flow animates. This document is the guideline for extending field notes
to any demo — read it before adding a new structure.

The implementation is two files:

- `website/src/scripts/tutorial.js` — the field-notes module (`createFieldNotes`).
- `website/src/scripts/demo.js` — the demo engine, which calls into the module
  at each point in an op's lifecycle.

## The load-bearing idea

The marks are hand-drawn on purpose. They read as an **inspector's annotation
over a precise printed survey sheet** — not as UI chrome. That contrast (sketchy
mark over exact linework) is the whole effect. Never reach for a hand-drawn
library for actual controls or layout; it only works as an overlay on top of the
crisp demo. See `PRODUCT.md` / `DESIGN.md` for the survey-quadrangle aesthetic.

## Color grammar (do not break this)

Every mark uses the demo's existing two-color system. This is the same grammar
the live values use, so the annotation and the thing it points at always agree.

| Token          | Meaning                                   | Use for                          |
| -------------- | ----------------------------------------- | -------------------------------- |
| `--ink`        | a sequenced / converged fact              | anything already agreed by all   |
| `--overprint`  | pending / optimistic / unsequenced        | a local edit not yet sequenced   |

**Rule:** a mark on a *pending* change is magenta (`--overprint`); a mark on a
*sequenced / applied* change is ink (`--ink`). Read the colors from CSS at draw
time (`cssVar`) — never hardcode hex, so theming stays intact.

## Two annotation models

Pick one per structure.

### 1. Static (persistent marks)

Draw one or two marks that point at *where on the sheet* the merge rule is
visible, plus a bracket on the op log. The marks persist while the view is
active and are redrawn (`pulse()`) as ops converge. Good for structures whose
lesson is a fixed shape rather than motion — for example, marking the boundary
of a set or the layout of a lattice that a reader should hold in view.

Discipline: **at most one or two marks**, drawn on **client A only** (via the
`q()` helper). Every extra mark dilutes the ones that matter.

### 2. Event-driven (flash what changes)

Draw **no** static marks. Instead, snapshot the structure's live-value elements
before each op is applied and **flash** (transient, self-removing circle) every
element whose value actually changed — magenta while pending on the origin, ink
as the op is sequenced and applied to each replica. A box flashes on the newest
op-log line as it is sequenced.

This is the model for **Shared map** and the **counters** (Shared counter, PN
counter, G-counter): the lesson is *motion* — you learn the merge rule by
watching exactly which values move, when, and in which color. For the map, a
cell flashing ink as a remote write lands shows last-write-wins as a literal
overwrite. It generalizes to any structure whose teaching moment is "watch
these values converge."

## How to add a structure to the event-driven set

Everything is driven by one table. To onboard a new structure you touch two
files and write no bespoke drawing code.

### 1. Give every live value a stable selector (`Demo.astro`)

Each element that carries a value the reader should watch converge needs a
`data-*` attribute, present in **every** client panel. The value must live in the
element's `textContent` and be updated **in place** by the render function (the
snapshot is keyed by node identity — re-creating the node breaks the diff).

```html
<output data-mydds-value>0</output>
<dd data-mydds-part="a">0</dd>
```

### 2. Register the selectors (`tutorial.js`)

Add one entry to `CHANGE_TARGETS`, listing every live-value selector. A selector
may match multiple elements per client (e.g. per-author cells) — each is
diffed independently, so only the ones that changed flash.

```js
const CHANGE_TARGETS = {
  map: [".dds-map tbody [data-value]"],
  counter: ["[data-counter-value]"],
  pn: ["[data-pn-value]", "[data-pn-fill]", "[data-pn-cut]"],
  gcounter: ["[data-gcounter-value]", "[data-gcounter-author]"],
  mydds: ["[data-mydds-value]", "[data-mydds-part]"], // ← new
};
```

Then add a **caption-only** recipe (no static marks). The caption names the
merge rule and tells the reader what to watch:

```js
mydds() {
  setNote(
    "My DDS — <one sentence naming the rule>. Watch <which values> flash " +
    "magenta on edit, then ink as the op is sequenced and applied.",
  );
},
```

That's it in `tutorial.js`. `render()` automatically skips the static narration
bracket for any structure in `CHANGE_TARGETS`, and `trackChange` / `flashLog` /
`clearFlashes` all key off the same table.

### 3. Route the lifecycle hooks (`demo.js`)

Add the structure's id to the `FIELD_FLASH` set. The engine already calls the
module at every lifecycle point; the set is what routes those calls:

```js
const FIELD_FLASH = new Set(["map", "counter", "pn", "gcounter", "mydds"]);
```

The four hook points, and what each does for an event-driven structure:

| Lifecycle moment            | Where in `demo.js`         | Call                                                            |
| --------------------------- | -------------------------- | -------------------------------------------------------------- |
| Local edit (optimistic)     | the `local…` mutator       | `trackChange(id, client.el, true, () => render(client))`       |
| Op sequenced                | `logOp`                    | `flashLog()` (guarded by `FIELD_FLASH.has(ddsId)`)             |
| Applied to a replica        | broadcast deliver loop     | `trackChange(id, target.el, false, () => render(target))`      |
| Duplicate re-delivered      | `redeliverLastDelta` loop  | `flashLog()` only — values are absorbed, so nothing flashes    |

`trackChange(ddsId, clientEl, pending, applyFn)` is the workhorse: it snapshots
the live values, runs `applyFn` (your normal `render`), then flashes the diffs.
It is a no-op passthrough unless field notes are on and this is the active view,
so it is always safe to call in place of a bare `render`.

## Timing

Flashes are sized to the demo's global speed. Draw-in is `duration(450)`; a
flash lingers `duration(1300)` (a log box lingers `1400`) then removes itself.
`duration()` already folds in the animation-speed slider, so flashes stay in
sync with the dots at any speed. Because each lifecycle moment fires as its dot
arrives, the highlights naturally stage: origin (magenta) → log box → each
replica (ink).

## Checklist for a new structure

- [ ] Every live value has a `data-*` selector in **all** client panels.
- [ ] The render function mutates those nodes **in place** (never re-creates them).
- [ ] Selectors registered in `CHANGE_TARGETS`.
- [ ] A caption-only recipe added, naming the rule in the ink/magenta language.
- [ ] Structure id added to `FIELD_FLASH` in `demo.js`.
- [ ] Verified in a browser: 0 static marks; edit flashes magenta on the origin;
      the log box flashes on sequence; each replica flashes ink as its dot lands;
      toggling field notes off clears everything; no console errors.
- [ ] Reduced motion respected (marks draw instantly, still correct).

## Field notes on the rig demos

The dedicated demo pages (`/directory`, `/sudoku`, `/json-ot`, `/sequence`)
run on the sluice rig (`website/src/scripts/demo/sluice-rig.ts`), not the
homepage engine, and their render functions rebuild or re-position DOM instead
of mutating text in place — so the node-identity snapshot in `tutorial.js`
cannot see their changes.

`website/src/scripts/demo/rig-notes.ts` is the rig-side variant. It keeps the
event-driven model and the color grammar, but inverts the contract: the demo
script owns the diff (it knows which of its keyed elements changed) and calls
`flashEls(changedEls, pending)`; the module only draws. A `MutationObserver`
on the op log replaces `flashLog` — the rig prints one line per sequenced op,
so an added `<li>` *is* the "op sequenced" moment (only `<li>` additions count: rough-notation inserts its annotation svg beside the boxed line, and reacting to that would loop).

Onboarding a rig demo:

- give the page a field-notes checkbox and a caption `<p class="field-note">`,
  wired through `createRigNotes({ rig, toggle, note, caption })`;
- diff in the demo's render — compare the previous visible state to the new
  one and collect the changed elements;
- call `flashEls(changed, pending)` with `pending = true` only on the origin's
  optimistic render (magenta), `false` on sequenced applies (ink);
- static marks stay out, same as the event-driven set upstream.

The **sequence** demo (`/sequence`) is the reference: stations are keyed by
waypoint name, its render compares the previous order to the new one, and any
position whose value changed flashes — magenta as the author edits, ink on
every replica as the op lands.
