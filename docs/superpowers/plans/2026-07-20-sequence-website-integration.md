# SharedSequence Website Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the SharedSequence DDS into the watershed website: a `sequences` catalog category, a dedicated three-pane portage-route demo at `/sequence`, event-driven field notes on that demo, and a models-page prose touch-up.

**Architecture:** All catalog surfaces (homepage field sheets, `/structures/*`, models page) derive from `website/src/data/structures.ts`, so one data entry lights them all up. The demo clones the directory demo's architecture: three real watershed documents driven through the in-memory sluice (`scripts/demo/sluice-rig.ts`) and the JS facade (`watershed_js.mjs`). Field notes get a new rig-side module (`scripts/demo/rig-notes.ts`) because the homepage module (`tutorial.js`) snapshots by node identity, which rig demos break by rebuilding DOM.

**Tech Stack:** Astro 6 (static site), TypeScript demo scripts importing Gleam-compiled JS from `build/dev/javascript/`, rough-notation for field-note marks, pnpm.

**Spec:** `docs/superpowers/specs/2026-07-20-sequence-website-design.md`

**Verification model:** The website has no test harness. Every task verifies with `pnpm build` in `website/` (its `prebuild` runs `gleam build --target javascript` first), and demo tasks add a manual dev-server smoke check. Run all commands from the repo root unless the step says otherwise.

---

### Task 1: Catalog entry — sequences category

**Files:**
- Modify: `website/src/data/structures.ts` (add a `sequences` array after the `maps` array, and a category object in `categories`)
- Create: `website/src/pages/structures/sequences.astro`

The catalog is the single source of truth: the homepage field-sheet stack (`AdjoiningSheets.astro`), `/structures` index, the category page (via `StructureCategory.astro`), and the models page all read `categories`. `demoHref` excludes the structure from the shared gauge demo and links its plate to the dedicated page instead (the category page already renders nothing for a family with zero shared-demo views — see `familyViews.length > 0` in `StructureCategory.astro`).

- [ ] **Step 1: Add the `sequences` structure array**

In `website/src/data/structures.ts`, directly after the closing `];` of the `const maps: Structure[]` array (the one ending with SharedDirectory), insert:

```ts
const sequences: Structure[] = [
  {
    id: "sequence",
    name: "SharedSequence",
    module: "sequence_kernel",
    kind: "CRDT",
    onHomepage: true,
    tagline:
      "An ordered list many people can edit at once — insert, move, and reorder without losing anyone's changes.",
    rule: "each item keeps a stable identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers",
    optimistic:
      "your edit shows immediately in magenta; items slide when the sequenced order lands",
    summary: "the sequenced list reloads intact; pending edits replay on top",
    how: [
      "A shared sequence holds an ordered list of JSON values. You address an edit by index — insert at 2, move 4 to 1 — but the index only records intent. Underneath, every item carries a stable identity, and the CRDT delta that ships is expressed against identities, not positions. That is what lets two replicas edit the same region concurrently and still converge: a move follows the item it named rather than whatever later occupies its slot, and two inserts at one position both survive in a deterministic order.",
      "The lattice merge is duplicate- and order-tolerant: a delta delivered twice, or after its neighbors, is absorbed without disturbing the list. Local edits apply optimistically and ride the sequenced stream as deltas; if the server rejects one, it rolls back and the remaining pending edits replay over the sequenced base.",
      "Replace is composed rather than native: it deletes the visible item and inserts the replacement at the same position as one collaborative operation — one pending entry, one wire op, one event. Unlike SharedMap or SharedDirectory, this is not a Fluid Framework port; the wire format is watershed's own.",
    ],
    useCases: [
      "Shared itineraries, checklists, and ordered plans edited by many hands",
      "Reorderable collections — playlists, priority queues, kanban lanes — where a move must not clobber a concurrent edit",
      "The ordered substrate beneath a future collaborative-text DDS",
    ],
    demoHref: "/sequence",
  },
];
```

- [ ] **Step 2: Add the category**

In the same file, in the `export const categories: Category[]` array, insert this object **between** the `maps` category object and the `coordination` category object:

```ts
  {
    slug: "sequences",
    name: "Sequences",
    tagline: "Ordered lists that stay ordered while everyone rearranges them.",
    lede: [
      "Order is the hardest thing to agree on. An index is only meaningful against one version of a list — the moment two people insert, move, or delete concurrently, “position 3” names different items on different screens.",
      "Sequences resolve that by giving every item a stable identity beneath its index. Positions are how you address an edit; identities are how edits merge. Concurrent inserts at one spot both land, a move follows the item rather than the slot, and every replica converges on the same order.",
    ],
    structures: sequences,
  },
```

