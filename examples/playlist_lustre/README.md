# watershed playlist — SharedSequence demo

A collaborative, reorderable playlist as a Lustre single-page app. Where
[`dice_lustre`](../dice_lustre) edits one key on a map and
[`sudoku_lustre`](../sudoku_lustre) fans out across four nested channels, this
example exists to exercise the one operation no other watershed DDS offers:
**`move`**, a convergent reorder of an ordered list.

## Why a sequence and not a map

You can fake an ordered list on a `SharedMap` by storing an index or a sort key
per entry, and it works right up until two clients reorder concurrently — then
you get duplicated positions, lost entries, or an order the two tabs disagree
about. A `SharedSequence` converges: two tabs dragging the same track to
different places land on the *same* order, with every track still present
exactly once.

That property is pinned by a test rather than left as a claim —
`concurrent_sequence_move_preserves_every_element_test` in
[`test/watershed/sluice/driver_js_test.gleam`](../../test/watershed/sluice/driver_js_test.gleam)
runs a move racing a replace through the in-memory sluice and asserts length,
uniqueness, and survival of both edits. It needs no server and runs in
`gleam test --target javascript`.

## Op coverage

All four sequence mutations, against a single channel:

| UI            | Call                       | Note                                            |
| ------------- | -------------------------- | ----------------------------------------------- |
| **Add**       | `sequence_insert(seq, n, v)` | Appends: the insert index may equal the length (`0..length`) |
| **↑ / ↓**     | `sequence_move(seq, i, j)` | **Destination is interpreted after removal** — down one is `to = from + 1`, up one is `to = from - 1` |
| **Rename**    | `sequence_replace(seq, i, v)` | One watershed op composed from lattice delete + insert deltas, not a native lattice primitive |
| **✕**         | `sequence_delete(seq, i)`  | |

Plus `subscribe_sequence`, which delivers a `SequenceChanged` carrying the full
post-edit value list for local and remote edits alike.

### Edits return `Result`, and that matters

Unlike `watershed_js.set` on a map, every sequence mutation returns
`Result(Nil, String)`. Index-addressed ops on a *shared* list can legitimately
fail: a peer may delete the row out from under this tab between render and
click. The app renders the runtime's own error message in a banner instead of
asserting — that is the honest shape for this API, and the reason the example
never uses `let assert` on an edit.

## Bootstrapping

The root map is typed ([`src/doc_schema.gleam`](src/doc_schema.gleam)) with one
plain field and one channel field:

```text
root ─┬─ "title"  = "watershed shared playlist"
      └─ "tracks" = handle ──▶ SharedSequence of track objects
```

Every tab calls `watershed_lustre.ensure_sequence` unconditionally on connect;
it creates and attaches a sequence only when the slot is empty, so tabs don't
race to duplicate one.

Track values are plain JSON objects encoded by
[`src/track.gleam`](src/track.gleam) — a sequence holds arbitrary JSON, so the
element shape is the app's business, not the DDS's. Decoding is deliberately
fallible: a malformed element renders as a placeholder row and still reorders
and deletes correctly, because those ops address by index.

## Prerequisites

Start a levee dev server from the `levee` repo:

```sh
just server   # registers tenant "dev-tenant", listens on :4000
```

## Run it

```sh
cd examples/playlist_lustre
pnpm install
pnpm run build
pnpm run serve      # http://localhost:8080
```

Open two browser tabs. Add tracks in one and watch them appear in the other;
reorder from both tabs at once and watch the orders reconcile. Each tab joins
as a distinct `web-XXXX` user so they are genuinely separate connections.

The **Force reconnect** button drops the socket mid-session — reorder during the
reconnect and nothing is lost.

## Headless smoke test

`src/smoke.gleam` drives two clients from Node against a running `just server`,
racing a move on one client against a replace on the other:

```sh
gleam build --target javascript
pnpm exec esbuild build/dev/javascript/playlist_lustre/smoke.mjs \
  --bundle --format=esm --outfile=dist/smoke.mjs
node smoke/run.mjs   # supplies a WebSocket global for phoenix.js
# → SMOKE PASS: concurrent move and replace converged
```

It asserts convergence, that the racing replace survived the move, that no
track was duplicated, and that an out-of-bounds delete is refused rather than
silently clamped.

## Build check

```sh
gleam build --target javascript   # from this directory
```
