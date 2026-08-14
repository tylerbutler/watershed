//// A browser WebSocket signaling adapter for `p2p_transport_js`.
////
//// This is the client half of `crdt_signaling`: it speaks that module's
//// frame vocabulary over a native `WebSocket` and nothing else. It has no
//// dependency on `crdt_core`, `crdt_js`, or `crdt_wire` — it cannot see a
//// document, so it cannot leak one into a signaling service even by
//// accident.
////
//// `join` is synchronous and the socket is not, which is the one thing
//// worth knowing about it:
////
//// - a `WebSocket` this browser refuses to construct at all (a malformed
////   or blocked URL, a context with no `WebSocket`) fails `join`, and the
////   transport reports `SignalingFailed`;
//// - a socket that opens and then fails is reported twice over: to the
////   transport as a `Failed` signal, so a document still waiting to be
////   admitted is answered rather than left hanging, and to the
////   application's own `on_failure`, so it can say so on screen. Once
////   each, because a socket that has failed is finished;
//// - frames written before the socket opens are queued and flushed, in
////   order, when it does. Nothing is dropped and nothing is sent twice.
////
//// ## The roster
////
//// The transport's contract asks for exactly one `Roster` per join,
//// listing the whole room. This adapter's is the service's `joined`
//// frame, which arrives a round trip after `join` returned — so a
//// document connected through it holds its empty root, silently, until
//// the room is known, and only then decides whether it is alone or has
//// state to wait for. There is no moment where it announces an empty
//// document that a peer is about to fill.
////
//// A roster that never arrives is a failure like any other:
//// `roster_timeout_ms` after `join`, the wait ends with a `Failed`
//// rather than hanging on a service that accepted a socket and then said
//// nothing.
////
//// JavaScript target only.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/crdt_signaling.{type ClientFrame, type ServerFrame}
@target(javascript)
import watershed/p2p_transport_js.{
  type Signal, type Signaling, Failed, Message, PeerJoined, PeerLeft, Roster,
  Signaling,
}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
/// How long a service has to admit this peer before the join is called a
/// failure. Generous: it covers a socket handshake and one round trip,
/// not a negotiation.
pub const default_roster_timeout_ms = 10_000

@target(javascript)
/// An opaque native socket, owned by the FFI. It holds the browser
/// `WebSocket`, its listeners, and the queue of frames written before it
/// opened.
pub type NativeSocket

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "openSignaling")
fn native_open(
  url: String,
  on_message: fn(String) -> Nil,
  on_failure: fn(String) -> Nil,
) -> Result(NativeSocket, String)

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "sendSignaling")
fn native_send(socket: NativeSocket, payload: String) -> Nil

@target(javascript)
@external(javascript, "./ws_ffi.mjs", "close")
fn native_close(socket: NativeSocket) -> Nil

@target(javascript)
type State {
  State(
    socket: Option(NativeSocket),
    /// The deadline for the service's `joined` frame, cancelled the
    /// moment it arrives or the socket fails.
    deadline: Option(transport_js.TimerId),
    /// Whether the roster has been reported to the transport. One join,
    /// one roster.
    roster: Bool,
    /// Whether a failure has been reported. One socket, one failure: the
    /// first one is the one that explains the rest.
    failed: Bool,
    closed: Bool,
  )
}

@target(javascript)
/// A signaling adapter that connects to a `crdt_signaling` service at
/// `url`.
///
/// `on_failure` receives socket-level failures that happen after `join`
/// returned — an unreachable service, a socket the service closed, a
/// refusal frame naming its reason, a roster that never came. It is
/// required rather than optional: a signaling service that has gone away
/// is not something an application should be able to not notice.
///
/// One adapter drives one membership. The transport calls `join` once;
/// each `join` gets a state cell of its own, which is what lets
/// `SignalingSession` stay free of adapter internals.
pub fn websocket_signaling(
  url url: String,
  on_failure on_failure: fn(String) -> Nil,
) -> Signaling {
  websocket_signaling_with_timeout(
    url: url,
    on_failure: on_failure,
    roster_timeout_ms: default_roster_timeout_ms,
  )
}

@target(javascript)
/// `websocket_signaling` with the roster deadline chosen explicitly. A
/// non-positive timeout never expires, which is only ever right for a
/// caller that is bounding the wait itself.
pub fn websocket_signaling_with_timeout(
  url url: String,
  on_failure on_failure: fn(String) -> Nil,
  roster_timeout_ms roster_timeout_ms: Int,
) -> Signaling {
  // Every `join` allocates a state cell of its own, and the socket's
  // callbacks close over that cell — never a shared one. A dead socket
  // from a replaced join can therefore neither disarm the current join's
  // roster deadline nor mark the adapter failed and swallow the current
  // socket's own failure; its late `onclose` finds only its own state.
  // `send` and `leave` reach the current join through this outer cell.
  let current = transport_js.new_cell(None)
  Signaling(
    join: fn(room, peer, on_signal) {
      let cell =
        transport_js.new_cell(State(
          socket: None,
          deadline: None,
          roster: False,
          failed: False,
          closed: False,
        ))
      case
        native_open(
          url,
          fn(raw) { receive(cell, raw, on_signal, on_failure) },
          fn(detail) { fail(cell, detail, on_signal, on_failure) },
        )
      {
        Error(detail) -> Error(detail)
        Ok(socket) -> {
          let state = transport_js.get_cell(cell)
          transport_js.set_cell(cell, State(..state, socket: Some(socket)))
          transport_js.set_cell(current, Some(cell))
          write(cell, crdt_signaling.Join(room: room, peer: peer))
          arm(cell, roster_timeout_ms, on_signal, on_failure)
          Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer))
        }
      }
    },
    send: fn(_session, to, payload) {
      use cell <- with_current(current)
      write(cell, crdt_signaling.Signal(to: to, payload: payload))
    },
    leave: fn(_session) {
      use cell <- with_current(current)
      let state = transport_js.get_cell(cell)
      case state.closed {
        True -> Nil
        False -> {
          write(cell, crdt_signaling.Leave)
          disarm(state)
          transport_js.set_cell(
            cell,
            State(..state, deadline: None, closed: True),
          )
          case state.socket {
            Some(socket) -> native_close(socket)
            None -> Nil
          }
        }
      }
    },
  )
}

