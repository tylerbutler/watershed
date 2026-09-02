//// A deterministic connection graph for component ports.
////
//// A stored connection joins one output port to one input port. Two clients
//// can each add a connection that is acyclic in their own graph, yet the
//// merged set of connections can hold a cycle. This module reads the stored
//// list, checks each connection, and builds an effective graph that is always
//// acyclic and always the same on every target.
////
//// The module keeps every invalid stored connection as a diagnostic. It does
//// not change the stored list. A later render or merge step reads the
//// diagnostics to show what the graph dropped and why.
////
//// This module does not depend on the runtime target. It sorts connection IDs
//// by their UTF-8 bytes through `canonical_json.compare`, so the effective
//// graph keeps one order on Erlang and on JavaScript, even for astral
//// Unicode text.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}
import watershed/canonical_json
import watershed/port

/// A reference to one port on one component instance.
pub type PortRef {
  PortRef(instance_id: String, port_id: String)
}

/// A stored connection from one source port to one target port.
pub type Connection {
  Connection(id: String, source: PortRef, target: PortRef)
}

/// A reason the effective graph dropped one stored connection.
pub type GraphError {
  /// More than one stored connection carries this ID. The graph drops every
  /// connection with the ID and reports the ID one time.
  DuplicateConnection(connection_id: String)
  /// The connection names an instance the port lookup does not know.
  UnknownInstance(connection_id: String, instance_id: String)
  /// The named instance does not carry the named port.
  UnknownPort(connection_id: String, port: PortRef)
  /// The port has the wrong direction. The source must be an output port and
  /// the target must be an input port.
  WrongDirection(
    connection_id: String,
    port: PortRef,
    expected: port.DirectionKind,
  )
  /// The source port and the target port name different schema IDs.
  SchemaMismatch(connection_id: String, source: String, target: String)
  /// Adding the connection makes a cycle. The graph keeps the earlier edges
  /// and drops this one.
  Cycle(connection_id: String)
}

/// The result of reading a stored connection list. It holds the connections
/// the graph kept and one diagnostic for each connection it dropped.
pub opaque type EffectiveGraph {
  EffectiveGraph(connections: List(Connection), errors: List(GraphError))
}

type State {
  State(
    accepted: List(Connection),
    arcs: Dict(String, List(String)),
    errors: List(GraphError),
    emitted_duplicates: Set(String),
  )
}

/// Build one stored connection.
pub fn connection(id: String, source: PortRef, target: PortRef) -> Connection {
  Connection(id: id, source: source, target: target)
}

