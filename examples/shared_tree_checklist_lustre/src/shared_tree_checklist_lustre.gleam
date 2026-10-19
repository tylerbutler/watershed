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
import lustre/element/keyed
import lustre/event
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/lifecycle
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/id
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed/tree/history_stack as history
import watershed/tree/types
import watershed_lustre
import watershed_lustre/tree

const default_host = "127.0.0.1"

const default_port = "4000"

const default_tenant = "dev-tenant"

const default_secret = "levee-dev-secret-change-in-production"

@internal
pub type Config {
  Config(base_url: String, socket_url: String, tenant: String, secret: String)
}

@internal
pub type Phase {
  Creating
  Connecting
  Ready
  Closed
  Failed(String)
}

@internal
pub type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(shared_tree.Tree(checklist.Checklist)),
    change_subscription: Option(shared_tree.Subscription),
    commit_subscription: Option(shared_tree.Subscription),
    checklist: checklist.Checklist,
    item_nodes: List(shared_tree.Ref(checklist.Item)),
    history: history.History(shared_tree.Revertible),
    history_action: Option(lifecycle.Action),
    draft: String,
    pending: Int,
    errors: List(String),
  )
}

@internal
pub type Msg {
  Created(Result(String, tree_error.Error))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(shared_tree.Tree(checklist.Checklist), tree_error.Error))
  ChangeSubscribed(Result(shared_tree.Subscription, tree_error.Error))
  CommitSubscribed(Result(shared_tree.Subscription, tree_error.Error))
  TreeChanged(shared_tree.ChangeEvent)
  CommitCaptured(Result(tree.CommitEvent, tree_error.Error))
  CommitSettled(Result(shared_tree.CommitOutcome, tree_error.Error))
  Read(
    Result(
      #(checklist.Checklist, List(shared_tree.Ref(checklist.Item))),
      tree_error.Error,
    ),
  )
  DraftChanged(String)
  AddClicked
  EditCommitted(item: shared_tree.Ref(checklist.Item), text: String)
  ToggleClicked(item: shared_tree.Ref(checklist.Item), completed: Bool)
  DeleteClicked(item: shared_tree.Ref(checklist.Item))
  MoveClicked(
    item: shared_tree.Ref(checklist.Item),
    before: Option(shared_tree.Ref(checklist.Item)),
  )
  UndoClicked
  RedoClicked
  CompleteAllClicked
  RunCompleteAll(shared_tree.Tree(checklist.Checklist))
  ClearHistoryClicked
  CloseClicked
  MutationFinished(Result(Nil, tree_error.Error))
  HistoryFinished(Result(Nil, tree_error.Error))
  BulkFinished(Result(Bool, shared_tree.TransactionError(tree_error.Error)))
  Disposed(Result(Nil, tree_error.Error))
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
      item_nodes: [],
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
        document_schema.configuration(),
        checklist.empty(),
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

