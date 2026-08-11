# retro_board_lustre

A collaborative retro board — sticky notes in three columns, votes, and a
presence roster — built on five watershed channels behind one root map. A
sticky-note wall is the canonical "many people editing the same board at once"
app, and every commercial one has a concurrent-add bug story. This demo is
built around the two moments where naive implementations lose data:

- **Concurrent add.** Two people add a card in the same instant. Under a naive
  last-writer-wins map keyed by index or count, one card disappears. Here each
  card is a fresh key in an add-wins OR-map, and both survive.
- **Concurrent vote.** Two people upvote the same card while a third
  downvotes. Under `get → +1 → set`, votes are silently lost — exactly the
  failure the website's [counter-bug page](../../website/src/pages/counter-bug.astro)
  argues in prose. Here votes are per-key PN-counter leaves in a `TallyMode`
  OR-map: +1, +1, −1 lands on +1, always, on every client.

Both claims are executable: `test/convergence_test.gleam` runs them as two
in-process clients over the in-memory sluice, and `pnpm run smoke` re-runs the
headline pair against a live floodgate server.

## The document

| Channel        | Kind                    | Holds                                  |
| -------------- | ----------------------- | -------------------------------------- |
| `notes`        | OR-map (`RegisterMode`) | note id → JSON-encoded note record     |
| `votes`        | OR-map (`TallyMode`)    | note id → signed tally                 |
| `went_well`    | SharedSequence          | display order for the column           |
| `to_improve`   | SharedSequence          | display order for the column           |
| `action_items` | SharedSequence          | display order for the column           |

A note record carries its authoritative column id plus a client-clock
`created` timestamp used only as a render tiebreaker:

```json
{ "text": "deploys are still scary", "column": "to_improve",
  "author": "web-4821", "created": 1754000000000 }
```

**Why tally mode and not `PnCounter`?** By design, not necessity —
`subscribe_pn_counter` exists on both facades. One `PnCounter` channel per
note would mean a channel create on every card and N subscriptions to manage;
`TallyMode` gives per-key PN-counter leaves in a single channel with a single
subscription. It also puts both of the OR-map's value modes side by side in
one app: the same channel kind stores LWW registers for the cards and
conflict-free arithmetic for the votes, and the mode split is one argument at
`ensure_or_map` time.

## The move is not atomic

Dragging a note between columns is three ops across two channel kinds: delete
from the source sequence, insert into the destination sequence, rewrite the
note's `column` register. There is no transaction spanning them. Under
concurrent moves of the same note by two clients, the reachable states include
the note's id sitting in two column sequences at once, or in none, or in a
sequence that disagrees with its register.

The app does not pretend otherwise. It applies one rule at render time — **the
`column` register is authoritative** (`src/board.gleam`):

- an id in a sequence whose column doesn't match the note's register is
  skipped when rendering that sequence;
- a note whose register names a column whose sequence doesn't contain it
  renders at the end of that column, ordered by `(created, id)`;
- a note whose register names no known column renders in an "unfiled" strip
  rather than being dropped.

The garbage entries are deliberately left in the sequences rather than
repaired on render: repair-on-render means every client issuing corrective ops
on every render, and those clients fighting each other. Instead the app
repairs opportunistically on user action — a cross-column move sweeps the id
out of *every* sequence, not just the source. The convergence suite pins that
two simultaneous cross-column moves of the same card leave both tabs rendering
it exactly once, in the same column (which column wins is wall-clock LWW and
deliberately unasserted).

## Edit vs delete — observed behaviour

One participant rewrites a card's text while another deletes it, in the same
tick. Observed (and pinned in `edit_vs_delete_converges_test`): **the edit
wins and the card comes back with the edited text.** The OR-map is an
observed-remove map — the delete covers only the writes the deleter had seen,
and the concurrent edit minted one it hadn't — so delete wins only when nobody
is touching the note. The delete's sequence sweep *does* stand, though, so the
resurrected card is in no sequence and reappears at the tail of its column via
the `created` tiebreaker: visible, not ghostly, and exactly once.

## The vote budget is advisory

A real retro gives everyone N votes. The "5 votes left" pill tracks them in
**local state only** — never in the document. A shared budget is a
coordination problem (two clients concurrently spending the last vote both
succeed), and solving it properly means `Claims` or `PactMap`, which is a
different demo. The budget resets on reload; the tally is the only thing that
converges.

## Running it

```sh
just integration-up        # floodgate dev server on :4000 (from the repo root)
cd examples/retro_board_lustre
pnpm install
pnpm run build
pnpm run serve             # http://localhost:8080
```

Open two browser tabs on the same `?document=` URL (the first tab mints one
and pushes it into the address bar). Add cards from both tabs at once, vote
from both, drag cards between columns, and watch the boards agree.

### How drag-and-drop is wired

Dragging uses the [`dnd` package](https://hex.pm/packages/dnd) (`dnd/groups`),
configured with `Operation: Unaltered` on both the same-group and cross-group
paths. The library runs the gesture — grip mousedown, ghost positioning, drop
tracking — but never reorders anything: on `DragEnd` the app reads the drag
system's `info`, resolves the endpoints by element id (ids survive a remote
edit reflowing the board mid-drag; indices would not), and issues the same
channel ops the "→ column" buttons issue. One deliberate subtlety: the note's
`column` register is rewritten only when the drop actually changes columns,
because the note record is whole-record LWW and a gratuitous rewrite on a
same-column reorder would clobber a peer's concurrent text edit. Drag is
mouse-only for now; the ↑/↓ and "→ column" buttons remain the touch and
keyboard path.

## Tests

```sh
gleam test        # codec round-trips, render-rule unit tests, and the
                  # convergence suite over the in-memory sluice — no server
pnpm run smoke    # the headline pair against a live floodgate
                  # (needs `just integration-up`)
```
