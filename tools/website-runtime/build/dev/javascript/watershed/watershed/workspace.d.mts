import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $component from "../watershed/component.d.mts";
import type * as $port from "../watershed/port.d.mts";
import type * as $port_graph from "../watershed/port_graph.d.mts";
import type * as $schema from "../watershed/schema.d.mts";

export type WorkspaceSchema$ = any;

export class ManifestEntry extends _.CustomType {
  /** @deprecated */
  constructor(
    instance_id: string,
    kind: string,
    version: number,
    config: $json.Json$,
    child_handle: $json.Json$
  );
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  config: $json.Json$;
  /** @deprecated */
  child_handle: $json.Json$;
}
export function ManifestEntry$ManifestEntry(
  instance_id: string,
  kind: string,
  version: number,
  config: $json.Json$,
  child_handle: $json.Json$,
): ManifestEntry$;
export function ManifestEntry$isManifestEntry(
  value: any,
): value is ManifestEntry$;
export function ManifestEntry$ManifestEntry$0(value: ManifestEntry$): string;
export function ManifestEntry$ManifestEntry$instance_id(value: ManifestEntry$): string;
export function ManifestEntry$ManifestEntry$1(
  value: ManifestEntry$,
): string;
export function ManifestEntry$ManifestEntry$kind(value: ManifestEntry$): string;
export function ManifestEntry$ManifestEntry$2(value: ManifestEntry$): number;
export function ManifestEntry$ManifestEntry$version(value: ManifestEntry$): number;
export function ManifestEntry$ManifestEntry$3(
  value: ManifestEntry$,
): $json.Json$;
export function ManifestEntry$ManifestEntry$config(value: ManifestEntry$): $json.Json$;
export function ManifestEntry$ManifestEntry$4(
  value: ManifestEntry$,
): $json.Json$;
export function ManifestEntry$ManifestEntry$child_handle(value: ManifestEntry$): $json.Json$;

export type ManifestEntry$ = ManifestEntry;

export class StoredManifestEntry extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    raw: $json.Json$,
    decoded: _.Result<ManifestEntry$, $json.DecodeError$>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  raw: $json.Json$;
  /** @deprecated */
  decoded: _.Result<ManifestEntry$, $json.DecodeError$>;
}
export function StoredManifestEntry$StoredManifestEntry(
  key: string,
  raw: $json.Json$,
  decoded: _.Result<ManifestEntry$, $json.DecodeError$>,
): StoredManifestEntry$;
export function StoredManifestEntry$isStoredManifestEntry(
  value: any,
): value is StoredManifestEntry$;
export function StoredManifestEntry$StoredManifestEntry$0(value: StoredManifestEntry$): string;
export function StoredManifestEntry$StoredManifestEntry$key(
  value: StoredManifestEntry$,
): string;
export function StoredManifestEntry$StoredManifestEntry$1(value: StoredManifestEntry$): $json.Json$;
export function StoredManifestEntry$StoredManifestEntry$raw(
  value: StoredManifestEntry$,
): $json.Json$;
export function StoredManifestEntry$StoredManifestEntry$2(value: StoredManifestEntry$): _.Result<
  ManifestEntry$,
  $json.DecodeError$
>;
export function StoredManifestEntry$StoredManifestEntry$decoded(value: StoredManifestEntry$): _.Result<
  ManifestEntry$,
  $json.DecodeError$
>;

export type StoredManifestEntry$ = StoredManifestEntry;

