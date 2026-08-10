import lustre
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

import watershed/browser

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("grocery-triptych")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

type Model {
  Model(document: String)
}

fn init(document: String) -> #(Model, Effect(Nil)) {
  #(Model(document: document), effect.none())
}

fn update(model: Model, _msg: Nil) -> #(Model, Effect(Nil)) {
  #(model, effect.none())
}

fn view(model: Model) -> Element(Nil) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · grocery triptych")]),
    html.p([class("status")], [
      html.text("scaffold only · document " <> model.document),
    ]),
    html.section([class("panel")], [
      html.h2([], [html.text("Pantry channels")]),
      html.div([class("pantry")], [
        card("grow_only", "GSet"),
        card("two_phase", "TwoPSet"),
        card("observed", "OrSet"),
      ]),
    ]),
  ])
}

fn card(name: String, kind: String) -> Element(Nil) {
  html.article([class("card")], [
    html.h2([], [html.text(name)]),
    html.p([], [html.text("tagged by Pantry · " <> kind)]),
  ])
}
