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

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

import watershed/wire

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

// ─────────────────────────────────────────────────────────────────────────────
// Beryl-shaped presence model
//
// One model, two implementations. Server mode mirrors Beryl's `PresenceEntry`
// and Phoenix's `presence_state`/`presence_diff` wire shape; ripple mode derives
// the same values from heartbeats and a TTL. Both produce `Event(a)`, so an
// application renders one thing either way.
// ─────────────────────────────────────────────────────────────────────────────

/// The event names on the presence lane. Client→server commands are camelCase
/// like `submitOp`/`submitSignal`; server→client frames are snake_case like
/// `connect_document_success`. That split is the existing wire convention, not
/// an inconsistency in this module.
pub const event_join = "joinPresence"

pub const event_update = "updatePresence"

pub const event_leave = "leavePresence"

pub const event_state = "presence_state"

pub const event_diff = "presence_diff"

pub const event_error = "presence_error"

/// Meta fields the server owns. They are stripped before the application's
/// decoder runs, so an app never sees them and can never claim them.
pub const reserved_meta_fields = ["phx_ref", "phx_ref_prev", "client_id"]

/// One tracked session: Beryl's `PresenceEntry` with `meta: a` in place of its
/// `meta: Json`.
///
/// `session_id` identifies one tab, device, CLI process, or reconnect
/// incarnation; `key` groups the sessions belonging to one authenticated user.
/// Two tabs from one user are two entries sharing a `key`.
pub type PresenceEntry(a) {
  PresenceEntry(session_id: String, key: String, meta: a)
}

/// A tracked session plus the wire-only `phx_ref` that identifies *which* meta
/// joined or left. Never public: `phx_ref` is Phoenix's bookkeeping, not the
/// application's.
type Tracked(a) {
  Tracked(phx_ref: String, session_id: String, key: String, meta: a)
}

/// A meta the application's decoder rejected. The entry is dropped and reported
/// rather than failing the whole frame — one malformed peer must not blank the
/// roster.
pub type Dropped {
  Dropped(key: String, session_id: String)
}

/// A membership change. Opaque because it carries `phx_ref`.
pub opaque type Diff(a) {
  Diff(
    joins: List(Tracked(a)),
    leaves: List(Tracked(a)),
    dropped: List(Dropped),
  )
}

/// A decoded `presence_state`, not yet applied.
pub opaque type Snapshot(a) {
  Snapshot(entries: List(Tracked(a)), dropped: List(Dropped))
}

/// What a presence handle reports. `State` replaces the roster wholesale;
/// `Changed` carries both the delta and the resulting roster so a renderer can
/// use either.
pub type Event(a) {
  State(entries: List(PresenceEntry(a)))
  Changed(diff: Diff(a), entries: List(PresenceEntry(a)))
  Failed(error: PresenceError)
}

pub type PresenceError {
  /// `Mode.Server` was forced against a server that does not advertise
  /// `presence_v1`.
  UnsupportedPresence
  /// The server rejected a presence command.
  Rejected(code: String, message: String)
  /// One peer's metadata failed the application decoder; that entry was
  /// dropped and the rest of the roster kept.
  DecodeFailed(key: String, session_id: String)
}

/// The sessions that joined in this change.
pub fn diff_joins(diff: Diff(a)) -> List(PresenceEntry(a)) {
  public_entries(diff.joins)
}

/// The sessions that left in this change.
pub fn diff_leaves(diff: Diff(a)) -> List(PresenceEntry(a)) {
  public_entries(diff.leaves)
}

/// Whether this change moves nothing. A bare ripple heartbeat produces one.
pub fn diff_is_empty(diff: Diff(a)) -> Bool {
  diff.joins == [] && diff.leaves == []
}

/// Every session registered under one presence key — i.e. one user's tabs.
pub fn by_key(
  entries: List(PresenceEntry(a)),
  key: String,
) -> List(PresenceEntry(a)) {
  list.filter(entries, fn(entry) { entry.key == key })
}

/// Everyone but this client. Presence state includes the local session (server
/// snapshots and Phoenix diffs both carry it), so interfaces that only render
/// peers filter it out here.
pub fn remote_entries(
  entries: List(PresenceEntry(a)),
  local_session: String,
) -> List(PresenceEntry(a)) {
  list.filter(entries, fn(entry) { entry.session_id != local_session })
}

// ── Server-mode tracker ──────────────────────────────────────────────────────

