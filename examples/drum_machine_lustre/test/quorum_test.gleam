//// The tempo half of the demo: a `PactMap` key that only changes once the
//// room has signed off.
////
//// **Three clients, not two.** A two-client version of every test in this
//// file passed against the broken quorum this demo was written to expose —
//// `runtime_core` used to fabricate the signoff list as `[self, author]`,
//// which is exactly the right answer when the room has two people in it and
//// silently wrong the moment it has three. Two clients cannot distinguish a
//// real roster from that hardcoding. Do not reduce these to two.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

import watershed/pact_map_kernel
import watershed/sluice_js.{type Sluice}
import watershed/transport_js
import watershed_js.{type Document, type PactMap}

const bpm_key = "bpm"

// ── Harness ──────────────────────────────────────────────────────────────────

type Room {
  Room(
    sluice: Sluice,
    docs: List(Document),
    settings: List(PactMap),
    events: List(fn() -> List(pact_map_kernel.PactMapEvent)),
  )
}

/// `n` clients sharing one settings `PactMap`, each subscribed to it.
///
/// The app reaches this state through `ensure_pact_map`, which resolves on a
/// retry timer; the sluice is synchronous, so the handle is seeded directly
/// and every assertion can read straight after a `settle`.
fn room(name: String, clients: Int) -> Room {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let docs =
    int.range(from: 0, to: clients, with: [], run: fn(acc, n) { [n, ..acc] })
    |> list.reverse
    |> list.map(fn(n) { sluice_js.connect(sluice, "user-" <> int.to_string(n)) })
  sluice_js.settle(sluice)

  let assert [first, ..] = docs
  let assert Ok(seed) = watershed_js.create_pact_map(first)
  watershed_js.set(
    watershed_js.root(first),
    "settings",
    watershed_js.pact_map_handle_of(seed),
  )
  sluice_js.settle(sluice)

  let settings =
    docs
    |> list.map(fn(doc) {
      let assert Some(value) =
        watershed_js.get(watershed_js.root(doc), "settings")
      let assert Ok(pact) = watershed_js.resolve_pact_map(doc, value)
      pact
    })
  let events = list.map(settings, recorder)
  Room(sluice: sluice, docs: docs, settings: settings, events: events)
}

/// Subscribe and return a reader for everything seen so far. The two
/// transitions this collects *are* the protocol — a client that cannot see
/// them can propose and read but never learn that a peer's proposal landed.
fn recorder(pact: PactMap) -> fn() -> List(pact_map_kernel.PactMapEvent) {
  let seen = transport_js.new_cell([])
  watershed_js.subscribe_pact_map(pact, fn(event) {
    transport_js.set_cell(seen, [event, ..transport_js.get_cell(seen)])
  })
  fn() { list.reverse(transport_js.get_cell(seen)) }
}

fn nth(items: List(a), index: Int) -> a {
  let assert [item, ..] = list.drop(items, index)
  item
}

fn settings_of(room: Room, index: Int) -> PactMap {
  nth(room.settings, index)
}

fn events_of(room: Room, index: Int) -> List(pact_map_kernel.PactMapEvent) {
  nth(room.events, index)()
}

fn propose(room: Room, from index: Int, bpm bpm: Int) -> Nil {
  watershed_js.pact_map_set(settings_of(room, index), bpm_key, json.int(bpm))
}

fn tempo(room: Room, index: Int) -> Option(Int) {
  watershed_js.pact_map_get(settings_of(room, index), bpm_key)
  |> option.map(fn(value) {
    let assert Ok(bpm) = json.parse(json.to_string(value), decode.int)
    bpm
  })
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn a_proposal_is_accepted_once_all_three_clients_sign_off_test() {
  let room = room("drum-quorum", 3)

  propose(room, from: 0, bpm: 132)
  sluice_js.settle(room.sluice)

  // Every replica agrees, and the value is live rather than pending.
  tempo(room, 0) |> should.equal(Some(132))
  tempo(room, 1) |> should.equal(Some(132))
  tempo(room, 2) |> should.equal(Some(132))
  watershed_js.pact_map_is_pending(settings_of(room, 0), bpm_key)
  |> should.be_false

  // And every replica saw both ends of the protocol, in order.
  events_of(room, 0)
  |> should.equal([
    pact_map_kernel.WentPending(bpm_key),
    pact_map_kernel.WentAccepted(bpm_key),
  ])
  events_of(room, 2)
  |> should.equal([
    pact_map_kernel.WentPending(bpm_key),
    pact_map_kernel.WentAccepted(bpm_key),
  ])
}

pub fn a_proposal_stalls_while_one_client_is_not_acknowledging_test() {
  let room = room("drum-stall", 3)

  // The third tab is backgrounded: its frames stop being delivered, so it
  // never sees the proposal and never acknowledges it.
  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, bpm: 96)
  sluice_js.settle(room.sluice)

  // Pending everywhere, and *stays* pending. This is the window a two-client
  // test cannot produce: with the old `[self, author]` quorum the proposer and
  // the author are the same client here, so it accepted instantly.
  watershed_js.pact_map_is_pending(settings_of(room, 0), bpm_key)
  |> should.be_true
  watershed_js.pact_map_is_pending(settings_of(room, 1), bpm_key)
  |> should.be_true
  tempo(room, 0) |> should.equal(None)

  // The UI's "waiting on N of M" comes from here, and it must name the client
  // that has gone quiet rather than a bare spinner.
  let assert Some(waiting) =
    watershed_js.pact_map_pending_signoffs(settings_of(room, 0), bpm_key)
  list.length(waiting) |> should.equal(1)

  // Bringing the tab back resolves it — nothing was lost, it was only waiting.
  sluice_js.resume(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)
  tempo(room, 0) |> should.equal(Some(96))
  tempo(room, 2) |> should.equal(Some(96))
}

