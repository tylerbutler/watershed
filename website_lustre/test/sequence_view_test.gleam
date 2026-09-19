import gleam/list
import gleam/string
import lustre/element
import watershed_site/sequence/runtime
import watershed_site/sequence/view

pub fn static_view_exposes_the_shared_route_contract_test() {
  let html = view.static() |> element.to_string
  [
    "A shared portage route, live",
    "data-route-rig",
    "data-route",
    "data-route-actions",
    "data-route-race-move",
    "data-route-race-insert",
    "data-route-reset",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}

pub fn client_view_renders_routes_and_actions_test() {
  let html =
    runtime.ready_model()
    |> view.view(True)
    |> element.to_string

  [
    "data-mounted",
    "put-in",
    "mill-race weir",
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
