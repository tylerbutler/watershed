//// JavaScript test driver for the in-memory sluice (plan HM4).
////
//// The mirror of `watershed/sluice` for the JS target, and much simpler: JS is
//// single-threaded, so the runtime processes every inbound frame synchronously
//// and pushes its own ops back synchronously. There are no actors and no
//// barriers — `settle` just drains the core's outbox in a loop, and each
//// delivery's reaction lands in the same cell before the next iteration reads
//// it.
////
//// This is what lets app authors — whose apps are JS/Lustre — write gleeunit
//// convergence tests on `--target javascript`.
////
//// `advance` moves a *logical* clock and fires the timers that came due with
//// it, so anything on a heartbeat or a TTL — presence's ripple fallback, above
//// all — is driven by stepping the clock rather than by waiting. Hand
//// `scheduler` to `presence_js.start_with_scheduler` to put a presence handle
//// on that clock.

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/int
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/sluice/core
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/wire/socket
@target(javascript)
import watershed_js

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A running in-memory server for one document.
pub opaque type Sluice {
  Sluice(cell: Cell(State), tenant: String, document: String)
}

@target(javascript)
/// One delivered frame's metadata, returned by `step_info` so a caller (e.g. a
/// live demo) can animate and log each hop. For `op` events `sequence_number`
/// and `author` are the sequenced op's SN and authoring client; other events
/// (handshake, signal) report `0` / `""`.
pub type Delivery {
  Delivery(to: String, event: String, sequence_number: Int, author: String)
}

@target(javascript)
/// Start a sluice for one document.
pub fn start(tenant tenant: String, document document: String) -> Sluice {
  Sluice(
    cell: transport_js.new_cell(State(
      core: core.new(tenant, document),
      conns: [],
      bindings: [],
      last_registered: None,
      timers: [],
      next_timer_id: 1,
    )),
    tenant: tenant,
    document: document,
  )
}

@target(javascript)
/// Connect a fresh client, returning a real `watershed_js.Document`. The
/// handshake completes on the next `settle` (delivery is explicit).
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> watershed_js.Document {
  let transport = make_transport(sluice.cell)
  let document =
    watershed_js.connect_via(
      tenant: sluice.tenant,
      document: sluice.document,
      user_id: user_id,
      transport: transport,
      on_ready: fn(_result) { Nil },
    )
  // The runtime has now stored its transport handle, so it is safe to fire the
  // `on_join` that makes it push `connect_document`. (Firing during
  // `transport.connect` would run before the handle is stored.) We also bind the
  // document's runtime to the just-registered client id so `pause`/`resume` can
  // target it by identity.
  let state = transport_js.get_cell(sluice.cell)
  case state.last_registered {
    Some(client_id) -> {
      transport_js.set_cell(
        sluice.cell,
        State(
          ..state,
          bindings: [
            #(watershed_js.runtime_of(document), client_id),
            ..state.bindings
          ],
          last_registered: None,
        ),
      )
      case find_conn(state.conns, client_id) {
        Ok(conn) -> conn.on_join()
        Error(_) -> Nil
      }
    }
    None -> Nil
  }
  document
}

@target(javascript)
/// Hold a client's inbound frames until `resume` — its queued frames stay put
/// while others are delivered, so a race can be scripted.
pub fn pause(sluice: Sluice, document: watershed_js.Document) -> Nil {
  apply_to_client(sluice, document, core.pause)
}

@target(javascript)
/// Release a paused client's held frames back into the deliverable queue.
pub fn resume(sluice: Sluice, document: watershed_js.Document) -> Nil {
  apply_to_client(sluice, document, core.resume)
}

@target(javascript)
/// Drop a client from the room, sequencing a `"leave"` to the survivors.
///
/// This is the ungraceful-departure path, and it is the only way to test the
/// kernel behaviour that hangs off membership: a `TaskManager` role released
/// because its holder vanished, or a `PactMap` proposal whose signoff list
/// drains because one of the clients it was waiting on is no longer in the
/// room. `pause` cannot stand in for it — a paused client is still a member,
/// so a pact still waits on it, which is exactly the stall being tested.
pub fn disconnect(sluice: Sluice, document: watershed_js.Document) -> Nil {
  apply_to_client(sluice, document, core.disconnect)
}

