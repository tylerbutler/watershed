import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $types from "../spillway/types.d.mts";

export class ClientJoinSignal extends _.CustomType {}
export function SystemSignalType$ClientJoinSignal(): SystemSignalType$;
export function SystemSignalType$isClientJoinSignal(
  value: any,
): value is SystemSignalType$;

export class ClientLeaveSignal extends _.CustomType {}
export function SystemSignalType$ClientLeaveSignal(): SystemSignalType$;
export function SystemSignalType$isClientLeaveSignal(
  value: any,
): value is SystemSignalType$;

export type SystemSignalType$ = ClientJoinSignal | ClientLeaveSignal;

export class ClientJoinContent extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string, client: $types.Client$);
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  client: $types.Client$;
}
export function ClientJoinContent$ClientJoinContent(
  client_id: string,
  client: $types.Client$,
): ClientJoinContent$;
export function ClientJoinContent$isClientJoinContent(
  value: any,
): value is ClientJoinContent$;
export function ClientJoinContent$ClientJoinContent$0(value: ClientJoinContent$): string;
export function ClientJoinContent$ClientJoinContent$client_id(
  value: ClientJoinContent$,
): string;
export function ClientJoinContent$ClientJoinContent$1(value: ClientJoinContent$): $types.Client$;
export function ClientJoinContent$ClientJoinContent$client(
  value: ClientJoinContent$,
): $types.Client$;

export type ClientJoinContent$ = ClientJoinContent;

export class ClientLeaveContent extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string);
  /** @deprecated */
  client_id: string;
}
export function ClientLeaveContent$ClientLeaveContent(
  client_id: string,
): ClientLeaveContent$;
export function ClientLeaveContent$isClientLeaveContent(
  value: any,
): value is ClientLeaveContent$;
export function ClientLeaveContent$ClientLeaveContent$0(value: ClientLeaveContent$): string;
export function ClientLeaveContent$ClientLeaveContent$client_id(
  value: ClientLeaveContent$,
): string;

export type ClientLeaveContent$ = ClientLeaveContent;

export class JoinSignal extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ClientJoinContent$);
  /** @deprecated */
  0: ClientJoinContent$;
}
export function SystemSignal$JoinSignal($0: ClientJoinContent$): SystemSignal$;
export function SystemSignal$isJoinSignal(value: any): value is SystemSignal$;
export function SystemSignal$JoinSignal$0(value: SystemSignal$): ClientJoinContent$;

export class LeaveSignal extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ClientLeaveContent$);
  /** @deprecated */
  0: ClientLeaveContent$;
}
export function SystemSignal$LeaveSignal(
  $0: ClientLeaveContent$,
): SystemSignal$;
export function SystemSignal$isLeaveSignal(value: any): value is SystemSignal$;
export function SystemSignal$LeaveSignal$0(value: SystemSignal$): ClientLeaveContent$;

export type SystemSignal$ = JoinSignal | LeaveSignal;

export class BroadcastAddress extends _.CustomType {}
export function SignalAddress$BroadcastAddress(): SignalAddress$;
export function SignalAddress$isBroadcastAddress(
  value: any,
): value is SignalAddress$;

export class ContainerAddress extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function SignalAddress$ContainerAddress($0: string): SignalAddress$;
export function SignalAddress$isContainerAddress(
  value: any,
): value is SignalAddress$;
export function SignalAddress$ContainerAddress$0(value: SignalAddress$): string;

export type SignalAddress$ = BroadcastAddress | ContainerAddress;

