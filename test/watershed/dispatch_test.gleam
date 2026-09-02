import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/dispatch
import watershed/port
import watershed/port_graph

fn ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([
        port.Descriptor("completed", port.OutputPort, "task@1", None),
      ])
    "activity" ->
      Ok([
        port.Descriptor(
          "append",
          port.InputPort,
          "task@1",
          Some(port.CollaborativeInput(capabilities: ["sequence:insert"])),
        ),
      ])
    "notes" ->
      Ok([
        port.Descriptor(
          "focus",
          port.InputPort,
          "task@1",
          Some(port.LocalInput),
        ),
      ])
    _ -> Error(Nil)
  }
}

fn graph() -> port_graph.EffectiveGraph {
  port_graph.effective(
    [
      port_graph.connection(
        "activity",
        port_graph.PortRef("tasks", "completed"),
        port_graph.PortRef("activity", "append"),
      ),
      port_graph.connection(
        "notes",
        port_graph.PortRef("tasks", "completed"),
        port_graph.PortRef("notes", "focus"),
      ),
    ],
    ports,
  )
}

pub fn local_intent_fans_out_in_edge_order_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-1",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports,
    )

  dispatch.deliveries(planned)
  |> list.map(fn(delivery) { delivery.edge_id })
  |> expect.to_equal(["activity", "notes"])
}

pub fn replicated_change_produces_no_deliveries_test() -> Nil {
  dispatch.plan(
    trace_id: "trace-2",
    origin: dispatch.ReplicatedChange,
    source: port_graph.PortRef("tasks", "completed"),
    payload: json.string("task-42"),
    graph: graph(),
    ports_for: ports,
  )
  |> dispatch.deliveries
  |> expect.to_equal([])
}

pub fn delivery_keeps_target_class_and_capabilities_test() -> Nil {
  let assert [delivery, ..] =
    dispatch.plan(
      "trace-3",
      dispatch.LocalIntent,
      port_graph.PortRef("tasks", "completed"),
      json.string("task-42"),
      graph(),
      ports,
    )
    |> dispatch.deliveries

  delivery.input_class
  |> expect.to_equal(port.CollaborativeInput(capabilities: ["sequence:insert"]))
}

pub fn deliveries_carry_unique_edge_ids_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-4",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports,
    )

  let edge_ids =
    dispatch.deliveries(planned)
    |> list.map(fn(delivery) { delivery.edge_id })

  edge_ids
  |> list.unique
  |> expect.to_equal(edge_ids)
}

fn ports_with_stale_activity(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "activity" -> Ok([])
    other -> ports(other)
  }
}

pub fn stale_target_descriptor_reports_target_unavailable_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-5",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports_with_stale_activity,
    )

  dispatch.errors(planned)
  |> expect.to_equal([
    dispatch.TargetUnavailable(
      "activity",
      port_graph.PortRef("activity", "append"),
    ),
  ])

  dispatch.deliveries(planned)
  |> list.map(fn(delivery) { delivery.edge_id })
  |> expect.to_equal(["notes"])
}

fn project_room_ports(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([
        port.Descriptor("task-selected", port.OutputPort, "task-id@1", None),
        port.Descriptor("task-completed", port.OutputPort, "task-id@1", None),
      ])
    "notes" ->
      Ok([
        port.Descriptor(
          "focus-subject",
          port.InputPort,
          "task-id@1",
          Some(port.LocalInput),
        ),
      ])
    "activity" ->
      Ok([
        port.Descriptor(
          "append-entry",
          port.InputPort,
          "task-id@1",
          Some(port.CollaborativeInput(capabilities: ["sequence:insert"])),
        ),
      ])
    _ -> Error(Nil)
  }
}

fn project_room_graph() -> port_graph.EffectiveGraph {
  port_graph.effective(
    [
      port_graph.connection(
        "focus",
        port_graph.PortRef("tasks", "task-selected"),
        port_graph.PortRef("notes", "focus-subject"),
      ),
      port_graph.connection(
        "append",
        port_graph.PortRef("tasks", "task-completed"),
        port_graph.PortRef("activity", "append-entry"),
      ),
    ],
    project_room_ports,
  )
}

pub fn project_room_local_intent_reaches_both_edges_test() -> Nil {
  let focus_plan =
    dispatch.plan(
      trace_id: "trace-focus",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "task-selected"),
      payload: json.string("task-42"),
      graph: project_room_graph(),
      ports_for: project_room_ports,
    )
  let assert [focus_delivery] = dispatch.deliveries(focus_plan)
  focus_delivery.input_class
  |> expect.to_equal(port.LocalInput)

  let append_plan =
    dispatch.plan(
      trace_id: "trace-append",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "task-completed"),
      payload: json.string("task-42"),
      graph: project_room_graph(),
      ports_for: project_room_ports,
    )
  let assert [append_delivery] = dispatch.deliveries(append_plan)
  append_delivery.input_class
  |> expect.to_equal(port.CollaborativeInput(capabilities: ["sequence:insert"]))

  dispatch.plan(
    trace_id: "trace-focus-echo",
    origin: dispatch.ReplicatedChange,
    source: port_graph.PortRef("tasks", "task-selected"),
    payload: json.string("task-42"),
    graph: project_room_graph(),
    ports_for: project_room_ports,
  )
  |> dispatch.deliveries
  |> expect.to_equal([])

  dispatch.plan(
    trace_id: "trace-append-echo",
    origin: dispatch.ReplicatedChange,
    source: port_graph.PortRef("tasks", "task-completed"),
    payload: json.string("task-42"),
    graph: project_room_graph(),
    ports_for: project_room_ports,
  )
  |> dispatch.deliveries
  |> expect.to_equal([])
}
