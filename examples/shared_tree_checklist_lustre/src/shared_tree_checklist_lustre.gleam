import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/id
import watershed/tree/types
import watershed/tree_kernel
import watershed_lustre
import watershed_lustre/tree

const default_host = "127.0.0.1"

const default_port = "4000"

const default_tenant = "dev-tenant"

const default_secret = "levee-dev-secret-change-in-production"

type Config {
  Config(base_url: String, socket_url: String, tenant: String, secret: String)
}

type Phase {
  Creating
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(watershed.SharedTree),
    subscription: Option(watershed.SubscriptionToken),
    checklist: checklist.Checklist,
    draft: String,
    pending: Int,
    errors: List(String),
  )
}

pub type Action {
  Add(id: String, text: String)
  Edit(id: String, text: String)
  Toggle(id: String)
  Delete(id: String)
  MoveUp(id: String)
  MoveDown(id: String)
}

type Msg {
  Created(Result(String, String))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(watershed.SharedTree, String))
  Subscribed(watershed.SubscriptionToken)
  TreeChanged(tree_kernel.TreeEvent)
  Read(Result(Option(types.TreeValue), String))
  DraftChanged(String)
  AddClicked
  EditCommitted(id: String, text: String)
  ToggleClicked(id: String)
  DeleteClicked(id: String)
  MoveUpClicked(id: String)
  MoveDownClicked(id: String)
  MutationFinished(Result(Nil, String))
}

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "replaceDocument")
fn replace_document(document_id: String) -> Nil

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn base_url(host: String, port: String) -> String {
  "http://" <> host <> ":" <> port
}

pub fn socket_url(host: String, port: String) -> String {
  "ws://" <> host <> ":" <> port <> "/socket/websocket?vsn=2.0.0"
}

pub fn creation_error(detail: String) -> String {
  "Creation failed. The service might have created a document whose ID this browser did not receive: "
  <> detail
}

fn init(_argument: Nil) -> #(Model, Effect(Msg)) {
  let host = query_parameter("host", default_host)
  let port = query_parameter("port", default_port)
  let config =
    Config(
      base_url: base_url(host, port),
      socket_url: socket_url(host, port),
      tenant: query_parameter("tenant", default_tenant),
      secret: query_parameter("secret", default_secret),
    )
  let document_id = query_parameter("document", "")
  let model =
    Model(
      config: config,
      phase: case document_id {
        "" -> Creating
        _ -> Connecting
      },
      document_id: document_id,
      document: None,
      tree: None,
      subscription: None,
      checklist: checklist.empty(),
      draft: "",
      pending: 0,
      errors: [],
    )
  case document_id {
    "" -> #(
      model,
      tree.create_dev(
        config.base_url,
        config.tenant,
        config.secret,
        document_schema.stored(),
        Some(document_schema.initial()),
        Created,
      ),
    )
    id -> #(model, connect(config, id))
  }
}

