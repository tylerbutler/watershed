import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option, None, Some}
import lustre
import lustre/effect
import watershed.{type SharedText}
import watershed_site/text/runtime
import watershed_site/text/view

@external(javascript, "./text_ffi.mjs", "syncEditors")
fn sync_editors(
  root: Dynamic,
  channel_a: SharedText,
  channel_b: SharedText,
  cursor_a: String,
  cursor_b: String,
  on_change_a: fn() -> Nil,
  on_change_b: fn() -> Nil,
  on_cursor_a: fn(String) -> Nil,
  on_cursor_b: fn(String) -> Nil,
  on_error_a: fn(String) -> Nil,
  on_error_b: fn(String) -> Nil,
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
            case
              runtime.channel(model, runtime.ElementA),
              runtime.channel(model, runtime.ElementB)
            {
              Some(channel_a), Some(channel_b) ->
                effect.after_paint(fn(dispatch, root) {
                  case
                    sync_editors(
                      root,
                      channel_a,
                      channel_b,
                      runtime.peer_cursor(model, runtime.ElementA)
                        |> cursor_or_empty,
                      runtime.peer_cursor(model, runtime.ElementB)
                        |> cursor_or_empty,
                      fn() {
                        dispatch(runtime.ElementChanged(runtime.ElementA))
                      },
                      fn() {
                        dispatch(runtime.ElementChanged(runtime.ElementB))
                      },
                      fn(payload) {
                        dispatch(runtime.CursorChanged(
                          runtime.ElementA,
                          payload,
                        ))
                      },
                      fn(payload) {
                        dispatch(runtime.CursorChanged(
                          runtime.ElementB,
                          payload,
                        ))
                      },
                      fn(reason) {
                        dispatch(runtime.EditorFailed(runtime.ElementA, reason))
                      },
                      fn(reason) {
                        dispatch(runtime.EditorFailed(runtime.ElementB, reason))
                      },
                    )
                  {
                    Ok(Nil) -> Nil
                    Error(reason) ->
                      dispatch(runtime.EditorFailed(runtime.ElementA, reason))
                  }
                })
              _, _ -> effect.none()
            },
          ]),
        )
      },
      view: view.view(_, False),
    )
  let assert Ok(_) = lustre.start(app, "#text-mount", Nil)
}

fn cursor_or_empty(cursor: Option(String)) -> String {
  case cursor {
    Some(payload) -> payload
    None -> ""
  }
}
