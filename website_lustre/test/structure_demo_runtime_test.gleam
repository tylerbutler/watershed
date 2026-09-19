import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import lustre/effect
import watershed/map_kernel
import watershed/pact_map_kernel
import watershed/transport_js
import watershed_site/structure_demo/model.{
  type Model, Claims, ClientA, ClientB, ClientC, Counter, CounterReplica,
  GCounter, GSet, LwwMap, LwwRegister, Map, MapReplica, Model, MvRegister, OrMap,
  OrMapMvRegister, OrSet, OrderedCollection, PactMap, PactReplica, PnCounter,
  Ready, RegisterCollection, ReplayOperation, TaskManager, TwoPSet,
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

pub fn counter_only_origin_is_optimistic_until_delivery_test() {
  let model =
    runtime.ready_model(Counter)
    |> runtime.transition(runtime.IncrementCounter(ClientA, 8))
  should_equal(counter_values(model), [128, 120, 120])
  should_equal(runtime.pending_count(model, ClientA), 1)
  should_equal(model.sequence_number, 0)
  should_equal(model.log, [])
  let delivered = deliver_all(model)
  should_equal(counter_values(delivered), [128, 128, 128])
  should_equal(runtime.pending_count(delivered, ClientA), 0)
  should_equal(delivered.sequence_number, 1)
}

pub fn disconnected_counter_queues_b_and_catches_up_before_ack_test() {
  let model =
    runtime.ready_model(Counter)
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.IncrementCounter(ClientB, 5))
    |> runtime.transition(runtime.IncrementCounter(ClientB, -2))
  should_equal(counter_values(model), [120, 123, 120])
  should_equal(runtime.pending_count(model, ClientB), 2)
  should_equal(model.sequence_number, 0)
  let model = model |> runtime.transition(runtime.IncrementCounter(ClientA, 8))
  should_equal(counter_values(model), [128, 123, 128])
  should_equal(runtime.pending_count(model, ClientA), 0)
  should_equal(model.sequence_number, 1)
  let model =
    model
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.Deliver(0))
  should_equal(counter_values(model), [128, 131, 128])
  should_equal(runtime.pending_count(model, ClientB), 2)
  should_equal(model.sequence_number, 1)
  let model = deliver_all(model)
  should_equal(counter_values(model), [131, 131, 131])
  should_equal(runtime.pending_count(model, ClientB), 0)
  should_equal(model.sequence_number, 3)
  should_equal(
    model.log |> list.reverse |> list.map(fn(entry) { entry.author }),
    [ClientA, ClientB, ClientB],
  )
}

pub fn counter_race_uses_the_delivery_queue_test() {
  let model =
    runtime.ready_model(Counter)
    |> runtime.transition(runtime.RunRace)
  should_equal(counter_values(model), [128, 125, 120])
  should_equal(model.sequence_number, 0)
  should_equal(counter_values(deliver_all(model)), [133, 133, 133])
}

pub fn pact_proposal_waits_for_separate_signoff_deliveries_test() {
  let model =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
    |> runtime.transition(runtime.Deliver(0))
  should_equal(model.visible_error, None)
  should_equal(model.sequence_number, 1)
  [model.alpha, model.beta, model.gamma]
  |> list.each(fn(replica) { should_equal(pact_signoffs(replica), [1, 2, 3]) })
  let model = deliver_all(model)
  should_equal(model.sequence_number, 4)
  [ClientA, ClientB, ClientC]
  |> list.each(fn(replica) {
    should_equal(
      runtime.pact_value(model, replica, "gate-policy", False),
      "Survey",
    )
    should_equal(runtime.pact_value(model, replica, "gate-policy", True), "—")
  })
}

pub fn disconnected_pact_preserves_signoffs_and_catch_up_sequence_test() {
  let model =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.PactSet(ClientB, "gate-policy"))
    |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
  should_equal(model.visible_error, None)
  should_equal(model.sequence_number, 3)
  should_equal(pact_signoffs(model.alpha), [2])
  should_equal(pact_signoffs(model.gamma), [2])
  should_equal(runtime.pact_value(model, ClientB, "gate-policy", True), "—")
  should_equal(runtime.pact_value(model, ClientA, "gate-policy", False), "—")
  let model =
    model
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.Deliver(0))
  should_equal(pact_signoffs(model.beta), [1, 2, 3])
  let model =
    model
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.Deliver(0))
  should_equal(pact_signoffs(model.beta), [2])
  should_equal(model.sequence_number, 3)
  let model = deliver_all(model)
  should_equal(model.sequence_number, 5)
  [model.alpha, model.beta, model.gamma]
  |> list.each(fn(replica) {
    let assert PactReplica(state) = replica
    should_equal(
      pact_map_kernel.get_with_details(state, "gate-policy"),
      Ok(pact_map_kernel.Accepted(Some(json.string("Survey")), 5)),
    )
    should_equal(pact_map_kernel.is_pending(state, "gate-policy"), False)
  })
}