(Use curly typographic quotes in the lede, matching the existing copy style — e.g. SharedDirectory's `how` uses `’`.)

- [ ] **Step 3: Create the category page**

Create `website/src/pages/structures/sequences.astro` (same shape as `maps.astro`):

```astro
---
import StructureCategory from "../../components/StructureCategory.astro";
---

<StructureCategory slug="sequences" />
```

- [ ] **Step 4: Build**

Run: `cd website && pnpm build`
Expected: build succeeds (the `prebuild` hook compiles Gleam first). Then confirm the page rendered:

Run: `ls website/dist/structures/sequences/index.html && rg -c "SharedSequence" website/dist/index.html`
Expected: the file exists and the homepage mentions SharedSequence at least once (field-sheet stack).

- [ ] **Step 5: Commit**

```bash
git add website/src/data/structures.ts website/src/pages/structures/sequences.astro
git commit -m "feat(website): add sequences catalog category

SharedSequence field sheet, detail plate, and category page, kind CRDT
(lattice merge, not a Fluid port), demoHref reserved at /sequence."
```

---

### Task 2: Models-page prose touch-up

**Files:**
- Modify: `website/src/pages/models.astro:47`

The membership lists on this page derive from `structures.ts`, so SharedSequence already appears in the CRDT column after Task 1. Only the OT card's trade-off line needs updating — it currently implies ordered sequences are OT's home turf.

- [ ] **Step 1: Edit the OT trade-off line**

In `website/src/pages/models.astro`, find:

```ts
    tradeoff:
      "Minimal per-op metadata and a natural fit for ordered sequences, at the cost of transform functions that must be correct for every pair of op types.",
```

Replace with:

```ts
    tradeoff:
      "Minimal per-op metadata and a natural fit for ordered sequences — though SharedSequence now reaches the same ground by merge — at the cost of transform functions that must be correct for every pair of op types.",
```

- [ ] **Step 2: Build**

Run: `cd website && pnpm build`
Expected: success. `rg -c "SharedSequence" website/dist/models/index.html` prints ≥ 2 (membership list + trade-off line).

- [ ] **Step 3: Commit**

```bash
git add website/src/pages/models.astro
git commit -m "docs(website): acknowledge merge-based sequences on models page"
```

---

### Task 3: Rig-side field-notes module

**Files:**
- Create: `website/src/scripts/demo/rig-notes.ts`

The homepage field-notes module (`tutorial.js`) snapshots live values **by node identity** and requires renders that mutate text in place. Rig demos rebuild or re-position DOM per render, so this module inverts the contract: the demo owns its diff and hands over the changed elements; the module only draws. Same color grammar (magenta `--overprint` pending, ink `--ink` sequenced), flash-only per the event-driven model in `docs/field-notes.md`. A MutationObserver on the op log replaces `flashLog` — the rig prints exactly one line per sequenced op.

- [ ] **Step 1: Write the module**

Create `website/src/scripts/demo/rig-notes.ts`:

```ts
// Field notes for the sluice-rig demos (sequence, and any future rig page).
//
// The homepage engine's field-notes module (tutorial.js) snapshots live values
// by node identity, which requires renders that mutate nodes in place. The rig
// demos rebuild or re-position DOM per render, so this variant inverts the
// contract: the demo owns its diff — it knows which of its keyed elements
// changed — and calls `flashEls`; this module only draws. Same color grammar
// as tutorial.js (magenta --overprint for a pending local edit, ink --ink once
// sequenced) and flash-only: no static marks, per the event-driven model in
// docs/field-notes.md.
import { annotate } from "rough-notation";
import { prefersReducedMotion } from "./timing.ts";

export interface RigNotes {
  /** Whether the field-notes checkbox is on. */
  readonly active: boolean;
  /** Circle-flash elements the demo diffed as changed. */
  flashEls(els: Array<Element | null | undefined>, pending: boolean): void;
}

interface FlashEntry {
  a: { remove(): void };
  timer: ReturnType<typeof setTimeout>;
}

export function createRigNotes(config: {
  /** The rig container (holds the op log). */
  rig: Element;
  /** The field-notes checkbox. */
  toggle: HTMLInputElement;
  /** The caption element shown while notes are on. */
  note: HTMLElement;
  /** Caption naming the merge rule in the ink/magenta language. */
  caption: string;
}): RigNotes {
  const cssVar = (name: string) =>
    getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  let active = false;
  let flashes: FlashEntry[] = [];

  function flash(el: Element | null, cfg: Record<string, unknown>, ttl: number) {
    if (!el) return;
    const a = annotate(el as HTMLElement, {
      animate: !prefersReducedMotion(),
      animationDuration: 450,
      ...cfg,
    });
    a.show();
    const entry: FlashEntry = {
      a,
      timer: setTimeout(() => {
        a.remove();
        flashes = flashes.filter((f) => f !== entry);
      }, ttl),
    };
    flashes.push(entry);
  }

  function clearFlashes() {
    for (const f of flashes) {
      clearTimeout(f.timer);
      f.a.remove();
    }
    flashes = [];
  }

  config.note.textContent = config.caption;
  config.toggle.addEventListener("change", () => {
    active = config.toggle.checked;
    config.note.hidden = !active;
    if (!active) clearFlashes();
  });

  // The rig prints one op-log line per sequenced op, so a childList mutation
  // is the "op sequenced" moment — box the newest line, like flashLog upstream.
  const log = config.rig.querySelector("[data-op-log]");
  if (log) {
    new MutationObserver(() => {
      if (!active) return;
      flash(
        log.querySelector("li"),
        { type: "box", color: cssVar("--ink"), strokeWidth: 2, padding: 3 },
        1400,
      );
    }).observe(log, { childList: true });
  }

  return {
    get active() {
      return active;
    },
    flashEls(els, pending) {
      if (!active) return;
      const color = pending ? cssVar("--overprint") : cssVar("--ink");
      for (const el of els)
        if (el)
          flash(el, { type: "circle", color, strokeWidth: 2, padding: 6 }, 1300);
    },
  };
}
```

Note: `prefersReducedMotion` is the function exported by `./timing.ts` (the same one `sluice-rig.ts` imports); rough-notation is already a website dependency.

- [ ] **Step 2: Commit**

The module is only compiled once a page imports it (Task 4 verifies it in the build), so commit as-is:

```bash
git add website/src/scripts/demo/rig-notes.ts
git commit -m "feat(website): add rig-side field-notes module

Event-driven flashes for sluice-rig demos: the demo owns the diff and
passes changed elements; a MutationObserver on the op log boxes each
newly sequenced line. Same ink/magenta grammar as tutorial.js."
```

---

### Task 4: The `/sequence` portage demo

**Files:**
- Create: `website/src/scripts/sequence-demo.ts`
- Create: `website/src/components/SequenceDemo.astro`
- Create: `website/src/pages/sequence.astro`

Three real watershed documents share one `SharedSequence` through the sluice rig. Client A creates the sequence via the JS facade, attaches its handle under root-map key `route`, and seeds the initial route inside `setup` (drained silently by `settle`, so the visible timeline starts clean); B and C resolve the handle. Every edit is a facade call (`sequence_insert/move/replace/delete`); reads use `sequence_values`. Stations are keyed by waypoint name (names are kept unique via the spare-name pool), absolutely positioned, and moved with a CSS `transform` transition — that is what makes stations visibly *slide* on reorder. The SVG river path is drawn in pixel units (no viewBox) so it shares the stations' coordinate space.

- [ ] **Step 1: Write the demo script**

Create `website/src/scripts/sequence-demo.ts`:

```ts
// Live SharedSequence convergence demo: three real watershed documents share
// one ordered portage route, driven through the in-memory sluice (see
// ./demo/sluice-rig.ts for the shared orchestration). Client A creates the
// sequence via the JS facade and attaches its handle under the root map; the
// others resolve it. From there, edits are ordinary facade calls the sluice
// sequences — the runtime owns optimistic apply, pending, and resubmit — so
// the demo just issues inserts/moves/renames/deletes and reads values back.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";
import { createRigNotes, type RigNotes } from "./demo/rig-notes.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
// The route the demo starts with, upstream → downstream.
const INITIAL_ROUTE = [
  "put-in",
  "mill-race weir",
  "kettle-run rapids",
  "low-ford portage",
  "take-out",
];
// Pool for inserted/renamed waypoints. Names are kept unique on the route so
// stations can be keyed (and slide-animated) by name.
const SPARE_NAMES = [
  "beaver dam",
  "gravel bar",
  "oxbow",
  "sweeper",
  "boulder garden",
  "eddy pool",
  "cache point",
  "lining chute",
  "high camp",
];
const SEQ_ADDRESS = "route"; // root-map key holding the sequence handle

// ── geometry (pixel units, shared by stations and the SVG river) ────────────
const ROW_H = 56;
const PAD_Y = 20;
const MEANDER = [0, 26, 42, 26, 0, -22, -36, -22];
const SVG_NS = "http://www.w3.org/2000/svg";

function xAt(i: number): number {
  const m = MEANDER[((i % MEANDER.length) + MEANDER.length) % MEANDER.length];
  return 64 + m;
}
function yAt(i: number): number {
  return PAD_Y + i * ROW_H + ROW_H / 2;
}
function routeHeight(count: number): number {
  return PAD_Y * 2 + Math.max(count, 1) * ROW_H;
}

interface PaneData {
  stationEls: Map<string, HTMLElement>;
  order: string[] | null;
  selected: string | null;
  nameCursor: number;
}

function pane(client: RigClient): PaneData {
  return client.data as unknown as PaneData;
}
function unquote(raw: string): string {
  return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
    ? raw.slice(1, -1)
    : raw;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}
function values(client: RigClient): string[] {
  return watershed
    .sequence_values(client.handle)
    .toArray()
    .map((v: unknown) => unquote(json.to_string(v)));
}

export function initSequenceDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;
  let notes: RigNotes | null = null;
  // True while a local edit's synchronous render runs, so the field-notes
  // flash is magenta on the origin and ink on sequenced deliveries.
  let submitting = false;

  function nextName(client: RigClient): string {
    const data = pane(client);
    const visible = new Set(values(client));
    for (let i = 0; i < SPARE_NAMES.length; i++) {
      const name = SPARE_NAMES[data.nameCursor % SPARE_NAMES.length];
      data.nameCursor += CLIENT_IDS.length;
      if (!visible.has(name)) return name;
    }
    return SPARE_NAMES[pane(client).nameCursor % SPARE_NAMES.length];
  }

  function submitOp(
    client: RigClient,
    marker: string | null,
    write: () => void,
    label: string,
  ) {
    if (!rig) return;
    submitting = true;
    try {
      rig.submit(client, marker, write, label);
    } finally {
      submitting = false;
    }
  }

  // ── local edits (indexes validated against the caller's optimistic list) ──
  function localInsert(clientId: string, index: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const at = Math.max(0, Math.min(index, values(client).length));
    const name = nextName(client);
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_insert(client.handle, at, json.string(name));
      },
      `insert ${name} @${at + 1}`,
    );
  }

  function localMove(clientId: string, from: number, to: number, name: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const len = values(client).length;
    // lattice contract: `to` is evaluated after removing the item at `from`,
    // so its valid range is 0..len-1 (the shortened list has len-1 items).
    if (from < 0 || from >= len || to < 0 || to > len - 1) return;
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_move(client.handle, from, to);
      },
      `move ${name} ${from + 1}→${to + 1}`,
    );
  }

  function localRename(clientId: string, index: number, oldName: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    if (index < 0 || index >= values(client).length) return;
    const name = nextName(client);
    const data = pane(client);
    if (data.selected === oldName) data.selected = name;
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_replace(client.handle, index, json.string(name));
      },
      `rename ${oldName} → ${name}`,
    );
  }

  function localDelete(clientId: string, index: number, name: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    if (index < 0 || index >= values(client).length) return;
    pane(client).selected = null;
    submitOp(
      client,
      null,
      () => {
        watershed.sequence_delete(client.handle, index);
      },
      `delete ${name} @${index + 1}`,
    );
  }

  // ── rendering ─────────────────────────────────────────────────────────────
  function drawRiver(routeEl: HTMLElement, count: number) {
    let svg = routeEl.querySelector("svg.route-river");
    if (!(svg instanceof SVGSVGElement)) {
      svg = document.createElementNS(SVG_NS, "svg");
      svg.classList.add("route-river");
      svg.setAttribute("aria-hidden", "true");
      svg.append(document.createElementNS(SVG_NS, "path"));
      routeEl.prepend(svg);
    }
    const path = svg.querySelector("path");
    if (!path) return;
    // A smooth meander through every station point, extended one step above
    // the first and below the last so the river runs off the pane.
    const pts: Array<[number, number]> = [];
    for (let i = -1; i <= count; i++) pts.push([xAt(i), yAt(i)]);
    let d = `M ${pts[0][0]} ${pts[0][1]}`;
    for (let i = 1; i < pts.length - 1; i++) {
      const mx = (pts[i][0] + pts[i + 1][0]) / 2;
      const my = (pts[i][1] + pts[i + 1][1]) / 2;
      d += ` Q ${pts[i][0]} ${pts[i][1]} ${mx} ${my}`;
    }
    const last = pts[pts.length - 1];
    d += ` L ${last[0]} ${last[1]}`;
    path.setAttribute("d", d);
  }

  function buildStation(client: RigClient, name: string): HTMLElement {
    const st = document.createElement("div");
    st.className = "station";
    const dot = document.createElement("span");
    dot.className = "station-dot";
    dot.setAttribute("aria-hidden", "true");
    const no = document.createElement("span");
    no.className = "station-no annot";
    no.setAttribute("data-station-no", "");
    const label = document.createElement("button");
    label.type = "button";
    label.className = "station-name";
    label.textContent = name;
    label.setAttribute(
      "aria-label",
      `Select ${name} on ${CLIENT_LABEL[client.id]}`,
    );
    label.addEventListener("click", () => {
      const data = pane(client);
      data.selected = data.selected === name ? null : name;
      renderRoute(client);
    });
    st.append(dot, no, label);
    return st;
  }

  function rebuildGaps(client: RigClient, routeEl: HTMLElement, count: number) {
    for (const gap of routeEl.querySelectorAll(".gap")) gap.remove();
    for (let i = 0; i <= count; i++) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "gap";
      btn.textContent = "+";
      btn.setAttribute(
        "aria-label",
        `Insert a waypoint at position ${i + 1} on ${CLIENT_LABEL[client.id]}`,
      );
      btn.title = `Insert a waypoint at position ${i + 1}`;
      const x = (xAt(i - 1) + xAt(i)) / 2;
      const y = PAD_Y + i * ROW_H;
      btn.style.transform = `translate(${x - 10}px, ${y - 10}px)`;
      btn.addEventListener("click", () => localInsert(client.id, i));
      routeEl.append(btn);
    }
  }

  function updateActionBar(client: RigClient, names: string[]) {
    const bar = client.el.querySelector("[data-route-actions]");
    if (!bar) return;
    const data = pane(client);
    const i = data.selected == null ? -1 : names.indexOf(data.selected);
    for (const btn of bar.querySelectorAll("button[data-act]")) {
      if (!(btn instanceof HTMLButtonElement)) continue;
      const act = btn.getAttribute("data-act");
      btn.disabled =
        i < 0 ||
        (act === "up" && i === 0) ||
        (act === "down" && i === names.length - 1);
    }
    const label = bar.querySelector("[data-selected]");
    if (label) label.textContent = data.selected ?? "select a station";
  }

  function renderRoute(client: RigClient) {
    const routeEl = client.el.querySelector("[data-route]");
    if (!(routeEl instanceof HTMLElement)) return;
    const data = pane(client);
    const prev = data.order;
    const names = values(client);
    if (data.selected != null && !names.includes(data.selected))
      data.selected = null;

    routeEl.style.height = `${routeHeight(names.length)}px`;
    drawRiver(routeEl, names.length);

    const seen = new Set<string>();
    names.forEach((name, i) => {
      seen.add(name);
      let st = data.stationEls.get(name);
      if (!st) {
        st = buildStation(client, name);
        data.stationEls.set(name, st);
        routeEl.append(st);
      }
      st.style.transform = `translate(${xAt(i) - 8}px, ${yAt(i) - 8}px)`;
      const no = st.querySelector("[data-station-no]");
      if (no) no.textContent = String(i + 1);
      st.classList.toggle("pending", client.pending.includes("st:" + name));
      st.classList.toggle("selected", data.selected === name);
    });
    for (const [name, el] of data.stationEls) {
      if (!seen.has(name)) {
        el.remove();
        data.stationEls.delete(name);
      }
    }
    rebuildGaps(client, routeEl, names.length);
    updateActionBar(client, names);

    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${client.pending.length} pending`;
      badge.classList.toggle("is-pending", client.pending.length > 0);
    }

    data.order = names;
    // Field notes: flash every position whose value changed — magenta on the
    // origin's optimistic render, ink as a sequenced op lands on a replica.
    if (notes?.active && prev != null) {
      const changed = names
        .map((name, i) => (prev[i] !== name ? data.stationEls.get(name) : null))
        .filter((el): el is HTMLElement => el != null);
      notes.flashEls(changed, submitting);
    }
  }

  rig = createSluiceRig({
    rig: "[data-route-rig]",
    status: "[data-route-status]",
    section: "#route-demo",
    control: "route",
    document: "sequence-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      // One client creates the sequence, attaches it under the root map, and
      // seeds the initial route; the others resolve the shared handle. All of
      // this drains inside setup's settle, so the visible timeline is clean.
      const a = clients["a"];
      const seq = okValue<unknown>(watershed.create_sequence(a.doc));
      a.handle = seq;
      const runtimeA = watershed.runtime_of(a.doc);
      runtime.set(
        runtimeA,
        "root",
        SEQ_ADDRESS,
        watershed.sequence_handle_of(seq),
      );
      INITIAL_ROUTE.forEach((name, i) => {
        watershed.sequence_insert(seq, i, json.string(name));
      });
      sluice.settle(server);
      CLIENT_IDS.forEach((id, i) => {
        const client = clients[id];
        if (id !== "a") {
          const rt = watershed.runtime_of(client.doc);
          const stored = some<unknown>(runtime.get(rt, "root", SEQ_ADDRESS));
          client.handle = okValue<unknown>(
            watershed.resolve_sequence(client.doc, stored),
          );
        }
        client.data = {
          stationEls: new Map(),
          order: null,
          selected: null,
          nameCursor: i,
        } as unknown as Record<string, unknown>;
        // Reset re-runs setup against panes that still hold old station DOM.
        client.el.querySelector("[data-route]")?.replaceChildren();
      });
    },
    render: renderRoute,
    canonical: (client) => JSON.stringify(values(client)),
  });
  if (!rig) return;

  const rigEl = document.querySelector("[data-route-rig]");
  const noteToggle = document.querySelector("[data-route-notes]");
  const noteEl = document.querySelector("[data-route-note]");
  if (
    rigEl &&
    noteToggle instanceof HTMLInputElement &&
    noteEl instanceof HTMLElement
  ) {
    notes = createRigNotes({
      rig: rigEl,
      toggle: noteToggle,
      note: noteEl,
      caption:
        "SharedSequence — items keep identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers. Watch a station flash magenta the moment a client edits the route, then ink on every replica as the op is sequenced and applied; the newest log line boxes as each op lands.",
    });
  }

  // Per-pane action bar: acts on that pane's selected station.
  for (const id of CLIENT_IDS) {
    const client = rig.clients[id];
    const bar = client.el.querySelector("[data-route-actions]");
    if (!bar) continue;
    bar.addEventListener("click", (event) => {
      const btn =
        event.target instanceof Element
          ? event.target.closest("button[data-act]")
          : null;
      if (!(btn instanceof HTMLButtonElement) || btn.disabled) return;
      const data = pane(client);
      if (data.selected == null) return;
      const names = values(client);
      const i = names.indexOf(data.selected);
      if (i < 0) return;
      switch (btn.getAttribute("data-act")) {
        case "up":
          localMove(id, i, i - 1, data.selected);
          break;
        case "down":
          localMove(id, i, i + 1, data.selected);
          break;
        case "rename":
          localRename(id, i, data.selected);
          break;
        case "delete":
          localDelete(id, i, data.selected);
          break;
      }
    });
  }

  // Race a move: B and C move the same waypoint opposite ways, concurrently.
  document.querySelector("[data-route-race-move]")?.addEventListener("click", () => {
    if (!rig) return;
    const bNames = values(rig.clients["b"]);
    const cNames = values(rig.clients["c"]);
    for (const name of bNames) {
      const iB = bNames.indexOf(name);
      const iC = cNames.indexOf(name);
      if (iB > 0 && iC >= 0 && iC < cNames.length - 1) {
        localMove("b", iB, iB - 1, name);
        localMove("c", iC, iC + 1, name);
        return;
      }
    }
  });

  // Crowd an insert: B and C insert different waypoints at the same position.
  document
    .querySelector("[data-route-race-insert]")
    ?.addEventListener("click", () => {
      if (!rig) return;
      localInsert("b", Math.min(2, values(rig.clients["b"]).length));
      localInsert("c", Math.min(2, values(rig.clients["c"]).length));
    });

  document.querySelector("[data-route-reset]")?.addEventListener("click", () => rig?.reset());
}
```

- [ ] **Step 2: Write the demo component**

Create `website/src/components/SequenceDemo.astro`. The rig/channel/controls skeleton and their styles deliberately mirror `DirectoryDemo.astro` (same grid areas, same op-log/flow-dot/status CSS); the tree styles are replaced by route/station styles.

```astro
---
const clients = [
  { id: "a", name: "Client A" },
  { id: "b", name: "Client B" },
  { id: "c", name: "Client C" },
];
const actions = [
  { act: "up", glyph: "↑", label: "Move the selected waypoint upstream" },
  { act: "down", glyph: "↓", label: "Move the selected waypoint downstream" },
  { act: "rename", glyph: "✎", label: "Rename the selected waypoint" },
  { act: "delete", glyph: "×", label: "Delete the selected waypoint" },
];
---

