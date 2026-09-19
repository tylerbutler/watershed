import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import lustre/effect
import watershed/transport_js
import watershed_site/sequence/runtime

pub fn concurrent_inserts_keep_deterministic_order_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Insert(runtime.ClientB, 2))
    |> runtime.transition(runtime.Insert(runtime.ClientC, 2))
    |> deliver_all

  let routes = runtime.routes(model)
  should.equal(runtime.all_routes_equal(routes), True)
  should.equal(runtime.route(model, runtime.ClientA), [
    "put-in",
    "mill-race weir",
    "gravel bar",
    "oxbow",
    "kettle-run rapids",
    "low-ford portage",
    "take-out",
  ])
}

pub fn concurrent_remove_and_insert_converge_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Delete(runtime.ClientA, 1))
    |> runtime.transition(runtime.Insert(runtime.ClientB, 1))
    |> deliver_all

  should.equal(runtime.all_routes_equal(runtime.routes(model)), True)
  should.equal(runtime.route(model, runtime.ClientA), [
    "put-in",
    "gravel bar",
    "kettle-run rapids",
    "low-ford portage",
    "take-out",
  ])
}

pub fn local_insert_is_visible_as_pending_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Insert(runtime.ClientA, 2))

  should.equal(runtime.pending_count(model, runtime.ClientA), 1)
  should.equal(runtime.route(model, runtime.ClientA), [
    "put-in",
    "mill-race weir",
    "beaver dam",
    "kettle-run rapids",
    "low-ford portage",
    "take-out",
  ])
}

pub fn reset_advances_generation_and_rejects_stale_delivery_test() {
  let model = runtime.ready_model()
  let old_generation = model.generation
  let reset = runtime.transition(model, runtime.Reset)
  let #(after_stale, _) = runtime.update(reset, runtime.Deliver(old_generation))

  should.equal(reset.generation, old_generation + 1)
  should.equal(after_stale, reset)
}

pub fn runtime_failure_is_visible_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.RuntimeFailed("Cannot animate the route."))

  should.equal(model.error, Some("Cannot animate the route."))
  should.equal(model.phase, runtime.Failed)
}

pub fn crowd_insert_uses_each_short_route_index_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Delete(runtime.ClientC, 4))
    |> runtime.transition(runtime.Delete(runtime.ClientC, 3))
    |> runtime.transition(runtime.Delete(runtime.ClientC, 2))
    |> runtime.transition(runtime.Delete(runtime.ClientC, 1))
    |> runtime.transition(runtime.RaceInsert)

  should.equal(model.error, None)
  should.equal(list.length(runtime.route(model, runtime.ClientB)), 6)
  should.equal(list.length(runtime.route(model, runtime.ClientC)), 2)
}

pub fn unavailable_move_race_preserves_editing_and_reset_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Delete(runtime.ClientA, 4))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 3))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 2))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 1))
    |> deliver_all
  let unavailable = runtime.transition(model, runtime.RaceMove)
  should.equal(unavailable.phase, runtime.Ready)
  should.equal(
    unavailable.error,
    Some("No waypoint can move in both directions."),
  )
  should.equal(unavailable.routes, model.routes)
  should.equal(unavailable.pending, [])
  let edited =
    unavailable
    |> runtime.transition(runtime.Insert(runtime.ClientB, 1))
    |> deliver_all
  should.equal(runtime.route(edited, runtime.ClientA), ["put-in", "gravel bar"])
  should.equal(edited.error, None)
  let reset = runtime.transition(unavailable, runtime.Reset)
  should.equal(reset.phase, runtime.Ready)
  should.equal(reset.error, None)
  should.equal(list.length(runtime.route(reset, runtime.ClientA)), 5)
}