/// Server-mode presence state, keyed by `phx_ref`.
///
/// `entries` is `None` until the first `presence_state` arrives. That is not a
/// flag but the mechanism: an unsynced tracker has nowhere to apply a diff, so
/// diffs queue structurally instead of corrupting a stale roster. A reconnect
/// calls `reset`, which returns to that state and is what stops stale diffs
/// from replaying across sessions.
pub opaque type Tracker(a) {
  Tracker(entries: Option(Dict(String, Tracked(a))), pending: List(Diff(a)))
}

/// A tracker awaiting its first snapshot.
pub fn tracker() -> Tracker(a) {
  Tracker(entries: None, pending: [])
}

/// Forget everything, including queued diffs. Emits nothing: reporting an empty
/// roster on every socket blip would blank the UI for a gap the next snapshot
/// closes in milliseconds.
pub fn reset(_tracker: Tracker(a)) -> Tracker(a) {
  tracker()
}

/// Whether an initial snapshot has been applied.
pub fn is_synced(tracker: Tracker(a)) -> Bool {
  tracker.entries != None
}

/// The current roster, sorted by key then session id.
pub fn tracker_entries(tracker: Tracker(a)) -> List(PresenceEntry(a)) {
  case tracker.entries {
    None -> []
    Some(entries) -> public_entries(dict.values(entries))
  }
}

/// Adopt an initial snapshot, then drain any diffs that arrived ahead of it.
/// A snapshot arriving while already synced is ignored — duplicate states are
/// not a resync, and treating them as one would drop concurrent diffs.
pub fn apply_state(
  tracker: Tracker(a),
  snapshot: Snapshot(a),
) -> #(Tracker(a), List(Event(a))) {
  case tracker.entries {
    Some(_) -> #(tracker, [])
    None -> {
      let entries =
        snapshot.entries
        |> list.map(fn(tracked) { #(tracked.phx_ref, tracked) })
        |> dict.from_list
      let synced = Tracker(entries: Some(entries), pending: [])
      let events =
        list.append(dropped_events(snapshot.dropped), [
          State(public_entries(dict.values(entries))),
        ])
      list.fold(tracker.pending, #(synced, events), fn(acc, queued) {
        let #(current, seen) = acc
        let #(next, more) = apply_diff(current, queued)
        #(next, list.append(seen, more))
      })
    }
  }
}

/// Apply a change, or queue it when no snapshot has arrived yet.
///
/// Joins for a `phx_ref` already present and leaves for one that is absent are
/// dropped: the server may replay a change across a reconnect, and applying it
/// twice would double-count a session. A change with nothing left after that
/// filter produces no event.
pub fn apply_diff(
  tracker: Tracker(a),
  diff: Diff(a),
) -> #(Tracker(a), List(Event(a))) {
  case tracker.entries {
    None -> #(
      Tracker(..tracker, pending: list.append(tracker.pending, [diff])),
      [],
    )
    Some(entries) -> {
      let reported = dropped_events(diff.dropped)
      let leaves =
        list.filter(diff.leaves, fn(t) { dict.has_key(entries, t.phx_ref) })
      let joins =
        list.filter(diff.joins, fn(t) { !dict.has_key(entries, t.phx_ref) })
      case leaves, joins {
        [], [] -> #(tracker, reported)
        _, _ -> {
          let next =
            entries
            |> dict.drop(list.map(leaves, fn(t) { t.phx_ref }))
            |> insert_tracked(joins)
          let effective = Diff(joins: joins, leaves: leaves, dropped: [])
          #(
            Tracker(entries: Some(next), pending: []),
            list.append(reported, [
              Changed(effective, public_entries(dict.values(next))),
            ]),
          )
        }
      }
    }
  }
}

// ── Ripple-mode sessions ─────────────────────────────────────────────────────

/// Ripple-mode state, keyed by **session id** rather than by user.
///
/// That is the whole fix for the old roster: two tabs from one user are two
/// sessions sharing a key, and they join, update, and expire independently.
pub opaque type Sessions(a) {
  Sessions(entries: Dict(String, Live(a)))
}

type Live(a) {
  Live(key: String, meta: a, last_seen: Int)
}

/// An empty ripple roster.
pub fn sessions() -> Sessions(a) {
  Sessions(dict.new())
}

