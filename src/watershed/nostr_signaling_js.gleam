//// A serverless signaling adapter for `p2p_transport_js`, over public
//// Nostr relays.
////
//// An operator must deploy the reference signaling service
//// (`tools/signaling`). This adapter removes that requirement. The peers meet
//// on public Nostr relays that already run, and they use those relays as a
//// broadcast topic and nothing more. This adapter does not depend on
//// `crdt_core`, `crdt_js`, or `crdt_wire`, the same as `crdt_signaling_js`. It
//// cannot see a document, so it cannot send one out. The only payloads that it
//// carries are the closed signal sum of the transport.
////
//// The relays cannot read the traffic. The topic is a hash of the room name,
//// and a key derived from that name encrypts every frame. See
//// `nostr_signaling_ffi.mjs`. The room name is the secret of the room, the
//// same as for the reference service.
////
//// ## The gossip protocol
////
//// A public topic has no server, and thus no membership. The members must
//// therefore announce each other:
////
//// - A peer that joins broadcasts `hello`.
//// - Every member answers a `hello` with an `ack` that names the new peer. It
////   also announces the new peer to its own transport.
//// - A `signal` frame carries an offer, an answer, or a candidate, addressed
////   to one peer.
//// - A peer that leaves broadcasts `bye`, on a best-effort basis.
////
//// Every frame names its sender. Every member receives everything, and each
//// member keeps only what concerns it. The contract of the transport permits
//// a duplicate and a reordering, and that permission is what makes gossip
//// this simple sufficient. For any pair of peers, the `hello` of the new peer
//// reaches the existing member, and the `ack` of that member reaches the new
//// peer. Whichever of the two must send the offer thus learns about the
//// other.
////
//// ## The roster is a census
////
//// The transport needs exactly one `Roster` for each join, and that roster
//// must be complete at admission. A medium with no membership cannot produce
//// one. This adapter thus takes a census instead. It starts at the
//// subscription acknowledgement of the first relay, collects the `hello`
//// answers for `roster_window_ms`, and reports the set that it heard by the
//// deadline as the roster.
////
//// ponytail: a census is not a guarantee. The adapter finds a member whose
//// ack loses the race late, through the traffic of that member, which still
//// satisfies the pair contract. But a document can believe for a short time
//// that it is alone in a room that is not empty. For a CRDT document that
//// condition causes a merge, and not a loss. A room that needs an exact
//// roster must use the reference service. A longer window gives more
//// confidence and more latency.
////
//// A join that cannot take a census at all ends in `Failed`, so the wait
//// always ends. That occurs when no relay is reachable, or when no relay
//// acknowledges within `roster_timeout_ms`. The adapter *drops* traffic that
//// it cannot decode, and it does not fail. `crdt_signaling_js` differs here.
//// A public topic can carry the bytes of a stranger, and a stranger must not
//// be able to end the signaling of a room.
////
//// Signaling is one half of "nothing to deploy". NAT traversal is the other
//// half. `p2p_transport_js.public_stun_servers` works with this adapter for a
//// document with no server at all. Free public STUN covers most NAT pairs,
//// and its docstring names the one arrangement that still needs a TURN server
//// of your own: a symmetric NAT at both ends.
////
//// The application must install `nostr-tools`. It is an optional peer
//// dependency, the same as `phoenix` for the sequenced transport. A relay
//// verifies the signature of an event, so every event must have a Schnorr
//// signature. The keys are temporary, and the adapter generates them for each
//// join. The peer ids of watershed carry the identity.
////
//// JavaScript target only.

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/int
@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/set.{type Set}

@target(javascript)
import watershed/crdt_signaling
@target(javascript)
import watershed/p2p_transport_js.{
  type Signal, type SignalPayload, type Signaling, Failed, Message, PeerJoined,
  PeerLeft, Roster, Signaling,
}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
/// Public relays with a record of years of uptime, for a caller with no
/// preference. Any NIP-01 relay list works here, including a private one.
pub const default_relays = [
  "wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band",
]

