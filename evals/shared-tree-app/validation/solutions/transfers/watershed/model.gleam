import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import incident_eval/domain as d
import incident_eval/schema as s
import lustre/effect.{type Effect}
import watershed
import watershed/tree as t
import watershed/tree/error as e
import watershed/tree/types
import watershed_lustre as w
import watershed_lustre/tree as effects

// mutation:start imports
// mutation:end imports

pub opaque type Model {
  Model(
    config: d.Config,
    state: d.State,
    document: Option(watershed.Document(Nil)),
    tree: Option(t.Tree(d.Board)),
    subscription: Option(t.Subscription),
    // mutation:start fields
    // mutation:end fields
  )
}

pub opaque type Msg {
  Created(Result(String, e.Error))
  Document(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(t.Tree(d.Board), e.Error))
  Subscribed(Result(t.Subscription, e.Error))
  Changed(Result(d.Board, e.Error))
  Edited(Result(Nil, e.Error))
  Released(Result(Nil, e.Error))
  Poll
}

pub fn init(config: d.Config) -> #(Model, Effect(Msg)) {
  // mutation:start init
  let model =
    Model(config, d.State(d.Opening, None, d.Board([]), []), None, None, None)
  // mutation:end init
  #(model, case config.document_id {
    None ->
      effects.create_dev(
        config.base_url,
        config.tenant,
        config.development_secret,
        s.configuration(),
        d.Board([]),
        Created,
      )
    Some(id) -> connect(config, id)
  })
}

fn connect(config: d.Config, id: String) -> Effect(Msg) {
  w.connect_dev(
    config.socket_url,
    config.tenant,
    config.development_secret,
    id,
    config.client_id,
    Document,
    Connected,
  )
}

fn issue(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      state: d.State(..model.state, errors: [detail, ..model.state.errors]),
    ),
    effect.none(),
  )
}

fn release(model: Model) -> Effect(Msg) {
  // mutation:start cleanup
  effects.perform(
    fn() {
      case model.subscription {
        Some(subscription) -> t.unsubscribe(subscription)
        None -> Nil
      }
      let outcome = case model.tree {
        Some(tree) -> t.dispose(tree)
        None -> Ok(Nil)
      }
      case model.document {
        Some(document) -> watershed.close(document)
        None -> Nil
      }
      outcome
    },
    Released,
  )
  // mutation:end cleanup
}

fn fatal(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  let #(model, _) =
    issue(
      Model(..model, state: d.State(..model.state, phase: d.Failed)),
      detail,
    )
  #(model, release(model))
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case model.state.phase, message {
    d.Closed, Document(document) | d.Failed, Document(document) -> #(
      model,
      effect.from(fn(_) { watershed.close(document) }),
    )
    d.Closed, Opened(Ok(tree)) | d.Failed, Opened(Ok(tree)) -> #(
      model,
      effects.dispose(tree, fn(_) { Poll }),
    )
    d.Closed, Subscribed(Ok(subscription))
    | d.Failed, Subscribed(Ok(subscription))
    -> #(model, effects.unsubscribe(subscription))
    d.Closed, Released(Error(error)) | d.Failed, Released(Error(error)) ->
      issue(model, e.to_string(error))
    d.Closed, Created(Error(error)) -> issue(model, e.to_string(error))
    d.Closed, _ -> #(model, effect.none())
    d.Failed, _ -> #(model, effect.none())
    _, Created(Ok(id)) -> #(
      Model(..model, config: d.Config(..model.config, document_id: Some(id))),
      connect(model.config, id),
    )
    _, Created(Error(error)) -> fatal(model, e.to_string(error))
    _, Document(document) -> #(
      Model(..model, document: Some(document)),
      w.after(100, Poll),
    )
    _, Connected(Error(detail)) -> fatal(model, detail)
    _, Connected(Ok(_)) ->
      case model.document {
        Some(document) -> #(
          model,
          effects.open(document, s.configuration(), Opened),
        )
        None -> fatal(model, "Connection has no document")
      }
    _, Opened(Error(error)) -> fatal(model, e.to_string(error))
    // mutation:start open
    _, Opened(Ok(tree)) -> #(
      Model(..model, tree: Some(tree)),
      effects.observe(tree, Subscribed, Changed),
    )
    // mutation:end open
    _, Subscribed(Error(error)) -> fatal(model, e.to_string(error))
    _, Subscribed(Ok(subscription)) -> {
      let model = Model(..model, subscription: Some(subscription))
      case model.tree {
        Some(tree) -> #(model, effects.read_root(tree, Changed))
        None -> fatal(model, "Subscription has no tree")
      }
    }
    _, Changed(Error(error)) -> fatal(model, e.to_string(error))
    _, Changed(Ok(board)) -> #(
      Model(
        ..model,
        state: d.State(
          d.Ready,
          model.config.document_id,
          board,
          model.state.errors,
        ),
      ),
      effect.none(),
    )
    _, Edited(Error(error)) -> issue(model, e.to_string(error))
    _, Released(Error(error)) -> issue(model, e.to_string(error))
    _, Released(Ok(_)) -> #(model, effect.none())
    _, Edited(Ok(_)) ->
      case model.tree {
        Some(tree) -> #(model, effects.read_root(tree, Changed))
        None -> fatal(model, "Edit has no tree")
      }
    _, Poll ->
      case model.document {
        Some(document) -> {
          let phase = watershed.diagnostics(document).phase
          case model.state.phase, phase {
            d.Ready, "ready" -> #(model, w.after(100, Poll))
            d.Ready, _ -> {
              let #(model, _) =
                issue(
                  Model(
                    ..model,
                    state: d.State(..model.state, phase: d.Disconnected),
                  ),
                  "Service connection is unavailable",
                )
              #(model, w.after(100, Poll))
            }
            d.Disconnected, "ready" -> #(
              Model(..model, state: d.State(..model.state, phase: d.Ready)),
              w.after(100, Poll),
            )
            d.Failed, _ -> #(model, effect.none())
            _, _ -> #(model, w.after(100, Poll))
          }
        }
        None -> #(model, effect.none())
      }
  }
}