@target(javascript)
/// Drop a client's socket and let it come back — the reconnect a real client
/// survives, rather than a departure it does not.
///
/// The distinction from `disconnect` is the whole point. `disconnect` removes a
/// client from the room for good; this severs the connection underneath a
/// runtime that keeps its core — kernel state, pending consensus, and the
/// in-flight queue all survive — and then lets it re-handshake. The server
/// assigns it a **fresh client id**, exactly as floodgate does, so the returning
/// client is a different member of the room than the one that left.
///
/// That is the window a lot of protocol bugs live in: ops sequenced while the
/// client was away replay against the room as it was *then*, edits made during
/// the gap are restamped and resubmitted, and a consensus kernel may owe
/// signoffs under an identity that no longer exists.
///
/// Unlike the erlang driver this never re-runs `Transport.connect`, because the
/// JS runtime never does either — its real transport is a Phoenix socket that
/// auto-rejoins and re-fires `on_join` on the same channel. So the rejoin is
/// modelled where it actually happens: the connection stays, and the *server*
/// hands it a new identity.
///
/// The handshake completes on the next `settle`, like `connect`.
pub fn reconnect(sluice: Sluice, document: watershed_js.Document) -> Nil {
  drop(sluice, document)
  rejoin(sluice, document)
}

@target(javascript)
/// The first half of `reconnect`: take the socket away and leave it away.
///
/// Splitting the two matters because the interesting window is *between* them.
/// A client is out of the room from its `leave` until its rejoin, and anything
/// sequenced in that gap was sequenced for a room it was not in — which it then
/// has to replay, under an identity that did not exist when those ops were
/// made. Scripting that means being able to sequence ops while the client is
/// away, which an atomic reconnect cannot express.
///
/// The runtime keeps its core and sits in its reconnecting phase until
/// `rejoin`.
pub fn drop(sluice: Sluice, document: watershed_js.Document) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case conn_for(state, watershed_js.runtime_of(document)) {
    Error(_) -> Nil
    Ok(#(token, _)) -> drop_token(sluice.cell, token)
  }
}

@target(javascript)
/// `drop` keyed by transport token rather than by document.
///
/// The transport handle closes over its token and has no `Sluice` or
/// `Document` to hand, so this is the form its `hold` needs — which is what
/// makes `watershed_js.go_offline` work against the sluice and not just against
/// a real socket.
fn drop_token(cell: Cell(State), token: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case list.key_find(state.conns, token) {
    Error(_) -> Nil
    Ok(conn) -> {
      transport_js.set_cell(
        cell,
        State(
          ..state,
          // The leave the server sequences when a socket goes away.
          core: core.disconnect(state.core, conn.current),
          conns: list.key_set(state.conns, token, Conn(..conn, dropped: True)),
        ),
      )
      conn.on_close()
    }
  }
}

@target(javascript)
/// The second half of `reconnect`: let a dropped client come back, under a
/// fresh server-assigned client id.
///
/// A no-op for a client that was not `drop`ped.
pub fn rejoin(sluice: Sluice, document: watershed_js.Document) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case conn_for(state, watershed_js.runtime_of(document)) {
    Ok(#(token, _)) -> rejoin_token(sluice.cell, token)
    Error(_) -> Nil
  }
}

@target(javascript)
/// `rejoin` keyed by transport token — the form the handle's `resume` needs.
/// See `drop_token`.
fn rejoin_token(cell: Cell(State), token: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case list.key_find(state.conns, token) {
    Ok(conn) if conn.dropped -> {
      let #(core, rejoined) = core.register(state.core)
      transport_js.set_cell(
        cell,
        State(
          ..state,
          core: core,
          conns: list.key_set(
            state.conns,
            token,
            Conn(..conn, current: rejoined, dropped: False),
          ),
        ),
      )
      // `on_close` already moved the runtime into its reconnecting phase, so
      // the `connect_document` this triggers carries `last_seen` and asks for a
      // catch-up rather than a fresh bootstrap.
      conn.on_join()
    }
    _ -> Nil
  }
}

