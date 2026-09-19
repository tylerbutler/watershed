import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $p2p_transport_js from "../watershed/p2p_transport_js.d.mts";

export class Join extends _.CustomType {
  /** @deprecated */
  constructor(room: string, peer: string);
  /** @deprecated */
  room: string;
  /** @deprecated */
  peer: string;
}
export function ClientFrame$Join(room: string, peer: string): ClientFrame$;
export function ClientFrame$isJoin(value: any): value is ClientFrame$;
export function ClientFrame$Join$0(value: ClientFrame$): string;
export function ClientFrame$Join$room(value: ClientFrame$): string;
export function ClientFrame$Join$1(value: ClientFrame$): string;
export function ClientFrame$Join$peer(value: ClientFrame$): string;

export class Signal extends _.CustomType {
  /** @deprecated */
  constructor(to: string, payload: $p2p_transport_js.SignalPayload$);
  /** @deprecated */
  to: string;
  /** @deprecated */
  payload: $p2p_transport_js.SignalPayload$;
}
export function ClientFrame$Signal(
  to: string,
  payload: $p2p_transport_js.SignalPayload$,
): ClientFrame$;
export function ClientFrame$isSignal(value: any): value is ClientFrame$;
export function ClientFrame$Signal$0(value: ClientFrame$): string;
export function ClientFrame$Signal$to(value: ClientFrame$): string;
export function ClientFrame$Signal$1(value: ClientFrame$): $p2p_transport_js.SignalPayload$;
export function ClientFrame$Signal$payload(
  value: ClientFrame$,
): $p2p_transport_js.SignalPayload$;

export class Leave extends _.CustomType {}
export function ClientFrame$Leave(): ClientFrame$;
export function ClientFrame$isLeave(value: any): value is ClientFrame$;

export type ClientFrame$ = Join | Signal | Leave;

export class Joined extends _.CustomType {
  /** @deprecated */
  constructor(room: string, peer: string, peers: _.List<string>);
  /** @deprecated */
  room: string;
  /** @deprecated */
  peer: string;
  /** @deprecated */
  peers: _.List<string>;
}
export function ServerFrame$Joined(
  room: string,
  peer: string,
  peers: _.List<string>,
): ServerFrame$;
export function ServerFrame$isJoined(value: any): value is ServerFrame$;
export function ServerFrame$Joined$0(value: ServerFrame$): string;
export function ServerFrame$Joined$room(value: ServerFrame$): string;
export function ServerFrame$Joined$1(value: ServerFrame$): string;
export function ServerFrame$Joined$peer(value: ServerFrame$): string;
export function ServerFrame$Joined$2(value: ServerFrame$): _.List<string>;
export function ServerFrame$Joined$peers(value: ServerFrame$): _.List<string>;

export class PeerJoined extends _.CustomType {
  /** @deprecated */
  constructor(peer: string);
  /** @deprecated */
  peer: string;
}
export function ServerFrame$PeerJoined(peer: string): ServerFrame$;
export function ServerFrame$isPeerJoined(value: any): value is ServerFrame$;
export function ServerFrame$PeerJoined$0(value: ServerFrame$): string;
export function ServerFrame$PeerJoined$peer(value: ServerFrame$): string;

export class PeerLeft extends _.CustomType {
  /** @deprecated */
  constructor(peer: string);
  /** @deprecated */
  peer: string;
}
export function ServerFrame$PeerLeft(peer: string): ServerFrame$;
export function ServerFrame$isPeerLeft(value: any): value is ServerFrame$;
export function ServerFrame$PeerLeft$0(value: ServerFrame$): string;
export function ServerFrame$PeerLeft$peer(value: ServerFrame$): string;

export class Forwarded extends _.CustomType {
  /** @deprecated */
  constructor(from: string, payload: $p2p_transport_js.SignalPayload$);
  /** @deprecated */
  from: string;
  /** @deprecated */
  payload: $p2p_transport_js.SignalPayload$;
}
export function ServerFrame$Forwarded(
  from: string,
  payload: $p2p_transport_js.SignalPayload$,
): ServerFrame$;
export function ServerFrame$isForwarded(value: any): value is ServerFrame$;
export function ServerFrame$Forwarded$0(value: ServerFrame$): string;
export function ServerFrame$Forwarded$from(value: ServerFrame$): string;
export function ServerFrame$Forwarded$1(value: ServerFrame$): $p2p_transport_js.SignalPayload$;
export function ServerFrame$Forwarded$payload(
  value: ServerFrame$,
): $p2p_transport_js.SignalPayload$;

export class Rejected extends _.CustomType {
  /** @deprecated */
  constructor(reason: string, detail: string);
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}
export function ServerFrame$Rejected(
  reason: string,
  detail: string,
): ServerFrame$;
export function ServerFrame$isRejected(value: any): value is ServerFrame$;
export function ServerFrame$Rejected$0(value: ServerFrame$): string;
export function ServerFrame$Rejected$reason(value: ServerFrame$): string;
export function ServerFrame$Rejected$1(value: ServerFrame$): string;
export function ServerFrame$Rejected$detail(value: ServerFrame$): string;

