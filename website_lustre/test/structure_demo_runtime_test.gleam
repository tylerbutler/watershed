import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lustre/effect
import watershed/map_kernel
import watershed/transport_js
import watershed_site/structure_demo/model.{
  type Model, Claims, ClientA, ClientB, ClientC, Counter, GCounter, GSet, LwwMap,
  LwwRegister, Map, MapReplica, Model, MvRegister, OrMap, OrMapMvRegister, OrSet,
  OrderedCollection, PactMap, PnCounter, Ready, RegisterCollection,
  ReplayOperation, TaskManager, TwoPSet,
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

pub fn offline_a_delivery_does_not_bypass_b_submission_order_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b first"))
  let model =
    runtime.transition(model, runtime.WriteMv(ClientA, "catch-up between"))
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b second"))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = deliver_all(model)
  let values = runtime.mv_values(model, ClientA)
  should_equal(values, ["b second"])
  should_equal(values, runtime.mv_values(model, ClientB))
  should_equal(values, runtime.mv_values(model, ClientC))
  should_equal(
    model.log
      |> list.reverse
      |> list.map(fn(entry) { entry.label }),
    [
      "MV-register write catch-up between",
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

pub fn map_reconnect_catches_b_up_before_resubmitting_local_write_test() {
  let model = runtime.ready_model(Map)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model =
    runtime.transition(model, runtime.StepMap(ClientB, "mill-race", 1))
  let model =
    runtime.transition(model, runtime.StepMap(ClientA, "mill-race", 10))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = deliver_all(model)
  should_equal(runtime.map_values(model, "mill-race"), [25, 25, 25])
  should_equal(
    model.log
      |> list.reverse
      |> list.map(fn(entry) { entry.author }),
    [ClientA, ClientB],
  )
}

pub fn offline_sequencing_updates_latest_replay_metadata_test() {
  let model = runtime.ready_model(Map)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model =
    runtime.transition(model, runtime.StepMap(ClientA, "mill-race", 1))
  let model =
    runtime.transition(model, runtime.StepMap(ClientC, "kettle-run", 1))
  let assert Some(ReplayOperation(_, _, sequence)) = model.last_replay
  should_equal(sequence, 2)
}

pub fn reconnect_preserves_all_offline_a_and_c_catch_up_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b local"))
  let model = runtime.transition(model, runtime.WriteMv(ClientA, "a remote"))
  let model = runtime.transition(model, runtime.WriteMv(ClientC, "c remote"))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = deliver_all(model)
  should_equal(runtime.mv_values(model, ClientA), ["b local"])
  should_equal(runtime.mv_values(model, ClientB), ["b local"])
  should_equal(runtime.mv_values(model, ClientC), ["b local"])
  should_equal(model.pending, [])
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

pub fn deferred_results_reduce_into_current_state_test() -> promise.Promise(Nil) {
  let model = runtime.ready_model(Map)
  let #(model, first) =
    runtime.update(model, runtime.StepMap(ClientA, "mill-race", 1))
  let #(model, second) =
    runtime.update(model, runtime.StepMap(ClientC, "kettle-run", 1))
  let messages = transport_js.new_cell([])
  perform(first, messages)
  perform(second, messages)
  use _ <- promise.await(promise.wait(0))
  let assert [message] = transport_js.get_cell(messages)
  transport_js.set_cell(messages, [])
  let #(model, next) = runtime.update(model, message)
  perform(next, messages)
  use _ <- promise.map(promise.wait(0))
  let assert [message] = transport_js.get_cell(messages)
  let model = runtime.update(model, message).0
  should_equal(runtime.map_value_for(model, ClientA, "mill-race"), 25)
  should_equal(runtime.map_value_for(model, ClientC, "kettle-run"), 62)
  should_equal(list.length(model.pending), 2)
  Nil
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

pub fn every_structure_race_performs_visible_operations_test() {
  [
    Map,
    Counter,
    GCounter,
    PnCounter,
    OrMap,
    OrMapMvRegister,
    LwwMap,
    LwwRegister,
    MvRegister,
    OrSet,
    GSet,
    TwoPSet,
    Claims,
    RegisterCollection,
    OrderedCollection,
    TaskManager,
    PactMap,
  ]
  |> list.each(fn(structure) {
    let before = runtime.ready_model(structure)
    let raced = runtime.transition(before, runtime.RunRace)
    should_equal(
      raced.pending != [] || raced.sequence_number > before.sequence_number,
      True,
    )
  })
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

pub fn every_rendered_map_gauge_is_projection_validated_test() {
  let model = runtime.ready_model(Map)
  let broken =
    Model(
      ..model,
      alpha: MapReplica(
        map_kernel.from_sequenced([
          #("mill-race", json.int(24)),
          #("kettle-run", json.string("invalid")),
          #("low-ford", json.int(42)),
        ]),
      ),
    )
  let projected = runtime.transition(broken, runtime.Project)
  should_equal(projected.visible_error, Some("Map value is not an integer."))
}

pub fn restoring_busy_structure_schedules_its_pending_generation_test() -> promise.Promise(
  Nil,
) {
  let map =
    runtime.ready_model(Map)
    |> fn(model) { Model(..model, latency_ms: 0) }
    |> runtime.transition(runtime.StepMap(ClientA, "mill-race", 1))
  let mv =
    map
    |> runtime.transition(runtime.SelectStructure(MvRegister))
    |> runtime.transition(runtime.WriteMv(ClientA, "busy mv"))
  let #(waiting, selecting) = runtime.update(mv, runtime.SelectStructure(Map))
  let messages = transport_js.new_cell([])
  perform(selecting, messages)
  use _ <- promise.await(promise.wait(0))
  let assert [selected] = transport_js.get_cell(messages)
  transport_js.set_cell(messages, [])
  let #(restored, delivery) = runtime.update(waiting, selected)
  should_equal(restored.selected, Map)
  should_equal(list.length(restored.pending), 1)
  perform(delivery, messages)
  use _ <- promise.map(promise.wait(5))
  let assert [runtime.Deliver(generation)] = transport_js.get_cell(messages)
  should_equal(generation, restored.generation)
  Nil
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

fn perform(pending_effect, messages) {
  effect.perform(
    pending_effect,
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