pub fn a_stalled_proposal_drains_when_the_silent_client_leaves_test() {
  let room = room("drum-drain", 3)

  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, bpm: 108)
  sluice_js.settle(room.sluice)
  watershed_js.pact_map_is_pending(settings_of(room, 0), bpm_key)
  |> should.be_true

  // The tab is closed rather than restored. A signoff list is not a deadlock:
  // it drains as the sequenced `"leave"` removes the client it was waiting on,
  // and the tempo the survivors were promised finally lands.
  sluice_js.disconnect(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)

  tempo(room, 0) |> should.equal(Some(108))
  tempo(room, 1) |> should.equal(Some(108))
  watershed_js.pact_map_is_pending(settings_of(room, 0), bpm_key)
  |> should.be_false
  events_of(room, 1)
  |> should.equal([
    pact_map_kernel.WentPending(bpm_key),
    pact_map_kernel.WentAccepted(bpm_key),
  ])
}

pub fn a_second_proposal_while_one_is_pending_is_rejected_test() {
  let room = room("drum-collide", 3)

  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, bpm: 140)
  sluice_js.settle(room.sluice)

  // Someone else drags the slider while the first change is still in flight.
  // The kernel drops it — which is why the app disables the control rather
  // than letting a proposal disappear with nothing on screen to explain it.
  propose(room, from: 1, bpm: 90)
  sluice_js.settle(room.sluice)

  sluice_js.resume(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)

  // The first proposal wins; the second left no trace.
  tempo(room, 0) |> should.equal(Some(140))
  tempo(room, 1) |> should.equal(Some(140))
  tempo(room, 2) |> should.equal(Some(140))
  events_of(room, 1)
  |> should.equal([
    pact_map_kernel.WentPending(bpm_key),
    pact_map_kernel.WentAccepted(bpm_key),
  ])
}

/// **This test pins a bug, not a behaviour.** See
/// `docs/plans/2026-08-09-consensus-replay-quorum-plan.md`.
///
/// A client that joins after a tempo has been agreed cannot read it. It
/// replays the historical `Set`, and `runtime_core.quorum_of` builds the
/// signoff list from *its own present-day roster* rather than from the roster
/// the op was sequenced against — so the joiner writes itself into the quorum
/// of a proposal that settled before it existed. The replayed `Accept`s drain
/// the clients that really did sign off, and the joiner is left waiting on
/// itself forever.
///
/// Against a live floodgate server the same cause is louder: the joiner's
/// owed `Accept` reaches peers who settled that pact long ago, they answer
/// `UnexpectedAccept`, and the connection dies with
/// `bootstrap failed: AckMismatch("client was not expected to sign off")`.
///
/// When the fix lands, the assertions below flip to `Some(json.int(128))` /
/// `should.be_false` and this comment and the name prefix come off.
pub fn known_bug_a_late_joiner_cannot_read_an_agreed_tempo_test() {
  let room = room("drum-late-join", 3)

  propose(room, from: 0, bpm: 128)
  sluice_js.settle(room.sluice)
  tempo(room, 0) |> should.equal(Some(128))

  // A fourth tab opens and replays the history: one `Set`, three `Accept`s.
  let doc_d = sluice_js.connect(room.sluice, "user-late")
  sluice_js.settle(room.sluice)

  let assert Some(value) =
    watershed_js.get(watershed_js.root(doc_d), "settings")
  let assert Ok(settings_d) = watershed_js.resolve_pact_map(doc_d, value)

  // The agreed tempo is unreadable...
  watershed_js.pact_map_get(settings_d, bpm_key) |> should.equal(None)
  // ...because the joiner reconstructed a settled pact as pending, waiting on
  // exactly one client: itself.
  watershed_js.pact_map_is_pending(settings_d, bpm_key) |> should.be_true
  let assert Some(waiting) =
    watershed_js.pact_map_pending_signoffs(settings_d, bpm_key)
  list.length(waiting) |> should.equal(1)
}

pub fn tempo_is_agreed_while_the_pattern_is_not_test() {
  let room = room("drum-contrast", 3)

  // The contrast the demo is built to show, in one test: with a client not
  // acknowledging, a tempo change cannot land...
  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, bpm: 150)
  sluice_js.settle(room.sluice)
  tempo(room, 0) |> should.equal(None)

  // ...while the steps everyone can hear keep flowing between the clients
  // that are still talking, because nothing about them requires agreement.
  let assert Ok(kick) = watershed_js.create_or_set(nth(room.docs, 0))
  watershed_js.set(
    watershed_js.root(nth(room.docs, 0)),
    "kick",
    watershed_js.or_set_handle_of(kick),
  )
  sluice_js.settle(room.sluice)
  watershed_js.or_set_add(kick, "0")
  sluice_js.settle(room.sluice)

  let assert Some(value) =
    watershed_js.get(watershed_js.root(nth(room.docs, 1)), "kick")
  let assert Ok(kick_b) = watershed_js.resolve_or_set(nth(room.docs, 1), value)
  watershed_js.or_set_values(kick_b) |> should.equal(["0"])
}
