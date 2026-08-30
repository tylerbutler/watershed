//// A deterministic stand-in for a relay service and a clock, for the
//// `crdt_relay_v1` client and facade tests.
////
//// One `Hub` runs the *real* protocol — `watershed/crdt_relay`, the same
//// module the reference service and Floodgate must implement — over an
//// in-memory queue instead of a socket. So these tests exercise the
//// admission rules, the order stamping, the attestation arithmetic and
//// the log compaction as they actually ship, and only the socket is
//// pretend.
////
//// Delivery is queued rather than direct: every frame in either
//// direction is enqueued and runs only inside `settle`, so a test never
//// observes a relay callback firing re-entrantly out of the send that
//// caused it, and every run produces the same interleaving.
////
//// `Clock` is the other half. It is a `transport_js.Scheduler` over a
//// logical millisecond counter, so reconnect backoff, resync backoff and
//// the `SequencedOnly` readiness deadline are all stepped with `advance`
//// rather than waited for. It also records every delay it was asked for,
//// which is how the backoff *sequence* is asserted rather than just its
//// effect.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/order
@target(javascript)
import gleam/string

@target(javascript)
import watershed/crdt_relay
@target(javascript)
import watershed/crdt_sequencer_js.{
  type Driver, type Handlers, Connection, Driver,
}
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler, Scheduler}

// ─────────────────────────────────────────────────────────────────────────────
// A logical clock
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub type Clock {
  Clock(cell: Cell(ClockState))
}

