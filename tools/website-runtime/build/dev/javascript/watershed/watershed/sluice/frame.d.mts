import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $types from "../../../spillway/spillway/types.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Sequenced extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: $option.Option$<string>,
    sequence_number: number,
    minimum_sequence_number: number,
    client_sequence_number: number,
    reference_sequence_number: number,
    operation_type: string,
    contents: $json.Json$,
    metadata: $option.Option$<$json.Json$>,
    timestamp: number,
    data: $option.Option$<string>
  );
  /** @deprecated */
  client_id: $option.Option$<string>;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  minimum_sequence_number: number;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  operation_type: string;
  /** @deprecated */
  contents: $json.Json$;
  /** @deprecated */
  metadata: $option.Option$<$json.Json$>;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  data: $option.Option$<string>;
}
export function Sequenced$Sequenced(
  client_id: $option.Option$<string>,
  sequence_number: number,
  minimum_sequence_number: number,
  client_sequence_number: number,
  reference_sequence_number: number,
  operation_type: string,
  contents: $json.Json$,
  metadata: $option.Option$<$json.Json$>,
  timestamp: number,
  data: $option.Option$<string>,
): Sequenced$;
export function Sequenced$isSequenced(value: any): value is Sequenced$;
export function Sequenced$Sequenced$0(value: Sequenced$): $option.Option$<
  string
>;
export function Sequenced$Sequenced$client_id(value: Sequenced$): $option.Option$<
  string
>;
export function Sequenced$Sequenced$1(value: Sequenced$): number;
export function Sequenced$Sequenced$sequence_number(value: Sequenced$): number;
export function Sequenced$Sequenced$2(value: Sequenced$): number;
export function Sequenced$Sequenced$minimum_sequence_number(value: Sequenced$): number;
export function Sequenced$Sequenced$3(
  value: Sequenced$,
): number;
export function Sequenced$Sequenced$client_sequence_number(value: Sequenced$): number;
export function Sequenced$Sequenced$4(
  value: Sequenced$,
): number;
export function Sequenced$Sequenced$reference_sequence_number(value: Sequenced$): number;
export function Sequenced$Sequenced$5(
  value: Sequenced$,
): string;
export function Sequenced$Sequenced$operation_type(value: Sequenced$): string;
export function Sequenced$Sequenced$6(value: Sequenced$): $json.Json$;
export function Sequenced$Sequenced$contents(value: Sequenced$): $json.Json$;
export function Sequenced$Sequenced$7(value: Sequenced$): $option.Option$<
  $json.Json$
>;
export function Sequenced$Sequenced$metadata(value: Sequenced$): $option.Option$<
  $json.Json$
>;
export function Sequenced$Sequenced$8(value: Sequenced$): number;
export function Sequenced$Sequenced$timestamp(value: Sequenced$): number;
export function Sequenced$Sequenced$9(value: Sequenced$): $option.Option$<
  string
>;
export function Sequenced$Sequenced$data(value: Sequenced$): $option.Option$<
  string
>;

export type Sequenced$ = Sequenced;

export class ConnectRequest extends _.CustomType {
  /** @deprecated */
  constructor(
    tenant_id: string,
    document_id: string,
    client: $types.Client$,
    last_seen_sequence_number: $option.Option$<number>
  );
  /** @deprecated */
  tenant_id: string;
  /** @deprecated */
  document_id: string;
  /** @deprecated */
  client: $types.Client$;
  /** @deprecated */
  last_seen_sequence_number: $option.Option$<number>;
}
export function ConnectRequest$ConnectRequest(
  tenant_id: string,
  document_id: string,
  client: $types.Client$,
  last_seen_sequence_number: $option.Option$<number>,
): ConnectRequest$;
export function ConnectRequest$isConnectRequest(
  value: any,
): value is ConnectRequest$;
export function ConnectRequest$ConnectRequest$0(value: ConnectRequest$): string;
export function ConnectRequest$ConnectRequest$tenant_id(value: ConnectRequest$): string;
export function ConnectRequest$ConnectRequest$1(
  value: ConnectRequest$,
): string;
export function ConnectRequest$ConnectRequest$document_id(value: ConnectRequest$): string;
export function ConnectRequest$ConnectRequest$2(
  value: ConnectRequest$,
): $types.Client$;
export function ConnectRequest$ConnectRequest$client(value: ConnectRequest$): $types.Client$;
export function ConnectRequest$ConnectRequest$3(
  value: ConnectRequest$,
): $option.Option$<number>;
export function ConnectRequest$ConnectRequest$last_seen_sequence_number(value: ConnectRequest$): $option.Option$<
  number
