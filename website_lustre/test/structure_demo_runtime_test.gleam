import gleam/list
import gleam/option.{None, Some}
import watershed_site/structure_demo/model.{
  type Model, ClientA, ClientB, ClientC, Map, MvRegister, Ready,
}
import watershed_site/structure_demo/runtime

pub fn map_race_uses_later_sequence_number_test() {
  runtime.map_race_values()
  |> should_equal([14, 14, 14])
}

pub fn counter_race_keeps_both_increments_test() {
  runtime.counter_race_values()
  |> should_equal([130, 130, 130])
}

pub fn duplicate_pn_delta_is_absorbed_test() {
  runtime.duplicate_pn_values()
  |> should_equal([52, 52, 52])
}

pub fn or_set_concurrent_add_survives_observed_remove_test() {
  runtime.or_set_race_values()
  |> should_equal([
    ["north-stake", "sluice-tag"],
    ["north-stake", "sluice-tag"],
    ["north-stake", "sluice-tag"],
  ])
}

pub fn two_p_set_tombstone_wins_test() {
  runtime.two_p_set_race_values()
  |> should_equal([[], [], []])
}

pub fn claim_loser_stays_uncommitted_test() {
  runtime.claim_race_values()
  |> should_equal([Some("A"), Some("A"), Some("A")])
}

pub fn ordered_collection_second_acquire_is_empty_test() {
  runtime.ordered_race_values()
  |> should_equal([Some("flood-watch"), None])
}

pub fn cut_link_queues_local_and_remote_work_test() {
  let model = runtime.ready_model(Map)
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let #(model, _) =
    runtime.update(model, runtime.StepMap(ClientA, "mill-race", 1))
  let #(model, _) =
    runtime.update(model, runtime.StepMap(ClientB, "mill-race", 1))
  should_equal(model.queued_for_b > 0, True)
  should_equal(model.pending != [], True)
}

pub fn restored_link_converges_concurrent_mv_writes_test() {
  let model = runtime.ready_model(MvRegister)
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let #(model, _) =
    runtime.update(model, runtime.WriteMv(ClientA, "raise crest"))
  let #(model, _) = runtime.update(model, runtime.WriteMv(ClientB, "arm pump"))
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  let alpha = runtime.mv_values(model, ClientA)
  should_equal(alpha, runtime.mv_values(model, ClientB))
  should_equal(alpha, runtime.mv_values(model, ClientC))
  should_equal(list.length(alpha), 2)
}

pub fn two_offline_b_writes_acknowledge_in_submission_order_test() {
  let model = runtime.ready_model(MvRegister)
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let #(model, _) =
    runtime.update(model, runtime.WriteMv(ClientA, "catch-up first"))
  let #(model, _) = runtime.update(model, runtime.WriteMv(ClientB, "b first"))
  let #(model, _) = runtime.update(model, runtime.WriteMv(ClientB, "b second"))
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let model = deliver_all(model)
  let values = runtime.mv_values(model, ClientA)
  should_equal(values, runtime.mv_values(model, ClientB))
  should_equal(values, runtime.mv_values(model, ClientC))
  should_equal(list.contains(values, "b second"), True)
}

pub fn cut_b_link_keeps_a_and_c_online_test() {
  let model = runtime.ready_model(Map)
  let #(model, _) = runtime.update(model, runtime.ToggleLink)
  let #(model, _) =
    runtime.update(model, runtime.StepMap(ClientA, "mill-race", 1))
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  should_equal(runtime.map_value_for(model, ClientA, "mill-race"), 25)
  should_equal(runtime.map_value_for(model, ClientC, "mill-race"), 25)
  should_equal(runtime.map_value_for(model, ClientB, "mill-race"), 24)
}

pub fn replay_reuses_sequence_and_does_not_restore_resolved_values_test() {
  let model = runtime.ready_model(MvRegister)
  let #(model, _) =
    runtime.update(model, runtime.WriteMv(ClientA, "raise crest"))
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  let sequenced = model.sequence_number
  let #(model, _) = runtime.update(model, runtime.ResolveMv(ClientA))
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  let resolved_sequence = model.sequence_number
  let #(model, _) = runtime.update(model, runtime.Replay)
  let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
  should_equal(sequenced, 1)
  should_equal(model.sequence_number, resolved_sequence)
  should_equal(runtime.mv_values(model, ClientA), ["raise crest + arm pump"])
}

pub fn reset_invalidates_old_delivery_test() {
  let model = runtime.ready_model(MvRegister)
  let old_generation = model.generation
  let #(reset, _) = runtime.update(model, runtime.Reset)
  let #(after_stale, _) = runtime.update(reset, runtime.Deliver(old_generation))
  should_equal(after_stale.generation, old_generation + 1)
  should_equal(after_stale, reset)
  should_equal(after_stale.phase, Ready)
}

fn deliver_all(model: Model) -> Model {
  case model.pending {
    [] -> model
    [_, ..] -> {
      let #(model, _) = runtime.update(model, runtime.Deliver(model.generation))
      deliver_all(model)
    }
  }
}

fn should_equal(actual: a, expected: a) {
  let assert True = actual == expected
}
