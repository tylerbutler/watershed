//// The optional sequencer relay client: one socket, the `crdt_relay_v1`
//// handshake, and bounded reconnection.
////
//// This module carries strings. It does not know what a document is, it
//// never touches `crdt_core`, and the only thing it understands about an
//// envelope is that it is opaque and has a size limit. What arrives is
//// handed up as the exact string the sender wrote; the relay's
//// diagnostic `order` is read here and goes no further than the
//// attestation that quotes it back.
////
//// ## The driver seam
////
//// A `Driver` is the whole of the browser dependency: give it a URL and
//// three callbacks, get back something you can write strings to and
//// close. `native_driver` is a real `WebSocket`; a test supplies
//// closures, and every timing rule below then becomes a deterministic
//// assertion rather than a wait. The same shape, and the same reason, as
//// the transport's `Signaling`.
////
//// ## Generations
////
//// Every connection attempt takes a generation number, and every
//// callback closes over the one that created it. A socket that errors
//// after it was replaced, a message that arrives after `close`, a
//// reconnect timer that fires after a newer socket opened — all three
//// find a stale generation and do nothing. This is the only defence that
//// works: the browser will call a dead socket's handlers, and a relay
//// that let a retired connection report a drop would tear down the one
//// that replaced it.
////
//// ## Backoff
////
//// 250 ms, 500 ms, 1 s, 2 s, then 5 s for every attempt after that. The
//// delay is scheduled through an injected `Scheduler`, so a test steps a
//// logical clock instead of sleeping. A session that reached the point
//// of being useful — the caller says so with `healthy` — resets the
//// sequence, so an hour-long connection that drops retries promptly
//// rather than at the cap it reached a week ago.
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
/// A live socket, as this module needs it: somewhere to write a string
/// and a way to hang up. Closures rather than a handle type, so a fake
/// driver needs no FFI of its own.
///
/// `send` answers whether the string was actually handed to an open
/// socket. A `False` is not a queue and not a retry — it is the caller's
/// signal that this path is gone and the other one is needed *now*.
pub type Connection {
  Connection(send: fn(String) -> Bool, close: fn() -> Nil)
}

@target(javascript)
/// What a driver reports. `on_close` is terminal for that socket and is
/// delivered exactly once per successful `open`, whether the far end hung
/// up, the socket errored, or the transport gave up. There is no
/// `on_open`: this client writes nothing before the relay's greeting,
/// which arrives on `on_message`, so the socket opening is not an event
/// it acts on.
pub type Handlers {
  Handlers(on_message: fn(String) -> Nil, on_close: fn(String) -> Nil)
}