pub fn pact_cut_after_proposal_keeps_b_signoff_until_reconnect_test() {
  let model =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.Deliver(0))
  should_equal(model.visible_error, None)
  should_equal(pact_signoffs(model.alpha), [2])
  should_equal(pact_signoffs(model.beta), [1, 2, 3])
  let model = model |> runtime.transition(runtime.ToggleLink) |> deliver_all
  [model.alpha, model.beta, model.gamma]
  |> list.each(fn(replica) {
    let assert PactReplica(state) = replica
    should_equal(
      pact_map_kernel.get_with_details(state, "gate-policy"),
      Ok(pact_map_kernel.Accepted(Some(json.string("Survey")), 4)),
    )
  })
}

pub fn pact_catch_up_preserves_original_accept_sequence_test() {
  let model =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.PactSet(ClientA, "inspection-window"))
  should_equal(model.visible_error, None)
  should_equal(model.sequence_number, 7)
  let model =
    model
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.Deliver(0))
  [model.alpha, model.beta, model.gamma]
  |> list.each(fn(replica) {
    let assert PactReplica(state) = replica
    should_equal(
      pact_map_kernel.get_with_details(state, "gate-policy"),
      Ok(pact_map_kernel.Accepted(Some(json.string("Survey")), 4)),
    )
  })
}

pub fn pending_pact_refusal_does_not_fail_the_delivery_queue_test() {
  let pending =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
    |> runtime.transition(runtime.Deliver(0))
  let refused =
    pending |> runtime.transition(runtime.PactSet(ClientA, "gate-policy"))
  should_equal(refused.phase, pending.phase)
  should_equal(refused.visible_error != None, True)
  should_equal(refused.pending, pending.pending)
  let settled =
    refused
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.Deliver(0))
    |> runtime.transition(runtime.Deliver(0))
  should_equal(
    runtime.pact_value(settled, ClientB, "gate-policy", False),
    "Survey",
  )
  let retry =
    settled |> runtime.transition(runtime.PactSet(ClientB, "gate-policy"))
  should_equal(retry.visible_error, None)
  let accepted = deliver_all(retry)
  should_equal(
    runtime.pact_value(accepted, ClientA, "gate-policy", False),
    "Works",
  )
}

pub fn disconnected_pact_delete_keeps_accepted_value_until_b_signs_test() {
  let model =
    runtime.ready_model(PactMap)
    |> runtime.transition(runtime.ToggleLink)
    |> runtime.transition(runtime.PactDelete(ClientA, "datum-grid"))
  should_equal(model.visible_error, None)
  should_equal(
    runtime.pact_value(model, ClientA, "datum-grid", False),
    "Survey datum",
  )
  should_equal(runtime.pact_value(model, ClientA, "datum-grid", True), "delete")
  should_equal(
    runtime.pact_signoffs(model, ClientA, "datum-grid"),
    "awaiting B",
  )
  let model = model |> runtime.transition(runtime.ToggleLink) |> deliver_all
  [model.alpha, model.beta, model.gamma]
  |> list.each(fn(replica) {
    let assert PactReplica(state) = replica
    should_equal(
      pact_map_kernel.get_with_details(state, "datum-grid"),
      Ok(pact_map_kernel.Accepted(None, 4)),
    )
  })
}

fn counter_values(model: Model) -> List(Int) {
  [model.alpha, model.beta, model.gamma]
  |> list.map(fn(replica) {
    let assert CounterReplica(state) = replica
    state.value
  })
}

