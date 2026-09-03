import gleam/dynamic
import gleeunit/should

import lustre/effect

import watershed
import watershed/rich_text
import watershed/rich_text_kernel
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/rich_editor

@external(javascript, "./rich_editor_test_ffi.mjs", "fakeEditor")
fn fake_editor(on_update: fn() -> Nil) -> rich_editor.Editor

@external(javascript, "./rich_editor_test_ffi.mjs", "editorDestroyed")
fn editor_destroyed(editor: rich_editor.Editor) -> Bool

fn channel(name: String) -> watershed.SharedRichText {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let assert Ok(channel) = watershed.create_rich_text(document)
  channel
}

fn delta(text: String) -> rich_text.Delta {
  let assert Ok(delta) =
    rich_text.delta_insert_text(
      rich_text.empty_delta(),
      text,
      rich_text.attributes([]),
    )
  delta
}

fn run(effect_to_run: effect.Effect(msg), dispatch: fn(msg) -> Nil) -> Nil {
  effect.perform(
    effect_to_run,
    dispatch,
    fn(_name, _payload) { Nil },
    fn(_selector) { Nil },
    fn() { dynamic.nil() },
    fn(_name, _payload) { Nil },
    fn(_name, _decoder) { Nil },
    fn(_name) { Nil },
  )
}

pub fn remote_editor_work_runs_in_an_effect_test() -> Nil {
  let #(model, _mount) = rich_editor.init("editor", channel("editor-remote"))
  let calls = transport_js.new_cell(0)
  let editor =
    fake_editor(fn() {
      transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
    })
  let #(model, _) = rich_editor.update(model, rich_editor.Mounted(editor))

  let #(_model, remote) =
    rich_editor.update(
      model,
      rich_editor.ChannelChanged(rich_text_kernel.RichTextChanged(
        delta("remote"),
        False,
      )),
    )

  transport_js.get_cell(calls) |> should.equal(0)
  run(remote, fn(_) { Nil })
  transport_js.get_cell(calls) |> should.equal(1)
  rich_editor.stop(model)
}

pub fn stopped_editor_destroys_late_mount_completion_test() -> Nil {
  let #(model, _mount) = rich_editor.init("editor", channel("editor-stopped"))
  let editor = fake_editor(fn() { Nil })

  rich_editor.stop(model)
  let #(_model, effect) = rich_editor.update(model, rich_editor.Mounted(editor))
  run(effect, fn(_) { Nil })

  editor_destroyed(editor) |> should.be_true
}