export class SignalV1Envelope extends _.CustomType {
  /** @deprecated */
  constructor(
    address: string,
    contents: SignalV1Contents$,
    client_broadcast_signal_sequence_number: number
  );
  /** @deprecated */
  address: string;
  /** @deprecated */
  contents: SignalV1Contents$;
  /** @deprecated */
  client_broadcast_signal_sequence_number: number;
}
export function SignalV1Envelope$SignalV1Envelope(
  address: string,
  contents: SignalV1Contents$,
  client_broadcast_signal_sequence_number: number,
): SignalV1Envelope$;
export function SignalV1Envelope$isSignalV1Envelope(
  value: any,
): value is SignalV1Envelope$;
export function SignalV1Envelope$SignalV1Envelope$0(value: SignalV1Envelope$): string;
export function SignalV1Envelope$SignalV1Envelope$address(
  value: SignalV1Envelope$,
): string;
export function SignalV1Envelope$SignalV1Envelope$1(value: SignalV1Envelope$): SignalV1Contents$;
export function SignalV1Envelope$SignalV1Envelope$contents(
  value: SignalV1Envelope$,
): SignalV1Contents$;
export function SignalV1Envelope$SignalV1Envelope$2(value: SignalV1Envelope$): number;
export function SignalV1Envelope$SignalV1Envelope$client_broadcast_signal_sequence_number(
  value: SignalV1Envelope$,
): number;

export type SignalV1Envelope$ = SignalV1Envelope;

export class SignalV1Contents extends _.CustomType {
  /** @deprecated */
  constructor(signal_type: string, content: $dynamic.Dynamic$);
  /** @deprecated */
  signal_type: string;
  /** @deprecated */
  content: $dynamic.Dynamic$;
}
export function SignalV1Contents$SignalV1Contents(
  signal_type: string,
  content: $dynamic.Dynamic$,
): SignalV1Contents$;
export function SignalV1Contents$isSignalV1Contents(
  value: any,
): value is SignalV1Contents$;
export function SignalV1Contents$SignalV1Contents$0(value: SignalV1Contents$): string;
export function SignalV1Contents$SignalV1Contents$signal_type(
  value: SignalV1Contents$,
): string;
export function SignalV1Contents$SignalV1Contents$1(value: SignalV1Contents$): $dynamic.Dynamic$;
export function SignalV1Contents$SignalV1Contents$content(
  value: SignalV1Contents$,
): $dynamic.Dynamic$;

export type SignalV1Contents$ = SignalV1Contents;