@target(javascript)
/// How long the census listens after the first relay acknowledges the
/// subscription. The window gives one relay round trip for the `ack` of every
/// member. A public relay needs much less time than this.
pub const default_roster_window_ms = 1500

@target(javascript)
/// How long the relays have to acknowledge a subscription before the join
/// becomes a failure. This is the backstop for a relay that accepts a socket
/// and then sends nothing.
pub const default_roster_timeout_ms = 10_000

@target(javascript)
/// An opaque relay pool, which the FFI owns. It holds the sockets, the
/// temporary signing key, the cipher key that comes from the room name, and
/// the duplicate suppression across the relays.
pub type Pool

@target(javascript)
@external(javascript, "./nostr_signaling_ffi.mjs", "openPool")
fn native_open(
  relays: List(String),
  room: String,
  on_plaintext: fn(String) -> Nil,
  on_first_ready: fn() -> Nil,
  on_all_failed: fn(String) -> Nil,
) -> Result(Pool, String)

@target(javascript)
@external(javascript, "./nostr_signaling_ffi.mjs", "publish")
fn native_publish(pool: Pool, plaintext: String) -> Nil

@target(javascript)
@external(javascript, "./nostr_signaling_ffi.mjs", "closePool")
fn native_close(pool: Pool) -> Nil

@target(javascript)
/// The gossip vocabulary. `Forward` uses the payload codec of
/// `crdt_signaling`, because the two lanes carry the same three WebRTC
/// payloads.
type Frame {
  Hello(from: String)
  Ack(from: String, to: String)
  Bye(from: String)
  Forward(from: String, to: String, payload: SignalPayload)
}

@target(javascript)
type State {
  State(
    pool: Option(Pool),
    /// The peers that the adapter has heard from. This set is the census when
    /// the window closes.
    seen: Set(String),
    /// The census window. The first subscription acknowledgement starts it.
    window: Option(transport_js.TimerId),
    /// The deadline for that acknowledgement to arrive.
    backstop: Option(transport_js.TimerId),
    roster: Bool,
    failed: Bool,
    closed: Bool,
  )
}

@target(javascript)
/// A signaling adapter that meets the peers on `relays`, with the default
/// census window and the default backstop.
///
/// `on_failure` receives each failure that occurs after `join` returns. Those
/// failures are the loss of every relay, no acknowledgement from any relay,
/// and a crypto environment that does not work. The argument is required, and
/// not optional. An application must always know that the signaling is no
/// longer available.
pub fn nostr_signaling(
  relays relays: List(String),
  on_failure on_failure: fn(String) -> Nil,
) -> Signaling {
  nostr_signaling_with_timing(
    relays: relays,
    on_failure: on_failure,
    roster_window_ms: default_roster_window_ms,
    roster_timeout_ms: default_roster_timeout_ms,
  )
}