@target(javascript)
fn conn_for(
  state: State,
  runtime: runtime_js.Runtime,
) -> Result(#(String, Conn), Nil) {
  case token_of(state.bindings, runtime) {
    Error(_) -> Error(Nil)
    Ok(token) ->
      case list.key_find(state.conns, token) {
        Ok(conn) -> Ok(#(token, conn))
        Error(_) -> Error(Nil)
      }
  }
}

@target(javascript)
fn apply_to_client(
  sluice: Sluice,
  document: watershed_js.Document,
  change: fn(core.Sluice, String) -> core.Sluice,
) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case client_id_of(state, watershed_js.runtime_of(document)) {
    Ok(client_id) ->
      transport_js.set_cell(
        sluice.cell,
        State(..state, core: change(state.core, client_id)),
      )
    Error(_) -> Nil
  }
}

@target(javascript)
/// Deliver queued frames until the system is quiescent. Synchronous: each
/// delivery's reaction is pushed back into the core before the next iteration.
pub fn settle(sluice: Sluice) -> Nil {
  drain(sluice.cell)
}

@target(javascript)
/// Deliver exactly one queued frame (to a non-paused client), returning `False`
/// when nothing was deliverable.
pub fn step(sluice: Sluice) -> Bool {
  case take_deliver(sluice.cell) {
    Some(_) -> True
    None -> False
  }
}

@target(javascript)
/// Like `step`, but reports what was delivered (target client, event, and — for
/// `op` events — the sequence number and author). `None` when nothing was
/// deliverable. For driving live visualisations that animate each hop.
pub fn step_info(sluice: Sluice) -> Option(Delivery) {
  case take_deliver(sluice.cell) {
    None -> None
    Some(frame) -> {
      let #(sequence_number, author) = op_meta(frame)
      Some(Delivery(
        to: frame.client_id,
        event: frame.event,
        sequence_number: sequence_number,
        author: author,
      ))
    }
  }
}

@target(javascript)
/// Report the next frame `step`/`step_info` would deliver, without delivering
/// it. Lets a caller group a whole broadcast wave (every frame sharing an op's
/// sequence number) into one animation tick, so all replicas receive an op
/// together instead of one serial hop at a time.
pub fn peek_info(sluice: Sluice) -> Option(Delivery) {
  case core.peek(transport_js.get_cell(sluice.cell).core) {
    None -> None
    Some(frame) -> {
      let #(sequence_number, author) = op_meta(frame)
      Some(Delivery(
        to: frame.client_id,
        event: frame.event,
        sequence_number: sequence_number,
        author: author,
      ))
    }
  }
}

@target(javascript)
/// Whether any frame is still awaiting delivery to a non-paused client.
pub fn pending(sluice: Sluice) -> Bool {
  core.has_pending(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// The sluice-assigned client id for a document (matches the `to`/`author`
/// fields of `step_info`), or `Error` if it isn't connected here.
pub fn client_id(
  sluice: Sluice,
  document: watershed_js.Document,
) -> Result(String, Nil) {
  client_id_of(
    transport_js.get_cell(sluice.cell),
    watershed_js.runtime_of(document),
  )
}

@target(javascript)
/// The current server sequence number. Ops sequence synchronously on submit,
/// so reading this right after an edit yields that op's SN.
pub fn sequence_number(sluice: Sluice) -> Int {
  core.sequence_number(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// Advance the sluice's logical clock and fire every timer that came due, so
/// TTL- and heartbeat-based logic is testable without real time passing.
///
/// Timers fire one at a time, re-reading the cell between each: a heartbeat
/// re-schedules itself from inside its own callback, and the replacement must
/// not be fired by this same `advance`.
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(..state, core: core.advance(state.core, ms)),
  )
  fire_due(sluice)
}

@target(javascript)
/// Withhold `presence_v1` from the handshake, so a client under `Auto` picks the
/// ripple fallback and a client forcing `Server` fails. Call before `connect`.
pub fn disable_presence(sluice: Sluice) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(..state, core: core.set_presence_supported(state.core, False)),
  )
}

