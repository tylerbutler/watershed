# watershed

Collaborative data structures for Gleam. A watershed document is a collection
of data stored in those structures; your application decides what the data
means. Many people can edit the same document at once. Watershed applies each
edit locally the moment it happens, sequences it through a server, and
converges every client on the same state — across concurrent edits, dropped
connections, and reloads.

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
import watershed/channel.{type ChannelEvent}
import watershed_beam

type Msg {
  MapChanged(ChannelEvent)
}

pub fn main() {
  // Blocks until the op history has replayed locally.
  let assert Ok(document) =
    watershed_beam.connect(
      host: "127.0.0.1",
      port: 4000,
      tenant: "flow-co",
      document: "flowboard",
      token: token,
      user_id: "ada",
    )
  let board = watershed_beam.root(document)
  let events = watershed_beam.subscribe(board)
  let selector =
    process.new_selector()
    |> process.select_map(events, MapChanged)

  // Subscribe first: this local write emits immediately.
  watershed_beam.set(board, "title", json.string("Q3 sprint board"))

  // The same subject also receives remote changes as they are applied.
  let MapChanged(_event) = process.selector_receive_forever(selector)
}
```

The default `watershed` facade is for JavaScript. It takes a
`WatershedConfig` and an
`on_ready` callback instead of blocking, and delivers events to callbacks rather
than a `Subject`. On the BEAM, import `watershed_beam` as shown above.
Everything below the facade is the same code. See the [connect
guide](https://watershed.tylerbutler.com/guide/connect) for both.

## Data structures

Every structure rides the same sequenced stream and can be mixed freely in one
document. Pick by how you want concurrent edits to merge — the
[field guide](https://watershed.tylerbutler.com/structures) covers each one's
merge rule, optimistic behaviour, and what it is best for.

| Family | Structures | Use it for |
| --- | --- | --- |
| Maps & cells | `SharedMap`, `OR-Map`, `SharedDirectory`, `LWWRegister`, `MvRegister` | key/value state, nested folders, or a cell with one winner or concurrent alternatives |
| Counters | `SharedCounter`, `G-Counter`, `PN Counter` | numbers many people add to at once |
| Sets | `OR-Set`, `G-Set`, `2P-Set` | membership: re-addable, add-only, or permanent removal |
| Sequences | `SharedSequence`, `SharedText` | ordered lists with `move`, and plain text many people type into |
| Transforms | `JSON OT`, `SharedRichText` | one JSON document, or Quill-style rich text with formatting |
| Coordination | `Claims`, `TaskManager`, `Ordered collection`, `Register collection`, `Pact map` | ownership, work queues, and quorum agreement |

Each has matching `create_*`, `ensure_*`, mutation, read, and `subscribe_*`
functions on both the Erlang (`watershed_beam`) and JavaScript (`watershed`)
facades. For example:

```gleam
let assert Ok(items) = watershed.create_sequence(document)
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

`G-Counter` only goes up, which is what you want for hit counts, votes, and
anything else where a decrement would be a bug rather than a feature. Every
replica keeps its own tally and the visible value is their sum, so concurrent
increments never fight. A negative amount is refused and nothing is sent:

```gleam
let assert Ok(hits) = watershed.create_g_counter(document)
let assert Ok(Nil) = watershed.g_counter_increment(hits, 3)
let assert Error(_) = watershed.g_counter_increment(hits, -1)
watershed.g_counter_value(hits)
// Ok(3)
```

Use `create_g_counter`, `ensure_g_counter`, `g_counter_increment`,
`g_counter_value`, and `subscribe_g_counter` on either sequenced facade; typed
fields use `schema.GCounterChannel`, and peer-to-peer documents get
`p2p.g_counter_root()`.

An `OR-Map` chooses one value mode at creation: signed tallies (`TallyMode`),
string registers (`RegisterMode`), or sets of strings (`OrSetMode`). Set mode
fits things like tags per document: two people can add different tags to the
same document without replacing each other's collection.

```gleam
let assert Ok(labels) =
  watershed.create_or_map(document, or_map_kernel.OrSetMode)
let assert Ok(Nil) =
  watershed.or_map_add_member(labels, "inspection-brief", "reviewed")
watershed.or_map_value(labels, "inspection-brief")
// Ok(or_map_kernel.SetMembers(["reviewed"]))

let assert Ok(Nil) =
  watershed.or_map_remove_member(labels, "inspection-brief", "reviewed")
watershed.or_map_value(labels, "inspection-brief")
// Ok(or_map_kernel.SetMembers([]))

let assert Ok(Nil) = watershed.or_map_remove_key(labels, "inspection-brief")
watershed.or_map_value(labels, "inspection-brief")
// Error(Nil)
```

Removing a member and removing its key are different edits. Removing the last
member leaves a present, empty set; removing an absent member does nothing and
does not create a key. Key removal clears the members its author observed.
A concurrent, unseen member addition can keep the key alive, but a later
re-add does not bring removed members back.