fn invalid(detail: String) -> e.Error {
  e.InvalidValue(types.InvalidEdit([], detail))
}

fn find(
  array: t.Ref(List(a)),
  id: String,
  get_id: fn(a) -> String,
  index: Int,
) -> Result(Option(t.Ref(a)), e.Error) {
  // mutation:start lookup
  use node <- result.try(t.array_node(array, index))
  case node {
    None -> Ok(None)
    Some(node) -> {
      use value <- result.try(t.read(node))
      case get_id(value) == id {
        True -> Ok(Some(node))
        False -> find(array, id, get_id, index + 1)
      }
      // mutation:end lookup
    }
  }
}

fn with_incident(
  tree: t.Tree(d.Board),
  id: String,
  action: fn(t.Ref(d.Incident), t.Ref(List(d.Incident))) -> Result(Nil, e.Error),
) -> Result(Nil, e.Error) {
  use root <- result.try(t.required_root(tree))
  use array <- result.try(t.child(root, s.incidents()))
  use node <- result.try(find(array, id, fn(v) { v.id }, 0))
  case node {
    None -> Ok(Nil)
    Some(node) -> action(node, array)
  }
}

fn with_step(
  tree: t.Tree(d.Board),
  incident: String,
  id: String,
  action: fn(t.Ref(d.Step), t.Ref(List(d.Step))) -> Result(Nil, e.Error),
) -> Result(Nil, e.Error) {
  use node, _ <- with_incident(tree, incident)
  use array <- result.try(t.child(node, s.steps()))
  use step <- result.try(find(array, id, fn(v) { v.id }, 0))
  case step {
    None -> Ok(Nil)
    Some(step) -> action(step, array)
  }
}

fn unique(tree: t.Tree(d.Board), id: String) -> Result(Nil, e.Error) {
  use board <- result.try(t.read_root(tree))
  let ids =
    list.flat_map(board.incidents, fn(v) {
      [v.id, ..list.map(v.steps, fn(step) { step.id })]
    })
  case id == "" || list.contains(ids, id) {
    True -> Error(invalid("ID must be nonempty and unique"))
    False -> Ok(Nil)
  }
}

fn move(
  array: t.Ref(List(a)),
  node: t.Ref(a),
  before: Option(String),
  get_id: fn(a) -> String,
) -> Result(Nil, e.Error) {
  use target <- result.try(case before {
    None -> Ok(None)
    Some(id) -> {
      use found <- result.try(find(array, id, get_id, 0))
      case found {
        None -> Error(invalid("Destination is not a sibling"))
        Some(_) -> Ok(found)
      }
    }
  })
  t.array_move_before(array, node, array, target)
}