@target(javascript)
/// A scheduler bound to this sluice's logical clock, for driving a presence
/// handle (or anything else with a heartbeat) from `advance` instead of real
/// elapsed time.
pub fn scheduler(sluice: Sluice) -> transport_js.Scheduler {
  transport_js.Scheduler(
    now_ms: fn() { core.now(transport_js.get_cell(sluice.cell).core) },
    schedule: fn(action, ms) { schedule_timer(sluice, action, ms) },
  )
}

@target(javascript)
fn schedule_timer(sluice: Sluice, action: fn() -> Nil, ms: Int) -> fn() -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  let id = state.next_timer_id
  transport_js.set_cell(
    sluice.cell,
    State(
      ..state,
      timers: [#(core.now(state.core) + ms, id, action), ..state.timers],
      next_timer_id: id + 1,
    ),
  )
  fn() { cancel_timer(sluice, id) }
}

@target(javascript)
fn cancel_timer(sluice: Sluice, id: Int) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(
      ..state,
      timers: list.filter(state.timers, fn(timer) { timer.1 != id }),
    ),
  )
}

@target(javascript)
/// Fire the earliest due timer, then look again. Recursing rather than folding
/// is deliberate: each callback may schedule, cancel, or fire further timers,
/// so the list has to be re-read every round.
fn fire_due(sluice: Sluice) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  let now = core.now(state.core)
  let due = list.filter(state.timers, fn(timer) { timer.0 <= now })
  case list.sort(due, fn(a, b) { int.compare(a.0, b.0) }) {
    [] -> Nil
    [#(_, id, action), ..] -> {
      cancel_timer(sluice, id)
      action()
      fire_due(sluice)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn drain(cell: Cell(State)) -> Nil {
  case take_deliver(cell) {
    None -> Nil
    Some(_) -> drain(cell)
  }
}

@target(javascript)
/// Take the next deliverable frame, deliver it, and return it (or `None`).
/// Commits the take before delivering: the recipient's reaction pushes back
/// into the same cell, and we must not clobber it.
fn take_deliver(cell: Cell(State)) -> Option(core.Outbound) {
  let state = transport_js.get_cell(cell)
  case core.take(state.core) {
    #(core, None) -> {
      transport_js.set_cell(cell, State(..state, core: core))
      None
    }
    #(core, Some(frame)) -> {
      transport_js.set_cell(cell, State(..state, core: core))
      case find_conn(state.conns, frame.client_id) {
        Ok(conn) -> conn.on_event(frame.event, to_dynamic(frame.payload))
        Error(_) -> Nil
      }
      Some(frame)
    }
  }
}

@target(javascript)
/// Pull the sequence number and author from an `op` frame's payload (`0`/`""`
/// for other event kinds), for `step_info`.
fn op_meta(frame: core.Outbound) -> #(Int, String) {
  case frame.event {
    "op" ->
      case
        json.parse(json.to_string(frame.payload), socket.op_message_decoder())
      {
        Ok(message) ->
          case message.ops {
            [op, ..] -> #(op.sequence_number, option.unwrap(op.client_id, ""))
            [] -> #(0, "")
          }
        Error(_) -> #(0, "")
      }
    _ -> #(0, "")
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport: bridges a runtime to the sluice cell
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn make_transport(cell: Cell(State)) -> runtime_js.Transport {
  runtime_js.Transport(
    connect: fn(callbacks: runtime_js.TransportCallbacks) -> runtime_js.TransportHandle {
      let token =
        register(
          cell,
          callbacks.on_event,
          callbacks.on_join,
          callbacks.on_close,
        )
      // Closes over the *token*, not the server-assigned id, so the handle keeps
      // working after a reconnect reassigns the latter.
      // `close` and `drop` stay inert: the sluice drives those from the outside,
      // through `sluice_js.disconnect` / `drop`, because a test scripting a
      // race needs to sequence ops *between* the two halves of a reconnect.
      // `hold`/`resume` have no such external caller — they exist so
      // `watershed_js.go_offline` behaves the same here as over a real socket,
      // which is what lets an app test its own offline path.
      runtime_js.TransportHandle(
        push: fn(event, payload) { push(cell, token, event, payload) },
        close: fn() { Nil },
        drop: fn() { Nil },
        hold: fn() { drop_token(cell, token) },
        resume: fn() { rejoin_token(cell, token) },
      )
    },
  )
}

@target(javascript)
fn register(
  cell: Cell(State),
  on_event: fn(String, Dynamic) -> Nil,
  on_join: fn() -> Nil,
  on_close: fn() -> Nil,
) -> String {
  let state = transport_js.get_cell(cell)
  let #(core, client_id) = core.register(state.core)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      core: core,
      // The minted id is both the token this connection is keyed by and its
      // first server-assigned identity; only the latter moves.
      conns: [
        #(client_id, Conn(on_event, on_join, on_close, client_id, False)),
        ..state.conns
      ],
      last_registered: Some(client_id),
    ),
  )
  client_id
}

