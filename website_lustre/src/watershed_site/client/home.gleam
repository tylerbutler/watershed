import gleam/option
import watershed_site/client/structure_demo
import watershed_site/structure_demo/model
import watershed_site/structure_demo/view

@external(javascript, "./home_ffi.mjs", "enhance")
fn enhance() -> Nil

pub fn main() {
  structure_demo.mount(
    "#home-structure-demo-mount",
    model.Map,
    view.Options(True, ["map"], option.None),
  )
  enhance()
}
