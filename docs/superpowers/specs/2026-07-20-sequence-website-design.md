# SharedSequence Website Integration Design

## Goal

Integrate the SharedSequence DDS into the watershed website: a catalog entry
with the standard field-sheet treatment, a dedicated live demo, field-notes
annotations on that demo, and the documentation copy that supports both.

The DDS itself is already implemented (`sequence_kernel.gleam`, runtime
integration, and JS facade). This work is website-only plus one entry in
`docs/field-notes.md`.

## Scope

Included:

- a new `sequences` category in `website/src/data/structures.ts` with a full
  SharedSequence entry;
- a dedicated demo page at `/sequence` with three client panes driven by the
  in-memory sluice and the JS runtime facade;
- event-driven field notes on the demo;
- a prose touch-up on the models page;
- a short entry in `docs/field-notes.md` recording the annotation model.

Excluded:

- guide-step (`/guide`) changes;
- README or developer-doc expansion;
- drag-and-drop reordering (interaction is button-based);
- anything for the future text DDS;
- changes to the shared homepage demo (`demo.js`).

## Catalog and Taxonomy

Add a `sequences` category to `structures.ts`. None of the existing five
categories fits an ordered list, and the planned text DDS will join this
category later.

The SharedSequence entry:

- `id`: `sequence`; `module`: `sequence_kernel`; `kind`: `"CRDT"`.
- `onHomepage`: `true`, so the field sheet appears in the homepage stack.
- `demoHref`: `/sequence`, so the plate links to the dedicated demo and the
  structure is excluded from the shared demo picker.

`kind` is `CRDT`, not `DDS`, despite the `Shared*` name. The site's `DDS`
label means "converges by the server's total order" and marks Fluid-compatible
ports. SharedSequence converges by lattice merge — deltas are
duplicate-tolerant and order-independent — and is not Fluid-compatible, so it
belongs beside PN Counter, OR-Map, and OR-Set in the CRDT column. The detail
page's `how` copy states this explicitly so the name does not mislead.

Draft copy (final wording set during implementation):

- **tagline**: "An ordered list many people can edit at once — insert, move,
  and reorder without losing anyone's changes."
- **rule**: "each item keeps a stable identity, so concurrent inserts, moves,
  and deletes merge instead of fighting over index numbers"
- **optimistic**: "your edit shows immediately in magenta; stations slide when
  the sequenced order lands"
- **summary**: "the sequenced list reloads intact; pending edits replay on top"
- **how**: two or three paragraphs covering: an index expresses intent but
  item identity is authoritative under concurrency; the lattice merge absorbs
  duplicate and reordered deltas; replace composes delete + insert into one
  pending entry, one wire op, one event batch.
- **useCases**: shared itineraries, checklists, and ordered plans; reorderable
  lists edited by many hands (playlists, priority queues); the substrate the
  future text DDS builds on.

The models page (`models.astro`) derives its DDS/CRDT membership lists from
`structures.ts`, so the new entry appears there automatically. One prose
change: the OT card's trade-off line calls OT "a natural fit for ordered
sequences" — add a clause acknowledging that the catalog now also contains a
merge-based sequence, so the comparison stays honest.

## Demo Page: `/sequence` — "Plotting the portage"

### Architecture

New files: `website/src/pages/sequence.astro` and
`website/src/scripts/sequence-demo.ts`, cloned from the directory demo's
architecture. `createSluiceRig` (from `scripts/demo/sluice-rig.ts`) drives
three real watershed documents — clients A, B, and C — through the in-memory
sluice. Client A calls `create_sequence` on the JS facade and attaches the
handle under the root map key `route` via `set_sequence_field`; B and C
resolve it with `ensure_sequence`/`resolve_sequence_field`. All edits go
through the public facade (`sequence_insert`, `sequence_delete`,
`sequence_move`, `sequence_replace`) and reads through `sequence_values`, so
the demo exercises the real runtime end to end: optimistic apply, pending
ops, and resubmit belong to the runtime, not the demo script.

Items are plain JSON strings — waypoint names from the site's toponym pool
("put-in", "mill-race weir", "kettle-run rapids", "low-ford portage",
"take-out", plus a spare-name pool for inserts, following the directory
demo's `FOLDER_NAMES` pattern). `replace` therefore reads as renaming a
waypoint.

### Rendering

Each pane draws a stylized SVG river polyline. Waypoints render as numbered,
labeled survey stations placed along the line in sequence order. The color
grammar is the site standard, read from CSS variables at draw time:

- sequenced stations in `--ink`;
- pending local edits in `--overprint` magenta until acknowledged.

When a remote or sequenced op changes the visible order, stations slide to
their new positions along the line.

### Interaction

Button-based, no drag, for accessibility:

- clicking a station selects it and exposes **move upstream**,
  **move downstream**, **rename** (replace), and **delete**;
- a small **+** affordance between stations inserts a new waypoint at that
  position;
- latency controls, flow dots, and the op log reuse the shared demo modules
  exactly as the directory page does.

Two race buttons stage the classic conflicts in one click:

- **Race a move** — client B moves a waypoint upstream while client C moves
  the same waypoint downstream. Panes disagree optimistically, then converge
  to one deterministic order.
- **Crowd an insert** — B and C insert different waypoints at the same
  position. Both survive in a deterministic order; nothing is renumbered
  away.

## Field Notes

Use the event-driven model from `docs/field-notes.md` (the model used for
SharedMap and the counters): no static marks. Before each op applies,
snapshot the station elements; flash the ones whose value or position
changed — magenta on the origin pane while the op is pending, ink as the op
sequences into each replica — and box-flash the newest op-log line as it is
sequenced. Motion is the lesson for a sequence, so the flash model fits.

Add a short section to `docs/field-notes.md` recording that the sequence demo
uses the event-driven model, as that document requires for new structures.

## Verification

- `gleam build --target javascript`, then the website build
  (`pnpm build` in `website/`), must pass.
- Manual smoke test: both race buttons converge identically across all three
  panes at high latency; field notes flash the changed stations and only the
  changed stations; the field sheet, detail page, and models page all show
  the new entry with working links.
