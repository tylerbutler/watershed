import gleam/list
import gleam/option.{None, Some}
import lustre/effect
import watershed/transport_js
import watershed_site/structure_demo/model.{
  type Model, ClientA, ClientB, ClientC, GCounter, Map, Model, MvRegister, OrMap,
  OrSet, PnCounter, Ready, ReplayOperation,
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
  let model = runtime.transition(model, runtime.ToggleLink)
  let model =
    runtime.transition(model, runtime.StepMap(ClientA, "mill-race", 1))
  let model =
    runtime.transition(model, runtime.StepMap(ClientB, "mill-race", 1))
  should_equal(model.queued_for_b > 0, True)
  should_equal(model.pending != [], True)
}

pub fn restored_link_converges_concurrent_mv_writes_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = runtime.transition(model, runtime.WriteMv(ClientA, "raise crest"))
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "arm pump"))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  let alpha = runtime.mv_values(model, ClientA)
  should_equal(alpha, runtime.mv_values(model, ClientB))
  should_equal(alpha, runtime.mv_values(model, ClientC))
  should_equal(alpha, ["arm pump"])
}

pub fn two_offline_b_writes_acknowledge_in_submission_order_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model =
    runtime.transition(model, runtime.WriteMv(ClientA, "catch-up first"))
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b first"))
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b second"))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = deliver_all(model)
  let values = runtime.mv_values(model, ClientA)
  should_equal(values, runtime.mv_values(model, ClientB))
  should_equal(values, runtime.mv_values(model, ClientC))
  should_equal(values, ["b second"])
  should_equal(
    model.log
      |> list.reverse
      |> list.map(fn(entry) { entry.label }),
    [
      "MV-register write catch-up first",
      "MV-register write b first",
      "MV-register write b second",
    ],
  )
}

pub fn cut_b_link_keeps_a_and_c_online_test() {
  let model = runtime.ready_model(Map)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model =
    runtime.transition(model, runtime.StepMap(ClientA, "mill-race", 1))
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  should_equal(runtime.map_value_for(model, ClientA, "mill-race"), 25)
  should_equal(runtime.map_value_for(model, ClientC, "mill-race"), 25)
  should_equal(runtime.map_value_for(model, ClientB, "mill-race"), 24)
}

pub fn replay_reuses_sequence_and_does_not_restore_resolved_values_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.WriteMv(ClientA, "raise crest"))
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  let sequenced = model.sequence_number
  let model = runtime.transition(model, runtime.ResolveMv(ClientA))
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  let resolved_sequence = model.sequence_number
  let assert Some(ReplayOperation(_, _, replay_sequence)) = model.last_replay
  should_equal(replay_sequence, resolved_sequence)
  let model = runtime.transition(model, runtime.Replay)
  let model = runtime.transition(model, runtime.Deliver(model.generation))
  should_equal(sequenced, 1)
  should_equal(model.sequence_number, resolved_sequence)
  should_equal(runtime.mv_values(model, ClientA), ["raise crest + arm pump"])
}

pub fn kernel_mutation_is_deferred_until_effect_runs_test() {
  let model = runtime.ready_model(Map)
  let #(waiting, pending) =
    runtime.update(model, runtime.StepMap(ClientA, "mill-race", 1))
  should_equal(runtime.map_value_for(waiting, ClientA, "mill-race"), 24)
  let messages = transport_js.new_cell([])
  effect.perform(
    pending,
    fn(message) {
      transport_js.set_cell(messages, [
        message,
        ..transport_js.get_cell(messages)
      ])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "This effect does not use the root." },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
  should_equal(transport_js.get_cell(messages), [])
}

pub fn shared_crdt_baselines_use_one_summary_test() {
  let g = runtime.ready_model(GCounter)
  let g = runtime.transition(g, runtime.IncrementGCounter(ClientA, 1))
  let g = deliver_all(g)
  should_equal(runtime.g_counter_value(g, ClientA), 19)
  should_equal(runtime.g_counter_value(g, ClientB), 19)

  let pn = runtime.ready_model(PnCounter)
  let pn = runtime.transition(pn, runtime.UpdatePnCounter(ClientA, 1))
  let pn = deliver_all(pn)
  should_equal(runtime.pn_value(pn, ClientA), 45)
  should_equal(runtime.pn_value(pn, ClientB), 45)

  let or_map = runtime.ready_model(OrMap)
  let or_map =
    runtime.transition(
      or_map,
      runtime.IncrementOrMap(ClientA, "spoil-north", 1),
    )
  let or_map = deliver_all(or_map)
  should_equal(runtime.or_map_value(or_map, ClientA, "spoil-north"), "19")
  should_equal(runtime.or_map_value(or_map, ClientB, "spoil-north"), "19")

  let or_set = runtime.ready_model(OrSet)
  let or_set =
    runtime.transition(or_set, runtime.RemoveOrSet(ClientA, "north-stake"))
  let or_set = deliver_all(or_set)
  should_equal(runtime.set_contains(or_set, ClientA, "north-stake"), False)
  should_equal(runtime.set_contains(or_set, ClientB, "north-stake"), False)
}

pub fn projection_failure_is_visible_test() {
  let map = runtime.ready_model(Map)
  let counter = runtime.ready_model(GCounter)
  let broken = Model(..map, alpha: counter.alpha)
  let projected = runtime.transition(broken, runtime.Project)
  should_equal(
    projected.visible_error,
    Some("Cannot project Client A as a shared map."),
  )
}

pub fn reset_invalidates_old_delivery_test() {
  let model = runtime.ready_model(MvRegister)
  let old_generation = model.generation
  let reset = runtime.transition(model, runtime.Reset)
  let #(after_stale, _) = runtime.update(reset, runtime.Deliver(old_generation))
  should_equal(after_stale.generation, old_generation + 1)
  should_equal(after_stale, reset)
  should_equal(after_stale.phase, Ready)
}

fn deliver_all(model: Model) -> Model {
  case model.pending {
    [] -> model
    [_, ..] -> {
      let model = runtime.transition(model, runtime.Deliver(model.generation))
      deliver_all(model)
    }
  }
}

fn should_equal(actual: a, expected: a) {
  let assert True = actual == expected
}
