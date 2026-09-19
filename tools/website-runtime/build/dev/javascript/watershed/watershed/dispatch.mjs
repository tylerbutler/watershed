/// <reference types="./dispatch.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $port from "../watershed/port.mjs";
import * as $port_graph from "../watershed/port_graph.mjs";

export class LocalIntent extends $CustomType {}
export const Origin$LocalIntent$const = new LocalIntent();
export const Origin$LocalIntent = () => Origin$LocalIntent$const;
export const Origin$isLocalIntent = (value) => value instanceof LocalIntent;

export class ReplicatedChange extends $CustomType {}
export const Origin$ReplicatedChange$const = new ReplicatedChange();
export const Origin$ReplicatedChange = () => Origin$ReplicatedChange$const;
export const Origin$isReplicatedChange = (value) =>
  value instanceof ReplicatedChange;

export class Trace extends $CustomType {
  constructor(id) {
    super();
    this.id = id;
  }
}
export const Trace$Trace = (id) => new Trace(id);
export const Trace$isTrace = (value) => value instanceof Trace;
export const Trace$Trace$id = (value) => value.id;
export const Trace$Trace$0 = (value) => value.id;

export class Delivery extends $CustomType {
  constructor(trace, edge_id, target, input_class, payload) {
    super();
    this.trace = trace;
    this.edge_id = edge_id;
    this.target = target;
    this.input_class = input_class;
    this.payload = payload;
  }
}
export const Delivery$Delivery = (trace, edge_id, target, input_class, payload) =>
  new Delivery(trace, edge_id, target, input_class, payload);
export const Delivery$isDelivery = (value) => value instanceof Delivery;
export const Delivery$Delivery$trace = (value) => value.trace;
export const Delivery$Delivery$0 = (value) => value.trace;
export const Delivery$Delivery$edge_id = (value) => value.edge_id;
export const Delivery$Delivery$1 = (value) => value.edge_id;
export const Delivery$Delivery$target = (value) => value.target;
export const Delivery$Delivery$2 = (value) => value.target;
export const Delivery$Delivery$input_class = (value) => value.input_class;
export const Delivery$Delivery$3 = (value) => value.input_class;
export const Delivery$Delivery$payload = (value) => value.payload;
export const Delivery$Delivery$4 = (value) => value.payload;

/**
 * The source port is no longer present, or it is no longer an output
 * port. The plan builds no delivery.
 */
export class SourceUnavailable extends $CustomType {
  constructor(trace, source) {
    super();
    this.trace = trace;
    this.source = source;
  }
}
export const DispatchError$SourceUnavailable = (trace, source) =>
  new SourceUnavailable(trace, source);
export const DispatchError$isSourceUnavailable = (value) =>
  value instanceof SourceUnavailable;
export const DispatchError$SourceUnavailable$trace = (value) => value.trace;
export const DispatchError$SourceUnavailable$0 = (value) => value.trace;
export const DispatchError$SourceUnavailable$source = (value) => value.source;
export const DispatchError$SourceUnavailable$1 = (value) => value.source;

/**
 * The target instance is no longer present, the target port is no longer
 * present, or the target port is no longer an input port. The host
 * catalog changed between the graph's construction and this dispatch.
 */
export class TargetUnavailable extends $CustomType {
  constructor(trace, edge_id, target) {
    super();
    this.trace = trace;
    this.edge_id = edge_id;
    this.target = target;
  }
}
export const DispatchError$TargetUnavailable = (trace, edge_id, target) =>
  new TargetUnavailable(trace, edge_id, target);
export const DispatchError$isTargetUnavailable = (value) =>
  value instanceof TargetUnavailable;
export const DispatchError$TargetUnavailable$trace = (value) => value.trace;
export const DispatchError$TargetUnavailable$0 = (value) => value.trace;
export const DispatchError$TargetUnavailable$edge_id = (value) => value.edge_id;
export const DispatchError$TargetUnavailable$1 = (value) => value.edge_id;
export const DispatchError$TargetUnavailable$target = (value) => value.target;
export const DispatchError$TargetUnavailable$2 = (value) => value.target;

/**
 * The source port and the target port now name different schema IDs. The
 * host catalog changed a schema ID after the graph accepted this edge,
 * so the target can no longer decode the payload.
 */
export class SchemaChanged extends $CustomType {
  constructor(trace, edge_id, source, target) {
    super();
    this.trace = trace;
    this.edge_id = edge_id;
    this.source = source;
    this.target = target;
  }
}
export const DispatchError$SchemaChanged = (trace, edge_id, source, target) =>
  new SchemaChanged(trace, edge_id, source, target);
export const DispatchError$isSchemaChanged = (value) =>
  value instanceof SchemaChanged;
