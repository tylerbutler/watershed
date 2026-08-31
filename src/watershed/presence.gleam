//// Presence — who is here, and what they are doing.
////
//// One model, two implementations. **Server mode** is the same design as the
//// presence of Beryl. The server tracks each connection, so a late joiner
//// receives the whole roster in one snapshot, and a dropped socket removes its
//// entry without any action by the browser. **Ripple mode** is the fallback
//// for a server without the presence lane. Each client announces itself on a
//// heartbeat, and it removes a peer that it stops receiving. Both modes
//// produce the same `PresenceEntry`, `Diff`, and `Event` values, so an
//// application renders one thing in both modes.
////
//// Presence is transient collaboration state. Nothing sequences it, stores it,
//// or replays it. Ripple mode uses watershed *ripples*, which are
//// fire-and-forget and do not sequence. Server mode uses a lane of its own,
//// which also never touches the operation stream.
////
//// A session is one tab, one device, or one CLI process. A key groups the
//// sessions of one authenticated user. Two tabs of one person are two entries
//// that share a key. The roster is thus keyed by session, and not by user.
////
//// This module is target-agnostic and pure. The JavaScript driver
//// (`watershed/presence_js`) drives it. An Erlang driver can be added later.

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

/// The `type` tag of the ripple and the `kind` value of the envelope, for every
/// presence broadcast. floodgate removes the `type` field of a ripple on a
/// broadcast, for compatibility with Fluid. This module thus separates the
/// inbound kinds by the `kind` field of the content envelope. It keeps the
/// `type` stamp for compatibility with a later server only. Several uses of
/// ripples in one document work together, because `kind` separates them.
pub const ripple_type = "presence"

/// The implementation that a presence handle uses.
///
/// `Auto` selects server presence when the server announces `presence_v1`, and
/// the ripple heartbeat in every other condition. `Server` never changes to the
/// fallback, because a silent downgrade would make presence look intermittently
/// broken and would report nothing. `Ripple` forces the heartbeat, for a test
/// and for a server that you know has no presence lane.
pub type Mode {
  Auto
  Server
  Ripple
}

/// The encoder and decoder for the presence metadata of an application, the
/// implementation to use, and, in ripple mode only, the heartbeat interval.
///
/// The metadata must encode to a JSON **object**. The Phoenix `metas` shape
/// puts the `phx_ref` and `client_id` fields of the server beside the fields of
/// the application, and a scalar or an array has no position for them.
pub opaque type Config(a) {
  Config(
    encode: fn(a) -> Json,
    decode: Decoder(a),
    mode: Mode,
    heartbeat_milliseconds: Int,
    ttl_milliseconds: Int,
  )
}

/// A presence configuration: a codec for the metadata of the application, in
/// `Auto` mode, with the default ripple interval. The client announces itself
/// again every 2 seconds, and it removes a peer after 6.5 seconds, which is
/// about three missed beats.
pub fn config(encode: fn(a) -> Json, decode: Decoder(a)) -> Config(a) {
  Config(
    encode: encode,
    decode: decode,
    mode: Auto,
    heartbeat_milliseconds: 2000,
    ttl_milliseconds: 6500,
  )
}

pub fn with_mode(config: Config(a), mode: Mode) -> Config(a) {
  Config(..config, mode: mode)
}

/// Replace the ripple heartbeat interval and the liveness window. Server mode
/// ignores both values. It has no heartbeat in the browser at all, because the
/// connection *is* the liveness signal.
pub fn with_ripple_timing(
  config: Config(a),
  heartbeat_milliseconds heartbeat_milliseconds: Int,
  ttl_milliseconds ttl_milliseconds: Int,
) -> Config(a) {
  Config(
    ..config,
    heartbeat_milliseconds: heartbeat_milliseconds,
    ttl_milliseconds: ttl_milliseconds,
  )
}

pub fn config_mode(config: Config(a)) -> Mode {
  config.mode
}

pub fn config_encode(config: Config(a)) -> fn(a) -> Json {
  config.encode
}

pub fn config_decoder(config: Config(a)) -> Decoder(a) {
  config.decode
}

pub fn config_heartbeat_milliseconds(config: Config(a)) -> Int {
  config.heartbeat_milliseconds
}

pub fn config_ttl_milliseconds(config: Config(a)) -> Int {
  config.ttl_milliseconds
}

// ─────────────────────────────────────────────────────────────────────────────
// Beryl-shaped presence model
//
// One model, two implementations. Server mode mirrors Beryl's `PresenceEntry`
// and Phoenix's `presence_state`/`presence_diff` wire shape; ripple mode derives
// the same values from heartbeats and a TTL. Both produce `Event(a)`, so an
// application renders one thing either way.
// ─────────────────────────────────────────────────────────────────────────────

/// The event names on the presence lane. A command from the client to the
/// server uses camel case, the same as `submitOp` and `submitSignal`. A frame
/// from the server to the client uses snake case, the same as
/// `connect_document_success`. That difference is the existing wire
/// convention. It is not an error in this module.
pub const event_join = "joinPresence"