>;

export type ConnectRequest$ = ConnectRequest;

export class SubmittedOperation extends _.CustomType {
  /** @deprecated */
  constructor(
    operation_type: string,
    contents: $json.Json$,
    client_sequence_number: number,
    reference_sequence_number: number,
    metadata: $option.Option$<$json.Json$>
  );
  /** @deprecated */
  operation_type: string;
  /** @deprecated */
  contents: $json.Json$;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  metadata: $option.Option$<$json.Json$>;
}
export function SubmittedOperation$SubmittedOperation(
  operation_type: string,
  contents: $json.Json$,
  client_sequence_number: number,
  reference_sequence_number: number,
  metadata: $option.Option$<$json.Json$>,
): SubmittedOperation$;
export function SubmittedOperation$isSubmittedOperation(
  value: any,
): value is SubmittedOperation$;
export function SubmittedOperation$SubmittedOperation$0(value: SubmittedOperation$): string;
export function SubmittedOperation$SubmittedOperation$operation_type(
  value: SubmittedOperation$,
): string;
export function SubmittedOperation$SubmittedOperation$1(value: SubmittedOperation$): $json.Json$;
export function SubmittedOperation$SubmittedOperation$contents(
  value: SubmittedOperation$,
): $json.Json$;
export function SubmittedOperation$SubmittedOperation$2(value: SubmittedOperation$): number;
export function SubmittedOperation$SubmittedOperation$client_sequence_number(
  value: SubmittedOperation$,
): number;
export function SubmittedOperation$SubmittedOperation$3(value: SubmittedOperation$): number;
export function SubmittedOperation$SubmittedOperation$reference_sequence_number(
  value: SubmittedOperation$,
): number;
export function SubmittedOperation$SubmittedOperation$4(value: SubmittedOperation$): $option.Option$<
  $json.Json$
>;
export function SubmittedOperation$SubmittedOperation$metadata(value: SubmittedOperation$): $option.Option$<
  $json.Json$
>;

export type SubmittedOperation$ = SubmittedOperation;

export class SubmitOperation extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string, batches: _.List<_.List<SubmittedOperation$>>);
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  batches: _.List<_.List<SubmittedOperation$>>;
}
export function SubmitOperation$SubmitOperation(
  client_id: string,
  batches: _.List<_.List<SubmittedOperation$>>,
): SubmitOperation$;
export function SubmitOperation$isSubmitOperation(
  value: any,
): value is SubmitOperation$;
export function SubmitOperation$SubmitOperation$0(value: SubmitOperation$): string;
export function SubmitOperation$SubmitOperation$client_id(
  value: SubmitOperation$,
): string;
export function SubmitOperation$SubmitOperation$1(value: SubmitOperation$): _.List<
  _.List<SubmittedOperation$>
>;
export function SubmitOperation$SubmitOperation$batches(value: SubmitOperation$): _.List<
  _.List<SubmittedOperation$>
>;

export type SubmitOperation$ = SubmitOperation;

