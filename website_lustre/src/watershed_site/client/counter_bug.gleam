import lustre
import watershed_site/counter_bug/view

pub fn main() {
  let app =
    lustre.application(
      init: fn(_) { view.init() },
      update: view.update,
      view: fn(model) { view.view(model, False) },
    )
  let assert Ok(_) = lustre.start(app, "#counter-bug-mount", Nil)
}
