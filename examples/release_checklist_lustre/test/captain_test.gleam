//// The captain half of the demo: a `Claims` channel that elects one release
//// captain, first-writer-wins, with compare-and-set take-over. No server and
//// no browser — the in-memory `sluice_js` delivers every frame explicitly,
//// so `settle` drains the room before the assertions read it.
////
//// This is a UI convenience, not a security boundary: `try_set_claim` and
//// `compare_and_set_claim` are ordinary channel writes any client can make.
//// What these tests demonstrate is that the *election* converges to exactly
//// one winner even when several clients contend for the seat at once — the
//// same guarantee `release_readiness.is_captain` leans on to decide who the
//// app's release-form UI shows to.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

import doc_schema
import release_readiness
import watershed.{type Claims, type Document}
import watershed/sluice_js.{type Sluice}

const captain_key = "captain"

// ── Harness ──────────────────────────────────────────────────────────────────

/// `n` clients sharing one captain `Claims` channel.
///
/// The app reaches this state through `ensure_claims`, which resolves on a
/// retry timer; the sluice is synchronous, so the handle is seeded directly
/// and every assertion can read straight after a `settle`.
fn room(name: String, clients: List(String)) -> #(Sluice, List(Claims)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let docs = list.map(clients, fn(user) { sluice_js.connect(sluice, user) })
  sluice_js.settle(sluice)

  let assert [first, ..] = docs
  let assert Ok(seed) = watershed.create_claims(first)
  watershed.set(
    watershed.root(first),
    captain_key,
    watershed.claims_handle_of(seed),
  )
  sluice_js.settle(sluice)

  let claims =
    docs
    |> list.map(fn(doc: Document(doc_schema.Checklist)) {
      let assert Some(value) = watershed.get(watershed.root(doc), captain_key)
      let assert Ok(claims) = watershed.resolve_claims(doc, value)
      claims
    })
  #(sluice, claims)
}

fn nth(items: List(a), index: Int) -> a {
  let assert [item, ..] = list.drop(items, index)
  item
}

fn captain_of(claims: List(Claims), index: Int) -> Claims {
  nth(claims, index)
}

