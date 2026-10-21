import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import incident_eval/domain as d
import watershed/tree/types

// fixture:start codec
pub fn mutation_encode(board: d.Board) -> String {
  json.object([
    #(
      "incidents",
      json.array(board.incidents, fn(incident) {
        json.object([
          #("id", json.string(incident.id)),
          #("title", json.string(incident.title)),
          #("status", json.string(d.status_name(incident.status))),
          #("assignee", case incident.assignee {
            option.None -> json.null()
            option.Some(value) -> json.string(value)
          }),
          #(
            "steps",
            json.array(incident.steps, fn(step) {
              json.object([
                #("id", json.string(step.id)),
                #("label", json.string(step.label)),
                #("done", json.bool(step.done)),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
  |> json.to_string
}

pub fn mutation_decode(text: String) -> Result(d.Board, types.TreeError) {
  let step = {
    use id <- decode.field("id", decode.string)
    use label <- decode.field("label", decode.string)
    use done <- decode.field("done", decode.bool)
    decode.success(d.Step(id, label, done))
  }
  let incident = {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use status <- decode.field("status", decode.string)
    use assignee <- decode.field("assignee", decode.optional(decode.string))
    use steps <- decode.field("steps", decode.list(step))
    decode.success(d.Incident(
      id,
      title,
      case status {
        "investigating" -> d.Investigating
        "resolved" -> d.Resolved
        _ -> d.Open
      },
      assignee,
      steps,
    ))
  }
  json.parse(text, {
    use incidents <- decode.field("incidents", decode.list(incident))
    decode.success(d.Board(incidents))
  })
  |> result.map_error(fn(_) {
    types.CorruptData("serialized board", "Invalid JSON board")
  })
}

// fixture:end codec

// fixture:start actions
fn mutation_move(
  items: List(a),
  id: String,
  before,
  get_id: fn(a) -> String,
) -> List(a) {
  case before == Some(id), list.find(items, fn(item) { get_id(item) == id }) {
    True, _ | _, Error(_) -> items
    False, Ok(item) -> {
      let rest = list.filter(items, fn(item) { get_id(item) != id })
      mutation_insert(rest, item, before, get_id)
    }
  }
}

fn mutation_insert(
  items: List(a),
  item: a,
  before,
  get_id: fn(a) -> String,
) -> List(a) {
  case items, before {
    [], _ -> [item]
    _, None -> list.append(items, [item])
    [head, ..tail], Some(id) ->
      case get_id(head) == id {
        True -> [item, ..items]
        False -> [head, ..mutation_insert(tail, item, before, get_id)]
      }
  }
}

pub fn mutation_apply(board: d.Board, action: d.Action) -> d.Board {
  let incidents = case action {
    d.AddIncident(id, title) ->
      list.append(board.incidents, [d.Incident(id, title, d.Open, None, [])])
    d.RemoveIncident(id) ->
      list.filter(board.incidents, fn(incident) { incident.id != id })
    d.MoveIncident(id, before) ->
      mutation_move(board.incidents, id, before, fn(incident) { incident.id })
    _ ->
      list.map(board.incidents, fn(incident) {
        case action {
          d.Title(id, value) if incident.id == id ->
            d.Incident(..incident, title: value)
          d.Status(id, value) if incident.id == id ->
            d.Incident(..incident, status: value)
          d.Assignee(id, value) if incident.id == id ->
            d.Incident(..incident, assignee: value)
          d.AddStep(parent, id, label) if incident.id == parent ->
            d.Incident(
              ..incident,
              steps: list.append(incident.steps, [d.Step(id, label, False)]),
            )
          d.RemoveStep(parent, id) if incident.id == parent ->
            d.Incident(
              ..incident,
              steps: list.filter(incident.steps, fn(step) { step.id != id }),
            )
          d.MoveStep(parent, id, before) if incident.id == parent ->
            d.Incident(
              ..incident,
              steps: mutation_move(incident.steps, id, before, fn(step) {
                step.id
              }),
            )
          d.StepLabel(parent, id, value) if incident.id == parent ->
            d.Incident(
              ..incident,
              steps: list.map(incident.steps, fn(step) {
                case step.id == id {
                  True -> d.Step(..step, label: value)
                  False -> step
                }
              }),
            )
          d.StepDone(parent, id, value) if incident.id == parent ->
            d.Incident(
              ..incident,
              steps: list.map(incident.steps, fn(step) {
                case step.id == id {
                  True -> d.Step(..step, done: value)
                  False -> step
                }
              }),
            )
          _ -> incident
        }
      })
  }
  d.Board(incidents)
}
// fixture:end actions
