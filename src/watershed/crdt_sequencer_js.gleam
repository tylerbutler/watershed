//// The optional sequencer relay client: one socket, the `crdt_relay_v1`
//// handshake, and bounded reconnection.
////
//// This module carries strings. It does not know what a document is. It never
//// calls `crdt_core`. It knows two things about an envelope: the envelope is
//// opaque, and it has a size limit. The module passes each arrival up as the
//// exact string that the sender wrote. It reads the diagnostic `order` value
//// of the relay, and that value goes no further than the attestation that
//// quotes it back.
////
//// ## The driver seam
////
//// A `Driver` value is the whole browser dependency. Give it a URL and three
//// callbacks, and it returns a value that you can write strings to and close.
//// `native_driver` is a real `WebSocket`. A test supplies closures instead,
//// and every timing rule below then becomes a deterministic assertion, and not
//// a wait. This is the same shape as the `Signaling` type of the transport,
//// for the same reason.
////
//// ## Generations
////
//// Every connection attempt takes a generation number, and every callback
//// closes over the number that created it. Three conditions thus find a stale
//// generation and do nothing: a socket that errors after a newer socket
//// replaced it, a message that arrives after `close`, and a reconnect timer
//// that runs after a newer socket opened. This is the only defence that works.
//// The browser calls the handlers of a dead socket. A relay that let a retired
//// connection report a drop would thus close the connection that replaced it.
////
//// ## Backoff
////
//// The delays are 250 ms, 500 ms, 1 s, 2 s, and then 5 s for every attempt
//// after that. An injected `Scheduler` schedules the delay, so a test steps a
//// logical clock and does not wait. A session that became useful resets the
//// sequence, and the caller reports that condition with `healthy`. A
//// connection that ran for an hour and then dropped thus retries quickly. It
//// does not retry at the limit that it reached a week before.
////
//// JavaScript target only.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/crdt_relay
@target(javascript)
import watershed/p2p.{type P2pError}
@target(javascript)
import watershed/timer_js
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler}

// ─────────────────────────────────────────────────────────────────────────────
// The driver seam
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A live socket, in the form that this module needs: a place to write a
/// string, and a way to close the socket. The type holds closures, and not a
/// handle type, so a substitute driver needs no FFI of its own.
///
/// `send` returns whether it gave the string to an open socket. A `False`
/// result is not a queue and not a retry. It tells the caller that this path is
/// gone and that the other path is necessary *now*.
pub type Connection {
  Connection(send: fn(String) -> Bool, close: fn() -> Nil)
}

@target(javascript)
/// Why a write did not reach the relay.
///
/// `RelayClosed` and `RelayNotReady` name the two ways this module refuses a
/// write on its own: `close` ran, or the greeting of the relay has not
/// arrived yet. `SendFailed` names the one way the socket itself refused a
/// string that this module was ready to send. The caller must act on any of
/// the three immediately, because this module never retries a dropped
/// write.
pub type SendError {
  RelayClosed
  RelayNotReady
  SendFailed
}

@target(javascript)
/// What a driver reports. `on_close` is terminal for that socket, and each
/// successful `open` call gives exactly one of them. The far end can close the
/// connection, the socket can error, or the transport can stop. `on_close`
/// reports all three. There is no `on_open` callback. This client writes
/// nothing before the greeting of the relay, which arrives on `on_message`, so
/// the client does not act on the open event of the socket.
pub type Handlers {
  Handlers(on_message: fn(String) -> Nil, on_close: fn(String) -> Nil)
}

@target(javascript)
/// A value that opens sockets. An `Error` result means that the environment
/// refused to construct the socket at all. That is a failure of this attempt,
/// and not an exception out of `start`.
pub type Driver {
  Driver(open: fn(String, Handlers) -> Result(Connection, String))
}

@target(javascript)
pub type NativeSocket

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "openRelay")
fn native_open(
  url: String,
  on_message: fn(String) -> Nil,
  on_close: fn(String) -> Nil,
) -> Result(NativeSocket, String)

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "sendRelay")
fn native_send(socket: NativeSocket, payload: String) -> Bool

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "close")
fn native_close(socket: NativeSocket) -> Nil

