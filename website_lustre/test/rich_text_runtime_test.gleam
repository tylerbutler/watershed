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

pub fn reconnect_refreshes_identity_and_reloads_every_editor_test() {
  let ready = runtime.ready_model()
  let old_identity = runtime.client_identity(ready, runtime.ClientB)
  let reconnected =
    ready
    |> runtime.transition(runtime.Reconnect(runtime.ClientB))

  should.not_equal(
    runtime.client_identity(reconnected, runtime.ClientB),
    old_identity,
  )
  runtime.replicas()
  |> list.each(fn(replica) {
    should.equal(
      runtime.document_reload(reconnected, replica),
      Some(runtime.document_json(reconnected, replica)),
    )
  })
}

pub fn reconnected_editor_is_the_author_of_its_next_delivery_test() {
  let delivered =
    runtime.ready_model()
    |> runtime.transition(runtime.Reconnect(runtime.ClientB))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientB,
      delta("[{\"insert\":\"B\"}]"),
    ))
    |> runtime.transition(runtime.Deliver(0))
  let assert [entry, ..] = delivered.log

  should.equal(entry.author, runtime.ClientB)
}

pub fn peer_selections_transform_in_gleam_test() {
  let selected =
    runtime.ready_model()
    |> runtime.transition(runtime.SelectionChanged(runtime.ClientA, 2, 0))
    |> runtime.transition(runtime.SelectionChanged(runtime.ClientB, 5, 3))
  let edited =
    selected
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
    |> runtime.transition(runtime.SelectionChanged(runtime.ClientA, 3, 0))

  should.equal(
    runtime.peer_selection(edited, runtime.ClientA, runtime.ClientB),
    Some(#(6, 3)),
  )
  should.equal(
    runtime.peer_selection(edited, runtime.ClientB, runtime.ClientA),
    Some(#(3, 0)),
  )

  let delivered = runtime.transition(edited, runtime.Deliver(0))
  should.equal(
    runtime.peer_selection(delivered, runtime.ClientC, runtime.ClientA),
    Some(#(3, 0)),
  )
  should.equal(
    runtime.peer_selection(delivered, runtime.ClientC, runtime.ClientB),
    Some(#(6, 3)),
  )
}

pub fn playback_jitter_settle_and_log_are_model_state_test() {
  let settled =
    runtime.ready_model()
    |> runtime.transition(runtime.SetPace("0.5"))
    |> runtime.transition(runtime.SetJitter(True))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientA,
      delta("[{\"insert\":\"A\"}]"),
    ))
    |> runtime.transition(runtime.EditorChanged(
      runtime.ClientB,
      delta("[{\"insert\":\"B\"}]"),
    ))
    |> runtime.transition(runtime.Settle)

  should.equal(settled.pace_quarters, 2)
  should.equal(settled.jitter, True)
  should.equal(settled.pending, [])
  should.be_true(settled.latest_sequence > 0)
  should.equal(list.length(settled.log), 2)
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
