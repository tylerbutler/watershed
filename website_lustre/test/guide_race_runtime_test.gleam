import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import retro_tutorial_lustre/board
import watershed_site/guide_race/runtime as race

pub fn static_and_initial_state_test() {
  let model = race.static_model()
  model.phase |> should.equal(race.Static)
  model.rig |> should.equal(None)
  model.error |> should.equal(None)
  model.alpha |> should.equal(model.beta)
  let assert [card] = board.cards_for(model.alpha, board.WentWell)
  card.note.text |> should.equal("ship week went smoothly")
  race.init().0.phase |> should.equal(race.Starting)
}

pub fn ready() {
  let assert Ok(rig) = race.start_rig()
  #(race.update(race.init().0, race.Started(0, Ok(rig))).0, rig)
}

pub fn real_add_race_diverges_and_converges_test() {
  let #(model, rig) = ready()
  model.phase |> should.equal(race.Ready)
  let locked = race.update(model, race.RunAddRace).0
  locked.race_locked |> should.be_true()
  race.update(locked, race.RunAddRace).0 |> should.equal(locked)
  let assert Ok(mutation) = race.submit_add_race(rig)
  let pending = race.update(locked, race.AddRaceSubmitted(0, Ok(mutation))).0
  board.note_count(pending.alpha) |> should.equal(2)
  board.note_count(pending.beta) |> should.equal(2)
  { pending.alpha != pending.beta } |> should.be_true()
  list.length(pending.pending) |> should.equal(2)
  list.length(pending.flows) |> should.equal(2)
  let assert Ok(first) = race.deliver_group(rig)
  let intermediate = race.update(pending, race.Delivered(0, Ok(first))).0
  intermediate.delivery_active |> should.be_true()
  let assert Ok(second) = race.deliver_group(rig)
  let completed = race.update(intermediate, race.Delivered(0, Ok(second))).0
  completed.alpha |> should.equal(completed.beta)
  board.note_count(completed.alpha) |> should.equal(3)
  completed.converged |> should.be_true()
  completed.delivery_active |> should.be_false()
  completed.race_locked |> should.be_true()
  completed.pending |> should.equal([])
  list.length(completed.log) |> should.equal(4)
  let authors =
    completed.log |> list.map(fn(entry) { entry.author }) |> list.unique
  list.length(authors) |> should.equal(2)
  let sequences =
    completed.log
    |> list.map(fn(entry) { entry.sequence_number })
    |> list.unique
  list.length(sequences) |> should.equal(2)
}

pub fn real_vote_race_preserves_signed_total_test() {
  let #(model, rig) = ready()
  let assert Ok(mutation) = race.submit_vote_race(rig)
  list.length(mutation.pending) |> should.equal(3)
  let pending = race.update(model, race.VoteRaceSubmitted(0, Ok(mutation))).0
  let complete =
    list.fold([1, 2, 3], pending, fn(model, _) {
      let assert Ok(delivery) = race.deliver_group(rig)
      race.update(model, race.Delivered(0, Ok(delivery))).0
    })
  complete.alpha |> should.equal(complete.beta)
  let assert [card] = board.cards_for(complete.alpha, board.WentWell)
  card.votes |> should.equal(1)
}

pub fn reset_and_stale_messages_test() {
  let #(ready, rig) = ready()
  let reset = race.update(ready, race.Reset).0
  reset.generation |> should.equal(1)
  reset.phase |> should.equal(race.Starting)
  reset.log |> should.equal([])
  reset.flows |> should.equal([])
  reset.race_locked |> should.be_false()
  [
    race.Started(0, Ok(rig)),
    race.ResetDone(0, Ok(rig)),
    race.AddRaceSubmitted(0, Error(race.UnexpectedDelivery("old"))),
    race.VoteRaceSubmitted(0, Error(race.UnexpectedDelivery("old"))),
    race.Delivered(0, Error(race.UnexpectedDelivery("old"))),
    race.Deliver(0),
    race.ClearFlow(0, 1),
  ]
  |> list.each(fn(message) {
    race.update(reset, message).0 |> should.equal(reset)
  })
  race.update(reset, race.ResetDone(1, Ok(rig))).0.phase
  |> should.equal(race.Ready)
}

pub fn failed_outcomes_remain_visible_test() {
  [
    race.Started(0, Error(race.CannotCreateNotes("refused"))),
    race.ResetDone(0, Error(race.CannotCreateVotes("refused"))),
    race.AddRaceSubmitted(
      0,
      Error(race.CannotProject(race.Alpha, "wrong mode")),
    ),
    race.VoteRaceSubmitted(
      0,
      Error(race.CannotProject(race.Beta, "wrong mode")),
    ),
    race.Delivered(0, Error(race.UnexpectedDelivery("handshake"))),
  ]
  |> list.each(fn(message) {
    let failed = race.update(race.static_model(), message).0
    failed.phase |> should.equal(race.Failed)
    let assert Some(reason) = failed.error
    { reason != "" } |> should.be_true()
  })
}

pub fn latency_clamps_and_flow_clear_is_specific_test() {
  let model = race.static_model()
  race.update(model, race.SetLatency(1)).0.latency_ms |> should.equal(100)
  race.update(model, race.SetLatency(5000)).0.latency_ms |> should.equal(2000)
  let first = race.FlowMarker(1, "alpha", "seq", "first")
  let second = race.FlowMarker(2, "beta", "seq", "second")
  let flowing = race.Model(..model, flows: [first, second])
  race.update(flowing, race.ClearFlow(0, 1)).0.flows |> should.equal([second])
}
