# watershed

Collaborative data structures for Gleam. Many people edit the same document at
once; watershed applies each edit locally the moment it happens, sequences it
through a server, and converges every client on the same state — across
concurrent edits, dropped connections, and reloads.

It runs on both Gleam targets from one codebase: an OTP actor on the BEAM, and
the browser via the JavaScript target ([Lustre bindings](watershed_lustre)
included). It speaks the Fluid Framework wire protocol, so it works against any
Fluid-compatible sequencing service — [floodgate](https://floodgate.tylerbutler.com),
[levee](https://github.com/tylerbutler/levee), or Fluid Framework's own
[routerlicious](https://github.com/microsoft/FluidFramework/tree/main/server/routerlicious).

**[Guide](https://watershed.tylerbutler.com/guide)** ·
**[Data structures](https://watershed.tylerbutler.com/structures)** ·
**[Live demos](https://watershed.tylerbutler.com)**

## Install

watershed is not on Hex yet. Add it to your `gleam.toml` as a git dependency,
pinned to a commit — a branch ref is not a pin, and projects that resolve on
different days will land on different revisions:

```toml
[dependencies]
watershed = { git = "https://github.com/tylerbutler/watershed", ref = "<commit-sha>" }
```

[`watershed_lustre`](watershed_lustre) ships from this same repository, so Lustre
apps take it with a `path` into the clone (Gleam 1.18 or newer):

```toml
watershed_lustre = { git = "https://github.com/tylerbutler/watershed", ref = "<commit-sha>", path = "watershed_lustre" }
```

That pulls `watershed` along with it; declare `watershed` yourself only if you
also use it directly. Pin both to the same commit.

## Quick start

```gleam
import gleam/erlang/process
import gleam/json
import watershed
import watershed/channel.{type ChannelEvent}

type Msg {
  MapChanged(ChannelEvent)
}

pub fn main() {
  // Blocks until the op history has replayed locally.
  let assert Ok(doc) =
    watershed.connect(
      host: "127.0.0.1",
      port: 4000,
      tenant: "flow-co",
      document: "flowboard",
      token: token,
      user_id: "ada",
    )
  let board = watershed.root(doc)
  let events = watershed.subscribe(board)
  let selector =
    process.new_selector()
    |> process.select_map(events, MapChanged)

  // Subscribe first: this local write emits immediately.
  watershed.set(board, "title", json.string("Q3 sprint board"))

  // The same subject also receives remote changes as they are applied.
  let MapChanged(_event) = process.selector_receive_forever(selector)
}
```

In the browser, `watershed_js.connect` takes a `WatershedConfig` and an
`on_ready` callback instead of blocking, and delivers events to callbacks rather
than a `Subject`. Everything below the facade is the same code. See the
[connect guide](https://watershed.tylerbutler.com/guide/connect) for both.

## Data structures

Every structure rides the same sequenced stream and can be mixed freely in one
document. Pick by how you want concurrent edits to merge — the
[field guide](https://watershed.tylerbutler.com/structures) covers each one's
merge rule, optimistic behaviour, and what it is best for.

| Family | Structures | Use it for |
| --- | --- | --- |
| Maps | `SharedMap`, `OR-Map`, `SharedDirectory` | key/value state; last-write-wins, edit-wins-over-delete, or nested folders |
| Counters | `SharedCounter`, `G-Counter`, `PN Counter` | numbers many people add to at once |
| Sets | `OR-Set`, `G-Set`, `2P-Set` | membership: re-addable, add-only, or permanent removal |
| Sequences | `SharedSequence`, `SharedText` | ordered lists with `move`, and plain text many people type into |
| Transforms | `JSON OT`, `SharedRichText` | one JSON document, or Quill-style rich text with formatting |
| Coordination | `Claims`, `TaskManager`, `Ordered collection`, `Register collection`, `Pact map` | ownership, work queues, and quorum agreement |

Each has matching `create_*`, `ensure_*`, mutation, read, and `subscribe_*`
functions on both the Erlang (`watershed`) and JavaScript (`watershed_js`)
facades. For example:

```gleam
let assert Ok(items) = watershed.create_sequence(doc)
let assert Ok(Nil) = watershed.sequence_insert(items, 0, json.string("first"))
let assert Ok(Nil) = watershed.sequence_insert(items, 1, json.string("second"))
let assert Ok(Nil) = watershed.sequence_move(items, 0, 1)
watershed.sequence_values(items)
// [json.string("second"), json.string("first")]
```

Indexing rules differ by structure and are enforced, not clamped:
`SharedSequence` and `SharedText` index by **Unicode grapheme cluster**, while
`SharedRichText` uses **UTF-16 code units** to match Quill and JavaScript string
indexing exactly.

## Targets

The core (kernels, wire codecs, and the runtime state machine) is
target-agnostic; only the transport and the runtime shell differ. Erlang-only
modules are gated with `@target(erlang)`, so `gleam build --target javascript`
compiles the core plus the JS runtime and nothing else.

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Core | kernels · `wire` · `runtime_core` | ← identical, shared |

For Lustre apps, [`watershed_lustre`](watershed_lustre) binds the JS facade to
Lustre as effects — `connect`, per-kind subscriptions, `ensure_*` bootstrap, and
presence — so an app declares its wiring instead of hand-bridging callbacks into
`dispatch`. Every Lustre example here is built on it.

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read and write through it. Typing is a *decode
boundary*, not a closed schema — remote peers (or old summaries) can still write
any JSON, so typed reads return `Result`.

Each slot is a field: a plain value, a nested typed map (`ChildField`), or a
handle to any other channel kind (`ChannelField`).

```gleam
pub type Doc

pub fn title() -> Field(Doc, String) {
  schema.field("title", json.string, decode.string)
}
pub fn items() -> ChannelField(Doc, SequenceChannel) {
  schema.channel_field("items")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, replacing the
create / race / retry bootstrap apps otherwise write by hand:

```gleam
let root = watershed.typed(watershed.root(doc))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(sequence) = watershed.ensure_sequence(doc, root, items())
```

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift. Events narrow per field or per channel via `subscribe_field`,
`subscribe_counter`, `subscribe_sequence`, and `subscribe_typed`.
[`examples/sudoku_lustre`](examples/sudoku_lustre) shows the pattern end to end;
[`examples/scoreboard_cli`](examples/scoreboard_cli) shows the record builders.

## Summaries

`summarize` writes a checkpoint that a later client bootstraps from instead of
replaying the whole op log. `auto_summarize(document, summary_policy.policy())`
hands that decision to the runtime, which writes one once the document has
drifted past the policy's threshold and this client is settled. It is safe to
install on every client in a room: attempts are spread over a jitter window, and
the first summary sequenced stands the rest down. Off unless installed;
`ops_since_summary` reports the current drift.

## Testing your app

`watershed/sluice` (Erlang) and `watershed/sluice_js` (JavaScript) are an
in-memory server: a deterministic, single-process stand-in so you can write
multi-client convergence tests with no infrastructure. It runs the *real*
runtime — same codecs, pending queues, resubmit, reconnect catch-up — over an
injected transport, and the *real* server sequencing, so a passing sluice test
exercises production code paths end to end.

Delivery is explicit: ops sequence when submitted but arrive only when you call
`settle` (deliver until quiescent) or `step` (deliver one frame). That makes
races scriptable — "both clients claim the cell, deliver B first" is a sequence
of calls, not a timing accident.

```gleam
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

Other controls: `pause`/`resume` (Erlang — hold a client's frames to script
delivery order) and `advance(ms)`, which moves the sluice's logical clock and
fires the timers that fall due with it, so heartbeat- and TTL-driven logic such
as presence is stepped rather than waited out. The sluice also speaks
`presence_v1`, so server-backed presence is testable in-repo.

The sluice models a real server; it is not one. Keep a live-server test for
anything whose correctness depends on the server's actual behaviour.
[`examples/sudoku_lustre/test/convergence_test.gleam`](examples/sudoku_lustre/test/convergence_test.gleam)
is a real app test.

## Compatibility

- SharedMap ops are byte-identical to the TypeScript `@fluidframework/map`
  format (`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
  SharedCounter ops match `@fluidframework/counter`
  (`{type: "increment", incrementAmount}`).
- `SharedRichText` documents and deltas are JSON arrays of Quill Delta ops, the
  same wire format Quill itself emits and consumes.
- `SharedText` is **not** Fluid's `SharedString`: it uses watershed's own delta
  format over an identity CRDT, so it does not interoperate with Fluid's
  interval merge-tree format. Use it when watershed is on both ends.

Upstream license notices for ported packages are in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Examples

[`examples/`](examples) holds runnable apps, each with its own README:
a [dice roller](examples/dice_lustre) (Lustre) and its
[CLI counterpart](examples/dice_cli), a
[collaborative text editor](examples/text_lustre), a
[reorderable playlist](examples/playlist_lustre) on `SharedSequence`, a
[shared pixel canvas](examples/pixel_canvas_lustre), a
[Sudoku board](examples/sudoku_lustre) on the typed layer, a
[drum machine](examples/drum_machine_lustre) with quorum-agreed tempo, a
[release checklist](examples/release_checklist_lustre) with a first-writer-wins
captain seat and a quorum-agreed release target, and a
[showcase](examples/showcase_lustre) composing several into one document.
Several are live at [watershed.tylerbutler.com](https://watershed.tylerbutler.com).

## Development

```sh
gleam deps download
gleam test                      # BEAM: unit + property + corpus tests
gleam build --target erlang     # BEAM: OTP runtime
gleam build --target javascript # browser: core + JS runtime
gleam format
```

Or use the root justfile:

```sh
just deps
just test
just build
just format
just lint
just integration-up             # local floodgate server on :4000
```
