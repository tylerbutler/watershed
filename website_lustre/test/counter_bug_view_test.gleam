import gleam/list
import gleam/string
import gleeunit/should
import lustre/element
import watershed_site/counter_bug/view

pub fn static_view_preserves_all_three_experiments_test() {
  let html = view.static() |> element.to_string
  [
    "Demonstrate the bug",
    "Play the fix",
    "Play the SharedCounter fix",
    "SharedMap · one shared key",
    "Per-replica keys · sum",
    "SharedCounter · signed delta ops",
    "This demonstration runs a live Gleam kernel",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}

pub fn reset_ignores_an_old_playback_step_test() {
  let started = view.update(view.static_model(), view.Play(view.Bug)).0
  let reset = view.update(started, view.Reset(view.Bug)).0
  reset.generation |> should.equal(1)
  view.update(reset, view.Finish(0, view.Bug)).0
  |> should.equal(reset)
}
