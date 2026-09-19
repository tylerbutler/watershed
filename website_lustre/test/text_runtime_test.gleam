import gleam/option.{Some}
import gleam/string
import gleeunit/should
import watershed_site/text/runtime

pub fn concurrent_inserts_converge_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.Insert(runtime.ClientB, 0, "upstream "))
    |> runtime.transition(runtime.Insert(runtime.ClientC, 0, "downstream "))
    |> deliver_all

  should.equal(runtime.all_values_equal(model), True)
  should.be_true(
    runtime.value(model, runtime.ClientA)
    |> string.contains("upstream "),
  )
  should.be_true(
    runtime.value(model, runtime.ClientA)
    |> string.contains("downstream "),
  )
}

pub fn cursor_payload_is_forwarded_to_the_other_editor_test() {
  let payload = "{\"start\":{\"kind\":\"start\"},\"end\":{\"kind\":\"end\"}}"
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.CursorChanged(runtime.ElementA, payload))

  should.equal(runtime.peer_cursor(model, runtime.ElementB), Some(payload))
}

pub fn reset_advances_generation_and_rejects_stale_delivery_test() {
  let model = runtime.ready_model()
  let old_generation = model.generation
  let reset = runtime.transition(model, runtime.Reset)
  let #(after_stale, _) = runtime.update(reset, runtime.Deliver(old_generation))

  should.equal(reset.generation, old_generation + 1)
  should.equal(after_stale, reset)
}

pub fn editor_startup_failure_is_visible_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorFailed(
      runtime.ElementA,
      "Cannot start the text editor.",
    ))

  should.equal(model.error, Some("Cannot start the text editor."))
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