@target(javascript)
/// `nostr_signaling` with an explicit census window and backstop. A backstop
/// of zero or less never expires. A window of zero or less reports the roster
/// when a relay acknowledges, which is correct in a test only.
pub fn nostr_signaling_with_timing(
  relays relays: List(String),
  on_failure on_failure: fn(String) -> Nil,
  roster_window_ms roster_window_ms: Int,
  roster_timeout_ms roster_timeout_ms: Int,
) -> Signaling {
  // As in `crdt_signaling_js`: every `join` allocates a state cell of its
  // own and the pool's callbacks close over it, so a replaced join's late
  // events find only their own state. `send` and `leave` reach the
  // current join through this outer cell.
  let current = transport_js.new_cell(None)
  Signaling(
    join: fn(room, peer, on_signal) {
      let cell =
        transport_js.new_cell(State(
          pool: None,
          seen: set.new(),
          window: None,
          backstop: None,
          roster: False,
          failed: False,
          closed: False,
        ))
      case
        native_open(
          relays,
          room,
          fn(raw) { receive(cell, peer, raw, on_signal) },
          fn() { open_window(cell, roster_window_ms, on_signal) },
          fn(detail) { fail(cell, detail, on_signal, on_failure) },
        )
      {
        Error(detail) -> Error(detail)
        Ok(pool) -> {
          let state = transport_js.get_cell(cell)
          transport_js.set_cell(cell, State(..state, pool: Some(pool)))
          transport_js.set_cell(current, Some(cell))
          write(cell, Hello(from: peer))
          arm_backstop(cell, roster_timeout_ms, on_signal, on_failure)
          Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer))
        }
      }
    },
    send: fn(session, to, payload) {
      use cell <- with_current(current)
      write(
        cell,
        Forward(
          from: p2p_transport_js.session_peer_id(session),
          to: to,
          payload: payload,
        ),
      )
    },
    leave: fn(session) {
      use cell <- with_current(current)
      let state = transport_js.get_cell(cell)
      case state.closed {
        True -> Nil
        False -> {
          // Best-effort: a `bye` queued on a relay that never opened is
          // lost, and the transport retires the peer on channel liveness.
          write(cell, Bye(from: p2p_transport_js.session_peer_id(session)))
          disarm(state.window)
          disarm(state.backstop)
          transport_js.set_cell(
            cell,
            State(..state, window: None, backstop: None, closed: True),
          )
          case state.pool {
            Some(pool) -> native_close(pool)
            None -> Nil
          }
        }
      }
    },
  )
}

@target(javascript)
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
/// The first relay acknowledged the subscription, so the census can start.
fn open_window(
  cell: Cell(State),
  window_ms: Int,
  on_signal: fn(Signal) -> Nil,
) -> Nil {
  case window_ms > 0 {
    False -> report_roster(cell, on_signal)
    True -> {
      let timer =
        transport_js.set_timer(fn() { report_roster(cell, on_signal) }, window_ms)
      let state = transport_js.get_cell(cell)
      case state.roster || state.failed || state.closed {
        True -> transport_js.clear_timer(timer)
        False -> transport_js.set_cell(cell, State(..state, window: Some(timer)))
      }
    }
  }
}

@target(javascript)
/// Close the census. The set that the adapter heard is the one roster of this
/// join.
fn report_roster(cell: Cell(State), on_signal: fn(Signal) -> Nil) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.roster || state.failed || state.closed {
    True -> Nil
    False -> {
      disarm(state.backstop)
      transport_js.set_cell(
        cell,
        State(..state, window: None, backstop: None, roster: True),
      )
      on_signal(Roster(set.to_list(state.seen)))
    }
  }
}

@target(javascript)
fn arm_backstop(
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
                  "no relay acknowledged the subscription within "
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
      case state.roster || state.failed || state.closed {
        True -> transport_js.clear_timer(timer)
        False ->
          transport_js.set_cell(cell, State(..state, backstop: Some(timer)))
      }
    }
  }
}

@target(javascript)
fn disarm(timer: Option(transport_js.TimerId)) -> Nil {
  case timer {
    Some(timer) -> transport_js.clear_timer(timer)
    None -> Nil
  }
}

@target(javascript)
/// Report one failure to the transport and to the application, one time each.
/// The contract is the same as for `crdt_signaling_js.fail`.
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
      disarm(state.window)
      disarm(state.backstop)
      transport_js.set_cell(
        cell,
        State(..state, window: None, backstop: None, failed: True),
      )
      on_signal(Failed(detail))
      on_failure(detail)
    }
  }
}

@target(javascript)
fn write(cell: Cell(State), frame: Frame) -> Nil {
  let state = transport_js.get_cell(cell)
  case state.closed, state.pool {
    True, _ -> Nil
    _, None -> Nil
    _, Some(pool) -> native_publish(pool, encode(frame))
  }
}

