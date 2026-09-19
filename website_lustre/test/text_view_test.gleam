import gleam/list
import gleam/string
import lustre/element
import watershed_site/text/view

pub fn static_view_exposes_both_shared_text_contracts_test() {
  let html = view.static() |> element.to_string
  [
    "One shared string, live",
    "data-text-rig",
    "data-text-editor",
    "data-text-race-insert",
    "All of that, as one tag",
    "watershed-textarea",
    "data-text-element-fallback",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}