export class SignalSubmission extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    content: $json.Json$,
    signal_type: $option.Option$<string>
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  content: $json.Json$;
  /** @deprecated */
  signal_type: $option.Option$<string>;
}
export function SignalSubmission$SignalSubmission(
  client_id: string,
  content: $json.Json$,
  signal_type: $option.Option$<string>,
): SignalSubmission$;
export function SignalSubmission$isSignalSubmission(
  value: any,
): value is SignalSubmission$;
export function SignalSubmission$SignalSubmission$0(value: SignalSubmission$): string;
export function SignalSubmission$SignalSubmission$client_id(
  value: SignalSubmission$,
): string;
export function SignalSubmission$SignalSubmission$1(value: SignalSubmission$): $json.Json$;
export function SignalSubmission$SignalSubmission$content(
  value: SignalSubmission$,
): $json.Json$;
export function SignalSubmission$SignalSubmission$2(value: SignalSubmission$): $option.Option$<
  string
>;
export function SignalSubmission$SignalSubmission$signal_type(value: SignalSubmission$): $option.Option$<
  string
>;

export type SignalSubmission$ = SignalSubmission;

export class PresenceMeta extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    phx_ref: string,
    fields: _.List<[string, $json.Json$]>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  phx_ref: string;
  /** @deprecated */
  fields: _.List<[string, $json.Json$]>;
}
export function PresenceMeta$PresenceMeta(
  key: string,
  phx_ref: string,
  fields: _.List<[string, $json.Json$]>,
): PresenceMeta$;
export function PresenceMeta$isPresenceMeta(value: any): value is PresenceMeta$;
export function PresenceMeta$PresenceMeta$0(value: PresenceMeta$): string;
export function PresenceMeta$PresenceMeta$key(value: PresenceMeta$): string;
export function PresenceMeta$PresenceMeta$1(value: PresenceMeta$): string;
export function PresenceMeta$PresenceMeta$phx_ref(value: PresenceMeta$): string;
export function PresenceMeta$PresenceMeta$2(value: PresenceMeta$): _.List<
  [string, $json.Json$]
>;
export function PresenceMeta$PresenceMeta$fields(value: PresenceMeta$): _.List<
  [string, $json.Json$]
>;

export type PresenceMeta$ = PresenceMeta;

export function decode_connect_document(payload: $dynamic.Dynamic$): _.Result<
  ConnectRequest$,
  string
>;

export function decode_submit_operation(payload: $dynamic.Dynamic$): _.Result<
  SubmitOperation$,
  string
>;

export function decode_request_operations(payload: $dynamic.Dynamic$): _.Result<
  number,
  string
>;

export function decode_noop(payload: $dynamic.Dynamic$): _.Result<
  [string, number],
  string
>;

export function decode_submit_signal(payload: $dynamic.Dynamic$): _.Result<
  SignalSubmission$,
  string
>;

export function encode_sequenced(operation: Sequenced$): $json.Json$;

export function encode_connected(
  client_id: string,
  tenant_id: string,
  document_id: string,
  scopes: _.List<string>,
  checkpoint_sequence_number: number,
  initial_clients: _.List<string>,
  initial_messages: _.List<Sequenced$>,
  timestamp: number,
  presence_v1: boolean
): $json.Json$;

export function encode_operation_event(operations: _.List<Sequenced$>): $json.Json$;

export function system_join_data(client_id: string): string;

export function system_leave_data(client_id: string): string;

export function encode_signal(from_client: string, content: $json.Json$): $json.Json$;

export function decode_presence_meta(payload: $dynamic.Dynamic$): _.Result<
  _.List<[string, $json.Json$]>,
  string
>;

export function names_reserved_field(payload: $dynamic.Dynamic$): boolean;

export function encode_presence_state(entries: _.List<[string, PresenceMeta$]>): $json.Json$;

export function encode_presence_diff(
  joins: _.List<[string, PresenceMeta$]>,
  leaves: _.List<[string, PresenceMeta$]>
): $json.Json$;

export function encode_presence_error(code: string, message: string): $json.Json$;
