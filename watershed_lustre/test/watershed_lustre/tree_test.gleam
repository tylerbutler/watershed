import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None}
import lustre/effect.{type Effect}
import watershed/container
import watershed/transport_js
import watershed/tree/schema
import watershed_lustre/tree

type Msg {
  Performed(Result(Nil, String))
  Created(Result(String, String))
}

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

pub fn perform_runs_lazily_and_defers_the_outcome_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let operation = fn() {
    transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
    Ok(Nil)
  }
  let pending = tree.perform(operation, Performed)
  let assert 0 = transport_js.get_cell(calls)
  run(pending, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  promise.resolve(Nil)
}

pub fn perform_preserves_errors_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  run(tree.perform(fn() { Error("refused") }, Performed), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error("refused"))] = messages(sink)
  promise.resolve(Nil)
}

pub fn create_preserves_invalid_configuration_and_defers_dispatch_test() -> Promise(
  Nil,
) {
  let assert Ok(stored) = schema.stored_from_string(definition)
  let sink = transport_js.new_cell([])
  run(
    tree.create(
      container.CreateConfig("ftp://invalid", "dev-tenant", "token"),
      stored,
      None,
      Created,
    ),
    sink,
  )
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Created(Error(detail))] = messages(sink)
  let assert True = detail != ""
  promise.resolve(Nil)
}

fn run(effect_to_run: Effect(Msg), sink: transport_js.Cell(List(Msg))) -> Nil {
  effect.perform(
    effect_to_run,
    fn(message) {
      transport_js.set_cell(sink, [message, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

fn messages(sink: transport_js.Cell(List(Msg))) -> List(Msg) {
  transport_js.get_cell(sink) |> list.reverse
}
