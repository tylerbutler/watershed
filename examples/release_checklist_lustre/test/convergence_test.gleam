//// The checklist half of the demo: an OR-set of completed gate ids, with no
//// server and no browser — the in-memory `sluice_js` delivers every frame
//// explicitly, so `settle` drains the room before the assertions read it.

import gleam/list
import gleam/string
import gleeunit/should

import release_checklist_lustre/doc_schema
import watershed.{type Document, type OrSet}
import watershed/sluice_js.{type Sluice}

const checks_key = "checks"

// ── Harness ──────────────────────────────────────────────────────────────────

/// A room with the `checks` OR-set already seeded, and both clients holding
/// resolved handles to it.
///
/// The app bootstraps this with `ensure_or_set`, which resolves through a
/// retry loop on a timer. That is right in a browser and wrong here — the
/// sluice's whole point is synchronous, deterministic delivery — so the test
/// seeds the handle directly and keeps the assertions free of waiting.
fn room(name: String) -> #(Sluice, OrSet, OrSet) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(seed) = watershed.create_or_set(doc_a)
  watershed.set(
    watershed.root(doc_a),
    checks_key,
    watershed.or_set_handle_of(seed),
  )
  sluice_js.settle(sluice)

  #(sluice, checks_of(doc_a), checks_of(doc_b))
}

fn checks_of(doc: Document(doc_schema.Checklist)) -> OrSet {
  let assert Ok(value) = watershed.get(watershed.root(doc), checks_key)
  let assert Ok(set) = watershed.resolve_or_set(doc, value)
  set
}

/// Completed gate ids, sorted — an OR-set is a set, so its read order carries
/// no meaning and asserting on it would make the test flaky for no reason.
fn completed(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> list.sort(string.compare)
}

/// Toggle exactly as the app does: decided against the optimistic local
/// state, which is what the person clicking can currently see.
fn toggle(set: OrSet, id: String) -> Nil {
  case watershed.or_set_contains(set, id) {
    True -> watershed.or_set_remove(set, id)
    False -> watershed.or_set_add(set, id)
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn two_clients_converge_on_a_checklist_test() -> Nil {
  let #(sluice, a, b) = room("checklist-converge")

  toggle(a, "tests_passing")
  toggle(b, "changelog_updated")
  sluice_js.settle(sluice)

  completed(a) |> should.equal(["changelog_updated", "tests_passing"])
  completed(b) |> should.equal(["changelog_updated", "tests_passing"])
}

pub fn concurrently_completing_the_same_gate_is_not_a_conflict_test() -> Nil {
  let #(sluice, a, b) = room("checklist-same-gate")

  // Two people reaching for the same gate is the most likely collision in
  // the app, and it must not produce a duplicate or a flicker.
  watershed.or_set_add(a, "security_review")
  watershed.or_set_add(b, "security_review")
  sluice_js.settle(sluice)

  completed(a) |> should.equal(["security_review"])
  completed(b) |> should.equal(["security_review"])
}

pub fn a_concurrent_completion_survives_a_reopen_test() -> Nil {
  let #(sluice, a, b) = room("checklist-add-wins")

  watershed.or_set_add(a, "docs_updated")
  sluice_js.settle(sluice)

  // Both edits happen before either is delivered, which is what makes them
  // concurrent: A reopens the gate while B completes it again. A's remove
  // can only carry the tags A knows about, so B's fresh tag survives it.
  watershed.or_set_remove(a, "docs_updated")
  watershed.or_set_add(b, "docs_updated")
  sluice_js.settle(sluice)

  // Add-wins: the gate reads complete. This is why `checks` is an OR-set —
  // a TwoPSet would have tombstoned "docs_updated" and refused to let anyone
  // complete it again.
  completed(a) |> should.equal(["docs_updated"])
  completed(b) |> should.equal(["docs_updated"])
}

pub fn a_gate_toggles_off_and_back_on_test() -> Nil {
  let #(sluice, a, b) = room("checklist-retoggle")

  toggle(a, "tests_passing")
  sluice_js.settle(sluice)
  completed(b) |> should.equal(["tests_passing"])

  toggle(a, "tests_passing")
  sluice_js.settle(sluice)
  completed(b) |> should.equal([])

  toggle(a, "tests_passing")
  sluice_js.settle(sluice)
  completed(b) |> should.equal(["tests_passing"])
}

pub fn a_late_joiner_replays_the_checklist_test() -> Nil {
  let #(sluice, a, _b) = room("checklist-late-join")

  list.each(["tests_passing", "docs_updated"], fn(id) {
    watershed.or_set_add(a, id)
  })
  sluice_js.settle(sluice)

  // Someone walking in halfway through sees what the room has already done.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  completed(checks_of(doc_c))
  |> should.equal(["docs_updated", "tests_passing"])
}
