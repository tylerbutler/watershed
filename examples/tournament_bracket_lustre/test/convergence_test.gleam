import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/string
import gleeunit
import gleeunit/should

import tournament_bracket_lustre/bracket
import tournament_bracket_lustre/document_schema
import watershed.{type Document, type RegisterCollection}
import watershed/register_collection_kernel.{Atomic}
import watershed/sluice_js.{type Sluice}

pub fn main() -> Nil {
  gleeunit.main()
}

fn room(name: String) -> #(Sluice, RegisterCollection, RegisterCollection) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root_a = watershed.root_typed(document_a)
  let assert Ok(matches) = watershed.create_register_collection(document_a)
  watershed.set_register_collection_field(
    root_a,
    document_schema.matches(),
    matches,
  )
  sluice_js.settle(sluice)

  #(sluice, matches, matches_for(document_b))
}

fn matches_for(
  document: Document(document_schema.BracketDocument),
) -> RegisterCollection {
  let root = watershed.root_typed(document)
  let assert Ok(Some(matches)) =
    watershed.resolve_register_collection_field(
      document,
      root,
      document_schema.matches(),
    )
  matches
}

fn report(
  matches: RegisterCollection,
  key: String,
  winner: String,
  score: String,
) -> Nil {
  watershed.register_write(
    matches,
    key,
    bracket.to_json(bracket.MatchResult(winner:, score:)),
  )
}

fn official(
  matches: RegisterCollection,
  key: String,
) -> option.Option(bracket.MatchResult) {
  case watershed.register_read(matches, key, Atomic) {
    Ok(value) -> Some(bracket.from_json(value))
    Error(_) -> option.None
  }
}

fn versions(
  matches: RegisterCollection,
  key: String,
) -> List(bracket.MatchResult) {
  case watershed.register_versions(matches, key) {
    Ok(values) -> list.map(values, bracket.from_json)
    Error(_) -> []
  }
}

pub fn full_bracket_converges_to_the_same_champion_test() -> Nil {
  let #(sluice, matches_a, matches_b) = room("bracket-convergence-full")

  report(matches_a, "r1m1", "Alaric", "3-1")
  report(matches_b, "r1m2", "Delphine", "2-1")
  report(matches_a, "r1m3", "Ewan", "3-0")
  report(matches_b, "r1m4", "Gideon", "3-2")
  sluice_js.settle(sluice)

  official(matches_a, "r1m1")
  |> should.equal(Some(bracket.MatchResult("Alaric", "3-1")))
  official(matches_b, "r1m1")
  |> should.equal(Some(bracket.MatchResult("Alaric", "3-1")))

  report(matches_a, "r2m1", "Alaric", "3-2")
  report(matches_b, "r2m2", "Gideon", "3-1")
  sluice_js.settle(sluice)

  report(matches_a, "r3m1", "Alaric", "4-2")
  sluice_js.settle(sluice)

  official(matches_a, "r3m1")
  |> should.equal(Some(bracket.MatchResult("Alaric", "4-2")))
  official(matches_b, "r3m1")
  |> should.equal(Some(bracket.MatchResult("Alaric", "4-2")))
}

/// The demo's payoff scenario: two clients report the *same* match
/// concurrently with different results. Both must converge on the same
/// atomic winner (whichever write the CAS settles on), and the loser's
/// submission must still be retrievable via `register_versions` — a
/// sequenced write is never silently discarded, only out-voted for the
/// atomic slot.
pub fn concurrent_conflicting_reports_converge_on_one_official_winner_test() -> Nil {
  let #(sluice, matches_a, matches_b) = room("bracket-convergence-conflict")

  // Both clients report r1m1 before either has seen the other's write —
  // a genuine concurrent conflict, not a stale-overwrite race.
  report(matches_a, "r1m1", "Alaric", "3-1")
  report(matches_b, "r1m1", "Beatrix", "3-2")
  sluice_js.settle(sluice)

  let result_a = official(matches_a, "r1m1")
  let result_b = official(matches_b, "r1m1")

  // Convergence: both clients land on the identical official winner.
  result_a |> should.equal(result_b)
  result_a |> should.not_equal(option.None)

  // Nothing is silently discarded: both submitted results are still present
  // in the retained version history, on both clients.
  let winners_a =
    versions(matches_a, "r1m1")
    |> list.map(fn(result) { result.winner })
    |> list.sort(order_winner)
  let winners_b =
    versions(matches_b, "r1m1")
    |> list.map(fn(result) { result.winner })
    |> list.sort(order_winner)

  winners_a |> should.equal(["Alaric", "Beatrix"])
  winners_b |> should.equal(["Alaric", "Beatrix"])
}

fn order_winner(a: String, b: String) -> order.Order {
  string.compare(a, b)
}
