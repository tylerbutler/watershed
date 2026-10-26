import gleam/option.{type Option}
import gleam/result
import incident_eval/domain as d
import watershed/tree/schema_builder as b
import watershed/tree/types

// mutation:start imports
// mutation:end imports

fn factory() -> b.Factory {
  b.factory("incident_eval")
}

pub fn incidents() -> b.Property(d.Board, List(d.Incident)) {
  b.required(
    "incidents",
    b.array(factory(), "Incidents", incident()),
    fn(v: d.Board) { v.incidents },
  )
}

pub fn incident_id() -> b.Property(d.Incident, String) {
  b.required("id", b.string(), fn(v: d.Incident) { v.id })
}

pub fn title() -> b.Property(d.Incident, String) {
  b.required("title", b.string(), fn(v: d.Incident) { v.title })
}

pub fn status() -> b.Property(d.Incident, String) {
  b.required("status", b.string(), fn(v: d.Incident) { d.status_name(v.status) })
}

pub fn assignee() -> b.Property(d.Incident, Option(String)) {
  b.optional("assignee", b.string(), fn(v: d.Incident) { v.assignee })
}

pub fn steps() -> b.Property(d.Incident, List(d.Step)) {
  b.required("steps", b.array(factory(), "Steps", step()), fn(v: d.Incident) {
    v.steps
  })
}

pub fn step_id() -> b.Property(d.Step, String) {
  b.required("id", b.string(), fn(v: d.Step) { v.id })
}

pub fn label() -> b.Property(d.Step, String) {
  b.required("label", b.string(), fn(v: d.Step) { v.label })
}

pub fn done() -> b.Property(d.Step, Bool) {
  b.required("done", b.boolean(), fn(v: d.Step) { v.done })
}

fn step() -> b.Node(d.Step) {
  b.object3(factory(), "Step", d.Step, step_id(), label(), done())
}

fn incident() -> b.Node(d.Incident) {
  b.object(
    factory(),
    "Incident",
    [
      b.property(incident_id()),
      b.property(title()),
      b.property(status()),
      b.property(assignee()),
      b.property(steps()),
    ],
    fn(reader) {
      use id <- result.try(b.read_property(reader, incident_id()))
      use title <- result.try(b.read_property(reader, title()))
      use status <- result.try(b.read_property(reader, status()))
      use assignee <- result.try(b.read_property(reader, assignee()))
      use steps <- result.try(b.read_property(reader, steps()))
      use status <- result.try(case status {
        "open" -> Ok(d.Open)
        "investigating" -> Ok(d.Investigating)
        "resolved" -> Ok(d.Resolved)
        _ -> Error(types.InvalidEdit(["status"], "Invalid status"))
      })
      Ok(d.Incident(id, title, status, assignee, steps))
    },
  )
}

pub fn configuration() -> b.Root(d.Board) {
  // mutation:start board-schema
  b.object1(factory(), "Board", d.Board, incidents()) |> b.root
  // mutation:end board-schema
}
