import gleam/list
import gleam/string
import lustre/element
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