@target(javascript)
pub type ClockState {
  ClockState(
    now: Int,
    next_id: Int,
    /// Armed timers: id, the moment they are due, and what to run.
    timers: List(#(Int, Int, fn() -> Nil)),
    /// Every delay the clock was ever asked for, oldest first.
    requested: List(Int),
  )
}

@target(javascript)
pub fn new_clock() -> Clock {
  Clock(
    cell: transport_js.new_cell(
      ClockState(now: 0, next_id: 1, timers: [], requested: []),
    ),
  )
}

@target(javascript)
/// The `Scheduler` this clock drives.
pub fn scheduler(clock: Clock) -> Scheduler {
  Scheduler(
    now_ms: fn() { transport_js.get_cell(clock.cell).now },
    schedule: fn(action, delay) {
      let state = transport_js.get_cell(clock.cell)
      let id = state.next_id
      transport_js.set_cell(
        clock.cell,
        ClockState(
          ..state,
          next_id: id + 1,
          timers: [#(id, state.now + delay, action), ..state.timers],
          requested: [delay, ..state.requested],
        ),
      )
      fn() {
        let state = transport_js.get_cell(clock.cell)
        transport_js.set_cell(
          clock.cell,
          ClockState(
            ..state,
            timers: list.filter(state.timers, fn(timer) { timer.0 != id }),
          ),
        )
      }
    },
  )
}

@target(javascript)
/// Every delay this clock was asked to wait, oldest first. The backoff
/// sequence, as a list.
pub fn delays(clock: Clock) -> List(Int) {
  list.reverse(transport_js.get_cell(clock.cell).requested)
}

@target(javascript)
pub fn now(clock: Clock) -> Int {
  transport_js.get_cell(clock.cell).now
}

@target(javascript)
pub fn armed(clock: Clock) -> Int {
  list.length(transport_js.get_cell(clock.cell).timers)
}

@target(javascript)
/// Timers that are already due at the current logical instant — the
/// zero-delay ticks a coalesced digest is armed on. A settle loop uses
/// this to know it still has work, without moving the clock.
pub fn due(clock: Clock) -> Int {
  let state = transport_js.get_cell(clock.cell)
  state.timers
  |> list.filter(fn(timer) { timer.1 <= state.now })
  |> list.length
}

@target(javascript)
/// Move the clock forward, running everything that comes due in order.
/// A timer armed by a timer runs too, if it is due within the same step.
pub fn advance(clock: Clock, by: Int) -> Nil {
  let state = transport_js.get_cell(clock.cell)
  let target = state.now + by
  step(clock, target, 1000)
}

@target(javascript)
fn step(clock: Clock, target: Int, fuel: Int) -> Nil {
  case fuel <= 0 {
    True -> panic as "relay_fake: the clock did not settle"
    False -> {
      let state = transport_js.get_cell(clock.cell)
      let due =
        state.timers
        |> list.filter(fn(timer) { timer.1 <= target })
        |> list.sort(fn(left, right) {
          case int.compare(left.1, right.1) {
            order.Eq -> int.compare(left.0, right.0)
            other -> other
          }
        })
      case due {
        [] -> {
          transport_js.set_cell(clock.cell, ClockState(..state, now: target))
          Nil
        }
        [#(id, at, action), ..] -> {
          transport_js.set_cell(
            clock.cell,
            ClockState(
              ..state,
              now: at,
              timers: list.filter(state.timers, fn(timer) { timer.0 != id }),
            ),
          )
          action()
          step(clock, target, fuel - 1)
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A relay hub
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub type Socket {
  Socket(
    id: Int,
    on_message: fn(String) -> Nil,
    on_close: fn(String) -> Nil,
    open: Bool,
  )
}

@target(javascript)
pub type Effect {
  ToRelay(connection: Int, raw: String)
  ToClient(connection: Int, raw: String)
  CloseClient(connection: Int, detail: String)
  OpenClient(connection: Int)
}

@target(javascript)
pub type HubState {
  HubState(
    relay: crdt_relay.Relay,
    sockets: Dict(Int, Socket),
    next_connection: Int,
    queue: List(Effect),
    /// Whether the service is running at all. `False` models the process
    /// being absent: sockets are refused and open ones are dropped.
    up: Bool,
    /// What the greeting advertises. `False` models a sequencer with no
    /// relay lane.
    supports: Bool,
    /// A greeting to send instead of the real one, for the malformed
    /// handshake cases.
    greeting: Option(String),
    /// Whether writes from a client reach the service. `False` models a
    /// socket that has left `OPEN` without its close having been
    /// delivered yet — the window in which a real `WebSocket.send` is a
    /// silent no-operation unless the caller is told about it.
    writable: Bool,
    /// How many more writes this hub will accept before behaving that
    /// way. Negative is unlimited; a budget is how a test makes exactly
    /// the third or fourth frame of an attachment be the one that does
    /// not arrive.
    write_budget: Int,
    /// Every raw frame a client ever wrote, oldest first.
    inbound: List(String),
    /// Every raw frame the service ever wrote, oldest first.
    outbound: List(String),
    /// Durable lines by room, exactly as a service would have written
    /// them: appends extend, compactions replace.
    storage: Dict(String, List(String)),
    opens: Int,
  )
}

@target(javascript)
pub type Hub {
  Hub(cell: Cell(HubState))
}

@target(javascript)
pub fn new_hub() -> Hub {
  Hub(
    cell: transport_js.new_cell(HubState(
      relay: crdt_relay.new_relay(),
      sockets: dict.new(),
      next_connection: 1,
      queue: [],
      up: True,
      supports: True,
      greeting: None,
      writable: True,
      write_budget: -1,
      inbound: [],
      outbound: [],
      storage: dict.new(),
      opens: 0,
    )),
  )
}

@target(javascript)
/// A driver that opens sockets onto this hub.
pub fn driver(hub: Hub) -> Driver {
  Driver(open: fn(_url, handlers: Handlers) {
    let state = get(hub)
    set(hub, HubState(..state, opens: state.opens + 1))
    case state.up {
      False -> Error("connection refused")
      True -> {
        let connection = state.next_connection
        let socket =
          Socket(
            id: connection,
            on_message: handlers.on_message,
            on_close: handlers.on_close,
            open: True,
          )
        let state = get(hub)
        set(
          hub,
          HubState(
            ..state,
            next_connection: connection + 1,
            sockets: dict.insert(state.sockets, connection, socket),
          ),
        )
        enqueue(hub, OpenClient(connection))
        Ok(Connection(
          send: fn(payload) {
            // A real socket answers whether the write reached it. This
            // one does the same: a client whose socket has gone, whose
            // writes have been frozen, or whose budget is spent is told
            // so rather than told nothing.
            let hub_state = get(hub)
            case
              live(hub, connection),
              hub_state.writable,
              hub_state.write_budget
            {
              Ok(_), True, 0 -> False
              Ok(_), True, budget -> {
                set(hub, HubState(..hub_state, write_budget: budget - 1))
                enqueue(hub, ToRelay(connection, payload))
                True
              }
              _, _, _ -> False
            }
          },
          close: fn() { drop(hub, connection, "closed by the client") },
        ))
      }
    }
  })
}

@target(javascript)
/// Run every queued frame, and everything they queue in turn, until the
/// hub is quiet.
pub fn settle(hub: Hub) -> Nil {
  drain(hub, 20_000)
}

@target(javascript)
fn drain(hub: Hub, fuel: Int) -> Nil {
  case fuel <= 0 {
    True -> panic as "relay_fake: the hub did not settle"
    False -> {
      let state = get(hub)
      case state.queue {
        [] -> Nil
        [effect, ..rest] -> {
          set(hub, HubState(..state, queue: rest))
          run(hub, effect)
          drain(hub, fuel - 1)
        }
      }
    }
  }
}

@target(javascript)
pub fn pending(hub: Hub) -> Int {
  list.length(get(hub).queue)
}

@target(javascript)
fn run(hub: Hub, effect: Effect) -> Nil {
  case effect {
    OpenClient(connection) ->
      case live(hub, connection) {
        Error(Nil) -> Nil
        Ok(_socket) -> {
          // The relay speaks first, exactly as the reference service does.
          let state = get(hub)
          let #(relay, actions) = crdt_relay.connect(state.relay, connection)
          set(hub, HubState(..get(hub), relay: relay))
          perform(hub, actions)
        }
      }
    ToRelay(connection, raw) -> {
      let state = get(hub)
      set(hub, HubState(..state, inbound: [raw, ..state.inbound]))
      case live(hub, connection) {
        Error(Nil) -> Nil
        Ok(_) -> {
          let state = get(hub)
          let #(relay, actions, _tag) =
            crdt_relay.serve(state.relay, connection, raw)
          set(hub, HubState(..get(hub), relay: relay))
          perform(hub, actions)
        }
      }
    }
    ToClient(connection, raw) ->
      case live(hub, connection) {
        Error(Nil) -> Nil
        Ok(socket) -> socket.on_message(raw)
      }
    CloseClient(connection, detail) ->
      case dict.get(get(hub).sockets, connection) {
        Error(Nil) -> Nil
        Ok(socket) -> {
          let state = get(hub)
          set(
            hub,
            HubState(..state, sockets: dict.delete(state.sockets, connection)),
          )
          let #(relay, actions) =
            crdt_relay.disconnect(get(hub).relay, connection)
          set(hub, HubState(..get(hub), relay: relay))
          perform(hub, actions)
          case socket.open {
            True -> socket.on_close(detail)
            False -> Nil
          }
        }
      }
  }
}

@target(javascript)
/// Carry out the protocol's actions the way the reference service does:
/// storage first, then sockets.
fn perform(hub: Hub, actions: List(crdt_relay.Action)) -> Nil {
  list.each(crdt_relay.render_storage(actions), fn(entry) {
    let #(room, mode, lines) = entry
    let state = get(hub)
    let existing = case dict.get(state.storage, room) {
      Ok(found) -> found
      Error(Nil) -> []
    }
    let next = case mode {
      "append" -> list.append(existing, lines)
      _ -> lines
    }
    set(hub, HubState(..state, storage: dict.insert(state.storage, room, next)))
  })
  list.each(crdt_relay.render_sockets(actions), fn(entry) {
    let #(connection, payload, close_reason) = entry
    case payload != "" {
      True -> write(hub, connection, payload)
      False -> Nil
    }
    case close_reason != "" {
      True -> drop(hub, connection, close_reason)
      False -> Nil
    }
  })
}

@target(javascript)
/// One frame from the service, with the greeting substitutions a test
/// asked for applied on the way out.
fn write(hub: Hub, connection: Int, payload: String) -> Nil {
  let state = get(hub)
  let payload = case
    string.contains(payload, "\"type\":\"connected\""),
    state.greeting,
    state.supports
  {
    True, Some(substitute), _ -> substitute
    True, None, False ->
      crdt_relay.server_to_string(crdt_relay.Connected(
        supports: False,
        envelope_bytes: crdt_relay.max_frame_bytes(),
      ))
    _, _, _ -> payload
  }
  let state = get(hub)
  set(hub, HubState(..state, outbound: [payload, ..state.outbound]))
  enqueue(hub, ToClient(connection, payload))
}

@target(javascript)
fn drop(hub: Hub, connection: Int, detail: String) -> Nil {
  enqueue(hub, CloseClient(connection, detail))
}

@target(javascript)
fn live(hub: Hub, connection: Int) -> Result(Socket, Nil) {
  case dict.get(get(hub).sockets, connection) {
    Ok(socket) if socket.open -> Ok(socket)
    _ -> Error(Nil)
  }
}

@target(javascript)
fn enqueue(hub: Hub, effect: Effect) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, queue: list.append(state.queue, [effect])))
}

@target(javascript)
fn get(hub: Hub) -> HubState {
  transport_js.get_cell(hub.cell)
}

@target(javascript)
fn set(hub: Hub, state: HubState) -> Nil {
  transport_js.set_cell(hub.cell, state)
}

// ─────────────────────────────────────────────────────────────────────────────
// Controls
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Take the service away: every open socket drops and every later
/// connection attempt is refused. The durable log survives, because a
/// process going down is not a disk going away.
pub fn stop(hub: Hub) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, up: False))
  dict.keys(state.sockets)
  |> list.sort(int.compare)
  |> list.each(fn(connection) { drop(hub, connection, "the relay went away") })
}

@target(javascript)
/// Bring the service back, replaying every room from the lines it wrote
/// before it went down — which is exactly what the reference service does
/// on start, and the only honest way to model a restart.
pub fn restart(hub: Hub) -> Nil {
  let state = get(hub)
  let relay =
    dict.fold(state.storage, crdt_relay.new_relay(), fn(relay, room, lines) {
      crdt_relay.replay(relay, room, lines)
    })
  set(
    hub,
    HubState(..state, up: True, relay: relay, sockets: dict.new(), queue: []),
  )
}

@target(javascript)
/// Bring the service back without touching its memory. A socket outage
/// rather than a process restart.
pub fn resume(hub: Hub) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, up: True, writable: True, write_budget: -1))
}