<section id="route-demo" class="demo" aria-labelledby="route-demo-title">
  <div class="demo-head" data-reveal="rise">
    <h2 id="route-demo-title">A shared portage route, live</h2>
    <p>
      All three clients are real <code>watershed</code> documents sharing one
      <code>SharedSequence</code> — an ordered list of waypoints down a river.
      One client creates it and shares the handle; the others resolve it. They
      talk to one <code>sluice</code>, the in-memory server that ships in the
      library for deterministic tests — the real runtime, no backend. Local
      edits are drawn in <strong class="k-pending">magenta</strong> until the
      sluice stamps them; server-sequenced state is
      <strong class="k-seq">ink</strong>.
    </p>
    <p class="demo-hint">
      Select a station to move, rename, or delete it, or press
      <strong>+</strong> between stations to insert one. Then stage a race:
      <strong>Race a move</strong> has B and C drag the same waypoint opposite
      ways; <strong>Crowd an insert</strong> has them insert different
      waypoints at the same spot. Both converge — a move follows its waypoint
      and concurrent inserts both survive, because ops name items, not index
      numbers.
    </p>
  </div>

  <p class="field-note" data-route-note role="note" hidden></p>

  <div class="rig" data-route-rig>
    {
      clients.map((c) => (
        <article
          class="client"
          data-client={c.id}
          aria-label={`${c.name} replica`}
          style={`grid-area: ${c.id}`}
        >
          <header class="client-head">
            <h3>{c.name}</h3>
            <span class="pending-count annot" data-pending-count>0 pending</span>
          </header>
          <div class="route" data-route aria-label={`${c.name} route`} />
          <div class="route-actions" data-route-actions>
            <span class="selected-label annot" data-selected>
              select a station
            </span>
            {actions.map((a) => (
              <button
                type="button"
                class="node-action"
                data-act={a.act}
                aria-label={`${a.label} on ${c.name}`}
                title={a.label}
                disabled
              >
                {a.glyph}
              </button>
            ))}
          </div>
        </article>
      ))
    }

    <div class="channel" style="grid-area: seq">
      <div class="seq-node" data-seq-node>
        <span class="annot">Sequencer</span>
        <output
          class="seq-counter"
          data-seq-counter
          aria-label="Latest sequence number"
        >
          SN&nbsp;0
        </output>
      </div>
      <ol
        class="op-log"
        data-op-log
        aria-live="polite"
        aria-label="Sequenced operations, newest first"
      >
      </ol>
    </div>

    <div class="flow-layer" data-flow-layer aria-hidden="true"></div>
  </div>

  <div class="demo-controls" data-reveal="rise">
    <label class="latency">
      <span class="annot">Link latency</span>
      <input
        type="range"
        min="100"
        max="2000"
        step="100"
        value="700"
        data-route-latency
        disabled
      />
      <output data-route-latency-out>700 ms</output>
    </label>
    <label class="pace">
      <span class="annot">Animation speed</span>
      <input
        type="range"
        min="0.25"
        max="2"
        step="0.25"
        value="0.5"
        data-route-pace
        title="Playback multiplier — how fast the whole animation plays on screen. It only changes how fast you watch; the simulated outcome is identical at any speed."
        disabled
      />
      <output data-route-pace-out>0.5×</output>
    </label>
    <label class="field-notes-toggle">
      <input
        type="checkbox"
        data-route-latency-variance
        title="Add random ±50 ms jitter to each hop's link latency, so ops no longer travel in lock-step and arrival order can shuffle."
        disabled
      />
      <span class="annot">Jitter ±50&nbsp;ms</span>
    </label>
    <label class="field-notes-toggle">
      <input
        type="checkbox"
        data-route-notes
        title="Annotate the demo with hand-drawn field notes while ops animate."
        disabled
      />
      <span class="annot">Field notes</span>
    </label>
    <button type="button" class="race-btn" data-route-race-move disabled>
      Race a move
    </button>
    <button type="button" class="race-btn" data-route-race-insert disabled>
      Crowd an insert
    </button>
    <button
      type="button"
      class="reset-btn"
      data-route-reset
      aria-label="Reset all replicas to the initial route"
      disabled
    >
      Reset
    </button>
    <p class="status" data-route-status role="status">
      <span class="stamp converged">Converged</span>
      all routes identical · nothing pending
    </p>
  </div>

  <p class="controls-hint">
    <strong>Link latency</strong> is the simulated network delay — the demo’s
    physics. <strong>Animation speed</strong> just scales how fast that plays on
    screen. <strong>Jitter</strong> adds random ±50&nbsp;ms per hop, so ops stop
    travelling in lock-step and their arrival order can shuffle. Only latency
    and jitter change the outcome.
  </p>

  <noscript>
    <p class="demo-noscript">
      The live demo needs JavaScript — it runs the real watershed runtime and
      the in-memory <code>sluice</code> as compiled JavaScript in your browser.
      The rest of the page works fine without it.
    </p>
  </noscript>

  <p class="demo-noscript" data-route-fallback hidden>
    The live demo couldn’t start — it runs the real watershed runtime against
    the in-memory <code>sluice</code> as compiled JavaScript, and this browser
    didn’t load it. The rest of the page works fine without it.
  </p>