fn connect(config: Config, document_id: String) -> Effect(Msg) {
  watershed_lustre.connect_dev(
    url: config.socket_url,
    tenant: config.tenant,
    secret: config.secret,
    document: document_id,
    user_id: "checklist-" <> id.uuid_v4(),
    got_document: GotDocument,
    connected: Connected,
  )
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Created(Ok(document_id)) -> {
      replace_document(document_id)
      let model = Model(..model, phase: Connecting, document_id: document_id)
      #(model, connect(model.config, document_id))
    }
    Created(Error(detail)) -> fail(model, creation_error(detail))
    GotDocument(document) -> #(
      Model(..model, document: Some(document)),
      effect.none(),
    )
    Connected(Error(detail)) -> fail(model, detail)
    Connected(Ok(Nil)) ->
      case model.document {
        Some(document) -> #(
          model,
          tree.open(document, document_schema.view(), Opened),
        )
        None ->
          fail(model, "connection completed before the document handle arrived")
      }
    Opened(Error(detail)) -> fail(model, detail)
    Opened(Ok(shared_tree)) -> #(
      Model(..model, tree: Some(shared_tree)),
      effect.batch([
        tree.subscribe(shared_tree, Subscribed, TreeChanged),
        tree.read_root(shared_tree, Read),
      ]),
    )
    Subscribed(subscription) -> #(
      Model(..model, subscription: Some(subscription)),
      effect.none(),
    )
    TreeChanged(_) ->
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    Read(Error(detail)) -> #(append_error(model, detail), effect.none())
    Read(Ok(None)) -> fail(model, "The SharedTree root is absent")
    Read(Ok(Some(value))) ->
      case checklist.decode(value) {
        Ok(decoded) -> #(
          Model(..model, phase: Ready, checklist: decoded),
          effect.none(),
        )
        Error(detail) -> fail(model, "Invalid checklist snapshot: " <> detail)
      }
    DraftChanged(draft) -> #(Model(..model, draft: draft), effect.none())
    AddClicked ->
      mutate(Model(..model, draft: ""), Add(id.uuid_v4(), model.draft))
    EditCommitted(item_id, text) -> mutate(model, Edit(item_id, text))
    ToggleClicked(item_id) -> mutate(model, Toggle(item_id))
    DeleteClicked(item_id) -> mutate(model, Delete(item_id))
    MoveUpClicked(item_id) -> mutate(model, MoveUp(item_id))
    MoveDownClicked(item_id) -> mutate(model, MoveDown(item_id))
    MutationFinished(outcome) -> {
      let pending = case model.pending > 0 {
        True -> model.pending - 1
        False -> 0
      }
      let model = Model(..model, pending: pending)
      let model = case outcome {
        Ok(Nil) -> model
        Error(detail) -> append_error(model, detail)
      }
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    }
  }
}

pub fn prepare(
  value: checklist.Checklist,
  action: Action,
) -> Result(Option(types.Edit), String) {
  case action {
    Add(item_id, text) ->
      checklist.add(value, item_id, text) |> result.map(Some)
    Edit(item_id, text) ->
      checklist.edit(value, item_id, text) |> result.map(Some)
    Toggle(item_id) -> checklist.toggle(value, item_id) |> result.map(Some)
    Delete(item_id) -> checklist.delete(value, item_id) |> result.map(Some)
    MoveUp(item_id) -> checklist.move_up(value, item_id)
    MoveDown(item_id) -> checklist.move_down(value, item_id)
  }
}

fn mutate(model: Model, action: Action) -> #(Model, Effect(Msg)) {
  case model.tree {
    None -> #(append_error(model, "SharedTree is not ready"), effect.none())
    Some(shared_tree) ->
      case prepare(model.checklist, action) {
        Error(detail) -> #(append_error(model, detail), effect.none())
        Ok(None) -> #(model, effect.none())
        Ok(Some(edit)) -> #(
          Model(..model, pending: model.pending + 1),
          tree.perform(fn() { operation(shared_tree, edit) }, MutationFinished),
        )
      }
  }
}

fn operation(
  shared_tree: watershed.SharedTree,
  edit: types.Edit,
) -> Result(Nil, String) {
  case edit {
    types.SetField(path, value) -> watershed.tree_set(shared_tree, path, value)
    types.ClearField(path) -> watershed.tree_clear(shared_tree, path)
    types.ArrayInsert(path, index, values) ->
      watershed.tree_array_insert(shared_tree, path, index, values)
    types.ArrayRemove(path, start, end) ->
      watershed.tree_array_remove(shared_tree, path, start, end)
    types.ArrayMove(source, start, end, destination, gap) ->
      watershed.tree_array_move(
        shared_tree,
        source,
        start,
        end,
        destination,
        gap,
      )
    types.MapSet(_, _, _) -> Error("checklist does not use map edits")
    types.MapDelete(_, _) -> Error("checklist does not use map edits")
  }
}

