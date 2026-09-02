import gleam/int
import gleam/list
import startest/expect
import watershed/port
import watershed/port_graph

fn output(id: String, schema_id: String) -> port.Descriptor {
  port.Descriptor(id, port.OutputPort, schema_id)
}

fn local_input(id: String, schema_id: String) -> port.Descriptor {
  port.Descriptor(id, port.InputPort(port.LocalInput), schema_id)
}

fn ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([output("completed", "task@1"), local_input("open", "task@1")])
    "activity" ->
      Ok([output("selected", "task@1"), local_input("append", "task@1")])
    "notes" -> Ok([local_input("focus", "task@1")])
    _ -> Error(Nil)
  }
}

fn triad_ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "a" | "b" | "c" -> Ok([output("out", "s@1"), local_input("in", "s@1")])
    _ -> Error(Nil)
  }
}

fn edge(
  id: String,
  source_instance: String,
  source_port: String,
  target_instance: String,
  target_port: String,
) -> port_graph.Connection {
  port_graph.connection(
    id,
    port_graph.PortRef(source_instance, source_port),
    port_graph.PortRef(target_instance, target_port),
  )
}

pub fn valid_edges_are_sorted_by_id_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("b", "activity", "selected", "notes", "focus"),
        edge("a", "tasks", "completed", "activity", "append"),
      ],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["a", "b"])
}

pub fn unknown_instance_is_reported_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("a", "missing", "completed", "activity", "append")],
      ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.UnknownInstance("a", "missing")])
}

pub fn unknown_port_is_reported_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("a", "tasks", "ghost", "activity", "append")],
      ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([
    port_graph.UnknownPort("a", port_graph.PortRef("tasks", "ghost")),
  ])
}

pub fn wrong_direction_is_reported_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("a", "tasks", "open", "activity", "append")],
      ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([
    port_graph.WrongDirection(
      "a",
      port_graph.PortRef("tasks", "open"),
      port.OutputDirection,
    ),
  ])
}

pub fn schema_mismatch_is_reported_test() -> Nil {
  let mismatched_ports = fn(instance_id) {
    case instance_id {
      "tasks" -> Ok([output("completed", "task@1")])
      "activity" -> Ok([local_input("append", "activity@1")])
      _ -> Error(Nil)
    }
  }
  let graph =
    port_graph.effective(
      [edge("a", "tasks", "completed", "activity", "append")],
      mismatched_ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.SchemaMismatch("a", "task@1", "activity@1")])
}

pub fn duplicate_id_rejects_all_and_reports_once_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("dup", "tasks", "completed", "activity", "append"),
        edge("dup", "activity", "selected", "notes", "focus"),
      ],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal([])

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.DuplicateConnection("dup")])
}

pub fn merged_cycle_keeps_lexically_first_acyclic_edges_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("02-activity-tasks", "activity", "selected", "tasks", "open"),
        edge("01-tasks-activity", "tasks", "completed", "activity", "append"),
      ],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["01-tasks-activity"])

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.Cycle("02-activity-tasks")])
}

pub fn self_edge_is_a_cycle_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("x", "tasks", "completed", "tasks", "open")],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal([])

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.Cycle("x")])
}

pub fn three_instance_cycle_keeps_lexically_first_edges_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("1", "a", "out", "b", "in"),
        edge("2", "b", "out", "c", "in"),
        edge("3", "c", "out", "a", "in"),
      ],
      triad_ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["1", "2"])

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.Cycle("3")])
}

pub fn outgoing_returns_edges_from_a_port_in_order_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("a", "tasks", "completed", "activity", "append"),
        edge("b", "activity", "selected", "notes", "focus"),
      ],
      ports,
    )

  port_graph.outgoing(graph, port_graph.PortRef("tasks", "completed"))
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["a"])
}

pub fn permutation_keeps_stable_result_test() -> Nil {
  let edges = [
    edge("01-tasks-activity", "tasks", "completed", "activity", "append"),
    edge("02-activity-tasks", "activity", "selected", "tasks", "open"),
    edge("03-activity-notes", "activity", "selected", "notes", "focus"),
  ]

  list.permutations(edges)
  |> list.each(fn(permutation) {
    let graph = port_graph.effective(permutation, ports)

    port_graph.connections(graph)
    |> list.map(fn(connection) { connection.id })
    |> expect.to_equal(["01-tasks-activity", "03-activity-notes"])

    port_graph.errors(graph)
    |> expect.to_equal([port_graph.Cycle("02-activity-tasks")])
  })
}

pub fn permutation_rejects_duplicate_ids_test() -> Nil {
  let edges = [
    edge("dup", "tasks", "completed", "activity", "append"),
    edge("dup", "activity", "selected", "notes", "focus"),
    edge("keep", "tasks", "completed", "activity", "append"),
  ]

  list.permutations(edges)
  |> list.each(fn(permutation) {
    let graph = port_graph.effective(permutation, ports)

    port_graph.connections(graph)
    |> list.map(fn(connection) { connection.id })
    |> expect.to_equal(["keep"])

    port_graph.errors(graph)
    |> expect.to_equal([port_graph.DuplicateConnection("dup")])
  })
}

fn any_instance_ports(
  _instance_id: String,
) -> Result(List(port.Descriptor), Nil) {
  Ok([output("out", "s@1"), local_input("in", "s@1")])
}

fn diamond_edges(count: Int) -> List(port_graph.Connection) {
  list.repeat(Nil, count)
  |> list.index_map(fn(_, index) { index })
  |> list.flat_map(fn(index) {
    let label = int.to_string(index)
    let node = "n" <> label
    let next = "n" <> int.to_string(index + 1)
    let left = "x" <> label
    let right = "y" <> label
    [
      edge("a-" <> label <> "-left", node, "out", left, "in"),
      edge("a-" <> label <> "-right", node, "out", right, "in"),
      edge("b-" <> label <> "-left", left, "out", next, "in"),
      edge("b-" <> label <> "-right", right, "out", next, "in"),
    ]
  })
}

pub fn reconverging_paths_visit_each_instance_one_time_test() -> Nil {
  let count = 24
  let stored =
    list.append(diamond_edges(count), [edge("z", "z", "out", "n0", "in")])

  let graph = port_graph.effective(stored, any_instance_ports)

  port_graph.errors(graph)
  |> expect.to_equal([])

  port_graph.connections(graph)
  |> list.length
  |> expect.to_equal(count * 4 + 1)
}

pub fn reconverging_paths_still_find_a_cycle_test() -> Nil {
  let count = 24
  let last = "n" <> int.to_string(count)
  let stored =
    list.append(diamond_edges(count), [edge("z", last, "out", "n0", "in")])

  let graph = port_graph.effective(stored, any_instance_ports)

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.Cycle("z")])

  port_graph.connections(graph)
  |> list.length
  |> expect.to_equal(count * 4)
}
