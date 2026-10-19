import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
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
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/edits
import shared_tree_project_brief_lustre/input
import shared_tree_project_brief_lustre/schema
import shared_tree_project_brief_lustre/selection as s
import watershed
import watershed/id
import watershed/presence
import watershed/presence_js
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed_lustre
import watershed_lustre/tree

@internal
pub type Model {
  Model(
    status: String,
    connection: String,
    session: Option(String),
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(shared_tree.Tree(brief.ProjectBrief)),
    subscription: Option(shared_tree.Subscription),
    rendered: Option(edits.RenderState),
    inputs: Dict(String, input.Input),
    metadata: s.Metadata,
    policy: s.Policy,
    fresh: Dict(String, presence.PresenceEntry(s.Metadata)),
    presence: Option(presence_js.Handle(s.Metadata)),
    generation: Int,
    change_count: Int,
    pending: Int,
    errors: List(String),
  )
}

@internal
pub type InputEvent {
  Changed(String, Int, Int)
  CompositionStarted
  CompositionEnded(String, Int, Int)
  Selected(Int, Int)
}

@internal
pub type Msg {
  Created(Result(String, tree_error.Error))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(shared_tree.Tree(brief.ProjectBrief), tree_error.Error))
  Subscribed(Result(shared_tree.Subscription, tree_error.Error))
  TreeChanged
  Captured(Result(edits.RenderState, tree_error.Error))
  Input(s.Field, fn(String) -> Result(Nil, tree_error.Error), InputEvent)
  Action(fn() -> Result(Nil, tree_error.Error))
  Edited(Result(Nil, tree_error.Error))
  Focus(Option(s.Field))
  PresenceStarted(Int, presence_js.Handle(s.Metadata))
  PresenceEvent(Int, presence.Event(s.Metadata))
  PresenceObserved(Option(String), watershed.Ripple)
  Poll
  Close
}

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "currentOrigin")
fn current_origin() -> String

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "proxyFloodgateHttp")
fn proxy_floodgate_http(upstream: String) -> Nil

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "replaceDocument")
fn replace_document(document_id: String) -> Nil

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "restoreSelection")
fn restore_selection(element_id: String, start: Int, end: Int) -> Nil

@external(javascript, "./shared_tree_project_brief_lustre_ffi.mjs", "queueMicrotask")
fn queue_microtask(action: fn() -> Nil) -> Nil

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(init, update, view) |> lustre.start("#app", Nil)
  Nil
}

// docs:snippet-start project-brief-watershed-lifecycle
fn init(_: Nil) -> #(Model, Effect(Msg)) {
  proxy_floodgate_http("http://127.0.0.1:4000")
  let document_id = query_parameter("document", "")
  let model =
    Model(
      status: case document_id {
        "" -> "creating"
        _ -> "connecting"
      },
      connection: "connecting",
      session: None,
      document_id:,
      document: None,
      tree: None,
      subscription: None,
      rendered: None,
      inputs: dict.new(),
      metadata: s.Metadata(query_parameter("name", "Editor"), s.Blue, 0, None),
      policy: s.new(),
      fresh: dict.new(),
      presence: None,
      generation: 0,
      change_count: 0,
      pending: 0,
      errors: [],
    )
  #(model, case document_id {
    "" ->
      tree.create_dev(
        query_parameter("base", current_origin()),
        query_parameter("tenant", "dev-tenant"),
        query_parameter("secret", "levee-dev-secret-change-in-production"),
        schema.configuration(),
        brief.initial(id.uuid_v4(), id.uuid_v4()),
        Created,
      )
    _ -> connect(document_id)
  })
}

fn connect(document_id: String) -> Effect(Msg) {
  watershed_lustre.connect_dev(
    url: "ws://127.0.0.1:4000/socket/websocket?vsn=2.0.0",
    tenant: query_parameter("tenant", "dev-tenant"),
    secret: query_parameter("secret", "levee-dev-secret-change-in-production"),
    document: document_id,
    user_id: "project-brief-editor",
    got_document: GotDocument,
    connected: Connected,
  )
}

