//// The release-target half of the demo: a `PactMap` key that only changes
//// once the room has signed off — same protocol as the drum machine's
//// `"bpm"`, applied to a version string instead of a tempo.
////
//// **Three clients, not two.** A two-client version of every test in this
//// file passed against the broken quorum this demo family was written to
//// expose — the signoff list must be the connected roster, not `[self,
//// author]`, and two clients cannot tell those apart. Do not reduce these to
//// two.

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

import doc_schema
import gleam/dynamic/decode
import release_readiness
import watershed/pact_map_kernel
import watershed/sluice_js.{type Sluice}
import watershed/transport_js
import watershed.{type Document, type OrSet, type PactMap}

const target_key = "target"

const checks_key = "checks"

// ── Harness ──────────────────────────────────────────────────────────────────

type Room {
  Room(
    sluice: Sluice,
    docs: List(Document(doc_schema.Checklist)),
    release: List(PactMap),
    events: List(fn() -> List(pact_map_kernel.PactMapEvent)),
  )
}

/// `n` clients sharing one release `PactMap`, each subscribed to it.
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
  let assert Ok(seed) = watershed.create_pact_map(first)
  watershed.set(
    watershed.root(first),
    target_key,
    watershed.pact_map_handle_of(seed),
  )
  sluice_js.settle(sluice)

  let release =
    docs
    |> list.map(fn(doc) {
      let assert Some(value) =
        watershed.get(watershed.root(doc), target_key)
      let assert Ok(pact) = watershed.resolve_pact_map(doc, value)
      pact
    })
  let events = list.map(release, recorder)
  Room(sluice: sluice, docs: docs, release: release, events: events)
}

/// Subscribe and return a reader for everything seen so far. The two
/// transitions this collects *are* the protocol — a client that cannot see
/// them can propose and read but never learn that a peer's proposal landed.
fn recorder(pact: PactMap) -> fn() -> List(pact_map_kernel.PactMapEvent) {
  let seen = transport_js.new_cell([])
  watershed.subscribe_pact_map(pact, fn(event) {
    transport_js.set_cell(seen, [event, ..transport_js.get_cell(seen)])
  })
  fn() { list.reverse(transport_js.get_cell(seen)) }
}

fn nth(items: List(a), index: Int) -> a {
  let assert [item, ..] = list.drop(items, index)
  item
}

fn release_of(room: Room, index: Int) -> PactMap {
  nth(room.release, index)
}

fn events_of(room: Room, index: Int) -> List(pact_map_kernel.PactMapEvent) {
  nth(room.events, index)()
}

fn propose(room: Room, from index: Int, target target: String) -> Nil {
  watershed.pact_map_set(
    release_of(room, index),
    target_key,
    json.string(target),
  )
}

fn target(room: Room, index: Int) -> Option(String) {
  watershed.pact_map_get(release_of(room, index), target_key)
  |> option.map(fn(value) {
    let assert Ok(target) = json.parse(json.to_string(value), decode.string)
    target
  })
}

/// Seed a `checks` OR-set on the same document a `Room`'s `release` PactMap
/// already lives on, and resolve it on every client — the same two-channel
/// root the app bootstraps, so a test that reopens a check exercises the real
/// OR-set, not a stand-in for it.
fn checks_channel(room: Room) -> List(OrSet) {
  let assert [first, ..] = room.docs
  let assert Ok(seed) = watershed.create_or_set(first)
  watershed.set(
    watershed.root(first),
    checks_key,
    watershed.or_set_handle_of(seed),
  )
  sluice_js.settle(room.sluice)

  room.docs
  |> list.map(fn(doc: Document(doc_schema.Checklist)) {
    let assert Some(value) =
      watershed.get(watershed.root(doc), checks_key)
    let assert Ok(set) = watershed.resolve_or_set(doc, value)
    set
  })
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn a_proposal_is_accepted_once_all_three_clients_sign_off_test() {
  let room = room("checklist-quorum", 3)

  propose(room, from: 0, target: "v1.2.0")
  sluice_js.settle(room.sluice)

  // Every replica agrees, and the value is live rather than pending.
  target(room, 0) |> should.equal(Some("v1.2.0"))
  target(room, 1) |> should.equal(Some("v1.2.0"))
  target(room, 2) |> should.equal(Some("v1.2.0"))
  watershed.pact_map_is_pending(release_of(room, 0), target_key)
  |> should.be_false

  // And every replica saw both ends of the protocol, in order.
  events_of(room, 0)
  |> should.equal([
    pact_map_kernel.WentPending(target_key),
    pact_map_kernel.WentAccepted(target_key),
  ])
  events_of(room, 2)
  |> should.equal([
    pact_map_kernel.WentPending(target_key),
    pact_map_kernel.WentAccepted(target_key),
  ])
}

pub fn a_proposal_stalls_while_one_client_is_not_acknowledging_test() {
  let room = room("checklist-stall", 3)

  // The third tab is backgrounded: its frames stop being delivered, so it
  // never sees the proposal and never acknowledges it.
  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, target: "v2.0.0-rc1")
  sluice_js.settle(room.sluice)

  // Pending everywhere, and *stays* pending. This is the window a two-client
  // test cannot produce: with a broken `[self, author]` quorum the proposer
  // and the author are the same client here, so it would accept instantly.
  watershed.pact_map_is_pending(release_of(room, 0), target_key)
  |> should.be_true
  watershed.pact_map_is_pending(release_of(room, 1), target_key)
  |> should.be_true
  target(room, 0) |> should.equal(None)

  // The UI's "waiting on N of M" comes from here, and it must name the
  // client that has gone quiet rather than a bare spinner.
  let assert Some(waiting) =
    watershed.pact_map_pending_signoffs(release_of(room, 0), target_key)
  list.length(waiting) |> should.equal(1)

  // Bringing the tab back resolves it — nothing was lost, only waiting.
  sluice_js.resume(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)
  target(room, 0) |> should.equal(Some("v2.0.0-rc1"))
  target(room, 2) |> should.equal(Some("v2.0.0-rc1"))
}

