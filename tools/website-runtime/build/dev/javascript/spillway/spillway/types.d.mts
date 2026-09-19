import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $types from "../../signet/signet/types.d.mts";
import type * as _ from "../gleam.d.mts";

export class WriteMode extends _.CustomType {}
export function ConnectionMode$WriteMode(): ConnectionMode$;
export function ConnectionMode$isWriteMode(
  value: any,
): value is ConnectionMode$;

export class ReadMode extends _.CustomType {}
export function ConnectionMode$ReadMode(): ConnectionMode$;
export function ConnectionMode$isReadMode(value: any): value is ConnectionMode$;

export type ConnectionMode$ = WriteMode | ReadMode;

export class ClientCapabilities extends _.CustomType {
  /** @deprecated */
  constructor(interactive: boolean);
  /** @deprecated */
  interactive: boolean;
}
export function ClientCapabilities$ClientCapabilities(
  interactive: boolean,
): ClientCapabilities$;
export function ClientCapabilities$isClientCapabilities(
  value: any,
): value is ClientCapabilities$;
export function ClientCapabilities$ClientCapabilities$0(value: ClientCapabilities$): boolean;
export function ClientCapabilities$ClientCapabilities$interactive(
  value: ClientCapabilities$,
): boolean;

export type ClientCapabilities$ = ClientCapabilities;

export class ClientDetails extends _.CustomType {
  /** @deprecated */
  constructor(
    capabilities: ClientCapabilities$,
    client_type: $option.Option$<string>,
    environment: $option.Option$<string>,
    device: $option.Option$<string>
  );
  /** @deprecated */
  capabilities: ClientCapabilities$;
  /** @deprecated */
  client_type: $option.Option$<string>;
  /** @deprecated */
  environment: $option.Option$<string>;
  /** @deprecated */
  device: $option.Option$<string>;
}
export function ClientDetails$ClientDetails(
  capabilities: ClientCapabilities$,
  client_type: $option.Option$<string>,
  environment: $option.Option$<string>,
  device: $option.Option$<string>,
): ClientDetails$;
export function ClientDetails$isClientDetails(
  value: any,
): value is ClientDetails$;
export function ClientDetails$ClientDetails$0(value: ClientDetails$): ClientCapabilities$;
export function ClientDetails$ClientDetails$capabilities(
  value: ClientDetails$,
): ClientCapabilities$;
export function ClientDetails$ClientDetails$1(value: ClientDetails$): $option.Option$<
  string
>;
export function ClientDetails$ClientDetails$client_type(value: ClientDetails$): $option.Option$<
  string
>;
export function ClientDetails$ClientDetails$2(value: ClientDetails$): $option.Option$<
  string
>;
export function ClientDetails$ClientDetails$environment(value: ClientDetails$): $option.Option$<
  string
>;
export function ClientDetails$ClientDetails$3(value: ClientDetails$): $option.Option$<
  string
>;
export function ClientDetails$ClientDetails$device(value: ClientDetails$): $option.Option$<
  string
>;

export type ClientDetails$ = ClientDetails;

export class Client extends _.CustomType {
  /** @deprecated */
  constructor(
    mode: ConnectionMode$,
    details: ClientDetails$,
    permission: _.List<string>,
    user: $token.User$,
    scopes: _.List<string>,
    timestamp: $option.Option$<number>
  );
  /** @deprecated */
  mode: ConnectionMode$;
  /** @deprecated */
  details: ClientDetails$;
  /** @deprecated */
  permission: _.List<string>;
  /** @deprecated */
  user: $token.User$;
  /** @deprecated */
  scopes: _.List<string>;
  /** @deprecated */
  timestamp: $option.Option$<number>;
}
export function Client$Client(
  mode: ConnectionMode$,
  details: ClientDetails$,
  permission: _.List<string>,
  user: $token.User$,
  scopes: _.List<string>,
  timestamp: $option.Option$<number>,
): Client$;
export function Client$isClient(value: any): value is Client$;
export function Client$Client$0(value: Client$): ConnectionMode$;
export function Client$Client$mode(value: Client$): ConnectionMode$;
export function Client$Client$1(value: Client$): ClientDetails$;
export function Client$Client$details(value: Client$): ClientDetails$;
export function Client$Client$2(value: Client$): _.List<string>;
export function Client$Client$permission(value: Client$): _.List<string>;
export function Client$Client$3(value: Client$): $token.User$;
export function Client$Client$user(value: Client$): $token.User$;
export function Client$Client$4(value: Client$): _.List<string>;
export function Client$Client$scopes(value: Client$): _.List<string>;
export function Client$Client$5(value: Client$): $option.Option$<number>;
export function Client$Client$timestamp(value: Client$): $option.Option$<number>;