@target(javascript)
/// Put durable lines into a room before anything connects, and replay
/// them: a relay that came up on a disk somebody else wrote. The only
/// honest way to model a log that already holds an entry no client in
/// the room will ever merge.
pub fn seed(hub: Hub, room: String, lines: List(String)) -> Nil {
  let state = get(hub)
  set(
    hub,
    HubState(
      ..state,
      storage: dict.insert(state.storage, room, lines),
      relay: crdt_relay.replay(state.relay, room, lines),
    ),
  )
}

@target(javascript)
/// Whether the greeting advertises `crdt_relay_v1`.
pub fn set_capability(hub: Hub, supported: Bool) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, supports: supported))
}

@target(javascript)
/// Whether a client's writes reach the service. `False` is a socket that
/// has left `OPEN` with no close delivered yet: every `send` fails and
/// nothing else changes.
pub fn set_writable(hub: Hub, writable: Bool) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, writable: writable))
}

@target(javascript)
/// Accept exactly `writes` more frames from clients, and fail every one
/// after that. Negative is unlimited, which is the default.
///
/// The seam for "the third write of the attachment is the one that does
/// not arrive": a socket does not stop being writable at a moment a test
/// can name any other way.
pub fn set_write_budget(hub: Hub, writes: Int) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, write_budget: writes))
}