@internal
pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Created(Ok(document_id)) -> {
      replace_document(document_id)
      let model = Model(..model, phase: Connecting, document_id: document_id)
      #(model, connect(model.config, document_id))
    }
    Created(Error(error)) ->
      fail(model, creation_error(tree_error.to_string(error)))
    GotDocument(document) -> #(
      Model(..model, document: Some(document)),
      effect.none(),
    )
    Connected(Error(detail)) -> fail(model, detail)
    Connected(Ok(Nil)) ->
      case model.document {
        Some(document) -> #(
          model,
          tree.open(document, document_schema.configuration(), Opened),
        )
        None ->
          fail(model, "connection completed before the document handle arrived")
      }
    Opened(Error(error)) -> fail(model, tree_error.to_string(error))
    Opened(Ok(shared_tree)) -> #(
      Model(..model, tree: Some(shared_tree)),
      effect.batch([
        tree.subscribe_changes(shared_tree, ChangeSubscribed, TreeChanged),
        tree.subscribe_commits(
          shared_tree,
          CommitSubscribed,
          CommitCaptured,
          CommitSettled,
        ),
        read_effect(shared_tree),
      ]),
    )
    ChangeSubscribed(Error(error)) -> fail(model, tree_error.to_string(error))
    ChangeSubscribed(Ok(subscription)) ->
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
    CommitSubscribed(Error(error)) -> fail(model, tree_error.to_string(error))
    CommitSubscribed(Ok(subscription)) ->
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
        _, Some(shared_tree) -> #(model, read_effect(shared_tree))
      }
    CommitCaptured(outcome) -> {
      let outcome = result.map_error(outcome, tree_error.to_string)
      let outcome =
        result.map(outcome, fn(event) {
          let tree.CommitEvent(kind, local, revertible) = event
          #(kind, local, revertible)
        })
      let model = refresh_history(model)
      let lifecycle.Transition(next, dispose, error) =
        lifecycle.captured(
          lifecycle_state(model),
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
    CommitSettled(outcome) -> {
      let model = refresh_history(model)
      case lifecycle.settled(result.map_error(outcome, tree_error.to_string)) {
        Some(detail) -> #(append_error(model, detail), effect.none())
        None -> #(model, effect.none())
      }
    }
    Read(Error(error)) -> #(
      append_error(model, tree_error.to_string(error)),
      effect.none(),
    )
    Read(Ok(#(decoded, item_nodes))) ->
      case model.phase {
        Closed -> #(model, effect.none())
        _ -> #(
          Model(
            ..model,
            phase: Ready,
            checklist: decoded,
            item_nodes: item_nodes,
          ),
          effect.none(),
        )
      }
    DraftChanged(draft) -> #(Model(..model, draft: draft), effect.none())
    AddClicked -> add(Model(..model, draft: ""), id.uuid_v4(), model.draft)
    EditCommitted(item, text) -> mutate(model, fn() { rename_item(item, text) })
    ToggleClicked(item, completed) ->
      mutate(model, fn() { toggle_item(item, completed) })
    DeleteClicked(item) ->
      mutate(model, fn() {
        use items <- result.try(current_items(model))
        delete_item(items, item)
      })
    MoveClicked(item, before) ->
      mutate(model, fn() {
        use items <- result.try(current_items(model))
        move_item(items, item, before)
      })
    UndoClicked -> request_history(model, lifecycle.Undoing)
    RedoClicked -> request_history(model, lifecycle.Redoing)
    CompleteAllClicked -> request_complete_all(model)
    RunCompleteAll(shared_tree) -> #(
      model,
      tree.transaction(shared_tree, [], complete_all, BulkFinished),
    )
    ClearHistoryClicked ->
      case can_interact(model) {
        False -> #(model, effect.none())
        True -> {
          let model = refresh_history(model)
          let history.Routed(empty, dispose) = history.clear(model.history)
          dispose_handles(Model(..model, history: empty), dispose)
        }
      }
    CloseClicked -> close_document(model)
    MutationFinished(outcome) -> {
      let model = finish_pending(model)
      let model = case outcome {
        Ok(Nil) -> model
        Error(error) -> append_error(model, tree_error.to_string(error))
      }
      case model.tree {
        Some(shared_tree) -> #(model, read_effect(shared_tree))
        None -> #(model, effect.none())
      }
    }
    HistoryFinished(outcome) -> {
      let lifecycle.Transition(next, _, error) =
        lifecycle.history_finished(
          lifecycle_state(model),
          result.map_error(outcome, tree_error.to_string),
        )
      let model = apply_lifecycle(model, next)
      let model = case error {
        Some(detail) -> append_error(model, detail)
        None -> model
      }
      case model.tree {
        Some(shared_tree) -> #(model, read_effect(shared_tree))
        None -> #(model, effect.none())
      }
    }
    BulkFinished(outcome) -> {
      let model = finish_pending(model)
      let model = case outcome {
        Ok(_) -> model
        Error(shared_tree.Aborted(error)) ->
          append_error(
            model,
            "Complete all aborted: " <> tree_error.to_string(error),
          )
        Error(shared_tree.TransactionFailed(detail)) ->
          append_error(
            model,
            "Complete all failed: " <> tree_error.to_string(detail),
          )
      }
      case model.tree {
        Some(shared_tree) -> #(model, read_effect(shared_tree))
        None -> #(model, effect.none())
      }
    }
    Disposed(outcome) -> {
      let lifecycle.Disposal(next, error, _) =
        lifecycle.disposal_finished(
          lifecycle_state(model),
          result.map_error(outcome, tree_error.to_string),
        )
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

pub fn rename_item(
  item: shared_tree.Ref(checklist.Item),
  text: String,
) -> Result(Nil, tree_error.Error) {
  use text <- result.try(
    checklist.normalize_text(text)
    |> result.map_error(fn(detail) {
      tree_error.InvalidValue(types.InvalidEdit(["text"], detail))
    }),
  )
  shared_tree.set(item, document_schema.text(), text)
}

pub fn toggle_item(
  item: shared_tree.Ref(checklist.Item),
  completed: Bool,
) -> Result(Nil, tree_error.Error) {
  shared_tree.set(item, document_schema.completed(), !completed)
}

pub fn delete_item(
  items: shared_tree.Ref(List(checklist.Item)),
  item: shared_tree.Ref(checklist.Item),
) -> Result(Nil, tree_error.Error) {
  shared_tree.array_remove_node(items, item)
}

pub fn move_item(
  items: shared_tree.Ref(List(checklist.Item)),
  item: shared_tree.Ref(checklist.Item),
  before: Option(shared_tree.Ref(checklist.Item)),
) -> Result(Nil, tree_error.Error) {
  shared_tree.array_move_before(items, item, items, before)
}

pub fn complete_all(
  shared_tree: shared_tree.Tree(checklist.Checklist),
) -> Result(Bool, tree_error.Error) {
  use root <- result.try(required_root(shared_tree))
  use items <- result.try(shared_tree.child(root, document_schema.items()))
  use nodes <- result.try(checklist.nodes(items))
  complete_incomplete(nodes, False)
}

fn complete_incomplete(
  items: List(shared_tree.Ref(checklist.Item)),
  changed: Bool,
) -> Result(Bool, tree_error.Error) {
  case items {
    [] -> Ok(changed)
    [item, ..rest] -> {
      use value <- result.try(shared_tree.read(item))
      use _ <- result.try(case value.completed {
        True -> Ok(Nil)
        False -> shared_tree.set(item, document_schema.completed(), True)
      })
      complete_incomplete(rest, changed || !value.completed)
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
      let current = refresh_history(model)
      let #(next, handle) = lifecycle.request(lifecycle_state(current), action)
      case handle {
        None -> #(apply_lifecycle(current, next), effect.none())
        Some(handle) -> #(
          apply_lifecycle(current, next),
          tree.revert(handle, shared_tree.DisposeRevertible, HistoryFinished),
        )
      }
    }
  }
}

fn request_complete_all(model: Model) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.tree {
    True, Some(shared_tree) -> #(
      Model(..model, pending: model.pending + 1),
      after_paint(RunCompleteAll(shared_tree)),
    )
    True, None -> #(
      append_error(model, "SharedTree is not ready"),
      effect.none(),
    )
    False, _ -> #(model, effect.none())
  }
}

