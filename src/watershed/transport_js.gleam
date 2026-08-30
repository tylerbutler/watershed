//// FFI bindings to the Phoenix-based JS transport (`transport_ffi.mjs`).
////
//// JavaScript target only. `@target(javascript)` gates the whole module, so
//// the Erlang build of watershed ignores it.

@target(javascript)
import gleam/javascript/promise.{type Promise}

@target(javascript)
/// An opaque Phoenix channel handle. It carries a back-reference to its
/// socket.
pub type Channel

@target(javascript)
/// A mutable state cell used by `runtime` to hold its state machine.
pub type Cell(a)

@target(javascript)
/// Open a socket, join `topic`, and connect the runtime callbacks.
///
/// `on_join` runs after every successful join. Phoenix joins again by itself
/// after a socket reconnect, so `on_join` is also the re-handshake hook.
///
/// `on_event` receives `(event_name, payload_json)`. `payload_json` is the
/// event's payload, serialized to a JSON string on the JavaScript side, ready
/// for `gleam/json`'s decoders on the Gleam side.
@external(javascript, "./transport_ffi.mjs", "connect")
pub fn connect(
  url url: String,
  topic topic: String,
  join_payload join_payload: String,
  on_event on_event: fn(String, String) -> Nil,
  on_join on_join: fn() -> Nil,
  on_close on_close: fn() -> Nil,
) -> Channel

@target(javascript)
/// Push a channel event. `payload` is a JSON string from the wire encoders.
@external(javascript, "./transport_ffi.mjs", "push")
pub fn push(channel: Channel, event: String, payload: String) -> Nil

@target(javascript)
/// Close the socket, to test the reconnect path. Phoenix joins again.
@external(javascript, "./transport_ffi.mjs", "dropSocket")
pub fn drop_socket(channel: Channel) -> Nil

@target(javascript)
/// Close the socket and keep it closed, so the client can continue to edit
/// offline. `resume_socket` opens it again.
@external(javascript, "./transport_ffi.mjs", "holdSocket")
pub fn hold_socket(channel: Channel) -> Nil

@target(javascript)
/// Open a held socket again. Phoenix joins again and runs the join callback
/// again.
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
pub fn now_milliseconds() -> Int

@target(javascript)
/// A cancellable timer handle returned by `set_timer`.
pub type TimerId

@target(javascript)
/// Schedule `action` after `ms`, and return a handle for `clear_timer`.
@external(javascript, "./transport_ffi.mjs", "setTimer")
pub fn set_timer(action: fn() -> Nil, milliseconds: Int) -> TimerId

@target(javascript)
/// Cancel a pending timer.
@external(javascript, "./transport_ffi.mjs", "clearTimer")
pub fn clear_timer(id: TimerId) -> Nil

@target(javascript)
/// A clock and timer source. A logical clock in a test can thus drive
/// everything that has a time-to-live (TTL) or a heartbeat, instead of the
/// real elapsed time.
///
/// `schedule` returns a canceller and not a `TimerId`, so a substitute
/// scheduler needs no FFI type of its own. See `sluice_js.scheduler`, which
/// builds one on the `advance` function of the sluice.
pub type Scheduler {
  Scheduler(
    now_milliseconds: fn() -> Int,
    schedule: fn(fn() -> Nil, Int) -> fn() -> Nil,
  )
}

@target(javascript)
/// The real clock and `setTimeout`.
pub fn real_scheduler() -> Scheduler {
  Scheduler(
    now_milliseconds: now_milliseconds,
    schedule: fn(action, milliseconds) {
      let id = set_timer(action, milliseconds)
      fn() { clear_timer(id) }
    },
  )
}

@target(javascript)
/// Mint an HS256 development JWT that agrees with the development-mode
/// verification of floodgate. The function signs with Web Crypto, so the token
/// resolves asynchronously.
@external(javascript, "./transport_ffi.mjs", "mintDevToken")
pub fn mint_dev_token(
  secret: String,
  tenant: String,
  document: String,
  user_id: String,
) -> Promise(String)