export class NormalizedSignal extends _.CustomType {
  /** @deprecated */
  constructor(
    content: $dynamic.Dynamic$,
    signal_type: $option.Option$<string>,
    client_connection_number: $option.Option$<number>,
    reference_sequence_number: $option.Option$<number>,
    target_client_id: $option.Option$<string>,
    targeted_clients: $option.Option$<_.List<string>>,
    ignored_clients: $option.Option$<_.List<string>>
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
  /** @deprecated */
  targeted_clients: $option.Option$<_.List<string>>;
  /** @deprecated */
  ignored_clients: $option.Option$<_.List<string>>;
}
export function NormalizedSignal$NormalizedSignal(
  content: $dynamic.Dynamic$,
  signal_type: $option.Option$<string>,
  client_connection_number: $option.Option$<number>,
  reference_sequence_number: $option.Option$<number>,
  target_client_id: $option.Option$<string>,
  targeted_clients: $option.Option$<_.List<string>>,
  ignored_clients: $option.Option$<_.List<string>>,
): NormalizedSignal$;
export function NormalizedSignal$isNormalizedSignal(
  value: any,
): value is NormalizedSignal$;
export function NormalizedSignal$NormalizedSignal$0(value: NormalizedSignal$): $dynamic.Dynamic$;
export function NormalizedSignal$NormalizedSignal$content(
  value: NormalizedSignal$,
): $dynamic.Dynamic$;
export function NormalizedSignal$NormalizedSignal$1(value: NormalizedSignal$): $option.Option$<
  string
>;
export function NormalizedSignal$NormalizedSignal$signal_type(value: NormalizedSignal$): $option.Option$<
  string
>;
export function NormalizedSignal$NormalizedSignal$2(value: NormalizedSignal$): $option.Option$<
  number
>;
export function NormalizedSignal$NormalizedSignal$client_connection_number(value: NormalizedSignal$): $option.Option$<
  number
>;
export function NormalizedSignal$NormalizedSignal$3(value: NormalizedSignal$): $option.Option$<
  number
>;
export function NormalizedSignal$NormalizedSignal$reference_sequence_number(value: NormalizedSignal$): $option.Option$<
  number
>;
export function NormalizedSignal$NormalizedSignal$4(value: NormalizedSignal$): $option.Option$<
  string
>;
export function NormalizedSignal$NormalizedSignal$target_client_id(value: NormalizedSignal$): $option.Option$<
  string
>;
export function NormalizedSignal$NormalizedSignal$5(value: NormalizedSignal$): $option.Option$<
  _.List<string>
>;
export function NormalizedSignal$NormalizedSignal$targeted_clients(value: NormalizedSignal$): $option.Option$<
  _.List<string>
>;
export function NormalizedSignal$NormalizedSignal$6(value: NormalizedSignal$): $option.Option$<
  _.List<string>
>;
export function NormalizedSignal$NormalizedSignal$ignored_clients(value: NormalizedSignal$): $option.Option$<
  _.List<string>
>;

export type NormalizedSignal$ = NormalizedSignal;

export class SignalV2 extends _.CustomType {
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
export function SignalV2$SignalV2(
  content: $dynamic.Dynamic$,
  signal_type: $option.Option$<string>,
  client_connection_number: $option.Option$<number>,
  reference_sequence_number: $option.Option$<number>,
  target_client_id: $option.Option$<string>,
): SignalV2$;
export function SignalV2$isSignalV2(value: any): value is SignalV2$;
export function SignalV2$SignalV2$0(value: SignalV2$): $dynamic.Dynamic$;
export function SignalV2$SignalV2$content(value: SignalV2$): $dynamic.Dynamic$;
export function SignalV2$SignalV2$1(value: SignalV2$): $option.Option$<string>;
export function SignalV2$SignalV2$signal_type(value: SignalV2$): $option.Option$<
  string
>;
export function SignalV2$SignalV2$2(value: SignalV2$): $option.Option$<number>;
export function SignalV2$SignalV2$client_connection_number(value: SignalV2$): $option.Option$<
  number
>;
export function SignalV2$SignalV2$3(value: SignalV2$): $option.Option$<number>;
export function SignalV2$SignalV2$reference_sequence_number(value: SignalV2$): $option.Option$<
  number
>;
export function SignalV2$SignalV2$4(value: SignalV2$): $option.Option$<string>;
export function SignalV2$SignalV2$target_client_id(value: SignalV2$): $option.Option$<
  string
>;

export type SignalV2$ = SignalV2;

export class ClientBroadcastSignalEnvelope extends _.CustomType {
  /** @deprecated */
  constructor(
    signal: SignalV2$,
    targeted_clients: $option.Option$<_.List<string>>,
    ignored_clients: $option.Option$<_.List<string>>
  );
  /** @deprecated */
  signal: SignalV2$;
  /** @deprecated */
  targeted_clients: $option.Option$<_.List<string>>;
  /** @deprecated */
  ignored_clients: $option.Option$<_.List<string>>;
}
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope(
  signal: SignalV2$,
  targeted_clients: $option.Option$<_.List<string>>,
  ignored_clients: $option.Option$<_.List<string>>,
): ClientBroadcastSignalEnvelope$;
export function ClientBroadcastSignalEnvelope$isClientBroadcastSignalEnvelope(
  value: any,
): value is ClientBroadcastSignalEnvelope$;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$0(value: ClientBroadcastSignalEnvelope$): SignalV2$;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$signal(
  value: ClientBroadcastSignalEnvelope$,
): SignalV2$;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$1(value: ClientBroadcastSignalEnvelope$): $option.Option$<
  _.List<string>
>;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$targeted_clients(value: ClientBroadcastSignalEnvelope$): $option.Option$<
  _.List<string>
>;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$2(value: ClientBroadcastSignalEnvelope$): $option.Option$<
  _.List<string>
>;
export function ClientBroadcastSignalEnvelope$ClientBroadcastSignalEnvelope$ignored_clients(value: ClientBroadcastSignalEnvelope$): $option.Option$<
  _.List<string>
>;

export type ClientBroadcastSignalEnvelope$ = ClientBroadcastSignalEnvelope;

export class InvalidFormat extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function SignalParseError$InvalidFormat($0: string): SignalParseError$;
export function SignalParseError$isInvalidFormat(
  value: any,
): value is SignalParseError$;
export function SignalParseError$InvalidFormat$0(value: SignalParseError$): string;

export class MissingField extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function SignalParseError$MissingField($0: string): SignalParseError$;
export function SignalParseError$isMissingField(
  value: any,
): value is SignalParseError$;
export function SignalParseError$MissingField$0(value: SignalParseError$): string;

export type SignalParseError$ = InvalidFormat | MissingField;

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

export class V1Format extends _.CustomType {}
export function SignalVersion$V1Format(): SignalVersion$;
export function SignalVersion$isV1Format(value: any): value is SignalVersion$;

export class V2Format extends _.CustomType {}
export function SignalVersion$V2Format(): SignalVersion$;
export function SignalVersion$isV2Format(value: any): value is SignalVersion$;

export class UnknownFormat extends _.CustomType {}
export function SignalVersion$UnknownFormat(): SignalVersion$;
export function SignalVersion$isUnknownFormat(
  value: any,
): value is SignalVersion$;

export type SignalVersion$ = V1Format | V2Format | UnknownFormat;

export function client_join_signal(client_id: string, client: $types.Client$): SystemSignal$;

export function client_leave_signal(client_id: string): SystemSignal$;

export function parse_v1_envelope_from_map(
  raw: $dict.Dict$<string, $dynamic.Dynamic$>
): _.Result<SignalV1Envelope$, SignalParseError$>;

export function normalize_signal(raw: $dict.Dict$<string, $dynamic.Dynamic$>): NormalizedSignal$;

export function normalize_signal_batch(batch: $dynamic.Dynamic$): _.List<
  NormalizedSignal$
>;

export function normalized_to_map(s: NormalizedSignal$): $dict.Dict$<
  string,
  $dynamic.Dynamic$
>;

export function is_targeted(signal: SignalV2$): boolean;

export function should_receive(signal: SignalV2$, client_id: string): boolean;

export function get_signal_recipients(
  envelope: ClientBroadcastSignalEnvelope$,
  all_clients: _.List<string>,
  sender_client_id: string
): _.List<string>;

export function should_client_receive_signal(
  envelope: ClientBroadcastSignalEnvelope$,
  client_id: string,
  sender_client_id: string
): boolean;

export function broadcast(
  content: $dynamic.Dynamic$,
  signal_type: $option.Option$<string>,
  connection_number: $option.Option$<number>,
  rsn: $option.Option$<number>
): SignalV2$;

export function targeted(
  content: $dynamic.Dynamic$,
  target_client_id: string,
  signal_type: $option.Option$<string>,
  connection_number: $option.Option$<number>,
  rsn: $option.Option$<number>
): SignalV2$;

export function broadcast_envelope(signal: SignalV2$): ClientBroadcastSignalEnvelope$;

export function targeted_envelope(signal: SignalV2$, targets: _.List<string>): ClientBroadcastSignalEnvelope$;

export function ignored_envelope(signal: SignalV2$, ignored: _.List<string>): ClientBroadcastSignalEnvelope$;

export function signal_message_from_v2(
  sender_client_id: string,
  signal: SignalV2$
): SignalMessage$;

export function system_signal_message(
  content: $dynamic.Dynamic$,
  signal_type: string
): SignalMessage$;

export function detect_signal_version(
  has_address: boolean,
  has_targeted_clients: boolean,
  has_ignored_clients: boolean
): SignalVersion$;
