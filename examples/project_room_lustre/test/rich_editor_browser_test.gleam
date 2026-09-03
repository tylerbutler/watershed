import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element/html

import watershed
import watershed/rich_text
import watershed/sluice_js

import project_room_lustre/rich_editor

type Model {
  Model(editor: rich_editor.Model, status: String)
}

type Msg {
  EditorMessage(rich_editor.Msg)
}

@external(javascript, "./rich_editor_browser_test_ffi.mjs", "recordMounted")
fn record_mounted(editor: rich_editor.Editor) -> Nil

fn channel() -> watershed.SharedRichText {
  let sluice =
    sluice_js.start(tenant: "default", document: "rich-editor-browser")
  let document = sluice_js.connect(sluice, "browser")
  sluice_js.settle(sluice)
  let assert Ok(channel) = watershed.create_rich_text(document)
  let assert Ok(initial) =
    rich_text.parse_delta(
      "[{\"insert\":\"Heading\"},{\"insert\":\"\\n\",\"attributes\":{\"header\":1}}]",
    )
  watershed.submit_rich_text(channel, initial)
  channel
}

fn init(_arguments: Nil) -> #(Model, Effect(Msg)) {
  let #(editor, editor_effect) = rich_editor.init("editor", channel())
  #(Model(editor:, status: "waiting"), effect.map(editor_effect, EditorMessage))
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  let EditorMessage(editor_message) = message
  let #(editor, editor_effect) =
    rich_editor.update(model.editor, editor_message)
  let status = case editor_message {
    rich_editor.Mounted(mounted) -> {
      record_mounted(mounted)
      "mounted"
    }
    rich_editor.MountFailed(reason) -> "failed: " <> reason
    rich_editor.ChannelChanged(_) -> model.status
  }
  #(Model(editor:, status:), effect.map(editor_effect, EditorMessage))
}

fn view(model: Model) {
  html.div([], [
    html.div([attribute.id("editor")], []),
    html.p([attribute.id("status")], [html.text(model.status)]),
  ])
}

pub fn start() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