@target(javascript)
fn push(cell: Cell(State), token: String, event: String, payload: Json) -> Nil {
  let state = transport_js.get_cell(cell)
  case list.key_find(state.conns, token) {
    Error(_) -> Nil
    Ok(conn) ->
      transport_js.set_cell(
        cell,
        State(
          ..state,
          core: core.handle(
            state.core,
            conn.current,
            event,
            to_dynamic(payload),
          ),
        ),
      )
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// One open connection.
///
/// `current` is the id the *server* has assigned it, which is not fixed: a
/// rejoin gets a fresh one, exactly as floodgate hands one out per connection.
/// Everything else keys off the connection's stable token instead, so a
/// reconnect rotates the identity without the runtime's handle going stale.
type Conn {
  Conn(
    on_event: fn(String, Dynamic) -> Nil,
    on_join: fn() -> Nil,
    on_close: fn() -> Nil,
    current: String,
    /// Socket taken away by `drop`, awaiting `rejoin`.
    dropped: Bool,
  )
}

@target(javascript)
type State {
  State(
    core: core.Sluice,
    /// Keyed by connection token — the id minted when the link opened, which
    /// never changes even when the server reassigns `Conn.current`.
    conns: List(#(String, Conn)),
    /// Runtime → connection token, so `pause`/`resume` can target a document by
    /// identity (structural equality would deep-compare state cells).
    bindings: List(#(runtime_js.Runtime, String)),
    last_registered: Option(String),
    /// Timers scheduled against the logical clock: `#(due_at_ms, id, action)`.
    /// `advance` is what fires them, which is how a heartbeat or a TTL becomes
    /// a scriptable step rather than a wait.
    timers: List(#(Int, Int, fn() -> Nil)),
    next_timer_id: Int,
  )
}

@target(javascript)
/// The connection token bound to a runtime.
fn token_of(
  bindings: List(#(runtime_js.Runtime, String)),
  runtime: runtime_js.Runtime,
) -> Result(String, Nil) {
  case list.find(bindings, fn(pair) { reference_equals(pair.0, runtime) }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
/// The server-assigned id a runtime is currently known by.
fn client_id_of(
  state: State,
  runtime: runtime_js.Runtime,
) -> Result(String, Nil) {
  case token_of(state.bindings, runtime) {
    Error(_) -> Error(Nil)
    Ok(token) ->
      case list.key_find(state.conns, token) {
        Ok(conn) -> Ok(conn.current)
        Error(_) -> Error(Nil)
      }
  }
}

@target(javascript)
@external(javascript, "./sluice_ffi.mjs", "referenceEquals")
fn reference_equals(a: runtime_js.Runtime, b: runtime_js.Runtime) -> Bool

@target(javascript)
/// The connection the server currently knows by `client_id`. Frames are
/// addressed by server-assigned id, so this searches `current` rather than the
/// token the list is keyed by.
fn find_conn(
  conns: List(#(String, Conn)),
  client_id: String,
) -> Result(Conn, Nil) {
  case list.find(conns, fn(pair) { { pair.1 }.current == client_id }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
/// Serialize a queued `Json` frame and re-parse it as `Dynamic` — the exact
/// trip a frame takes over a real socket before the runtime decodes it.
fn to_dynamic(payload: Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}
