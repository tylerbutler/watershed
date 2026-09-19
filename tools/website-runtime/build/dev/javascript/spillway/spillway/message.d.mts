import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $types from "../../signet/signet/types.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $types from "../spillway/types.d.mts";

export class ConnectMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    tenant_id: string,
    document_id: string,
    token: $option.Option$<string>,
    client: $types.Client$,
    versions: _.List<string>,
    driver_version: $option.Option$<string>,
    mode: $types.ConnectionMode$,
    nonce: $option.Option$<string>,
    epoch: $option.Option$<string>,
    supported_features: $option.Option$<$dict.Dict$<string, $dynamic.Dynamic$>>,
    relay_user_agent: $option.Option$<string>
  );
  /** @deprecated */
  tenant_id: string;
  /** @deprecated */
  document_id: string;
  /** @deprecated */
  token: $option.Option$<string>;
  /** @deprecated */
  client: $types.Client$;
  /** @deprecated */
  versions: _.List<string>;
  /** @deprecated */
  driver_version: $option.Option$<string>;
  /** @deprecated */
  mode: $types.ConnectionMode$;
  /** @deprecated */
  nonce: $option.Option$<string>;
  /** @deprecated */
  epoch: $option.Option$<string>;
  /** @deprecated */
  supported_features: $option.Option$<$dict.Dict$<string, $dynamic.Dynamic$>>;
  /** @deprecated */
  relay_user_agent: $option.Option$<string>;
}
export function ConnectMessage$ConnectMessage(
  tenant_id: string,
  document_id: string,
  token: $option.Option$<string>,
  client: $types.Client$,
  versions: _.List<string>,
  driver_version: $option.Option$<string>,
  mode: $types.ConnectionMode$,
  nonce: $option.Option$<string>,
  epoch: $option.Option$<string>,
  supported_features: $option.Option$<$dict.Dict$<string, $dynamic.Dynamic$>>,
  relay_user_agent: $option.Option$<string>,
): ConnectMessage$;
export function ConnectMessage$isConnectMessage(
  value: any,
): value is ConnectMessage$;
export function ConnectMessage$ConnectMessage$0(value: ConnectMessage$): string;
export function ConnectMessage$ConnectMessage$tenant_id(value: ConnectMessage$): string;
export function ConnectMessage$ConnectMessage$1(
  value: ConnectMessage$,
): string;
export function ConnectMessage$ConnectMessage$document_id(value: ConnectMessage$): string;
export function ConnectMessage$ConnectMessage$2(
  value: ConnectMessage$,
): $option.Option$<string>;
export function ConnectMessage$ConnectMessage$token(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$3(value: ConnectMessage$): $types.Client$;
export function ConnectMessage$ConnectMessage$client(
  value: ConnectMessage$,
): $types.Client$;
export function ConnectMessage$ConnectMessage$4(value: ConnectMessage$): _.List<
  string
>;
export function ConnectMessage$ConnectMessage$versions(value: ConnectMessage$): _.List<
  string
>;
export function ConnectMessage$ConnectMessage$5(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$driver_version(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$6(value: ConnectMessage$): $types.ConnectionMode$;
export function ConnectMessage$ConnectMessage$mode(
  value: ConnectMessage$,
): $types.ConnectionMode$;
export function ConnectMessage$ConnectMessage$7(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$nonce(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$8(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$epoch(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$9(value: ConnectMessage$): $option.Option$<
  $dict.Dict$<string, $dynamic.Dynamic$>
>;
export function ConnectMessage$ConnectMessage$supported_features(value: ConnectMessage$): $option.Option$<
  $dict.Dict$<string, $dynamic.Dynamic$>
>;
export function ConnectMessage$ConnectMessage$10(value: ConnectMessage$): $option.Option$<
  string
>;
export function ConnectMessage$ConnectMessage$relay_user_agent(value: ConnectMessage$): $option.Option$<
  string
>;

export type ConnectMessage$ = ConnectMessage;

export class ConnectedMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    claims: $types.TokenClaims$,
    client_id: string,
    existing: boolean,
    max_message_size: number,
    mode: $types.ConnectionMode$,
    service_configuration: $types.ServiceConfiguration$,
    initial_clients: _.List<$types.SignalClient$>,
    initial_messages: _.List<$types.SequencedDocumentMessage$>,
    initial_signals: _.List<SignalMessage$>,
    supported_versions: _.List<string>,
    supported_features: $dict.Dict$<string, $dynamic.Dynamic$>,
    version: string,
    timestamp: $option.Option$<number>,
    checkpoint_sequence_number: $option.Option$<number>,
    epoch: $option.Option$<string>,
    relay_service_agent: $option.Option$<string>,
    summary_context: $option.Option$<SummaryContext$>
  );
  /** @deprecated */
  claims: $types.TokenClaims$;
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  existing: boolean;
  /** @deprecated */
  max_message_size: number;
  /** @deprecated */
  mode: $types.ConnectionMode$;
  /** @deprecated */
  service_configuration: $types.ServiceConfiguration$;
  /** @deprecated */
  initial_clients: _.List<$types.SignalClient$>;
  /** @deprecated */
  initial_messages: _.List<$types.SequencedDocumentMessage$>;
  /** @deprecated */
  initial_signals: _.List<SignalMessage$>;
  /** @deprecated */
  supported_versions: _.List<string>;
  /** @deprecated */
  supported_features: $dict.Dict$<string, $dynamic.Dynamic$>;
  /** @deprecated */
  version: string;
  /** @deprecated */
  timestamp: $option.Option$<number>;
  /** @deprecated */
  checkpoint_sequence_number: $option.Option$<number>;
  /** @deprecated */
  epoch: $option.Option$<string>;
  /** @deprecated */
  relay_service_agent: $option.Option$<string>;
  /** @deprecated */
  summary_context: $option.Option$<SummaryContext$>;
}
export function ConnectedMessage$ConnectedMessage(
  claims: $types.TokenClaims$,
  client_id: string,
  existing: boolean,
  max_message_size: number,
  mode: $types.ConnectionMode$,
  service_configuration: $types.ServiceConfiguration$,
  initial_clients: _.List<$types.SignalClient$>,
  initial_messages: _.List<$types.SequencedDocumentMessage$>,
  initial_signals: _.List<SignalMessage$>,
  supported_versions: _.List<string>,
  supported_features: $dict.Dict$<string, $dynamic.Dynamic$>,
  version: string,
  timestamp: $option.Option$<number>,
  checkpoint_sequence_number: $option.Option$<number>,
  epoch: $option.Option$<string>,
  relay_service_agent: $option.Option$<string>,
  summary_context: $option.Option$<SummaryContext$>,
): ConnectedMessage$;
export function ConnectedMessage$isConnectedMessage(
  value: any,
): value is ConnectedMessage$;
export function ConnectedMessage$ConnectedMessage$0(value: ConnectedMessage$): $types.TokenClaims$;
export function ConnectedMessage$ConnectedMessage$claims(
  value: ConnectedMessage$,
): $types.TokenClaims$;
export function ConnectedMessage$ConnectedMessage$1(value: ConnectedMessage$): string;
export function ConnectedMessage$ConnectedMessage$client_id(
  value: ConnectedMessage$,
): string;
export function ConnectedMessage$ConnectedMessage$2(value: ConnectedMessage$): boolean;
export function ConnectedMessage$ConnectedMessage$existing(
  value: ConnectedMessage$,
): boolean;
export function ConnectedMessage$ConnectedMessage$3(value: ConnectedMessage$): number;
export function ConnectedMessage$ConnectedMessage$max_message_size(
  value: ConnectedMessage$,
): number;
export function ConnectedMessage$ConnectedMessage$4(value: ConnectedMessage$): $types.ConnectionMode$;
export function ConnectedMessage$ConnectedMessage$mode(
  value: ConnectedMessage$,
): $types.ConnectionMode$;
export function ConnectedMessage$ConnectedMessage$5(value: ConnectedMessage$): $types.ServiceConfiguration$;
export function ConnectedMessage$ConnectedMessage$service_configuration(
  value: ConnectedMessage$,
): $types.ServiceConfiguration$;
export function ConnectedMessage$ConnectedMessage$6(value: ConnectedMessage$): _.List<
  $types.SignalClient$
>;
export function ConnectedMessage$ConnectedMessage$initial_clients(value: ConnectedMessage$): _.List<
  $types.SignalClient$
>;
export function ConnectedMessage$ConnectedMessage$7(value: ConnectedMessage$): _.List<
  $types.SequencedDocumentMessage$
>;
export function ConnectedMessage$ConnectedMessage$initial_messages(value: ConnectedMessage$): _.List<
  $types.SequencedDocumentMessage$
>;
export function ConnectedMessage$ConnectedMessage$8(value: ConnectedMessage$): _.List<
  SignalMessage$
>;
export function ConnectedMessage$ConnectedMessage$initial_signals(value: ConnectedMessage$): _.List<
  SignalMessage$
>;
export function ConnectedMessage$ConnectedMessage$9(value: ConnectedMessage$): _.List<
  string
>;
export function ConnectedMessage$ConnectedMessage$supported_versions(value: ConnectedMessage$): _.List<
  string
>;
export function ConnectedMessage$ConnectedMessage$10(value: ConnectedMessage$): $dict.Dict$<
  string,
  $dynamic.Dynamic$
>;
export function ConnectedMessage$ConnectedMessage$supported_features(value: ConnectedMessage$): $dict.Dict$<
  string,
  $dynamic.Dynamic$
>;
export function ConnectedMessage$ConnectedMessage$11(value: ConnectedMessage$): string;
export function ConnectedMessage$ConnectedMessage$version(
  value: ConnectedMessage$,
): string;
export function ConnectedMessage$ConnectedMessage$12(value: ConnectedMessage$): $option.Option$<
  number
>;
export function ConnectedMessage$ConnectedMessage$timestamp(value: ConnectedMessage$): $option.Option$<
  number
>;
export function ConnectedMessage$ConnectedMessage$13(value: ConnectedMessage$): $option.Option$<
  number
>;
export function ConnectedMessage$ConnectedMessage$checkpoint_sequence_number(value: ConnectedMessage$): $option.Option$<
  number
>;
export function ConnectedMessage$ConnectedMessage$14(value: ConnectedMessage$): $option.Option$<
  string
>;
export function ConnectedMessage$ConnectedMessage$epoch(value: ConnectedMessage$): $option.Option$<
  string
>;
export function ConnectedMessage$ConnectedMessage$15(value: ConnectedMessage$): $option.Option$<
  string
>;
export function ConnectedMessage$ConnectedMessage$relay_service_agent(value: ConnectedMessage$): $option.Option$<
  string
>;
export function ConnectedMessage$ConnectedMessage$16(value: ConnectedMessage$): $option.Option$<
  SummaryContext$
>;
export function ConnectedMessage$ConnectedMessage$summary_context(value: ConnectedMessage$): $option.Option$<
  SummaryContext$
>;

export type ConnectedMessage$ = ConnectedMessage;

export class SummaryContext extends _.CustomType {
  /** @deprecated */
  constructor(handle: string, sequence_number: number);
  /** @deprecated */
  handle: string;
  /** @deprecated */
  sequence_number: number;
}
export function SummaryContext$SummaryContext(
  handle: string,
  sequence_number: number,
): SummaryContext$;
export function SummaryContext$isSummaryContext(
  value: any,
): value is SummaryContext$;
export function SummaryContext$SummaryContext$0(value: SummaryContext$): string;
export function SummaryContext$SummaryContext$handle(value: SummaryContext$): string;
export function SummaryContext$SummaryContext$1(
  value: SummaryContext$,
): number;
export function SummaryContext$SummaryContext$sequence_number(value: SummaryContext$): number;

export type SummaryContext$ = SummaryContext;

export class ConnectError extends _.CustomType {
  /** @deprecated */
  constructor(code: number, message: string);
  /** @deprecated */
  code: number;
  /** @deprecated */
  message: string;
}
export function ConnectError$ConnectError(
  code: number,
  message: string,
): ConnectError$;
export function ConnectError$isConnectError(value: any): value is ConnectError$;
export function ConnectError$ConnectError$0(value: ConnectError$): number;
export function ConnectError$ConnectError$code(value: ConnectError$): number;
export function ConnectError$ConnectError$1(value: ConnectError$): string;
export function ConnectError$ConnectError$message(value: ConnectError$): string;

export type ConnectError$ = ConnectError;

export class SignalMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: $option.Option$<string>,
    content: $dynamic.Dynamic$,
    signal_type: $option.Option$<string>,
    client_connection_number: $option.Option$<number>,
    reference_sequence_number: $option.Option$<number>,
    target_client_id: $option.Option$<string>
  );
  /** @deprecated */
  client_id: $option.Option$<string>;
  /** @deprecated */
  content: $dynamic.Dynamic$;
  /** @deprecated */
  signal_type: $option.Option$<string>;
  /** @deprecated */
  client_connection_number: $option.Option$<number>;
  /** @deprecated */
  reference_sequence_number: $option.Option$<number>;
  /** @deprecated */
  target_client_id: $option.Option$<string>;
}
export function SignalMessage$SignalMessage(
  client_id: $option.Option$<string>,
  content: $dynamic.Dynamic$,
  signal_type: $option.Option$<string>,
  client_connection_number: $option.Option$<number>,
  reference_sequence_number: $option.Option$<number>,
  target_client_id: $option.Option$<string>,
): SignalMessage$;
export function SignalMessage$isSignalMessage(
  value: any,
): value is SignalMessage$;
export function SignalMessage$SignalMessage$0(value: SignalMessage$): $option.Option$<
  string
>;
export function SignalMessage$SignalMessage$client_id(value: SignalMessage$): $option.Option$<
  string
>;
export function SignalMessage$SignalMessage$1(value: SignalMessage$): $dynamic.Dynamic$;
export function SignalMessage$SignalMessage$content(
  value: SignalMessage$,
): $dynamic.Dynamic$;
export function SignalMessage$SignalMessage$2(value: SignalMessage$): $option.Option$<
  string
>;
export function SignalMessage$SignalMessage$signal_type(value: SignalMessage$): $option.Option$<
  string
>;
export function SignalMessage$SignalMessage$3(value: SignalMessage$): $option.Option$<
  number
>;
export function SignalMessage$SignalMessage$client_connection_number(value: SignalMessage$): $option.Option$<
  number
>;
export function SignalMessage$SignalMessage$4(value: SignalMessage$): $option.Option$<
  number
>;
export function SignalMessage$SignalMessage$reference_sequence_number(value: SignalMessage$): $option.Option$<
  number
>;
export function SignalMessage$SignalMessage$5(value: SignalMessage$): $option.Option$<
  string
>;
export function SignalMessage$SignalMessage$target_client_id(value: SignalMessage$): $option.Option$<
  string
>;

export type SignalMessage$ = SignalMessage;

export class SentSignalMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    content: $dynamic.Dynamic$,
    signal_type: $option.Option$<string>,
    client_connection_number: $option.Option$<number>,
    reference_sequence_number: $option.Option$<number>,
    target_client_id: $option.Option$<string>
  );
  /** @deprecated */
  content: $dynamic.Dynamic$;
  /** @deprecated */
  signal_type: $option.Option$<string>;
  /** @deprecated */
  client_connection_number: $option.Option$<number>;
  /** @deprecated */
  reference_sequence_number: $option.Option$<number>;
  /** @deprecated */
  target_client_id: $option.Option$<string>;
}
export function SentSignalMessage$SentSignalMessage(
  content: $dynamic.Dynamic$,
  signal_type: $option.Option$<string>,
  client_connection_number: $option.Option$<number>,
  reference_sequence_number: $option.Option$<number>,
  target_client_id: $option.Option$<string>,
): SentSignalMessage$;
export function SentSignalMessage$isSentSignalMessage(
  value: any,
): value is SentSignalMessage$;
export function SentSignalMessage$SentSignalMessage$0(value: SentSignalMessage$): $dynamic.Dynamic$;
export function SentSignalMessage$SentSignalMessage$content(
  value: SentSignalMessage$,
): $dynamic.Dynamic$;
export function SentSignalMessage$SentSignalMessage$1(value: SentSignalMessage$): $option.Option$<
  string
>;
export function SentSignalMessage$SentSignalMessage$signal_type(value: SentSignalMessage$): $option.Option$<
  string
>;
export function SentSignalMessage$SentSignalMessage$2(value: SentSignalMessage$): $option.Option$<
  number
>;
export function SentSignalMessage$SentSignalMessage$client_connection_number(value: SentSignalMessage$): $option.Option$<
  number
>;
export function SentSignalMessage$SentSignalMessage$3(value: SentSignalMessage$): $option.Option$<
  number
>;
export function SentSignalMessage$SentSignalMessage$reference_sequence_number(value: SentSignalMessage$): $option.Option$<
  number
>;
export function SentSignalMessage$SentSignalMessage$4(value: SentSignalMessage$): $option.Option$<
  string
>;
export function SentSignalMessage$SentSignalMessage$target_client_id(value: SentSignalMessage$): $option.Option$<
  string
>;

export type SentSignalMessage$ = SentSignalMessage;

export class OpMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    document_id: string,
    ops: _.List<$types.SequencedDocumentMessage$>
  );
  /** @deprecated */
  document_id: string;
  /** @deprecated */
  ops: _.List<$types.SequencedDocumentMessage$>;
}
export function OpMessage$OpMessage(
  document_id: string,
  ops: _.List<$types.SequencedDocumentMessage$>,
): OpMessage$;
export function OpMessage$isOpMessage(value: any): value is OpMessage$;
export function OpMessage$OpMessage$0(value: OpMessage$): string;
export function OpMessage$OpMessage$document_id(value: OpMessage$): string;
export function OpMessage$OpMessage$1(value: OpMessage$): _.List<
  $types.SequencedDocumentMessage$
