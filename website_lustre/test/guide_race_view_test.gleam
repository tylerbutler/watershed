import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import guide_race_runtime_test
import lustre/dev/query
import lustre/dev/simulate
import lustre/effect
import lustre/element
import watershed_site/guide_race/runtime
import watershed_site/guide_race/view

fn options() {
  view.Options(notes_only: True, include_noscript: False)
}

fn target(id: String) {
  query.element(query.attribute("data-testid", id))
}

pub fn static_view_has_one_complete_demo_test() {
  let root = view.static()
  view.view(runtime.static_model(), view.Options(True, True))
  |> query.find_all(query.element(query.id("guide-race-demo")))
  |> list.length
  |> should.equal(1)
  let html = root |> element.to_string
  string.split(html, "id=\"guide-race-demo\"") |> list.length |> should.equal(2)
  [
    "Client A retro board replica",
    "Client B retro board replica",
    "ship week went smoothly",
    "Went well",
    "Link latency",
    "Add two notes at once",
    "Cast three votes",
    "Sequenced operations, newest first",
    "<noscript>",
    "The live race needs JavaScript",
    "The live race couldn&#39;t start",
    "data-testid=\"race-votes\"",
    "hidden",
    "aria-live=\"polite\"",
  ]
  |> list.each(fn(text) {
    let assert True = string.contains(html, text) as text
  })
}

pub fn simulated_race_and_reset_test() {
  let #(ready, rig) = guide_race_runtime_test.ready()
  let app =
    simulate.application(
      init: fn(_) { #(ready, effect.none()) },
      update: runtime.update,
      view: view.view(_, options()),
    )
  let simulation =
    simulate.start(app, Nil)
    |> simulate.event(target("race-add"), "click", [])
  simulate.model(simulation).race_locked |> should.be_true()
  let assert Ok(mutation) = runtime.submit_add_race(rig)
  let simulation =
    simulation |> simulate.message(runtime.AddRaceSubmitted(0, Ok(mutation)))
  { simulate.model(simulation).alpha != simulate.model(simulation).beta }
  |> should.be_true()
  let assert Ok(first) = runtime.deliver_group(rig)
  let simulation =
    simulation |> simulate.message(runtime.Delivered(0, Ok(first)))
  simulate.model(simulation).delivery_active |> should.be_true()
  let assert Ok(last) = runtime.deliver_group(rig)
  let simulation =
    simulation |> simulate.message(runtime.Delivered(0, Ok(last)))
  simulate.model(simulation).converged |> should.be_true()
  let assert Ok(button) =
    simulate.view(simulation) |> query.find(target("race-add"))
  string.contains(element.to_string(button), "disabled") |> should.be_true()
  let simulation =
    simulation |> simulate.event(target("race-reset"), "click", [])
  let assert Ok(fresh) = runtime.start_rig()
  let simulation =
    simulation |> simulate.message(runtime.ResetDone(1, Ok(fresh)))
  simulate.model(simulation).converged |> should.be_true()
  simulate.model(simulation).race_locked |> should.be_false()
  simulate.model(simulation).alpha |> should.equal(runtime.static_model().alpha)
}

pub fn latency_and_vote_events_test() {
  let #(ready, _) = guide_race_runtime_test.ready()
  let app =
    simulate.application(
      init: fn(_) { #(ready, effect.none()) },
      update: runtime.update,
      view: view.view(_, view.Options(False, False)),
    )
  let simulation =
    simulate.start(app, Nil)
    |> simulate.event(target("latency"), "input", [
      #("target", json.object([#("value", json.string("1200"))])),
    ])
  simulate.model(simulation).latency_ms |> should.equal(1200)
  simulation
  |> simulate.event(target("race-votes"), "click", [])
  |> simulate.model
  |> fn(model) { model.race_locked }
  |> should.be_true()
}

pub fn failed_effect_text_is_visible_test() {
  let model =
    runtime.update(
      runtime.static_model(),
      runtime.Started(
        0,
        Error(runtime.CannotProject(runtime.Beta, "wrong mode")),
      ),
    ).0
  let assert Ok(error) =
    view.view(model, options()) |> query.find(target("race-error"))
  string.contains(
    element.to_string(error),
    "Client B: Cannot read the board: wrong mode",
  )
  |> should.be_true()
}
