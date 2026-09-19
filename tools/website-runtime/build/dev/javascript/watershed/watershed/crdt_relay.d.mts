import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";

export class Connected extends _.CustomType {
  /** @deprecated */
  constructor(supports: boolean, envelope_bytes: number);
  /** @deprecated */
  supports: boolean;
  /** @deprecated */
  envelope_bytes: number;
}
export function ServerFrame$Connected(
  supports: boolean,
  envelope_bytes: number,
): ServerFrame$;
export function ServerFrame$isConnected(value: any): value is ServerFrame$;
export function ServerFrame$Connected$0(value: ServerFrame$): boolean;
export function ServerFrame$Connected$supports(value: ServerFrame$): boolean;
export function ServerFrame$Connected$1(value: ServerFrame$): number;
export function ServerFrame$Connected$envelope_bytes(value: ServerFrame$): number;

export class Frame extends _.CustomType {
  /** @deprecated */
  constructor(order: number, envelope: string);
  /** @deprecated */
  order: number;
  /** @deprecated */
  envelope: string;
}
export function ServerFrame$Frame(
  order: number,
  envelope: string,
): ServerFrame$;
export function ServerFrame$isFrame(value: any): value is ServerFrame$;
export function ServerFrame$Frame$0(value: ServerFrame$): number;
export function ServerFrame$Frame$order(value: ServerFrame$): number;
export function ServerFrame$Frame$1(value: ServerFrame$): string;
export function ServerFrame$Frame$envelope(value: ServerFrame$): string;

export class Synced extends _.CustomType {
  /** @deprecated */
  constructor(order: number);
  /** @deprecated */
  order: number;
}
export function ServerFrame$Synced(order: number): ServerFrame$;
export function ServerFrame$isSynced(value: any): value is ServerFrame$;
export function ServerFrame$Synced$0(value: ServerFrame$): number;
export function ServerFrame$Synced$order(value: ServerFrame$): number;

export class Attested extends _.CustomType {
  /** @deprecated */
  constructor(order: number, digest: string);
  /** @deprecated */
  order: number;
  /** @deprecated */
  digest: string;
}
export function ServerFrame$Attested(
  order: number,
  digest: string,
): ServerFrame$;
export function ServerFrame$isAttested(value: any): value is ServerFrame$;
export function ServerFrame$Attested$0(value: ServerFrame$): number;
export function ServerFrame$Attested$order(value: ServerFrame$): number;
export function ServerFrame$Attested$1(value: ServerFrame$): string;
export function ServerFrame$Attested$digest(value: ServerFrame$): string;

export class CheckpointRequest extends _.CustomType {}
export function ServerFrame$CheckpointRequest(): ServerFrame$;
export function ServerFrame$isCheckpointRequest(
  value: any,
): value is ServerFrame$;

export class Refused extends _.CustomType {
  /** @deprecated */
  constructor(reason: string, detail: string);
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}
export function ServerFrame$Refused(
  reason: string,
  detail: string,
): ServerFrame$;
export function ServerFrame$isRefused(value: any): value is ServerFrame$;
export function ServerFrame$Refused$0(value: ServerFrame$): string;
export function ServerFrame$Refused$reason(value: ServerFrame$): string;
export function ServerFrame$Refused$1(value: ServerFrame$): string;
export function ServerFrame$Refused$detail(value: ServerFrame$): string;

export type ServerFrame$ = Connected | Frame | Synced | Attested | CheckpointRequest | Refused;

export class Attest extends _.CustomType {
  /** @deprecated */
  constructor(digest: string, up_to: number);
  /** @deprecated */
  digest: string;
  /** @deprecated */
  up_to: number;
}
export function ControlFrame$Attest(
  digest: string,
  up_to: number,
): ControlFrame$;
export function ControlFrame$isAttest(value: any): value is ControlFrame$;
export function ControlFrame$Attest$0(value: ControlFrame$): string;
export function ControlFrame$Attest$digest(value: ControlFrame$): string;
export function ControlFrame$Attest$1(value: ControlFrame$): number;
export function ControlFrame$Attest$up_to(value: ControlFrame$): number;