export class Dropped extends _.CustomType {
  /** @deprecated */
  constructor(reason: string, detail: string);
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}
export function ServerFrame$Dropped(
  reason: string,
  detail: string,
): ServerFrame$;
export function ServerFrame$isDropped(value: any): value is ServerFrame$;
export function ServerFrame$Dropped$0(value: ServerFrame$): string;
export function ServerFrame$Dropped$reason(value: ServerFrame$): string;
export function ServerFrame$Dropped$1(value: ServerFrame$): string;
export function ServerFrame$Dropped$detail(value: ServerFrame$): string;

export type ServerFrame$ = Joined | PeerJoined | PeerLeft | Forwarded | Rejected | Dropped;

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

export type Action$ = Send | Close;

export function Action$connection(value: Action$): number;

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

export class NotJoined extends _.CustomType {}
export function Refusal$NotJoined(): Refusal$;
export function Refusal$isNotJoined(value: any): value is Refusal$;

export class AlreadyJoined extends _.CustomType {}
export function Refusal$AlreadyJoined(): Refusal$;
export function Refusal$isAlreadyJoined(value: any): value is Refusal$;

export class DuplicatePeerId extends _.CustomType {
  /** @deprecated */
  constructor(peer: string);
  /** @deprecated */
  peer: string;
}
export function Refusal$DuplicatePeerId(peer: string): Refusal$;
export function Refusal$isDuplicatePeerId(value: any): value is Refusal$;
export function Refusal$DuplicatePeerId$0(value: Refusal$): string;
export function Refusal$DuplicatePeerId$peer(value: Refusal$): string;

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

export class CrossRoomTarget extends _.CustomType {
  /** @deprecated */
  constructor(peer: string);
  /** @deprecated */
  peer: string;
}
export function Refusal$CrossRoomTarget(peer: string): Refusal$;
export function Refusal$isCrossRoomTarget(value: any): value is Refusal$;
export function Refusal$CrossRoomTarget$0(value: Refusal$): string;
export function Refusal$CrossRoomTarget$peer(value: Refusal$): string;

export class UnknownTarget extends _.CustomType {
  /** @deprecated */
  constructor(peer: string);
  /** @deprecated */
  peer: string;
}
export function Refusal$UnknownTarget(peer: string): Refusal$;
export function Refusal$isUnknownTarget(value: any): value is Refusal$;
export function Refusal$UnknownTarget$0(value: Refusal$): string;
export function Refusal$UnknownTarget$peer(value: Refusal$): string;

export class InvalidId extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Refusal$InvalidId(detail: string): Refusal$;
export function Refusal$isInvalidId(value: any): value is Refusal$;
export function Refusal$InvalidId$0(value: Refusal$): string;
export function Refusal$InvalidId$detail(value: Refusal$): string;

export type Refusal$ = FrameTooLarge | Malformed | NotJoined | AlreadyJoined | DuplicatePeerId | RoomFull | CrossRoomTarget | UnknownTarget | InvalidId;

declare class Rooms extends _.CustomType {
  /** @deprecated */
  constructor(
    rooms: $dict.Dict$<string, $dict.Dict$<string, number>>,
    members: $dict.Dict$<number, [string, string]>,
    occupancy: $dict.Dict$<string, number>
  );
  /** @deprecated */
  rooms: $dict.Dict$<string, $dict.Dict$<string, number>>;
  /** @deprecated */
  members: $dict.Dict$<number, [string, string]>;
  /** @deprecated */
  occupancy: $dict.Dict$<string, number>;
}

export type Rooms$ = Rooms;

export const max_frame_bytes: number;

export const max_id_bytes: number;

export function room_limit(): number;

export function is_terminal(refusal: Refusal$): boolean;

export function refusal_parts(refusal: Refusal$): [string, string];

export function encode_payload(payload: $p2p_transport_js.SignalPayload$): $json.Json$;

export function encode_client(frame: ClientFrame$): $json.Json$;

export function client_to_string(frame: ClientFrame$): string;

export function encode_server(frame: ServerFrame$): $json.Json$;

export function server_to_string(frame: ServerFrame$): string;

export function payload_decoder(): $decode.Decoder$<
  $p2p_transport_js.SignalPayload$
>;

export function decode_client(raw: string): _.Result<ClientFrame$, Refusal$>;

export function decode_server(raw: string): _.Result<ServerFrame$, Refusal$>;

export function new_rooms(): Rooms$;

export function members(rooms: Rooms$, room: string): _.List<string>;

export function room_names(rooms: Rooms$): _.List<string>;

export function membership(rooms: Rooms$, connection: number): _.Result<
  [string, string],
  undefined
>;

export function disconnect(rooms: Rooms$, connection: number): [
  Rooms$,
  _.List<Action$>
];

export function handle_frame(rooms: Rooms$, connection: number, raw: string): [
  Rooms$,
  _.List<Action$>
];

export function render_actions(actions: _.List<Action$>): _.List<
  [number, string, string]
>;

export function serve(rooms: Rooms$, connection: number, raw: string): [
  Rooms$,
  _.List<[number, string, string]>,
  string
];