fn edit(tree: t.Tree(d.Board), action: d.Action) -> Result(Nil, e.Error) {
  // mutation:start edit
  case action {
    d.AddIncident(id, title) -> {
      use _ <- result.try(unique(tree, id))
      use root <- result.try(t.required_root(tree))
      use array <- result.try(t.child(root, s.incidents()))
      use values <- result.try(t.read(array))
      t.array_insert(array, list.length(values), [
        d.Incident(id, title, d.Open, None, []),
      ])
    }
    // mutation:start title
    d.Title(id, value) -> {
      use node, _ <- with_incident(tree, id)
      t.set(node, s.title(), value)
    }
    // mutation:end title
    d.Status(id, value) -> {
      use node, _ <- with_incident(tree, id)
      t.set(node, s.status(), d.status_name(value))
    }
    d.Assignee(id, value) -> {
      use node, _ <- with_incident(tree, id)
      t.set(node, s.assignee(), value)
    }
    d.RemoveIncident(id) -> {
      use node, array <- with_incident(tree, id)
      t.array_remove_node(array, node)
    }
    d.MoveIncident(id, before) -> {
      use node, array <- with_incident(tree, id)
      move(array, node, before, fn(v) { v.id })
    }
    d.AddStep(incident, id, label) -> {
      use node, _ <- with_incident(tree, incident)
      use _ <- result.try(unique(tree, id))
      use array <- result.try(t.child(node, s.steps()))
      use values <- result.try(t.read(array))
      t.array_insert(array, list.length(values), [d.Step(id, label, False)])
    }
    d.StepLabel(incident, id, value) -> {
      use node, _ <- with_step(tree, incident, id)
      t.set(node, s.label(), value)
    }
    d.StepDone(incident, id, value) -> {
      use node, _ <- with_step(tree, incident, id)
      t.set(node, s.done(), value)
    }
    d.RemoveStep(incident, id) -> {
      use node, array <- with_step(tree, incident, id)
      t.array_remove_node(array, node)
    }
    d.MoveStep(incident, id, before) -> {
      use node, array <- with_step(tree, incident, id)
      move(array, node, before, fn(v) { v.id })
    }
    d.TransferStep(incident, id, destination, before) -> {
      // mutation:start transfer-lookup
      use node, source <- with_step(tree, incident, id)
      // mutation:end transfer-lookup
      // mutation:start transfer-target
      use root <- result.try(t.required_root(tree))
      use incidents <- result.try(t.child(root, s.incidents()))
      use target <- result.try(find(incidents, destination, fn(v) { v.id }, 0))
      use target <- result.try(case destination, target {
        "", _ | _, None -> Error(invalid("Destination incident does not exist"))
        _, Some(target) -> Ok(target)
      })
      use destination <- result.try(t.child(target, s.steps()))
      // mutation:end transfer-target
      use before <- result.try(case before {
        None -> Ok(None)
        Some(id) -> {
          use sibling <- result.try(find(destination, id, fn(v) { v.id }, 0))
          case sibling {
            None -> Error(invalid("Destination is not a sibling"))
            Some(_) -> Ok(sibling)
          }
        }
      })
      // mutation:start transfer-move
      t.array_move_before(source, node, destination, before)
      // mutation:end transfer-move
    }
  }
  // mutation:end edit
}

pub fn apply(model: Model, action: d.Action) -> #(Model, Effect(Msg)) {
  // mutation:start apply
  case model.state.phase, model.tree {
    d.Ready, Some(tree) -> #(
      model,
      effects.perform(fn() { edit(tree, action) }, Edited),
    )
    _, _ -> #(model, effect.none())
  }
  // mutation:end apply
}

pub fn close(model: Model) -> #(Model, Effect(Msg)) {
  case model.state.phase {
    d.Closed -> #(model, effect.none())
    d.Failed -> #(
      Model(..model, state: d.State(..model.state, phase: d.Closed)),
      effect.none(),
    )
    _ -> #(
      Model(..model, state: d.State(..model.state, phase: d.Closed)),
      release(model),
    )
  }
}

pub fn read(model: Model) -> d.State {
  model.state
}

pub fn native_tree(model: Model) -> Option(t.Tree(d.Board)) {
  model.tree
}

pub fn native_document(model: Model) -> Option(watershed.Document(Nil)) {
  model.document
}