// docs:snippet-end project-brief-watershed-lifecycle

@internal
pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case model.status, message {
    "closed", Created(Ok(document_id)) -> {
      replace_document(document_id)
      #(Model(..model, document_id:), effect.none())
    }
    "closed", Created(Error(error)) ->
      problem(
        model,
        "Creation failed after close: " <> tree_error.to_string(error),
      )
    "closed", GotDocument(document) -> #(
      model,
      effect.from(fn(_) { watershed.close(document) }),
    )
    "closed", Subscribed(Ok(subscription)) -> #(
      model,
      tree.unsubscribe(subscription),
    )
    "closed", Opened(Ok(handle)) -> #(
      model,
      tree.dispose(handle, fn(_) { Close }),
    )
    "closed", PresenceStarted(_, handle) -> #(
      model,
      watershed_lustre.stop_presence(handle),
    )
    "closed", _ -> #(model, effect.none())
    _, _ -> update_active(model, message)
  }
}

fn update_active(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Created(Ok(document_id)) -> {
      replace_document(document_id)
      #(
        Model(..model, document_id:, status: "connecting"),
        connect(document_id),
      )
    }
    Created(Error(error)) ->
      fatal(
        model,
        "Creation failed. The document might exist. Do not retry automatically: "
          <> tree_error.to_string(error),
      )
    // docs:snippet-start project-brief-watershed-presence-start
    GotDocument(document) -> {
      let next = Model(..model, document: Some(document))
      #(
        next,
        effect.batch([
          observe_presence(document),
          watershed_lustre.presence(
            document:,
            config: s.config(),
            initial: next.metadata,
            started: fn(handle) { PresenceStarted(next.generation, handle) },
            on_event: fn(event) { PresenceEvent(next.generation, event) },
          ),
          watershed_lustre.after(250, Poll),
        ]),
      )
    }
    // docs:snippet-end project-brief-watershed-presence-start
    // docs:snippet-start project-brief-watershed-lifecycle-open
    Connected(Error(detail)) -> fatal(model, detail)
    Connected(Ok(_)) ->
      case model.document {
        Some(document) -> #(
          model,
          tree.open(document, schema.configuration(), Opened),
        )
        None -> fatal(model, "Connection completed without a document handle")
      }
    Opened(Error(error)) -> fatal(model, tree_error.to_string(error))
    Opened(Ok(handle)) -> #(
      Model(..model, tree: Some(handle)),
      tree.subscribe_changes(handle, Subscribed, fn(_) { TreeChanged }),
    )
    Subscribed(Error(error)) -> fatal(model, tree_error.to_string(error))
    Subscribed(Ok(subscription)) ->
      capture(Model(..model, subscription: Some(subscription)))
    TreeChanged -> capture(Model(..model, change_count: model.change_count + 1))
    // docs:snippet-end project-brief-watershed-lifecycle-open
    Captured(Error(error)) -> fatal(model, tree_error.to_string(error))
    Captured(Ok(rendered)) -> {
      // A replacement can arrive without a capture of the absent review.
      let review_removed = case model.rendered {
        Some(previous) ->
          case previous.review {
            Some(node) -> shared_tree.status(node) != Ok(tree_error.Attached)
            None -> False
          }
        None -> False
      }
      let selection_value = case review_removed {
        True -> brief.ProjectBrief(..rendered.value, review: None)
        False -> rendered.value
      }
      let inputs =
        list.fold(string_values(rendered.value), dict.new(), fn(inputs, pair) {
          let #(field, value) = pair
          let key = s.field_key(field)
          let local = case review_removed, field {
            True, s.Fixed(s.ReviewReviewer) -> input.new(value)
            _, _ ->
              dict.get(model.inputs, key) |> result.unwrap(input.new(value))
          }
          dict.insert(inputs, key, input.remote(local, value))
        })
      let metadata = s.reconcile_local(model.metadata, selection_value)
      let policy =
        s.reconcile(model.policy, s.peers(model.policy), selection_value)
      let policy = s.reconcile(policy, s.peers(policy), rendered.value)
      let next =
        Model(
          ..model,
          rendered: Some(rendered),
          inputs:,
          metadata:,
          policy:,
          status: "ready",
        )
      let caret = case metadata.selected {
        Some(field) ->
          case
            dict.get(inputs, s.field_key(field)),
            dict.get(model.inputs, s.field_key(field))
          {
            Ok(local), Ok(old) if local.value != old.value && !local.composing ->
              case local.selection {
                Some(#(start, end)) -> {
                  use _, _ <- effect.before_paint
                  restore_selection(dom_id(field), start, end)
                }
                None -> effect.none()
              }
            _, _ -> effect.none()
          }
        None -> effect.none()
      }
      #(next, effect.batch([caret, announce(next)]))
    }
    Input(field, write, input_event) -> {
      let model = connection_state(model)
      case editable(model), dict.get(model.inputs, s.field_key(field)) {
        True, Ok(local) -> {
          let transition = case input_event {
            Changed(value, start, end) ->
              input.changed(input.selected(local, start, end), value)
            CompositionStarted ->
              input.Transition(input.composition_started(local), None)
            CompositionEnded(value, start, end) ->
              input.composition_ended(input.selected(local, start, end), value)
            Selected(start, end) ->
              input.Transition(input.selected(local, start, end), None)
          }
          let next =
            Model(
              ..model,
              inputs: dict.insert(
                model.inputs,
                s.field_key(field),
                transition.input,
              ),
            )
          case transition.publish {
            None -> #(next, effect.none())
            Some(value) -> perform(next, fn() { write(value) })
          }
        }
        False, Ok(_) -> #(
          Model(..model, inputs: cancel_inputs(model)),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
      }
    }
    Action(operation) -> {
      let model = connection_state(model)
      case editable(model) {
        True -> perform(model, operation)
        False -> #(model, effect.none())
      }
    }
    Edited(outcome) -> {
      let model = Model(..model, pending: int.max(0, model.pending - 1))
      case outcome {
        Ok(_) -> #(model, effect.none())
        Error(error) -> {
          let #(model, _) = problem(model, tree_error.to_string(error))
          capture(model)
        }
      }
    }
    // docs:snippet-start project-brief-watershed-presence-focus
    Focus(field) -> {
      let model = Model(..model, metadata: s.focus(model.metadata, field))
      #(model, announce(model))
    }
    // docs:snippet-end project-brief-watershed-presence-focus
    PresenceStarted(generation, handle) ->
      case generation == model.generation {
        False -> #(model, watershed_lustre.stop_presence(handle))
        True -> {
          let next = Model(..model, presence: Some(handle))
          #(next, announce(next))
        }
      }
    PresenceEvent(generation, event) -> {
      let model = connection_state(model)
      case generation == model.generation, event, model.rendered {
        True, presence.Failed(error), _ ->
          problem(model, "Presence failed: " <> string.inspect(error))
        True, presence.State(entries), Some(rendered)
        | True, presence.Changed(_, entries), Some(rendered)
          if model.connection == "ready"
        -> {
          let entries =
            presence.remote_entries(entries, option.unwrap(model.session, ""))
            |> list.filter(fn(peer) {
              dict.has_key(model.fresh, peer.session_id)
            })
          let fresh =
            list.fold(entries, dict.new(), fn(fresh, peer) {
              dict.insert(fresh, peer.session_id, peer)
            })
          #(
            Model(
              ..model,
              fresh:,
              policy: s.reconcile(model.policy, entries, rendered.value),
            ),
            effect.none(),
          )
        }
        _, _, _ -> #(model, effect.none())
      }
    }
    PresenceObserved(session, ripple) -> {
      let model = connection_state(model)
      case
        model.connection == "ready" && session == model.session,
        watershed.ripple_client_id(ripple),
        json.parse(
          json.to_string(watershed.ripple_content(ripple)),
          presence.ripple_decoder(s.decoder()),
        ),
        model.rendered,
        model.presence
      {
        True, Some(id), Ok(#(key, metadata)), Some(rendered), Some(handle)
          if Some(id) != model.session
        -> {
          case presence_js.local_session(handle) == session {
            True -> {
              let peer = presence.PresenceEntry(id, key, metadata)
              let fresh = dict.insert(model.fresh, id, peer)
              #(
                Model(
                  ..model,
                  fresh:,
                  policy: s.reconcile(
                    model.policy,
                    dict.values(fresh),
                    rendered.value,
                  ),
                ),
                effect.none(),
              )
            }
            False -> #(model, effect.none())
          }
        }
        _, _, _, _, _ -> #(model, effect.none())
      }
    }
    Poll -> poll(model)
    Close -> {
      let unsubscribe = case model.subscription {
        Some(subscription) -> tree.unsubscribe(subscription)
        None -> effect.none()
      }
      let stop = stop_presence(model)
      let close = case model.document {
        Some(document) -> effect.from(fn(_) { watershed.close(document) })
        None -> effect.none()
      }
      #(
        Model(
          ..model,
          status: "closed",
          connection: "closed",
          document: None,
          tree: None,
          subscription: None,
          presence: None,
          fresh: dict.new(),
          inputs: cancel_inputs(model),
          generation: model.generation + 1,
          policy: clear_peers(model),
          metadata: s.focus(model.metadata, None),
        ),
        effect.batch([stop, unsubscribe, close]),
      )
    }
  }
}

