import gleam/list
import gleam/option.{Some}
import gleeunit/should
import watershed/json_ot.{
  Index, Key, VObject, VString, list_insert, object_insert,
}
import watershed_site/json_ot/runtime

pub fn concurrent_object_inserts_converge_test() {
  let model = runtime.ready_model()
  let model =
    runtime.transition(
      model,
      runtime.Submit(
        runtime.ClientA,
        [object_insert([Key("alpha")], VString("surveyed"))],
        "field:alpha",
        "insert .alpha",
      ),
    )
  let model =
    runtime.transition(
      model,
      runtime.Submit(
        runtime.ClientB,
        [object_insert([Key("beta")], VString("checked"))],
        "field:beta",
        "insert .beta",
      ),
    )
    |> deliver_all

  should.equal(runtime.documents(model), [
    VObject([
      #("alpha", VString("surveyed")),
      #("beta", VString("checked")),
      #("crew", runtime.string_array(["Ada", "Ben"])),
      #("gauge", runtime.gauge_value(24, "steady")),
      #("site", VString("Mill Race")),
    ]),
    VObject([
      #("alpha", VString("surveyed")),
      #("beta", VString("checked")),
      #("crew", runtime.string_array(["Ada", "Ben"])),
      #("gauge", runtime.gauge_value(24, "steady")),
      #("site", VString("Mill Race")),
    ]),
    VObject([
      #("alpha", VString("surveyed")),
      #("beta", VString("checked")),
      #("crew", runtime.string_array(["Ada", "Ben"])),
      #("gauge", runtime.gauge_value(24, "steady")),
      #("site", VString("Mill Race")),
    ]),
  ])
}

pub fn concurrent_array_inserts_transform_positions_test() {
  let model = runtime.ready_model()
  let model =
    runtime.transition(
      model,
      runtime.Submit(
        runtime.ClientA,
        [list_insert([Key("crew"), Index(0)], VString("Cy"))],
        "field:crew",
        "insert Cy",
      ),
    )
  let model =
    runtime.transition(
      model,
      runtime.Submit(
        runtime.ClientB,
        [list_insert([Key("crew"), Index(0)], VString("Dot"))],
        "field:crew",
        "insert Dot",
      ),
    )
    |> deliver_all

  should.equal(runtime.crew(model, runtime.ClientA), ["Cy", "Dot", "Ada", "Ben"])
  should.equal(runtime.crew(model, runtime.ClientB), ["Cy", "Dot", "Ada", "Ben"])
  should.equal(runtime.crew(model, runtime.ClientC), ["Cy", "Dot", "Ada", "Ben"])
}

pub fn reset_rejects_stale_delivery_test() {
  let model = runtime.ready_model()
  let old_generation = model.generation
  let reset = runtime.transition(model, runtime.Reset)
  let #(after_stale, _) = runtime.update(reset, runtime.Deliver(old_generation))

  should.equal(after_stale.generation, old_generation + 1)
  should.equal(after_stale, reset)
}

pub fn runtime_failure_is_visible_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.RuntimeFailed("Cannot animate the flow."))

  should.equal(model.error, Some("Cannot animate the flow."))
  should.equal(model.phase, runtime.Failed)
}

pub fn delivery_logs_one_broadcast_group_per_step_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.StepStage(runtime.ClientA, 1))
    |> runtime.transition(runtime.StepStage(runtime.ClientB, 2))
  let assert [first, second] = model.pending

  let delivered = runtime.transition(model, runtime.Deliver(model.generation))

  should.equal(delivered.latest_sequence, first.sequence_number)
  should.equal(delivered.pending, [second])
  should.equal(list.length(delivered.log), 1)
  should.equal(delivered.delivery_active, True)
}

pub fn buffered_edits_wait_for_their_real_acknowledgement_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.StepStage(runtime.ClientA, 1))
    |> runtime.transition(runtime.StepStage(runtime.ClientA, 2))
  let assert [first, buffered] = model.pending

  should.be_true(first.sequence_number > 0)
  should.equal(buffered.sequence_number, 0)

  let after_first = runtime.transition(model, runtime.Deliver(model.generation))
  let assert [promoted] = after_first.pending

  should.be_true(promoted.sequence_number > first.sequence_number)
  should.equal(runtime.pending_count(after_first, runtime.ClientA), 1)
  should.equal(after_first.delivery_active, True)
  should.equal(runtime.is_converged(after_first), False)

  let after_second =
    runtime.transition(after_first, runtime.Deliver(after_first.generation))

  should.equal(runtime.pending_count(after_second, runtime.ClientA), 0)
  should.equal(after_second.delivery_active, False)
  should.equal(runtime.is_converged(after_second), True)
  should.equal(list.map(after_second.log, fn(entry) { entry.sequence_number }), [
    promoted.sequence_number,
    first.sequence_number,
  ])
}

fn deliver_all(model: runtime.Model) -> runtime.Model {
  case model.pending {
    [] -> model
    [_, ..] ->
      model
      |> runtime.transition(runtime.Deliver(model.generation))
      |> deliver_all
  }
}