export class Skip extends _.CustomType {
  /** @deprecated */
  constructor(order: number);
  /** @deprecated */
  order: number;
}
export function ControlFrame$Skip(order: number): ControlFrame$;
export function ControlFrame$isSkip(value: any): value is ControlFrame$;
export function ControlFrame$Skip$0(value: ControlFrame$): number;
export function ControlFrame$Skip$order(value: ControlFrame$): number;

export class Supports extends _.CustomType {
  /** @deprecated */
  constructor(checkpoint_requests: boolean);
  /** @deprecated */
  checkpoint_requests: boolean;
}
export function ControlFrame$Supports(
  checkpoint_requests: boolean,
): ControlFrame$;
export function ControlFrame$isSupports(value: any): value is ControlFrame$;
export function ControlFrame$Supports$0(value: ControlFrame$): boolean;
export function ControlFrame$Supports$checkpoint_requests(value: ControlFrame$): boolean;

export type ControlFrame$ = Attest | Skip | Supports;

export class Document extends _.CustomType {
  /** @deprecated */
  constructor(
    raw: string,
    room: string,
    from: string,
    session: string,
    message: MessageKind$
  );
  /** @deprecated */
  raw: string;
  /** @deprecated */
  room: string;
  /** @deprecated */
  from: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  message: MessageKind$;
}
export function ClientFrame$Document(
  raw: string,
  room: string,
  from: string,
  session: string,
  message: MessageKind$,
): ClientFrame$;
export function ClientFrame$isDocument(value: any): value is ClientFrame$;
export function ClientFrame$Document$0(value: ClientFrame$): string;
export function ClientFrame$Document$raw(value: ClientFrame$): string;
export function ClientFrame$Document$1(value: ClientFrame$): string;
export function ClientFrame$Document$room(value: ClientFrame$): string;
export function ClientFrame$Document$2(value: ClientFrame$): string;
export function ClientFrame$Document$from(value: ClientFrame$): string;
export function ClientFrame$Document$3(value: ClientFrame$): string;
export function ClientFrame$Document$session(value: ClientFrame$): string;
export function ClientFrame$Document$4(value: ClientFrame$): MessageKind$;
export function ClientFrame$Document$message(value: ClientFrame$): MessageKind$;

export class Control extends _.CustomType {
  /** @deprecated */
  constructor(frame: ControlFrame$);
  /** @deprecated */
  frame: ControlFrame$;
}
export function ClientFrame$Control(frame: ControlFrame$): ClientFrame$;
export function ClientFrame$isControl(value: any): value is ClientFrame$;
export function ClientFrame$Control$0(value: ClientFrame$): ControlFrame$;
export function ClientFrame$Control$frame(value: ClientFrame$): ControlFrame$;

export type ClientFrame$ = Document | Control;

export class HelloMessage extends _.CustomType {}
export function MessageKind$HelloMessage(): MessageKind$;
export function MessageKind$isHelloMessage(value: any): value is MessageKind$;

export class ChannelMessage extends _.CustomType {}
export function MessageKind$ChannelMessage(): MessageKind$;
export function MessageKind$isChannelMessage(value: any): value is MessageKind$;

export class DeltaMessage extends _.CustomType {}
export function MessageKind$DeltaMessage(): MessageKind$;
export function MessageKind$isDeltaMessage(value: any): value is MessageKind$;

export class StateRequestMessage extends _.CustomType {}
export function MessageKind$StateRequestMessage(): MessageKind$;
export function MessageKind$isStateRequestMessage(
  value: any,
): value is MessageKind$;

export class StateMessage extends _.CustomType {}
export function MessageKind$StateMessage(): MessageKind$;
export function MessageKind$isStateMessage(value: any): value is MessageKind$;

