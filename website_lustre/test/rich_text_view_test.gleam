import gleam/list
import gleam/string
import lustre/element
import watershed_site/rich_text/view

pub fn static_view_exposes_the_quill_runtime_contract_test() {
  let html = view.static() |> element.to_string
  [
    "SharedRichText, live",
    "data-rt-rig",
    "data-quill-root",
    "data-canonical",
    "data-peer-list",
    "data-rt-race-type",
    "data-rt-race-format",
    "data-rt-race-delete",
    "data-rt-embed",
    "data-rt-step",
    "data-rt-settle",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}
