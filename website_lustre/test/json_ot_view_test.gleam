import gleam/list
import gleam/string
import lustre/element
import watershed_site/json_ot/runtime
import watershed_site/json_ot/view

pub fn static_view_exposes_the_complete_runtime_contract_test() {
  let html = view.static() |> element.to_string
  [
    "Operational transform, live",
    "data-jot-rig",
    "data-stage-inc",
    "data-trend-cycle",
    "data-site-cycle",
    "data-crew-add",
    "Race two inserts at index 0",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}

pub fn client_view_renders_runtime_state_and_actions_test() {
  let html =
    runtime.ready_model()
    |> view.view(True)
    |> element.to_string

  [
    "data-mounted",
    "Ada",
    "Ben",
    "Mill Race",
    "data-testid=\"status\"",
    "data-testid=\"error\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}

pub fn client_view_can_omit_noscript_test() {
  let html =
    runtime.ready_model()
    |> view.view(False)
    |> element.to_string
  let assert False = string.contains(html, "<noscript")
}
