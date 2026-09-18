import gleam/list
import gleam/string
import lustre/element
import watershed_site/view/home

pub fn home_preserves_the_live_map_and_field_atlas_contract_test() {
  let html = home.view([]) |> element.to_string
  [
    "Collaborative data structures",
    "data-demo-rig",
    "data-client=\"a\"",
    "data-demo-fallback",
    "Watch a boat vanish, live",
    "field atlas",
    "One pure core, two runtimes",
    "What is implemented and tested",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}