export class DigestMessage extends _.CustomType {}
export function MessageKind$DigestMessage(): MessageKind$;
export function MessageKind$isDigestMessage(value: any): value is MessageKind$;

export type MessageKind$ = HelloMessage | ChannelMessage | DeltaMessage | StateRequestMessage | StateMessage | DigestMessage;

export class FrameTooLarge extends _.CustomType {
  /** @deprecated */
  constructor(bytes: number);
  /** @deprecated */
  bytes: number;
}
export function Refusal$FrameTooLarge(bytes: number): Refusal$;
export function Refusal$isFrameTooLarge(value: any): value is Refusal$;
export function Refusal$FrameTooLarge$0(value: Refusal$): number;
export function Refusal$FrameTooLarge$bytes(value: Refusal$): number;

export class Malformed extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Refusal$Malformed(detail: string): Refusal$;
export function Refusal$isMalformed(value: any): value is Refusal$;
export function Refusal$Malformed$0(value: Refusal$): string;
export function Refusal$Malformed$detail(value: Refusal$): string;

export class UnsupportedMessage extends _.CustomType {
  /** @deprecated */
  constructor(tag: string);
  /** @deprecated */
  tag: string;
}
export function Refusal$UnsupportedMessage(tag: string): Refusal$;
export function Refusal$isUnsupportedMessage(value: any): value is Refusal$;
export function Refusal$UnsupportedMessage$0(value: Refusal$): string;
export function Refusal$UnsupportedMessage$tag(value: Refusal$): string;

export class NotAdmitted extends _.CustomType {}
export function Refusal$NotAdmitted(): Refusal$;
export function Refusal$isNotAdmitted(value: any): value is Refusal$;

export class InvalidRoom extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Refusal$InvalidRoom(detail: string): Refusal$;
export function Refusal$isInvalidRoom(value: any): value is Refusal$;
export function Refusal$InvalidRoom$0(value: Refusal$): string;
export function Refusal$InvalidRoom$detail(value: Refusal$): string;

export class RoomFull extends _.CustomType {
  /** @deprecated */
  constructor(limit: number);
  /** @deprecated */
  limit: number;
}
export function Refusal$RoomFull(limit: number): Refusal$;
export function Refusal$isRoomFull(value: any): value is Refusal$;
export function Refusal$RoomFull$0(value: Refusal$): number;
export function Refusal$RoomFull$limit(value: Refusal$): number;

export class IdentityChanged extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Refusal$IdentityChanged(detail: string): Refusal$;
export function Refusal$isIdentityChanged(value: any): value is Refusal$;
export function Refusal$IdentityChanged$0(value: Refusal$): string;
export function Refusal$IdentityChanged$detail(value: Refusal$): string;

export class DuplicateSession extends _.CustomType {
  /** @deprecated */
  constructor(session: string);
  /** @deprecated */
  session: string;
}
export function Refusal$DuplicateSession(session: string): Refusal$;
export function Refusal$isDuplicateSession(value: any): value is Refusal$;
export function Refusal$DuplicateSession$0(value: Refusal$): string;
export function Refusal$DuplicateSession$session(value: Refusal$): string;

export class TooManySkips extends _.CustomType {
  /** @deprecated */
  constructor(limit: number);
  /** @deprecated */
  limit: number;
}
export function Refusal$TooManySkips(limit: number): Refusal$;
export function Refusal$isTooManySkips(value: any): value is Refusal$;
export function Refusal$TooManySkips$0(value: Refusal$): number;
export function Refusal$TooManySkips$limit(value: Refusal$): number;

export class RoomAtCapacity extends _.CustomType {
  /** @deprecated */
  constructor(limit: number);
  /** @deprecated */
  limit: number;
}
export function Refusal$RoomAtCapacity(limit: number): Refusal$;
export function Refusal$isRoomAtCapacity(value: any): value is Refusal$;
export function Refusal$RoomAtCapacity$0(value: Refusal$): number;
export function Refusal$RoomAtCapacity$limit(value: Refusal$): number;