export type Client$ = Client;

export class SequencedClient extends _.CustomType {
  /** @deprecated */
  constructor(client: Client$, sequence_number: number);
  /** @deprecated */
  client: Client$;
  /** @deprecated */
  sequence_number: number;
}
export function SequencedClient$SequencedClient(
  client: Client$,
  sequence_number: number,
): SequencedClient$;
export function SequencedClient$isSequencedClient(
  value: any,
): value is SequencedClient$;
export function SequencedClient$SequencedClient$0(value: SequencedClient$): Client$;
export function SequencedClient$SequencedClient$client(
  value: SequencedClient$,
): Client$;
export function SequencedClient$SequencedClient$1(value: SequencedClient$): number;
export function SequencedClient$SequencedClient$sequence_number(
  value: SequencedClient$,
): number;

export type SequencedClient$ = SequencedClient;

export class SignalClient extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    client: Client$,
    client_connection_number: $option.Option$<number>,
    reference_sequence_number: $option.Option$<number>
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  client: Client$;
  /** @deprecated */
  client_connection_number: $option.Option$<number>;
  /** @deprecated */
  reference_sequence_number: $option.Option$<number>;
}
export function SignalClient$SignalClient(
  client_id: string,
  client: Client$,
  client_connection_number: $option.Option$<number>,
  reference_sequence_number: $option.Option$<number>,
): SignalClient$;
export function SignalClient$isSignalClient(value: any): value is SignalClient$;
export function SignalClient$SignalClient$0(value: SignalClient$): string;
export function SignalClient$SignalClient$client_id(value: SignalClient$): string;
export function SignalClient$SignalClient$1(
  value: SignalClient$,
): Client$;
export function SignalClient$SignalClient$client(value: SignalClient$): Client$;
export function SignalClient$SignalClient$2(value: SignalClient$): $option.Option$<
  number
>;
export function SignalClient$SignalClient$client_connection_number(value: SignalClient$): $option.Option$<
  number
>;
export function SignalClient$SignalClient$3(value: SignalClient$): $option.Option$<
  number
>;
export function SignalClient$SignalClient$reference_sequence_number(value: SignalClient$): $option.Option$<
  number
>;

export type SignalClient$ = SignalClient;

export class ServiceConfiguration extends _.CustomType {
  /** @deprecated */
  constructor(
    block_size: number,
    max_message_size: number,
    noop_time_frequency: $option.Option$<number>,
    noop_count_frequency: $option.Option$<number>
  );
  /** @deprecated */
  block_size: number;
  /** @deprecated */
  max_message_size: number;
  /** @deprecated */
  noop_time_frequency: $option.Option$<number>;
  /** @deprecated */
  noop_count_frequency: $option.Option$<number>;
}
export function ServiceConfiguration$ServiceConfiguration(
  block_size: number,
  max_message_size: number,
  noop_time_frequency: $option.Option$<number>,
  noop_count_frequency: $option.Option$<number>,
): ServiceConfiguration$;
export function ServiceConfiguration$isServiceConfiguration(
  value: any,
): value is ServiceConfiguration$;
export function ServiceConfiguration$ServiceConfiguration$0(value: ServiceConfiguration$): number;
export function ServiceConfiguration$ServiceConfiguration$block_size(
  value: ServiceConfiguration$,
): number;
export function ServiceConfiguration$ServiceConfiguration$1(value: ServiceConfiguration$): number;
export function ServiceConfiguration$ServiceConfiguration$max_message_size(
  value: ServiceConfiguration$,
): number;
export function ServiceConfiguration$ServiceConfiguration$2(value: ServiceConfiguration$): $option.Option$<
  number
>;
export function ServiceConfiguration$ServiceConfiguration$noop_time_frequency(value: ServiceConfiguration$): $option.Option$<
  number
>;
export function ServiceConfiguration$ServiceConfiguration$3(value: ServiceConfiguration$): $option.Option$<
  number
>;
export function ServiceConfiguration$ServiceConfiguration$noop_count_frequency(value: ServiceConfiguration$): $option.Option$<
  number
>;

export type ServiceConfiguration$ = ServiceConfiguration;