export const DispatchError$SchemaChanged$trace = (value) => value.trace;
export const DispatchError$SchemaChanged$0 = (value) => value.trace;
export const DispatchError$SchemaChanged$edge_id = (value) => value.edge_id;
export const DispatchError$SchemaChanged$1 = (value) => value.edge_id;
export const DispatchError$SchemaChanged$source = (value) => value.source;
export const DispatchError$SchemaChanged$2 = (value) => value.source;
export const DispatchError$SchemaChanged$target = (value) => value.target;
export const DispatchError$SchemaChanged$3 = (value) => value.target;

export const DispatchError$trace = (value) => value.trace;

class Plan extends $CustomType {
  constructor(deliveries, errors) {
    super();
    this.deliveries = deliveries;
    this.errors = errors;
  }
}

function find_descriptor(ref, ports_for) {
  let $ = ports_for(ref.instance_id);
  if ($ instanceof Ok) {
    let descriptors = $[0];
    return $list.find(
      descriptors,
      (descriptor) => { return descriptor.id === ref.port_id; },
    );
  } else {
    return $;
  }
}

/**
 * Read the current target descriptor and check it against the source. The
 * graph checked both ports when it accepted the edge, so a fault here means
 * the host catalog changed after that point.
 * 
 * @ignore
 */
function resolve_delivery(
  trace,
  connection,
  source_schema_id,
  payload,
  ports_for
) {
  let $ = find_descriptor(connection.target, ports_for);
  if ($ instanceof Ok) {
    let $1 = $[0].direction;
    if ($1 instanceof $port.InputPort) {
      let schema_id = $[0].schema_id;
      let input_class = $1.class;
      let $2 = schema_id === source_schema_id;
      if ($2) {
        return new Ok(
          new Delivery(
            trace,
            connection.id,
            connection.target,
            input_class,
            payload,
          ),
        );
      } else {
        return new Error(
          new SchemaChanged(trace, connection.id, source_schema_id, schema_id),
        );
      }
    } else {
      return new Error(
        new TargetUnavailable(trace, connection.id, connection.target),
      );
    }
  } else {
    return new Error(
      new TargetUnavailable(trace, connection.id, connection.target),
    );
  }
}

/**
 * Read the current source descriptor and return its schema ID.
 * 
 * @ignore
 */
function resolve_output(trace, source, ports_for) {
  let $ = find_descriptor(source, ports_for);
  if ($ instanceof Ok) {
    let $1 = $[0].direction;
    if ($1 instanceof $port.OutputPort) {
      let schema_id = $[0].schema_id;
      return new Ok(schema_id);
    } else {
      return new Error(new SourceUnavailable(trace, source));
    }
  } else {
    return new Error(new SourceUnavailable(trace, source));
  }
}

function plan_local_intent(trace, source, payload, graph, ports_for) {
  let $ = resolve_output(trace, source, ports_for);
  if ($ instanceof Ok) {
    let source_schema_id = $[0];
    let _block;
    let _pipe = $port_graph.outgoing(graph, source);
    _block = $list.map(
      _pipe,
      (connection) => {
        return resolve_delivery(
          trace,
          connection,
          source_schema_id,
          payload,
          ports_for,
        );
      },
    );
    let outcomes = _block;
    let deliveries$1 = $list.filter_map(
      outcomes,
      (outcome) => {
        if (outcome instanceof Ok) {
          return outcome;
        } else {
          return new Error(undefined);
        }
      },
    );
    let errors$1 = $list.filter_map(
      outcomes,
      (outcome) => {
        if (outcome instanceof Ok) {
          return new Error(undefined);
        } else {
          let dispatch_error = outcome[0];
          return new Ok(dispatch_error);
        }
      },
    );
    return new Plan(deliveries$1, errors$1);
  } else {
    let dispatch_error = $[0];
    return new Plan($List$Empty$const, toList([dispatch_error]));
  }
}

/**
 * Plan the deliveries for one payload at one output port.
 *
 * `graph` supplies the effective connections in graph order. `ports_for`
 * re-reads the current port descriptors for one instance, so the plan
 * catches a port that a host catalog change removed or changed since the
 * graph was built. The plan compares the current schema ID of the source
 * port against the current schema ID of each target port, and it reports
 * `SchemaChanged` for a target that no longer matches. Returns an empty
 * plan without reading the graph when `origin` is `ReplicatedChange`.
 */
export function plan(trace_id, origin, source, payload, graph, ports_for) {
  if (origin instanceof LocalIntent) {
    return plan_local_intent(
      new Trace(trace_id),
      source,
      payload,
      graph,
      ports_for,
    );
  } else {
    return new Plan($List$Empty$const, $List$Empty$const);
  }
}

/**
 * The deliveries the plan built, in effective graph order.
 */
export function deliveries(plan) {
  return plan.deliveries;
}

/**
 * One diagnostic for each edge the plan could not resolve.
 */
export function errors(plan) {
  return plan.errors;
}
