import gleam/list
import gleam/string
import gleeunit/should
import lustre/dev/query
import lustre/element
import watershed_site/directory/runtime
import watershed_site/directory/view

fn target(id: String) {
  query.element(query.attribute("data-testid", id))
}

pub fn static_view_preserves_fallback_content_test() {
  let html = view.static() |> element.to_string
  [
    "A shared folder tree, live",
    "Client A replica",
    "Client B replica",
    "Client C replica",
    "Race the same folder",
    "Build sample tree",
    "The live demo needs JavaScript",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
}

pub fn ready_view_renders_root_actions_test() {
  let assert Ok(rig) = runtime.start_rig()
  let model = runtime.update(runtime.init().0, runtime.Started(0, Ok(rig))).0
  let rendered = view.view(model, view.Options(False))
  rendered
  |> query.find_all(query.element(query.class("dir-node")))
  |> list.length
  |> should.equal(3)
  let assert Ok(add_folder) =
    rendered |> query.find(target("add-folder-a-root"))
  string.contains(
    element.to_string(add_folder),
    "Add a folder under / on Client A",
  )
  |> should.be_true()
}