export type Refusal$ = FrameTooLarge | Malformed | UnsupportedMessage | NotAdmitted | InvalidRoom | RoomFull | IdentityChanged | DuplicateSession | TooManySkips | RoomAtCapacity;

export class Send extends _.CustomType {
  /** @deprecated */
  constructor(connection: number, frame: ServerFrame$);
  /** @deprecated */
  connection: number;
  /** @deprecated */
  frame: ServerFrame$;
}
export function Action$Send(connection: number, frame: ServerFrame$): Action$;
export function Action$isSend(value: any): value is Action$;
export function Action$Send$0(value: Action$): number;
export function Action$Send$connection(value: Action$): number;
export function Action$Send$1(value: Action$): ServerFrame$;
export function Action$Send$frame(value: Action$): ServerFrame$;

export class Close extends _.CustomType {
  /** @deprecated */
  constructor(connection: number, reason: string);
  /** @deprecated */
  connection: number;
  /** @deprecated */
  reason: string;
}
export function Action$Close(connection: number, reason: string): Action$;
export function Action$isClose(value: any): value is Action$;
export function Action$Close$0(value: Action$): number;
export function Action$Close$connection(value: Action$): number;
export function Action$Close$1(value: Action$): string;
export function Action$Close$reason(value: Action$): string;

export class Append extends _.CustomType {
  /** @deprecated */
  constructor(room: string, line: string);
  /** @deprecated */
  room: string;
  /** @deprecated */
  line: string;
}
export function Action$Append(room: string, line: string): Action$;
export function Action$isAppend(value: any): value is Action$;
export function Action$Append$0(value: Action$): string;
export function Action$Append$room(value: Action$): string;
export function Action$Append$1(value: Action$): string;
export function Action$Append$line(value: Action$): string;

export class Compact extends _.CustomType {
  /** @deprecated */
  constructor(room: string, lines: _.List<string>);
  /** @deprecated */
  room: string;
  /** @deprecated */
  lines: _.List<string>;
}
export function Action$Compact(room: string, lines: _.List<string>): Action$;
export function Action$isCompact(value: any): value is Action$;
export function Action$Compact$0(value: Action$): string;
export function Action$Compact$room(value: Action$): string;
export function Action$Compact$1(value: Action$): _.List<string>;
export function Action$Compact$lines(value: Action$): _.List<string>;

export type Action$ = Send | Close | Append | Compact;

declare class Preamble extends _.CustomType {
  /** @deprecated */
  constructor(
    version: number,
    room: string,
    from: string,
    session: string,
    message_type: string
  );
  /** @deprecated */
  version: number;
  /** @deprecated */
  room: string;
  /** @deprecated */
  from: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  message_type: string;
}

type Preamble$ = Preamble;

declare class ServerShape extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: string,
    order: number,
    envelope: string,
    digest: string,
    reason: string,
    detail: string,
    capabilities: $dict.Dict$<string, boolean>,
    envelope_bytes: number
  );
  /** @deprecated */
  kind: string;
  /** @deprecated */
  order: number;
  /** @deprecated */
  envelope: string;
  /** @deprecated */
  digest: string;
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
  /** @deprecated */
  capabilities: $dict.Dict$<string, boolean>;
  /** @deprecated */
  envelope_bytes: number;
}

type ServerShape$ = ServerShape;

declare class ControlShape extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: string,
    digest: string,
    up_to: number,
    order: number,
    checkpoint_requests: boolean
  );
  /** @deprecated */
  kind: string;
  /** @deprecated */
  digest: string;
  /** @deprecated */
  up_to: number;
  /** @deprecated */
  order: number;
  /** @deprecated */
  checkpoint_requests: boolean;
}

type ControlShape$ = ControlShape;