/// Record a heartbeat from one session.
///
/// An unseen session joins; a repeat of the same metadata moves only
/// `last_seen` and reports nothing, so a bare heartbeat never re-renders; and
/// changed metadata reports a leave and a join for that session — deliberately
/// the same shape server mode produces for an update.
pub fn observe_session(
  sessions: Sessions(a),
  session_id: String,
  key: String,
  meta: a,
  now: Int,
) -> #(Sessions(a), Diff(a)) {
  let next =
    Sessions(dict.insert(
      sessions.entries,
      session_id,
      Live(key: key, meta: meta, last_seen: now),
    ))
  let joined = Tracked(session_id, session_id, key, meta)
  case dict.get(sessions.entries, session_id) {
    Error(Nil) -> #(next, Diff(joins: [joined], leaves: [], dropped: []))
    Ok(previous) ->
      case previous.key == key && previous.meta == meta {
        True -> #(next, empty_diff())
        False -> #(
          next,
          Diff(
            joins: [joined],
            leaves: [
              Tracked(session_id, session_id, previous.key, previous.meta),
            ],
            dropped: [],
          ),
        )
      }
  }
}

/// Drop sessions whose last heartbeat is older than the TTL. A session exactly
/// at the TTL survives, matching the old `prune` boundary.
pub fn expire_sessions(
  sessions: Sessions(a),
  ttl_ms: Int,
  now: Int,
) -> #(Sessions(a), Diff(a)) {
  let #(kept, expired) =
    sessions.entries
    |> dict.to_list
    |> list.partition(fn(entry) { now - { entry.1 }.last_seen <= ttl_ms })
  case expired {
    [] -> #(sessions, empty_diff())
    _ -> #(
      Sessions(dict.from_list(kept)),
      Diff(joins: [], leaves: list.map(expired, live_to_tracked), dropped: []),
    )
  }
}

/// Remove one session by id (a local stop, or a session being re-keyed after a
/// reconnect assigns a new client id).
pub fn forget_session(
  sessions: Sessions(a),
  session_id: String,
) -> #(Sessions(a), Diff(a)) {
  case dict.get(sessions.entries, session_id) {
    Error(Nil) -> #(sessions, empty_diff())
    Ok(previous) -> #(
      Sessions(dict.delete(sessions.entries, session_id)),
      Diff(
        joins: [],
        leaves: [Tracked(session_id, session_id, previous.key, previous.meta)],
        dropped: [],
      ),
    )
  }
}

/// The current ripple roster, sorted by key then session id.
pub fn session_entries(sessions: Sessions(a)) -> List(PresenceEntry(a)) {
  sessions.entries
  |> dict.to_list
  |> list.map(live_to_tracked)
  |> public_entries
}

// ── Wire codecs ──────────────────────────────────────────────────────────────