>;
export function OpMessage$OpMessage$ops(value: OpMessage$): _.List<
  $types.SequencedDocumentMessage$
>;

export type OpMessage$ = OpMessage;

export class NoOp extends _.CustomType {}
export function MessageType$NoOp(): MessageType$;
export function MessageType$isNoOp(value: any): value is MessageType$;

export class ClientJoin extends _.CustomType {}
export function MessageType$ClientJoin(): MessageType$;
export function MessageType$isClientJoin(value: any): value is MessageType$;

export class ClientLeave extends _.CustomType {}
export function MessageType$ClientLeave(): MessageType$;
export function MessageType$isClientLeave(value: any): value is MessageType$;

export class Propose extends _.CustomType {}
export function MessageType$Propose(): MessageType$;
export function MessageType$isPropose(value: any): value is MessageType$;

export class Reject extends _.CustomType {}
export function MessageType$Reject(): MessageType$;
export function MessageType$isReject(value: any): value is MessageType$;

export class Accept extends _.CustomType {}
export function MessageType$Accept(): MessageType$;
export function MessageType$isAccept(value: any): value is MessageType$;

export class Summarize extends _.CustomType {}
export function MessageType$Summarize(): MessageType$;
export function MessageType$isSummarize(value: any): value is MessageType$;

