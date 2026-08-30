# watershed_lustre

[Lustre](https://lustre.build) effect bindings for
[watershed](https://github.com/tylerbutler/watershed) — the collaborative DDS
client meets the UI framework, so a Lustre app *declares* its connection and
subscriptions instead of hand-wiring watershed's callbacks into `dispatch`.

```gleam
import watershed
import watershed_lustre

fn init(_) {
  let user = "web-" <> int.to_string(int.random(9999))
  #(initial, watershed_lustre.connect_dev(
    url: "ws://localhost:4000/socket/websocket?vsn=2.0.0",
    tenant: "dev-tenant", secret: dev_secret,
    document: "dice", user_id: user,
    got_document: GotHandle, connected: Connected,
  ))
}

fn update(model, msg) {
  case msg {
    GotHandle(doc) -> #(
      Model(..model, doc: Some(doc)),
      // local + remote edits arrive as MapChanged
      watershed_lustre.subscribe(watershed.root(doc), fn(_) { MapChanged }),
    )
    // …
  }
}
```

## What it owns

- **Scheduling, not vocabulary.** Every effect takes a caller-supplied
  `fn(...) -> msg` constructor, the way `lustre/event` handlers do. The app keeps
  its own `Msg` type.
- **No mid-`update` dispatch.** watershed delivers events synchronously —
  sometimes from inside a running `update`, since a local edit made there fires
  its subscription callback before `update` returns, and a nested `dispatch` is
  clobbered. Every inbound callback here is deferred to a microtask, so that
  whole class of lost update never arises.
- **Timers as effects.** `after(ms, msg)` for heartbeats, debounces, and retries
  — no hand-rolled `setTimeout` FFI per app.

## API

Every effect takes the app's own `fn(...) -> msg` constructors; edits and reads
stay on `watershed` (`set`, `get`, `entries`, `increment`, …) — this package
only wraps the callback-shaped surface.

**Connect**
| Effect | Hands back |
| --- | --- |
| `connect(config, got_document:, connected:)` | the `Document`, then the handshake result |
| `connect_dev(url:, tenant:, secret:, document:, user_id:, got_document:, connected:)` | same, minting the HS256 dev token first |

**Subscriptions** — each delivers its channel's own event type, never the
whole-runtime union:
`subscribe` (map) and `subscribe_directory` / `_counter` / `_pn_counter` /
`_or_map` / `_or_set` / `_g_set` / `_two_p_set` / `_register_collection` /
`_claims` / `_task_manager` / `_pact_map` / `_ordered_collection` / `_sequence` /
`_text` / `_rich_text` / `_json_ot`, plus `subscribe_ripples` for ephemeral
document ripples.

**Typed** (over a `watershed/schema` `TypedMap`):
`subscribe_field` (decoded `FieldChange`), `subscribe_typed` (whole-map events).

**Claims writes** — `claim_once(claims, key, value, to_msg:)` and
`compare_and_set_claim(claims, key, value, to_msg:)` submit a claim and
deliver its `claims_kernel.ClaimOutcome` (`Accepted` / `Lost` / `Aborted`)
as a message once the outcome is known, the same deferred-to-microtask way
every other callback in this package arrives. Claims reads are not
optimistic — nothing about `get_claim`/`has_claim` changes until that
message lands — so render the interval between calling either effect and its
outcome as pending. `claim_once` is write-once and resolves `Lost`
synchronously if the key is already claimed; `compare_and_set_claim` takes
it regardless of who holds it, so long as nobody's write has landed since
the committed entry it captures its `reference_sequence_number` from.

**Declarative bootstrap** — each dispatches its resolved channel once it settles,
so a document's nested structure is an `effect.batch` in `init`:
`ensure_map` / `ensure_directory` / `ensure_counter` / `ensure_or_map` /
`ensure_or_set` / `ensure_g_set` / `ensure_two_p_set` /
`ensure_register_collection` / `ensure_claims` / `ensure_task_manager` /
`ensure_pn_counter` / `ensure_pact_map` / `ensure_ordered_collection` /
`ensure_sequence` / `ensure_text` / `ensure_rich_text` / `ensure_json_ot` /
`ensure_child`, and `ensure_field` (synchronous set-if-absent).

**Presence** — the heartbeat driver as effects:
`presence(document:, user_id:, config:, encode:, decode:, started:, on_peers:)`
starts it and hands the `Handle` back; `announce(handle, payload)` broadcasts.

**Summaries** — `auto_summarize(document:, policy:)` lets the client write its
own checkpoints once the document drifts past the policy's threshold, so a
later join replays recent history instead of all of it; `stop_auto_summarize`
turns it off. Off unless installed.

**Timers & misc**: `after(ms, msg)`, `submit_ripple`, `force_reconnect`.

## Peer-to-peer CRDTs

`watershed_lustre/crdt` is the Lustre surface for the peer-to-peer facade
(`watershed/crdt_js`), the same way the effects above wrap the sequenced
`watershed`. A document's channels merge directly between browser tabs over
WebRTC data channels — there is no document server, and nothing sequences an
edit. The bindings keep the package's discipline: they schedule and defer, the
app owns its `Msg` vocabulary, so an app never hand-writes an `effect.from`
around a `crdt_js` callback.

```gleam
import watershed/crdt_js
import watershed/p2p
import watershed_lustre/crdt

// init — join the room. `Retained` carries the connection to keep (and later
// close), `Connected` the readiness result, `StatusChanged` the status stream.
crdt.connect(config, connection: Retained, ready: Connected, status: StatusChanged)

// after Connected(Ok(document)) — watch the root counter, keep the subscription
crdt.subscribe_pn_counter(crdt_js.root(document), subscribed: Watching, event: Bumped)

// on a click — author an edit; the subscription reports the new total
crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
```

### Why a separate module

The names mirror `crdt_js` exactly, and the module boundary is what keeps them
from colliding with the sequenced `subscribe_*`/`ensure_*` effects:
`watershed_lustre.subscribe_pn_counter` binds a server-sequenced counter,
`watershed_lustre/crdt.subscribe_pn_counter` a peer-to-peer one. Their handle
types differ and are not interchangeable, so a qualified import
(`import watershed_lustre/crdt`) reads unambiguously and the compiler rejects a
handle passed to the wrong stack.

### What it wraps

| Group | Effects |
| --- | --- |
| Connect & lifecycle | `open`, `connect`, `attach`, `attach_with_rtc` — `open` tries IndexedDB first and reports `PersistenceStatus`; all four deliver the `CrdtConnection` to retain (always before `ready`), readiness, and every `Status`; `close` tears the connection down |
| Subscriptions | `subscribe_pn_counter` / `_or_map` / `_or_set` / `_g_set` / `_two_p_set` / `_sequence` / `_text` — each delivers its channel's own event type and hands back the `Subscription`; `unsubscribe` drops one while the document stays connected |
| Mutations | one generic `perform(operation:, outcome:)` — compose it with the typed `crdt_js` edit (`perform(fn() { crdt_js.or_set_add(set, "x") }, Added)`); it runs the edit in the effect phase and delivers the typed `Result(Nil, P2pError)` deferred, passed through untouched — an invalid or unsupported edit stays an `Error`, never a success-shaped `Ok` |
| Snapshots | `export_snapshot`, `import_snapshot` |
| Persistence | `start_persistence`, `persistence_changed`, `stop_persistence` — start digest-gated IndexedDB saving, report `Saving` / `Saved` / `SaveFailed`, call `persistence_changed` after local edits, and stop the timers / `pagehide` hook when the document closes |

Every inbound callback — readiness, status, an event, a mutation `Result`, a
delivered connection or subscription — is deferred to a microtask before
dispatch, exactly like the sequenced bindings, so a callback watershed fires
synchronously from inside a running `update` can never clobber it.

Pure configuration (`crdt_js.config`, `with_transport_policy`,
`with_sequencer`, `with_ice_servers`), synchronous reads (`pn_counter_value`,
`or_set_values`, `text_value`, …), channel registration (`create_channel`,
`root`), and diagnostics (`peer_count`, `policy`, `effective_path`, …) stay on
`crdt_js` and are called directly: they need no scheduling, and wrapping them
would only duplicate a pure API. The transport policy is chosen with
`crdt_js.with_transport_policy` (`Auto`, `P2pOnly`, `SequencedOnly`) and read
back through the delivered `Status` stream and `crdt_js.effective_path`.

### Disk-first open and local durability

`open` is the offline-first entry point. It runs `persist_js.load` first; a
valid stored snapshot reports `LocalSnapshotReady`, hands back the retained
`CrdtConnection`, and dispatches `ready(Ok(document))` before networking can
succeed or fail. That snapshot document is already editable; peers and the
relay are an enhancement once `attach` finishes in the background.

`persist_js.save` is join-before-save: it reads the latest stored snapshot,
merges it into the live document with `crdt_js.merge_snapshot`, then exports
and writes the joined state. Bad JSON, incompatible snapshots, and quota or
other storage failures surface as `PersistenceFailed` / `SaveFailed`; the
stored bytes are retained rather than deleted. `persist_controller_js` drives
the save loop: debounce after local edits, a periodic digest sweep so remote
merges get saved too, and one final `pagehide` attempt.

This is browser-local durability. A fresh browser profile or another device can
recover only from another live peer or from a durable relay such as Floodgate;
signaling alone is never storage.

### Operational contract

- **Signaling is required for peer discovery, and never carries document
  data.** A signaling service introduces peers and relays WebRTC offers,
  answers, and ICE candidates; by protocol shape it cannot route a document
  payload. Peers that are already connected keep working if it goes away.
- **WebRTC needs application-supplied STUN/TURN across NATs.** Tabs on one
  machine or one LAN connect on host candidates alone; anything across a NAT
  needs ICE servers you configure with `crdt_js.with_ice_servers`. Watershed
  ships no STUN or TURN service and no credentials.
- **The full mesh is capped at eight peers** by the current reference
  transport — every peer holds a connection to every other, and the ninth to
  join is refused with `RoomFull`.
- **Readiness under `Auto` is sequencer-independent.** The document is editable
  from the first frame; readiness waits only for the mesh — an empty roster is
  ready immediately, a populated one after a peer's state merges — never for a
  relay. A relay that is down costs a status line and no edits.
- **Durability depends on the active transport.** Peer-only state disappears
  when the last peer leaves unless it was captured with
  `crdt_js.export_snapshot`. Relay-primary state (`SequencedOnly`, or `Auto`
  once a relay has proven itself) is durably logged; edits authored during a
  relay outage stay peer-held until they merge back. Signaling alone is never
  durable storage.
- **Relay limits, checkpointing, and quarantine** are specified in
  [`docs/crdt-relay-v1.md`](../docs/crdt-relay-v1.md).
- **Supported structures** are PN counter, OR-map, OR-set, G-set, 2P-set,
  sequence, and text. The consensus, acknowledgement-based DDS, and
  last-write-wins types that need a sequencer are outside this set: they are not
  eligible and are refused at the `create_channel`/`new_document` boundary
  rather than diverging later.
- **Trust and authentication are examples, not production admission.** The
  reference signaling and relay services admit anyone who names a room and an
  unused peer id. Every payload that arrives on a data channel is still
  decoded, attributed to its sender, and checked against the room's
  protocol/compatibility/root before it merges; a peer that breaks a rule is
  closed one at a time without touching the local document.

See [`examples/clap_counter_lustre`](../examples/clap_counter_lustre) for the
whole surface in a real two-tab app — the `just p2p-clap` gate drives it in two
real browsers.

## Components

Where the effects above wrap watershed's callbacks, these wrap a whole
DDS↔widget bridge — the part every app would otherwise copy by hand.

**`watershed_lustre/textarea`** — a `<textarea>` bound to a `SharedText`, as a
nested MVU triple. `init(channel)` takes the resolved channel and subscribes;
the parent routes `Msg` through `update` and `element.map`s the `view`:

```gleam
EnsuredBody(Ok(channel)) -> {
  let #(editor, fx) = textarea.init(channel)
  #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
}

// view — caller attributes are yours, the value binding and handler are its
textarea.view(editor, [rows(10), class("editor")]) |> element.map(Editor)
```

It owns the snapshot discipline, the grapheme diff that turns a whole-value
`input` event into one minimal op, and the folding of a rejected stale index
into `textarea.error`. Read `value` / `length` / `error` / `selection` /
`channel` off the model — no callbacks to plumb.

It also keeps the caret still. A remote edit rewrites the element's value, and
the browser leaves the caret at a code-unit offset into a string that no longer
exists; the component holds the selection as `TextAnchor`s instead, resolves
them after each remote edit, and writes the caret back from
`effect.before_paint` — after the DOM is patched, before the browser paints, so
there is no visible jump. `selection(model)` exposes the tracked range as
grapheme indices, which is what a shared-cursor overlay would broadcast.

Two pure modules underneath it, useful on their own:

| Module | What it does |
| --- | --- |
| `watershed_lustre/grapheme_diff` | the one minimal `Insert`/`Delete`/`Replace` between two strings, in grapheme clusters |
| `watershed_lustre/grapheme_offset` | UTF-16 code-unit offsets (what the browser reports) ↔ grapheme indices (what the CRDT addresses) |

See [`examples/text_lustre`](../examples/text_lustre) for the component in an
app, [`examples/sudoku_lustre`](../examples/sudoku_lustre) for the typed +
presence surface end to end, and [`examples/dice_lustre`](../examples/dice_lustre)
for the minimal untyped case. JavaScript target only; consumed as a path
dependency inside the watershed monorepo (hex publication follows watershed's).