fn clear_peers(model: Model) -> s.Policy {
  case model.rendered {
    Some(rendered) -> s.reconcile(model.policy, [], rendered.value)
    None -> model.policy
  }
}

fn poll(model: Model) -> #(Model, Effect(Msg)) {
  let next = connection_state(model)
  #(next, case next.document {
    Some(_) -> watershed_lustre.after(250, Poll)
    None -> effect.none()
  })
}

fn connection_state(model: Model) -> Model {
  case model.document {
    None -> model
    Some(document) -> {
      let diagnostics = watershed.diagnostics(document)
      let phase = diagnostics.phase
      let online = phase == "ready"
      let lost = !online || diagnostics.client_id != model.session
      case lost {
        True ->
          Model(
            ..model,
            connection: phase,
            session: diagnostics.client_id,
            policy: clear_peers(model),
            fresh: dict.new(),
            inputs: cancel_inputs(model),
          )
        False ->
          Model(..model, connection: phase, session: diagnostics.client_id)
      }
    }
  }
}

fn cancel_inputs(model: Model) -> Dict(String, input.Input) {
  let values = case model.rendered {
    Some(rendered) ->
      string_values(rendered.value)
      |> list.map(fn(pair) { #(s.field_key(pair.0), pair.1) })
      |> dict.from_list
    None -> dict.new()
  }
  dict.map_values(model.inputs, fn(key, local) {
    input.Input(
      ..local,
      value: dict.get(values, key) |> result.unwrap(local.value),
      composing: False,
      composition_end: None,
    )
  })
}

fn observe_presence(document: watershed.Document(Nil)) -> Effect(Msg) {
  // Unchanged heartbeats emit no driver event. Observe freshness only.
  use dispatch <- effect.from
  watershed.subscribe_ripples(document, fn(ripple) {
    let diagnostics = watershed.diagnostics(document)
    let session = case diagnostics.phase {
      "ready" -> diagnostics.client_id
      _ -> None
    }
    queue_microtask(fn() { dispatch(PresenceObserved(session, ripple)) })
  })
}

fn capture(model: Model) -> #(Model, Effect(Msg)) {
  #(model, case model.tree {
    Some(handle) -> tree.perform(fn() { edits.capture(handle) }, Captured)
    None -> effect.none()
  })
}

