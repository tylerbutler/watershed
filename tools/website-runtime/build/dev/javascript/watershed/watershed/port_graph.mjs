/// <reference types="./port_graph.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $canonical_json from "../watershed/canonical_json.mjs";
import * as $port from "../watershed/port.mjs";

export class PortRef extends $CustomType {
  constructor(instance_id, port_id) {
    super();
    this.instance_id = instance_id;
    this.port_id = port_id;
  }
}
export const PortRef$PortRef = (instance_id, port_id) =>
  new PortRef(instance_id, port_id);
export const PortRef$isPortRef = (value) => value instanceof PortRef;
export const PortRef$PortRef$instance_id = (value) => value.instance_id;
export const PortRef$PortRef$0 = (value) => value.instance_id;
export const PortRef$PortRef$port_id = (value) => value.port_id;
export const PortRef$PortRef$1 = (value) => value.port_id;

export class Connection extends $CustomType {
  constructor(id, source, target) {
    super();
    this.id = id;
    this.source = source;
    this.target = target;
  }
}
export const Connection$Connection = (id, source, target) =>
  new Connection(id, source, target);
export const Connection$isConnection = (value) => value instanceof Connection;
export const Connection$Connection$id = (value) => value.id;
export const Connection$Connection$0 = (value) => value.id;
export const Connection$Connection$source = (value) => value.source;
export const Connection$Connection$1 = (value) => value.source;
export const Connection$Connection$target = (value) => value.target;
export const Connection$Connection$2 = (value) => value.target;

/**
 * More than one stored connection carries this ID. The graph drops every
 * connection with the ID and reports the ID one time.
 */
export class DuplicateConnection extends $CustomType {
  constructor(connection_id) {
    super();
    this.connection_id = connection_id;
  }
}
export const GraphError$DuplicateConnection = (connection_id) =>
  new DuplicateConnection(connection_id);
export const GraphError$isDuplicateConnection = (value) =>
  value instanceof DuplicateConnection;
export const GraphError$DuplicateConnection$connection_id = (value) =>
  value.connection_id;
export const GraphError$DuplicateConnection$0 = (value) => value.connection_id;

/**
 * The connection names an instance the port lookup does not know.
 */
export class UnknownInstance extends $CustomType {
  constructor(connection_id, instance_id) {
    super();
    this.connection_id = connection_id;
    this.instance_id = instance_id;
  }
}
export const GraphError$UnknownInstance = (connection_id, instance_id) =>
  new UnknownInstance(connection_id, instance_id);
export const GraphError$isUnknownInstance = (value) =>
  value instanceof UnknownInstance;
export const GraphError$UnknownInstance$connection_id = (value) =>
  value.connection_id;
export const GraphError$UnknownInstance$0 = (value) => value.connection_id;
export const GraphError$UnknownInstance$instance_id = (value) =>
  value.instance_id;
export const GraphError$UnknownInstance$1 = (value) => value.instance_id;

/**
 * The named instance does not carry the named port.
 */
export class UnknownPort extends $CustomType {
  constructor(connection_id, port) {
    super();
    this.connection_id = connection_id;
    this.port = port;
  }
}
export const GraphError$UnknownPort = (connection_id, port) =>
  new UnknownPort(connection_id, port);
export const GraphError$isUnknownPort = (value) => value instanceof UnknownPort;
export const GraphError$UnknownPort$connection_id = (value) =>
  value.connection_id;
export const GraphError$UnknownPort$0 = (value) => value.connection_id;
export const GraphError$UnknownPort$port = (value) => value.port;
export const GraphError$UnknownPort$1 = (value) => value.port;

/**
 * The port has the wrong direction. The source must be an output port and
 * the target must be an input port.
 */
export class WrongDirection extends $CustomType {
  constructor(connection_id, port, expected) {
    super();
    this.connection_id = connection_id;
    this.port = port;
    this.expected = expected;
  }
}
export const GraphError$WrongDirection = (connection_id, port, expected) =>
  new WrongDirection(connection_id, port, expected);
export const GraphError$isWrongDirection = (value) =>
  value instanceof WrongDirection;
export const GraphError$WrongDirection$connection_id = (value) =>
  value.connection_id;