@target(javascript)
/// A real browser `WebSocket`. The function reads it from `globalThis` at call
/// time, so a bundle that configures no sequencer pays no cost for this
/// module.
pub fn native_driver() -> Driver {
  Driver(open: fn(url, handlers) {
    case native_open(url, handlers.on_message, handlers.on_close) {
      Error(detail) -> Error(detail)
      Ok(socket) ->
        Ok(
          Connection(
            send: fn(payload) { native_send(socket, payload) },
            close: fn() { native_close(socket) },
          ),
        )
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// What the owner of a relay receives. The module already checks the generation
/// of each one. A stale socket thus reaches none of them.
pub type Events {
  Events(
    /// A connection attempt starts. There is one of these events for each
    /// attempt, and that includes the first attempt. A reconnect sequence thus
    /// gives one event for each retry.
    on_connecting: fn() -> Nil,
    /// The relay sent its greeting and announced `crdt_relay_v1`. The lane is
    /// usable from this point.
    on_ready: fn() -> Nil,
    /// One encoded `crdt_wire.Envelope` value, exactly as its author wrote
    /// it.
    ///
    /// The callback returns whether the client *processed* the envelope. A
    /// `False` result, which is a refusal or a closed document, goes to the
    /// relay as a `skip` frame that names that exact order. A client that will
    /// never merge an entry thus stops waiting behind it, and the relay keeps
    /// that entry for a client that can merge it.
    ///
    /// If the module cannot write the skip, it retires the socket. A mark that
    /// can never move again is a lane that can never checkpoint again. An
    /// attestation that quoted a higher order would claim to have accounted for
    /// an entry that this client never merged and never reported.
    on_envelope: fn(String) -> Bool,
    /// The relay replayed everything that it holds for this room. This is the
    /// moment at which the merged local state is worth a publication.
    on_synced: fn() -> Nil,
    /// The answer to an `attest` frame: the digest, echoed back, or `""` when
    /// the relay holds more than the state that this client published.
    on_attested: fn(String) -> Nil,
    /// The relay asks for a checkpoint. Publish the current merged state and
    /// attest it.
    ///
    /// The relay sends this frame only to a client that declared support with
    /// `declare_support`, and only when its live log grows past the point at
    /// which it would otherwise start to refuse traffic. The frame carries
    /// nothing that a document could read: no order, no digest, and no
    /// envelope. An answer to it thus can never carry the diagnostic sequence
    /// of a relay into `crdt_core`.
    on_checkpoint_requested: fn() -> Nil,
    /// The endpoint answered, and it does not support this lane. This event is
    /// terminal, and the module schedules no retry. A sequencer without the
    /// capability does not get one when a client asks again.
    on_unsupported: fn(String) -> Nil,
    /// The socket closed. An `on_retry` event follows when the module
    /// scheduled a reconnect, and nothing follows when it did not.
    on_dropped: fn(String) -> Nil,
    on_retry: fn(Int) -> Nil,
    on_error: fn(P2pError) -> Nil,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Backoff
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The number of refused orders that this client keeps for diagnostics, for
/// each socket. The relay holds the authoritative claims. This list exists so
/// that a test or an operator can see what a lane refused. It has a limit, so
/// that a room full of unreadable records cannot make a diagnostic use
/// unbounded memory in a browser tab.
pub const max_reported_skips = 64

@target(javascript)
/// The reconnect delay for the nth consecutive failure, counted from zero. The
/// delays are 250 ms, 500 ms, 1 s, 2 s, and then 5 s for every later
/// attempt.
pub fn backoff_ms(attempt: Int) -> Int {
  case attempt {
    0 -> 250
    1 -> 500
    2 -> 1000
    3 -> 2000
    _ -> 5000
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type State {
  State(
    url: String,
    driver: Driver,
    scheduler: Scheduler,
    /// Whether a dropped socket is worth another attempt. The value is `True`
    /// until the endpoint shows that it does not support this lane at all. To
    /// ask a sequencer without the capability again would give the same
    /// answer.
    retry: Bool,
    events: Events,
    connection: Option(Connection),
    /// The number of the current attempt. Every callback carries the number
    /// that it was created under, and the module ignores an older one.
    generation: Int,
    /// The number of consecutive failures after the last healthy session.
    /// `backoff_ms` uses this number as its index.
    attempt: Int,
    /// The function that cancels a pending reconnect.
    pending: Option(fn() -> Nil),
    /// Whether this generation finished the capability handshake.
    ready: Bool,
    /// The highest diagnostic order that this socket *accounted for*, which
    /// means that the client processed it or reported it as skipped. An
    /// attestation quotes this value back, and nothing else uses it. It never
    /// enters an envelope, a kernel, or a digest.
    ///
    /// Every generation resets this value. A relay that restarts rebuilds its
    /// counter from its log, and it can then give out an order that it already
    /// used. A number that a client carried across a reconnect would thus have
    /// no meaning, and the effect would be large, because the relay retires
    /// each log entry at that order or below it.
    order: Int,
    /// The module sets this flag when the client did not process something
    /// that this socket delivered, *and* could not report it as skipped. The
    /// high-water mark then stops. This client cannot make a claim about
    /// anything after a gap that it did not report.
    stalled: Bool,
    /// The most recent orders that this socket reported as skipped, newest
    /// first, and never more than `max_reported_skips` of them.
    ///
    /// This list is a diagnostic only. The relay keeps the authoritative list,
    /// and every generation resets this one. The list has a limit, because a
    /// diagnostic must not use all the memory of a tab. A client in a room full
    /// of records that it cannot read refuses one record for each replayed
    /// entry, and a list with no limit would thus grow with the room without an
    /// end. `skips` counts every refusal.
    skipped: List(Int),
    /// The number of refusals that this socket reported, and that number
    /// includes the refusals that the module removed from `skipped`.
    skips: Int,
    closed: Bool,
  )
}

@target(javascript)
pub opaque type Relay {
  Relay(cell: Cell(State))
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Build a relay lane. The function opens nothing until you call `connect`.
///
/// A dropped socket always schedules another attempt, until a `close` call, or
/// until an endpoint shows that it does not support this lane at all.
pub fn start(
  url url: String,
  driver driver: Driver,
  scheduler scheduler: Scheduler,
  events events: Events,
) -> Relay {
  let relay =
    Relay(
      cell: transport_js.new_cell(State(
        url: url,
        driver: driver,
        scheduler: scheduler,
        retry: True,
        events: events,
        connection: None,
        generation: 0,
        attempt: 0,
        pending: None,
        ready: False,
        order: 0,
        stalled: False,
        skipped: [],
        skips: 0,
        closed: False,
      )),
    )
  relay
}

@target(javascript)
/// Start to connect.
///
/// This function is separate from `start` on purpose. A driver can deliver its
/// whole conversation from inside `open`. A substitute driver does that, and so
/// does a socket that fails synchronously. An owner that had not stored the
/// relay yet would thus miss every event of the first generation. Store the
/// relay first, and connect second.
pub fn connect(relay: Relay) -> Nil {
  open(relay.cell)
}

@target(javascript)
/// Start one connection attempt, under a new generation.
fn open(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      let generation = state.generation + 1
      transport_js.set_cell(
        cell,
        State(
          ..state,
          generation: generation,
          connection: None,
          ready: False,
          pending: None,
          order: 0,
          stalled: False,
          skipped: [],
          skips: 0,
        ),
      )
      state.events.on_connecting()
      let announced = transport_js.get_cell(cell)
      // Reporting the attempt runs the owner's code, and an owner that
      // closed the document from inside it is owed no socket.
      case announced.closed || announced.generation != generation {
        True -> Nil
        False -> {
          let handlers =
            Handlers(
              on_message: fn(raw) { receive(cell, generation, raw) },
              on_close: fn(detail) { dropped(cell, generation, detail) },
            )
          case state.driver.open(state.url, handlers) {
            Error(detail) -> {
              emit_error(cell, p2p.SequencerUnavailable(detail))
              dropped(cell, generation, detail)
            }
            Ok(connection) -> {
              let opened = transport_js.get_cell(cell)
              // A driver that delivered its whole conversation from
              // inside `open` — a fake, or a socket that failed
              // synchronously — has already retired this generation.
              // Storing the connection now would resurrect it.
              case opened.generation == generation && !opened.closed {
                False -> connection.close()
                True ->
                  transport_js.set_cell(
                    cell,
                    State(..opened, connection: Some(connection)),
                  )
              }
            }
          }
        }
      }
    }
  }
}

@target(javascript)
/// Stop permanently. A second call has no more effect. The function cancels a
/// pending reconnect and the live socket, so a closed relay schedules
/// nothing.
pub fn close(relay: Relay) -> Nil {
  let cell = relay.cell
  let state = transport_js.get_cell(cell)
  case state.closed {
    True -> Nil
    False -> {
      transport_js.set_cell(
        cell,
        State(
          ..state,
          closed: True,
          ready: False,
          connection: None,
          pending: None,
        ),
      )
      case state.pending {
        Some(cancel) -> cancel()
        None -> Nil
      }
      case state.connection {
        Some(connection) -> connection.close()
        None -> Nil
      }
    }
  }
}

@target(javascript)
/// Report that the current session worked. The next drop thus starts the
/// backoff sequence again, and it does not continue the earlier sequence.
pub fn healthy(relay: Relay) -> Nil {
  let state = transport_js.get_cell(relay.cell)
  transport_js.set_cell(relay.cell, State(..state, attempt: 0))
}

// ─────────────────────────────────────────────────────────────────────────────
// Writing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Write one encoded envelope, without a change. A relay that is not ready
/// drops it. The caller is on another path, and a queue here would deliver the
/// history of a document in the wrong order after a reconnect.
///
/// An `Error` result means that the string did not reach an open socket. The
/// `SendError` names which of the three ways that happened. The caller must
/// act on that result immediately, because this module never writes again.
pub fn send_envelope(relay: Relay, payload: String) -> Result(Nil, SendError) {
  write(relay, payload)
}

@target(javascript)
/// Attest a digest for the state that this client published, and quote the
/// highest order that this client accounted for, which it processed or reported
/// as skipped. The relay answers on `on_attested`.
pub fn attest(relay: Relay, digest: String) -> Result(Nil, SendError) {
  let state = transport_js.get_cell(relay.cell)
  write(
    relay,
    crdt_relay.control_to_string(crdt_relay.Attest(
      digest: digest,
      up_to: state.order,
    )),
  )
}

@target(javascript)
/// Tell the relay which optional control frames this client understands.
///
/// The client sends this frame after the `hello` frame that admits the
/// connection. The first frame of a relay must be an envelope, so this frame
/// cannot come before it. This frame is the only reason for a relay to send a
/// `CheckpointRequest` frame. A client that never calls this function receives
/// the same treatment as a client that a developer built before the frame
/// existed: the relay never sends it one.
pub fn declare_support(relay: Relay) -> Result(Nil, SendError) {
  write(
    relay,
    crdt_relay.control_to_string(crdt_relay.Supports(checkpoint_requests: True)),
  )
}

@target(javascript)
fn write(relay: Relay, payload: String) -> Result(Nil, SendError) {
  let state = transport_js.get_cell(relay.cell)
  case state.closed, state.ready, state.connection {
    False, True, Some(connection) ->
      case connection.send(payload) {
        True -> Ok(Nil)
        False -> Error(SendFailed)
      }
    True, _, _ -> Error(RelayClosed)
    False, False, _ -> Error(RelayNotReady)
    False, True, None -> Error(RelayNotReady)
  }
}

@target(javascript)
/// Drop the current socket, and keep the lane.
///
/// Use this function when an owner found that the socket was gone by a write to
/// it. The module retires the generation, runs `on_dropped`, and schedules the
/// reconnect of the policy, exactly as it would for a close that the driver
/// reported. The function does not change a relay that is already closed, or a
/// relay that has no socket.
pub fn abort(relay: Relay, detail: String) -> Nil {
  let cell = relay.cell
  let state = transport_js.get_cell(cell)
  case state.closed, state.connection {
    True, _ -> Nil
    _, None -> Nil
    _, Some(_) -> hang_up(cell, state.generation, detail)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reading
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// One frame from the relay, under the generation that requested it.
fn receive(cell: Cell(State), generation: Int, raw: String) -> Nil {
  case current(cell, generation) {
    False -> Nil
    True ->
      case oversize(raw) {
        True -> {
          emit_error(
            cell,
            p2p.InvalidEnvelope(
              "sequencer",
              "relay frame of "
                <> int.to_string(byte_size(raw))
                <> " bytes exceeds the "
                <> int.to_string(crdt_relay.max_frame_bytes())
                <> " byte limit",
            ),
          )
          hang_up(cell, generation, "oversize relay frame")
        }
        False ->
          case crdt_relay.decode_server(raw) {
            Error(detail) -> {
              emit_error(cell, p2p.InvalidEnvelope("sequencer", detail))
              hang_up(cell, generation, "malformed relay frame")
            }
            Ok(frame) -> deliver(cell, generation, frame)
          }
      }
  }
}

@target(javascript)
fn deliver(
  cell: Cell(State),
  generation: Int,
  frame: crdt_relay.ServerFrame,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case frame, state.ready {
    crdt_relay.Connected(_, _), _ ->
      case crdt_relay.supports_relay(frame) {
        True -> {
          transport_js.set_cell(cell, State(..state, ready: True))
          state.events.on_ready()
        }
        False -> unsupported(cell, generation)
      }
    // Nothing but the greeting is legal before the greeting. A relay
    // that starts talking about documents before it has said what lane
    // it is has not negotiated anything, and guessing would be exactly
    // the trust this handshake exists to withhold.
    _, False -> {
      emit_error(
        cell,
        p2p.InvalidEnvelope(
          "sequencer",
          "the relay sent traffic before advertising " <> crdt_relay.capability,
        ),
      )
      hang_up(cell, generation, "relay handshake violated")
    }
    crdt_relay.Frame(order, envelope), True ->
      case state.events.on_envelope(envelope) {
        True -> note_order(cell, order)
        False -> refused(cell, generation, order)
      }
    crdt_relay.Synced(order), True -> {
      note_order(cell, order)
      state.events.on_synced()
    }
    crdt_relay.Attested(order, digest), True -> {
      note_order(cell, order)
      state.events.on_attested(digest)
    }
    // No order to note, and nothing to read out of it: the request is a
    // prompt, and the answer is made entirely of the client's own state.
    crdt_relay.CheckpointRequest, True -> state.events.on_checkpoint_requested()
    crdt_relay.Refused(reason, detail), True -> {
      emit_error(
        cell,
        p2p.SequencerUnavailable(case detail {
          "" -> reason
          _ -> reason <> ": " <> detail
        }),
      )
      hang_up(cell, generation, reason)
    }
  }
}

@target(javascript)
/// Something arrived that this document will not merge.
///
/// The module reports it to the relay as a `skip` frame that names the exact
/// order. The relay can thus keep the entry for a client that *can* merge it,
/// keep it through the checkpoints of this client, and still accept those
/// checkpoints. The high-water mark can move past that entry only after the
/// skip is on the wire. An entry that a client refuses without a report is an
/// entry that a later attestation would claim to have accounted for, and no
/// client said so.
///
/// A relay that stamped no order, which is the value `0`, gave this client
/// nothing to name. There is thus nothing to report, and the mark freezes
/// instead.
///
/// A skip that the module could not *write* is a different condition. The
/// socket is gone, so the module retires it here. It does not leave the socket
/// with the appearance of health and a frozen mark that it can never move
/// again.
fn refused(cell: Cell(State), generation: Int, order: Int) -> Nil {
  let state = transport_js.get_cell(cell)
  case order > 0 && !state.stalled {
    False -> stall(cell)
    True ->
      case state.closed, state.ready, state.connection {
        False, True, Some(connection) ->
          case
            connection.send(
              crdt_relay.control_to_string(crdt_relay.Skip(order: order)),
            )
          {
            True -> {
              let current = transport_js.get_cell(cell)
              transport_js.set_cell(
                cell,
                State(
                  ..current,
                  skipped: list.take(
                    [order, ..current.skipped],
                    max_reported_skips,
                  ),
                  skips: current.skips + 1,
                ),
              )
              note_order(cell, order)
            }
            False -> {
              stall(cell)
              hang_up(cell, generation, "the relay socket was not writable")
            }
          }
        _, _, _ -> stall(cell)
      }
  }
}

@target(javascript)
/// The diagnostic order. The module records it, and it never falls below the
/// order that the client already processed. This value leaves the module inside
/// an attestation only.
fn note_order(cell: Cell(State), order: Int) -> Nil {
  let state = transport_js.get_cell(cell)
  case !state.stalled && order > state.order {
    True -> transport_js.set_cell(cell, State(..state, order: order))
    False -> Nil
  }
}

@target(javascript)
/// A gap that this client cannot account for. Freeze the high-water mark. From
/// this point, the socket cannot correctly claim that it holds everything up to
/// a later order.
fn stall(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, stalled: True))
}

@target(javascript)
/// The endpoint is a sequencer without this lane. The module reports that one
/// time and stops the relay. A retry would ask the same question without an
/// end.
fn unsupported(cell: Cell(State), generation: Int) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, retry: False))
  state.events.on_unsupported(
    "the sequencer does not advertise " <> crdt_relay.capability,
  )
  hang_up(cell, generation, "capability " <> crdt_relay.capability <> " absent")
}

@target(javascript)
/// Close the socket of this generation and retire it. The `on_close` callback
/// of the driver can follow, or it can not follow. In both conditions `dropped`
/// runs exactly one time for this generation, because the second caller finds a
/// stale generation.
fn hang_up(cell: Cell(State), generation: Int, detail: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.connection {
    Some(connection) -> connection.close()
    None -> Nil
  }
  dropped(cell, generation, detail)
}

@target(javascript)
/// The socket of this generation closed. The function advances the generation
/// first, so a driver that calls back two times cannot schedule two
/// reconnects.
fn dropped(cell: Cell(State), generation: Int, detail: String) -> Nil {
  case current(cell, generation) {
    False -> Nil
    True -> {
      let state = transport_js.get_cell(cell)
      transport_js.set_cell(
        cell,
        State(
          ..state,
          generation: state.generation + 1,
          connection: None,
          ready: False,
          order: 0,
          stalled: False,
          skipped: [],
          skips: 0,
        ),
      )
      state.events.on_dropped(detail)
      schedule(cell)
    }
  }
}

@target(javascript)
/// Arm the next attempt, if the policy permits one.
fn schedule(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.retry {
    True, _ -> Nil
    _, False -> Nil
    False, True -> {
      let delay = backoff_ms(state.attempt)
      let generation = state.generation
      timer_js.arm(
        scheduler: state.scheduler,
        delay_ms: delay,
        action: fn() {
          let armed = transport_js.get_cell(cell)
          case armed.closed, armed.generation == generation {
            False, True -> {
              transport_js.set_cell(cell, State(..armed, pending: None))
              open(cell)
            }
            _, _ -> Nil
          }
        },
        wanted: fn() {
          let armed = transport_js.get_cell(cell)
          armed.generation == generation && !armed.closed
        },
        store: fn(cancel) {
          let armed = transport_js.get_cell(cell)
          transport_js.set_cell(
            cell,
            State(..armed, attempt: armed.attempt + 1, pending: Some(cancel)),
          )
          armed.events.on_retry(delay)
        },
      )
    }
  }
}

@target(javascript)
fn current(cell: Cell(State), generation: Int) -> Bool {
  let state = transport_js.get_cell(cell)
  !state.closed && state.generation == generation
}

@target(javascript)
fn emit_error(cell: Cell(State), error: P2pError) -> Nil {
  transport_js.get_cell(cell).events.on_error(error)
}

@target(javascript)
fn oversize(raw: String) -> Bool {
  byte_size(raw) > crdt_relay.max_frame_bytes()
}

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "byteSize")
fn byte_size(raw: String) -> Int

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostics
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Whether the capability handshake has completed on the current socket.
pub fn is_ready(relay: Relay) -> Bool {
  transport_js.get_cell(relay.cell).ready
}

@target(javascript)
pub fn is_closed(relay: Relay) -> Bool {
  transport_js.get_cell(relay.cell).closed
}

@target(javascript)
/// The highest diagnostic order processed on this lane.
pub fn last_order(relay: Relay) -> Int {
  transport_js.get_cell(relay.cell).order
}

@target(javascript)
/// The most recent orders that this socket reported as skipped, oldest first.
/// There are `max_reported_skips` of them at most. `skip_count` gives the
/// number that the socket reported.
pub fn skipped_orders(relay: Relay) -> List(Int) {
  list.reverse(transport_js.get_cell(relay.cell).skipped)
}

@target(javascript)
/// The number of refusals that this socket reported, whether or not they are
/// still in `skipped_orders`.
pub fn skip_count(relay: Relay) -> Int {
  transport_js.get_cell(relay.cell).skips
}

@target(javascript)
/// The number of consecutive failed attempts after the last `healthy` call.
pub fn attempts(relay: Relay) -> Int {
  transport_js.get_cell(relay.cell).attempt
}

@target(javascript)
/// Whether a reconnect is armed.
pub fn is_retrying(relay: Relay) -> Bool {
  transport_js.get_cell(relay.cell).pending != None
}
