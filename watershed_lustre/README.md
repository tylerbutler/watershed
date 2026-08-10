# watershed_lustre

[Lustre](https://lustre.build) effect bindings for
[watershed](https://github.com/tylerbutler/watershed) — the collaborative DDS
client meets the UI framework, so a Lustre app *declares* its connection and
subscriptions instead of hand-wiring watershed's callbacks into `dispatch`.

```gleam
import watershed_js
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
      watershed_lustre.subscribe(watershed_js.root(doc), fn(_) { MapChanged }),
    )
    // …
  }
}
```

## What it owns

- **Scheduling, not vocabulary.** Every effect takes a caller-supplied
  `fn(...) -> msg` constructor, the way `lustre/event` handlers do. The app keeps
  its own `Msg` type.
- **The mid-`update` dispatch bug, deleted.** watershed delivers events
  synchronously — sometimes from inside a running `update` (a local edit made in
  `update` fires its subscription callback before `update` returns). A `dispatch`
  nested in a running update is clobbered. Every inbound callback here is
  unconditionally deferred to a microtask, so the bug class is designed out
  rather than documented.
- **Timers as effects.** `after(ms, msg)` for heartbeats, debounces, and retries
  — no hand-rolled `setTimeout` FFI per app.

## API

Every effect takes the app's own `fn(...) -> msg` constructors; edits and reads
stay on `watershed_js` (`set`, `get`, `entries`, `increment`, …) — this package
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
