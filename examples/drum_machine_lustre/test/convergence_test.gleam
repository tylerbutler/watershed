//// Two clients jamming on the same pattern, with no server and no browser:
//// the in-memory `sluice_js` delivers every frame explicitly, so `settle`
//// drains the room before the assertions read it.
////
//// These are the claims the demo makes out loud, asserted rather than
//// eyeballed in two tabs. Audio is deliberately absent — the scheduler is a
//// Web Audio concern with no collaborative content, and a test that asserted
//// step timings against a mocked clock would be testing the mock.

import doc_schema
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

import watershed.{type Document, type OrSet}
import watershed/sluice_js.{type Sluice}

/// The four track keys, in the order `drum_machine_lustre.tracks()` uses.
const track_keys = ["kick", "snare", "hat", "clap"]

// ── Harness ──────────────────────────────────────────────────────────────────

/// One client's four resolved tracks, in `track_keys` order.
type Client {
  Client(tracks: List(OrSet))
}

/// A room with the four track OR-sets already seeded, and both clients holding
/// resolved handles to them.
///
/// The app bootstraps these with `ensure_or_set`, which resolves through a
/// retry loop on a timer. That is right in a browser and wrong here — the
/// sluice's whole point is synchronous, deterministic delivery — so the test
/// seeds the handles directly and keeps the assertions free of waiting.
fn room(name: String) -> #(Sluice, Client, Client) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root_a = watershed.root(doc_a)
  list.each(track_keys, fn(key) {
    let assert Ok(set) = watershed.create_or_set(doc_a)
    watershed.set(root_a, key, watershed.or_set_handle_of(set))
  })
  sluice_js.settle(sluice)

  #(sluice, client(doc_a), client(doc_b))
}

fn client(doc: Document(doc_schema.Machine)) -> Client {
  let root = watershed.root(doc)
  let tracks =
    track_keys
    |> list.map(fn(key) {
      let assert Some(value) = watershed.get(root, key)
      let assert Ok(set) = watershed.resolve_or_set(doc, value)
      set
    })
  Client(tracks: tracks)
}

fn track(client: Client, index: Int) -> OrSet {
  let assert [set, ..] = list.drop(client.tracks, index)
  set
}

/// Enabled steps, sorted — an OR-set is a set, so its read order carries no
/// meaning and asserting on it would make the test flaky for no reason.
fn steps(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> list.sort(string.compare)
}

/// Toggle exactly as the app does: decided against the optimistic local state,
/// which is what the person clicking can currently see.
fn toggle(set: OrSet, step: String) -> Nil {
  case watershed.or_set_contains(set, step) {
    True -> watershed.or_set_remove(set, step)
    False -> watershed.or_set_add(set, step)
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn two_clients_converge_on_a_pattern_test() {
  let #(sluice, a, b) = room("drum-converge")

  // A lays down four-on-the-floor, B puts hats on the offbeats.
  list.each(["0", "4", "8", "12"], fn(step) { toggle(track(a, 0), step) })
  list.each(["2", "6", "10", "14"], fn(step) { toggle(track(b, 2), step) })
  sluice_js.settle(sluice)

  steps(track(a, 0)) |> should.equal(["0", "12", "4", "8"])
  steps(track(b, 0)) |> should.equal(["0", "12", "4", "8"])
  steps(track(a, 2)) |> should.equal(["10", "14", "2", "6"])
  steps(track(b, 2)) |> should.equal(["10", "14", "2", "6"])
}

pub fn concurrently_enabling_the_same_step_is_not_a_conflict_test() {
  let #(sluice, a, b) = room("drum-same-step")

  // Two people reaching for the same step is the most likely collision in the
  // app, and it must not produce a duplicate or a flicker.
  watershed.or_set_add(track(a, 1), "4")
  watershed.or_set_add(track(b, 1), "4")
  sluice_js.settle(sluice)

  steps(track(a, 1)) |> should.equal(["4"])
  steps(track(b, 1)) |> should.equal(["4"])
}

pub fn a_concurrent_enable_survives_a_disable_test() {
  let #(sluice, a, b) = room("drum-add-wins")

  watershed.or_set_add(track(a, 0), "3")
  sluice_js.settle(sluice)

  // Both edits happen before either is delivered, which is what makes them
  // concurrent: A turns the step off while B turns it on again. A's remove can
  // only carry the tags A knows about, so B's fresh tag survives it.
  watershed.or_set_remove(track(a, 0), "3")
  watershed.or_set_add(track(b, 0), "3")
  sluice_js.settle(sluice)

  // Add-wins: the step is on. This is why the tracks are OR-sets — a TwoPSet
  // would have tombstoned "3" and refused to let anyone enable it again.
  steps(track(a, 0)) |> should.equal(["3"])
  steps(track(b, 0)) |> should.equal(["3"])
}

pub fn a_step_toggles_off_and_back_on_test() {
  let #(sluice, a, b) = room("drum-retoggle")

  toggle(track(a, 3), "9")
  sluice_js.settle(sluice)
  steps(track(b, 3)) |> should.equal(["9"])

  toggle(track(a, 3), "9")
  sluice_js.settle(sluice)
  steps(track(b, 3)) |> should.equal([])

  toggle(track(a, 3), "9")
  sluice_js.settle(sluice)
  steps(track(b, 3)) |> should.equal(["9"])
}

pub fn tracks_are_independent_test() {
  let #(sluice, a, b) = room("drum-independent")

  // The same step index on all four tracks: one channel per track means these
  // cannot interfere, and this is the test that would catch a shared channel.
  list.each([0, 1, 2, 3], fn(index) {
    watershed.or_set_add(track(a, index), "5")
  })
  watershed.or_set_remove(track(b, 1), "5")
  sluice_js.settle(sluice)

  steps(track(b, 0)) |> should.equal(["5"])
  steps(track(b, 2)) |> should.equal(["5"])
  steps(track(b, 3)) |> should.equal(["5"])
  steps(track(a, 1)) |> should.equal(steps(track(b, 1)))
}

pub fn a_late_joiner_replays_the_pattern_test() {
  let #(sluice, a, _b) = room("drum-late-join")

  list.each(["0", "8"], fn(step) { watershed.or_set_add(track(a, 0), step) })
  sluice_js.settle(sluice)

  // Someone walking in halfway through hears what the room is already playing.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  steps(track(client(doc_c), 0)) |> should.equal(["0", "8"])
}