/// `joinPresence` / `updatePresence` payload. The client never sends `key`,
/// `session_id`, or `phx_ref`: the server derives identity from the
/// authenticated connection, so a client cannot claim another user or session.
pub fn encode_command(encode: fn(a) -> Json, meta: a) -> Json {
  json.object([#("meta", encode(meta))])
}

/// `leavePresence` payload.
pub fn encode_leave() -> Json {
  json.object([])
}

/// Decode Phoenix's `{key: {metas: [{phx_ref, client_id, ...app}]}}` snapshot.
pub fn presence_state_decoder(decode meta: Decoder(a)) -> Decoder(Snapshot(a)) {
  use groups <- decode.then(group_decoder())
  let #(entries, dropped) = tracked_from_groups(groups, meta)
  decode.success(Snapshot(entries: entries, dropped: dropped))
}

/// Decode Phoenix's `{joins: {...}, leaves: {...}}` change.
pub fn presence_diff_decoder(decode meta: Decoder(a)) -> Decoder(Diff(a)) {
  use joins <- decode.optional_field("joins", dict.new(), group_decoder())
  use leaves <- decode.optional_field("leaves", dict.new(), group_decoder())
  let #(joined, join_dropped) = tracked_from_groups(joins, meta)
  let #(left, leave_dropped) = tracked_from_groups(leaves, meta)
  decode.success(Diff(
    joins: joined,
    leaves: left,
    dropped: list.append(join_dropped, leave_dropped),
  ))
}

/// Decode a `presence_error` frame.
pub fn presence_error_decoder() -> Decoder(PresenceError) {
  use code <- decode.optional_field("code", "unknown", decode.string)
  use message <- decode.optional_field("message", "", decode.string)
  decode.success(Rejected(code: code, message: message))
}

/// The ripple-mode envelope: `{"kind": "presence", "key": ..., "meta": ...}`.
///
/// No session id rides along — the receiver takes it from the ripple's
/// server-stamped client id, so a sender cannot name its own session.
pub fn encode_ripple(key: String, encode: fn(a) -> Json, meta: a) -> Json {
  json.object([
    #("kind", json.string(ripple_type)),
    #("key", json.string(key)),
    #("meta", encode(meta)),
  ])
}

/// Decoder for an inbound ripple envelope, yielding `#(key, meta)`. Fails for a
/// foreign `kind` or malformed metadata; ripples are unsequenced,
/// garbage-tolerant input, so callers drop failures rather than crash.
pub fn ripple_decoder(decode meta: Decoder(a)) -> Decoder(#(String, a)) {
  use kind <- decode.field("kind", decode.string)
  use key <- decode.field("key", decode.string)
  // Decode the metadata before the kind check so `decode.failure` has a real
  // zero of type `a` for the foreign-kind case.
  use meta <- decode.field("meta", meta)
  case kind == ripple_type {
    True -> decode.success(#(key, meta))
    False -> decode.failure(#(key, meta), "presence envelope")
  }
}

// ── Model internals ──────────────────────────────────────────────────────────

fn empty_diff() -> Diff(a) {
  Diff(joins: [], leaves: [], dropped: [])
}

fn live_to_tracked(entry: #(String, Live(a))) -> Tracked(a) {
  let #(session_id, live) = entry
  Tracked(session_id, session_id, live.key, live.meta)
}

fn dropped_events(dropped: List(Dropped)) -> List(Event(a)) {
  list.map(dropped, fn(d) { Failed(DecodeFailed(d.key, d.session_id)) })
}

fn insert_tracked(
  entries: Dict(String, Tracked(a)),
  tracked: List(Tracked(a)),
) -> Dict(String, Tracked(a)) {
  list.fold(tracked, entries, fn(acc, one) {
    dict.insert(acc, one.phx_ref, one)
  })
}

/// Project tracked sessions into the public entry list, dropping `phx_ref` and
/// sorting by key then session id so every render order is stable.
fn public_entries(tracked: List(Tracked(a))) -> List(PresenceEntry(a)) {
  tracked
  |> list.map(fn(one) {
    PresenceEntry(session_id: one.session_id, key: one.key, meta: one.meta)
  })
  |> list.sort(fn(left, right) {
    case string.compare(left.key, right.key) {
      order.Eq -> string.compare(left.session_id, right.session_id)
      other -> other
    }
  })
}

// ── Codec internals ──────────────────────────────────────────────────────────

/// `{key: {metas: [...]}}` with each meta left as raw `Dynamic`, so one
/// undecodable meta can be dropped without failing its siblings.
fn group_decoder() -> Decoder(Dict(String, List(Dynamic))) {
  decode.dict(decode.string, metas_decoder())
}

fn metas_decoder() -> Decoder(List(Dynamic)) {
  use metas <- decode.optional_field("metas", [], decode.list(decode.dynamic))
  decode.success(metas)
}

fn tracked_from_groups(
  groups: Dict(String, List(Dynamic)),
  meta: Decoder(a),
) -> #(List(Tracked(a)), List(Dropped)) {
  groups
  |> dict.to_list
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> list.flat_map(fn(group) {
    let #(key, metas) = group
    list.map(metas, fn(raw) {
      case decode.run(raw, tracked_decoder(key, meta)) {
        Ok(outcome) -> outcome
        // No `phx_ref`: the frame is not something this client can track, and
        // there is no session id to name in the report either.
        Error(_) -> Error(Dropped(key: key, session_id: ""))
      }
    })
  })
  |> split_outcomes
}

/// Split decoded metas into the tracked ones and the dropped ones, preserving
/// the order they arrived in.
fn split_outcomes(
  outcomes: List(Result(Tracked(a), Dropped)),
) -> #(List(Tracked(a)), List(Dropped)) {
  let #(tracked, dropped) =
    list.fold(outcomes, #([], []), fn(acc, outcome) {
      let #(tracked, dropped) = acc
      case outcome {
        Ok(one) -> #([one, ..tracked], dropped)
        Error(one) -> #(tracked, [one, ..dropped])
      }
    })
  #(list.reverse(tracked), list.reverse(dropped))
}

fn tracked_decoder(
  key: String,
  meta: Decoder(a),
) -> Decoder(Result(Tracked(a), Dropped)) {
  use phx_ref <- decode.field("phx_ref", decode.string)
  use session_id <- decode.optional_field("client_id", "", decode.string)
  use fields <- decode.then(decode.dict(
    decode.string,
    wire.json_value_decoder(),
  ))
  let stripped =
    fields
    |> dict.drop(reserved_meta_fields)
    |> dict.to_list
    |> json.object
    |> json.to_string
  case json.parse(stripped, meta) {
    Ok(decoded) ->
      decode.success(Ok(Tracked(phx_ref, session_id, key, decoded)))
    Error(_) -> decode.success(Error(Dropped(key: key, session_id: session_id)))
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