@target(javascript)
/// One decrypted frame from the topic. The function drops traffic that it
/// cannot decode, a frame addressed to another peer, and the echo of a frame
/// that this member sent.
fn receive(
  cell: Cell(State),
  me: String,
  raw: String,
  on_signal: fn(Signal) -> Nil,
) -> Nil {
  case transport_js.get_cell(cell).closed {
    True -> Nil
    False ->
      case decode(raw) {
        Error(Nil) -> Nil
        Ok(frame) ->
          case sender(frame) == me {
            True -> Nil
            False -> deliver(cell, me, frame, on_signal)
          }
      }
  }
}

@target(javascript)
fn deliver(
  cell: Cell(State),
  me: String,
  frame: Frame,
  on_signal: fn(Signal) -> Nil,
) -> Nil {
  case frame {
    // A newcomer. Announce it to the transport, answer so its census
    // hears this member. Duplicates are free, so a re-`hello` (a rejoin
    // under the same id, a relay's redelivery) needs no bookkeeping.
    Hello(from) -> {
      note(cell, from)
      on_signal(PeerJoined(from))
      write(cell, Ack(from: me, to: from))
    }
    Ack(from, to) if to == me -> {
      note(cell, from)
      on_signal(PeerJoined(from))
    }
    Bye(from) -> {
      forget(cell, from)
      on_signal(PeerLeft(from))
    }
    Forward(from, to, payload) if to == me -> {
      // A member signaling us is a member: it belongs in a census still
      // open, and `Message` is discovery enough for the pair contract.
      note(cell, from)
      on_signal(Message(from: from, payload: payload))
    }
    // Addressed to someone else: everyone hears everything, each keeps
    // what is theirs.
    Ack(_, _) -> Nil
    Forward(_, _, _) -> Nil
  }
}

@target(javascript)
fn note(cell: Cell(State), peer: String) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, seen: set.insert(state.seen, peer)))
}

@target(javascript)
/// A peer that joined and then left inside the census window was a member and
/// is not a member now. The census must not add it again.
fn forget(cell: Cell(State), peer: String) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(cell, State(..state, seen: set.delete(state.seen, peer)))
}

@target(javascript)
fn sender(frame: Frame) -> String {
  case frame {
    Hello(from) -> from
    Ack(from, _) -> from
    Bye(from) -> from
    Forward(from, _, _) -> from
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The frame codec
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn encode(frame: Frame) -> String {
  let version = #("v", json.int(1))
  json.to_string(case frame {
    Hello(from) ->
      json.object([
        version,
        #("t", json.string("hello")),
        #("from", json.string(from)),
      ])
    Ack(from, to) ->
      json.object([
        version,
        #("t", json.string("ack")),
        #("from", json.string(from)),
        #("to", json.string(to)),
      ])
    Bye(from) ->
      json.object([
        version,
        #("t", json.string("bye")),
        #("from", json.string(from)),
      ])
    Forward(from, to, payload) ->
      json.object([
        version,
        #("t", json.string("signal")),
        #("from", json.string(from)),
        #("to", json.string(to)),
        #("payload", crdt_signaling.encode_payload(payload)),
      ])
  })
}

@target(javascript)
fn decode(raw: String) -> Result(Frame, Nil) {
  case json.parse(raw, frame_decoder()) {
    Ok(frame) -> Ok(frame)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
fn frame_decoder() -> decode.Decoder(Frame) {
  use version <- decode.field("v", decode.int)
  case version {
    1 -> {
      use tag <- decode.field("t", decode.string)
      use from <- decode.field("from", decode.string)
      case tag {
        "hello" -> decode.success(Hello(from))
        "ack" -> {
          use to <- decode.field("to", decode.string)
          decode.success(Ack(from, to))
        }
        "bye" -> decode.success(Bye(from))
        "signal" -> {
          use to <- decode.field("to", decode.string)
          use payload <- decode.field(
            "payload",
            crdt_signaling.payload_decoder(),
          )
          decode.success(Forward(from, to, payload))
        }
        _ -> decode.failure(Bye(""), "nostr signaling frame")
      }
    }
    _ -> decode.failure(Bye(""), "nostr signaling frame")
  }
}