fn perform(
  model: Model,
  operation: fn() -> Result(Nil, tree_error.Error),
) -> #(Model, Effect(Msg)) {
  #(Model(..model, pending: model.pending + 1), tree.perform(operation, Edited))
}

// docs:snippet-start project-brief-watershed-presence-update
fn announce(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) -> watershed_lustre.update_presence(handle, model.metadata)
    None -> effect.none()
  }
}

// docs:snippet-end project-brief-watershed-presence-update

fn stop_presence(model: Model) -> Effect(Msg) {
  case model.presence {
    Some(handle) -> watershed_lustre.stop_presence(handle)
    None -> effect.none()
  }
}

fn problem(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(Model(..model, errors: [detail, ..model.errors]), effect.none())
}

fn fatal(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  problem(
    Model(..model, status: "failed", inputs: cancel_inputs(model)),
    detail,
  )
}

fn editable(model: Model) -> Bool {
  model.status == "ready" && model.connection == "ready"
}

fn string_values(value: brief.ProjectBrief) -> List(#(s.Field, String)) {
  let fixed = [
    #(s.Fixed(s.Title), value.title),
    #(s.Fixed(s.OwnerName), value.owner.name),
    #(s.Fixed(s.OwnerEmail), value.owner.email),
    #(s.Fixed(s.ScheduleStart), value.schedule.start),
    #(s.Fixed(s.ScheduleTarget), value.schedule.target),
  ]
  let review = case value.review {
    Some(review) -> [#(s.Fixed(s.ReviewReviewer), review.reviewer)]
    None -> []
  }
  list.append(
    fixed,
    list.append(
      review,
      list.map(value.schedule.milestones, fn(item) {
        #(s.Milestone(item.id, s.MilestoneTitle), item.title)
      }),
    ),
  )
}

fn dom_id(field: s.Field) -> String {
  "field-" <> s.field_key(field)
}

fn value_event(
  to_event: fn(String, Int, Int) -> InputEvent,
) -> decode.Decoder(InputEvent) {
  use value <- decode.subfield(["target", "value"], decode.string)
  use start <- decode.subfield(["target", "selectionStart"], decode.int)
  use end <- decode.subfield(["target", "selectionEnd"], decode.int)
  decode.success(to_event(value, start, end))
}

fn selection_event() -> decode.Decoder(InputEvent) {
  use start <- decode.subfield(["target", "selectionStart"], decode.int)
  use end <- decode.subfield(["target", "selectionEnd"], decode.int)
  decode.success(Selected(start, end))
}

fn text_field(
  model: Model,
  field: s.Field,
  label: String,
  write: fn(String) -> Result(Nil, tree_error.Error),
) -> Element(Msg) {
  let local =
    dict.get(model.inputs, s.field_key(field)) |> result.unwrap(input.new(""))
  let handler = fn(event) { Input(field, write, event) }
  let bindings = [
    attribute.id(dom_id(field)),
    attribute.type_("text"),
    attribute.attribute("data-field", s.field_key(field)),
    attribute.attribute("aria-describedby", dom_id(field) <> "-selection"),
    attribute.disabled(!editable(model)),
    event.on_focus(Focus(Some(field))),
    event.on_blur(Focus(None)),
    event.on("input", decode.map(value_event(Changed), handler)),
    event.on("compositionstart", decode.success(handler(CompositionStarted))),
    event.on(
      "compositionend",
      decode.map(value_event(CompositionEnded), handler),
    ),
    event.on("select", decode.map(selection_event(), handler)),
    event.on("click", decode.map(selection_event(), handler)),
    event.on("keyup", decode.map(selection_event(), handler)),
    event.on("keydown", decode.map(selection_event(), handler)),
  ]
  let bindings = case local.composing {
    True -> bindings
    False -> [attribute.value(local.value), ..bindings]
  }
  html.div([attribute.class("field")], [
    html.label([attribute.for(dom_id(field))], [html.text(label)]),
    html.input(bindings),
    badges(model, field),
  ])
}

fn checkbox(
  model: Model,
  field: s.Field,
  label: String,
  checked: Bool,
  write: fn(Bool) -> Result(Nil, tree_error.Error),
) -> Element(Msg) {
  html.div([attribute.class("field checkbox")], [
    html.label([attribute.for(dom_id(field))], [html.text(label)]),
    html.input([
      attribute.id(dom_id(field)),
      attribute.type_("checkbox"),
      attribute.attribute("data-field", s.field_key(field)),
      attribute.attribute("aria-describedby", dom_id(field) <> "-selection"),
      attribute.disabled(!editable(model)),
      attribute.checked(checked),
      event.on_focus(Focus(Some(field))),
      event.on_blur(Focus(None)),
      event.on_check(fn(value) { Action(fn() { write(value) }) }),
    ]),
    badges(model, field),
  ])
}

fn badges(model: Model, field: s.Field) -> Element(Msg) {
  html.div(
    [
      attribute.id(dom_id(field) <> "-selection"),
      attribute.attribute("data-selection-for", s.field_key(field)),
      attribute.class("selectors"),
    ],
    list.filter_map(s.peers(model.policy), fn(peer) {
      case peer.meta.selected == Some(field) {
        False -> Error(Nil)
        True ->
          Ok(
            html.span(
              [
                attribute.attribute("data-session-id", peer.session_id),
                attribute.class(
                  "badge "
                  <> case peer.meta.color {
                    s.Blue -> "blue"
                    s.Green -> "green"
                    s.Amber -> "amber"
                    s.Violet -> "violet"
                  },
                ),
              ],
              [html.text(peer.meta.name)],
            ),
          )
      }
    }),
  )
}

fn button(
  action: String,
  label: String,
  message: Msg,
  disabled: Bool,
) -> Element(Msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.attribute("data-action", action),
      attribute.disabled(disabled),
      event.on_click(message),
    ],
    [html.text(label)],
  )
}

