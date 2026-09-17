import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/option.{None, Some}
import lustre
import lustre/effect
import watershed_site/sudoku/runtime
import watershed_site/sudoku/view

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
        let focus_id = case model.focus {
          None -> ""
          Some(runtime.Focus(replica, row, column)) ->
            "cell-"
            <> runtime.replica_id(replica)
            <> "-"
            <> int.to_string(row)
            <> "-"
            <> int.to_string(column)
        }
        #(
          model,
          effect.batch([
            effects,
            case model.phase == runtime.Failed {
              True -> effect.none()
              False ->
                effect.after_paint(fn(dispatch, root) {
                  case
                    sync_dom(root, model.pace_quarters, model.jitter, focus_id)
                  {
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
  let assert Ok(_) = lustre.start(app, "#sudoku-mount", Nil)
}