pub fn a_stalled_proposal_drains_when_the_silent_client_leaves_test() {
  let room = room("checklist-drain", 3)

  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, target: "v1.9.0")
  sluice_js.settle(room.sluice)
  watershed.pact_map_is_pending(release_of(room, 0), target_key)
  |> should.be_true

  // The tab is closed rather than restored — a silent disconnect, not a
  // reconnect. A signoff list is not a deadlock: it drains as the sequenced
  // "leave" removes the client it was waiting on, and the target the
  // survivors were promised finally lands.
  sluice_js.disconnect(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)

  target(room, 0) |> should.equal(Some("v1.9.0"))
  target(room, 1) |> should.equal(Some("v1.9.0"))
  watershed.pact_map_is_pending(release_of(room, 0), target_key)
  |> should.be_false
  events_of(room, 1)
  |> should.equal([
    pact_map_kernel.WentPending(target_key),
    pact_map_kernel.WentAccepted(target_key),
  ])
}

pub fn a_second_proposal_while_one_is_pending_is_rejected_test() {
  let room = room("checklist-collide", 3)

  sluice_js.pause(room.sluice, nth(room.docs, 2))
  propose(room, from: 0, target: "v3.0.0")
  sluice_js.settle(room.sluice)

  // Someone else drafts a different target while the first proposal is still
  // in flight. The kernel drops it — which is why the app disables the
  // draft control rather than letting a proposal disappear with nothing on
  // screen to explain it.
  propose(room, from: 1, target: "v3.0.0-alt")
  sluice_js.settle(room.sluice)

  sluice_js.resume(room.sluice, nth(room.docs, 2))
  sluice_js.settle(room.sluice)

  // The first proposal wins; the second left no trace.
  target(room, 0) |> should.equal(Some("v3.0.0"))
  target(room, 1) |> should.equal(Some("v3.0.0"))
  target(room, 2) |> should.equal(Some("v3.0.0"))
  events_of(room, 1)
  |> should.equal([
    pact_map_kernel.WentPending(target_key),
    pact_map_kernel.WentAccepted(target_key),
  ])
}

/// A tab that opens after the room has agreed a release target reads that
/// target — and does not, on top of it, read a phantom pending proposal.
///
/// This is the regression this family of tests exists to guard: a joiner
/// replays a `Set` and every `Accept` that already settled, and it must
/// reconstruct the *outcome* rather than re-run the protocol as if it had
/// been in the room, which would leave the pact reading pending against a
/// signoff list the joiner was never actually asked to join.
pub fn a_late_joiner_reads_the_accepted_target_without_a_false_pending_test() {
  let room = room("checklist-late-join", 3)

  propose(room, from: 0, target: "v1.2.0")
  sluice_js.settle(room.sluice)
  target(room, 0) |> should.equal(Some("v1.2.0"))

  // A fourth tab opens and replays the history: one `Set`, three `Accept`s.
  let doc_d = sluice_js.connect(room.sluice, "user-late")
  sluice_js.settle(room.sluice)

  let assert Some(value) =
    watershed.get(watershed.root(doc_d), target_key)
  let assert Ok(release_d) = watershed.resolve_pact_map(doc_d, value)

  watershed.pact_map_get(release_d, target_key)
  |> should.equal(Some(json.string("v1.2.0")))
  watershed.pact_map_is_pending(release_d, target_key) |> should.be_false
  watershed.pact_map_pending_signoffs(release_d, target_key)
  |> should.equal(None)

  // And the joiner is now a full member: the next proposal waits on it too.
  propose(room, from: 1, target: "v1.3.0")
  sluice_js.settle(room.sluice)
  watershed.pact_map_get(release_d, target_key)
  |> should.equal(Some(json.string("v1.3.0")))
}

pub fn a_reopened_check_does_not_clear_the_accepted_target_test() {
  // `release_readiness.can_propose` gates *new* proposals on every check
  // being complete; it says nothing about a target the room already
  // accepted. Reopening a real check after publication must leave the
  // accepted target exactly as it was — the room simply is not ready to
  // publish a *different* one until every gate is complete again.
  let room = room("checklist-reopen-after-publish", 3)
  let assert [checks_a, checks_b, checks_c] = checks_channel(room)

  watershed.or_set_add(checks_a, "tests_passing")
  sluice_js.settle(room.sluice)

  propose(room, from: 0, target: "v1.0.0")
  sluice_js.settle(room.sluice)
  target(room, 0) |> should.equal(Some("v1.0.0"))
  target(room, 1) |> should.equal(Some("v1.0.0"))
  target(room, 2) |> should.equal(Some("v1.0.0"))

  // Reopen the gate the app required before this proposal was allowed —
  // publication already happened, so the accepted target must not move.
  watershed.or_set_remove(checks_a, "tests_passing")
  sluice_js.settle(room.sluice)

  watershed.or_set_values(checks_b) |> should.equal([])
  target(room, 0) |> should.equal(Some("v1.0.0"))
  target(room, 1) |> should.equal(Some("v1.0.0"))
  target(room, 2) |> should.equal(Some("v1.0.0"))
  watershed.pact_map_is_pending(release_of(room, 1), target_key)
  |> should.be_false

  // And the room genuinely is not ready to publish a different target until
  // every gate is complete again — read off the real, now-reopened OR-set.
  release_readiness.all_checks_complete(watershed.or_set_values(checks_c), [
    "tests_passing",
  ])
  |> should.be_false
}
