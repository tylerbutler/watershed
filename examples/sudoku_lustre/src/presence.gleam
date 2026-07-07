//// Ephemeral presence for collaborative Sudoku, carried over watershed
//// *signals* — NOT any DDS. Presence (who's here, whose cell is selected, who
//// is typing) is transient collaboration state: it must not be sequenced,
//// persisted, or replayed, so signals (fire-and-forget, non-sequenced) are the
//// right primitive. Liveness is derived from a heartbeat + TTL, so a peer that
//// goes silent simply expires.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// The signal `type` tag used for all presence broadcasts.
pub const signal_type = "presence"

/// How often each client re-announces itself (ms).
pub const heartbeat_ms = 2000

/// A peer is considered gone once this long has passed with no heartbeat (ms).
/// ~3 missed heartbeats.
pub const ttl_ms = 6500

/// One peer's last announced presence.
pub type Presence {
  Presence(
    user: String,
    color: String,
    name: String,
    /// The `r{r}c{c}` key of the peer's selected cell, if any.
    cell: Option(String),
    /// Whether the peer is actively typing into their selected cell.
    editing: Bool,
  )
}

/// A live peer plus the wall-clock time (ms) its last heartbeat arrived.
pub type Peer {
  Peer(presence: Presence, last_seen: Int)
}

/// The roster of live peers, keyed by user id.
pub type Peers =
  List(#(String, Peer))

pub fn new_peers() -> Peers {
  []
}

/// Encode a presence value as the signal `content` payload.
pub fn encode(presence: Presence) -> Json {
  json.object([
    #("user", json.string(presence.user)),
    #("color", json.string(presence.color)),
    #("name", json.string(presence.name)),
    #("cell", case presence.cell {
      Some(key) -> json.string(key)
      None -> json.null()
    }),
    #("editing", json.bool(presence.editing)),
  ])
}

/// Decode an inbound signal's `Dynamic` content into a `Presence`.
pub fn decode(content: Dynamic) -> Result(Presence, Nil) {
  let decoder = {
    use user <- decode.field("user", decode.string)
    use color <- decode.field("color", decode.string)
    use name <- decode.field("name", decode.string)
    use cell <- decode.optional_field(
      "cell",
      None,
      decode.optional(decode.string),
    )
    use editing <- decode.optional_field("editing", False, decode.bool)
    decode.success(Presence(
      user: user,
      color: color,
      name: name,
      cell: cell,
      editing: editing,
    ))
  }
  case decode.run(content, decoder) {
    Ok(presence) -> Ok(presence)
    Error(_) -> Error(Nil)
  }
}

/// Record a peer's heartbeat, replacing any prior entry for that user. Our own
/// user id is filtered out by the caller.
pub fn observe(peers: Peers, presence: Presence, now: Int) -> Peers {
  let without = list.filter(peers, fn(entry) { entry.0 != presence.user })
  [#(presence.user, Peer(presence: presence, last_seen: now)), ..without]
}

/// Drop peers whose last heartbeat is older than the TTL.
pub fn prune(peers: Peers, now: Int) -> Peers {
  list.filter(peers, fn(entry) { now - { entry.1 }.last_seen <= ttl_ms })
}

/// The list of live peers (presence only), sorted by user id for stable render.
pub fn roster(peers: Peers) -> List(Presence) {
  peers
  |> list.map(fn(entry) { { entry.1 }.presence })
  |> list.sort(fn(a, b) { string.compare(a.user, b.user) })
}

/// Live peers whose selected cell matches `key` (for cursor overlays).
pub fn on_cell(peers: Peers, key: String) -> List(Presence) {
  peers
  |> roster
  |> list.filter(fn(p) { p.cell == Some(key) })
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