export const GraphError$WrongDirection$0 = (value) => value.connection_id;
export const GraphError$WrongDirection$port = (value) => value.port;
export const GraphError$WrongDirection$1 = (value) => value.port;
export const GraphError$WrongDirection$expected = (value) => value.expected;
export const GraphError$WrongDirection$2 = (value) => value.expected;

/**
 * The source port and the target port name different schema IDs.
 */
export class SchemaMismatch extends $CustomType {
  constructor(connection_id, source, target) {
    super();
    this.connection_id = connection_id;
    this.source = source;
    this.target = target;
  }
}
export const GraphError$SchemaMismatch = (connection_id, source, target) =>
  new SchemaMismatch(connection_id, source, target);
export const GraphError$isSchemaMismatch = (value) =>
  value instanceof SchemaMismatch;
export const GraphError$SchemaMismatch$connection_id = (value) =>
  value.connection_id;
export const GraphError$SchemaMismatch$0 = (value) => value.connection_id;
export const GraphError$SchemaMismatch$source = (value) => value.source;
export const GraphError$SchemaMismatch$1 = (value) => value.source;
export const GraphError$SchemaMismatch$target = (value) => value.target;
export const GraphError$SchemaMismatch$2 = (value) => value.target;

/**
 * Adding the connection makes a cycle. The graph keeps the earlier edges
 * and drops this one.
 */
export class Cycle extends $CustomType {
  constructor(connection_id) {
    super();
    this.connection_id = connection_id;
  }
}
export const GraphError$Cycle = (connection_id) => new Cycle(connection_id);
export const GraphError$isCycle = (value) => value instanceof Cycle;
export const GraphError$Cycle$connection_id = (value) => value.connection_id;
export const GraphError$Cycle$0 = (value) => value.connection_id;

export const GraphError$connection_id = (value) => value.connection_id;

class EffectiveGraph extends $CustomType {
  constructor(connections, errors) {
    super();
    this.connections = connections;
    this.errors = errors;
  }
}

class State extends $CustomType {
  constructor(accepted, arcs, errors, emitted_duplicates) {
    super();
    this.accepted = accepted;
    this.arcs = arcs;
    this.errors = errors;
    this.emitted_duplicates = emitted_duplicates;
  }
}

/**
 * Build one stored connection.
 */
export function connection(id, source, target) {
  return new Connection(id, source, target);
}

function add_arc(arcs, from, to) {
  return $dict.upsert(
    arcs,
    from,
    (existing) => {
      if (existing instanceof $option.Some) {
        let targets = existing[0];
        return listPrepend(to, targets);
      } else {
        return toList([to]);
      }
    },
  );
}

/**
 * Walk the arcs from a frontier of instances and look for one goal. The
 * visited set is shared by every branch, so the walk expands each instance
 * one time. One query therefore costs O(V + E).
 * 
 * @ignore
 */
function reachable(loop$frontier, loop$goal, loop$arcs, loop$visited) {
  while (true) {
    let frontier = loop$frontier;
    let goal = loop$goal;
    let arcs = loop$arcs;
    let visited = loop$visited;
    if (frontier instanceof $Empty) {
      return false;
    } else {
      let current = frontier.head;
      let rest = frontier.tail;
      let $ = current === goal;
      if ($) {
        return $;
      } else {
        let $1 = $set.contains(visited, current);
        if ($1) {
          loop$frontier = rest;
          loop$goal = goal;
          loop$arcs = arcs;
          loop$visited = visited;
        } else {
          let _block;
          let _pipe = $dict.get(arcs, current);
          _block = $result.unwrap(_pipe, $List$Empty$const);
          let next = _block;
          loop$frontier = $list.append(next, rest);
          loop$goal = goal;
          loop$arcs = arcs;
          loop$visited = $set.insert(visited, current);
        }
      }
    }
  }
}

function creates_cycle(source, target, arcs) {
  return reachable(toList([target]), source, arcs, $set.new$());
}

function accept_or_cycle(state, connection) {
  let source = connection.source.instance_id;
  let target = connection.target.instance_id;
  let $ = creates_cycle(source, target, state.arcs);
  if ($) {
    return new State(
      state.accepted,
      state.arcs,
      listPrepend(new Cycle(connection.id), state.errors),
      state.emitted_duplicates,
    );
  } else {
    return new State(
      listPrepend(connection, state.accepted),
      add_arc(state.arcs, source, target),
      state.errors,
      state.emitted_duplicates,
    );
  }
}

