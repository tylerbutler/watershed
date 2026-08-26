//// Driver-level presence tests: real `watershed` documents over the
//// in-memory `sluice_js`, exercising both implementations end to end.
////
//// The heartbeat and TTL run on the sluice's *logical* clock via
//// `sluice_js.scheduler`, so ripple-mode expiry is a step (`advance`) rather
//// than a wait.

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import startest/expect

@target(javascript)
import watershed
@target(javascript)
import watershed/presence
@target(javascript)
import watershed/presence_js
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/transport_js

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Panel {
  Panel(name: String)
}

@target(javascript)
fn encode_panel(panel: Panel) -> json.Json {
  json.object([#("panel", json.string(panel.name))])
}

@target(javascript)
fn panel_decoder() -> decode.Decoder(Panel) {
  use name <- decode.field("panel", decode.string)
  decode.success(Panel(name))
}

@target(javascript)
fn config() -> presence.Config(Panel) {
  presence.config(encode_panel, panel_decoder())
}

@target(javascript)
/// A recorder for one client: every event, newest last, in a mutable cell.
type Log =
  transport_js.Cell(List(presence.Event(Panel)))

@target(javascript)
fn track(
  sluice: sluice_js.Sluice,
  document: watershed.Document(root),
  config: presence.Config(Panel),
  initial: Panel,
) -> #(presence_js.Handle(Panel), Log) {
  let log = transport_js.new_cell([])
  let handle =
    presence_js.start_with_scheduler(
      document: document,
      config: config,
      initial: initial,
      on_event: fn(event) {
        transport_js.set_cell(log, [event, ..transport_js.get_cell(log)])
      },
      scheduler: sluice_js.scheduler(sluice),
    )
  #(handle, log)
}

@target(javascript)
fn events(log: Log) -> List(presence.Event(Panel)) {
  list.reverse(transport_js.get_cell(log))
}

@target(javascript)
/// The roster as of the most recent event that carried one.
fn roster(log: Log) -> List(presence.PresenceEntry(Panel)) {
  list.fold(events(log), [], fn(latest, event) {
    case event {
      presence.State(entries) | presence.Changed(_, entries) -> entries
      presence.Failed(_) -> latest
    }
  })
}

@target(javascript)
fn failures(log: Log) -> List(presence.PresenceError) {
  list.filter_map(events(log), fn(event) {
    case event {
      presence.Failed(error) -> Ok(error)
      _ -> Error(Nil)
    }
  })
}

@target(javascript)
fn keys_and_panels(
  entries: List(presence.PresenceEntry(Panel)),
) -> List(#(String, String)) {
  list.map(entries, fn(entry) { #(entry.key, entry.meta.name) })
}

@target(javascript)
fn sessions(entries: List(presence.PresenceEntry(Panel))) -> List(String) {
  list.map(entries, fn(entry) { entry.session_id })
}

@target(javascript)
fn unwrap(value: Option(a), default: a) -> a {
  case value {
    Some(inner) -> inner
    None -> default
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode negotiation
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn auto_selects_server_mode_when_advertised_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-auto")
  let document = sluice_js.connect(sluice, user_id: "alice")
  let #(handle, _log) = track(sluice, document, config(), Panel("sudoku"))
  sluice_js.settle(sluice)

  presence_js.mode(handle) |> expect.to_equal(Some(presence.Server))
}

@target(javascript)
pub fn auto_falls_back_to_ripple_without_the_capability_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-fallback")
  sluice_js.disable_presence(sluice)
  let document = sluice_js.connect(sluice, user_id: "alice")
  let #(handle, _log) = track(sluice, document, config(), Panel("sudoku"))
  sluice_js.settle(sluice)

  presence_js.mode(handle) |> expect.to_equal(Some(presence.Ripple))
}

@target(javascript)
/// Forcing `Server` against a server without the lane is an error, not a quiet
/// downgrade — the caller asked for connection-backed presence and would
/// otherwise silently get heartbeat presence instead.
pub fn forced_server_mode_without_the_capability_fails_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-forced")
  sluice_js.disable_presence(sluice)
  let document = sluice_js.connect(sluice, user_id: "alice")
  let #(_handle, log) =
    track(
      sluice,
      document,
      presence.with_mode(config(), presence.Server),
      Panel("sudoku"),
    )
  sluice_js.settle(sluice)

  failures(log) |> expect.to_equal([presence.UnsupportedPresence])
}

// ─────────────────────────────────────────────────────────────────────────────
// Server mode
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The headline property: a late client learns the whole roster at once. Under
/// the old heartbeat model it would have waited out each peer's next beat.
pub fn a_late_client_receives_every_existing_session_at_once_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-late")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, _log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  // Carol arrives with the room already populated, and takes no heartbeat to
  // find out about it.
  let carol = sluice_js.connect(sluice, user_id: "carol")
  let #(_c, log_c) = track(sluice, carol, config(), Panel("board"))
  sluice_js.settle(sluice)

  let assert [presence.State(entries), ..] = events(log_c)
  keys_and_panels(entries)
  |> expect.to_equal([#("alice", "sudoku"), #("bob", "text")])
}

@target(javascript)
pub fn two_tabs_of_one_user_are_two_server_sessions_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-tabs")
  let tab_one = sluice_js.connect(sluice, user_id: "alice")
  let tab_two = sluice_js.connect(sluice, user_id: "alice")
  let #(_one, _log_one) = track(sluice, tab_one, config(), Panel("sudoku"))
  let #(_two, _log_two) = track(sluice, tab_two, config(), Panel("text"))
  sluice_js.settle(sluice)

  let watcher = sluice_js.connect(sluice, user_id: "bob")
  let #(_w, log_w) = track(sluice, watcher, config(), Panel("board"))
  sluice_js.settle(sluice)

  let assert [presence.State(entries), ..] = events(log_w)
  keys_and_panels(entries)
  |> expect.to_equal([#("alice", "sudoku"), #("alice", "text")])
  presence.by_key(entries, "alice") |> list.length |> expect.to_equal(2)
}

@target(javascript)
pub fn a_metadata_update_replaces_that_session_only_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-update")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(handle_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  presence_js.update(handle_a, Panel("board"))
  sluice_js.settle(sluice)

  keys_and_panels(roster(log_b))
  |> expect.to_equal([#("alice", "board"), #("bob", "text")])
}

@target(javascript)
/// Socket loss removes presence with no browser involvement and no TTL — the
/// property that motivates server presence in the first place.
pub fn a_disconnect_removes_that_session_for_peers_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-drop")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  sluice_js.disconnect(sluice, alice)
  sluice_js.settle(sluice)

  keys_and_panels(roster(log_b)) |> expect.to_equal([#("bob", "text")])
}

@target(javascript)
/// A reconnect mints a new session, and the rejoin carries whatever metadata is
/// current — including a change made while the socket was down.
pub fn a_reconnect_rejoins_with_the_latest_metadata_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-rejoin")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(handle_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  let before = unwrap(presence_js.local_session(handle_a), "")

  sluice_js.drop(sluice, alice)
  sluice_js.settle(sluice)
  // Metadata moves while there is no session to push it to.
  presence_js.update(handle_a, Panel("board"))
  sluice_js.rejoin(sluice, alice)
  sluice_js.settle(sluice)

  let after = unwrap(presence_js.local_session(handle_a), "")
  after |> expect.to_not_equal(before)

  keys_and_panels(roster(log_b))
  |> expect.to_equal([#("alice", "board"), #("bob", "text")])
  sessions(roster(log_b)) |> list.contains(before) |> expect.to_be_false
}

@target(javascript)
/// An update arriving after the socket is gone must not recreate a presence the
/// server has already cleaned up.
pub fn an_update_racing_a_disconnect_resurrects_nothing_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-race")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(handle_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  sluice_js.disconnect(sluice, alice)
  presence_js.update(handle_a, Panel("board"))
  sluice_js.settle(sluice)

  keys_and_panels(roster(log_b)) |> expect.to_equal([#("bob", "text")])
}

@target(javascript)
pub fn stopping_leaves_immediately_in_server_mode_test() {
  let sluice = sluice_js.start(tenant: "default", document: "presence-stop")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(handle_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))
  sluice_js.settle(sluice)

  presence_js.stop(handle_a)
  sluice_js.settle(sluice)

  keys_and_panels(roster(log_b)) |> expect.to_equal([#("bob", "text")])
}

// ─────────────────────────────────────────────────────────────────────────────
// Ripple mode
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn ripple_config() -> presence.Config(Panel) {
  presence.config(encode_panel, panel_decoder())
  |> presence.with_mode(presence.Ripple)
  |> presence.with_ripple_timing(heartbeat_ms: 2000, ttl_ms: 6500)
}

@target(javascript)
pub fn ripple_mode_announces_and_receives_peers_test() {
  let sluice = sluice_js.start(tenant: "default", document: "ripple-basic")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(_a, _log_a) = track(sluice, alice, ripple_config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, ripple_config(), Panel("text"))
  sluice_js.settle(sluice)

  keys_and_panels(roster(log_b))
  |> expect.to_equal([#("alice", "sudoku"), #("bob", "text")])
}

@target(javascript)
/// The bug the old roster had: two tabs of one user used to overwrite each
/// other, because the roster was keyed by user rather than by session.
pub fn two_tabs_of_one_user_are_two_ripple_sessions_test() {
  let sluice = sluice_js.start(tenant: "default", document: "ripple-tabs")
  let tab_one = sluice_js.connect(sluice, user_id: "alice")
  let tab_two = sluice_js.connect(sluice, user_id: "alice")
  let watcher = sluice_js.connect(sluice, user_id: "bob")
  let #(_one, _log_one) =
    track(sluice, tab_one, ripple_config(), Panel("sudoku"))
  let #(_two, _log_two) = track(sluice, tab_two, ripple_config(), Panel("text"))
  let #(_w, log_w) = track(sluice, watcher, ripple_config(), Panel("board"))
  sluice_js.settle(sluice)

  let entries = presence.by_key(roster(log_w), "alice")
  list.length(entries) |> expect.to_equal(2)
  keys_and_panels(entries)
  |> expect.to_equal([#("alice", "sudoku"), #("alice", "text")])
}

@target(javascript)
/// Two sessions under one key expire independently: silence one tab and the
/// other survives. Driven by the logical clock, so nothing waits.
pub fn ripple_sessions_expire_independently_test() {
  let sluice = sluice_js.start(tenant: "default", document: "ripple-ttl")
  let tab_one = sluice_js.connect(sluice, user_id: "alice")
  let tab_two = sluice_js.connect(sluice, user_id: "alice")
  let watcher = sluice_js.connect(sluice, user_id: "bob")
  let #(one, _log_one) =
    track(sluice, tab_one, ripple_config(), Panel("sudoku"))
  let #(_two, _log_two) = track(sluice, tab_two, ripple_config(), Panel("text"))
  let #(_w, log_w) = track(sluice, watcher, ripple_config(), Panel("board"))
  sluice_js.settle(sluice)

  // One tab goes quiet; the others keep beating past the TTL.
  presence_js.stop(one)
  advance_beats(sluice, 5)

  let alice_sessions = presence.by_key(roster(log_w), "alice")
  keys_and_panels(alice_sessions) |> expect.to_equal([#("alice", "text")])
}

@target(javascript)
/// Step the logical clock one heartbeat at a time, settling the sluice between
/// each so the ripples a beat emits are delivered before the next one fires.
fn advance_beats(sluice: sluice_js.Sluice, beats: Int) -> Nil {
  case beats {
    0 -> Nil
    _ -> {
      sluice_js.advance(sluice, 2000)
      sluice_js.settle(sluice)
      advance_beats(sluice, beats - 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Independence from raw ripples
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Presence and raw ripple traffic share a transport but not a lane: an app's
/// own ripples must not reach presence, and presence must not surface on the
/// app's ripple subscriber as something it has to filter.
pub fn raw_ripples_stay_independent_of_presence_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "ripple-independent")
  let alice = sluice_js.connect(sluice, user_id: "alice")
  let bob = sluice_js.connect(sluice, user_id: "bob")
  let #(_a, _log_a) = track(sluice, alice, config(), Panel("sudoku"))
  let #(_b, log_b) = track(sluice, bob, config(), Panel("text"))

  let seen = transport_js.new_cell(0)
  watershed.subscribe_ripples(bob, fn(_ripple) {
    transport_js.set_cell(seen, transport_js.get_cell(seen) + 1)
  })
  sluice_js.settle(sluice)

  // Presence is genuinely running, so "no new events" below means the ripple
  // was ignored rather than that nothing was ever listening.
  let before = list.length(events(log_b))
  before |> expect.to_not_equal(0)

  watershed.submit_ripple(
    alice,
    ripple_type: "confetti",
    content: json.object([#("kind", json.string("confetti"))]),
  )
  sluice_js.settle(sluice)

  // The app's ripple arrived...
  transport_js.get_cell(seen) |> expect.to_equal(1)
  // ...and presence did not react to it.
  list.length(events(log_b)) |> expect.to_equal(before)
}
