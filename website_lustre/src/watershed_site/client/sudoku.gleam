import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/option.{Some}
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
        let request_focus = case message {
          runtime.SetCell(_, _, _, _)
          | runtime.ClearCell(_, _, _)
          | runtime.CycleCell(_, _, _)
          | runtime.CellKey(_, _, _, _)
          | runtime.MoveFocus(_, _, _) -> True
          _ -> False
        }
        let focus_id = case request_focus, model.focus {
          True, Some(runtime.Focus(replica, row, column)) ->
            "cell-"
            <> runtime.replica_id(replica)
            <> "-"
            <> int.to_string(row)
            <> "-"
            <> int.to_string(column)
          _, _ -> ""
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
