import gleam/json
import gleam/option.{type Option, None, Some}

import lustre/effect.{type Effect}

import watershed
import watershed/rich_text
import watershed/rich_text_kernel
import watershed/transport_js

pub type Editor

pub opaque type Model {
  Model(
    channel: watershed.SharedRichText,
    editor: transport_js.Cell(Option(Editor)),
    subscription: transport_js.Cell(Option(watershed.SubscriptionToken)),
    stopped: transport_js.Cell(Bool),
    last_error: Option(String),
  )
}

pub type Msg {
  Mounted(Editor)
  ChannelChanged(rich_text_kernel.RichTextEvent)
  MountFailed(String)
}

@external(javascript, "./rich_editor_ffi.mjs", "mount")
fn mount_ffi(
  element_id: String,
  initial_document: String,
  on_user_delta: fn(String) -> Nil,
  on_error: fn(String) -> Nil,
) -> Editor

@external(javascript, "./rich_editor_ffi.mjs", "applyRemote")
fn apply_remote_ffi(editor: Editor, delta: String) -> Nil

@external(javascript, "./rich_editor_ffi.mjs", "destroy")
fn destroy_ffi(editor: Editor) -> Nil

pub fn init(
  element_id: String,
  channel: watershed.SharedRichText,
) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      channel:,
      editor: transport_js.new_cell(None),
      subscription: transport_js.new_cell(None),
      stopped: transport_js.new_cell(False),
      last_error: None,
    )
  #(model, mount_effect(model, element_id))
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case transport_js.get_cell(model.stopped) {
    True -> #(model, effect.none())
    False ->
      case msg {
        Mounted(editor) -> {
          transport_js.set_cell(model.editor, Some(editor))
          #(model, effect.none())
        }
        ChannelChanged(rich_text_kernel.RichTextChanged(_, True)) -> #(
          model,
          effect.none(),
        )
        ChannelChanged(rich_text_kernel.RichTextChanged(delta, False)) -> {
          case transport_js.get_cell(model.editor) {
            Some(editor) -> apply_remote_ffi(editor, delta_json(delta))
            None -> Nil
          }
          #(model, effect.none())
        }
        MountFailed(reason) -> #(
          Model(..model, last_error: Some(reason)),
          effect.none(),
        )
      }
  }
}

pub fn channel(model: Model) -> watershed.SharedRichText {
  model.channel
}

pub fn error(model: Model) -> Option(String) {
  model.last_error
}

pub fn stop(model: Model) -> Nil {
  case transport_js.get_cell(model.stopped) {
    True -> Nil
    False -> {
      transport_js.set_cell(model.stopped, True)
      case transport_js.get_cell(model.subscription) {
        Some(subscription) -> {
          watershed.unsubscribe(subscription)
          transport_js.set_cell(model.subscription, None)
        }
        None -> Nil
      }
      case transport_js.get_cell(model.editor) {
        Some(editor) -> {
          destroy_ffi(editor)
          transport_js.set_cell(model.editor, None)
        }
        None -> Nil
      }
    }
  }
}

fn mount_effect(model: Model, element_id: String) -> Effect(Msg) {
  use dispatch <- effect.from
  case transport_js.get_cell(model.stopped) {
    True -> Nil
    False ->
      case watershed.rich_text_view(model.channel) {
        Error(_) -> dispatch(MountFailed("rich-text channel is unavailable"))
        Ok(document) -> {
          let subscription =
            watershed.subscribe_rich_text(model.channel, fn(event) {
              case event, transport_js.get_cell(model.stopped) {
                rich_text_kernel.RichTextChanged(_, True), _ -> Nil
                _, True -> Nil
                _, False -> dispatch(ChannelChanged(event))
              }
            })
          transport_js.set_cell(model.subscription, Some(subscription))

          let editor =
            mount_ffi(
              element_id,
              document_json(document),
              fn(raw_delta) {
                case transport_js.get_cell(model.stopped) {
                  True -> Nil
                  False ->
                    case rich_text.parse_delta(raw_delta) {
                      Ok(delta) ->
                        watershed.submit_rich_text(model.channel, delta)
                      Error(_) ->
                        dispatch(MountFailed(
                          "rich editor rejected a user delta",
                        ))
                    }
                }
              },
              fn(reason) {
                case transport_js.get_cell(model.stopped) {
                  True -> Nil
                  False -> dispatch(MountFailed(reason))
                }
              },
            )

          case transport_js.get_cell(model.stopped) {
            True -> {
              watershed.unsubscribe(subscription)
              transport_js.set_cell(model.subscription, None)
              destroy_ffi(editor)
            }
            False -> {
              transport_js.set_cell(model.editor, Some(editor))
              dispatch(Mounted(editor))
            }
          }
        }
      }
  }
}

fn delta_json(delta: rich_text.Delta) -> String {
  delta |> rich_text.delta_to_json |> json.to_string
}

fn document_json(document: rich_text.Document) -> String {
  document |> rich_text.document_to_json |> json.to_string
}
