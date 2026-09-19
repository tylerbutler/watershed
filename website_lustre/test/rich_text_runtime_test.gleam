import gleam/list
import gleam/option.{Some}
import gleeunit/should
import watershed/rich_text
import watershed_site/rich_text/runtime

pub fn local_delta_is_submitted_optimistically_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))

  should.equal(runtime.pending_count(model, runtime.ClientA), 1)
  should.equal(runtime.canonical(model, runtime.ClientA), "A" <> runtime.seed())
}

pub fn one_operation_in_flight_buffers_later_edits_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"B\"}]"),
    ))
  let assert [first, buffered] = model.pending

  should.be_true(first.sequence_number > 0)
  should.equal(buffered.sequence_number, 0)
  should.equal(runtime.pending_count(model, runtime.ClientA), 2)
}

pub fn remote_delta_is_transformed_and_applied_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientB,
      delta("[{\"insert\":\"B\"}]"),
    ))
    |> runtime.transition(runtime.Deliver(0))

  should.equal(
    runtime.adapter_changes(model, runtime.ClientB)
      |> list.is_empty,
    False,
  )

  let converged = deliver_all(model)
  should.equal(runtime.all_documents_equal(converged), True)
  should.equal(
    runtime.canonical(converged, runtime.ClientA),
    "AB" <> runtime.seed(),
  )
}

pub fn acknowledgement_promotes_the_buffered_operation_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"retain\":1},{\"insert\":\"B\"}]"),
    ))
  let assert [first, _] = model.pending

  let acknowledged = runtime.transition(model, runtime.Deliver(0))
  let assert [promoted] = acknowledged.pending

  should.be_true(promoted.sequence_number > first.sequence_number)
  should.equal(runtime.pending_count(acknowledged, runtime.ClientA), 1)
}

pub fn reset_and_reconnect_replace_the_editor_document_test() {
  let edited =
    runtime.ready_model()
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
  let reset = runtime.transition(edited, runtime.Reset)
  let reconnected =
    runtime.transition(reset, runtime.Reconnect(runtime.ClientB))

  should.equal(reset.generation, edited.generation + 1)
  should.equal(runtime.canonical(reconnected, runtime.ClientB), runtime.seed())
  should.equal(
    runtime.document_reload(reconnected, runtime.ClientB),
    Some(runtime.document_json(reconnected, runtime.ClientB)),
  )
}

pub fn adapter_failure_is_visible_test() {
  let model =
    runtime.ready_model()
    |> runtime.transition(runtime.AdapterFailed(
      runtime.ClientC,
      "Cannot mount Quill.",
    ))

  should.equal(model.error, Some("Cannot mount Quill."))
  should.equal(model.phase, runtime.Failed)
}

fn delta(raw: String) -> rich_text.Delta {
  let assert Ok(delta) = rich_text.parse_delta(raw)
  delta
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