</section>

<script>
  try {
    const { initSequenceDemo } = await import("../scripts/sequence-demo.ts");
    initSequenceDemo();
  } catch (error) {
    console.error("watershed sequence demo failed to start", error);
    const note = document.querySelector("[data-route-fallback]");
    if (note instanceof HTMLElement) note.hidden = false;
  }
</script>

<style>
  .demo {
    padding: var(--space-section) var(--content-pad);
    border-bottom: 1px solid var(--hairline);
  }

  .demo-head {
    max-width: 68rem;
    margin-inline: auto;
  }

  h2 {
    font-size: var(--text-h2);
    font-weight: 620;
    font-stretch: 118%;
    letter-spacing: -0.015em;
    line-height: 1.05;
  }

  .demo-head p {
    margin-top: var(--space-lg);
  }

  .demo-hint {
    color: var(--ink);
    font-size: var(--text-sm);
    font-weight: 500;
  }

  .k-pending {
    color: var(--overprint-deep);
  }

  .k-seq {
    color: var(--ink);
  }

  .field-note {
    max-width: 68rem;
    margin: var(--space-lg) auto 0;
    padding-inline-start: var(--space-md);
    border-inline-start: 3px solid var(--overprint);
    color: var(--ink);
    font-size: var(--text-sm);
    line-height: 1.6;
  }

  .rig {
    position: relative;
    max-width: 68rem;
    margin: var(--space-xl) auto 0;
    display: grid;
    grid-template-areas:
      "a seq b"
      "c c   c";
    grid-template-columns: 1fr minmax(9rem, 0.55fr) 1fr;
    gap: var(--space-lg);
    align-items: start;
  }

  .rig .client[data-client="c"] {
    justify-self: center;
    width: min(100%, 24rem);
  }

  .client {
    border: 1px solid var(--ink);
    background: var(--bg);
    display: flex;
    flex-direction: column;
    min-height: 12rem;
  }

  .client-head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    padding: var(--space-sm) var(--space-md);
    border-bottom: 1px solid var(--hairline);
  }

  .client-head h3 {
    font-size: 1rem;
    font-weight: 650;
    font-stretch: 115%;
    letter-spacing: 0.01em;
    text-transform: uppercase;
  }

  .pending-count {
    color: var(--muted);
    transition: color var(--dur-state) var(--ease-out-quart);
  }

  .pending-count.is-pending {
    color: var(--overprint-deep);
  }

  /* ── the route ─────────────────────────────────────────────────────────── */
  /* Station and gap DOM is built at runtime by sequence-demo.ts, so it never
     carries Astro's scoping attribute — scope via :global under .route, the
     same pattern the directory tree uses. */
  .route {
    position: relative;
    margin: var(--space-sm);
    flex: 1;
  }

  .route :global(svg.route-river) {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .route :global(svg.route-river path) {
    fill: none;
    stroke: var(--waterline);
    stroke-width: 3;
    opacity: 0.35;
  }

  .route :global(.station) {
    position: absolute;
    top: 0;
    left: 0;
    display: flex;
    align-items: center;
    gap: 0.45rem;
    transition: transform 450ms var(--ease-out-quart);
    will-change: transform;
  }

  @media (prefers-reduced-motion: reduce) {
    .route :global(.station) {
      transition: none;
    }
  }

  .route :global(.station-dot) {
    width: 12px;
    height: 12px;
    border: 2px solid var(--ink);
    border-radius: 50%;
    background: var(--bg);
    flex: none;
  }

  .route :global(.station-no) {
    color: var(--muted);
    font-size: 0.65rem;
    min-width: 1.1em;
  }

  .route :global(.station-name) {
    border: none;
    background: none;
    padding: 0.15rem 0.35rem;
    border-radius: 2px;
    font-family: var(--font-mono);
    font-size: 0.85rem;
    color: var(--waterline);
    font-weight: 600;
    white-space: nowrap;
    cursor: pointer;
  }

  .route :global(.station-name:hover) {
    background: var(--overprint-faint);
  }

  .route :global(.station.selected .station-name) {
    outline: 1px solid var(--ink);
  }

  .route :global(.station.pending .station-name) {
    color: var(--overprint-deep);
  }

  .route :global(.station.pending .station-dot) {
    border-color: var(--overprint);
  }

  .route :global(.gap) {
    position: absolute;
    top: 0;
    left: 0;
    width: 20px;
    height: 20px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 1px solid var(--hairline);
    border-radius: 50%;
    background: var(--bg);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    line-height: 1;
    color: var(--muted);
    cursor: pointer;
    opacity: 0.45;
    transition:
      opacity var(--dur-feedback) var(--ease-out-quart),
      border-color var(--dur-feedback) var(--ease-out-quart),
      color var(--dur-feedback) var(--ease-out-quart);
  }

  .route :global(.gap:hover:enabled) {
    opacity: 1;
    border-color: var(--overprint);
    color: var(--overprint-deep);
  }

  /* ── per-pane action bar ───────────────────────────────────────────────── */
  .route-actions {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    padding: var(--space-sm) var(--space-md);
    border-top: 1px solid var(--hairline);
  }

  .selected-label {
    color: var(--muted);
    font-family: var(--font-mono);
    font-size: 0.72rem;
    margin-inline-end: auto;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .node-action {
    padding: 0.05rem 0.4rem;
    border: 1px solid var(--hairline);
    border-radius: 2px;
    background: var(--bg);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    line-height: 1.2;
    color: var(--muted);
    cursor: pointer;
    transition:
      background var(--dur-feedback) var(--ease-out-quart),
      border-color var(--dur-feedback) var(--ease-out-quart),
      color var(--dur-feedback) var(--ease-out-quart);
  }

  .node-action:hover:enabled {
    background: var(--overprint-faint);
    border-color: var(--overprint);
    color: var(--overprint-deep);
  }

  .node-action:active:enabled {
    transform: scale(0.97);
  }

  .node-action:disabled {
    opacity: 0.45;
    cursor: default;
  }

  /* ── channel / sequencer / op log ──────────────────────────────────────── */
  .channel {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-md);
    padding-top: clamp(var(--space-md), 5vw, 3.5rem);
  }

  .seq-node {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-2xs);
    padding: var(--space-sm) var(--space-lg);
    border: 1px solid var(--ink);
    border-radius: 999px;
    background: var(--bg);
  }

  .seq-counter {
    font-family: var(--font-mono);
    font-size: 1.25rem;
    font-variant-numeric: tabular-nums;
    color: var(--ink);
  }

  .seq-counter.stamped {
    animation: stamp 380ms var(--ease-out-quart);
  }

  @keyframes stamp {
    0% {
      color: var(--overprint);
      transform: scale(1.12);
    }
    100% {
      color: var(--ink);
      transform: none;
    }
  }

  .op-log {
    list-style: none;
    margin: 0;
    padding: 0;
    width: 100%;
    font-family: var(--font-mono);
    font-size: 0.72rem;
    line-height: 1.6;
    color: var(--muted);
    overflow: hidden;
    max-height: 13.5rem;
    mask-image: linear-gradient(black 55%, transparent 96%);
  }

  .op-log :global(li) {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0 0.4rem;
    justify-content: center;
    padding: 0.12rem 0;
  }

  .op-log :global(.op-meta) {
    color: var(--muted);
  }

  .op-log :global(.op-path) {
    color: var(--waterline);
  }

  .op-log :global(.op-kind) {
    color: var(--ink);
  }

  .op-log :global(li:first-child .op-meta) {
    color: var(--ink);
  }

  .flow-layer {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: var(--z-flow);
  }

  :global(.flow-dot) {
    position: absolute;
    top: 0;
    left: 0;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--overprint);
  }

  :global(.flow-dot.sequenced) {
    background: var(--ink);
  }

  :global(.flow-dot-label) {
    position: absolute;
    left: 50%;
    bottom: calc(100% + 4px);
    transform: translateX(-50%);
    white-space: nowrap;
    font-size: 0.625rem;
    line-height: 1;
    font-weight: 600;
    letter-spacing: 0.01em;
    padding: 2px 5px;
    border-radius: 4px;
    color: var(--bg);
    background: var(--overprint);
  }

  :global(.flow-dot.sequenced .flow-dot-label) {
    background: var(--ink);
  }

  /* ── controls ──────────────────────────────────────────────────────────── */
  .demo-controls {
    max-width: 68rem;
    margin: var(--space-xl) auto 0;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-xl);
  }

  .latency,
  .pace {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
  }

  .latency input,
  .pace input {
    accent-color: var(--overprint);
    width: clamp(8rem, 18vw, 14rem);
  }

  .latency output,
  .pace output {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-variant-numeric: tabular-nums;
    min-width: 5ch;
  }

  .field-notes-toggle {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    cursor: pointer;
  }

  .field-notes-toggle input {
    accent-color: var(--overprint);
    width: 1.05rem;
    height: 1.05rem;
    cursor: pointer;
  }

  .controls-hint {
    max-width: 68rem;
    margin: var(--space-sm) auto 0;
    color: var(--muted);
    font-size: var(--text-sm);
    line-height: 1.6;
  }

  .race-btn {
    padding: 0.65rem 1.2rem;
    border: 1px solid var(--ink);
    background: var(--bg);
    font-weight: 600;
    cursor: pointer;
    transition:
      background var(--dur-feedback) var(--ease-out-quart),
      transform var(--dur-feedback) var(--ease-out-quart);
  }

  .race-btn:hover:enabled {
    background: var(--overprint-faint);
  }

  .race-btn:active:enabled {
    transform: scale(0.97);
  }

  .reset-btn {
    padding: 0.65rem 1.2rem;
    border: 1px solid var(--hairline);
    background: var(--bg);
    color: var(--muted);
    font-weight: 400;
    cursor: pointer;
    transition:
      background var(--dur-feedback) var(--ease-out-quart),
      color var(--dur-feedback) var(--ease-out-quart),
      transform var(--dur-feedback) var(--ease-out-quart);
  }

  .reset-btn:hover:enabled {
    background: var(--surface);
    color: var(--ink);
  }

  .reset-btn:active:enabled {
    transform: scale(0.97);
  }

  .race-btn:disabled,
  .reset-btn:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .status {
    font-size: var(--text-sm);
    color: var(--muted);
    display: flex;
    align-items: center;
    gap: var(--space-sm);
  }

  .status :global(.stamp) {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    padding: 0.2rem 0.55rem;
    border: 1.5px solid currentColor;
    transform: rotate(-2deg);
  }

  .status :global(.stamp.converged) {
    color: var(--waterline);
  }

  .status :global(.stamp.revising) {
    color: var(--overprint-deep);
  }

  .demo-noscript {
    max-width: 68rem;
    margin: var(--space-lg) auto 0;
    color: var(--overprint-deep);
  }

  @media (max-width: 1080px) {
    .rig {
      grid-template-areas: "a" "seq" "b" "c";
      grid-template-columns: 1fr;
    }

    .rig .client[data-client="c"] {
      justify-self: stretch;
      width: auto;
    }

    .op-log {
      max-height: 5.7rem;
    }
  }

  @media (pointer: coarse) {
    .node-action {
      min-inline-size: 2.2rem;
      min-block-size: 2rem;
    }

    .route :global(.gap) {
      width: 26px;
      height: 26px;
      opacity: 1;
    }

    .race-btn,
    .reset-btn {
      padding: 0.85rem 1.2rem;
    }
  }
