import gleam/list
import gleam/string
import lustre/element
import watershed_site/mv_register/view

pub fn static_view_exposes_the_revision_slate_contract_test() {
  let html = view.static() |> element.to_string
  [
    "One slate, three field crews",
    "data-demo-rig",
    "data-dds=\"mv-register\"",
    "data-mv-register-input",
    "data-mv-register-write",
    "data-mv-register-resolve",
    "data-cut-link",
    "data-replay",
    "data-reset",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}
