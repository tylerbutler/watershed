# watershed

A Gleam Fluid Framework DDS client toolkit for Erlang and JavaScript. It provides
collaborative data structures with optimistic local edits, convergence through
server sequencing, and reconnect safety. SharedMap is the anchor DDS;
SharedCounter, SharedSequence, SharedText, SharedRichText, OR-set, claims, and
the other channel kinds share the same runtime. An opt-in
[typed document layer](#typed-documents) declares a document's shape once.
[levee](https://github.com/tylerbutler/levee) is one compatible server
implementation.

Plan: [docs/plans/2026-07-01-gleam-sharedmap-client-plan.md](docs/plans/2026-07-01-gleam-sharedmap-client-plan.md).

## Architecture

```
┌─────────────────────────────────────────────┐
│  Public API: connect, map handle, subscribe │   (M5)
├─────────────────────────────────────────────┤
│  Runtime actor ("delta manager")            │   (M3/M4)
│  handshake · CSN/RSN · inbound ordering ·   │
│  catch-up · resubmit · nack · event fan-out │
├──────────────────────┬──────────────────────┤
│  DDS kernels (PURE)  │  wire (PURE)         │   (M1 ✅ / M3)
│  sequenced + pending │  levee channel       │
│  LWW/delta merge     │  payload codecs      │
├──────────────────────┴──────────────────────┤
│  aquamarine (channel client, roost codec)   │
└─────────────────────────────────────────────┘
```

## Status

- **M1 — kernel: done.** `watershed/map_kernel` is a pure port of FluidFramework's
  `mapKernel.ts` (sequenced + pending state, lifetimes, event suppression,
  insertion-order iteration). Unit tests plus qcheck properties: convergence
  across authorship/submit-timing interleavings, ack transparency, and rebase
  equivalence, at 1000 iterations each.
- **SharedCounter kernel: done.** `watershed/counter_kernel` is a pure port of
  FluidFramework's `counter.ts` delta semantics: integer increments, optimistic
  local apply, FIFO acks, local message-id validation, stashed ops, rollback,
  and summary seeding.
- **SharedSequence kernel: done.** `watershed/sequence_kernel` uses
  `lattice_sequence` for optimistic insert, delete, and move operations over
  arbitrary JSON values, with summaries, stashed ops, rollback, and
  multi-client convergence.
- **SharedRichText kernel: done.** `watershed/rich_text` is a checked port of
  `quill-delta@4.2.1`/`rich-text@4.1.0` (the ot-types Quill format);
  `watershed/rich_text_kernel` rides that algebra on the same single-op-in-flight
  client-transform protocol as `watershed/json_ot_kernel`. See
  [Shared rich text](#shared-rich-text) below.
- **SharedText kernel: done.** `watershed/text_kernel` uses `lattice_text` for
  optimistic collaborative plain-text editing: grapheme-indexed `insert`,
  `delete_range`, `replace_range`, and `append` over an optimistic string, plus
  cursor anchors that survive concurrent edits. Indexing is by Unicode grapheme
  (never UTF-16 code unit), replace is one composed op, and the wire format is
  watershed's own delta over the `lattice_text` identity CRDT — **not** a port
  of Fluid Framework's SharedString merge-tree format.
- **M2 — shared test corpus: done.** 20 scenarios generated from the TS
  `MapKernel` oracle and replayed against `map_kernel` in a multi-client sim.
- **M3 — wire + happy-path runtime: done.** `watershed/wire` codecs over
  spillway types; `watershed/runtime_core` pure state machine; `watershed/runtime`
  OTP actor over aquamarine. Two BEAM clients converge against a live server.
- **M4 — resilience: done.** Out-of-order buffering + in-band `requestOps`,
  reconnect/reconcile with client-id remap, nack policy, noop heartbeat.
- **M5 — polish + example: in progress.** Public API (`watershed`), and a
  **Gleam-end-to-end Lustre** dice roller (see below).

## Targets

The pure core (`map_kernel`, `counter_kernel`, `sequence_kernel`, `rich_text`,
`rich_text_kernel`, `text_kernel`, `wire`, `runtime_core`) is target-agnostic.
Two runtimes sit on top:

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Pure core | `map_kernel` · `counter_kernel` · `sequence_kernel` · `rich_text` · `rich_text_kernel` · `text_kernel` · `wire` · `runtime_core` | ← identical, shared |

The erlang-only modules are gated with `@target(erlang)` so
`gleam build --target javascript` compiles just the pure core plus the JS
runtime. See [`examples/dice_lustre`](examples/dice_lustre) for a Lustre SPA
whose entire client is Gleam, verified converging against a live `just server`,
[`examples/dice_cli`](examples/dice_cli) for its Erlang-target CLI counterpart,
[`examples/scoreboard_cli`](examples/scoreboard_cli) for a multi-player
scoreboard whose per-player records use the [typed document layer](#typed-documents),
and [`examples/playlist_lustre`](examples/playlist_lustre) for a reorderable
playlist on `SharedSequence` — the example that exercises `move`, the
convergent reorder no other DDS here offers, and
[`examples/text_lustre`](examples/text_lustre) for a collaborative plain-text
editor on `SharedText`, diffing each `<textarea>` keystroke into one
grapheme-indexed op (mirrored by the [live `/text`
demo](https://watershed.tylerbutler.com/text)).

For Lustre apps, [`watershed_lustre`](watershed_lustre) binds the JS facade to
Lustre as effects — `connect`, per-kind subscriptions, `ensure_*` bootstrap, and
a presence effect — so an app declares its wiring instead of hand-bridging
watershed's callbacks into `dispatch` (and deferring each to dodge the
mid-`update` clobber). Every Lustre example here is built on it.

## Shared sequences

`SharedSequence` is a collaborative Array-like DDS that stores arbitrary JSON
values. The Erlang and JavaScript facades expose the same create, resolve,
insert, delete, move, replace, read, and subscription operations:

```gleam
import gleam/json

let assert Ok(items) = watershed.create_sequence(doc)
let assert Ok(Nil) =
  watershed.sequence_insert(items, 0, json.string("first"))
let assert Ok(Nil) =
  watershed.sequence_insert(items, 1, json.string("second"))
let assert Ok(Nil) = watershed.sequence_move(items, 0, 1)
watershed.sequence_values(items)
// [json.string("second"), json.string("first")]
```

Move destinations are interpreted after removing the source value. Replace is
one Watershed operation composed by merging `lattice_sequence` delete and insert
deltas; `lattice_sequence` has no native replace primitive. This Array-like DDS
is the substrate beneath collaborative text; the text-specific API is
[`SharedText`](#shared-text).

## Shared rich text

`SharedRichText` is a collaborative rich-text DDS for Quill-style editors. It
is **OT-backed** (client-transform over a central sequencer, the same protocol
`json_ot_kernel` uses), not the CRDT-backed `SharedText` used for plain
grapheme-indexed text. The two are separate, non-interchangeable designs.

- `watershed/rich_text` is a checked port of `quill-delta@4.2.1` composed with
  `rich-text@4.1.0` (the [ot-types](https://github.com/ottypes) Quill OT type):
  pure `apply`/`compose`/`transform`/`invert` over Quill Delta documents and
  changes. `watershed/rich_text_kernel` rides that algebra on the client
  runtime; the public API is `SharedRichText` (`watershed.gleam` on BEAM,
  `runtime_js.create_rich_text` / `submit_rich_text` / `rich_text_view` on
  JavaScript). Upstream license notices for both ported packages are in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- Documents and deltas are JSON arrays of Quill Delta ops: `{"insert": ...}`,
  `{"retain": n, "attributes": {...}}`, and `{"delete": n}`, matching the wire
  format Quill itself emits and consumes. An `insert` op's value is either a
  string or an embed (any other JSON value); embeds always have length `1`
  regardless of their JSON shape. In a `retain` op's `attributes` patch, a
  `null` value *removes* that formatting attribute rather than setting it —
  standard Quill Delta `compose` semantics.
- Positions are **UTF-16 code units**, matching Quill/JavaScript string
  indexing exactly (not grapheme clusters, unlike `SharedSequence` and
  `SharedText`). A `retain`/`delete` boundary that lands inside a supplementary
  character's UTF-16 surrogate pair is rejected rather than silently
  truncating a scalar.
- `rich_text.transform_position` / `transform_selection` carry a caret or
  selection range through a remote delta, so editors and shared-cursor
  presence can re-anchor a peer's cursor without recomputing it from scratch.
- The kernel keeps **at most one local operation in flight**; further local
  edits compose into a single pending buffer until the in-flight op is
  acknowledged, then that buffer becomes the next in-flight op.
- Remote (and local) change events carry the delta already transformed into
  the *current optimistic view's* context — not just the confirmed document —
  so an editor can apply it incrementally (`updateContents`) instead of
  re-rendering the whole document, and presence code can transform cached
  peer selections through the same delta.
- Summaries persist only sequenced (fully acknowledged) state. A detached
  channel's `attach` snapshot, by contrast, includes its optimistic state
  (pending local edits), matching every other optimistic kernel here.
- Unlike Quill/Fluid's `SharedString`, the data-structure layer does not
  require or assume a document-final trailing newline; that convention, where
  wanted, is an editor-layer concern.

```gleam
import watershed/rich_text

let assert Ok(doc) = watershed.create_rich_text(document)
let assert Ok(delta) =
  rich_text.delta_insert_text(rich_text.empty_delta(), "Hello", rich_text.attributes([]))
watershed.submit_rich_text(doc, delta)
watershed.rich_text_view(doc)
// Some(document containing [{"insert": "Hello"}])
```

JavaScript/Lustre apps use the equivalent `runtime_js` functions
(`create_rich_text`, `submit_rich_text`, `rich_text_view`, plus `subscribe`)
against the same `rich_text`/`rich_text_kernel` modules — see
[`website/src/scripts/rich-text-demo.ts`](website/src/scripts/rich-text-demo.ts)
for a full three-editor Quill wiring, live at the
[`/rich-text`](website/src/pages/rich-text.astro) website demo.

## Shared text

`SharedText` is a collaborative plain-text DDS for many typists on one string,
backed by `lattice_text`. All indexes are **grapheme** indexes (Unicode
extended grapheme clusters), so an emoji or a combining sequence counts as one
unit — never a UTF-16 code-unit offset. The Erlang and JavaScript facades expose
the same create, resolve, mutate, read, anchor, and subscription operations:

```gleam
let assert Ok(body) = watershed.create_text(doc)
let assert Ok(Nil) = watershed.text_append(body, "hello world")
let assert Ok(Nil) = watershed.text_insert(body, 5, ",")       // "hello, world"
let assert Ok(Nil) = watershed.text_delete_range(body, 0, 5)   // ", world"
let assert Ok(Nil) = watershed.text_replace_range(body, 2, 7, "there") // ", there"
watershed.text_value(body)
// ", there"
```

- Edits are **optimistic**: a local mutation shows immediately in the optimistic
  string and rides the sequenced stream as a delta; if the server rejects it the
  kernel rolls back and replays the remaining pending edits over the sequenced
  base. `text_value`, `text_length`, and `text_substring` read the optimistic
  view; every mutation returns `Result` and an out-of-bounds index is refused,
  not clamped. An empty edit validates its index and then succeeds as a no-op.
- **Replace is one composed operation** — a delete and an insert at the same
  place merged into a single pending entry, one wire op, one event — not a
  delete + insert pair.
- **Anchors** (`text_anchor_at`, `text_start_anchor`, `text_end_anchor`,
  `text_resolve_anchor`, `text_anchor_to_json`, `text_anchor_from_json`) pin a
  stable position that survives concurrent edits and merges: as text is inserted
  or deleted before an anchor, `text_resolve_anchor` reports its shifted grapheme
  index. This is the primitive shared cursors are built on; broadcasting them
  (presence) is out of scope for this release.
- `subscribe_text` delivers a `text_kernel.TextEvent` carrying the full
  post-edit optimistic string, for local and remote edits alike.

Unlike SharedMap and SharedCounter — byte-for-byte ports of the Fluid Framework
formats — `SharedText` is **not** a port of Fluid's `SharedString`. It uses
watershed's own delta wire format over the `lattice_text` identity CRDT (the
same identity lattice as `SharedSequence`), not Fluid's interval merge-tree
format. This first release also excludes rich-text formatting and attributes,
range-delta events, tombstone compaction and forwarding retention, the
`lattice_fugue` / `lattice_text_fugue` variants, and presence-based shared
cursors.

See [`examples/text_lustre`](examples/text_lustre) for a full collaborative
editor and the [live `/text` demo](https://watershed.tylerbutler.com/text).

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read/write through it. Typing is a *decode boundary*,
not a closed schema — remote peers (or old summaries) can still write any JSON,
so typed reads return `Result`.

Declare each slot as a field — a plain value, a nested typed map (`ChildField`),
or a handle to any other channel kind (`ChannelField`):

```gleam
import watershed/schema.{
  type ChannelField,
  type CounterChannel,
  type Field,
  type SequenceChannel,
}

pub type Doc
pub fn title() -> Field(Doc, String) {
  schema.field("title", json.string, decode.string)
}
pub fn mistakes() -> ChannelField(Doc, CounterChannel) {
  schema.channel_field("mistakes")
}
pub fn items() -> ChannelField(Doc, SequenceChannel) {
  schema.channel_field("items")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, subsuming the
create / race / retry bootstrap apps used to hand-write:

```gleam
let root = watershed.typed(watershed.root(doc))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(counter) = watershed.ensure_counter(doc, root, mistakes())
let assert Ok(sequence) = watershed.ensure_sequence(doc, root, items())
```

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift (see [`examples/scoreboard_cli`](examples/scoreboard_cli)). Events
narrow per field or per channel via `subscribe_field`, `subscribe_counter`,
`subscribe_sequence`, and `subscribe_typed`.
[`examples/sudoku_lustre`](examples/sudoku_lustre) shows the full pattern end to
end.

## Development

```sh
gleam deps download
gleam test                      # BEAM: unit + property + corpus tests
gleam build --target erlang     # BEAM: OTP runtime
gleam build --target javascript # browser: pure core + JS runtime
pnpm --dir examples/dice_lustre install
pnpm --dir examples/dice_lustre run build
gleam format
```

Or use the root justfile:

```sh
just deps
just test
just build
just format
just lint
```

Map ops are byte-identical to the TS `@fluidframework/map` format
(`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
SharedCounter ops match `@fluidframework/counter` (`{type: "increment",
incrementAmount}`).

## Testing your app (the sluice)

`watershed/sluice` (erlang) and `watershed/sluice_js` (JavaScript) are an
**in-memory levee**: a deterministic, single-process stand-in for the server so
you can write multi-client convergence tests with no infrastructure. It runs the
*real* runtime — same codecs, pending queues, resubmit, reconnect catch-up — over
an injected transport, and the *real* server sequencing (spillway's `sequencing`
module), so a passing sluice test exercises production code paths end to end.

Delivery is **explicit**: ops sequence when submitted but arrive only when you
call `settle` (deliver until quiescent) or `step` (deliver one frame). That makes
races scriptable — "both clients claim the cell, deliver B first" is a sequence
of calls, not a timing accident — and makes assertions deterministic without
polling.

```gleam
// JavaScript (browser/Lustre apps); erlang is identical via watershed/sluice.
import watershed/sluice_js
import watershed_js

pub fn two_clients_converge_test() {
  let sluice = sluice_js.start(tenant: "default", document: "demo")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)                       // complete both handshakes

  watershed_js.set(watershed_js.root(doc_a), "k", json.int(1))
  sluice_js.settle(sluice)                       // deliver the edit everywhere

  watershed_js.get(watershed_js.root(doc_b), "k")  // Some(json.int(1))
}
```

Controls: `settle`, `step`, `pause`/`resume` (erlang — hold a client's frames to
script delivery order), and `advance(ms)` (move the sluice's logical clock so
presence TTL logic is testable without sleeping). The live-server integration
suite stays authoritative and untouched; the sluice models levee, it is not
levee. See `examples/sudoku_lustre/test/convergence_test.gleam` for a real app
test, and `docs/plans/2026-07-06-in-memory-hub-plan.md` for the design.
