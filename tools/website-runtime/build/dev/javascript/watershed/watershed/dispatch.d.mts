import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $port from "../watershed/port.d.mts";
import type * as $port_graph from "../watershed/port_graph.d.mts";

export class LocalIntent extends _.CustomType {}
export function Origin$LocalIntent(): Origin$;
export function Origin$isLocalIntent(value: any): value is Origin$;

export class ReplicatedChange extends _.CustomType {}
export function Origin$ReplicatedChange(): Origin$;
export function Origin$isReplicatedChange(value: any): value is Origin$;

export type Origin$ = LocalIntent | ReplicatedChange;

export class Trace extends _.CustomType {
  /** @deprecated */
  constructor(id: string);
  /** @deprecated */
  id: string;
}
export function Trace$Trace(id: string): Trace$;
export function Trace$isTrace(value: any): value is Trace$;
export function Trace$Trace$0(value: Trace$): string;
export function Trace$Trace$id(value: Trace$): string;

export type Trace$ = Trace;

export class Delivery extends _.CustomType {
  /** @deprecated */
  constructor(
    trace: Trace$,
    edge_id: string,
    target: $port_graph.PortRef$,
    input_class: $port.InputClass$,
    payload: $json.Json$
  );
  /** @deprecated */
  trace: Trace$;
  /** @deprecated */
  edge_id: string;
  /** @deprecated */
  target: $port_graph.PortRef$;
  /** @deprecated */
  input_class: $port.InputClass$;
  /** @deprecated */
  payload: $json.Json$;
}
export function Delivery$Delivery(
  trace: Trace$,
  edge_id: string,
  target: $port_graph.PortRef$,
  input_class: $port.InputClass$,
  payload: $json.Json$,
): Delivery$;
export function Delivery$isDelivery(value: any): value is Delivery$;
export function Delivery$Delivery$0(value: Delivery$): Trace$;
export function Delivery$Delivery$trace(value: Delivery$): Trace$;
export function Delivery$Delivery$1(value: Delivery$): string;
export function Delivery$Delivery$edge_id(value: Delivery$): string;
export function Delivery$Delivery$2(value: Delivery$): $port_graph.PortRef$;
export function Delivery$Delivery$target(value: Delivery$): $port_graph.PortRef$;
export function Delivery$Delivery$3(
  value: Delivery$,
): $port.InputClass$;
export function Delivery$Delivery$input_class(value: Delivery$): $port.InputClass$;
export function Delivery$Delivery$4(
  value: Delivery$,
): $json.Json$;
export function Delivery$Delivery$payload(value: Delivery$): $json.Json$;

export type Delivery$ = Delivery;

export class SourceUnavailable extends _.CustomType {
  /** @deprecated */
  constructor(trace: Trace$, source: $port_graph.PortRef$);
  /** @deprecated */
  trace: Trace$;
  /** @deprecated */
  source: $port_graph.PortRef$;
}
export function DispatchError$SourceUnavailable(
  trace: Trace$,
  source: $port_graph.PortRef$,
): DispatchError$;
export function DispatchError$isSourceUnavailable(
  value: any,
): value is DispatchError$;
export function DispatchError$SourceUnavailable$0(value: DispatchError$): Trace$;
export function DispatchError$SourceUnavailable$trace(
  value: DispatchError$,
): Trace$;
export function DispatchError$SourceUnavailable$1(value: DispatchError$): $port_graph.PortRef$;
export function DispatchError$SourceUnavailable$source(
  value: DispatchError$,
): $port_graph.PortRef$;

export class TargetUnavailable extends _.CustomType {
  /** @deprecated */
  constructor(trace: Trace$, edge_id: string, target: $port_graph.PortRef$);
  /** @deprecated */
  trace: Trace$;
  /** @deprecated */
  edge_id: string;
  /** @deprecated */
  target: $port_graph.PortRef$;
}
export function DispatchError$TargetUnavailable(
  trace: Trace$,
  edge_id: string,
  target: $port_graph.PortRef$,
): DispatchError$;
export function DispatchError$isTargetUnavailable(
  value: any,
): value is DispatchError$;
export function DispatchError$TargetUnavailable$0(value: DispatchError$): Trace$;
export function DispatchError$TargetUnavailable$trace(
  value: DispatchError$,
): Trace$;
export function DispatchError$TargetUnavailable$1(value: DispatchError$): string;
export function DispatchError$TargetUnavailable$edge_id(
  value: DispatchError$,
): string;
export function DispatchError$TargetUnavailable$2(value: DispatchError$): $port_graph.PortRef$;
export function DispatchError$TargetUnavailable$target(
  value: DispatchError$,
): $port_graph.PortRef$;

export class SchemaChanged extends _.CustomType {
  /** @deprecated */
  constructor(trace: Trace$, edge_id: string, source: string, target: string);
  /** @deprecated */
  trace: Trace$;
  /** @deprecated */
  edge_id: string;
  /** @deprecated */
  source: string;
  /** @deprecated */
  target: string;
}
export function DispatchError$SchemaChanged(
  trace: Trace$,
  edge_id: string,
  source: string,
  target: string,
): DispatchError$;
export function DispatchError$isSchemaChanged(
  value: any,
): value is DispatchError$;
export function DispatchError$SchemaChanged$0(value: DispatchError$): Trace$;
export function DispatchError$SchemaChanged$trace(value: DispatchError$): Trace$;
export function DispatchError$SchemaChanged$1(
  value: DispatchError$,
): string;
export function DispatchError$SchemaChanged$edge_id(value: DispatchError$): string;
export function DispatchError$SchemaChanged$2(
  value: DispatchError$,
): string;
export function DispatchError$SchemaChanged$source(value: DispatchError$): string;
export function DispatchError$SchemaChanged$3(
  value: DispatchError$,
): string;
export function DispatchError$SchemaChanged$target(value: DispatchError$): string;

export type DispatchError$ = SourceUnavailable | TargetUnavailable | SchemaChanged;

export function DispatchError$trace(value: DispatchError$): Trace$;

declare class Plan extends _.CustomType {
  /** @deprecated */
  constructor(deliveries: _.List<Delivery$>, errors: _.List<DispatchError$>);
  /** @deprecated */
  deliveries: _.List<Delivery$>;
  /** @deprecated */
  errors: _.List<DispatchError$>;
}

export type Plan$ = Plan;

export function plan(
  trace_id: string,
  origin: Origin$,
  source: $port_graph.PortRef$,
  payload: $json.Json$,
  graph: $port_graph.EffectiveGraph$,
  ports_for: (x0: string) => _.Result<_.List<$port.Descriptor$>, undefined>
): Plan$;

export function deliveries(plan: Plan$): _.List<Delivery$>;

export function errors(plan: Plan$): _.List<DispatchError$>;
