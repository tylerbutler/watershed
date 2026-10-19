import gleam/option.{None, Some}
import gleeunit/should
import shared_tree_project_brief_lustre/input

pub fn ordinary_input_publishes_test() {
  let transition = input.changed(input.new("old"), "new")
  transition.publish |> should.equal(Some("new"))
  transition.input.value |> should.equal("new")
}

pub fn composition_defers_remote_binding_and_partial_publication_test() {
  let original = input.new("start") |> input.selected(1, 4)
  let composing = input.composition_started(original)
  let partial = input.changed(composing, "partial")
  partial.publish |> should.equal(None)
  let remote = input.remote(partial.input, "resolved")
  remote.value |> should.equal("resolved")
  remote.composing |> should.be_true
  remote.selection |> should.equal(Some(#(1, 4)))
  original.value |> should.equal("start")
}

pub fn composition_publishes_once_then_allows_real_edits_test() {
  let ended =
    input.new("")
    |> input.composition_started
    |> input.composition_ended("完成")
  ended.publish |> should.equal(Some("完成"))
  let duplicate = input.changed(ended.input, "完成")
  duplicate.publish |> should.equal(None)
  duplicate.input.composition_end |> should.equal(None)
  input.changed(duplicate.input, "完成").publish
  |> should.equal(Some("完成"))
  input.changed(duplicate.input, "完成!").publish
  |> should.equal(Some("完成!"))
  input.changed(ended.input, "different").publish
  |> should.equal(Some("different"))
}

pub fn remote_update_is_local_to_one_input_test() {
  let other = input.new("other") |> input.selected(2, 5)
  let changed = input.new("first") |> input.remote("remote")
  changed.value |> should.equal("remote")
  other |> should.equal(input.Input("other", False, None, Some(#(2, 5)), False))
}