@target(javascript)
/// Replace the greeting with an arbitrary string, for the malformed and
/// out-of-order handshake cases.
pub fn set_greeting(hub: Hub, greeting: Option(String)) -> Nil {
  let state = get(hub)
  set(hub, HubState(..state, greeting: greeting))
}

@target(javascript)
/// Write a raw frame to a client, bypassing the protocol entirely.
pub fn inject(hub: Hub, connection: Int, raw: String) -> Nil {
  enqueue(hub, ToClient(connection, raw))
}

@target(javascript)
/// Connection ids the hub has open, sorted.
pub fn open_sockets(hub: Hub) -> List(Int) {
  dict.keys(get(hub).sockets) |> list.sort(int.compare)
}

@target(javascript)
/// How many times a driver asked for a socket, refused attempts included.
pub fn opens(hub: Hub) -> Int {
  get(hub).opens
}

// ─────────────────────────────────────────────────────────────────────────────
// Observations
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Every raw frame a client wrote, oldest first.
pub fn inbound(hub: Hub) -> List(String) {
  list.reverse(get(hub).inbound)
}

@target(javascript)
/// Every raw frame the service wrote, oldest first.
pub fn outbound(hub: Hub) -> List(String) {
  list.reverse(get(hub).outbound)
}

@target(javascript)
/// The durable lines for a room, in the order a service would hold them.
pub fn lines(hub: Hub, room: String) -> List(String) {
  case dict.get(get(hub).storage, room) {
    Ok(found) -> found
    Error(Nil) -> []
  }
}

