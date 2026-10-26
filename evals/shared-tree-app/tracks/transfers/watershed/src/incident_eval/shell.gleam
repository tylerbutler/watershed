import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import incident_eval/domain as d
import incident_eval/model
import lustre
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event

type Model {
  Shell(
    model: model.Model,
    issues: List(String),
    transfers: Dict(String, #(String, Option(String))),
  )
}

type Msg {
  ModelEvent(model.Msg)
  Action(d.Action)
  AddIncident
  AddStep(String)
  InvalidStatus
  InvalidAction(String)
  TransferDestination(String, String)
  TransferBefore(String, String)
  Transfer(String, String)
  Close
}

@external(javascript, "../incident_eval_ffi.mjs", "query")
fn query(name: String, fallback: String) -> String

@external(javascript, "../incident_eval_ffi.mjs", "origin")
fn origin() -> String

@external(javascript, "../incident_eval_ffi.mjs", "uuid")
fn uuid() -> String

@external(javascript, "../incident_eval_ffi.mjs", "replaceDocument")
fn replace_document(id: String) -> Nil

@external(javascript, "../incident_eval_ffi.mjs", "install")
fn install(
  model: model.Model,
  state: d.State,
  apply: fn(d.Action) -> Nil,
  close: fn() -> Nil,
  error: fn(String) -> Nil,
) -> Nil

@external(javascript, "../incident_eval_ffi.mjs", "publish")
fn publish(model: model.Model, state: d.State) -> Nil

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(init, update, view) |> lustre.start("#app", Nil)
  Nil
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let document = case query("document", "") {
    "" -> None
    id -> Some(id)
  }
  let #(model, effects) =
    model.init(d.Config(
      base_url: query("base", origin() <> "/api"),
      socket_url: query(
        "socket",
        "ws://127.0.0.1:4000/socket/websocket?vsn=2.0.0",
      ),
      tenant: query("tenant", "dev-tenant"),
      development_secret: query(
        "secret",
        "levee-dev-secret-change-in-production",
      ),
      document_id: document,
      client_id: uuid(),
    ))
  #(
    Shell(model, [], dict.new()),
    effect.batch([
      effect.from(fn(dispatch) {
        install(
          model,
          model.read(model),
          fn(action) { dispatch(Action(action)) },
          fn() { dispatch(Close) },
          fn(error) { dispatch(InvalidAction(error)) },
        )
      }),
      effect.map(effects, ModelEvent),
    ]),
  )
}

fn wrap(
  current: Model,
  next: #(model.Model, Effect(model.Msg)),
) -> #(Model, Effect(Msg)) {
  let #(model, effects) = next
  let state = model.read(model)
  case state.document_id {
    Some(id) -> replace_document(id)
    None -> Nil
  }
  #(
    Shell(model, current.issues, current.transfers),
    effect.batch([
      effect.from(fn(_) { publish(model, state) }),
      effect.map(effects, ModelEvent),
    ]),
  )
}

fn update(current: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    ModelEvent(message) -> wrap(current, model.update(current.model, message))
    Close ->
      case model.read(current.model).phase {
        d.Closed -> #(current, effect.none())
        _ -> wrap(current, model.close(current.model))
      }
    InvalidAction(error) -> #(
      Shell(..current, issues: [error, ..current.issues]),
      effect.none(),
    )
    InvalidStatus -> #(
      Shell(..current, issues: ["Invalid status", ..current.issues]),
      effect.none(),
    )
    _ ->
      case model.read(current.model).phase {
        d.Ready ->
          case message {
            Action(action) -> wrap(current, model.apply(current.model, action))
            AddIncident ->
              wrap(
                current,
                model.apply(current.model, d.AddIncident(uuid(), "")),
              )
            AddStep(incident) ->
              wrap(
                current,
                model.apply(current.model, d.AddStep(incident, uuid(), "")),
              )
            TransferDestination(id, destination) -> #(
              Shell(
                ..current,
                transfers: dict.insert(current.transfers, id, #(
                  destination,
                  None,
                )),
              ),
              effect.none(),
            )
            TransferBefore(id, before) -> {
              let #(destination, _) = transfer_selection(current.transfers, id)
              #(
                Shell(
                  ..current,
                  transfers: dict.insert(
                    current.transfers,
                    id,
                    #(destination, case before {
                      "" -> None
                      id -> Some(id)
                    }),
                  ),
                ),
                effect.none(),
              )
            }
            Transfer(incident, id) -> {
              let #(destination, before) =
                transfer_selection(current.transfers, id)
              wrap(
                current,
                model.apply(
                  current.model,
                  d.TransferStep(incident, id, destination, before),
                ),
              )
            }
            _ -> #(current, effect.none())
          }
        _ -> #(current, effect.none())
      }
  }
}

