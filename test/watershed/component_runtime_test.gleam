import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/component
import watershed/component_runtime
import watershed/dispatch
import watershed/port
import watershed/port_graph
import watershed/workspace

fn entry(
  instance_id: String,
  kind: String,
  config: String,
) -> workspace.ManifestEntry {
  workspace.ManifestEntry(
    instance_id: instance_id,
    kind: kind,
    version: 1,
    config: json.string(config),
    child_handle: json.string("child-" <> instance_id),
  )
}

pub fn reconcile_keeps_stops_and_starts_by_persisted_identity_test() -> Nil {
  let unchanged = entry("a", "tasks", "same")
  let replacement = entry("b", "notes", "new")
  let removed = entry("c", "activity", "old")
  let current = [
    component_runtime.CurrentInstance("c", component_runtime.identity(removed)),
    component_runtime.CurrentInstance(
      "b",
      component_runtime.identity(entry("b", "notes", "old")),
    ),
    component_runtime.CurrentInstance(
      "a",
      component_runtime.identity(unchanged),
    ),
  ]

  let plan =
    component_runtime.reconcile(current, [
      workspace.Prepared(replacement, "map-b"),
      workspace.Prepared(unchanged, "map-a"),
    ])

  component_runtime.keeps(plan) |> expect.to_equal(["a"])
  component_runtime.stops(plan) |> expect.to_equal(["b", "c"])
  component_runtime.starts(plan)
  |> expect.to_equal([
    component_runtime.StartInstance(
      replacement,
      component_runtime.identity(replacement),
      "map-b",
    ),
  ])
}

pub fn reconcile_stops_running_instances_that_become_blocked_test() -> Nil {
  let loading = entry("a", "tasks", "same")
  let unavailable = entry("b", "missing", "same")
  let current = [
    component_runtime.CurrentInstance("a", component_runtime.identity(loading)),
    component_runtime.CurrentInstance(
      "b",
      component_runtime.identity(unavailable),
    ),
  ]

  let plan =
    component_runtime.reconcile(current, [
      workspace.Loading(loading, "child is not attached"),
      workspace.Unavailable(unavailable, component.NotRegistered("missing")),
      workspace.Failed("c", workspace.StoredIdMismatch("encoded-c")),
    ])

  component_runtime.stops(plan) |> expect.to_equal(["a", "b"])
  component_runtime.keeps(plan) |> expect.to_equal([])
  component_runtime.starts(plan) |> expect.to_equal([])
  component_runtime.blocked(plan)
  |> expect.to_equal([
    component_runtime.Loading(loading, "child is not attached"),
    component_runtime.Unavailable(
      unavailable,
      component.NotRegistered("missing"),
    ),
    component_runtime.Failed("c", workspace.StoredIdMismatch("encoded-c")),
  ])
}

pub fn trace_keeps_graph_order_and_schedules_each_edge_once_test() -> Nil {
  let first = delivery("trace-1", "edge-a", "notes")
  let duplicate = delivery("trace-1", "edge-a", "notes")
  let second = delivery("trace-1", "edge-b", "activity")
  let trace =
    component_runtime.new_trace("trace-1")
    |> component_runtime.enqueue([first, duplicate, second])

  component_runtime.trace_id(trace) |> expect.to_equal("trace-1")
  component_runtime.seen_edges(trace)
  |> expect.to_equal(["edge-a", "edge-b"])

  let #(next, trace) = component_runtime.next(trace)
  next |> expect.to_equal(Some(first))
  let #(next, trace) = component_runtime.next(trace)
  next |> expect.to_equal(Some(second))
  let #(next, trace) = component_runtime.next(trace)
  next |> expect.to_equal(None)
  component_runtime.is_empty(trace) |> expect.to_equal(True)
}

pub fn a_later_cascade_cannot_reschedule_an_executed_edge_test() -> Nil {
  let first = delivery("trace-1", "edge-a", "notes")
  let second = delivery("trace-1", "edge-b", "activity")
  let trace =
    component_runtime.new_trace("trace-1")
    |> component_runtime.enqueue([first])
  let #(_, trace) = component_runtime.next(trace)
  let trace = component_runtime.enqueue(trace, [first, second])

  component_runtime.seen_edges(trace)
  |> expect.to_equal(["edge-a", "edge-b"])
  let #(next, trace) = component_runtime.next(trace)
  next |> expect.to_equal(Some(second))
  component_runtime.is_empty(trace) |> expect.to_equal(True)
}

fn delivery(
  trace_id: String,
  edge_id: String,
  target_id: String,
) -> dispatch.Delivery {
  dispatch.Delivery(
    trace: dispatch.Trace(trace_id),
    edge_id: edge_id,
    target: port_graph.PortRef(target_id, "input"),
    input_class: port.LocalInput,
    payload: json.string("payload"),
  )
}
