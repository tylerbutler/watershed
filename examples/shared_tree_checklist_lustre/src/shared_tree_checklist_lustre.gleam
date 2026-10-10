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
import shared_tree_checklist_lustre/history
import shared_tree_checklist_lustre/lifecycle
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
  Closed
  Failed(String)
}

type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(watershed.SharedTree),
    change_subscription: Option(watershed.SubscriptionToken),
    commit_subscription: Option(watershed.SubscriptionToken),
    checklist: checklist.Checklist,
    history: history.History(watershed.TreeRevertible),
    history_action: Option(lifecycle.Action),
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
  ChangeSubscribed(watershed.SubscriptionToken)
  CommitSubscribed(watershed.SubscriptionToken)
  TreeChanged(tree_kernel.TreeEvent)
  CommitCaptured(Result(tree.CommitEvent, String))
  CommitSettled(Result(types.TreeCommitOutcome, String))
  Read(Result(Option(types.TreeValue), String))
  DraftChanged(String)
  AddClicked
  EditCommitted(id: String, text: String)
  ToggleClicked(id: String)
  DeleteClicked(id: String)
  MoveUpClicked(id: String)
  MoveDownClicked(id: String)
  UndoClicked
  RedoClicked
  CompleteAllClicked
  ClearHistoryClicked
  CloseClicked
  MutationFinished(Result(Nil, String))
  HistoryFinished(Result(Nil, String))
  BulkFinished(Result(Bool, watershed.TreeTransactionError(String)))
  Disposed(Result(Nil, String))
  CloseFinished(Result(Nil, String))
}

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "currentOrigin")
fn current_origin() -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "proxyFloodgateHttp")
fn proxy_floodgate_http(upstream: String) -> Nil

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
  let floodgate_url = base_url(default_host, default_port)
  proxy_floodgate_http(floodgate_url)
  let config =
    Config(
      base_url: query_parameter("base", current_origin()),
      socket_url: socket_url(default_host, default_port),
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
      change_subscription: None,
      commit_subscription: None,
      checklist: checklist.empty(),
      history: history.new(),
      history_action: None,
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
        tree.subscribe(shared_tree, ChangeSubscribed, TreeChanged),
        tree.subscribe_commits(
          shared_tree,
          CommitSubscribed,
          CommitCaptured,
          CommitSettled,
        ),
        tree.read_root(shared_tree, Read),
      ]),
    )
    ChangeSubscribed(subscription) ->
      case lifecycle.subscription(model.phase != Closed, subscription) {
        lifecycle.Unsubscribe(subscription) -> #(
          model,
          tree.unsubscribe(subscription),
        )
        lifecycle.Retain(subscription) -> #(
          Model(..model, change_subscription: Some(subscription)),
          effect.none(),
        )
      }
    CommitSubscribed(subscription) ->
      case lifecycle.subscription(model.phase != Closed, subscription) {
        lifecycle.Unsubscribe(subscription) -> #(
          model,
          tree.unsubscribe(subscription),
        )
        lifecycle.Retain(subscription) -> #(
          Model(..model, commit_subscription: Some(subscription)),
          effect.none(),
        )
      }
    TreeChanged(_) ->
      case model.phase, model.tree {
        Closed, _ | _, None -> #(model, effect.none())
        _, Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
      }
    CommitCaptured(outcome) -> {
      let outcome =
        result.map(outcome, fn(event) {
          let tree.CommitEvent(kind, local, revertible) = event
          #(kind, local, revertible)
        })
      let lifecycle.Transition(next, dispose, error) =
        lifecycle.captured(
          lifecycle_state(Model(..model, history: valid_history(model.history))),
          model.phase == Ready,
          outcome,
        )
      let model = apply_lifecycle(model, next)
      let model = case error {
        Some(detail) -> append_error(model, detail)
        None -> model
      }
      dispose_handles(model, dispose)
    }
    CommitSettled(outcome) ->
      case lifecycle.settled(outcome) {
        Some(detail) -> #(append_error(model, detail), effect.none())
        None -> #(model, effect.none())
      }
    Read(Error(detail)) -> #(append_error(model, detail), effect.none())
    Read(Ok(None)) -> fail(model, "The SharedTree root is absent")
    Read(Ok(Some(value))) ->
      case model.phase {
        Closed -> #(model, effect.none())
        _ ->
          case checklist.decode(value) {
            Ok(decoded) -> #(
              Model(..model, phase: Ready, checklist: decoded),
              effect.none(),
            )
            Error(detail) ->
              fail(model, "Invalid checklist snapshot: " <> detail)
          }
      }
    DraftChanged(draft) -> #(Model(..model, draft: draft), effect.none())
    AddClicked ->
      mutate(Model(..model, draft: ""), Add(id.uuid_v4(), model.draft))
    EditCommitted(item_id, text) -> mutate(model, Edit(item_id, text))
    ToggleClicked(item_id) -> mutate(model, Toggle(item_id))
    DeleteClicked(item_id) -> mutate(model, Delete(item_id))
    MoveUpClicked(item_id) -> mutate(model, MoveUp(item_id))
    MoveDownClicked(item_id) -> mutate(model, MoveDown(item_id))
    UndoClicked -> request_history(model, lifecycle.Undoing)
    RedoClicked -> request_history(model, lifecycle.Redoing)
    CompleteAllClicked -> request_complete_all(model)
    ClearHistoryClicked ->
      case can_interact(model) {
        False -> #(model, effect.none())
        True -> {
          let history.Routed(empty, dispose) =
            history.clear(valid_history(model.history))
          dispose_handles(Model(..model, history: empty), dispose)
        }
      }
    CloseClicked -> close_document(model)
    MutationFinished(outcome) -> {
      let model = finish_pending(model)
      let model = case outcome {
        Ok(Nil) -> model
        Error(detail) -> append_error(model, detail)
      }
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    }
    HistoryFinished(outcome) -> {
      let lifecycle.Transition(next, _, error) =
        lifecycle.history_finished(lifecycle_state(model), outcome)
      let model = apply_lifecycle(model, next)
      let model = case error {
        Some(detail) -> append_error(model, detail)
        None -> model
      }
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    }
    BulkFinished(outcome) -> {
      let model = finish_pending(model)
      let model = case outcome {
        Ok(_) -> model
        Error(watershed.Aborted(detail)) ->
          append_error(model, "Complete all aborted: " <> detail)
        Error(watershed.TransactionFailed(detail)) ->
          append_error(model, "Complete all failed: " <> detail)
      }
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    }
    Disposed(outcome) -> {
      let lifecycle.Disposal(next, error, _) =
        lifecycle.disposal_finished(lifecycle_state(model), outcome)
      let model = apply_lifecycle(model, next)
      let model = case error {
        Some(detail) -> append_error(model, detail)
        None -> model
      }
      continue_close(model)
    }
    CloseFinished(outcome) -> {
      let model = finish_pending(model)
      case outcome {
        Ok(Nil) -> #(model, effect.none())
        Error(detail) -> #(
          append_error(model, "Close failed: " <> detail),
          effect.none(),
        )
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

pub fn complete_all(shared_tree: watershed.SharedTree) -> Result(Bool, String) {
  use root <- result.try(watershed.tree_get(shared_tree, []))
  use value <- result.try(
    root
    |> option.to_result("The SharedTree root is absent"),
  )
  use decoded <- result.try(checklist.decode(value))
  let checklist.Checklist(items: items, ..) = decoded
  complete_incomplete(shared_tree, items, 0, False)
}

fn complete_incomplete(
  shared_tree: watershed.SharedTree,
  items: List(checklist.Item),
  index: Int,
  changed: Bool,
) -> Result(Bool, String) {
  case items {
    [] -> Ok(changed)
    [item, ..rest] -> {
      use _ <- result.try(case item.completed {
        True -> Ok(Nil)
        False ->
          watershed.tree_set(
            shared_tree,
            ["items", int.to_string(index), "completed"],
            types.BooleanValue(True),
          )
      })
      complete_incomplete(
        shared_tree,
        rest,
        index + 1,
        changed || !item.completed,
      )
    }
  }
}

fn request_history(
  model: Model,
  action: lifecycle.Action,
) -> #(Model, Effect(Msg)) {
  case can_interact(model) {
    False -> #(model, effect.none())
    True -> {
      let current = Model(..model, history: valid_history(model.history))
      let #(next, handle) = lifecycle.request(lifecycle_state(current), action)
      case handle {
        None -> #(apply_lifecycle(current, next), effect.none())
        Some(handle) -> #(
          apply_lifecycle(current, next),
          tree.revert(handle, True, HistoryFinished),
        )
      }
    }
  }
}