| | SharedMap | OR-map in `OrSetMode` |
| --- | --- | --- |
| Values | JSON, including arrays | Sets of strings |
| Concurrent edits to one key | The later server-sequenced write replaces the whole value | Member edits merge; unseen additions survive observed removals |
| Reads | Insertion-order keys | Keys and members sorted in UTF-8 order |
| Saved state | Visible values | Member tags, tombstones, removal history, and counter floors |

Both sequenced facades expose `or_map_add_member`, `or_map_remove_member`, and
`or_map_remove_key` as `Result(Nil, String)` operations. The last is a
result-returning companion to the existing `or_map_remove`; legacy methods
keep their signatures. Publish the handle with `set_or_map_field`, or use
`ensure_or_map` with `OrSetMode` after synchronization. Typed fields use the
existing `schema.OrMapChannel`.

`or_map_entries` returns `SetMembers` values, and `subscribe_or_map` delivers
`SetMembersUpdated(key, members)` or `KeyRemoved(key)`. Adding an already
visible member still creates a fresh causal tag, so it can survive a
concurrent removal, but it emits no duplicate visible-value event.

For JS CRDT documents, configure `root: p2p.or_map_root(or_map_kernel.OrSetMode)`.
The same three mutations return `Result(Nil, p2p.P2pError)` through `crdt_js`.
Its `or_map_value` has an outer result for document/channel errors:
`Ok(Error(Nil))` means a missing key, while `Ok(Ok(SetMembers([])))` means a
present empty key. Lustre uses the existing `ensure_or_map`, subscriptions,
and deferred `perform` effects; no separate set-map handle is needed.

