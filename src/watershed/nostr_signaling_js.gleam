//// A serverless signaling adapter for `p2p_transport_js`, over public
//// Nostr relays.
////
//// The reference signaling service (`tools/signaling`) is something an
//// operator must deploy. This adapter removes that requirement: peers
//// meet on already-running public Nostr relays instead, using them as
//// nothing but a broadcast topic. Like `crdt_signaling_js` it has no
//// dependency on `crdt_core`, `crdt_js`, or `crdt_wire` — it cannot see
//// a document, so it cannot leak one, and the only payloads it carries
//// are the transport's own closed signal sum.
////
//// The relays cannot read the traffic either: the topic is a hash of the
//// room name and every frame is encrypted with a key derived from it
//// (see `nostr_signaling_ffi.mjs`). The room name is the room's secret,
//// exactly as it is for the reference service.
////
//// ## The gossip protocol
////
//// A public topic has no server and therefore no membership, so the
//// members announce each other:
////
//// - a joining peer broadcasts `hello`;
//// - every member answers a `hello` with an `ack` naming the newcomer —
////   and announces the newcomer to its own transport;
//// - `signal` carries an offer, answer, or candidate, named to one peer;
//// - a leaving peer broadcasts `bye`, best-effort.
////
//// Frames name their sender, every member hears everything, and each
//// filters to what concerns it. Duplicates and reordering are free by
//// the transport's contract, which is what makes gossip this simple
//// sufficient: for any pair, the newcomer's `hello` reaches the existing
//// member and the member's `ack` reaches the newcomer, so whichever of
//// them must offer, learns of the other.
////
//// ## The roster is a census
////
//// The transport wants exactly one `Roster` per join, complete at
//// admission. A medium with no membership cannot produce that, so this
//// adapter takes a census instead: from the first relay's subscription
//// acknowledgement, `hello` answers are collected for `roster_window_ms`,
//// and the set heard by the deadline is the roster.
////
//// ponytail: a census is not a guarantee. A member whose ack loses the
//// race is discovered late — via its own traffic, which still satisfies
//// the pair contract — but a document may briefly believe it is alone in
//// a room that is not empty. For a CRDT document that is a merge, not a
//// loss. Rooms that need an exact roster keep the reference service;
//// lengthening the window buys confidence with latency.
////
//// A join that cannot even take a census — no relay reachable, none
//// acknowledging within `roster_timeout_ms` — ends in `Failed`, so the
//// wait always ends. Undecodable traffic is *dropped*, not failed,
//// unlike `crdt_signaling_js`: a public topic can carry strangers'
//// bytes, and a stranger must not be able to end a room's signaling.
////
//// Signaling is only half of "nothing to deploy": NAT traversal is the
//// other half. `p2p_transport_js.public_stun_servers` pairs with this
//// adapter for a fully serverless document — free public STUN covers
//// most NAT pairs, and its docstring names the one shape (symmetric
//// NATs on both ends) that still needs a TURN server of your own.
////
//// `nostr-tools` must be installed by the application (an optional peer
//// dependency, as `phoenix` is for the sequenced transport): relays
//// verify event signatures, so events must be Schnorr-signed. Keys are
//// throwaway, generated per join; identity lives in watershed peer ids.
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
/// Public relays with years of uptime, for callers without a preference.
/// Any NIP-01 relay list works, including a private one.
pub const default_relays = [
  "wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band",
]

@target(javascript)
/// How long the census listens after the first relay acknowledges the
/// subscription. The window is one relay round trip for every member's
/// `ack`; public relays sit well under this.
pub const default_roster_window_ms = 1500

@target(javascript)
/// How long the relays have to acknowledge a subscription before the
/// join is called a failure — the backstop for relays that accept a
/// socket and then say nothing.
pub const default_roster_timeout_ms = 10_000

@target(javascript)
/// An opaque relay pool, owned by the FFI: the sockets, the throwaway
/// signing key, the room-derived cipher key, and the cross-relay dedupe.
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
/// The gossip vocabulary. `Forward` reuses `crdt_signaling`'s payload
/// codec: both lanes carry the same three WebRTC blobs.
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
    /// Peers heard from so far; the census when the window closes.
    seen: Set(String),
    /// The census window, armed by the first subscription acknowledgement.
    window: Option(transport_js.TimerId),
    /// The deadline for that acknowledgement ever arriving.
    backstop: Option(transport_js.TimerId),
    roster: Bool,
    failed: Bool,
    closed: Bool,
  )
}

@target(javascript)
/// A signaling adapter that meets peers on `relays`, with the default
/// census window and backstop.
///
/// `on_failure` receives failures that happen after `join` returned —
/// every relay gone, no relay acknowledging, a broken crypto
/// environment. Required, not optional: signaling that has gone away is
/// not something an application should be able to not notice.
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
/// `nostr_signaling` with the census window and backstop chosen
/// explicitly. A non-positive backstop never expires; a non-positive
/// window reports the roster the moment a relay acknowledges, which is
/// only ever right in a test.
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
/// The first relay acknowledged the subscription: the census can start.
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
/// Close the census: the set heard so far is this join's one roster.
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
/// Report one failure, to the transport and to the application, once —
/// the same contract as `crdt_signaling_js.fail`.
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
/// One decrypted frame off the topic. Undecodable traffic and frames
/// addressed elsewhere are dropped without ceremony; a member's own
/// echo likewise.
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
/// A peer that joined and left inside the census window was a member and
/// is not one now; the census must not resurrect it.
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
