import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import startest/expect
import watershed/component
import watershed/dispatch
import watershed/port
import watershed/port_graph

fn ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" -> Ok([port.Descriptor("completed", port.OutputPort, "task@1")])
    "activity" ->
      Ok([
        port.Descriptor(
          "append",
          port.InputPort(
            port.CollaborativeInput(capabilities: ["sequence:insert"]),
          ),
          "task@1",
        ),
      ])
    "notes" ->
      Ok([port.Descriptor("focus", port.InputPort(port.LocalInput), "task@1")])
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

pub fn every_delivery_carries_the_dispatch_trace_test() -> Nil {
  dispatch.plan(
    trace_id: "trace-carried",
    origin: dispatch.LocalIntent,
    source: port_graph.PortRef("tasks", "completed"),
    payload: json.string("task-42"),
    graph: graph(),
    ports_for: ports,
  )
  |> dispatch.deliveries
  |> list.map(fn(delivery) { delivery.trace })
  |> expect.to_equal([
    dispatch.Trace("trace-carried"),
    dispatch.Trace("trace-carried"),
  ])
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
      dispatch.Trace("trace-5"),
      "activity",
      port_graph.PortRef("activity", "append"),
    ),
  ])

  dispatch.deliveries(planned)
  |> list.map(fn(delivery) { delivery.edge_id })
  |> expect.to_equal(["notes"])
}

fn ports_without_tasks(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" -> Error(Nil)
    other -> ports(other)
  }
}

pub fn missing_source_instance_reports_source_unavailable_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-6",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports_without_tasks,
    )

  dispatch.errors(planned)
  |> expect.to_equal([
    dispatch.SourceUnavailable(
      dispatch.Trace("trace-6"),
      port_graph.PortRef("tasks", "completed"),
    ),
  ])

  dispatch.deliveries(planned)
  |> expect.to_equal([])
}

fn ports_with_input_source(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([
        port.Descriptor("completed", port.InputPort(port.LocalInput), "task@1"),
      ])
    other -> ports(other)
  }
}

pub fn source_that_is_no_longer_an_output_is_unavailable_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-7",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports_with_input_source,
    )

  dispatch.errors(planned)
  |> expect.to_equal([
    dispatch.SourceUnavailable(
      dispatch.Trace("trace-7"),
      port_graph.PortRef("tasks", "completed"),
    ),
  ])
}

fn ports_with_new_activity_schema(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "activity" ->
      Ok([
        port.Descriptor(
          "append",
          port.InputPort(
            port.CollaborativeInput(capabilities: ["sequence:insert"]),
          ),
          "task@2",
        ),
      ])
    other -> ports(other)
  }
}

pub fn target_schema_change_reports_schema_changed_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-8",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports_with_new_activity_schema,
    )

  dispatch.errors(planned)
  |> expect.to_equal([
    dispatch.SchemaChanged(
      dispatch.Trace("trace-8"),
      "activity",
      "task@1",
      "task@2",
    ),
  ])

  dispatch.deliveries(planned)
  |> list.map(fn(delivery) { delivery.edge_id })
  |> expect.to_equal(["notes"])
}

fn ports_with_new_source_schema(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" -> Ok([port.Descriptor("completed", port.OutputPort, "task@2")])
    other -> ports(other)
  }
}

pub fn source_schema_change_reports_every_edge_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-9",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports_with_new_source_schema,
    )

  dispatch.errors(planned)
  |> expect.to_equal([
    dispatch.SchemaChanged(
      dispatch.Trace("trace-9"),
      "activity",
      "task@2",
      "task@1",
    ),
    dispatch.SchemaChanged(
      dispatch.Trace("trace-9"),
      "notes",
      "task@2",
      "task@1",
    ),
  ])

  dispatch.deliveries(planned)
  |> expect.to_equal([])
}

fn project_room_ports(
  instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([
        port.Descriptor("task-selected", port.OutputPort, "task-id@1"),
        port.Descriptor("task-completed", port.OutputPort, "task-id@1"),
      ])
    "notes" ->
      Ok([
        port.Descriptor(
          "focus-subject",
          port.InputPort(port.LocalInput),
          "task-id@1",
        ),
      ])
    "activity" ->
      Ok([
        port.Descriptor(
          "append-entry",
          port.InputPort(
            port.CollaborativeInput(capabilities: ["sequence:insert"]),
          ),
          "task-id@1",
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

fn tasks_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/tasks",
    version: 1,
    config_decoder: decode.success(Nil),
    start: fn(context, _config) { Ok(context) },
    ports: [
      port.output_descriptor(port.output(
        "task-completed",
        "task-id@1",
        json.string,
      )),
    ],
  )
}

fn activity_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/activity",
    version: 1,
    config_decoder: decode.success(Nil),
    start: fn(context, _config) { Ok(context) },
    ports: [
      port.input_descriptor(
        port.collaborative_input("append-entry", "task-id@1", decode.string, [
          "sequence:insert",
        ]),
      ),
    ],
  )
}

fn catalog() -> component.Catalog(String, String) {
  let assert Ok(with_tasks) =
    component.register(component.new_catalog(), tasks_descriptor())
  let assert Ok(full) = component.register(with_tasks, activity_descriptor())
  full
}

fn manifest_ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  let kind = case instance_id {
    "tasks-1" -> Ok("watershed/tasks")
    "activity-1" -> Ok("watershed/activity")
    _ -> Error(Nil)
  }

  use kind <- result.try(kind)
  component.find(catalog(), kind, 1)
  |> result.map(component.ports)
  |> result.replace_error(Nil)
}

pub fn catalog_ports_drive_the_graph_and_the_plan_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        port_graph.connection(
          "tasks-to-activity",
          port_graph.PortRef("tasks-1", "task-completed"),
          port_graph.PortRef("activity-1", "append-entry"),
        ),
      ],
      manifest_ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([])

  let planned =
    dispatch.plan(
      trace_id: "trace-catalog",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks-1", "task-completed"),
      payload: json.string("task-42"),
      graph: graph,
      ports_for: manifest_ports,
    )

  dispatch.errors(planned)
  |> expect.to_equal([])

  dispatch.deliveries(planned)
  |> expect.to_equal([
    dispatch.Delivery(
      trace: dispatch.Trace("trace-catalog"),
      edge_id: "tasks-to-activity",
      target: port_graph.PortRef("activity-1", "append-entry"),
      input_class: port.CollaborativeInput(capabilities: ["sequence:insert"]),
      payload: json.string("task-42"),
    ),
  ])
}
