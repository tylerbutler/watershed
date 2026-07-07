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

## API (LU1)

| Effect | Wraps |
| --- | --- |
| `connect` / `connect_dev` | `watershed_js.connect` (+ dev token mint) |
| `subscribe` and `subscribe_counter` / `_or_map` / `_or_set` / `_register_collection` / `_claims` / `_task_manager` / `subscribe_ripples` | the narrowed `watershed_js.subscribe_*` |
| `after(ms, msg)` | timer FFI |
| `submit_ripple` / `force_reconnect` | the matching `watershed_js` calls |

Edits and reads stay on `watershed_js` (`set`, `get`, `entries`, `increment`, …);
this package only wraps the callback-shaped surface.

Typed field/`ensure_*` effects (LU2) and a one-line presence effect (LU3) follow
once their watershed prerequisites land. JavaScript target only; consumed as a
path dependency inside the watershed monorepo.
