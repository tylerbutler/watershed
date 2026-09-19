import gleam/list
import gleam/option.{None}
import gleam/string
import lustre/element
import watershed_site/structure_demo/model.{Map, MvRegister}
import watershed_site/structure_demo/view

pub fn static_map_exposes_the_shared_demo_contract_test() {
  let html =
    view.static(Map, view.Options(False, ["map"], None))
    |> element.to_string
  [
    "data-demo-rig",
    "data-dds=\"map\"",
    "data-client=\"a\"",
    "data-step=\"1\"",
    "data-race",
    "data-reset",
  ]
  |> contains_all(html)
}

pub fn interactive_mv_register_uses_lustre_handlers_test() {
  let html =
    view.static(MvRegister, view.Options(True, ["mv-register"], None))
    |> element.to_string
  [
    "data-mv-register-input",
    "data-mv-register-write",
    "data-mv-register-resolve",
    "data-cut-link",
    "data-replay",
  ]
  |> contains_all(html)
}

fn contains_all(expected: List(String), html: String) {
  list.each(expected, fn(fragment) {
    let assert True = string.contains(html, fragment) as fragment
  })
}
