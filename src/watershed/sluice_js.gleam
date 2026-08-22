//// JavaScript test driver for the in-memory sluice (plan HM4).
////
//// This module is the equivalent of `watershed/sluice` for the JavaScript
//// target, and it is much simpler. JavaScript is single-threaded, so the
//// runtime processes every inbound frame synchronously, and it pushes its own
//// ops back synchronously. There is no actor and no barrier. `settle` empties
//// the outbox of the core in a loop, and the reaction to each delivery arrives
//// in the same cell before the next iteration reads that cell.
////
//// An application author whose application is JavaScript and Lustre can thus
//// write gleeunit convergence tests on `--target javascript`.
////
//// `advance` moves a *logical* clock and runs the timers that became due at
//// that time. A step of the clock thus drives everything that has a heartbeat
//// or a time-to-live (TTL), and the ripple fallback of presence above all.
//// Give `scheduler` to `presence_js.start_with_scheduler` to put a presence
//// handle on that clock.

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
import watershed/runtime
@target(javascript)
import watershed/sluice/core
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/wire/socket
@target(javascript)
import watershed

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A running in-memory server for one document.
pub opaque type Sluice {
  Sluice(cell: Cell(State), tenant: String, document: String)
}

@target(javascript)
/// The metadata of one delivered frame, which `step_info` returns. A caller,
/// for example a live demo, can thus animate and log each hop. For an `op`
/// event, `sequence_number` is the sequence number of the op and `author` is
/// the client that wrote it. Another event, such as a handshake or a signal,
/// reports `0` and `""`.
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
/// Connect a new client and return a real `watershed.Document` value. The
/// handshake completes on the next `settle`, because every delivery is
/// explicit.
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> watershed.Document(root) {
  let transport = make_transport(sluice.cell)
  let document =
    watershed.connect_via(
      tenant: sluice.tenant,
      document: sluice.document,
      user_id: user_id,
      transport: transport,
      on_ready: fn(_result) { Nil },
    )
  // Delayed work goes on the sluice's logical clock, so anything the runtime
  // schedules for itself — today, the automatic summarization policy's jitter
  // window — is driven by `advance` rather than by real elapsed time.
  runtime.set_scheduler(watershed.runtime_of(document), scheduler(sluice))
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
            #(watershed.runtime_of(document), client_id),
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
/// Hold the inbound frames of a client until a `resume` call. The queued frames
/// of that client stay in the queue while the sluice delivers the frames of the
/// other clients, so a test can script a race.
pub fn pause(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  apply_to_client(sluice, document, core.pause)
}

@target(javascript)
/// Return the held frames of a paused client to the deliverable queue.
pub fn resume(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  apply_to_client(sluice, document, core.resume)
}

@target(javascript)
/// Remove a client from the room, and sequence a `"leave"` message to the
/// clients that remain.
///
/// This is the path for a departure that is not graceful. It is the only way
/// to test the kernel behaviour that depends on membership: a `TaskManager`
/// role that the kernel releases because its holder left, or a `PactMap`
/// proposal whose signoff list becomes empty because one of the clients that
/// it waited on is no longer in the room. `pause` cannot replace this
/// function. A paused client is still a member, so a pact still waits on it,
/// and that stall is the condition under test.
pub fn disconnect(
  sluice: Sluice,
  document: watershed.Document(root),
) -> Nil {
  apply_to_client(sluice, document, core.disconnect)
}

@target(javascript)
/// Close the socket of a client and then let that client return. This is the
/// reconnect that a real client survives. It is not a departure.
///
/// The difference from `disconnect` is the purpose of this function.
/// `disconnect` removes a client from the room permanently. This function
/// closes the connection below a runtime that keeps its core, which is the
/// kernel state, the pending consensus, and the in-flight queue. The runtime
/// then does the handshake again. The server assigns it a **new client id**,
/// exactly as floodgate does, so the client that returns is a different member
/// of the room than the client that left.
///
/// Many protocol faults are in that window. An op that sequenced while the
/// client was absent replays against the room as it was at that time. An edit
/// from the interval gets a new stamp and a resubmission. A consensus kernel
/// can owe signoffs under an identity that no longer exists.
///
/// Unlike the Erlang driver, this function never runs `Transport.connect`
/// again, because the JavaScript runtime never does that either. Its real
/// transport is a Phoenix socket, which joins again by itself and runs
/// `on_join` again on the same channel. This driver thus models the rejoin
/// where it happens: the connection stays open, and the *server* gives it a
/// new identity.
///
/// The handshake completes on the next `settle`, the same as for `connect`.
pub fn reconnect(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  drop(sluice, document)
  rejoin(sluice, document)
}

@target(javascript)
/// The first half of `reconnect`: close the socket and keep it closed.
///
/// The two halves are separate because the interesting window is *between*
/// them. A client is outside the room from its `leave` until its rejoin. Every
/// op that sequences in that interval sequenced for a room that did not contain
/// the client. The client must then replay those ops, under an identity that
/// did not exist when other clients made them. To script that sequence, a test
/// must sequence ops while the client is absent, and one atomic reconnect
/// cannot express that.
///
/// The runtime keeps its core and stays in its reconnecting phase until
/// `rejoin`.
pub fn drop(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case conn_for(state, watershed.runtime_of(document)) {
    Error(_) -> Nil
    Ok(#(token, _)) -> drop_token(sluice.cell, token)
  }
}

@target(javascript)
/// `drop`, keyed by transport token instead of by document.
///
/// The transport handle closes over its token, and it has no `Sluice` value or
/// `Document` value to give. Its `hold` function thus needs this form.
/// `watershed.go_offline` therefore works against the sluice, and not against
/// a real socket only.
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
/// The second half of `reconnect`: let a dropped client return, under a new
/// client id that the server assigns.
///
/// The function does nothing for a client that `drop` did not remove.
pub fn rejoin(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case conn_for(state, watershed.runtime_of(document)) {
    Ok(#(token, _)) -> rejoin_token(sluice.cell, token)
    Error(_) -> Nil
  }
}

@target(javascript)
/// `rejoin`, keyed by transport token. The `resume` function of the handle
/// needs this form. See `drop_token`.
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
  runtime: runtime.Runtime,
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
  document: watershed.Document(root),
  change: fn(core.Sluice, String) -> core.Sluice,
) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case client_id_of(state, watershed.runtime_of(document)) {
    Ok(client_id) ->
      transport_js.set_cell(
        sluice.cell,
        State(..state, core: change(state.core, client_id)),
      )
    Error(_) -> Nil
  }
}

@target(javascript)
/// Deliver the queued frames until the system is quiet. The function is
/// synchronous: the reaction to each delivery goes back into the core before
/// the next iteration.
pub fn settle(sluice: Sluice) -> Nil {
  drain(sluice.cell)
}

@target(javascript)
/// Deliver exactly one queued frame, to a client that is not paused. The
/// function returns `False` when it can deliver no frame.
pub fn step(sluice: Sluice) -> Bool {
  case take_deliver(sluice.cell) {
    Some(_) -> True
    None -> False
  }
}

@target(javascript)
/// The same as `step`, but the function reports what it delivered: the target
/// client, the event, and, for an `op` event, the sequence number and the
/// author. The result is `None` when the function can deliver no frame. Use it
/// to drive a live visualization that animates each hop.
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
/// Report the next frame that `step` or `step_info` would deliver, and deliver
/// nothing. A caller can thus collect a whole broadcast group, which is every
/// frame that shares the sequence number of one op, into one animation step.
/// Every replica then receives the op together, and not one hop at a time.
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
/// Whether a frame still waits for delivery to a client that is not paused.
pub fn pending(sluice: Sluice) -> Bool {
  core.has_pending(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// The client id that the sluice assigned to a document. It is the same value
/// as the `to` field and the `author` field of `step_info`. The result is an
/// `Error` if the document is not connected to this sluice.
pub fn client_id(
  sluice: Sluice,
  document: watershed.Document(root),
) -> Result(String, Nil) {
  client_id_of(
    transport_js.get_cell(sluice.cell),
    watershed.runtime_of(document),
  )
}

@target(javascript)
/// The current server sequence number. An op sequences synchronously at submit
/// time, so a read immediately after an edit gives the sequence number of that
/// op.
pub fn sequence_number(sluice: Sluice) -> Int {
  core.sequence_number(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// Advance the logical clock of the sluice and run every timer that became
/// due. A test can thus check the logic that depends on a time-to-live (TTL) or
/// on a heartbeat, without a wait for the real time.
///
/// The timers run one at a time, and the function reads the cell again between
/// them. A heartbeat schedules itself again from inside its own callback, and
/// this same `advance` call must not run that replacement.
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(..state, core: core.advance(state.core, ms)),
  )
  fire_due(sluice)
}

@target(javascript)
/// Remove `presence_v1` from the handshake. A client in `Auto` mode thus
/// selects the ripple fallback, and a client that forces `Server` mode fails.
/// Call this function before `connect`.
pub fn disable_presence(sluice: Sluice) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(..state, core: core.set_presence_supported(state.core, False)),
  )
}

@target(javascript)
/// A scheduler that uses the logical clock of this sluice. Use it to drive a
/// presence handle, or anything else with a heartbeat, from `advance` instead
/// of from the real elapsed time.
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
/// Run the earliest timer that is due, then look again. The function recurses,
/// and it does not fold, and that choice is deliberate. Each callback can
/// schedule, cancel, or run more timers, so the function must read the list
/// again in every round.
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
/// Take the next deliverable frame, deliver it, and return it. The result is
/// `None` when there is no such frame. The function commits the take before the
/// delivery, because the reaction of the recipient goes back into the same
/// cell, and the function must not overwrite it.
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
/// Read the sequence number and the author from the payload of an `op` frame,
/// for `step_info`. The result is `0` and `""` for another kind of event.
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
fn make_transport(cell: Cell(State)) -> runtime.Transport {
  runtime.Transport(
    connect: fn(callbacks: runtime.TransportCallbacks) -> runtime.TransportHandle {
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
      // `watershed.go_offline` behaves the same here as over a real socket,
      // which is what lets an app test its own offline path.
      runtime.TransportHandle(
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
/// `current` is the id that the *server* assigned to the connection, and that
/// id can change. A rejoin gets a new one, exactly as floodgate gives one to
/// each connection. Every other part of the driver uses the stable token of
/// the connection as its key. A reconnect thus changes the identity, and the
/// handle of the runtime stays valid.
type Conn {
  Conn(
    on_event: fn(String, Dynamic) -> Nil,
    on_join: fn() -> Nil,
    on_close: fn() -> Nil,
    current: String,
    /// `drop` closed the socket, and the connection waits for `rejoin`.
    dropped: Bool,
  )
}

@target(javascript)
type State {
  State(
    core: core.Sluice,
    /// Keyed by connection token, which is the id that the driver created when
    /// the link opened. That id never changes, also when the server assigns a
    /// new `Conn.current` value.
    conns: List(#(String, Conn)),
    /// A map from a runtime to a connection token, so that `pause` and
    /// `resume` can select a document by its identity. A structural equality
    /// test would compare the state cells in full.
    bindings: List(#(runtime.Runtime, String)),
    last_registered: Option(String),
    /// The timers that the driver scheduled against the logical clock, as
    /// `#(due_at_ms, id, action)`. `advance` runs them. A heartbeat or a TTL
    /// thus becomes a step that a test can script, and not a wait.
    timers: List(#(Int, Int, fn() -> Nil)),
    next_timer_id: Int,
  )
}

@target(javascript)
/// The connection token that is bound to a runtime.
fn token_of(
  bindings: List(#(runtime.Runtime, String)),
  runtime: runtime.Runtime,
) -> Result(String, Nil) {
  case list.find(bindings, fn(pair) { reference_equals(pair.0, runtime) }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
/// The current id that the server assigned to a runtime.
fn client_id_of(
  state: State,
  runtime: runtime.Runtime,
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
fn reference_equals(a: runtime.Runtime, b: runtime.Runtime) -> Bool

@target(javascript)
/// The connection that the server knows by `client_id` now. A frame carries the
/// id that the server assigned, so this function searches the `current` field,
/// and not the token that keys the list.
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
/// Serialize a queued `Json` frame and parse it again as `Dynamic`. This is the
/// exact path that a frame takes over a real socket before the runtime decodes
/// it.
fn to_dynamic(payload: Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}