fn pact_signoffs(replica) -> List(Int) {
  let assert PactReplica(state) = replica
  let assert Ok(pending) = pact_map_kernel.pending(state, "gate-policy")
  pending.expected_signoffs
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

pub fn same_origin_mv_writes_stay_fifo_across_a_cut_link_test() {
  [ClientA, ClientC]
  |> list.each(fn(origin) {
    let model = runtime.ready_model(MvRegister)
    let model = runtime.transition(model, runtime.WriteMv(origin, "first"))
    should_equal(runtime.pending_count(model, origin), 1)
    should_equal(model.sequence_number, 0)
    let model = runtime.transition(model, runtime.ToggleLink)
    let model = runtime.transition(model, runtime.WriteMv(origin, "second"))
    should_equal(model.visible_error, None)
    should_equal(runtime.pending_count(model, origin), 0)
    should_equal(runtime.mv_sequenced_values(model, ClientA), ["second"])
    should_equal(runtime.mv_sequenced_values(model, ClientC), ["second"])
    should_equal(runtime.mv_values(model, ClientB), ["Survey datum"])
    should_equal(
      model.log |> list.reverse |> list.map(fn(entry) { entry.label }),
      ["MV-register write first", "MV-register write second"],
    )
    let model = runtime.transition(model, runtime.ToggleLink) |> deliver_all
    should_equal(model.visible_error, None)
    should_equal(model.pending, [])
    should_equal(model.sequence_number, 2)
    [ClientA, ClientB, ClientC]
    |> list.each(fn(replica) {
      should_equal(runtime.pending_count(model, replica), 0)
      should_equal(runtime.mv_values(model, replica), ["second"])
      should_equal(runtime.mv_sequenced_values(model, replica), ["second"])
    })
  })
}

pub fn b_mv_writes_stay_fifo_when_cut_between_submissions_test() {
  let model = runtime.ready_model(MvRegister)
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b first"))
  let model = runtime.transition(model, runtime.ToggleLink)
  let model = runtime.transition(model, runtime.WriteMv(ClientB, "b second"))
  should_equal(runtime.pending_count(model, ClientB), 2)
  should_equal(model.sequence_number, 0)
  let model = runtime.transition(model, runtime.ToggleLink) |> deliver_all
  should_equal(model.visible_error, None)
  should_equal(model.pending, [])
  should_equal(
    model.log |> list.reverse |> list.map(fn(entry) { entry.label }),
    ["MV-register write b first", "MV-register write b second"],
  )
  [ClientA, ClientB, ClientC]
  |> list.each(fn(replica) {
    should_equal(runtime.pending_count(model, replica), 0)
    should_equal(runtime.mv_values(model, replica), ["b second"])
    should_equal(runtime.mv_sequenced_values(model, replica), ["b second"])
  })
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

pub fn or_map_string_set_race_unions_concurrent_members_test() {
  let model =
    runtime.ready_model(OrMap)
    |> runtime.transition(runtime.SetOrMapMode("set"))
    |> runtime.transition(runtime.RunRace)
  should_equal(model.visible_error, None)
  should_equal(list.length(model.pending), 2)
  should_equal(
    runtime.or_map_value(model, ClientA, "inspection-brief"),
    "[\"draft\"]",
  )
  should_equal(
    runtime.or_map_value(model, ClientB, "inspection-brief"),
    "[\"reviewed\"]",
  )
  let model = deliver_all(model)
  should_equal(model.visible_error, None)
  should_equal(model.sequence_number, 2)
  should_equal(model.pending, [])
  [ClientA, ClientB, ClientC]
  |> list.each(fn(replica) {
    should_equal(
      runtime.or_map_value(model, replica, "inspection-brief"),
      "[\"draft\", \"reviewed\"]",
    )
    should_equal(runtime.pending_count(model, replica), 0)
  })
}

pub fn deferred_completions_keep_one_delivery_timer_until_it_fires_test() -> promise.Promise(
  Nil,
) {
  let model = Model(..runtime.ready_model(Map), latency_ms: 0, playback_ms: 0)
  use #(model, first) <- promise.await(complete_command(
    model,
    runtime.StepMap(ClientA, "mill-race", 1),
  ))
  use #(model, second) <- promise.await(complete_command(
    model,
    runtime.StepMap(ClientC, "kettle-run", 1),
  ))
  use #(model, projection) <- promise.await(complete_command(
    model,
    runtime.Project,
  ))
  use #(model, cleanup) <- promise.await(complete_command(
    model,
    runtime.ClearFlow(model.generation, -1),
  ))
  let messages = transport_js.new_cell([])
  perform(effect.batch([first, second, projection, cleanup]), messages)
  use _ <- promise.await(promise.wait(0))
  should_equal(delivery_messages(messages), [runtime.Deliver(model.generation)])
  transport_js.set_cell(messages, [])
  use #(model, next) <- promise.await(complete_command(
    model,
    runtime.Deliver(model.generation),
  ))
  should_equal(model.sequence_number, 1)
  should_equal(list.length(model.pending), 1)
  use #(model, projection) <- promise.await(complete_command(
    model,
    runtime.Project,
  ))
  perform(effect.batch([next, projection]), messages)
  use _ <- promise.await(promise.wait(0))
  should_equal(delivery_messages(messages), [runtime.Deliver(model.generation)])
  transport_js.set_cell(messages, [])
  use #(model, last) <- promise.await(complete_command(
    model,
    runtime.Deliver(model.generation),
  ))
  should_equal(model.sequence_number, 2)
  should_equal(model.pending, [])
  perform(last, messages)
  use _ <- promise.map(promise.wait(0))
  should_equal(delivery_messages(messages), [])
  Nil
}