Set mode accepts empty strings as keys or members. It has no whole-set setter,
clear, pruning, mixed value types, or nested-map support. Counter floors
survive rollback and reload without restoring pending members. The
[maps field guide](https://watershed.tylerbutler.com/structures/maps) includes
the set-mode races beside the other maps.

`LWWRegister` holds one string, initially `""`. Values are string-only in this
release. Each write gets `max(wall_clock_ms, last_seen + 1)` from the runtime
and kernel, so its logical clock advances even when the wall clock repeats or
moves backward. Callers supply only the value. The greatest timestamp wins;
the lexicographically greatest replica ID breaks a timestamp tie.

```gleam
let assert Ok(status) = watershed.create_lww_register(document)
let assert Ok(Nil) = watershed.lww_register_set(status, "ready")
watershed.lww_register_value(status)
// Ok("ready")
```

Store the new register's handle in an attached map to replicate it. Typed fields
use `schema.LwwRegisterChannel`, inferred here from `set_lww_register_field`:

```gleam
let root = watershed.typed(watershed.root(document))
let status_field = schema.channel_field("status")
watershed.set_lww_register_field(root, status_field, status)
watershed.resolve_lww_register_field(document, root, status_field)
// Ok(Some(status))
```

Use `ensure_lww_register` to adopt or create the field after synchronization:
JavaScript takes a result callback, while `watershed_beam` waits and returns the
result. Both sequenced facades expose the create, handle, resolve, set, read, and
typed field operations above. `subscribe_lww_register` delivers
`Changed(previous_value, value)` to a callback on JavaScript or a subject on the
BEAM. Writing the current string still replicates newer metadata (timestamp and
winning author), but emits no visible-value event. Writes return `Result` so
callers can handle channel and clock errors.

For a browser p2p document, use `root: p2p.lww_register_root()` in
`crdt_js.config`, create it with `crdt_js.new_document`, and call `crdt_js.attach`
to connect it to peers. Read and write its root through the CRDT API:

```gleam
let status = crdt_js.root(document)
let assert Ok(Nil) = crdt_js.lww_register_set(status, "ready")
crdt_js.lww_register_value(status)
// Ok("ready")
```

Use `crdt_js.subscribe_lww_register` for visible changes; CRDT reads and writes
return `Result(_, p2p.P2pError)`. Snapshots retain the winning timestamp and
author, including metadata-only writes. `LWWRegister` is a single-value CRDT:
the consensus register collection provides sequenced coordination across named
registers, while an `LWWMap` selects a winner per key.

`MvRegister` holds strings and returns a sorted list of alternatives, preservingduplicate text from independent concurrent writes. Use `create_mv_register`,
`ensure_mv_register`, `mv_register_set`, `mv_register_values`, and
`subscribe_mv_register` on either sequenced facade; typed fields use
`schema.MvRegisterChannel`. A new write replaces only the history its author has
observed. Writing `""` stores an empty string; it does not delete the value.

The peer-to-peer facade uses `p2p.mv_register_root()` with
`crdt_js.mv_register_set`, `mv_register_values`, and `subscribe_mv_register`.
Snapshots retain causal history even when the visible alternatives don't change.
The [revision slate](https://watershed.tylerbutler.com/mv-register) demonstrates
concurrent writes, ordinary-write resolution, and stale-delta replay.

## Targets

The core (kernels, wire codecs, and the runtime state machine) is
target-agnostic; only the transport and the runtime shell differ. Erlang-only
modules are gated with `@target(erlang)`, so `gleam build --target javascript`
compiles the core plus the JS runtime and nothing else.

| Layer | BEAM (`watershed_beam`) | Browser (`watershed`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime_beam` (OTP actor) | `runtime` (callbacks + mutable cell) |
| Core | kernels · `wire` · `runtime_core` | ← identical, shared |

For Lustre apps, [`watershed_lustre`](watershed_lustre) binds the JS facade to
Lustre as effects — `connect`, per-kind subscriptions, `ensure_*` bootstrap, and
presence — so an app declares its wiring instead of hand-bridging callbacks into
`dispatch`. Every Lustre example here is built on it.

## Durability boundary

`watershed_beam` / `watershed` are the **sequenced** line: once an op is accepted
by Floodgate (or another compatible service), durability lives there, and
summaries shorten the replay for later joins.

`watershed/crdt_js` is the **peer-to-peer** line. `merge_snapshot` joins an
exported snapshot into a live document without dropping local channels or local
edits; `import_snapshot` rebuilds a detached document, and `attach` brings it
online later. `watershed/persist_js` stores those snapshots in IndexedDB,
joining the latest stored value before every save and surfacing — never
deleting — corrupt bytes, import failures, and storage errors.
`watershed/persist_controller_js` is the save driver: debounce after local
edits, periodic digest sweep for remote merges, and one final `pagehide` save
attempt.

That browser durability is local to one profile. Cross-device recovery still
needs another live peer or a relay (`SequencedOnly`, or `Auto` once relay
primary). Signaling alone is never storage.

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read and write through it. Typing is a *decode
boundary*, not a closed schema — remote peers (or old summaries) can still write
any JSON, so typed reads return `Result`.

Each slot is a field: a plain value, a nested typed map (`ChildField`), or a
handle to any other channel kind (`ChannelField`).

```gleam
pub type Document

pub fn title() -> Field(Document, String) {
  schema.field("title", json.string, decode.string)
}
pub fn items() -> ChannelField(Document, SequenceChannel) {
  schema.channel_field("items")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, replacing the
create / race / retry bootstrap apps otherwise write by hand:

```gleam
let root = watershed.typed(watershed.root(document))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(sequence) = watershed.ensure_sequence(document, root, items())
```

Channel `ensure_*` calls wait for synchronization before reading or seeding a
field, so they can start before the handshake completes. They report a timeout
if the document or a newly seeded field does not synchronize within the retry
budget. A timeout does not undo an already submitted seed. `ensure_field`
remains synchronous set-if-absent.

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift. Events narrow per field or per channel via `subscribe_field`,
`subscribe_counter`, `subscribe_sequence`, and `subscribe_typed`.
[`examples/sudoku_lustre`](examples/sudoku_lustre) shows the pattern end to end;
[`examples/scoreboard_cli`](examples/scoreboard_cli) shows the record builders.

## Summaries

Automatic summaries are enabled by default on JavaScript and BEAM, including
Lustre connections. A settled client schedules a checkpoint after **500
sequenced messages** since the last known summary, with attempts spread across
a **3-second jitter window**. Messages can contain multiple edits. Each client
checks again before uploading, so a peer's summary can make its attempt
unnecessary. This reduces replay work; it does not guarantee a fixed replay
limit.

Tune `summary_policy.policy()` with `with_threshold` and
`with_jitter_milliseconds`, then apply it with `auto_summarize(document, policy)`.
`stop_auto_summarize(document)` opts that client out; `auto_summarize` re-enables
it. Manual `summarize(document)` remains available, and
`operations_since_summary` reports the message count. Uploads need floodgate
summary storage and a token with `summary:write`, which `connect` includes by
default. The call completes only after Floodgate publishes the checkpoint and
returns its Git commit ID. `get_versions(document, count:)` lists those commits
newest first. Pass an ID to `load_version(document, handle:)` to read that
historical snapshot without changing the live document.

A checkpoint captures confirmed channel state and membership at the blob's
own sequence number. A later client loads it and replays subsequent messages,
including those sequenced during upload. Pending local edits are not in the
checkpoint; reconnect preserves and resubmits them. See
[reconnect and summaries](https://watershed.tylerbutler.com/runtime/reconnect)
for the boundary and retry behavior.

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
import watershed

pub fn two_clients_converge_test() {
  let sluice = sluice_js.start(tenant: "default", document: "demo")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)                       // complete both handshakes

  watershed.set(watershed.root(document_a), "k", json.int(1))
  sluice_js.settle(sluice)                       // deliver the edit everywhere

  watershed.get(watershed.root(document_b), "k")  // Some(json.int(1))
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
Several are available at [watershed.tylerbutler.com](https://watershed.tylerbutler.com).

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

For source navigation, `just code-map overview` lists repository areas,
`just code-map find connect --path src` finds declarations, and
`just code-map file src/watershed/p2p.gleam` shows a file outline. Add `--json`
for agent-readable results. Queries refresh an ignored cache from current
source; they do not require an application or website build.

The [code-map tool](tools/code-map/README.md) has its own dependencies and can
move into a standalone repository. Watershed supplies exclusions through
[`code-map.json`](code-map.json), and keeps its real-source coverage gate in
[`tools/code-map-watershed.test.mjs`](tools/code-map-watershed.test.mjs).
`just deps` installs the tool; `just code-map-test` runs its focused suites.
