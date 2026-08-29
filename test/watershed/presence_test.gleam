import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import startest/expect
import watershed/presence

// A tiny app payload for the generic roster.
type Cursor {
  Cursor(cell: String)
}

fn encode_cursor(c: Cursor) -> json.Json {
  json.object([#("cell", json.string(c.cell))])
}

fn cursor_decoder() -> decode.Decoder(Cursor) {
  use cell <- decode.field("cell", decode.string)
  decode.success(Cursor(cell))
}

// ─────────────────────────────────────────────────────────────────────────────
// Beryl-shaped model
// ─────────────────────────────────────────────────────────────────────────────

/// `{key: {metas: [meta, ...]}}` — the Phoenix shape both `presence_state` and
/// the two halves of `presence_diff` use.
fn group(entries: List(#(String, List(json.Json)))) -> json.Json {
  json.object(
    list.map(entries, fn(entry) {
      #(entry.0, json.object([#("metas", json.preprocessed_array(entry.1))]))
    }),
  )
}

fn meta(phx_ref: String, client_id: String, cell: String) -> json.Json {
  json.object([
    #("phx_ref", json.string(phx_ref)),
    #("client_id", json.string(client_id)),
    #("cell", json.string(cell)),
  ])
}

fn state_of(
  entries: List(#(String, List(json.Json))),
) -> presence.Snapshot(Cursor) {
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(group(entries)),
      presence.presence_state_decoder(decode: cursor_decoder()),
    )
  snapshot
}

fn diff_of(
  joins: List(#(String, List(json.Json))),
  leaves: List(#(String, List(json.Json))),
) -> presence.Diff(Cursor) {
  let assert Ok(diff) =
    json.parse(
      json.to_string(
        json.object([#("joins", group(joins)), #("leaves", group(leaves))]),
      ),
      presence.presence_diff_decoder(decode: cursor_decoder()),
    )
  diff
}

fn synced(
  entries: List(#(String, List(json.Json))),
) -> presence.Tracker(Cursor) {
  let #(tracker, _) =
    presence.apply_state(presence.tracker(), state_of(entries))
  tracker
}

fn keys_and_sessions(
  entries: List(presence.PresenceEntry(Cursor)),
) -> List(#(String, String)) {
  list.map(entries, fn(entry) { #(entry.key, entry.session_id) })
}

pub fn presence_state_populates_the_roster_test() -> Nil {
  let #(tracker, events) =
    presence.apply_state(
      presence.tracker(),
      state_of([#("user:alice", [meta("A1", "client-17", "r2c4")])]),
    )

  events
  |> expect.to_equal([
    presence.State([
      presence.PresenceEntry(
        session_id: "client-17",
        key: "user:alice",
        meta: Cursor("r2c4"),
      ),
    ]),
  ])

  presence.is_synced(tracker)
  |> expect.to_be_true
}

pub fn reserved_fields_are_hidden_from_the_app_decoder_test() -> Nil {
  // A decoder that succeeds only when the metadata carries *nothing* but the
  // app's own field — so it fails outright if `phx_ref` or `client_id` leaks.
  let strict = {
    use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
    case dict.keys(fields) {
      ["cell"] -> decode.success(Cursor("ok"))
      other -> decode.failure(Cursor("leaked"), string.join(other, ","))
    }
  }

  let assert Ok(snapshot) =
    json.parse(
      json.to_string(
        group([#("user:alice", [meta("A1", "client-17", "r2c4")])]),
      ),
      presence.presence_state_decoder(decode: strict),
    )
  let #(_, events) = presence.apply_state(presence.tracker(), snapshot)

  events
  |> expect.to_equal([
    presence.State([
      presence.PresenceEntry(
        session_id: "client-17",
        key: "user:alice",
        meta: Cursor("ok"),
      ),
    ]),
  ])
}

pub fn diffs_before_the_initial_state_are_queued_then_applied_test() -> Nil {
  // A remote join can outrun the snapshot. It must not be lost, and it must not
  // be applied to a roster that does not exist yet.
  let #(queued, early) =
    presence.apply_diff(
      presence.tracker(),
      diff_of([#("user:bob", [meta("B1", "client-42", "r0c0")])], []),
    )

  early
  |> expect.to_equal([])

  let #(_, events) =
    presence.apply_state(
      queued,
      state_of([#("user:alice", [meta("A1", "client-17", "r2c4")])]),
    )

  let assert [presence.State(_), presence.Changed(_, entries)] = events

  keys_and_sessions(entries)
  |> expect.to_equal([#("user:alice", "client-17"), #("user:bob", "client-42")])
}

pub fn one_of_two_sessions_under_a_key_leaves_test() -> Nil {
  let tracker =
    synced([
      #("user:alice", [
        meta("A1", "client-17", "r0c0"),
        meta("A2", "client-18", "r1c1"),
      ]),
    ])

  let #(_, events) =
    presence.apply_diff(
      tracker,
      diff_of([], [#("user:alice", [meta("A1", "client-17", "r0c0")])]),
    )

  let assert [presence.Changed(diff, entries)] = events

  keys_and_sessions(presence.diff_leaves(diff))
  |> expect.to_equal([#("user:alice", "client-17")])

  keys_and_sessions(entries)
  |> expect.to_equal([#("user:alice", "client-18")])
}

pub fn duplicate_join_and_unknown_leave_are_ignored_test() -> Nil {
  let tracker = synced([#("user:alice", [meta("A1", "client-17", "r0c0")])])

  // Replaying a join we already hold, and a leave for a ref we never saw.
  let #(_, events) =
    presence.apply_diff(
      tracker,
      diff_of([#("user:alice", [meta("A1", "client-17", "r0c0")])], [
        #("user:ghost", [meta("G1", "client-99", "r0c0")]),
      ]),
    )

  events
  |> expect.to_equal([])
}

pub fn a_second_presence_state_is_ignored_until_reset_test() -> Nil {
  let tracker = synced([#("user:alice", [meta("A1", "client-17", "r0c0")])])

  let #(tracker, events) =
    presence.apply_state(
      tracker,
      state_of([#("user:bob", [meta("B1", "client-42", "r0c0")])]),
    )

  events
  |> expect.to_equal([])

  // A reconnect resets, and only then does a fresh snapshot replace the roster.
  let #(_, events) =
    presence.apply_state(
      presence.reset(tracker),
      state_of([#("user:bob", [meta("B1", "client-42", "r0c0")])]),
    )

  let assert [presence.State(entries)] = events

  keys_and_sessions(entries)
  |> expect.to_equal([#("user:bob", "client-42")])
}

pub fn a_metadata_update_is_one_leave_and_join_for_a_session_test() -> Nil {
  let tracker = synced([#("user:alice", [meta("A1", "client-17", "r0c0")])])

  let #(_, events) =
    presence.apply_diff(
      tracker,
      diff_of([#("user:alice", [meta("A2", "client-17", "r5c5")])], [
        #("user:alice", [meta("A1", "client-17", "r0c0")]),
      ]),
    )

  let assert [presence.Changed(diff, entries)] = events

  presence.diff_joins(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Cursor("r5c5")])

  entries
  |> expect.to_equal([
    presence.PresenceEntry(
      session_id: "client-17",
      key: "user:alice",
      meta: Cursor("r5c5"),
    ),
  ])
}

pub fn a_malformed_meta_drops_only_its_own_entry_test() -> Nil {
  let broken =
    json.object([
      #("phx_ref", json.string("B1")),
      #("client_id", json.string("client-42")),
      #("wrong", json.int(1)),
    ])

  let #(_, events) =
    presence.apply_state(
      presence.tracker(),
      state_of([
        #("user:alice", [meta("A1", "client-17", "r0c0")]),
        #("user:bob", [broken]),
      ]),
    )

  let assert [presence.Failed(error), presence.State(entries)] = events

  error
  |> expect.to_equal(presence.DecodeFailed("user:bob", "client-42"))

  keys_and_sessions(entries)
  |> expect.to_equal([#("user:alice", "client-17")])
}

pub fn entries_sort_by_key_then_session_test() -> Nil {
  let tracker =
    synced([
      #("user:bob", [meta("B1", "client-2", "r0c0")]),
      #("user:alice", [
        meta("A2", "client-9", "r0c0"),
        meta("A1", "client-1", "r0c0"),
      ]),
    ])

  presence.tracker_entries(tracker)
  |> keys_and_sessions
  |> expect.to_equal([
    #("user:alice", "client-1"),
    #("user:alice", "client-9"),
    #("user:bob", "client-2"),
  ])
}

pub fn by_key_and_remote_entries_filter_test() -> Nil {
  let entries =
    presence.tracker_entries(
      synced([
        #("user:alice", [
          meta("A1", "client-1", "r0c0"),
          meta("A2", "client-2", "r1c1"),
        ]),
        #("user:bob", [meta("B1", "client-3", "r2c2")]),
      ]),
    )

  presence.by_key(entries, "user:alice")
  |> keys_and_sessions
  |> expect.to_equal([#("user:alice", "client-1"), #("user:alice", "client-2")])

  presence.remote_entries(entries, "client-1")
  |> keys_and_sessions
  |> expect.to_equal([#("user:alice", "client-2"), #("user:bob", "client-3")])
}

// ── Ripple mode ──────────────────────────────────────────────────────────────

pub fn ripple_envelope_round_trips_test() -> Nil {
  let encoded =
    presence.encode_ripple("user:alice", encode_cursor, Cursor("r2c2"))
    |> json.to_string

  json.parse(encoded, presence.ripple_decoder(decode: cursor_decoder()))
  |> expect.to_equal(Ok(#("user:alice", Cursor("r2c2"))))
}

pub fn ripple_decoder_rejects_a_foreign_kind_test() -> Nil {
  let foreign =
    json.object([
      #("kind", json.string("chat")),
      #("key", json.string("user:alice")),
      #("meta", encode_cursor(Cursor("r0c0"))),
    ])
    |> json.to_string

  json.parse(foreign, presence.ripple_decoder(decode: cursor_decoder()))
  |> result.is_error
  |> expect.to_be_true
}

pub fn two_sessions_under_one_key_stay_separate_test() -> Nil {
  // The bug the old roster had: both tabs share a user, and one used to
  // overwrite the other.
  let #(sessions, _) =
    presence.observe_session(
      presence.sessions(),
      "client-1",
      "user:alice",
      Cursor("r0c0"),
      0,
    )
  let #(sessions, diff) =
    presence.observe_session(
      sessions,
      "client-2",
      "user:alice",
      Cursor("r1c1"),
      0,
    )

  keys_and_sessions(presence.diff_joins(diff))
  |> expect.to_equal([#("user:alice", "client-2")])

  presence.session_entries(sessions)
  |> keys_and_sessions
  |> expect.to_equal([#("user:alice", "client-1"), #("user:alice", "client-2")])
}

pub fn a_bare_heartbeat_reports_nothing_test() -> Nil {
  let #(sessions, _) =
    presence.observe_session(
      presence.sessions(),
      "client-1",
      "user:alice",
      Cursor("r0c0"),
      0,
    )

  let #(_, diff) =
    presence.observe_session(
      sessions,
      "client-1",
      "user:alice",
      Cursor("r0c0"),
      2000,
    )

  presence.diff_is_empty(diff)
  |> expect.to_be_true
}

pub fn changed_metadata_reports_a_leave_and_a_join_test() -> Nil {
  let #(sessions, _) =
    presence.observe_session(
      presence.sessions(),
      "client-1",
      "user:alice",
      Cursor("r0c0"),
      0,
    )

  let #(_, diff) =
    presence.observe_session(
      sessions,
      "client-1",
      "user:alice",
      Cursor("r5c5"),
      2000,
    )

  presence.diff_joins(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Cursor("r5c5")])

  presence.diff_leaves(diff)
  |> list.map(fn(entry) { entry.meta })
  |> expect.to_equal([Cursor("r0c0")])
}

pub fn sessions_expire_independently_at_the_ttl_boundary_test() -> Nil {
  let #(sessions, _) =
    presence.observe_session(
      presence.sessions(),
      "client-1",
      "user:alice",
      Cursor("a"),
      0,
    )
  let #(sessions, _) =
    presence.observe_session(
      sessions,
      "client-2",
      "user:alice",
      Cursor("b"),
      100,
    )

  // now=6600: client-1 is 6600ms stale (> 6500 ttl) and expires; client-2 is
  // 6500ms stale (== ttl) and survives.
  let #(sessions, diff) = presence.expire_sessions(sessions, 6500, 6600)

  keys_and_sessions(presence.diff_leaves(diff))
  |> expect.to_equal([#("user:alice", "client-1")])

  presence.session_entries(sessions)
  |> keys_and_sessions
  |> expect.to_equal([#("user:alice", "client-2")])
}

pub fn forgetting_an_unknown_session_reports_nothing_test() -> Nil {
  let #(_, diff) = presence.forget_session(presence.sessions(), "client-9")

  presence.diff_is_empty(diff)
  |> expect.to_be_true
}
