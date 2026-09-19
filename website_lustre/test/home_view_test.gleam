import gleam/list
import gleam/string
import lustre/element
import simplifile
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

pub fn home_has_one_lustre_owned_demo_mount_test() {
  let html = home.view([]) |> element.to_string
  let assert 2 = string.split(html, "id=\"home-demo-mount\"") |> list.length
  let assert True = string.contains(html, "data-demo-fallback")
  let assert True =
    string.contains(html, "aria-label=\"Convergence models compared\"")
  let assert False = string.contains(html, "home-structure-demo-mount")
}

pub fn home_ffi_only_owns_contour_animation_test() {
  let assert Ok(source) =
    simplifile.read("src/watershed_site/client/home_ffi.mjs")
  ["MutationObserver", "data-gauge-strip", "website" <> "/src"]
  |> list.each(fn(forbidden) {
    let assert False = string.contains(source, forbidden) as forbidden
  })
  ["startHeroDrift", "stopHeroDrift"]
  |> list.each(fn(required) {
    let assert True = string.contains(source, required) as required
  })
}
