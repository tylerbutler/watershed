import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $port from "../watershed/port.d.mts";

export class PortRef extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, port_id: string);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  port_id: string;
}
export function PortRef$PortRef(instance_id: string, port_id: string): PortRef$;
export function PortRef$isPortRef(value: any): value is PortRef$;
export function PortRef$PortRef$0(value: PortRef$): string;
export function PortRef$PortRef$instance_id(value: PortRef$): string;
export function PortRef$PortRef$1(value: PortRef$): string;
export function PortRef$PortRef$port_id(value: PortRef$): string;

export type PortRef$ = PortRef;

export class Connection extends _.CustomType {
  /** @deprecated */
  constructor(id: string, source: PortRef$, target: PortRef$);
  /** @deprecated */
  id: string;
  /** @deprecated */
  source: PortRef$;
  /** @deprecated */
  target: PortRef$;
}
export function Connection$Connection(
  id: string,
  source: PortRef$,
  target: PortRef$,
): Connection$;
export function Connection$isConnection(value: any): value is Connection$;
export function Connection$Connection$0(value: Connection$): string;
export function Connection$Connection$id(value: Connection$): string;
export function Connection$Connection$1(value: Connection$): PortRef$;
export function Connection$Connection$source(value: Connection$): PortRef$;
export function Connection$Connection$2(value: Connection$): PortRef$;
export function Connection$Connection$target(value: Connection$): PortRef$;

export type Connection$ = Connection;

export class DuplicateConnection extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string);
  /** @deprecated */
  connection_id: string;
}
export function GraphError$DuplicateConnection(
  connection_id: string,
): GraphError$;
export function GraphError$isDuplicateConnection(
  value: any,
): value is GraphError$;
export function GraphError$DuplicateConnection$0(value: GraphError$): string;
export function GraphError$DuplicateConnection$connection_id(value: GraphError$): string;

export class UnknownInstance extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string, instance_id: string);
  /** @deprecated */
  connection_id: string;
  /** @deprecated */
  instance_id: string;
}
export function GraphError$UnknownInstance(
  connection_id: string,
  instance_id: string,
): GraphError$;
export function GraphError$isUnknownInstance(value: any): value is GraphError$;
export function GraphError$UnknownInstance$0(value: GraphError$): string;
export function GraphError$UnknownInstance$connection_id(value: GraphError$): string;
export function GraphError$UnknownInstance$1(
  value: GraphError$,
): string;
export function GraphError$UnknownInstance$instance_id(value: GraphError$): string;

export class UnknownPort extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string, port: PortRef$);
  /** @deprecated */
  connection_id: string;
  /** @deprecated */
  port: PortRef$;
}
export function GraphError$UnknownPort(
  connection_id: string,
  port: PortRef$,
): GraphError$;
export function GraphError$isUnknownPort(value: any): value is GraphError$;
export function GraphError$UnknownPort$0(value: GraphError$): string;
export function GraphError$UnknownPort$connection_id(value: GraphError$): string;
export function GraphError$UnknownPort$1(
  value: GraphError$,
): PortRef$;
export function GraphError$UnknownPort$port(value: GraphError$): PortRef$;

export class WrongDirection extends _.CustomType {
  /** @deprecated */
  constructor(
    connection_id: string,
    port: PortRef$,
    expected: $port.DirectionKind$
  );
  /** @deprecated */
  connection_id: string;
  /** @deprecated */
  port: PortRef$;
  /** @deprecated */
  expected: $port.DirectionKind$;
}
export function GraphError$WrongDirection(
  connection_id: string,
  port: PortRef$,
  expected: $port.DirectionKind$,
): GraphError$;
export function GraphError$isWrongDirection(value: any): value is GraphError$;
export function GraphError$WrongDirection$0(value: GraphError$): string;
export function GraphError$WrongDirection$connection_id(value: GraphError$): string;
export function GraphError$WrongDirection$1(
  value: GraphError$,
): PortRef$;
export function GraphError$WrongDirection$port(value: GraphError$): PortRef$;
export function GraphError$WrongDirection$2(value: GraphError$): $port.DirectionKind$;
export function GraphError$WrongDirection$expected(
  value: GraphError$,
): $port.DirectionKind$;

export class SchemaMismatch extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string, source: string, target: string);
  /** @deprecated */
  connection_id: string;
  /** @deprecated */
  source: string;
  /** @deprecated */
  target: string;
}
export function GraphError$SchemaMismatch(
  connection_id: string,
  source: string,
  target: string,
): GraphError$;
export function GraphError$isSchemaMismatch(value: any): value is GraphError$;
export function GraphError$SchemaMismatch$0(value: GraphError$): string;
export function GraphError$SchemaMismatch$connection_id(value: GraphError$): string;
export function GraphError$SchemaMismatch$1(
  value: GraphError$,
): string;
export function GraphError$SchemaMismatch$source(value: GraphError$): string;
export function GraphError$SchemaMismatch$2(value: GraphError$): string;
export function GraphError$SchemaMismatch$target(value: GraphError$): string;

export class Cycle extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string);
  /** @deprecated */
  connection_id: string;
}
export function GraphError$Cycle(connection_id: string): GraphError$;
export function GraphError$isCycle(value: any): value is GraphError$;
export function GraphError$Cycle$0(value: GraphError$): string;
export function GraphError$Cycle$connection_id(value: GraphError$): string;

export type GraphError$ = DuplicateConnection | UnknownInstance | UnknownPort | WrongDirection | SchemaMismatch | Cycle;

export function GraphError$connection_id(value: GraphError$): string;

declare class EffectiveGraph extends _.CustomType {
  /** @deprecated */
  constructor(connections: _.List<Connection$>, errors: _.List<GraphError$>);
  /** @deprecated */
  connections: _.List<Connection$>;
  /** @deprecated */
  errors: _.List<GraphError$>;
}

export type EffectiveGraph$ = EffectiveGraph;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    accepted: _.List<Connection$>,
    arcs: $dict.Dict$<string, _.List<string>>,
    errors: _.List<GraphError$>,
    emitted_duplicates: $set.Set$<string>
  );
  /** @deprecated */
  accepted: _.List<Connection$>;
  /** @deprecated */
  arcs: $dict.Dict$<string, _.List<string>>;
  /** @deprecated */
  errors: _.List<GraphError$>;
  /** @deprecated */
  emitted_duplicates: $set.Set$<string>;
}

type State$ = State;

export function connection(id: string, source: PortRef$, target: PortRef$): Connection$;

export function effective(
  stored: _.List<Connection$>,
  ports_for: (x0: string) => _.Result<_.List<$port.Descriptor$>, undefined>
): EffectiveGraph$;

export function connections(graph: EffectiveGraph$): _.List<Connection$>;

export function errors(graph: EffectiveGraph$): _.List<GraphError$>;

export function outgoing(graph: EffectiveGraph$, source: PortRef$): _.List<
  Connection$
>;
