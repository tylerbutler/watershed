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
14-variant union:
`subscribe` (map) and `subscribe_counter` / `_or_map` / `_or_set` /
`_register_collection` / `_claims` / `_task_manager`, plus `subscribe_ripples`
for ephemeral document ripples.

**Typed** (over a `watershed/schema` `TypedMap`):
`subscribe_field` (decoded `FieldChange`), `subscribe_typed` (whole-map events).

**Declarative bootstrap** — each dispatches its resolved channel once it settles,
so a document's nested structure is an `effect.batch` in `init`:
`ensure_map` / `ensure_counter` / `ensure_or_map` / `ensure_or_set` /
`ensure_register_collection` / `ensure_claims` / `ensure_task_manager` /
`ensure_pn_counter` / `ensure_pact_map` / `ensure_ordered_collection` /
`ensure_child`, and `ensure_field` (synchronous set-if-absent).

**Presence** — the heartbeat driver as effects:
`presence(document:, user_id:, config:, encode:, decode:, started:, on_peers:)`
starts it and hands the `Handle` back; `announce(handle, payload)` broadcasts.

**Timers & misc**: `after(ms, msg)`, `submit_ripple`, `force_reconnect`.

See [`examples/sudoku_lustre`](../examples/sudoku_lustre) for the typed +
presence surface end to end, and [`examples/dice_lustre`](../examples/dice_lustre)
for the minimal untyped case. JavaScript target only; consumed as a path
dependency inside the watershed monorepo (hex publication follows watershed's).