fn form(model: Model, state: edits.RenderState) -> Element(Msg) {
  html.div([attribute.class("brief")], [
    html.fieldset([], [
      html.legend([], [html.text("Brief")]),
      text_field(model, s.Fixed(s.Title), "Title", fn(value) {
        shared_tree.set(state.root, schema.brief_title(), value)
      }),
    ]),
    // docs:snippet-start project-brief-watershed-edits
    html.fieldset([], [
      html.legend([], [html.text("Owner")]),
      text_field(model, s.Fixed(s.OwnerName), "Name", fn(value) {
        shared_tree.set(state.owner, schema.owner_name(), value)
      }),
      text_field(model, s.Fixed(s.OwnerEmail), "Email", fn(value) {
        shared_tree.set(state.owner, schema.owner_email(), value)
      }),
    ]),
    // docs:snippet-end project-brief-watershed-edits
    html.fieldset([], [
      html.legend([], [html.text("Schedule")]),
      text_field(model, s.Fixed(s.ScheduleStart), "Start", fn(value) {
        shared_tree.set(state.schedule, schema.schedule_start(), value)
      }),
      text_field(model, s.Fixed(s.ScheduleTarget), "Target", fn(value) {
        shared_tree.set(state.schedule, schema.schedule_target(), value)
      }),
      // docs:snippet-start project-brief-watershed-milestones-view
      keyed.div(
        [attribute.class("milestones")],
        list.filter_map(state.milestone_nodes, fn(pair) {
          let #(id, node) = pair
          use item <- result.try(
            list.find(state.value.schedule.milestones, fn(item) {
              item.id == id
            }),
          )
          Ok(#(
            id,
            html.div([attribute.attribute("data-milestone-id", id)], [
              text_field(
                model,
                s.Milestone(id, s.MilestoneTitle),
                "Milestone title",
                fn(value) {
                  shared_tree.set(node, schema.milestone_title(), value)
                },
              ),
              checkbox(
                model,
                s.Milestone(id, s.Completed),
                "Completed",
                item.completed,
                fn(value) {
                  shared_tree.set(node, schema.milestone_completed(), value)
                },
              ),
              button(
                "remove-milestone",
                "Remove milestone",
                Action(fn() { edits.remove(state.milestones, node) }),
                !editable(model),
              ),
            ]),
          ))
        }),
      ),
      button(
        "add-milestone",
        "Add milestone",
        Action(fn() { edits.append(state.schedule, id.uuid_v4()) }),
        !editable(model),
      ),
      // docs:snippet-end project-brief-watershed-milestones-view
    ]),
    html.fieldset([], [
      html.legend([], [html.text("Review")]),
      case state.review, state.value.review {
        Some(node), Some(value) ->
          html.div([], [
            text_field(model, s.Fixed(s.ReviewReviewer), "Reviewer", fn(value) {
              shared_tree.set(node, schema.review_reviewer(), value)
            }),
            checkbox(
              model,
              s.Fixed(s.ReviewApproved),
              "Approved",
              value.approved,
              fn(value) {
                shared_tree.set(node, schema.review_approved(), value)
              },
            ),
            button(
              "remove-review",
              "Remove review",
              Action(fn() {
                use _ <- result.try(shared_tree.read(node))
                shared_tree.set(state.root, schema.review(), None)
              }),
              !editable(model),
            ),
          ])
        _, _ ->
          button(
            "add-review",
            "Add review",
            Action(fn() {
              shared_tree.set(
                state.root,
                schema.review(),
                Some(brief.Review("", False)),
              )
            }),
            !editable(model),
          )
      },
    ]),
  ])
}