/// Read a stored connection list and build the effective graph.
///
/// `ports_for` returns the ports of one instance, or `Error(Nil)` when the
/// instance is not known. The function sorts the list by connection ID, drops
/// any ID that repeats, checks each remaining connection, and keeps only the
/// connections that pass and that do not make a cycle.
pub fn effective(
  stored: List(Connection),
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> EffectiveGraph {
  let sorted =
    list.sort(stored, fn(left, right) {
      canonical_json.compare(left.id, right.id)
    })
  let duplicates = duplicated_ids(sorted)
  let final =
    list.fold(sorted, new_state(), fn(state, connection) {
      step(state, connection, duplicates, ports_for)
    })
  EffectiveGraph(
    connections: list.reverse(final.accepted),
    errors: list.reverse(final.errors),
  )
}

/// The connections the graph kept, in sorted ID order.
pub fn connections(graph: EffectiveGraph) -> List(Connection) {
  graph.connections
}

/// One diagnostic for each stored connection the graph dropped.
pub fn errors(graph: EffectiveGraph) -> List(GraphError) {
  graph.errors
}

/// The kept connections that leave one port, in effective graph order.
pub fn outgoing(graph: EffectiveGraph, source: PortRef) -> List(Connection) {
  list.filter(graph.connections, fn(connection) { connection.source == source })
}

fn new_state() -> State {
  State(
    accepted: [],
    arcs: dict.new(),
    errors: [],
    emitted_duplicates: set.new(),
  )
}

fn duplicated_ids(connections: List(Connection)) -> Set(String) {
  let counts =
    list.fold(connections, dict.new(), fn(acc, connection) {
      dict.upsert(acc, connection.id, fn(existing) {
        case existing {
          option.Some(count) -> count + 1
          option.None -> 1
        }
      })
    })
  dict.fold(counts, set.new(), fn(acc, id, count) {
    case count > 1 {
      True -> set.insert(acc, id)
      False -> acc
    }
  })
}

fn step(
  state: State,
  connection: Connection,
  duplicates: Set(String),
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> State {
  case set.contains(duplicates, connection.id) {
    True -> record_duplicate(state, connection.id)
    False ->
      case validate(connection, ports_for) {
        Error(graph_error) ->
          State(..state, errors: [graph_error, ..state.errors])
        Ok(Nil) -> accept_or_cycle(state, connection)
      }
  }
}

fn record_duplicate(state: State, id: String) -> State {
  case set.contains(state.emitted_duplicates, id) {
    True -> state
    False ->
      State(
        ..state,
        errors: [DuplicateConnection(id), ..state.errors],
        emitted_duplicates: set.insert(state.emitted_duplicates, id),
      )
  }
}

fn accept_or_cycle(state: State, connection: Connection) -> State {
  let source = connection.source.instance_id
  let target = connection.target.instance_id
  case creates_cycle(source, target, state.arcs) {
    True -> State(..state, errors: [Cycle(connection.id), ..state.errors])
    False ->
      State(
        ..state,
        accepted: [connection, ..state.accepted],
        arcs: add_arc(state.arcs, source, target),
      )
  }
}

fn validate(
  connection: Connection,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Result(Nil, GraphError) {
  use source <- result.try(resolve(connection.id, connection.source, ports_for))
  use target <- result.try(resolve(connection.id, connection.target, ports_for))
  use _ <- result.try(check_direction(
    connection.id,
    connection.source,
    source,
    port.OutputDirection,
  ))
  use _ <- result.try(check_direction(
    connection.id,
    connection.target,
    target,
    port.InputDirection,
  ))
  case source.schema_id == target.schema_id {
    True -> Ok(Nil)
    False ->
      Error(SchemaMismatch(connection.id, source.schema_id, target.schema_id))
  }
}

fn resolve(
  id: String,
  ref: PortRef,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Result(port.Descriptor, GraphError) {
  case ports_for(ref.instance_id) {
    Error(Nil) -> Error(UnknownInstance(id, ref.instance_id))
    Ok(descriptors) ->
      case list.find(descriptors, fn(d) { d.id == ref.port_id }) {
        Ok(descriptor) -> Ok(descriptor)
        Error(Nil) -> Error(UnknownPort(id, ref))
      }
  }
}

fn check_direction(
  id: String,
  ref: PortRef,
  descriptor: port.Descriptor,
  expected: port.DirectionKind,
) -> Result(Nil, GraphError) {
  case port.direction_kind(descriptor.direction) == expected {
    True -> Ok(Nil)
    False -> Error(WrongDirection(id, ref, expected))
  }
}

fn add_arc(
  arcs: Dict(String, List(String)),
  from: String,
  to: String,
) -> Dict(String, List(String)) {
  dict.upsert(arcs, from, fn(existing) {
    case existing {
      option.Some(targets) -> [to, ..targets]
      option.None -> [to]
    }
  })
}

fn creates_cycle(
  source: String,
  target: String,
  arcs: Dict(String, List(String)),
) -> Bool {
  reachable([target], source, arcs, set.new())
}

/// Walk the arcs from a frontier of instances and look for one goal. The
/// visited set is shared by every branch, so the walk expands each instance
/// one time. One query therefore costs O(V + E).
fn reachable(
  frontier: List(String),
  goal: String,
  arcs: Dict(String, List(String)),
  visited: Set(String),
) -> Bool {
  case frontier {
    [] -> False
    [current, ..rest] ->
      case current == goal {
        True -> True
        False ->
          case set.contains(visited, current) {
            True -> reachable(rest, goal, arcs, visited)
            False -> {
              let next = dict.get(arcs, current) |> result.unwrap([])
              reachable(
                list.append(next, rest),
                goal,
                arcs,
                set.insert(visited, current),
              )
            }
          }
      }
  }
}
