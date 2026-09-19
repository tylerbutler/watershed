import lustre
import watershed_site/structure_demo/family as family_view
import watershed_site/structure_demo/model.{type Structure}
import watershed_site/structure_demo/runtime
import watershed_site/structure_demo/view
import watershed_site/structures

@external(javascript, "./structure_demo_ffi.mjs", "familySlug")
fn family_slug() -> String

@external(javascript, "./structure_demo_ffi.mjs", "setupDemo")
pub fn setup_demo(selector: String) -> Nil

pub fn mount(
  selector: String,
  selected: Structure,
  options: view.Options,
) -> Nil {
  let app =
    lustre.application(
      init: fn(_) { runtime.init(selected) },
      update: runtime.update,
      view: fn(model) { view.view(model, options) },
    )
  let assert Ok(_) = lustre.start(app, selector, Nil)
  setup_demo(selector)
  Nil
}

pub fn mount_family() -> Nil {
  let assert Ok(family) = structures.get(family_slug())
  let selected = family_view.first_structure(family)
  let app =
    lustre.application(
      init: fn(_) { runtime.init(selected) },
      update: runtime.update,
      view: fn(model) { family_view.view(family, model) },
    )
  let assert Ok(_) = lustre.start(app, "#structure-sheet-mount", Nil)
  setup_demo("#structure-sheet-mount")
  Nil
}