@internal
pub fn view(model: Model) -> Element(Msg) {
  let session = case model.presence {
    Some(handle) ->
      presence_js.local_session(handle) |> option.unwrap("pending")
    None -> "unavailable"
  }
  html.div(
    [
      attribute.attribute(
        "data-tree-change-count",
        int.to_string(model.change_count),
      ),
    ],
    [
      html.h1([], [html.text("SharedTree project brief")]),
      html.p([], [
        html.text(
          "Copy this URL into another tab. Each edit assigns one property; simultaneous typing is not character-level merging.",
        ),
      ]),
      html.p(
        [
          attribute.attribute("data-runtime-status", case model.status {
            "ready" -> model.connection
            _ -> model.status
          }),
          attribute.attribute("role", "status"),
        ],
        [
          html.text(
            model.status
            <> " · connection: "
            <> model.connection
            <> " · pending: "
            <> int.to_string(model.pending),
          ),
        ],
      ),
      html.p([attribute.attribute("data-document-id", model.document_id)], [
        html.text("Document: " <> model.document_id),
      ]),
      html.p([], [html.text(model.metadata.name <> " · session: " <> session)]),
      html.p([], [
        html.text(
          case model.connection == "ready" && option.is_some(model.presence) {
            True -> "Field selection is advisory. Everyone can edit."
            False ->
              "Awareness unavailable. Durable edits require a ready connection."
          },
        ),
      ]),
      case model.rendered {
        Some(state) -> form(model, state)
        None ->
          html.p([], [html.text("Waiting for a checked document snapshot.")])
      },
      button("close", "Close", Close, model.status == "closed"),
      html.div(
        [attribute.attribute("role", "alert")],
        list.map(list.reverse(model.errors), fn(detail) {
          html.p([attribute.attribute("data-error", "")], [html.text(detail)])
        }),
      ),
      html.p([], [
        html.text(
          "Development authentication only. These credentials are not for production. This app opens watershed documents, not Fluid documents. Closing does not confirm pending edits were saved.",
        ),
      ]),
    ],
  )
}