export class StateRecord extends _.CustomType {
  /** @deprecated */
  constructor(order: number, session: string, envelope: string);
  /** @deprecated */
  order: number;
  /** @deprecated */
  session: string;
  /** @deprecated */
  envelope: string;
}
export function LogRecord$StateRecord(
  order: number,
  session: string,
  envelope: string,
): LogRecord$;
export function LogRecord$isStateRecord(value: any): value is LogRecord$;
export function LogRecord$StateRecord$0(value: LogRecord$): number;
export function LogRecord$StateRecord$order(value: LogRecord$): number;
export function LogRecord$StateRecord$1(value: LogRecord$): string;
export function LogRecord$StateRecord$session(value: LogRecord$): string;
export function LogRecord$StateRecord$2(value: LogRecord$): string;
export function LogRecord$StateRecord$envelope(value: LogRecord$): string;

export class TrafficRecord extends _.CustomType {
  /** @deprecated */
  constructor(order: number, session: string, envelope: string);
  /** @deprecated */
  order: number;
  /** @deprecated */
  session: string;
  /** @deprecated */
  envelope: string;
}
export function LogRecord$TrafficRecord(
  order: number,
  session: string,
  envelope: string,
): LogRecord$;
export function LogRecord$isTrafficRecord(value: any): value is LogRecord$;
export function LogRecord$TrafficRecord$0(value: LogRecord$): number;
export function LogRecord$TrafficRecord$order(value: LogRecord$): number;
export function LogRecord$TrafficRecord$1(value: LogRecord$): string;
export function LogRecord$TrafficRecord$session(value: LogRecord$): string;
export function LogRecord$TrafficRecord$2(value: LogRecord$): string;
export function LogRecord$TrafficRecord$envelope(value: LogRecord$): string;

export class DigestRecord extends _.CustomType {
  /** @deprecated */
  constructor(order: number, digest: string, checkpoint: number);
  /** @deprecated */
  order: number;
  /** @deprecated */
  digest: string;
  /** @deprecated */
  checkpoint: number;
}
export function LogRecord$DigestRecord(
  order: number,
  digest: string,
  checkpoint: number,
): LogRecord$;
export function LogRecord$isDigestRecord(value: any): value is LogRecord$;
export function LogRecord$DigestRecord$0(value: LogRecord$): number;
export function LogRecord$DigestRecord$order(value: LogRecord$): number;
export function LogRecord$DigestRecord$1(value: LogRecord$): string;
export function LogRecord$DigestRecord$digest(value: LogRecord$): string;
export function LogRecord$DigestRecord$2(value: LogRecord$): number;
export function LogRecord$DigestRecord$checkpoint(value: LogRecord$): number;

export type LogRecord$ = StateRecord | TrafficRecord | DigestRecord;

export function LogRecord$order(value: LogRecord$): number;

declare class RawRecord extends _.CustomType {
  /** @deprecated */
  constructor(
    order: number,
    kind: string,
    session: string,
    envelope: string,
    digest: string,
    checkpoint: number
  );
  /** @deprecated */
  order: number;
  /** @deprecated */
  kind: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  envelope: string;
  /** @deprecated */
  digest: string;
  /** @deprecated */
  checkpoint: number;
}

type RawRecord$ = RawRecord;

declare class Entry extends _.CustomType {
  /** @deprecated */
  constructor(
    order: number,
    session: string,
    envelope: string,
    state: boolean,
    line: string
  );
  /** @deprecated */
  order: number;
  /** @deprecated */
  session: string;
  /** @deprecated */
  envelope: string;
  /** @deprecated */
  state: boolean;
  /** @deprecated */
  line: string;
}

type Entry$ = Entry;

declare class Client extends _.CustomType {
  /** @deprecated */
  constructor(
    from: string,
    session: string,
    delivered: number,
    skipped: _.List<number>,
    supports_checkpoints: boolean,
    checkpoint_requested: boolean
  );
  /** @deprecated */
  from: string;
  /** @deprecated */
  session: string;
  /** @deprecated */
  delivered: number;
  /** @deprecated */
  skipped: _.List<number>;
  /** @deprecated */
  supports_checkpoints: boolean;
  /** @deprecated */
  checkpoint_requested: boolean;
}

