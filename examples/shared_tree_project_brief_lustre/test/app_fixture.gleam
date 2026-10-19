import gleam/dict
import gleam/option.{None, Some}
import shared_tree_project_brief_lustre as app
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/edits
import shared_tree_project_brief_lustre/schema
import shared_tree_project_brief_lustre/selection as s
import watershed
import watershed/tree
import watershed/tree/error

pub fn model() -> app.Model {
  app.Model(
    status: "connecting",
    connection: "connecting",
    session: None,
    document_id: "project-brief",
    document: None,
    tree: None,
    subscription: None,
    rendered: None,
    review_generation: 0,
    inputs: dict.new(),
    metadata: s.Metadata("Local", s.Blue, 0, None),
    policy: s.new(),
    fresh: dict.new(),
    presence: None,
    generation: 0,
    change_count: 0,
    pending: 0,
    errors: [],
  )
}

pub fn opened(document: watershed.Document(Nil)) -> app.Model {
  let assert Ok(handle) = watershed.open_tree(document, schema.configuration())
  let assert Ok(captured) = edits.capture(handle)
  let #(model, _) =
    app.update(
      app.Model(..model(), document: Some(document), tree: Some(handle)),
      app.Captured(Ok(captured)),
    )
  let #(model, _) = app.update(model, app.Poll)
  model
}

pub fn initial() -> brief.ProjectBrief {
  brief.initial("first", "second")
}

pub fn with_review() -> brief.ProjectBrief {
  brief.ProjectBrief(..initial(), review: Some(brief.Review("Old", False)))
}

pub fn capture(model: app.Model) -> app.Msg {
  let assert Some(handle) = model.tree
  app.Captured(edits.capture(handle))
}

pub fn title_write(model: app.Model) -> fn(String) -> Result(Nil, error.Error) {
  let assert Some(captured) = model.rendered
  fn(value) { tree.set(captured.root, schema.brief_title(), value) }
}

pub fn replace_review(model: app.Model) -> Nil {
  let assert Some(captured) = model.rendered
  let assert Ok(Nil) = tree.set(captured.root, schema.review(), None)
  let assert Ok(Nil) =
    tree.set(captured.root, schema.review(), Some(brief.Review("New", False)))
  Nil
}
