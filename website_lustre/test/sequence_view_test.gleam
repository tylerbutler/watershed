import gleam/list
import gleam/string
import lustre/element
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