@target(javascript)
pub fn log_size(hub: Hub, room: String) -> Int {
  crdt_relay.log_size(get(hub).relay, room)
}

@target(javascript)
pub fn carried_orders(hub: Hub, room: String) -> List(Int) {
  crdt_relay.carried_orders(get(hub).relay, room)
}

@target(javascript)
pub fn attested(hub: Hub, room: String) -> String {
  crdt_relay.attested_digest(get(hub).relay, room)
}

@target(javascript)
/// The order of the `state` entry the room's checkpoint describes.
pub fn checkpoint_order(hub: Hub, room: String) -> Int {
  crdt_relay.checkpoint_order(get(hub).relay, room)
}

@target(javascript)
/// Every envelope a `stateRequest` would replay for a room.
pub fn replayable(hub: Hub, room: String) -> List(String) {
  crdt_relay.replayable(get(hub).relay, room)
}

@target(javascript)
pub fn next_order(hub: Hub, room: String) -> Int {
  crdt_relay.next_order(get(hub).relay, room)
}

@target(javascript)
pub fn sessions(hub: Hub, room: String) -> List(String) {
  crdt_relay.sessions(get(hub).relay, room)
}

@target(javascript)
/// Whether a connection told the relay it understands a checkpoint
/// request. Nothing is ever sent to a connection that did not.
pub fn supports_checkpoints(hub: Hub, connection: Int) -> Bool {
  crdt_relay.supports_checkpoints(get(hub).relay, connection)
}

@target(javascript)
/// How many checkpoint requests a room has sent.
pub fn checkpoint_requests(hub: Hub, room: String) -> Int {
  crdt_relay.checkpoint_requests(get(hub).relay, room)
}

@target(javascript)
/// The connections in a room with an unanswered checkpoint request.
pub fn checkpoints_pending(hub: Hub, room: String) -> List(Int) {
  crdt_relay.checkpoints_pending(get(hub).relay, room)
}
