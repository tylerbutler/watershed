//// Origin-aware dispatch planning for component ports.
////
//// A local intent starts inside one client. A replicated change arrives
//// from another client after the collaborative store already applied it.
//// This module turns one payload at one output port into a list of
//// deliveries for its connected input ports, but only for a local intent.
//// A replicated change produces no deliveries, because a collaborative
//// input port already saw the change through the store, and a local input
//// port must not see a change that did not start on this client.
////
//// This module does not depend on the runtime target. It does not decode
//// the payload and it does not call component code. The runtime execution
//// plan reads each `Delivery`, decodes the payload with the target port's
//// typed decoder, and calls the component immediately after.
////
//// One `plan` call is one step of a dispatch trace. This module keeps no
//// state between calls. The rule that the shell runs each edge at most one
//// time in one dispatch trace therefore belongs to the later stateful
//// runtime layer. One target can receive a payload through two paths, emit
//// an output, and start the same downstream edge two times in one trace.
//// Only a layer that remembers the edges of a trace can stop that cascade.

import gleam/json.{type Json}
import gleam/list
import watershed/port
import watershed/port_graph

/// Where a payload started.
///
/// `LocalIntent` names a payload that started on this client, for example a
/// user action. `ReplicatedChange` names a payload that arrived from the
/// collaborative store after another client, or this client, already
/// applied it.
pub type Origin {
  LocalIntent
  ReplicatedChange
}

/// One dispatch attempt. Trace metadata follows a delivery through logs and
/// diagnostics.
pub type Trace {
  Trace(id: String)
}

/// One payload routed to one target port.
///
/// `edge_id` names the connection the payload crossed, so a log can join a
/// delivery back to the stored connection list. `input_class` is a copy of
/// the target port's class at plan time, so a caller can check capabilities
/// without a second catalog read.
pub type Delivery {
  Delivery(
    trace: Trace,
    edge_id: String,
    target: port_graph.PortRef,
    input_class: port.InputClass,
    payload: Json,
  )
}

/// A reason the plan could not build one delivery. Every reason carries the
/// dispatch trace, so a caller that batches plans can associate one error
/// with one trace.
pub type DispatchError {
  /// The source port is no longer present, or it is no longer an output
  /// port. The plan builds no delivery.
  SourceUnavailable(trace: Trace, source: port_graph.PortRef)
  /// The target instance is no longer present, the target port is no longer
  /// present, or the target port is no longer an input port. The host
  /// catalog changed between the graph's construction and this dispatch.
  TargetUnavailable(trace: Trace, edge_id: String, target: port_graph.PortRef)
  /// The source port and the target port now name different schema IDs. The
  /// host catalog changed a schema ID after the graph accepted this edge,
  /// so the target can no longer decode the payload.
  SchemaChanged(trace: Trace, edge_id: String, source: String, target: String)
}

/// The result of planning one dispatch. Holds the deliveries to send and one
/// diagnostic for each edge the plan could not resolve.
pub opaque type Plan {
  Plan(deliveries: List(Delivery), errors: List(DispatchError))
}

/// Plan the deliveries for one payload at one output port.
///
/// `graph` supplies the effective connections in graph order. `ports_for`
/// re-reads the current port descriptors for one instance, so the plan
/// catches a port that a host catalog change removed or changed since the
/// graph was built. The plan compares the current schema ID of the source
/// port against the current schema ID of each target port, and it reports
/// `SchemaChanged` for a target that no longer matches. Returns an empty
/// plan without reading the graph when `origin` is `ReplicatedChange`.
pub fn plan(
  trace_id trace_id: String,
  origin origin: Origin,
  source source: port_graph.PortRef,
  payload payload: Json,
  graph graph: port_graph.EffectiveGraph,
  ports_for ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Plan {
  case origin {
    ReplicatedChange -> Plan(deliveries: [], errors: [])
    LocalIntent ->
      plan_local_intent(Trace(trace_id), source, payload, graph, ports_for)
  }
}

fn plan_local_intent(
  trace: Trace,
  source: port_graph.PortRef,
  payload: Json,
  graph: port_graph.EffectiveGraph,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Plan {
  case resolve_output(trace, source, ports_for) {
    Error(dispatch_error) -> Plan(deliveries: [], errors: [dispatch_error])
    Ok(source_schema_id) -> {
      let outcomes =
        port_graph.outgoing(graph, source)
        |> list.map(fn(connection) {
          resolve_delivery(
            trace,
            connection,
            source_schema_id,
            payload,
            ports_for,
          )
        })
      let deliveries =
        list.filter_map(outcomes, fn(outcome) {
          case outcome {
            Ok(delivery) -> Ok(delivery)
            Error(_) -> Error(Nil)
          }
        })
      let errors =
        list.filter_map(outcomes, fn(outcome) {
          case outcome {
            Error(dispatch_error) -> Ok(dispatch_error)
            Ok(_) -> Error(Nil)
          }
        })
      Plan(deliveries: deliveries, errors: errors)
    }
  }
}

/// Read the current source descriptor and return its schema ID.
fn resolve_output(
  trace: Trace,
  source: port_graph.PortRef,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Result(String, DispatchError) {
  case find_descriptor(source, ports_for) {
    Ok(port.Descriptor(direction: port.OutputPort, schema_id: schema_id, ..)) ->
      Ok(schema_id)
    _ -> Error(SourceUnavailable(trace, source))
  }
}

/// Read the current target descriptor and check it against the source. The
/// graph checked both ports when it accepted the edge, so a fault here means
/// the host catalog changed after that point.
fn resolve_delivery(
  trace: Trace,
  connection: port_graph.Connection,
  source_schema_id: String,
  payload: Json,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Result(Delivery, DispatchError) {
  case find_descriptor(connection.target, ports_for) {
    Ok(port.Descriptor(
      direction: port.InputPort(input_class),
      schema_id: schema_id,
      ..,
    )) ->
      case schema_id == source_schema_id {
        True ->
          Ok(Delivery(
            trace: trace,
            edge_id: connection.id,
            target: connection.target,
            input_class: input_class,
            payload: payload,
          ))
        False ->
          Error(SchemaChanged(trace, connection.id, source_schema_id, schema_id))
      }
    _ -> Error(TargetUnavailable(trace, connection.id, connection.target))
  }
}

fn find_descriptor(
  ref: port_graph.PortRef,
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Result(port.Descriptor, Nil) {
  case ports_for(ref.instance_id) {
    Error(Nil) -> Error(Nil)
    Ok(descriptors) ->
      list.find(descriptors, fn(descriptor) { descriptor.id == ref.port_id })
  }
}

/// The deliveries the plan built, in effective graph order.
pub fn deliveries(plan: Plan) -> List(Delivery) {
  plan.deliveries
}

/// One diagnostic for each edge the plan could not resolve.
pub fn errors(plan: Plan) -> List(DispatchError) {
  plan.errors
}