fn after_paint(message: Msg) -> Effect(Msg) {
  use dispatch, _root <- effect.after_paint
  dispatch(message)
}

fn add(model: Model, id: String, text: String) -> #(Model, Effect(Msg)) {
  mutate(model, fn() {
    use item <- result.try(
      checklist.new_item(id, text, False)
      |> result.map_error(fn(detail) {
        tree_error.InvalidValue(types.InvalidEdit(["text"], detail))
      }),
    )
    use items <- result.try(current_items(model))
    shared_tree.array_insert(items, list.length(model.item_nodes), [item])
  })
}

fn mutate(
  model: Model,
  operation: fn() -> Result(Nil, tree_error.Error),
) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.tree {
    False, _ -> #(model, effect.none())
    True, None -> #(
      append_error(model, "SharedTree is not ready"),
      effect.none(),
    )
    True, Some(_) -> #(
      Model(..model, pending: model.pending + 1),
      tree.perform(operation, MutationFinished),
    )
  }
}

fn close_document(model: Model) -> #(Model, Effect(Msg)) {
  case can_interact(model), model.document {
    False, _ -> #(model, effect.none())
    True, None -> #(append_error(model, "Document is not ready"), effect.none())
    True, Some(document) -> {
      let model = refresh_history(model)
      let lifecycle.Close(next, unsubscribe, dispose) =
        lifecycle.close(
          lifecycle_state(model),
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
  handles: List(shared_tree.Revertible),
) -> #(Model, Effect(Msg)) {
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
  value: history.History(shared_tree.Revertible),
) -> Result(history.History(shared_tree.Revertible), tree_error.Error) {
  let keep = fn(entries) {
    entries
    |> list.try_fold([], fn(retained, handle) {
      use status <- result.try(shared_tree.revertible_status(handle))
      case status {
        shared_tree.RevertibleValid -> Ok([handle, ..retained])
        shared_tree.RevertibleDisposed -> Ok(retained)
      }
    })
    |> result.map(list.reverse)
  }
  use undo <- result.try(keep(value.undo))
  use redo <- result.try(keep(value.redo))
  Ok(history.History(undo, redo))
}

fn refresh_history(model: Model) -> Model {
  case valid_history(model.history) {
    Ok(history) -> Model(..model, history: history)
    Error(error) -> append_error(model, tree_error.to_string(error))
  }
}

fn can_interact(model: Model) -> Bool {
  model.phase == Ready && model.pending == 0 && model.history_action == None
}

fn lifecycle_state(model: Model) -> lifecycle.State(shared_tree.Revertible) {
  lifecycle.State(
    history: model.history,
    action: model.history_action,
    pending: model.pending,
  )
}

fn apply_lifecycle(
  model: Model,
  state: lifecycle.State(shared_tree.Revertible),
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

fn read_effect(
  shared_tree: shared_tree.Tree(checklist.Checklist),
) -> Effect(Msg) {
  tree.perform(fn() { read_checklist(shared_tree) }, Read)
}

fn read_checklist(
  shared_tree: shared_tree.Tree(checklist.Checklist),
) -> Result(
  #(checklist.Checklist, List(shared_tree.Ref(checklist.Item))),
  tree_error.Error,
) {
  use decoded <- result.try(shared_tree.read_root(shared_tree))
  use root <- result.try(required_root(shared_tree))
  use items <- result.try(shared_tree.child(root, document_schema.items()))
  use nodes <- result.try(checklist.nodes(items))
  let checklist.Checklist(items: snapshots, ..) = decoded
  use nodes <- result.try(reconcile_nodes(snapshots, nodes))
  Ok(#(decoded, nodes))
}

fn reconcile_nodes(
  snapshots: List(checklist.Item),
  nodes: List(shared_tree.Ref(checklist.Item)),
) -> Result(List(shared_tree.Ref(checklist.Item)), tree_error.Error) {
  case snapshots {
    [] ->
      case nodes {
        [] -> Ok([])
        _ ->
          Error(tree_error.RuntimeFailure(
            "The checklist changed while it was read",
          ))
      }
    [snapshot, ..rest] -> {
      use node <- result.try(find_snapshot_node(snapshot, nodes))
      use reconciled <- result.try(reconcile_nodes(
        rest,
        list.filter(nodes, fn(candidate) { candidate != node }),
      ))
      Ok([node, ..reconciled])
    }
  }
}

fn find_snapshot_node(
  snapshot: checklist.Item,
  nodes: List(shared_tree.Ref(checklist.Item)),
) -> Result(shared_tree.Ref(checklist.Item), tree_error.Error) {
  case nodes {
    [] ->
      Error(tree_error.RuntimeFailure("The checklist changed while it was read"))
    [node, ..rest] -> {
      use value <- result.try(shared_tree.read(node))
      case value.id == snapshot.id {
        True ->
          case value == snapshot {
            True -> Ok(node)
            False ->
              Error(tree_error.RuntimeFailure(
                "The checklist changed while it was read",
              ))
          }
        False -> find_snapshot_node(snapshot, rest)
      }
    }
  }
}

fn required_root(
  shared_tree: shared_tree.Tree(checklist.Checklist),
) -> Result(shared_tree.Ref(checklist.Checklist), tree_error.Error) {
  shared_tree.required_root(shared_tree)
}

fn current_items(
  model: Model,
) -> Result(shared_tree.Ref(List(checklist.Item)), tree_error.Error) {
  use shared_tree <- result.try(
    model.tree
    |> option.to_result(tree_error.NotReady),
  )
  use root <- result.try(required_root(shared_tree))
  shared_tree.child(root, document_schema.items())
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
  let history.History(undo: undo, redo: redo) = model.history
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
    keyed.ul(
      [],
      list.index_map(list.zip(items, model.item_nodes), fn(entry, index) {
        #(
          entry.0.id,
          item_view(
            entry.0,
            entry.1,
            node_at(model.item_nodes, index - 1),
            node_at(model.item_nodes, index + 2),
            index,
            list.length(items),
            ready,
          ),
        )
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
  node: shared_tree.Ref(checklist.Item),
  before_up: Option(shared_tree.Ref(checklist.Item)),
  before_down: Option(shared_tree.Ref(checklist.Item)),
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
        event.on_check(fn(_) { ToggleClicked(node, item.completed) }),
      ]),
      html.input([
        attribute.type_("text"),
        attribute.value(item.text),
        attribute.disabled(!ready),
        attribute.aria_label("Edit " <> item.text),
        attribute.attribute("data-action", "edit"),
        event.on_change(fn(text) { EditCommitted(node, text) }),
      ]),
      html.button(
        [
          attribute.disabled(!ready || index == 0),
          attribute.attribute("data-action", "move-up"),
          event.on_click(MoveClicked(node, before_up)),
        ],
        [html.text("Up")],
      ),
      html.button(
        [
          attribute.disabled(!ready || index == length - 1),
          attribute.attribute("data-action", "move-down"),
          event.on_click(MoveClicked(node, before_down)),
        ],
        [html.text("Down")],
      ),
      html.button(
        [
          attribute.disabled(!ready),
          attribute.attribute("data-action", "delete"),
          event.on_click(DeleteClicked(node)),
        ],
        [html.text("Delete")],
      ),
    ],
  )
}

fn node_at(
  nodes: List(shared_tree.Ref(checklist.Item)),
  index: Int,
) -> Option(shared_tree.Ref(checklist.Item)) {
  case index < 0 {
    True -> None
    False ->
      case list.first(list.drop(nodes, index)) {
        Ok(node) -> Some(node)
        Error(Nil) -> None
      }
  }
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
