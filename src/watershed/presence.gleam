//// Generic ephemeral presence — the app-agnostic state machine promoted out of
//// `examples/sudoku_lustre/src/presence.gleam`.
////
//// Presence (who's here, whose cell is selected, who is typing) is transient
//// collaboration state: it must not be sequenced, persisted, or replayed, so it
//// rides on watershed *ripples* (fire-and-forget, non-sequenced), not a DDS.
//// Liveness is derived from a heartbeat + TTL, so a peer that goes silent simply
//// expires. This module owns the roster/observe/prune/TTL logic and the ripple
//// envelope; only the payload `a` is the app's. It is target-agnostic and pure —
//// the JS driver (`watershed/presence_js`) drives it, and an erlang driver can
//// slot in later.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/string

/// The ripple `type` tag and envelope `kind` value for all presence broadcasts.
/// levee strips the ripple `type` on broadcast (Fluid compat), so we discriminate
/// inbound by the `kind` field of the content envelope; the `type` stamp is kept
/// only for forward compat. Multiple ripple uses per document coexist by `kind`.
pub const ripple_type = "presence"

/// One live peer: their user id, last announced app payload, and the wall-clock
/// time (ms) their last heartbeat arrived.
pub type Peer(a) {
  Peer(user: String, payload: a, last_seen: Int)
}

/// The roster of live peers, keyed by user id (one entry per user).
pub opaque type Peers(a) {
  Peers(entries: List(Peer(a)))
}

/// Heartbeat cadence and liveness window. Default: re-announce every 2s, expire
/// after 6.5s (~3 missed beats).
pub type Config {
  Config(heartbeat_ms: Int, ttl_ms: Int)
}

/// The default cadence used by the sudoku prototype.
pub const default_config = Config(heartbeat_ms: 2000, ttl_ms: 6500)

/// An empty roster.
pub fn new() -> Peers(a) {
  Peers([])
}

/// Record a peer's heartbeat, replacing any prior entry for that user. The
/// caller filters out its own user id.
pub fn observe(
  peers: Peers(a),
  user: String,
  payload: a,
  now: Int,
) -> Peers(a) {
  let without = list.filter(peers.entries, fn(p) { p.user != user })
  Peers([Peer(user: user, payload: payload, last_seen: now), ..without])
}

/// Drop peers whose last heartbeat is older than the TTL.
pub fn prune(peers: Peers(a), config: Config, now: Int) -> Peers(a) {
  Peers(
    list.filter(peers.entries, fn(p) { now - p.last_seen <= config.ttl_ms }),
  )
}

/// The live peers, sorted by user id for a stable render order.
pub fn roster(peers: Peers(a)) -> List(Peer(a)) {
  list.sort(peers.entries, fn(a, b) { string.compare(a.user, b.user) })
}

/// Live peers whose payload matches `predicate` (subsumes sudoku's on_cell).
pub fn find(peers: Peers(a), predicate: fn(a) -> Bool) -> List(Peer(a)) {
  peers
  |> roster
  |> list.filter(fn(p) { predicate(p.payload) })
}

/// Enclose an app payload in the presence ripple envelope (decision 1).
pub fn encode_envelope(
  user: String,
  encode: fn(a) -> Json,
  payload: a,
) -> Json {
  json.object([
    #("kind", json.string(ripple_type)),
    #("user", json.string(user)),
    #("payload", encode(payload)),
  ])
}

/// Decoder for an inbound presence envelope, yielding `#(user, payload)`. Fails
/// (Error) for a foreign `kind` or a malformed payload — ripples are unsequenced,
/// garbage-tolerant input, so callers drop failures rather than crash.
pub fn decode_envelope(decode payload: Decoder(a)) -> Decoder(#(String, a)) {
  use kind <- decode.field("kind", decode.string)
  use user <- decode.field("user", decode.string)
  // Decode payload before the kind check so `decode.failure` has a real zero of
  // type `a` for the foreign-kind case (a missing/mismatched payload already
  // fails the run on its own).
  use payload <- decode.field("payload", payload)
  case kind == ripple_type {
    True -> decode.success(#(user, payload))
    False -> decode.failure(#(user, payload), "presence envelope")
  }
}

/// A stable, high-contrast color for a user id, chosen deterministically so
/// every client renders the same peer in the same color without coordination.
pub fn color_for(user: String) -> String {
  let palette = [
    "#e6194b", "#3cb44b", "#4363d8", "#f58231", "#911eb4", "#008080", "#9a6324",
    "#e6ac00", "#46f0f0", "#f032e6",
  ]
  let index = hash(user) % list.length(palette)
  case list.drop(palette, index) {
    [color, ..] -> color
    [] -> "#888888"
  }
}

/// A short display name derived from the user id (e.g. "web-1234" -> "1234").
pub fn short_name(user: String) -> String {
  case string.split(user, "-") {
    [_, tail, ..] -> tail
    _ -> user
  }
}

fn hash(text: String) -> Int {
  text
  |> string.to_utf_codepoints
  |> list.fold(0, fn(acc, cp) { acc + string.utf_codepoint_to_int(cp) })
  |> int.absolute_value
}