pub const event_update = "updatePresence"

pub const event_leave = "leavePresence"

pub const event_state = "presence_state"

pub const event_diff = "presence_diff"

pub const event_error = "presence_error"

/// The meta fields that the server owns. This module removes them before the
/// decoder of the application runs. An application thus never sees them, and it
/// can never claim one.
pub const reserved_meta_fields = ["phx_ref", "phx_ref_prev", "client_id"]

/// One tracked session. This is the `PresenceEntry` type of Beryl, with
/// `meta: a` in place of its `meta: Json`.
///
/// `session_id` identifies one tab, one device, one CLI process, or one
/// instance after a reconnect. `key` groups the sessions of one authenticated
/// user. Two tabs of one user are two entries that share a `key`.
pub type PresenceEntry(a) {
  PresenceEntry(session_id: String, key: String, meta: a)
}

/// A tracked session with the wire-only `phx_ref` value, which identifies the
/// meta that joined or left. This type is never public. `phx_ref` is a record
/// of Phoenix, and not of the application.
type Tracked(a) {
  Tracked(phx_ref: String, session_id: String, key: String, meta: a)
}

/// A meta that the decoder of the application refused. This module drops the
/// entry and reports it. It does not fail the whole frame, because one
/// malformed peer must not clear the roster.
pub type Dropped {
  Dropped(key: String, session_id: String)
}

/// A change of membership. The type is opaque, because it carries a
/// `phx_ref` value.
pub opaque type Diff(a) {
  Diff(
    joins: List(Tracked(a)),
    leaves: List(Tracked(a)),
    dropped: List(Dropped),
  )
}

/// A decoded `presence_state` frame that this module has not applied yet.
pub opaque type Snapshot(a) {
  Snapshot(entries: List(Tracked(a)), dropped: List(Dropped))
}

/// The report of a presence handle. `State` replaces the whole roster.
/// `Changed` carries the change and the roster that results, so a renderer can
/// use either one.
pub type Event(a) {
  State(entries: List(PresenceEntry(a)))
  Changed(diff: Diff(a), entries: List(PresenceEntry(a)))
  Failed(error: PresenceError)
}

pub type PresenceError {
  /// The application forced `Mode.Server` against a server that does not
  /// announce `presence_v1`.
  UnsupportedPresence
  /// The server rejected a presence command.
  Rejected(code: String, message: String)
  /// The metadata of one peer failed the decoder of the application. This
  /// module dropped that entry and kept the rest of the roster.
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

/// Whether this change moves nothing. A ripple heartbeat alone produces such a
/// change.
pub fn diff_is_empty(diff: Diff(a)) -> Bool {
  diff.joins == [] && diff.leaves == []
}

/// Every session that is registered under one presence key, which is the set
/// of tabs of one user.
pub fn by_key(
  entries: List(PresenceEntry(a)),
  key: String,
) -> List(PresenceEntry(a)) {
  list.filter(entries, fn(entry) { entry.key == key })
}

/// Every session except this client. The presence state contains the local
/// session, because a server snapshot and a Phoenix diff both carry it. An
/// interface that renders the peers only thus removes it with this function.
pub fn remote_entries(
  entries: List(PresenceEntry(a)),
  local_session: String,
) -> List(PresenceEntry(a)) {
  list.filter(entries, fn(entry) { entry.session_id != local_session })
}

// ── Server-mode tracker ──────────────────────────────────────────────────────

/// The presence state of server mode, keyed by `phx_ref`.
///
/// `entries` is `None` until the first `presence_state` frame arrives. That
/// value is not a flag. It is the mechanism: a tracker that is not synchronized
/// has no place to apply a diff, so the diffs queue by the structure of the
/// type, and they do not corrupt a stale roster. A reconnect calls `reset`,
/// which returns the tracker to that state. That call is what prevents a
/// replay of a stale diff into a new session.
pub opaque type Tracker(a) {
  Tracker(entries: Option(Dict(String, Tracked(a))), pending: List(Diff(a)))
}

/// A tracker that waits for its first snapshot.
pub fn tracker() -> Tracker(a) {
  Tracker(entries: None, pending: [])
}

/// Remove everything, including the queued diffs. The function emits no event.
/// A report of an empty roster on every short socket failure would clear the
/// interface for an interval that the next snapshot closes in milliseconds.
pub fn reset(_tracker: Tracker(a)) -> Tracker(a) {
  tracker()
}

/// Whether the tracker has applied an initial snapshot.
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

/// Take an initial snapshot, then apply each diff that arrived before it. The
/// tracker ignores a snapshot that arrives while it is already synchronized. A
/// duplicate state is not a resynchronization, and to treat it as one would
/// drop the concurrent diffs.
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
/// The tracker drops a join for a `phx_ref` that is already present, and a
/// leave for one that is absent. The server can replay a change across a
/// reconnect, and to apply that change two times would count a session two
/// times. A change with nothing left after that filter produces no event.
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

/// The state of ripple mode, keyed by **session id** and not by user.
///
/// That key is the complete fix for the old roster. Two tabs of one user are
/// two sessions that share a key, and each one joins, updates, and expires on
/// its own.
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

/// A change that moves nothing. A driver can thus use one code path, whether or
/// not it has something to report.
pub fn no_change() -> Diff(a) {
  empty_diff()
}

/// Record a heartbeat from one session.
///
/// A session that this module has not seen joins. A repeat of the same metadata
/// moves `last_seen` only and reports nothing, so a heartbeat alone never
/// causes a re-render. Metadata that changed reports a leave and then a join
/// for that session. That is the same shape that server mode produces for an
/// update, and the agreement is deliberate.
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

/// Remove each session whose last heartbeat is older than the time-to-live
/// (TTL). A session exactly at the TTL stays, which is the same boundary as in
/// the old `prune` function.
pub fn expire_sessions(
  sessions: Sessions(a),
  ttl_milliseconds: Int,
  now: Int,
) -> #(Sessions(a), Diff(a)) {
  let #(kept, expired) =
    sessions.entries
    |> dict.to_list
    |> list.partition(fn(entry) {
      now - { entry.1 }.last_seen <= ttl_milliseconds
    })
  case expired {
    [] -> #(sessions, empty_diff())
    _ -> #(
      Sessions(dict.from_list(kept)),
      Diff(joins: [], leaves: list.map(expired, live_to_tracked), dropped: []),
    )
  }
}