</style>
```

- [ ] **Step 3: Write the page**

Create `website/src/pages/sequence.astro`:

```astro
---
import Sheet from "../layouts/Sheet.astro";
import SequenceDemo from "../components/SequenceDemo.astro";
import Ecosystem from "../components/Ecosystem.astro";
---

<Sheet
  title="watershed — SharedSequence demo"
  description="Three browser clients edit one ordered portage route through watershed's real sequence_kernel — a CRDT sequence where items keep stable identity, so concurrent inserts, moves, and deletes merge without renumbering fights. Optimistic edits, server-sequenced convergence."
>
  <header class="page-hero">
    <div class="page-hero-inner">
      <p class="eyebrow annot">
        <a href="/structures/sequences">← Sequences</a> · SharedSequence
      </p>
      <h1>One route.<br />Many hands. <em>One order.</em></h1>
      <p class="lede">
        An index only means something against one version of a list.
        <strong>SharedSequence</strong> gives every item a stable identity
        beneath its index: you say <em>insert at 2</em> or
        <em>move 4 to 1</em>, but the delta that ships names the item, not the
        slot. Two surveyors can rearrange the same stretch of river at the same
        instant — moves follow their waypoint, concurrent inserts both land —
        and every replica converges on the same order. watershed’s
        <code>sequence_kernel</code> models that identity and converges.
      </p>
      <div class="cta-row">
        <a class="cta-quiet" href="#route-demo">Jump to the demo ↓</a>
        <a class="cta-quiet" href="https://github.com/tylerbutler/watershed">
          Read the source
        </a>
      </div>
    </div>
  </header>

  <main>
    <SequenceDemo />
  </main>
  <Ecosystem />