fn request_complete_all(model: Model) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.tree {
    True, Some(shared_tree) -> #(
      Model(..model, pending: model.pending + 1),
      tree.transaction(shared_tree, [], complete_all, BulkFinished),
    )
    True, None -> #(
      append_error(model, "SharedTree is not ready"),
      effect.none(),
    )
    False, _ -> #(model, effect.none())
  }
}

fn mutate(model: Model, action: Action) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.tree {
    False, _ -> #(model, effect.none())
    True, None -> #(
      append_error(model, "SharedTree is not ready"),
      effect.none(),
    )
    True, Some(shared_tree) ->
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

fn close_document(model: Model) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.document {
    False, _ -> #(model, effect.none())
    True, None -> #(append_error(model, "Document is not ready"), effect.none())
    True, Some(document) -> {
      let lifecycle.Close(next, unsubscribe, dispose) =
        lifecycle.close(
          lifecycle_state(Model(..model, history: valid_history(model.history))),
          model.change_subscription,
          model.commit_subscription,
        )
      let unsubscribe = list.map(unsubscribe, tree.unsubscribe)
      let cleanup =
        list.map(dispose, fn(handle) {
          tree.dispose_revertible(handle, Disposed)
        })
      let model =
        Model(
          ..model,
          phase: Closed,
          tree: None,
          change_subscription: None,
          commit_subscription: None,
          history: next.history,
          history_action: next.action,
          pending: next.pending,
        )
      case dispose {
        [] -> {
          let #(model, close) = start_close(model, document)
          #(model, effect.batch(list.append(unsubscribe, [close])))
        }
        _ -> #(model, effect.batch(list.append(unsubscribe, cleanup)))
      }
    }
  }
}

