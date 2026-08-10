//// FFI bindings to the Phoenix-based JS transport (`transport_ffi.mjs`).
////
//// JavaScript target only. The whole module is gated with `@target(javascript)`
//// so watershed's erlang build ignores it, mirroring how `runtime`/`watershed`
//// are gated to erlang.

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/javascript/promise.{type Promise}

@target(javascript)
/// An opaque Phoenix channel handle (carries its socket back-reference).
pub type Channel

@target(javascript)
/// A mutable state cell used by `runtime_js` to hold its state machine.
pub type Cell(a)

@target(javascript)
/// Open a socket, join `topic`, and wire the runtime callbacks. `on_join`
/// fires on every successful (re)join (Phoenix auto-rejoins after a socket
/// reconnect, so this is also the re-handshake hook); `on_event` receives
/// `(event_name, parsed_payload)` where the payload is a JS object ready for
/// Gleam's dynamic decoders.
@external(javascript, "./transport_ffi.mjs", "connect")
pub fn connect(
  url url: String,
  topic topic: String,
  join_payload join_payload: String,
  on_event on_event: fn(String, Dynamic) -> Nil,
  on_join on_join: fn() -> Nil,
  on_close on_close: fn() -> Nil,
) -> Channel

@target(javascript)
/// Push a channel event; `payload` is a JSON string from the wire encoders.
@external(javascript, "./transport_ffi.mjs", "push")
pub fn push(channel: Channel, event: String, payload: String) -> Nil

@target(javascript)
/// Force the socket down to exercise the reconnect path (Phoenix rejoins).
@external(javascript, "./transport_ffi.mjs", "dropSocket")
pub fn drop_socket(channel: Channel) -> Nil

@target(javascript)
/// Take the socket down and leave it down, so the client can keep editing
/// offline. `resume_socket` brings it back.
@external(javascript, "./transport_ffi.mjs", "holdSocket")
pub fn hold_socket(channel: Channel) -> Nil

@target(javascript)
/// Bring a held socket back; phoenix rejoins and re-fires the join callback.
@external(javascript, "./transport_ffi.mjs", "resumeSocket")
pub fn resume_socket(channel: Channel) -> Nil

@target(javascript)
@external(javascript, "./transport_ffi.mjs", "close")
pub fn close(channel: Channel) -> Nil

@target(javascript)
@external(javascript, "./transport_ffi.mjs", "newCell")
pub fn new_cell(value: a) -> Cell(a)

@target(javascript)
@external(javascript, "./transport_ffi.mjs", "getCell")
pub fn get_cell(cell: Cell(a)) -> a

@target(javascript)
@external(javascript, "./transport_ffi.mjs", "setCell")
pub fn set_cell(cell: Cell(a), value: a) -> Nil

@target(javascript)
@external(javascript, "./transport_ffi.mjs", "nowMs")
pub fn now_ms() -> Int

@target(javascript)
/// A cancellable timer handle returned by `set_timer`.
pub type TimerId

@target(javascript)
/// Schedule `action` after `ms`, returning a handle for `clear_timer`.
@external(javascript, "./transport_ffi.mjs", "setTimer")
pub fn set_timer(action: fn() -> Nil, ms: Int) -> TimerId

@target(javascript)
/// Cancel a pending timer.
@external(javascript, "./transport_ffi.mjs", "clearTimer")
pub fn clear_timer(id: TimerId) -> Nil

@target(javascript)
/// A clock and timer source, so anything with a TTL or a heartbeat can be
/// driven by a test's logical clock instead of by real elapsed time.
///
/// `schedule` returns a *canceller* rather than a `TimerId` so a substitute
/// scheduler needs no FFI type of its own — see `sluice_js.scheduler`, which
/// hangs one off the sluice's `advance`.
pub type Scheduler {
  Scheduler(now_ms: fn() -> Int, schedule: fn(fn() -> Nil, Int) -> fn() -> Nil)
}

@target(javascript)
/// The real clock and `setTimeout`.
pub fn real_scheduler() -> Scheduler {
  Scheduler(now_ms: now_ms, schedule: fn(action, ms) {
    let id = set_timer(action, ms)
    fn() { clear_timer(id) }
  })
}

@target(javascript)
/// Mint an HS256 dev JWT matching levee's dev-mode verification. Signs with
/// Web Crypto, so the token resolves asynchronously.
@external(javascript, "./transport_ffi.mjs", "mintDevToken")
pub fn mint_dev_token(
  secret: String,
  tenant: String,
  document: String,
  user_id: String,
) -> Promise(String)
