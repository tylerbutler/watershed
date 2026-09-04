//// Test entrypoint for the package's pure modules.
////
//// The root `watershed` package runs on startest, but startest's dependency
//// tree pins `gleam_stdlib < 1.0` while this package (and lustre) are on 1.x,
//// so the two cannot share a harness. gleeunit resolves cleanly here and needs
//// no assertion library on Gleam 1.11+ — plain `assert` is enough.

import gleam/javascript/promise.{type Promise}
import gleeunit
import lustre/effect
import watershed/transport_js
import watershed_lustre

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn perform_defers_operation_and_dispatch_test() -> Promise(Nil) {
  let ran = transport_js.new_cell(False)
  let messages = transport_js.new_cell([])
  let pending =
    watershed_lustre.perform(
      operation: fn() {
        transport_js.set_cell(ran, True)
        Error("Expected failure")
      },
      outcome: fn(outcome: Result(Nil, String)) { outcome },
    )
  assert transport_js.get_cell(ran) == False
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
  assert transport_js.get_cell(ran) == True
  assert transport_js.get_cell(messages) == []
  use _ <- promise.map(promise.wait(0))
  assert transport_js.get_cell(messages) == [Error("Expected failure")]
}