function check_direction(id, ref, descriptor, expected) {
  let $ = isEqual($port.direction_kind(descriptor.direction), expected);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new WrongDirection(id, ref, expected));
  }
}

function resolve(id, ref, ports_for) {
  let $ = ports_for(ref.instance_id);
  if ($ instanceof Ok) {
    let descriptors = $[0];
    let $1 = $list.find(descriptors, (d) => { return d.id === ref.port_id; });
    if ($1 instanceof Ok) {
      return $1;
    } else {
      return new Error(new UnknownPort(id, ref));
    }
  } else {
    return new Error(new UnknownInstance(id, ref.instance_id));
  }
}

function validate(connection, ports_for) {
  return $result.try$(
    resolve(connection.id, connection.source, ports_for),
    (source) => {
      return $result.try$(
        resolve(connection.id, connection.target, ports_for),
        (target) => {
          return $result.try$(
            check_direction(
              connection.id,
              connection.source,
              source,
              $port.DirectionKind$OutputDirection$const,
            ),
            (_) => {
              return $result.try$(
                check_direction(
                  connection.id,
                  connection.target,
                  target,
                  $port.DirectionKind$InputDirection$const,
                ),
                (_) => {
                  let $ = source.schema_id === target.schema_id;
                  if ($) {
                    return new Ok(undefined);
                  } else {
                    return new Error(
                      new SchemaMismatch(
                        connection.id,
                        source.schema_id,
                        target.schema_id,
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      );
    },
  );
}

function record_duplicate(state, id) {
  let $ = $set.contains(state.emitted_duplicates, id);
  if ($) {
    return state;
  } else {
    return new State(
      state.accepted,
      state.arcs,
      listPrepend(new DuplicateConnection(id), state.errors),
      $set.insert(state.emitted_duplicates, id),
    );
  }
}

function step(state, connection, duplicates, ports_for) {
  let $ = $set.contains(duplicates, connection.id);
  if ($) {
    return record_duplicate(state, connection.id);
  } else {
    let $1 = validate(connection, ports_for);
    if ($1 instanceof Ok) {
      return accept_or_cycle(state, connection);
    } else {
      let graph_error = $1[0];
      return new State(
        state.accepted,
        state.arcs,
        listPrepend(graph_error, state.errors),
        state.emitted_duplicates,
      );
    }
  }
}

function new_state() {
  return new State(
    $List$Empty$const,
    $dict.new$(),
    $List$Empty$const,
    $set.new$(),
  );
}

function duplicated_ids(connections) {
  let counts = $list.fold(
    connections,
    $dict.new$(),
    (acc, connection) => {
      return $dict.upsert(
        acc,
        connection.id,
        (existing) => {
          if (existing instanceof $option.Some) {
            let count = existing[0];
            return count + 1;
          } else {
            return 1;
          }
        },
      );
    },
  );
  return $dict.fold(
    counts,
    $set.new$(),
    (acc, id, count) => {
      let $ = count > 1;
      if ($) {
        return $set.insert(acc, id);
      } else {
        return acc;
      }
    },
  );
}

/**
 * Read a stored connection list and build the effective graph.
 *
 * `ports_for` returns the ports of one instance, or `Error(Nil)` when the
 * instance is not known. The function sorts the list by connection ID, drops
 * any ID that repeats, checks each remaining connection, and keeps only the
 * connections that pass and that do not make a cycle.
 */
export function effective(stored, ports_for) {
  let sorted = $list.sort(
    stored,
    (left, right) => { return $canonical_json.compare(left.id, right.id); },
  );
  let duplicates = duplicated_ids(sorted);
  let final = $list.fold(
    sorted,
    new_state(),
    (state, connection) => {
      return step(state, connection, duplicates, ports_for);
    },
  );
  return new EffectiveGraph(
    $list.reverse(final.accepted),
    $list.reverse(final.errors),
  );
}

/**
 * The connections the graph kept, in sorted ID order.
 */
export function connections(graph) {
  return graph.connections;
}

/**
 * One diagnostic for each stored connection the graph dropped.
 */
export function errors(graph) {
  return graph.errors;
}

/**
 * The kept connections that leave one port, in effective graph order.
 */
export function outgoing(graph, source) {
  return $list.filter(
    graph.connections,
    (connection) => { return isEqual(connection.source, source); },
  );
}
