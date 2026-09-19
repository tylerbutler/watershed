import gleam/dynamic.{type Dynamic}
import lustre
import lustre/effect
import lustre/element
import watershed_site/structure_demo/model
import watershed_site/structure_demo/runtime
import watershed_site/view/home

pub type Model {
  Model(demo: model.Model, gauge_strip: home.GaugeStrip)
}

pub type Msg {
  Demo(runtime.Msg)
}

@external(javascript, "./home_ffi.mjs", "startHeroDrift")
fn start_hero_drift(root: Dynamic) -> Nil

@external(javascript, "./home_ffi.mjs", "stopHeroDrift")
fn stop_hero_drift(root: Dynamic) -> Nil

fn init() -> #(Model, effect.Effect(Msg)) {
  let #(demo, effects) = runtime.init(model.Map)
  #(
    Model(demo:, gauge_strip: home.gauge_strip_model(demo)),
    effect.batch([
      effect.map(effects, Demo),
      effect.after_paint(fn(_, root) {
        stop_hero_drift(root)
        start_hero_drift(root)
      }),
    ]),
  )
}

fn update(model: Model, message: Msg) -> #(Model, effect.Effect(Msg)) {
  let Model(demo, _) = model
  let Demo(message) = message
  let #(demo, effects) = runtime.update(demo, message)
  #(
    Model(demo:, gauge_strip: home.gauge_strip_model(demo)),
    effect.map(effects, Demo),
  )
}

fn view(model: Model) -> element.Element(Msg) {
  let Model(demo, gauge_strip) = model
  home.demo(demo, gauge_strip)
  |> element.map(Demo)
}

pub fn main() {
  let app =
    lustre.application(init: fn(_) { init() }, update: update, view: view)
  let assert Ok(_) = lustre.start(app, "#home-demo-mount", Nil)
}
