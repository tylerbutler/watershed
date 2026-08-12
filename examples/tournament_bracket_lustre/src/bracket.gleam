//// Static single-elimination bracket topology and pure advancement logic.
////
//// This module is deliberately independent of watershed: the only
//// collaborative state in this demo is *match results*, one per key in a
//// `RegisterCollection` (see `doc_schema.matches`). Which seed plays which
//// seed, and which match's winner advances into which later match, is a
//// fixed table — the same for every room, every connection, forever — so it
//// is plain data here rather than something stored in the document.
////
//// Fixed 8-player single-elimination: 4 quarterfinals -> 2 semifinals -> 1
//// final, 7 matches total. Seeds pair up in adjacent order (1v2, 3v4, 5v6,
//// 7v8) rather than a reseeded bracket (1v8, 4v5, ...) — reseeding is a
//// nicety this demo does not need to earn its point about `RegisterCollection`.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// The 8 fixed seeds, in seed order. Display strings only — never written to
/// the document.
pub const seeds = [
  "Alaric", "Beatrix", "Cassius", "Delphine", "Ewan", "Farrah", "Gideon",
  "Halcyon",
]

pub type Round {
  Quarterfinal
  Semifinal
  Final
}

pub type MatchId {
  MatchId(round: Round, index: Int)
}

/// The `RegisterCollection` key for a match. `"r1m1"` .. `"r1m4"` for the
/// quarterfinals, `"r2m1"` / `"r2m2"` for the semifinals, `"r3m1"` for the
/// final — 7 keys, matching the plan's data model exactly.
pub fn match_key(id: MatchId) -> String {
  let round_num = case id.round {
    Quarterfinal -> 1
    Semifinal -> 2
    Final -> 3
  }
  "r" <> int.to_string(round_num) <> "m" <> int.to_string(id.index)
}

pub const quarterfinals = [
  MatchId(Quarterfinal, 1), MatchId(Quarterfinal, 2), MatchId(Quarterfinal, 3),
  MatchId(Quarterfinal, 4),
]

pub const semifinals = [MatchId(Semifinal, 1), MatchId(Semifinal, 2)]

pub const final = MatchId(Final, 1)

/// Every match in the bracket, in round order — the order `all_match_keys`
/// and the collection's 7 registers are enumerated.
pub fn all_matches() -> List(MatchId) {
  list.flatten([quarterfinals, semifinals, [final]])
}

pub fn all_match_keys() -> List(String) {
  all_matches() |> list.map(match_key)
}

/// A confirmed result: the `Atomic` (linearizable CAS winner) value for a
/// match's register, decoded from its JSON `{"winner": ..., "score": ...}`.
pub type MatchResult {
  MatchResult(winner: String, score: String)
}

/// What fills a match's two slots before it has been reported: either a fixed
/// seed name (quarterfinals), the winner of an earlier match once known, or
/// `Undecided` while the feeder match is still open.
pub type Slot {
  SeedSlot(String)
  WinnerSlot(String)
  Undecided
}

/// The two matches whose winners fill this match's slots, or `None` for a
/// quarterfinal (whose slots are fixed seeds, not other matches).
pub fn feeders(id: MatchId) -> Option(#(MatchId, MatchId)) {
  case id {
    MatchId(Quarterfinal, _) -> None
    MatchId(Semifinal, 1) ->
      Some(#(MatchId(Quarterfinal, 1), MatchId(Quarterfinal, 2)))
    MatchId(Semifinal, 2) ->
      Some(#(MatchId(Quarterfinal, 3), MatchId(Quarterfinal, 4)))
    MatchId(Final, _) ->
      Some(#(MatchId(Semifinal, 1), MatchId(Semifinal, 2)))
    MatchId(Semifinal, _) -> None
  }
}

/// The two fixed seed names for a quarterfinal, by adjacent pairing:
/// qf1 = seed 1 v 2, qf2 = seed 3 v 4, qf3 = seed 5 v 6, qf4 = seed 7 v 8.
pub fn quarterfinal_seeds(index: Int) -> #(String, String) {
  let assert Ok(a) = list_at(seeds, { index - 1 } * 2)
  let assert Ok(b) = list_at(seeds, { index - 1 } * 2 + 1)
  #(a, b)
}

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case list.drop(items, index) {
    [item, ..] -> Ok(item)
    [] -> Error(Nil)
  }
}

/// A match's two player slots, derived from fixed seeds (quarterfinals) or
/// from earlier matches' results (semifinals, final) — no register lookup
/// beyond the results already collected in `results`.
pub fn slots_for(
  id: MatchId,
  results: Dict(String, MatchResult),
) -> #(Slot, Slot) {
  case id, feeders(id) {
    MatchId(Quarterfinal, index), _ -> {
      let #(a, b) = quarterfinal_seeds(index)
      #(SeedSlot(a), SeedSlot(b))
    }
    _, Some(#(feeder_a, feeder_b)) -> #(
      slot_from_feeder(feeder_a, results),
      slot_from_feeder(feeder_b, results),
    )
    _, None -> #(Undecided, Undecided)
  }
}

fn slot_from_feeder(
  feeder: MatchId,
  results: Dict(String, MatchResult),
) -> Slot {
  case dict.get(results, match_key(feeder)) {
    Ok(MatchResult(winner:, ..)) -> WinnerSlot(winner)
    Error(_) -> Undecided
  }
}

/// A match is reportable once both of its slots are decided (a fixed seed, or
/// an earlier match's winner) and it has no result of its own yet.
pub fn is_reportable(
  id: MatchId,
  results: Dict(String, MatchResult),
) -> Bool {
  case dict.has_key(results, match_key(id)) {
    True -> False
    False ->
      case slots_for(id, results) {
        #(Undecided, _) | #(_, Undecided) -> False
        #(_, _) -> True
      }
  }
}

/// The champion's name, once the final has a result — the terminal state of
/// the whole bracket.
pub fn champion(results: Dict(String, MatchResult)) -> Option(String) {
  case dict.get(results, match_key(final)) {
    Ok(MatchResult(winner:, ..)) -> Some(winner)
    Error(_) -> None
  }
}

pub fn round_label(round: Round) -> String {
  case round {
    Quarterfinal -> "Quarterfinal"
    Semifinal -> "Semifinal"
    Final -> "Final"
  }
}

pub fn slot_label(slot: Slot) -> String {
  case slot {
    SeedSlot(name) -> name
    WinnerSlot(name) -> name
    Undecided -> "TBD"
  }
}