</Sheet>

<script>
  import { initReveals } from "../scripts/motion.js";
  initReveals();
</script>

<style>
  .page-hero {
    padding: clamp(3.5rem, 9vw, 7.5rem) var(--content-pad)
      clamp(2.5rem, 6vw, 5rem);
    border-bottom: 1px solid var(--hairline);
  }

  .page-hero-inner {
    max-width: 68rem;
    margin-inline: auto;
  }

  .eyebrow {
    color: var(--muted);
    margin: 0 0 var(--space-lg);
  }

  .eyebrow a {
    color: var(--waterline);
    text-decoration: none;
  }

  .eyebrow a:hover {
    color: var(--overprint-deep);
  }

  h1 {
    font-size: var(--text-display);
    font-weight: 640;
    font-stretch: 122%;
    line-height: 0.99;
    letter-spacing: -0.025em;
    max-width: 16ch;
  }

  h1 em {
    font-style: normal;
    color: var(--overprint-deep);
  }

  .lede {
    margin-top: var(--space-xl);
    font-size: clamp(1.125rem, 0.6vw + 1rem, 1.3125rem);
    line-height: 1.6;
    max-width: 56ch;
    color: var(--ink);
  }

  .cta-row {
    margin-top: var(--space-xl);
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-lg);
  }

  .cta-quiet {
    font-weight: 500;
    color: var(--waterline);
  }