type Client$ = Client;

declare class Room extends _.CustomType {
  /** @deprecated */
  constructor(
    clients: $dict.Dict$<number, Client$>,
    next_order: number,
    log: _.List<Entry$>,
    pending: $option.Option$<[number, number]>,
    attested: string,
    attested_order: number,
    checkpoint_order: number,
    pressure_at: number,
    requests: number
  );
  /** @deprecated */
  clients: $dict.Dict$<number, Client$>;
  /** @deprecated */
  next_order: number;
  /** @deprecated */
  log: _.List<Entry$>;
  /** @deprecated */
  pending: $option.Option$<[number, number]>;
  /** @deprecated */
  attested: string;
  /** @deprecated */
  attested_order: number;
  /** @deprecated */
  checkpoint_order: number;
  /** @deprecated */
  pressure_at: number;
  /** @deprecated */
  requests: number;
}

type Room$ = Room;

declare class Relay extends _.CustomType {
  /** @deprecated */
  constructor(
    rooms: $dict.Dict$<string, Room$>,
    connections: $dict.Dict$<number, string>
  );
  /** @deprecated */
  rooms: $dict.Dict$<string, Room$>;
  /** @deprecated */
  connections: $dict.Dict$<number, string>;
}

export type Relay$ = Relay;

export const capability: string;

export const max_room_bytes: number;

export const max_session_bytes: number;

export const checkpoint_request_interval: number;

export const checkpoint_pressure_records: number;

export const max_room_records: number;

export const max_room_clients: number;

export const max_client_skips: number;

export function max_frame_bytes(): number;

export function message_kind_to_string(kind: MessageKind$): string;

export function refusal_parts(refusal: Refusal$): [string, string];

export function server_to_json(frame: ServerFrame$): $json.Json$;

export function server_to_string(frame: ServerFrame$): string;

export function control_to_string(frame: ControlFrame$): string;

export function connected_frame(): ServerFrame$;

export function decode_server(raw: string): _.Result<ServerFrame$, string>;

export function supports_relay(frame: ServerFrame$): boolean;

export function decode_client(raw: string): _.Result<ClientFrame$, Refusal$>;

export function record_to_string(record: LogRecord$): string;

export function string_to_record(line: string): _.Result<LogRecord$, undefined>;

export function new_relay(): Relay$;

export function room_names(relay: Relay$): _.List<string>;

export function clients(relay: Relay$, room: string): _.List<number>;

export function sessions(relay: Relay$, room: string): _.List<string>;

export function next_order(relay: Relay$, room: string): number;

export function log_size(relay: Relay$, room: string): number;

export function attested_digest(relay: Relay$, room: string): string;

export function replayable(relay: Relay$, room: string): _.List<string>;

export function skipped_orders(relay: Relay$, connection: number): _.List<
  number
>;

export function carried_orders(relay: Relay$, room: string): _.List<number>;

export function checkpoint_order(relay: Relay$, room: string): number;

export function checkpoint_requests(relay: Relay$, room: string): number;

export function checkpoints_pending(relay: Relay$, room: string): _.List<number>;

export function supports_checkpoints(relay: Relay$, connection: number): boolean;

export function connect(relay: Relay$, connection: number): [
  Relay$,
  _.List<Action$>
];

export function disconnect(relay: Relay$, connection: number): [
  Relay$,
  _.List<Action$>
];

export function serve(relay: Relay$, connection: number, raw: string): [
  Relay$,
  _.List<Action$>,
  string
];

export function handle_frame(relay: Relay$, connection: number, raw: string): [
  Relay$,
  _.List<Action$>
];

export function replay(relay: Relay$, room: string, lines: _.List<string>): Relay$;

export function render_sockets(actions: _.List<Action$>): _.List<
  [number, string, string]
>;

export function render_storage(actions: _.List<Action$>): _.List<
  [string, string, _.List<string>]
>;