fn dispose_handles(
  model: Model,
  handles: List(watershed.TreeRevertible),
) -> #(Model, Effect(Msg)) {
  let handles =
    list.filter(handles, fn(handle) {
      watershed.tree_revertible_status(handle) == watershed.RevertibleValid
    })
  case handles {
    [] -> #(model, effect.none())
    _ -> #(
      Model(..model, pending: model.pending + list.length(handles)),
      handles
        |> list.map(fn(handle) { tree.dispose_revertible(handle, Disposed) })
        |> effect.batch,
    )
  }
}

fn continue_close(model: Model) -> #(Model, Effect(Msg)) {
  case model.phase, model.pending, model.document {
    Closed, 0, Some(document) -> start_close(model, document)
    _, _, _ -> #(model, effect.none())
  }
}

fn start_close(
  model: Model,
  document: watershed.Document(Nil),
) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, document: None, pending: model.pending + 1),
    tree.perform(
      fn() {
        watershed.close(document)
        Ok(Nil)
      },
      CloseFinished,
    ),
  )
}

fn valid_history(
  value: history.History(watershed.TreeRevertible),
) -> history.History(watershed.TreeRevertible) {
  history.prune(value, fn(handle) {
    watershed.tree_revertible_status(handle) == watershed.RevertibleValid
  })
}

fn can_interact(model: Model) -> Bool {
  model.phase == Ready && model.pending == 0 && model.history_action == None
}

fn lifecycle_state(model: Model) -> lifecycle.State(watershed.TreeRevertible) {
  lifecycle.State(
    history: model.history,
    action: model.history_action,
    pending: model.pending,
  )
}

fn apply_lifecycle(
  model: Model,
  state: lifecycle.State(watershed.TreeRevertible),
) -> Model {
  Model(
    ..model,
    history: state.history,
    history_action: state.action,
    pending: state.pending,
  )
}

fn finish_pending(model: Model) -> Model {
  Model(..model, pending: case model.pending > 0 {
    True -> model.pending - 1
    False -> 0
  })
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
  let ready = can_interact(model)
  let history.History(undo: undo, redo: redo) = valid_history(model.history)
  let undo_count = list.length(undo)
  let redo_count = list.length(redo)
  let has_incomplete = list.any(items, fn(item) { !item.completed })
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
          attribute.attribute("data-action", "add"),
        ],
        [html.text("Add")],
      ),
    ]),
    html.div([attribute.attribute("data-history-controls", "true")], [
      html.button(
        [
          attribute.disabled(!ready || undo_count == 0),
          attribute.attribute("data-action", "undo"),
          event.on_click(UndoClicked),
        ],
        [html.text("Undo")],
      ),
      html.button(
        [
          attribute.disabled(!ready || redo_count == 0),
          attribute.attribute("data-action", "redo"),
          event.on_click(RedoClicked),
        ],
        [html.text("Redo")],
      ),
      html.button(
        [
          attribute.disabled(!ready || !has_incomplete),
          attribute.attribute("data-action", "complete-all"),
          event.on_click(CompleteAllClicked),
        ],
        [html.text("Complete all")],
      ),
      html.button(
        [
          attribute.disabled(!ready || undo_count + redo_count == 0),
          attribute.attribute("data-action", "clear-history"),
          event.on_click(ClearHistoryClicked),
        ],
        [html.text("Clear history")],
      ),
      html.button(
        [
          attribute.disabled(!ready),
          attribute.attribute("data-action", "close"),
          event.on_click(CloseClicked),
        ],
        [html.text("Close")],
      ),
    ]),
    html.p(
      [
        attribute.attribute("data-undo-count", int.to_string(undo_count)),
        attribute.attribute("data-redo-count", int.to_string(redo_count)),
      ],
      [
        html.text(
          int.to_string(undo_count)
          <> " undo · "
          <> int.to_string(redo_count)
          <> " redo",
        ),
      ],
    ),
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
    Closed -> "closed"
    Failed(_) -> "failed"
  }
}

fn phase_label(phase: Phase) -> String {
  case phase {
    Creating -> "creating document"
    Connecting -> "connecting"
    Ready -> "ready"
    Closed -> "closed"
    Failed(detail) -> "failed: " <> detail
  }
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
