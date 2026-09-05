import gleam/dynamic.{type Dynamic}
import lustre
import lustre/effect
import watershed_site/guide_race/runtime
import watershed_site/guide_race/view

@external(javascript, "./guide_race_ffi.mjs", "animateFlows")
fn animate_flows(root: Dynamic, duration: Int) -> Result(Nil, String)

pub fn main() {
  let app =
    lustre.application(
      init: fn(_) { runtime.init() },
      update: fn(model, message) {
        let #(model, effects) = runtime.update(model, message)
        #(
          model,
          effect.batch([
            effects,
            effect.after_paint(fn(dispatch, root) {
              case animate_flows(root, model.latency_ms) {
                Ok(Nil) -> Nil
                Error(reason) -> dispatch(runtime.AnimationFailed(reason))
              }
            }),
          ]),
        )
      },
      view: view.view(_, view.Options(True, False)),
    )
  let assert Ok(_) = lustre.start(app, "#guide-race-mount", Nil)
}