</style>
```

- [ ] **Step 4: Build**

Run: `cd website && pnpm build`
Expected: success, and `ls website/dist/sequence/index.html` shows the page was rendered.

- [ ] **Step 5: Manual smoke test**

Run: `cd website && pnpm dev` and open `http://localhost:4321/sequence`. Check, in order:

1. Three panes each show the five-station route along a meandering river line; status reads **Converged**.
2. Insert (`+` between stations), then move/rename/delete via the action bar after selecting a station — the edit prints magenta on the origin, dots flow through the sequencer, all panes converge, status returns to **Converged**.
3. **Race a move** at high latency (drag Link latency up first): B and C disagree optimistically, then all three panes settle on one identical order.
4. **Crowd an insert**: both new waypoints appear on every pane, adjacent, same order everywhere.
5. **Field notes** on: caption appears; a local edit circles the changed stations magenta on the origin; as the op sequences, changed stations circle ink on the other panes and the newest op-log line gets a box; toggling off clears marks.
6. **Reset** restores the initial five-station route on all panes; no console errors anywhere above.

Fix anything that fails before committing.

- [ ] **Step 6: Commit**

```bash
git add website/src/scripts/sequence-demo.ts website/src/components/SequenceDemo.astro website/src/pages/sequence.astro
git commit -m "feat(website): add SharedSequence portage-route demo

Three real watershed documents share one sequence through the sluice
rig; stations are keyed by waypoint name and slide on reorder. Race
buttons stage concurrent moves of one waypoint and same-position
inserts; field notes flash changed stations via rig-notes."
```