/// Remove one session by its id. Use this function for a local stop, and for a
/// session that gets a new key after a reconnect assigns a new client id.
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

/// The payload of a `joinPresence` command or an `updatePresence` command. The
/// client never sends `key`, `session_id`, or `phx_ref`. The server derives
/// the identity from the authenticated connection, so a client cannot claim
/// another user or another session.
pub fn encode_command(encode: fn(a) -> Json, meta: a) -> Json {
  json.object([#("meta", encode(meta))])
}

/// The payload of a `leavePresence` command.
pub fn encode_leave() -> Json {
  json.object([])
}

/// Decode the Phoenix snapshot
/// `{key: {metas: [{phx_ref, client_id, ...app}]}}`.
pub fn presence_state_decoder(decode meta: Decoder(a)) -> Decoder(Snapshot(a)) {
  use groups <- decode.then(group_decoder())
  let #(entries, dropped) = tracked_from_groups(groups, meta)
  decode.success(Snapshot(entries: entries, dropped: dropped))
}

/// Decode the Phoenix change `{joins: {...}, leaves: {...}}`.
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

/// The envelope of ripple mode:
/// `{"kind": "presence", "key": ..., "meta": ...}`.
///
/// The envelope carries no session id. The receiver takes that id from the
/// server-stamped client id of the ripple, so a sender cannot select its own
/// session.
pub fn encode_ripple(key: String, encode: fn(a) -> Json, meta: a) -> Json {
  json.object([
    #("kind", json.string(ripple_type)),
    #("key", json.string(key)),
    #("meta", encode(meta)),
  ])
}

/// The decoder for an inbound ripple envelope. It gives `#(key, meta)`. It
/// fails for a foreign `kind` value and for malformed metadata. A ripple does
/// not sequence, and the lane accepts invalid input, so a caller drops a
/// failure and does not crash.
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

/// Convert the tracked sessions into the public entry list. The function
/// removes `phx_ref`, and it sorts by key and then by session id, so every
/// render uses the same stable order.
fn public_entries(tracked: List(Tracked(a))) -> List(PresenceEntry(a)) {
  tracked
  |> list.map(fn(one) {
    PresenceEntry(session_id: one.session_id, key: one.key, meta: one.meta)
  })
  |> list.sort(fn(left, right) {
    case string.compare(left.key, right.key) {
      order.Eq -> string.compare(left.session_id, right.session_id)
      order.Lt -> order.Lt
      order.Gt -> order.Gt
    }
  })
}

// ── Codec internals ──────────────────────────────────────────────────────────

/// `{key: {metas: [...]}}`, with each meta as a raw `Dynamic` value. This
/// module can thus drop one meta that it cannot decode, and keep the other
/// metas.
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

/// Separate the decoded metas into the tracked ones and the dropped ones, and
/// keep the order in which they arrived.
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

/// A stable color with high contrast for a user id. The function is
/// deterministic, so every client renders the same peer in the same color, and
/// the clients need no coordination.
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

/// A short display name from the user id. For example, `"web-1234"` gives
/// `"1234"`.
pub fn short_name(user: String) -> String {
  case string.split(user, "-") {
    [_, tail, ..] -> tail
    _ -> user
  }
}

fn hash(text: String) -> Int {
  text
  |> string.to_utf_codepoints
  |> list.fold(0, fn(acc, codepoint) {
    acc + string.utf_codepoint_to_int(codepoint)
  })
  |> int.absolute_value
}