fn button(
  action: String,
  text: String,
  message: Msg,
  disabled: Bool,
) -> Element(Msg) {
  h.button(
    [
      a.type_("button"),
      a.attribute("data-action", action),
      a.disabled(disabled),
      event.on_click(message),
    ],
    [h.text(text)],
  )
}

fn input(
  field: String,
  label: String,
  value: String,
  change: fn(String) -> Msg,
  disabled: Bool,
) -> Element(Msg) {
  h.label([], [
    h.text(label),
    h.input([
      a.attribute("data-field", field),
      a.value(value),
      a.disabled(disabled),
      event.on_input(change),
    ]),
  ])
}

fn before(ids: List(String), index: Int) -> Option(String) {
  case index < 0 {
    True -> None
    False ->
      case list.first(list.drop(ids, index)) {
        Ok(id) -> Some(id)
        Error(_) -> None
      }
  }
}

fn transfer_selection(
  transfers: Dict(String, #(String, Option(String))),
  id: String,
) -> #(String, Option(String)) {
  case dict.get(transfers, id) {
    Ok(selection) -> selection
    Error(_) -> #("", None)
  }
}

fn transfer_controls(
  board: d.Board,
  incident: String,
  id: String,
  transfers: Dict(String, #(String, Option(String))),
  disabled: Bool,
) -> Element(Msg) {
  let #(destination, before) = transfer_selection(transfers, id)
  let target = list.find(board.incidents, fn(value) { value.id == destination })
  let siblings = case target {
    Ok(value) -> value.steps
    Error(_) -> []
  }
  let missing = case target {
    Ok(_) -> False
    Error(_) -> True
  }
  h.div([], [
    h.label([], [
      h.text("Transfer destination"),
      h.select(
        [
          a.attribute("data-field", "transfer-destination"),
          a.disabled(disabled),
          event.on_change(fn(value) { TransferDestination(id, value) }),
        ],
        [
          h.option(
            [a.value(""), a.selected(destination == "")],
            "Choose incident",
          ),
          ..list.map(board.incidents, fn(value) {
            h.option(
              [a.value(value.id), a.selected(destination == value.id)],
              case value.title {
                "" -> value.id
                title -> title
              },
            )
          })
        ],
      ),
    ]),
    h.label([], [
      h.text("Transfer before"),
      h.select(
        [
          a.attribute("data-field", "transfer-before"),
          a.disabled(disabled || missing),
          event.on_change(fn(value) { TransferBefore(id, value) }),
        ],
        [
          h.option([a.value(""), a.selected(before == None)], "Append"),
          ..list.map(siblings, fn(step) {
            h.option(
              [a.value(step.id), a.selected(before == Some(step.id))],
              case step.label {
                "" -> step.id
                label -> label
              },
            )
          })
        ],
      ),
    ]),
    button(
      "transfer-step",
      "Transfer step",
      Transfer(incident, id),
      disabled || missing,
    ),
  ])
}

fn steps(
  board: d.Board,
  incident: d.Incident,
  transfers: Dict(String, #(String, Option(String))),
  disabled: Bool,
) -> Element(Msg) {
  let ids = list.map(incident.steps, fn(step) { step.id })
  keyed.div(
    [],
    list.index_map(incident.steps, fn(step, index) {
      #(
        step.id,
        h.div([a.attribute("data-step-id", step.id)], [
          input(
            "step-label",
            "Step",
            step.label,
            fn(value) { Action(d.StepLabel(incident.id, step.id, value)) },
            disabled,
          ),
          h.label([], [
            h.text("Complete"),
            h.input([
              a.type_("checkbox"),
              a.attribute("data-field", "step-done"),
              a.checked(step.done),
              a.disabled(disabled),
              event.on_check(fn(value) {
                Action(d.StepDone(incident.id, step.id, value))
              }),
            ]),
          ]),
          button(
            "step-up",
            "Move step up",
            Action(d.MoveStep(incident.id, step.id, before(ids, index - 1))),
            disabled || index == 0,
          ),
          button(
            "step-down",
            "Move step down",
            Action(d.MoveStep(incident.id, step.id, before(ids, index + 2))),
            disabled || index == list.length(ids) - 1,
          ),
          button(
            "remove-step",
            "Delete step",
            Action(d.RemoveStep(incident.id, step.id)),
            disabled,
          ),
          transfer_controls(board, incident.id, step.id, transfers, disabled),
        ]),
      )
    }),
  )
}

fn incident(
  board: d.Board,
  value: d.Incident,
  ids: List(String),
  index: Int,
  transfers: Dict(String, #(String, Option(String))),
  disabled: Bool,
) -> Element(Msg) {
  h.section([a.attribute("data-incident-id", value.id)], [
    input(
      "title",
      "Title",
      value.title,
      fn(text) { Action(d.Title(value.id, text)) },
      disabled,
    ),
    h.label([], [
      h.text("Status"),
      h.select(
        [
          a.attribute("data-field", "status"),
          a.disabled(disabled),
          event.on_change(fn(text) {
            case text {
              "open" -> Action(d.Status(value.id, d.Open))
              "investigating" -> Action(d.Status(value.id, d.Investigating))
              "resolved" -> Action(d.Status(value.id, d.Resolved))
              _ -> InvalidStatus
            }
          }),
        ],
        list.map([d.Open, d.Investigating, d.Resolved], fn(status) {
          h.option(
            [
              a.value(d.status_name(status)),
              a.selected(value.status == status),
            ],
            d.status_name(status),
          )
        }),
      ),
    ]),
    input(
      "assignee",
      "Assignee",
      option.unwrap(value.assignee, ""),
      fn(text) { Action(d.Assignee(value.id, Some(text))) },
      disabled,
    ),
    h.span(
      [
        a.attribute("data-assignee-present", case value.assignee {
          Some(_) -> "true"
          None -> "false"
        }),
      ],
      [
        h.text(case value.assignee {
          Some(_) -> "Assigned"
          None -> "Unassigned"
        }),
      ],
    ),
    button(
      "assignee-remove",
      "Remove assignee",
      Action(d.Assignee(value.id, None)),
      disabled,
    ),
    button(
      "incident-up",
      "Move incident up",
      Action(d.MoveIncident(value.id, before(ids, index - 1))),
      disabled || index == 0,
    ),
    button(
      "incident-down",
      "Move incident down",
      Action(d.MoveIncident(value.id, before(ids, index + 2))),
      disabled || index == list.length(ids) - 1,
    ),
    button(
      "remove-incident",
      "Delete incident",
      Action(d.RemoveIncident(value.id)),
      disabled,
    ),
    button("add-step", "Add step", AddStep(value.id), disabled),
    steps(board, value, transfers, disabled),
  ])
}

fn view(current: Model) -> Element(Msg) {
  let state = model.read(current.model)
  let disabled = state.phase != d.Ready
  let ids = list.map(state.board.incidents, fn(value) { value.id })
  h.div([], [
    h.h1([], [h.text("Incident response board")]),
    h.p(
      [
        a.attribute("data-state", d.phase_name(state.phase)),
        a.attribute("role", "status"),
      ],
      [h.text(d.phase_name(state.phase))],
    ),
    h.div(
      [],
      list.map(list.append(state.errors, current.issues), fn(error) {
        h.p([a.attribute("role", "alert")], [h.text(error)])
      }),
    ),
    button("add-incident", "Add incident", AddIncident, disabled),
    case state.board.incidents {
      [] ->
        h.p([a.attribute("data-empty", "incidents")], [h.text("No incidents")])
      _ -> h.text("")
    },
    keyed.div(
      [],
      list.index_map(state.board.incidents, fn(value, index) {
        #(
          value.id,
          incident(state.board, value, ids, index, current.transfers, disabled),
        )
      }),
    ),
    button("close", "Close", Close, state.phase == d.Closed),
  ])
}