---

### Task 5: Record the rig-demo field-notes model

**Files:**
- Modify: `docs/field-notes.md` (append a section at the end)

- [ ] **Step 1: Append the section**

Add to the end of `docs/field-notes.md`:

```markdown
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
so a childList mutation *is* the "op sequenced" moment.

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/field-notes.md
git commit -m "docs: record rig-demo field-notes model

rig-notes.ts inverts tutorial.js's contract for sluice-rig demos: the
demo owns the diff, the module only draws. Sequence demo is the
reference."
```

---

### Task 6: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full build**

Run: `cd website && pnpm build`
Expected: success with no warnings about the new pages.

- [ ] **Step 2: Cross-surface check**

Run: `rg -l "SharedSequence" website/dist/index.html website/dist/models/index.html website/dist/structures/index.html website/dist/structures/sequences/index.html website/dist/sequence/index.html`
Expected: all five files listed.

- [ ] **Step 3: Link walk**

With `pnpm dev` running, confirm by hand:

1. Homepage field-sheet stack shows the SharedSequence sheet and links to `/structures/sequences#sequence`.
2. `/structures` index lists the Sequences family; family ordinals on `/structures/coordination` and `/structures/transforms` shifted to 05/06 and their prev/next navigation still cycles correctly.
3. The SharedSequence plate on `/structures/sequences` shows "Open the live SharedSequence demo →" linking to `/sequence`.
4. `/models` lists SharedSequence in the CRDT column, linking to `/structures/sequences#sequence`, and the OT trade-off line reads naturally.
5. `/sequence` hero's "← Sequences" eyebrow links back to `/structures/sequences`.

- [ ] **Step 4: Re-run the demo smoke checklist**

Repeat Task 4 Step 5's six checks once more on the final build (`pnpm preview` after `pnpm build`, or the dev server). All must pass.
```
