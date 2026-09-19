import gleam/option.{Some}
import gleeunit/should
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
    "boulder garden",
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

fn deliver_all(model: runtime.Model) -> runtime.Model {
  case model.pending {
    [] -> model
    [_, ..] ->
      model
      |> runtime.transition(runtime.Deliver(model.generation))
      |> deliver_all
  }
}
