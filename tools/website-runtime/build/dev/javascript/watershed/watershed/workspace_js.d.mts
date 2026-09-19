import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $watershed from "../watershed.d.mts";
import type * as $component from "../watershed/component.d.mts";
import type * as $port_graph from "../watershed/port_graph.d.mts";
import type * as $schema from "../watershed/schema.d.mts";
import type * as $workspace from "../watershed/workspace.d.mts";

export class InvalidInstanceId extends _.CustomType {}
export function WorkspaceError$InvalidInstanceId(): WorkspaceError$;
export function WorkspaceError$isInvalidInstanceId(
  value: any,
): value is WorkspaceError$;

export class DuplicateInstance extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function WorkspaceError$DuplicateInstance(
  instance_id: string,
): WorkspaceError$;
export function WorkspaceError$isDuplicateInstance(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$DuplicateInstance$0(value: WorkspaceError$): string;
export function WorkspaceError$DuplicateInstance$instance_id(
  value: WorkspaceError$,
): string;

export class InvalidMove extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, to_index: number);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  to_index: number;
}
export function WorkspaceError$InvalidMove(
  instance_id: string,
  to_index: number,
): WorkspaceError$;
export function WorkspaceError$isInvalidMove(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$InvalidMove$0(value: WorkspaceError$): string;
export function WorkspaceError$InvalidMove$instance_id(value: WorkspaceError$): string;
export function WorkspaceError$InvalidMove$1(
  value: WorkspaceError$,
): number;
export function WorkspaceError$InvalidMove$to_index(value: WorkspaceError$): number;

export class UnsupportedComponent extends _.CustomType {
  /** @deprecated */
  constructor(reason: $component.LookupError$);
  /** @deprecated */
  reason: $component.LookupError$;
}
export function WorkspaceError$UnsupportedComponent(
  reason: $component.LookupError$,
): WorkspaceError$;
export function WorkspaceError$isUnsupportedComponent(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$UnsupportedComponent$0(value: WorkspaceError$): $component.LookupError$;
export function WorkspaceError$UnsupportedComponent$reason(
  value: WorkspaceError$,
): $component.LookupError$;

export class InvalidComponentConfig extends _.CustomType {
  /** @deprecated */
  constructor(reason: $component.ComponentError$);
  /** @deprecated */
  reason: $component.ComponentError$;
}
export function WorkspaceError$InvalidComponentConfig(
  reason: $component.ComponentError$,
): WorkspaceError$;
export function WorkspaceError$isInvalidComponentConfig(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$InvalidComponentConfig$0(value: WorkspaceError$): $component.ComponentError$;
export function WorkspaceError$InvalidComponentConfig$reason(
  value: WorkspaceError$,
): $component.ComponentError$;

export class ConnectionRejected extends _.CustomType {
  /** @deprecated */
  constructor(reason: $workspace.ConnectionError$);
  /** @deprecated */
  reason: $workspace.ConnectionError$;
}
export function WorkspaceError$ConnectionRejected(
  reason: $workspace.ConnectionError$,
): WorkspaceError$;
export function WorkspaceError$isConnectionRejected(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$ConnectionRejected$0(value: WorkspaceError$): $workspace.ConnectionError$;
export function WorkspaceError$ConnectionRejected$reason(
  value: WorkspaceError$,
): $workspace.ConnectionError$;

export class StorageError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function WorkspaceError$StorageError(reason: string): WorkspaceError$;
export function WorkspaceError$isStorageError(
  value: any,
): value is WorkspaceError$;
export function WorkspaceError$StorageError$0(value: WorkspaceError$): string;
export function WorkspaceError$StorageError$reason(value: WorkspaceError$): string;

export type WorkspaceError$ = InvalidInstanceId | DuplicateInstance | InvalidMove | UnsupportedComponent | InvalidComponentConfig | ConnectionRejected | StorageError;

declare class Workspace<BMCZ> extends _.CustomType {
  /** @deprecated */
  constructor(
    document: $watershed.Document$<BMCZ>,
    map: $watershed.TypedMap$<$workspace.WorkspaceSchema$>,
    manifest: $watershed.SharedMap$,
    layout: $watershed.SharedSequence$,
    connections: $watershed.SharedSequence$
  );
  /** @deprecated */
  document: $watershed.Document$<BMCZ>;
  /** @deprecated */
  map: $watershed.TypedMap$<$workspace.WorkspaceSchema$>;
  /** @deprecated */
  manifest: $watershed.SharedMap$;
  /** @deprecated */
  layout: $watershed.SharedSequence$;
  /** @deprecated */
  connections: $watershed.SharedSequence$;
}

export type Workspace$<BMCZ> = Workspace<BMCZ>;

declare class Subscription extends _.CustomType {
  /** @deprecated */
  constructor(
    manifest: $watershed.SubscriptionToken$,
    layout: $watershed.SubscriptionToken$,
    connections: $watershed.SubscriptionToken$
  );
  /** @deprecated */
  manifest: $watershed.SubscriptionToken$;
  /** @deprecated */
  layout: $watershed.SubscriptionToken$;
  /** @deprecated */
  connections: $watershed.SubscriptionToken$;
}

export type Subscription$ = Subscription;

export function ensure<BMDA, BMDC>(
  document: $watershed.Document$<BMDA>,
  root: $watershed.TypedMap$<BMDC>,
  field: $schema.ChildField$<BMDC, $workspace.WorkspaceSchema$>,
  done: (x0: _.Result<Workspace$<BMDA>, WorkspaceError$>) => undefined
): undefined;

export function resolve<BMDY, BMEA>(
  document: $watershed.Document$<BMDY>,
  root: $watershed.TypedMap$<BMEA>,
  field: $schema.ChildField$<BMEA, $workspace.WorkspaceSchema$>
): _.Result<Workspace$<BMDY>, WorkspaceError$>;

export function read(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>
): $workspace.Snapshot$;

export function prepare(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>
): _.List<$workspace.PreparationState$<$watershed.SharedMap$>>;

export function subscribe(store: Workspace$<any>, changed: () => undefined): Subscription$;

export function unsubscribe(subscription: Subscription$): undefined;

export function add_instance_with<BMFF>(
  store: Workspace$<BMFF>,
  catalog: $component.Catalog$<any, any>,
  instance_id: string,
  kind: string,
  version: number,
  config: $json.Json$,
  initialize: (x0: $watershed.Document$<BMFF>, x1: $watershed.SharedMap$) => _.Result<
    undefined,
    string
  >
): _.Result<$watershed.SharedMap$, WorkspaceError$>;

export function add_instance(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>,
  instance_id: string,
  kind: string,
  version: number,
  config: $json.Json$
): _.Result<$watershed.SharedMap$, WorkspaceError$>;

export function move_instance(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>,
  instance_id: string,
  to_index: number
): _.Result<undefined, WorkspaceError$>;

export function add_connection(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>,
  connection: $port_graph.Connection$
): _.Result<undefined, WorkspaceError$>;

export function remove_connection(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>,
  connection_id: string
): _.Result<undefined, WorkspaceError$>;

export function delete_instance(
  store: Workspace$<any>,
  catalog: $component.Catalog$<any, any>,
  instance_id: string
): _.Result<undefined, WorkspaceError$>;