pub fn restored_busy_structure_rearms_one_timer_in_its_new_generation_test() -> promise.Promise(
  Nil,
) {
  let model = Model(..runtime.ready_model(Map), latency_ms: 0, playback_ms: 0)
  use #(model, map_timer) <- promise.await(complete_command(
    model,
    runtime.StepMap(ClientA, "mill-race", 1),
  ))
  let map_generation = model.generation
  use #(model, select_mv) <- promise.await(complete_command(
    model,
    runtime.SelectStructure(MvRegister),
  ))
  use #(model, mv_timer) <- promise.await(complete_command(
    model,
    runtime.WriteMv(ClientA, "busy mv"),
  ))
  let mv_generation = model.generation
  use #(model, restored_timer) <- promise.await(complete_command(
    model,
    runtime.SelectStructure(Map),
  ))
  should_equal(model.selected, Map)
  should_equal(list.length(model.pending), 1)
  should_equal(model.generation, mv_generation + 1)
  use #(model, projection) <- promise.await(complete_command(
    model,
    runtime.Project,
  ))
  let messages = transport_js.new_cell([])
  perform(
    effect.batch([map_timer, select_mv, mv_timer, restored_timer, projection]),
    messages,
  )
  use _ <- promise.await(promise.wait(0))
  [map_generation, mv_generation, model.generation]
  |> list.each(fn(generation) {
    delivery_messages(messages)
    |> list.filter(fn(message) { message == runtime.Deliver(generation) })
    |> should_equal([runtime.Deliver(generation)])
  })
  transport_js.set_cell(messages, [])
  let #(unchanged, stale) =
    runtime.update(model, runtime.Deliver(map_generation))
  should_equal(unchanged, model)
  perform(stale, messages)
  use #(model, delivered) <- promise.await(complete_command(
    model,
    runtime.Deliver(model.generation),
  ))
  should_equal(model.pending, [])
  should_equal(runtime.map_values(model, "mill-race"), [25, 25, 25])
  perform(delivered, messages)
  use _ <- promise.map(promise.wait(0))
  should_equal(delivery_messages(messages), [])
  Nil
}

pub fn fired_delivery_keeps_timer_ownership_while_queued_behind_work_test() -> promise.Promise(
  Nil,
) {
  let model = Model(..runtime.ready_model(Map), latency_ms: 0, playback_ms: 0)
  use #(model, timer) <- promise.await(complete_command(
    model,
    runtime.StepMap(ClientA, "mill-race", 1),
  ))
  let messages = transport_js.new_cell([])
  perform(timer, messages)
  use _ <- promise.await(promise.wait(0))
  let assert [delivery] = delivery_messages(messages)
  transport_js.set_cell(messages, [])
  let #(model, projection) = runtime.update(model, runtime.Project)
  let #(waiting, queued) = runtime.update(model, delivery)
  perform(effect.batch([projection, queued]), messages)
  use _ <- promise.await(promise.wait(0))
  let assert [projected] = transport_js.get_cell(messages)
  transport_js.set_cell(messages, [])
  let #(waiting, work) = runtime.update(waiting, projected)
  perform(work, messages)
  use _ <- promise.await(promise.wait(0))
  should_equal(delivery_messages(messages), [])
  let assert [runtime.Deferred(_, _) as delivered] =
    transport_js.get_cell(messages)
  transport_js.set_cell(messages, [])
  let #(model, completed) = runtime.update(waiting, delivered)
  should_equal(model.sequence_number, 1)
  should_equal(model.pending, [])
  should_equal(runtime.map_values(model, "mill-race"), [25, 25, 25])
  perform(completed, messages)
  use _ <- promise.map(promise.wait(0))
  should_equal(delivery_messages(messages), [])
  Nil
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

fn complete_command(model: Model, command: runtime.Msg) {
  let #(waiting, work) = runtime.update(model, command)
  let messages = transport_js.new_cell([])
  perform(work, messages)
  use _ <- promise.map(promise.wait(0))
  let assert [runtime.Deferred(_, _) as completed] =
    transport_js.get_cell(messages)
  runtime.update(waiting, completed)
}

fn delivery_messages(messages) {
  transport_js.get_cell(messages)
  |> list.filter(fn(message) {
    case message {
      runtime.Deliver(_) -> True
      _ -> False
    }
  })
}

fn deliver_all(model: Model) -> Model {
  case model.pending {
    [] -> model
    [_, ..] -> {
      let delivered =
        runtime.transition(model, runtime.Deliver(model.generation))
      should_equal(delivered.visible_error, None)
      should_equal(delivered.pending == model.pending, False)
      deliver_all(delivered)
    }
  }
}

fn should_equal(actual: a, expected: a) {
  should.equal(actual, expected)
}