export class InvalidManifest extends _.CustomType {
  /** @deprecated */
  constructor(key: string, reason: $json.DecodeError$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function Diagnostic$InvalidManifest(
  key: string,
  reason: $json.DecodeError$,
): Diagnostic$;
export function Diagnostic$isInvalidManifest(value: any): value is Diagnostic$;
export function Diagnostic$InvalidManifest$0(value: Diagnostic$): string;
export function Diagnostic$InvalidManifest$key(value: Diagnostic$): string;
export function Diagnostic$InvalidManifest$1(value: Diagnostic$): $json.DecodeError$;
export function Diagnostic$InvalidManifest$reason(
  value: Diagnostic$,
): $json.DecodeError$;

export class ManifestIdMismatch extends _.CustomType {
  /** @deprecated */
  constructor(key: string, encoded_id: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  encoded_id: string;
}
export function Diagnostic$ManifestIdMismatch(
  key: string,
  encoded_id: string,
): Diagnostic$;
export function Diagnostic$isManifestIdMismatch(
  value: any,
): value is Diagnostic$;
export function Diagnostic$ManifestIdMismatch$0(value: Diagnostic$): string;
export function Diagnostic$ManifestIdMismatch$key(value: Diagnostic$): string;
export function Diagnostic$ManifestIdMismatch$1(value: Diagnostic$): string;
export function Diagnostic$ManifestIdMismatch$encoded_id(value: Diagnostic$): string;

export class InvalidLayout extends _.CustomType {
  /** @deprecated */
  constructor(index: number, reason: $json.DecodeError$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function Diagnostic$InvalidLayout(
  index: number,
  reason: $json.DecodeError$,
): Diagnostic$;
export function Diagnostic$isInvalidLayout(value: any): value is Diagnostic$;
export function Diagnostic$InvalidLayout$0(value: Diagnostic$): number;
export function Diagnostic$InvalidLayout$index(value: Diagnostic$): number;
export function Diagnostic$InvalidLayout$1(value: Diagnostic$): $json.DecodeError$;
export function Diagnostic$InvalidLayout$reason(
  value: Diagnostic$,
): $json.DecodeError$;

export class DuplicateLayout extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function Diagnostic$DuplicateLayout(instance_id: string): Diagnostic$;
export function Diagnostic$isDuplicateLayout(value: any): value is Diagnostic$;
export function Diagnostic$DuplicateLayout$0(value: Diagnostic$): string;
export function Diagnostic$DuplicateLayout$instance_id(value: Diagnostic$): string;

export class UnknownLayout extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string);
  /** @deprecated */
  instance_id: string;
}
export function Diagnostic$UnknownLayout(instance_id: string): Diagnostic$;
export function Diagnostic$isUnknownLayout(value: any): value is Diagnostic$;
export function Diagnostic$UnknownLayout$0(value: Diagnostic$): string;
export function Diagnostic$UnknownLayout$instance_id(value: Diagnostic$): string;

export class InvalidConnection extends _.CustomType {
  /** @deprecated */
  constructor(index: number, reason: $json.DecodeError$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function Diagnostic$InvalidConnection(
  index: number,
  reason: $json.DecodeError$,
): Diagnostic$;
export function Diagnostic$isInvalidConnection(
  value: any,
): value is Diagnostic$;
export function Diagnostic$InvalidConnection$0(value: Diagnostic$): number;
export function Diagnostic$InvalidConnection$index(value: Diagnostic$): number;
export function Diagnostic$InvalidConnection$1(value: Diagnostic$): $json.DecodeError$;
export function Diagnostic$InvalidConnection$reason(
  value: Diagnostic$,
): $json.DecodeError$;

export class InvalidGraph extends _.CustomType {
  /** @deprecated */
  constructor(error: $port_graph.GraphError$);
  /** @deprecated */
  error: $port_graph.GraphError$;
}
export function Diagnostic$InvalidGraph(
  error: $port_graph.GraphError$,
): Diagnostic$;
export function Diagnostic$isInvalidGraph(value: any): value is Diagnostic$;
export function Diagnostic$InvalidGraph$0(value: Diagnostic$): $port_graph.GraphError$;
export function Diagnostic$InvalidGraph$error(
  value: Diagnostic$,
): $port_graph.GraphError$;

export type Diagnostic$ = InvalidManifest | ManifestIdMismatch | InvalidLayout | DuplicateLayout | UnknownLayout | InvalidConnection | InvalidGraph;

export class Loading extends _.CustomType {
  /** @deprecated */
  constructor(entry: ManifestEntry$, reason: string);
  /** @deprecated */
  entry: ManifestEntry$;
  /** @deprecated */
  reason: string;
}
export function PreparationState$Loading<BLFC>(
  entry: ManifestEntry$,
  reason: string,
): PreparationState$<BLFC>;
export function PreparationState$isLoading<BLFC>(
  value: any,
): value is PreparationState$<unknown>;
export function PreparationState$Loading$0<BLFC>(value: PreparationState$<BLFC>): ManifestEntry$;
export function PreparationState$Loading$entry<BLFC>(
  value: PreparationState$<BLFC>,
): ManifestEntry$;
export function PreparationState$Loading$1<BLFC>(value: PreparationState$<BLFC>): string;
export function PreparationState$Loading$reason<BLFC>(
  value: PreparationState$<BLFC>,
): string;

export class Prepared<BLFC> extends _.CustomType {
  /** @deprecated */
  constructor(entry: ManifestEntry$, subtree: BLFC);
  /** @deprecated */
  entry: ManifestEntry$;
  /** @deprecated */
  subtree: BLFC;
}
export function PreparationState$Prepared<BLFC>(
  entry: ManifestEntry$,
  subtree: BLFC,
): PreparationState$<BLFC>;
export function PreparationState$isPrepared<BLFC>(
  value: any,
): value is PreparationState$<unknown>;
export function PreparationState$Prepared$0<BLFC>(value: PreparationState$<BLFC>): ManifestEntry$;
export function PreparationState$Prepared$entry<BLFC>(
  value: PreparationState$<BLFC>,
): ManifestEntry$;
export function PreparationState$Prepared$1<BLFC>(value: PreparationState$<BLFC>): BLFC;
export function PreparationState$Prepared$subtree<BLFC>(
  value: PreparationState$<BLFC>,
): BLFC;

export class Unavailable extends _.CustomType {
  /** @deprecated */
  constructor(entry: ManifestEntry$, reason: $component.LookupError$);
  /** @deprecated */
  entry: ManifestEntry$;
  /** @deprecated */
  reason: $component.LookupError$;
}
export function PreparationState$Unavailable<BLFC>(
  entry: ManifestEntry$,
  reason: $component.LookupError$,
): PreparationState$<BLFC>;
export function PreparationState$isUnavailable<BLFC>(
  value: any,
): value is PreparationState$<unknown>;
export function PreparationState$Unavailable$0<BLFC>(value: PreparationState$<
    BLFC
  >): ManifestEntry$;
export function PreparationState$Unavailable$entry<BLFC>(value: PreparationState$<
    BLFC
  >): ManifestEntry$;
export function PreparationState$Unavailable$1<BLFC>(value: PreparationState$<
    BLFC
  >): $component.LookupError$;
export function PreparationState$Unavailable$reason<BLFC>(value: PreparationState$<
    BLFC
  >): $component.LookupError$;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(instance_id: string, reason: PreparationError$);
  /** @deprecated */
  instance_id: string;
  /** @deprecated */
  reason: PreparationError$;
}
export function PreparationState$Failed<BLFC>(
  instance_id: string,
  reason: PreparationError$,
): PreparationState$<BLFC>;
export function PreparationState$isFailed<BLFC>(
  value: any,
): value is PreparationState$<unknown>;
export function PreparationState$Failed$0<BLFC>(value: PreparationState$<BLFC>): string;
export function PreparationState$Failed$instance_id<BLFC>(
  value: PreparationState$<BLFC>,
): string;
export function PreparationState$Failed$1<BLFC>(value: PreparationState$<BLFC>): PreparationError$;
export function PreparationState$Failed$reason<BLFC>(
  value: PreparationState$<BLFC>,
): PreparationError$;

export type PreparationState$<BLFC> = Loading | Prepared<BLFC> | Unavailable | Failed;

export class InvalidStoredManifest extends _.CustomType {
  /** @deprecated */
  constructor(reason: $json.DecodeError$);
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function PreparationError$InvalidStoredManifest(
  reason: $json.DecodeError$,
): PreparationError$;
export function PreparationError$isInvalidStoredManifest(
  value: any,
): value is PreparationError$;
export function PreparationError$InvalidStoredManifest$0(value: PreparationError$): $json.DecodeError$;
export function PreparationError$InvalidStoredManifest$reason(
  value: PreparationError$,
): $json.DecodeError$;

export class StoredIdMismatch extends _.CustomType {
  /** @deprecated */
  constructor(encoded_id: string);
  /** @deprecated */
  encoded_id: string;
}
export function PreparationError$StoredIdMismatch(
  encoded_id: string,
): PreparationError$;
export function PreparationError$isStoredIdMismatch(
  value: any,
): value is PreparationError$;
export function PreparationError$StoredIdMismatch$0(value: PreparationError$): string;
export function PreparationError$StoredIdMismatch$encoded_id(
  value: PreparationError$,
): string;

export class InvalidComponentConfig extends _.CustomType {
  /** @deprecated */
  constructor(reason: $component.ComponentError$);
  /** @deprecated */
  reason: $component.ComponentError$;
}
export function PreparationError$InvalidComponentConfig(
  reason: $component.ComponentError$,
): PreparationError$;
export function PreparationError$isInvalidComponentConfig(
  value: any,
): value is PreparationError$;
export function PreparationError$InvalidComponentConfig$0(value: PreparationError$): $component.ComponentError$;
export function PreparationError$InvalidComponentConfig$reason(
  value: PreparationError$,
): $component.ComponentError$;

export type PreparationError$ = InvalidStoredManifest | StoredIdMismatch | InvalidComponentConfig;

export class RejectedConnection extends _.CustomType {
  /** @deprecated */
  constructor(reason: $port_graph.GraphError$);
  /** @deprecated */
  reason: $port_graph.GraphError$;
}
export function ConnectionError$RejectedConnection(
  reason: $port_graph.GraphError$,
): ConnectionError$;
export function ConnectionError$isRejectedConnection(
  value: any,
): value is ConnectionError$;
export function ConnectionError$RejectedConnection$0(value: ConnectionError$): $port_graph.GraphError$;
export function ConnectionError$RejectedConnection$reason(
  value: ConnectionError$,
): $port_graph.GraphError$;

export class DisplacesConnection extends _.CustomType {
  /** @deprecated */
  constructor(connection_id: string);
  /** @deprecated */
  connection_id: string;
}
export function ConnectionError$DisplacesConnection(
  connection_id: string,
): ConnectionError$;
export function ConnectionError$isDisplacesConnection(
  value: any,
): value is ConnectionError$;
export function ConnectionError$DisplacesConnection$0(value: ConnectionError$): string;
export function ConnectionError$DisplacesConnection$connection_id(
  value: ConnectionError$,
): string;

export type ConnectionError$ = RejectedConnection | DisplacesConnection;

export class Move extends _.CustomType {
  /** @deprecated */
  constructor(
    remove_indexes: _.List<number>,
    from_index: number,
    to_index: number
  );
  /** @deprecated */
  remove_indexes: _.List<number>;
  /** @deprecated */
  from_index: number;
  /** @deprecated */
  to_index: number;
}
export function Move$Move(
  remove_indexes: _.List<number>,
  from_index: number,
  to_index: number,
): Move$;
export function Move$isMove(value: any): value is Move$;
export function Move$Move$0(value: Move$): _.List<number>;
export function Move$Move$remove_indexes(value: Move$): _.List<number>;
export function Move$Move$1(value: Move$): number;
export function Move$Move$from_index(value: Move$): number;
export function Move$Move$2(value: Move$): number;
export function Move$Move$to_index(value: Move$): number;

export type Move$ = Move;

declare class Snapshot extends _.CustomType {
  /** @deprecated */
  constructor(
    manifest: _.List<StoredManifestEntry$>,
    entries: _.List<ManifestEntry$>,
    raw_layout: _.List<$json.Json$>,
    layout: _.List<string>,
    raw_connections: _.List<$json.Json$>,
    stored_connections: _.List<$port_graph.Connection$>,
    graph: $port_graph.EffectiveGraph$,
    diagnostics: _.List<Diagnostic$>
  );
  /** @deprecated */
  manifest: _.List<StoredManifestEntry$>;
  /** @deprecated */
  entries: _.List<ManifestEntry$>;
  /** @deprecated */
  raw_layout: _.List<$json.Json$>;
  /** @deprecated */
  layout: _.List<string>;
  /** @deprecated */
  raw_connections: _.List<$json.Json$>;
  /** @deprecated */
  stored_connections: _.List<$port_graph.Connection$>;
  /** @deprecated */
  graph: $port_graph.EffectiveGraph$;
  /** @deprecated */
  diagnostics: _.List<Diagnostic$>;
}

export type Snapshot$ = Snapshot;

export function manifest_field(): $schema.ChannelField$<
  WorkspaceSchema$,
  $schema.MapChannel$
>;

export function layout_field(): $schema.ChannelField$<
  WorkspaceSchema$,
  $schema.SequenceChannel$
>;

export function connections_field(): $schema.ChannelField$<
  WorkspaceSchema$,
  $schema.SequenceChannel$
>;

export function encode_manifest(entry: ManifestEntry$): $json.Json$;

export function manifest_decoder(): $decode.Decoder$<ManifestEntry$>;

export function decode_manifest(value: $json.Json$): _.Result<
  ManifestEntry$,
  $json.DecodeError$
>;

export function encode_connection(connection: $port_graph.Connection$): $json.Json$;

export function connection_decoder(): $decode.Decoder$<$port_graph.Connection$>;

export function decode_connection(value: $json.Json$): _.Result<
  $port_graph.Connection$,
  $json.DecodeError$
>;

export function snapshot(
  raw_manifest: _.List<[string, $json.Json$]>,
  raw_layout: _.List<$json.Json$>,
  raw_connections: _.List<$json.Json$>,
  catalog: $component.Catalog$<any, any>
): Snapshot$;

export function manifest_entries(snapshot: Snapshot$): _.List<ManifestEntry$>;

export function stored_manifest(snapshot: Snapshot$): _.List<
  StoredManifestEntry$
>;

export function layout(snapshot: Snapshot$): _.List<string>;

export function raw_layout(snapshot: Snapshot$): _.List<$json.Json$>;

export function graph(snapshot: Snapshot$): $port_graph.EffectiveGraph$;

export function raw_connections(snapshot: Snapshot$): _.List<$json.Json$>;

export function diagnostics(snapshot: Snapshot$): _.List<Diagnostic$>;

export function prepare<BLGH>(
  snapshot: Snapshot$,
  catalog: $component.Catalog$<any, any>,
  resolve_child: (x0: $json.Json$) => _.Result<BLGH, string>
): _.List<PreparationState$<BLGH>>;

export function plan_move(
  snapshot: Snapshot$,
  instance_id: string,
  to_index: number
): _.Result<Move$, undefined>;

export function layout_removal_indices(snapshot: Snapshot$, instance_id: string): _.List<
  number
>;

export function connection_id_removal_indices(
  snapshot: Snapshot$,
  connection_id: string
): _.List<number>;

export function instance_connection_indices(
  snapshot: Snapshot$,
  instance_id: string
): _.List<number>;

export function validate_connection(
  snapshot: Snapshot$,
  candidate: $port_graph.Connection$,
  catalog: $component.Catalog$<any, any>
): _.Result<undefined, ConnectionError$>;