@target(javascript)
/// Opens sockets. An `Error` is a socket the environment refused to
/// construct at all, which is a failure this attempt rather than an
/// exception out of `start`.
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
/// A real browser `WebSocket`, read from `globalThis` at call time so a
/// bundle that never configures a sequencer pays nothing for this module.
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
/// What the owner of a relay hears. Every one of these is already
/// generation-checked: a stale socket reaches none of them.
pub type Events {
  Events(
    /// A connection attempt is starting. One per attempt, including the
    /// first, so a reconnect sequence reads as one of these per retry.
    on_connecting: fn() -> Nil,
    /// The relay greeted us and advertised `crdt_relay_v1`. The lane is
    /// usable from here.
    on_ready: fn() -> Nil,
    /// One encoded `crdt_wire.Envelope`, exactly as its author wrote it.
    ///
    /// Answers whether it was *processed*. A `False` — a refusal, a
    /// closed document — is reported to the relay as a `skip` naming
    /// that exact order, which is what lets a client that will never
    /// merge an entry stop being wedged behind it while the relay keeps
    /// the entry for whoever can. If the skip cannot be written the
    /// socket is retired, because a mark that can never move again is a
    /// lane that can never checkpoint again: an attestation quoting a
    /// higher order would be claiming to have accounted for an entry this
    /// client never merged and never reported.
    on_envelope: fn(String) -> Bool,
    /// The relay has replayed everything it holds for this room. The
    /// moment a merged local state is worth publishing.
    on_synced: fn() -> Nil,
    /// The answer to an `attest`: the digest echoed back, or `""` when
    /// the relay holds more than the state we published.
    on_attested: fn(String) -> Nil,
    /// The relay is asking for a checkpoint: publish the current merged
    /// state and attest it.
    ///
    /// Sent only to a client that declared support with
    /// `declare_support`, and only when the relay's live log has grown
    /// past the mark where it would otherwise have to start refusing
    /// traffic. It carries nothing a document could read — no order, no
    /// digest, no envelope — so answering it can never be a route from a
    /// relay's diagnostic sequence into `crdt_core`.
    on_checkpoint_requested: fn() -> Nil,
    /// The endpoint answered, but not with this lane. Terminal: no
    /// retry is scheduled, because a sequencer without the capability
    /// will not grow one by being asked again.
    on_unsupported: fn(String) -> Nil,
    /// The socket is gone. Followed by `on_retry` when a reconnect was
    /// scheduled, and by nothing when one was not.
    on_dropped: fn(String) -> Nil,
    on_retry: fn(Int) -> Nil,
    on_error: fn(P2pError) -> Nil,
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Backoff
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// How many refused orders this client keeps for diagnostics, per
/// socket. The relay holds the claims that matter; this list exists so a
/// test or an operator can see what a lane refused, and it is bounded so
/// that a room full of unreadable records cannot turn a diagnostic into
/// unbounded memory in a browser tab.
pub const max_reported_skips = 64

@target(javascript)
/// The reconnect delay for the nth consecutive failure, counting from
/// zero: 250 ms, 500 ms, 1 s, 2 s, then 5 s forever.
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
    /// Whether a dropped socket is worth another attempt. `True` until
    /// the endpoint proves it does not speak this lane at all — asking a
    /// sequencer without the capability again would get the same answer.
    retry: Bool,
    events: Events,
    connection: Option(Connection),
    /// The current attempt's number. Every callback carries the one it
    /// was created under, and anything older is ignored.
    generation: Int,
    /// Consecutive failures since the last healthy session, which is what
    /// `backoff_ms` indexes.
    attempt: Int,
    /// Cancels a pending reconnect.
    pending: Option(fn() -> Nil),
    /// Whether this generation finished the capability handshake.
    ready: Bool,
    /// The highest diagnostic order this socket has *accounted for* —
    /// processed, or reported as skipped. Quoted back in an attestation
    /// and used for nothing else: it never enters an envelope, a kernel,
    /// or a digest.
    ///
    /// Reset with every generation. A relay that restarts rebuilds its
    /// counter from its log and can hand out orders it has already used,
    /// so a number carried across a reconnect would mean nothing — and
    /// would mean it loudly, since the relay retires log entries at or
    /// below it.
    order: Int,
    /// Set when something this socket delivered was not processed *and*
    /// could not be reported as skipped. The high-water mark stops moving
    /// from there: everything after an unreported gap is something this
    /// client cannot vouch for.
    stalled: Bool,
    /// The most recent orders this socket reported as skipped, newest
    /// first, and never more than `max_reported_skips` of them.
    ///
    /// Diagnostic only — the relay keeps the authoritative list, and this
    /// one is reset with every generation. It is bounded because a
    /// diagnostic must not be the thing that runs a tab out of memory: a
    /// client attached to a room full of records it cannot read refuses
    /// one per replayed entry, and an unbounded list would grow with the
    /// room forever. `skips` counts every one of them.
    skipped: List(Int),
    /// How many refusals this socket has reported, including the ones
    /// that have aged out of `skipped`.
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
/// Build a relay lane. Opens nothing until `connect`.
///
/// A dropped socket always schedules another attempt, until `close` or an
/// endpoint that turns out not to speak this lane at all.
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
/// Begin connecting.
///
/// Separate from `start` on purpose: a driver may deliver its whole
/// conversation from inside `open` — a fake does, and so does a socket
/// that fails synchronously — and an owner that had not yet stored the
/// relay would miss every event of the first generation. Store first,
/// connect second.
pub fn connect(relay: Relay) -> Nil {
  open(relay.cell)
}

@target(javascript)
/// Begin one connection attempt under a fresh generation.
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
/// Stop for good. Idempotent, and it cancels a pending reconnect as well
/// as the live socket, so a closed relay schedules nothing more.
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
/// Report that the current session did its job, so the next drop starts
/// the backoff sequence again rather than continuing it.
pub fn healthy(relay: Relay) -> Nil {
  let state = transport_js.get_cell(relay.cell)
  transport_js.set_cell(relay.cell, State(..state, attempt: 0))
}

// ─────────────────────────────────────────────────────────────────────────────
// Writing
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Write one encoded envelope, unchanged. A relay that is not ready
/// drops it: the caller is on another path, and a queue here would
/// deliver a document's history in the wrong order after a reconnect.
///
/// `False` means the string did not reach an open socket — the lane was
/// never ready, it was closed, or the socket had gone underneath it. The
/// caller's business, and immediately: this module never retries a write.
pub fn send_envelope(relay: Relay, payload: String) -> Bool {
  write(relay, payload)
}

@target(javascript)
/// Attest a digest for the state just published, quoting the highest
/// order this client has accounted for — processed, or reported as
/// skipped. The relay answers on `on_attested`.
pub fn attest(relay: Relay, digest: String) -> Bool {
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
/// Tell the relay which optional control frames this client
/// understands.
///
/// Sent after the `hello` that admits the connection — a relay's first
/// frame must be an envelope, so this cannot come before it — and it is
/// the only reason a relay will ever send a `CheckpointRequest`. A
/// client that never calls this is treated exactly as a client built
/// before the frame existed: it is never sent one.
pub fn declare_support(relay: Relay) -> Bool {
  write(
    relay,
    crdt_relay.control_to_string(crdt_relay.Supports(checkpoint_requests: True)),
  )
}

@target(javascript)
fn write(relay: Relay, payload: String) -> Bool {
  let state = transport_js.get_cell(relay.cell)
  case state.closed, state.ready, state.connection {
    False, True, Some(connection) -> connection.send(payload)
    _, _, _ -> False
  }
}

@target(javascript)
/// Drop the current socket without retiring the lane.
///
/// For an owner that discovered the socket was gone by writing to it: the
/// generation is retired, `on_dropped` runs, and the policy's reconnect
/// is scheduled exactly as it would be for a close the driver reported.
/// A relay that is already closed, or that has no socket, is untouched.
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
/// One frame from the relay, under the generation that asked for it.
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
/// Reported to the relay as a `skip` naming the exact order, which is
/// what lets the relay carry the entry for whoever *can* merge it, keep
/// it through this client's checkpoints, and still let those checkpoints
/// land. Only once the skip is on the wire may the high-water mark move
/// past it: an entry refused in silence is an entry a later attestation
/// would claim to have accounted for without anyone having said so.
///
/// A relay that stamped no order — `0` — has given this client nothing to
/// name, so there is nothing to report and the mark freezes instead. A
/// skip that could not be *written* is a different thing entirely: the
/// socket is gone, so it is retired here rather than left looking healthy
/// with a frozen mark it can never unfreeze.
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
/// The diagnostic order, recorded and bounded below by what we have
/// already processed. It leaves this module only inside an attestation.
fn note_order(cell: Cell(State), order: Int) -> Nil {
  let state = transport_js.get_cell(cell)
  case !state.stalled && order > state.order {
    True -> transport_js.set_cell(cell, State(..state, order: order))
    False -> Nil
  }
}

@target(javascript)
/// A gap this client cannot account for. Freeze the high-water mark:
/// from here on this socket cannot honestly say it holds everything up to
/// any later order.
fn stall(cell: Cell(State)) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, stalled: True))
}

