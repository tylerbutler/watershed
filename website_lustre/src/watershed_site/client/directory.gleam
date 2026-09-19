import gleam/dynamic.{type Dynamic}
import lustre
import lustre/effect
import watershed_site/directory/runtime
import watershed_site/directory/view

@external(javascript, "./sudoku_ffi.mjs", "syncDom")
fn sync_dom(
  root: Dynamic,
  pace_quarters: Int,
  jitter: Bool,
  focus_id: String,
) -> Result(Nil, String)

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
            case model.phase == runtime.Failed {
              True -> effect.none()
              False ->
                effect.after_paint(fn(dispatch, root) {
                  case sync_dom(root, model.pace_quarters, model.jitter, "") {
                    Ok(Nil) -> Nil
                    Error(reason) -> dispatch(runtime.BrowserFailed(reason))
                  }
                })
            },
          ]),
        )
      },
      view: view.view(_, view.Options(False)),
    )
  let assert Ok(_) = lustre.start(app, "#directory-mount", Nil)
}