pub fn unavailable_move_race_survives_deferred_effects_test() -> promise.Promise(
  Nil,
) {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Delete(runtime.ClientA, 4))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 3))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 2))
    |> runtime.transition(runtime.Delete(runtime.ClientA, 1))
    |> deliver_all
  use model <- promise.await(complete_command(model, runtime.RaceMove))
  should.equal(model.phase, runtime.Ready)
  should.equal(model.error, Some("No waypoint can move in both directions."))
  should.equal(runtime.is_converged(model), True)
  use model <- promise.await(complete_command(
    model,
    runtime.ClearFlow(model.generation, -1),
  ))
  should.equal(model.phase, runtime.Ready)
  should.equal(runtime.is_converged(model), True)
  use model <- promise.map(complete_command(
    model,
    runtime.Insert(runtime.ClientB, 1),
  ))
  let model = deliver_all(model)
  should.equal(runtime.route(model, runtime.ClientA), ["put-in", "gravel bar"])
  should.equal(model.error, None)
}

fn complete_command(model: runtime.Model, command: runtime.Msg) {
  let #(waiting, work) = runtime.update(model, command)
  let messages = transport_js.new_cell([])
  effect.perform(
    work,
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
  use _ <- promise.map(promise.wait(0))
  let assert [runtime.Deferred(_, _) as completed] =
    transport_js.get_cell(messages)
  runtime.update(waiting, completed).0
}

pub fn rapid_crowd_inserts_allocate_unique_station_names_test() {
  let route =
    runtime.ready_model()
    |> runtime.transition(runtime.RaceInsert)
    |> runtime.transition(runtime.RaceInsert)
    |> runtime.transition(runtime.RaceInsert)
    |> deliver_all
    |> runtime.route(runtime.ClientA)

  should.equal(list.length(route), list.length(list.unique(route)))
}

pub fn delivery_logs_one_broadcast_group_per_step_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Insert(runtime.ClientA, 1))
    |> runtime.transition(runtime.Insert(runtime.ClientB, 2))
  let assert [first, second] = model.pending

  let delivered = runtime.transition(model, runtime.Deliver(model.generation))

  should.equal(delivered.latest_sequence, first.sequence_number)
  should.equal(delivered.pending, [second])
  should.equal(list.length(delivered.log), 1)
  should.equal(delivered.delivery_active, True)
}

pub fn deferred_completion_preserves_newer_station_selection_test() {
  let before =
    runtime.ready_model()
    |> runtime.transition(runtime.Select(runtime.ClientA, "put-in"))
  let next = runtime.transition(before, runtime.Insert(runtime.ClientB, 2))
  let current =
    runtime.transition(
      before,
      runtime.Select(runtime.ClientA, "mill-race weir"),
    )

  let #(completed, _) =
    runtime.update(
      current,
      runtime.Deferred(current.generation, Ok(#(before, next))),
    )

  should.equal(
    runtime.selected(completed, runtime.ClientA),
    Some("mill-race weir"),
  )
}

pub fn clearing_an_old_log_annotation_keeps_the_new_sequence_visible_test() {
  let first =
    runtime.ready_model()
    |> runtime.transition(runtime.SetFieldNotes(True))
    |> runtime.transition(runtime.Insert(runtime.ClientA, 1))
    |> runtime.transition(runtime.Deliver(0))
  let second =
    first
    |> runtime.transition(runtime.Insert(runtime.ClientB, 2))
    |> runtime.transition(runtime.Deliver(0))
  let assert [
    runtime.LogEntry(new_sequence, _, _),
    runtime.LogEntry(old_sequence, _, _),
  ] = second.log
  let assert Ok(runtime.Annotation(new_id, _, _)) =
    list.find(second.annotations, fn(annotation) {
      annotation.target == runtime.LogTarget(new_sequence)
    })
  let assert Ok(runtime.Annotation(old_id, _, _)) =
    list.find(second.annotations, fn(annotation) {
      annotation.target == runtime.LogTarget(old_sequence)
    })

  let cleared = runtime.transition(second, runtime.ClearAnnotation(0, old_id))

  should.be_true(new_id != old_id)
  should.equal(
    list.any(cleared.annotations, fn(annotation) {
      annotation.target == runtime.LogTarget(new_sequence)
    }),
    True,
  )
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