@target(javascript)
/// The endpoint is a sequencer without this lane. Reported once, and the
/// relay stops: retrying would ask the same question forever.
fn unsupported(cell: Cell(State), generation: Int) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, retry: False))
  state.events.on_unsupported(
    "the sequencer does not advertise " <> crdt_relay.capability,
  )
  hang_up(cell, generation, "capability " <> crdt_relay.capability <> " absent")
}

@target(javascript)
/// Close this generation's socket and retire it. The driver's own
/// `on_close` may or may not follow; either way `dropped` runs exactly
/// once for this generation, because the second caller finds it stale.
fn hang_up(cell: Cell(State), generation: Int, detail: String) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.connection {
    Some(connection) -> connection.close()
    None -> Nil
  }
  dropped(cell, generation, detail)
}

@target(javascript)
/// This generation's socket is gone. Advance the generation before
/// anything else, so a driver that calls back twice cannot schedule two
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
/// Arm the next attempt, if the policy wants one.
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
/// The most recent orders this socket reported as skipped, oldest first.
/// At most `max_reported_skips` of them — `skip_count` is the number
/// that were actually reported.
pub fn skipped_orders(relay: Relay) -> List(Int) {
  list.reverse(transport_js.get_cell(relay.cell).skipped)
}

@target(javascript)
/// How many refusals this socket has reported, whether or not they are
/// still in `skipped_orders`.
pub fn skip_count(relay: Relay) -> Int {
  transport_js.get_cell(relay.cell).skips
}

@target(javascript)
/// Consecutive failed attempts since the last `healthy`.
pub fn attempts(relay: Relay) -> Int {
  transport_js.get_cell(relay.cell).attempt
}

@target(javascript)
/// Whether a reconnect is armed.
pub fn is_retrying(relay: Relay) -> Bool {
  transport_js.get_cell(relay.cell).pending != None
}