export class SummaryAck extends _.CustomType {}
export function MessageType$SummaryAck(): MessageType$;
export function MessageType$isSummaryAck(value: any): value is MessageType$;

export class SummaryNack extends _.CustomType {}
export function MessageType$SummaryNack(): MessageType$;
export function MessageType$isSummaryNack(value: any): value is MessageType$;

export class Operation extends _.CustomType {}
export function MessageType$Operation(): MessageType$;
export function MessageType$isOperation(value: any): value is MessageType$;

export class NoClient extends _.CustomType {}
export function MessageType$NoClient(): MessageType$;
export function MessageType$isNoClient(value: any): value is MessageType$;

export class RoundTrip extends _.CustomType {}
export function MessageType$RoundTrip(): MessageType$;
export function MessageType$isRoundTrip(value: any): value is MessageType$;

export class Control extends _.CustomType {}
export function MessageType$Control(): MessageType$;
export function MessageType$isControl(value: any): value is MessageType$;

export type MessageType$ = NoOp | ClientJoin | ClientLeave | Propose | Reject | Accept | Summarize | SummaryAck | SummaryNack | Operation | NoClient | RoundTrip | Control;

export function message_type_to_string(mt: MessageType$): string;

export function message_type_from_string(s: string): _.Result<
  MessageType$,
  undefined
>;