@target(javascript)
/// Run `work` against the current join's state, or do nothing before the
/// first join has stored one.
fn with_current(
  current: Cell(Option(Cell(State))),
  work: fn(Cell(State)) -> Nil,
) -> Nil {
  case transport_js.get_cell(current) {
    Some(cell) -> work(cell)
    None -> Nil
  }
}

@target(javascript)
/// Start the roster deadline. The timer reads the cell rather than
/// closing over the socket, so a join that has already been admitted —
/// or failed, or left — finds nothing to report when it fires.
fn arm(
  cell: Cell(State),
  timeout_ms: Int,
  on_signal: fn(Signal) -> Nil,
  on_failure: fn(String) -> Nil,
) -> Nil {
  case timeout_ms > 0 {
    False -> Nil
    True -> {
      let timer =
        transport_js.set_timer(
          fn() {
            case transport_js.get_cell(cell).roster {
              True -> Nil
              False ->
                fail(
                  cell,
                  "the signaling service did not admit this peer within "
                    <> int.to_string(timeout_ms)
                    <> "ms",
                  on_signal,
                  on_failure,
                )
            }
          },
          timeout_ms,
        )
      let state = transport_js.get_cell(cell)
      // A socket that failed or was admitted while the timer was being
      // created has already answered the question the timer asks.
      case state.roster || state.failed || state.closed {
        True -> transport_js.clear_timer(timer)
        False ->
          transport_js.set_cell(cell, State(..state, deadline: Some(timer)))
      }
    }
  }
}

@target(javascript)
fn disarm(state: State) -> Nil {
  case state.deadline {
    Some(timer) -> transport_js.clear_timer(timer)
    None -> Nil
  }
}

@target(javascript)
/// Report one failure, to the transport and to the application, once.
///
/// The transport half is what stops a document hanging: a `Failed` signal
/// becomes a typed `SignalingFailed`, which resolves a readiness result
/// that would otherwise never come. A connection its owner already closed
/// reports nothing — that outcome was asked for.
fn fail(
  cell: Cell(State),
  detail: String,
  on_signal: fn(Signal) -> Nil,
  on_failure: fn(String) -> Nil,
) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.failed {
    True, _ -> Nil
    _, True -> Nil
    _, False -> {
      disarm(state)
      transport_js.set_cell(cell, State(..state, deadline: None, failed: True))
      on_signal(Failed(detail))
      on_failure(detail)
    }
  }
}

@target(javascript)
fn write(cell: Cell(State), frame: ClientFrame) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.socket {
    True, _ -> Nil
    _, None -> Nil
    _, Some(socket) ->
      native_send(socket, crdt_signaling.client_to_string(frame))
  }
}

@target(javascript)
/// One frame from the service. Only the membership and routing frames
/// mean anything; a terminal refusal is a failure, and so is anything
/// undecodable — a service that has started saying things this client
/// does not understand is a service to report, not to guess at.
fn receive(
  cell: Cell(State),
  raw: String,
  on_signal: fn(Signal) -> Nil,
  on_failure: fn(String) -> Nil,
) -> Nil {
  case transport_js.get_cell(cell).closed {
    True -> Nil
    False ->
      case crdt_signaling.decode_server(raw) {
        Error(refusal) ->
          fail(
            cell,
            describe(crdt_signaling.refusal_parts(refusal)),
            on_signal,
            on_failure,
          )
        Ok(frame) -> deliver(cell, frame, on_signal, on_failure)
      }
  }
}

@target(javascript)
fn deliver(
  cell: Cell(State),
  frame: ServerFrame,
  on_signal: fn(Signal) -> Nil,
  on_failure: fn(String) -> Nil,
) -> Nil {
  case frame {
    // Admission: the room's complete membership, and the one roster this
    // join will ever produce.
    crdt_signaling.Joined(_room, _peer, peers) -> {
      let state = transport_js.get_cell(cell)
      case state.roster {
        True -> Nil
        False -> {
          disarm(state)
          transport_js.set_cell(
            cell,
            State(..state, deadline: None, roster: True),
          )
          on_signal(Roster(peers))
        }
      }
    }
    crdt_signaling.PeerJoined(peer) -> on_signal(PeerJoined(peer))
    crdt_signaling.PeerLeft(peer) -> on_signal(PeerLeft(peer))
    crdt_signaling.Forwarded(from, payload) ->
      on_signal(Message(from: from, payload: payload))
    crdt_signaling.Rejected(reason, detail) ->
      fail(cell, describe(#(reason, detail)), on_signal, on_failure)
    // One frame could not be delivered and the connection is fine: the
    // target had left. The `peerLeft` that explains it is on its way and
    // the transport retires the peer on that, so there is nothing to do
    // here and nothing to fail.
    crdt_signaling.Dropped(_reason, _detail) -> Nil
  }
}

@target(javascript)
fn describe(parts: #(String, String)) -> String {
  case parts.1 {
    "" -> parts.0
    _ -> parts.0 <> " · " <> parts.1
  }
}
