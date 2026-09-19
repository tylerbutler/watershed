import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import watershed_lustre/grapheme_offset
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

pub fn ime_commit_keeps_a_concurrent_remote_edit_test() {
  let ready = runtime.ready_model()
  let base = runtime.value(ready, runtime.ClientB)
  let end =
    grapheme_offset.to_utf16(base, base |> string.to_graphemes |> list.length)
  let composing =
    ready
    |> runtime.transition(runtime.CompositionStarted(
      runtime.ClientB,
      base,
      end,
      end,
    ))
    |> runtime.transition(runtime.Insert(runtime.ClientC, 0, "upstream "))
    |> runtime.transition(runtime.Deliver(ready.generation))
  let committed =
    composing
    |> runtime.transition(runtime.CompositionEnded(
      runtime.ClientB,
      base <> " 水",
      end + 2,
      end + 2,
    ))
    |> deliver_all

  should.be_true(
    runtime.value(committed, runtime.ClientA)
    |> string.starts_with("upstream "),
  )
  should.be_true(
    runtime.value(committed, runtime.ClientA)
    |> string.ends_with(" 水"),
  )
  should.equal(runtime.all_values_equal(committed), True)
}

pub fn crowd_insert_submits_two_concurrent_replicas_test() {
  let racing =
    runtime.ready_model()
    |> runtime.transition(runtime.RaceInserts)

  should.equal(runtime.pending_count(racing, runtime.ClientB), 1)
  should.equal(runtime.pending_count(racing, runtime.ClientC), 1)

  let settled = deliver_all(racing)
  should.be_true(
    runtime.value(settled, runtime.ClientA)
    |> string.contains("still "),
  )
  should.be_true(
    runtime.value(settled, runtime.ClientA)
    |> string.contains("calm "),
  )
}

pub fn overlapping_edit_submits_both_sides_of_the_race_test() {
  let racing =
    runtime.ready_model()
    |> runtime.transition(runtime.RaceOverlap)

  should.equal(runtime.pending_count(racing, runtime.ClientB), 1)
  should.equal(runtime.pending_count(racing, runtime.ClientC), 1)
  should.equal(runtime.all_values_equal(deliver_all(racing)), True)
}

pub fn crowd_insert_after_overlapping_edit_is_recoverable_test() {
  let overlapped =
    runtime.ready_model()
    |> runtime.transition(runtime.RaceOverlap)
    |> deliver_all
  let unavailable =
    overlapped
    |> runtime.transition(runtime.RaceInserts)

  should.equal(unavailable.phase, runtime.Ready)
  should.equal(
    unavailable.error,
    Some("The crowd insert target is not available. Reset to restore it."),
  )

  let edited =
    unavailable
    |> runtime.transition(runtime.Insert(runtime.ClientA, 0, "recovered "))

  should.equal(edited.phase, runtime.Delivering)
  should.equal(edited.error, None)
  should.equal(
    runtime.transition(unavailable, runtime.Reset).phase,
    runtime.Ready,
  )
}

pub fn pinned_anchor_resolves_after_a_remote_insert_test() {
  let ready = runtime.ready_model()
  let offset = grapheme_offset.to_utf16(runtime.seed(), 4)
  let pinned =
    ready
    |> runtime.transition(runtime.SelectionChanged(
      runtime.ClientA,
      offset,
      offset,
    ))
    |> runtime.transition(runtime.PinAnchor(runtime.ClientA))
  should.equal(runtime.anchor_position(pinned, runtime.ClientA), Some(#(4, 4)))

  let moved =
    pinned
    |> runtime.transition(runtime.Insert(runtime.ClientB, 0, "wide "))
    |> runtime.transition(runtime.Deliver(ready.generation))

  should.equal(runtime.anchor_position(moved, runtime.ClientA), Some(#(4, 9)))
  should.equal(
    runtime.transition(moved, runtime.ClearAnchor(runtime.ClientA))
      |> runtime.anchor_position(runtime.ClientA),
    None,
  )
}

pub fn playback_jitter_settle_and_log_are_model_state_test() {
  let settled =
    runtime.ready_model()
    |> runtime.transition(runtime.SetPace("2"))
    |> runtime.transition(runtime.SetJitter(True))
    |> runtime.transition(runtime.RaceInserts)
    |> runtime.transition(runtime.Settle)

  should.equal(settled.pace_quarters, 8)
  should.equal(settled.jitter, True)
  should.equal(settled.pending, [])
  should.be_true(settled.latest_sequence > 0)
  should.equal(list.length(settled.log), 2)
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
