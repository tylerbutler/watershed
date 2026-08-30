import gleam/dict
import gleeunit
import gleeunit/should

import tournament_bracket_lustre/bracket.{
  MatchId, MatchResult, Quarterfinal, Semifinal,
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn quarterfinal_slots_are_the_fixed_seed_pairing_test() -> Nil {
  let results = dict.new()
  bracket.slots_for(MatchId(Quarterfinal, 1), results)
  |> should.equal(#(bracket.SeedSlot("Alaric"), bracket.SeedSlot("Beatrix")))
  bracket.slots_for(MatchId(Quarterfinal, 4), results)
  |> should.equal(#(bracket.SeedSlot("Gideon"), bracket.SeedSlot("Halcyon")))
}

pub fn quarterfinal_is_always_reportable_test() -> Nil {
  bracket.is_reportable(MatchId(Quarterfinal, 1), dict.new())
  |> should.be_true
}

pub fn semifinal_is_undecided_until_both_feeders_report_test() -> Nil {
  let results = dict.new()
  bracket.slots_for(MatchId(Semifinal, 1), results)
  |> should.equal(#(bracket.Undecided, bracket.Undecided))
  bracket.is_reportable(MatchId(Semifinal, 1), results) |> should.be_false

  let results = dict.from_list([#("r1m1", MatchResult("Alaric", "3-1"))])
  bracket.slots_for(MatchId(Semifinal, 1), results)
  |> should.equal(#(bracket.WinnerSlot("Alaric"), bracket.Undecided))
  bracket.is_reportable(MatchId(Semifinal, 1), results) |> should.be_false

  let results =
    dict.from_list([
      #("r1m1", MatchResult("Alaric", "3-1")),
      #("r1m2", MatchResult("Delphine", "2-1")),
    ])
  bracket.slots_for(MatchId(Semifinal, 1), results)
  |> should.equal(#(
    bracket.WinnerSlot("Alaric"),
    bracket.WinnerSlot("Delphine"),
  ))
  bracket.is_reportable(MatchId(Semifinal, 1), results) |> should.be_true
}

pub fn a_match_with_a_result_is_never_reportable_again_test() -> Nil {
  let results = dict.from_list([#("r1m1", MatchResult("Alaric", "3-1"))])
  bracket.is_reportable(MatchId(Quarterfinal, 1), results) |> should.be_false
}

pub fn champion_is_none_until_the_final_reports_test() -> Nil {
  let results =
    dict.from_list([
      #("r1m1", MatchResult("Alaric", "3-1")),
      #("r1m2", MatchResult("Delphine", "2-1")),
      #("r1m3", MatchResult("Ewan", "3-0")),
      #("r1m4", MatchResult("Gideon", "3-2")),
      #("r2m1", MatchResult("Alaric", "3-2")),
      #("r2m2", MatchResult("Gideon", "3-1")),
    ])
  bracket.champion(results) |> should.equal(Error(Nil))

  let results = dict.insert(results, "r3m1", MatchResult("Alaric", "4-2"))
  bracket.champion(results) |> should.equal(Ok("Alaric"))
}

pub fn match_keys_follow_the_planned_layout_test() -> Nil {
  bracket.all_match_keys()
  |> should.equal(["r1m1", "r1m2", "r1m3", "r1m4", "r2m1", "r2m2", "r3m1"])
}

pub fn quarterfinal_seeds_returns_correct_pairs_test() -> Nil {
  bracket.quarterfinal_seeds(1) |> should.equal(Ok(#("Alaric", "Beatrix")))
  bracket.quarterfinal_seeds(2) |> should.equal(Ok(#("Cassius", "Delphine")))
  bracket.quarterfinal_seeds(3) |> should.equal(Ok(#("Ewan", "Farrah")))
  bracket.quarterfinal_seeds(4) |> should.equal(Ok(#("Gideon", "Halcyon")))
}

pub fn quarterfinal_seeds_returns_error_for_invalid_index_test() -> Nil {
  bracket.quarterfinal_seeds(0) |> should.be_error
  bracket.quarterfinal_seeds(5) |> should.be_error
}