fn fail(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Failed(detail), errors: [detail, ..model.errors]),
    effect.none(),
  )
}

fn append_error(model: Model, detail: String) -> Model {
  Model(..model, errors: [detail, ..model.errors])
}

fn view(model: Model) -> Element(Msg) {
  let checklist.Checklist(title: title, items: items) = model.checklist
  let ready = case model.phase {
    Ready -> True
    _ -> False
  }
  html.main([], [
    html.h1([], [html.text(title)]),
    html.p(
      [
        attribute.attribute("data-runtime-status", phase_name(model.phase)),
      ],
      [html.text(phase_label(model.phase))],
    ),
    html.p(
      [
        attribute.attribute("data-document-id", model.document_id),
      ],
      [html.text("document: " <> model.document_id)],
    ),
    html.form([event.on_submit(fn(_) { AddClicked })], [
      html.input([
        attribute.attribute("data-new-item", "true"),
        attribute.placeholder("New checklist item"),
        attribute.value(model.draft),
        attribute.disabled(!ready),
        event.on_input(DraftChanged),
      ]),
      html.button(
        [
          attribute.disabled(!ready || string.trim(model.draft) == ""),
          attribute.type_("submit"),
        ],
        [html.text("Add")],
      ),
    ]),
    html.ul(
      [],
      list.index_map(items, fn(item, index) {
        item_view(item, index, list.length(items), ready)
      }),
    ),
    html.p(
      [
        attribute.attribute("data-pending", int.to_string(model.pending)),
      ],
      [html.text(int.to_string(model.pending) <> " pending")],
    ),
    html.p([attribute.attribute("data-development-auth", "true")], [
      html.text(
        "Local development only: this page mints tokens with a tenant secret.",
      ),
    ]),
    html.div(
      [],
      list.map(list.reverse(model.errors), fn(error) {
        html.p([attribute.attribute("data-error", "true")], [html.text(error)])
      }),
    ),
  ])
}

fn item_view(
  item: checklist.Item,
  index: Int,
  length: Int,
  ready: Bool,
) -> Element(Msg) {
  html.li(
    [
      attribute.attribute("data-item-id", item.id),
      attribute.attribute("data-item-completed", bool_string(item.completed)),
    ],
    [
      html.input([
        attribute.type_("checkbox"),
        attribute.checked(item.completed),
        attribute.disabled(!ready),
        attribute.aria_label("Toggle " <> item.text),
        attribute.attribute("data-action", "toggle"),
        event.on_check(fn(_) { ToggleClicked(item.id) }),
      ]),
      html.input([
        attribute.type_("text"),
        attribute.value(item.text),
        attribute.disabled(!ready),
        attribute.aria_label("Edit " <> item.text),
        attribute.attribute("data-action", "edit"),
        event.on_change(fn(text) { EditCommitted(item.id, text) }),
      ]),
      html.button(
        [
          attribute.disabled(!ready || index == 0),
          attribute.attribute("data-action", "move-up"),
          event.on_click(MoveUpClicked(item.id)),
        ],
        [html.text("Up")],
      ),
      html.button(
        [
          attribute.disabled(!ready || index == length - 1),
          attribute.attribute("data-action", "move-down"),
          event.on_click(MoveDownClicked(item.id)),
        ],
        [html.text("Down")],
      ),
      html.button(
        [
          attribute.disabled(!ready),
          attribute.attribute("data-action", "delete"),
          event.on_click(DeleteClicked(item.id)),
        ],
        [html.text("Delete")],
      ),
    ],
  )
}

fn phase_name(phase: Phase) -> String {
  case phase {
    Creating -> "creating"
    Connecting -> "connecting"
    Ready -> "ready"
    Failed(_) -> "failed"
  }
}

fn phase_label(phase: Phase) -> String {
  case phase {
    Creating -> "creating document"
    Connecting -> "connecting"
    Ready -> "ready"
    Failed(detail) -> "failed: " <> detail
  }
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
