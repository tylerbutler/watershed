import gleam/option
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/structure_demo/model
import watershed_site/structure_demo/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view(body: List(Element(Nil))) -> Element(Nil) {
  sheet.view("/mv-register/", [
    hero(),
    h.main([], [
      h.div([a.id("mv-register-demo-mount")], [
        demo.static(
          model.MvRegister,
          demo.Options(True, ["mv-register"], option.None),
        ),
      ]),
      h.section([a.class("mv-notes"), a.id("after-demo")], body),
    ]),
    ecosystem.view("/mv-register/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("mv-hero")], [
    h.p([a.class("annot")], [
      h.a([a.href("/structures/registers")], [h.text("Registers")]),
      h.text(" / Revision slate"),
    ]),
    h.h1([], [
      h.text("Converged."),
      h.br([]),
      h.text("Still "),
      h.em([], [h.text("two answers.")]),
    ]),
    h.p([], [
      h.text(
        "A last-write-wins cell would discard one revision. This one keeps the disagreement. Race \"raise crest\" against \"arm pump\": all three clients reach the same two alternatives. Nothing is stuck in transit.",
      ),
    ]),
    h.p([], [
      h.text(
        "Once you've read both, resolve with \"raise crest + arm pump\". That's an ordinary write, not a special conflict API. An unseen third revision would survive it.",
      ),
    ]),
  ])
}
