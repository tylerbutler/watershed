import gleam/json
import gleam/list
import gleam/option.{None, Some}
import incident_eval/domain as d
import lustre/effect.{type Effect}

pub opaque type Model {
  Model(state: d.State)
}

pub opaque type Msg {
  Unused
}

@external(javascript, "./fixture.mjs", "record")
fn record(value: String) -> Nil

@external(javascript, "./fixture.mjs", "empty")
fn empty() -> Bool

@external(javascript, "./fixture.mjs", "failEdit")
fn fail_edit() -> Bool

pub fn init(_config: d.Config) -> #(Model, Effect(Msg)) {
  #(
    Model(
      d.State(
        d.Ready,
        None,
        d.Board(case empty() {
          True -> []
          False -> [
            d.Incident("incident-a", "First", d.Open, Some("Alex"), [
              d.Step("step-a", "One", False),
              d.Step("step-b", "Two", False),
            ]),
            d.Incident("incident-b", "Second", d.Open, None, []),
          ]
        }),
        [],
      ),
    ),
    effect.none(),
  )
}

pub fn update(model: Model, _message: Msg) -> #(Model, Effect(Msg)) {
  #(model, effect.none())
}

pub fn apply(model: Model, action: d.Action) -> #(Model, Effect(Msg)) {
  let fields = case action {
    d.AddIncident(id, title) -> [
      #("type", json.string("add-incident")),
      #("id", json.string(id)),
      #("title", json.string(title)),
    ]
    d.Title(id, value) -> [
      #("type", json.string("title")),
      #("id", json.string(id)),
      #("value", json.string(value)),
    ]
    d.MoveIncident(id, before) -> [
      #("type", json.string("move-incident")),
      #("id", json.string(id)),
      #("before", json.nullable(before, json.string)),
    ]
    d.Assignee(id, value) -> [
      #("type", json.string("assignee")),
      #("id", json.string(id)),
      #("value", json.nullable(value, json.string)),
    ]
    d.MoveStep(incident, id, before) -> [
      #("type", json.string("move-step")),
      #("incident", json.string(incident)),
      #("id", json.string(id)),
      #("before", json.nullable(before, json.string)),
    ]
    _ -> [#("type", json.string("other"))]
  }
  let incidents = case action {
    d.AddIncident(id, title) ->
      list.append(model.state.board.incidents, [
        d.Incident(id, title, d.Open, None, []),
      ])
    d.Title(id, value) ->
      list.map(model.state.board.incidents, fn(incident) {
        case incident.id == id {
          True -> d.Incident(..incident, title: value)
          False -> incident
        }
      })
    _ -> model.state.board.incidents
  }
  #(
    Model(
      d.State(
        ..model.state,
        board: d.Board(incidents),
        errors: case action, fail_edit() {
          d.Title(_, _), True -> ["Service rejected the edit"]
          _, _ -> model.state.errors
        },
      ),
    ),
    effect.from(fn(_) { record(json.to_string(json.object(fields))) }),
  )
}

pub fn close(model: Model) -> #(Model, Effect(Msg)) {
  #(Model(d.State(..model.state, phase: d.Closed)), effect.none())
}

pub fn read(model: Model) -> d.State {
  model.state
}