export class Trace extends _.CustomType {
  /** @deprecated */
  constructor(service: string, action: string, timestamp: number);
  /** @deprecated */
  service: string;
  /** @deprecated */
  action: string;
  /** @deprecated */
  timestamp: number;
}
export function Trace$Trace(
  service: string,
  action: string,
  timestamp: number,
): Trace$;
export function Trace$isTrace(value: any): value is Trace$;
export function Trace$Trace$0(value: Trace$): string;
export function Trace$Trace$service(value: Trace$): string;
export function Trace$Trace$1(value: Trace$): string;
export function Trace$Trace$action(value: Trace$): string;
export function Trace$Trace$2(value: Trace$): number;
export function Trace$Trace$timestamp(value: Trace$): number;

export type Trace$ = Trace;

export class DocumentMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    client_sequence_number: number,
    reference_sequence_number: number,
    message_type: string,
    contents: $dynamic.Dynamic$,
    metadata: $option.Option$<$dynamic.Dynamic$>,
    server_metadata: $option.Option$<$dynamic.Dynamic$>,
    traces: $option.Option$<_.List<Trace$>>,
    compression: $option.Option$<string>
  );
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  message_type: string;
  /** @deprecated */
  contents: $dynamic.Dynamic$;
  /** @deprecated */
  metadata: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  server_metadata: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  traces: $option.Option$<_.List<Trace$>>;
  /** @deprecated */
  compression: $option.Option$<string>;
}
export function DocumentMessage$DocumentMessage(
  client_sequence_number: number,
  reference_sequence_number: number,
  message_type: string,
  contents: $dynamic.Dynamic$,
  metadata: $option.Option$<$dynamic.Dynamic$>,
  server_metadata: $option.Option$<$dynamic.Dynamic$>,
  traces: $option.Option$<_.List<Trace$>>,
  compression: $option.Option$<string>,
): DocumentMessage$;
export function DocumentMessage$isDocumentMessage(
  value: any,
): value is DocumentMessage$;
export function DocumentMessage$DocumentMessage$0(value: DocumentMessage$): number;
export function DocumentMessage$DocumentMessage$client_sequence_number(
  value: DocumentMessage$,
): number;
export function DocumentMessage$DocumentMessage$1(value: DocumentMessage$): number;
export function DocumentMessage$DocumentMessage$reference_sequence_number(
  value: DocumentMessage$,
): number;
export function DocumentMessage$DocumentMessage$2(value: DocumentMessage$): string;
export function DocumentMessage$DocumentMessage$message_type(
  value: DocumentMessage$,
): string;
export function DocumentMessage$DocumentMessage$3(value: DocumentMessage$): $dynamic.Dynamic$;
export function DocumentMessage$DocumentMessage$contents(
  value: DocumentMessage$,
): $dynamic.Dynamic$;
export function DocumentMessage$DocumentMessage$4(value: DocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function DocumentMessage$DocumentMessage$metadata(value: DocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function DocumentMessage$DocumentMessage$5(value: DocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function DocumentMessage$DocumentMessage$server_metadata(value: DocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function DocumentMessage$DocumentMessage$6(value: DocumentMessage$): $option.Option$<
  _.List<Trace$>
>;
export function DocumentMessage$DocumentMessage$traces(value: DocumentMessage$): $option.Option$<
  _.List<Trace$>
>;
export function DocumentMessage$DocumentMessage$7(value: DocumentMessage$): $option.Option$<
  string
>;
export function DocumentMessage$DocumentMessage$compression(value: DocumentMessage$): $option.Option$<
  string
>;

export type DocumentMessage$ = DocumentMessage;

export class SequencedDocumentMessage extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: $option.Option$<string>,
    sequence_number: number,
    minimum_sequence_number: number,
    client_sequence_number: number,
    reference_sequence_number: number,
    message_type: string,
    contents: $dynamic.Dynamic$,
    metadata: $option.Option$<$dynamic.Dynamic$>,
    server_metadata: $option.Option$<$dynamic.Dynamic$>,
    origin: $option.Option$<MessageOrigin$>,
    traces: $option.Option$<_.List<Trace$>>,
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
  message_type: string;
  /** @deprecated */
  contents: $dynamic.Dynamic$;
  /** @deprecated */
  metadata: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  server_metadata: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  origin: $option.Option$<MessageOrigin$>;
  /** @deprecated */
  traces: $option.Option$<_.List<Trace$>>;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  data: $option.Option$<string>;
}
export function SequencedDocumentMessage$SequencedDocumentMessage(
  client_id: $option.Option$<string>,
  sequence_number: number,
  minimum_sequence_number: number,
  client_sequence_number: number,
  reference_sequence_number: number,
  message_type: string,
  contents: $dynamic.Dynamic$,
  metadata: $option.Option$<$dynamic.Dynamic$>,
  server_metadata: $option.Option$<$dynamic.Dynamic$>,
  origin: $option.Option$<MessageOrigin$>,
  traces: $option.Option$<_.List<Trace$>>,
  timestamp: number,
  data: $option.Option$<string>,
): SequencedDocumentMessage$;
export function SequencedDocumentMessage$isSequencedDocumentMessage(
  value: any,
): value is SequencedDocumentMessage$;
export function SequencedDocumentMessage$SequencedDocumentMessage$0(value: SequencedDocumentMessage$): $option.Option$<
  string
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$client_id(value: SequencedDocumentMessage$): $option.Option$<
  string
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$1(value: SequencedDocumentMessage$): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$sequence_number(
  value: SequencedDocumentMessage$,
): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$2(value: SequencedDocumentMessage$): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$minimum_sequence_number(
  value: SequencedDocumentMessage$,
): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$3(value: SequencedDocumentMessage$): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$client_sequence_number(
  value: SequencedDocumentMessage$,
): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$4(value: SequencedDocumentMessage$): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$reference_sequence_number(
  value: SequencedDocumentMessage$,
): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$5(value: SequencedDocumentMessage$): string;
export function SequencedDocumentMessage$SequencedDocumentMessage$message_type(
  value: SequencedDocumentMessage$,
): string;
export function SequencedDocumentMessage$SequencedDocumentMessage$6(value: SequencedDocumentMessage$): $dynamic.Dynamic$;
export function SequencedDocumentMessage$SequencedDocumentMessage$contents(
  value: SequencedDocumentMessage$,
): $dynamic.Dynamic$;
export function SequencedDocumentMessage$SequencedDocumentMessage$7(value: SequencedDocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$metadata(value: SequencedDocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$8(value: SequencedDocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$server_metadata(value: SequencedDocumentMessage$): $option.Option$<
  $dynamic.Dynamic$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$9(value: SequencedDocumentMessage$): $option.Option$<
  MessageOrigin$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$origin(value: SequencedDocumentMessage$): $option.Option$<
  MessageOrigin$
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$10(value: SequencedDocumentMessage$): $option.Option$<
  _.List<Trace$>
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$traces(value: SequencedDocumentMessage$): $option.Option$<
  _.List<Trace$>
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$11(value: SequencedDocumentMessage$): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$timestamp(
  value: SequencedDocumentMessage$,
): number;
export function SequencedDocumentMessage$SequencedDocumentMessage$12(value: SequencedDocumentMessage$): $option.Option$<
  string
>;
export function SequencedDocumentMessage$SequencedDocumentMessage$data(value: SequencedDocumentMessage$): $option.Option$<
  string
>;

export type SequencedDocumentMessage$ = SequencedDocumentMessage;

export class MessageOrigin extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    sequence_number: number,
    minimum_sequence_number: number
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  minimum_sequence_number: number;
}
export function MessageOrigin$MessageOrigin(
  id: string,
  sequence_number: number,
  minimum_sequence_number: number,
): MessageOrigin$;
export function MessageOrigin$isMessageOrigin(
  value: any,
): value is MessageOrigin$;
export function MessageOrigin$MessageOrigin$0(value: MessageOrigin$): string;
export function MessageOrigin$MessageOrigin$id(value: MessageOrigin$): string;
export function MessageOrigin$MessageOrigin$1(value: MessageOrigin$): number;
export function MessageOrigin$MessageOrigin$sequence_number(value: MessageOrigin$): number;
export function MessageOrigin$MessageOrigin$2(
  value: MessageOrigin$,
): number;
export function MessageOrigin$MessageOrigin$minimum_sequence_number(value: MessageOrigin$): number;

export type MessageOrigin$ = MessageOrigin;

export type User = $token.User$;

export type TokenClaims = $token.TokenClaims$;

export type Scope = $token.Scope$;

export function scope_to_string(scope: $token.Scope$): string;

export function scope_from_string(value: string): _.Result<
  $token.Scope$,
  undefined
>;