/// Read the committed captain, exactly as `release_checklist_lustre.
/// read_captain` decodes it.
fn committed_captain(claims: Claims) -> Option(String) {
  case watershed.get_claim(claims, captain_key) {
    Some(value) ->
      case json.parse(json.to_string(value), decode.string) {
        Ok(user_id) -> Some(user_id)
        Error(_) -> None
      }
    None -> None
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

pub fn first_writer_wins_the_captain_seat_test() {
  let #(sluice, claims) = room("captain-first-writer", ["user-a", "user-b"])

  let _ =
    watershed.try_set_claim(
      captain_of(claims, 0),
      captain_key,
      json.string("user-a"),
    )
  sluice_js.settle(sluice)

  committed_captain(captain_of(claims, 0)) |> should.equal(Some("user-a"))
  committed_captain(captain_of(claims, 1)) |> should.equal(Some("user-a"))
}

pub fn a_second_claim_after_commit_is_rejected_test() {
  let #(sluice, claims) = room("captain-already-claimed", ["user-a", "user-b"])

  let _ =
    watershed.try_set_claim(
      captain_of(claims, 0),
      captain_key,
      json.string("user-a"),
    )
  sluice_js.settle(sluice)

  // B tries to claim a seat that is already taken. `try_set_claim` is
  // write-once: this must not disturb the committed captain.
  let _ =
    watershed.try_set_claim(
      captain_of(claims, 1),
      captain_key,
      json.string("user-b"),
    )
  sluice_js.settle(sluice)

  committed_captain(captain_of(claims, 0)) |> should.equal(Some("user-a"))
  committed_captain(captain_of(claims, 1)) |> should.equal(Some("user-a"))
}

pub fn concurrent_captain_claims_converge_on_one_winner_test() {
  let #(sluice, claims) =
    room("captain-concurrent", ["user-a", "user-b", "user-c"])

  // All three reach for the seat in the same instant — nobody has seen
  // anybody else's claim yet.
  let _ =
    watershed.try_set_claim(
      captain_of(claims, 0),
      captain_key,
      json.string("user-a"),
    )
  let _ =
    watershed.try_set_claim(
      captain_of(claims, 1),
      captain_key,
      json.string("user-b"),
    )
  let _ =
    watershed.try_set_claim(
      captain_of(claims, 2),
      captain_key,
      json.string("user-c"),
    )
  sluice_js.settle(sluice)

  // Exactly one of them won, and every replica agrees on who.
  let assert Some(winner) = committed_captain(captain_of(claims, 0))
  [Some("user-a"), Some("user-b"), Some("user-c")]
  |> list.contains(Some(winner))
  |> should.be_true
  committed_captain(captain_of(claims, 1)) |> should.equal(Some(winner))
  committed_captain(captain_of(claims, 2)) |> should.equal(Some(winner))

  // And the pure readiness helper agrees with the sluice: the winner (and
  // only the winner) reads as captain — this is exactly what the app's
  // release-form UI and its "only the captain publishes" rule rest on. Feed
  // that same winner/loser identity straight into `can_propose`, not just
  // `is_captain`, since that is the function the release-form UI actually
  // gates on.
  release_readiness.is_captain(Some(winner), winner) |> should.be_true
  release_readiness.can_propose(
    release_readiness.is_captain(Some(winner), winner),
    True,
    "v1.0.0",
    False,
    False,
  )
  |> should.be_true

  ["user-a", "user-b", "user-c"]
  |> list.filter(fn(user_id) { user_id != winner })
  |> list.each(fn(loser) {
    release_readiness.is_captain(Some(winner), loser) |> should.be_false
    release_readiness.can_propose(
      release_readiness.is_captain(Some(winner), loser),
      True,
      "v1.0.0",
      False,
      False,
    )
    |> should.be_false
  })
}

pub fn compare_and_set_takes_the_seat_over_test() {
  let #(sluice, claims) = room("captain-takeover", ["user-a", "user-b"])

  let _ =
    watershed.try_set_claim(
      captain_of(claims, 0),
      captain_key,
      json.string("user-a"),
    )
  sluice_js.settle(sluice)
  committed_captain(captain_of(claims, 1)) |> should.equal(Some("user-a"))

  // B takes over — a compare-and-set against the committed entry B has
  // observed, not a fresh write-once claim.
  let _ =
    watershed.compare_and_set_claim(
      captain_of(claims, 1),
      captain_key,
      json.string("user-b"),
    )
  sluice_js.settle(sluice)

  committed_captain(captain_of(claims, 0)) |> should.equal(Some("user-b"))
  committed_captain(captain_of(claims, 1)) |> should.equal(Some("user-b"))
  release_readiness.is_captain(Some("user-b"), "user-a") |> should.be_false
  release_readiness.is_captain(Some("user-b"), "user-b") |> should.be_true
}

pub fn concurrent_takeover_attempts_converge_on_one_winner_test() {
  let #(sluice, claims) =
    room("captain-takeover-race", ["user-a", "user-b", "user-c"])

  let _ =
    watershed.try_set_claim(
      captain_of(claims, 0),
      captain_key,
      json.string("user-a"),
    )
  sluice_js.settle(sluice)

  // B and C both observed A holding the seat, and both race to take it over
  // in the same instant.
  let _ =
    watershed.compare_and_set_claim(
      captain_of(claims, 1),
      captain_key,
      json.string("user-b"),
    )
  let _ =
    watershed.compare_and_set_claim(
      captain_of(claims, 2),
      captain_key,
      json.string("user-c"),
    )
  sluice_js.settle(sluice)

  let assert Some(winner) = committed_captain(captain_of(claims, 0))
  [Some("user-b"), Some("user-c")]
  |> list.contains(Some(winner))
  |> should.be_true
  committed_captain(captain_of(claims, 1)) |> should.equal(Some(winner))
  committed_captain(captain_of(claims, 2)) |> should.equal(Some(winner))

  // Only the take-over race's winner may propose — including "user-a", who
  // held the seat before the race and lost it, reads as a loser here too.
  release_readiness.can_propose(
    release_readiness.is_captain(Some(winner), winner),
    True,
    "v1.0.0",
    False,
    False,
  )
  |> should.be_true

  ["user-a", "user-b", "user-c"]
  |> list.filter(fn(user_id) { user_id != winner })
  |> list.each(fn(loser) {
    release_readiness.can_propose(
      release_readiness.is_captain(Some(winner), loser),
      True,
      "v1.0.0",
      False,
      False,
    )
    |> should.be_false
  })
}
