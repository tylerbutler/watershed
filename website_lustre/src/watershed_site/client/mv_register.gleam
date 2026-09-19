import gleam/option
import watershed_site/client/structure_demo
import watershed_site/structure_demo/model
import watershed_site/structure_demo/view

pub fn main() {
  structure_demo.mount(
    "#mv-register-demo-mount",
    model.MvRegister,
    view.Options(True, ["mv-register"], option.None),
  )
}
