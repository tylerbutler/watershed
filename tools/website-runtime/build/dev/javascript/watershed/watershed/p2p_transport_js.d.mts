import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export class Offer extends _.CustomType {
  /** @deprecated */
  constructor(sdp: string);
  /** @deprecated */
  sdp: string;
}
export function SignalPayload$Offer(sdp: string): SignalPayload$;
export function SignalPayload$isOffer(value: any): value is SignalPayload$;
export function SignalPayload$Offer$0(value: SignalPayload$): string;
export function SignalPayload$Offer$sdp(value: SignalPayload$): string;

export class Answer extends _.CustomType {
  /** @deprecated */
  constructor(sdp: string);
  /** @deprecated */
  sdp: string;
}
export function SignalPayload$Answer(sdp: string): SignalPayload$;
export function SignalPayload$isAnswer(value: any): value is SignalPayload$;
export function SignalPayload$Answer$0(value: SignalPayload$): string;
export function SignalPayload$Answer$sdp(value: SignalPayload$): string;

export class Candidate extends _.CustomType {
  /** @deprecated */
  constructor(candidate: string);
  /** @deprecated */
  candidate: string;
}
export function SignalPayload$Candidate(candidate: string): SignalPayload$;
export function SignalPayload$isCandidate(value: any): value is SignalPayload$;
export function SignalPayload$Candidate$0(value: SignalPayload$): string;
export function SignalPayload$Candidate$candidate(value: SignalPayload$): string;

export type SignalPayload$ = Offer | Answer | Candidate;

export class Roster extends _.CustomType {
  /** @deprecated */
  constructor(peers: _.List<string>);
  /** @deprecated */
  peers: _.List<string>;
}
export function Signal$Roster(peers: _.List<string>): Signal$;
export function Signal$isRoster(value: any): value is Signal$;
export function Signal$Roster$0(value: Signal$): _.List<string>;
export function Signal$Roster$peers(value: Signal$): _.List<string>;

export class PeerJoined extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Signal$PeerJoined(peer_id: string): Signal$;
export function Signal$isPeerJoined(value: any): value is Signal$;
export function Signal$PeerJoined$0(value: Signal$): string;
export function Signal$PeerJoined$peer_id(value: Signal$): string;

export class PeerLeft extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Signal$PeerLeft(peer_id: string): Signal$;
export function Signal$isPeerLeft(value: any): value is Signal$;
export function Signal$PeerLeft$0(value: Signal$): string;
export function Signal$PeerLeft$peer_id(value: Signal$): string;

export class Message extends _.CustomType {
  /** @deprecated */
  constructor(from: string, payload: SignalPayload$);
  /** @deprecated */
  from: string;
  /** @deprecated */
  payload: SignalPayload$;
}
export function Signal$Message(from: string, payload: SignalPayload$): Signal$;
export function Signal$isMessage(value: any): value is Signal$;
export function Signal$Message$0(value: Signal$): string;
export function Signal$Message$from(value: Signal$): string;
export function Signal$Message$1(value: Signal$): SignalPayload$;
export function Signal$Message$payload(value: Signal$): SignalPayload$;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Signal$Failed(detail: string): Signal$;
export function Signal$isFailed(value: any): value is Signal$;
export function Signal$Failed$0(value: Signal$): string;
export function Signal$Failed$detail(value: Signal$): string;

export type Signal$ = Roster | PeerJoined | PeerLeft | Message | Failed;

declare class SignalingSession extends _.CustomType {
  /** @deprecated */
  constructor(room: string, peer_id: string);
  /** @deprecated */
  room: string;
  /** @deprecated */
  peer_id: string;
}

export type SignalingSession$ = SignalingSession;

export class Signaling extends _.CustomType {
  /** @deprecated */
  constructor(
    join: (x0: string, x1: string, x2: (x0: Signal$) => undefined) => _.Result<
      SignalingSession$,
      string
    >,
    send: (x0: SignalingSession$, x1: string, x2: SignalPayload$) => undefined,
    leave: (x0: SignalingSession$) => undefined
  );
  /** @deprecated */
  join: (x0: string, x1: string, x2: (x0: Signal$) => undefined) => _.Result<
    SignalingSession$,
    string
  >;
  /** @deprecated */
  send: (x0: SignalingSession$, x1: string, x2: SignalPayload$) => undefined;
  /** @deprecated */
  leave: (x0: SignalingSession$) => undefined;
}
export function Signaling$Signaling(
  join: (x0: string, x1: string, x2: (x0: Signal$) => undefined) => _.Result<
    SignalingSession$,
    string
  >,
  send: (x0: SignalingSession$, x1: string, x2: SignalPayload$) => undefined,
  leave: (x0: SignalingSession$) => undefined,
): Signaling$;
export function Signaling$isSignaling(value: any): value is Signaling$;
export function Signaling$Signaling$0(value: Signaling$): (
  x0: string,
  x1: string,
  x2: (x0: Signal$) => undefined
) => _.Result<SignalingSession$, string>;
export function Signaling$Signaling$join(value: Signaling$): (
  x0: string,
  x1: string,
  x2: (x0: Signal$) => undefined
) => _.Result<SignalingSession$, string>;
export function Signaling$Signaling$1(value: Signaling$): (
  x0: SignalingSession$,
  x1: string,
  x2: SignalPayload$
) => undefined;
export function Signaling$Signaling$send(value: Signaling$): (
  x0: SignalingSession$,
  x1: string,
  x2: SignalPayload$
) => undefined;
export function Signaling$Signaling$2(value: Signaling$): (
  x0: SignalingSession$
) => undefined;
export function Signaling$Signaling$leave(value: Signaling$): (
  x0: SignalingSession$
) => undefined;

export type Signaling$ = Signaling;

export class IceServer extends _.CustomType {
  /** @deprecated */
  constructor(
    urls: _.List<string>,
    username: $option.Option$<string>,
    credential: $option.Option$<string>
  );
  /** @deprecated */
  urls: _.List<string>;
  /** @deprecated */
  username: $option.Option$<string>;
  /** @deprecated */
  credential: $option.Option$<string>;
}
export function IceServer$IceServer(
  urls: _.List<string>,
  username: $option.Option$<string>,
  credential: $option.Option$<string>,
): IceServer$;
export function IceServer$isIceServer(value: any): value is IceServer$;
export function IceServer$IceServer$0(value: IceServer$): _.List<string>;
export function IceServer$IceServer$urls(value: IceServer$): _.List<string>;
export function IceServer$IceServer$1(value: IceServer$): $option.Option$<
  string
>;
export function IceServer$IceServer$username(value: IceServer$): $option.Option$<
  string
>;
export function IceServer$IceServer$2(value: IceServer$): $option.Option$<
  string
>;
export function IceServer$IceServer$credential(value: IceServer$): $option.Option$<
  string
>;

export type IceServer$ = IceServer;

export class SignalingJoined extends _.CustomType {
  /** @deprecated */
  constructor(room: string, peer_id: string);
  /** @deprecated */
  room: string;
  /** @deprecated */
  peer_id: string;
}
export function Status$SignalingJoined(room: string, peer_id: string): Status$;
export function Status$isSignalingJoined(value: any): value is Status$;
export function Status$SignalingJoined$0(value: Status$): string;
export function Status$SignalingJoined$room(value: Status$): string;
export function Status$SignalingJoined$1(value: Status$): string;
export function Status$SignalingJoined$peer_id(value: Status$): string;

export class SignalingRoster extends _.CustomType {
  /** @deprecated */
  constructor(peers: _.List<string>);
  /** @deprecated */
  peers: _.List<string>;
}
export function Status$SignalingRoster(peers: _.List<string>): Status$;
export function Status$isSignalingRoster(value: any): value is Status$;
export function Status$SignalingRoster$0(value: Status$): _.List<string>;
export function Status$SignalingRoster$peers(value: Status$): _.List<string>;

export class SignalingLeft extends _.CustomType {}
export function Status$SignalingLeft(): Status$;
export function Status$isSignalingLeft(value: any): value is Status$;

export class PeerConnecting extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$PeerConnecting(peer_id: string): Status$;
export function Status$isPeerConnecting(value: any): value is Status$;
export function Status$PeerConnecting$0(value: Status$): string;
export function Status$PeerConnecting$peer_id(value: Status$): string;

export class PeerOpen extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$PeerOpen(peer_id: string): Status$;
export function Status$isPeerOpen(value: any): value is Status$;
export function Status$PeerOpen$0(value: Status$): string;
export function Status$PeerOpen$peer_id(value: Status$): string;

export class PeerClosed extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$PeerClosed(peer_id: string): Status$;
export function Status$isPeerClosed(value: any): value is Status$;
export function Status$PeerClosed$0(value: Status$): string;
export function Status$PeerClosed$peer_id(value: Status$): string;

export class PeerFailed extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, detail: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  detail: string;
}
export function Status$PeerFailed(peer_id: string, detail: string): Status$;
export function Status$isPeerFailed(value: any): value is Status$;
export function Status$PeerFailed$0(value: Status$): string;
export function Status$PeerFailed$peer_id(value: Status$): string;
export function Status$PeerFailed$1(value: Status$): string;
export function Status$PeerFailed$detail(value: Status$): string;

export class IceState extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, state: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  state: string;
}
export function Status$IceState(peer_id: string, state: string): Status$;
export function Status$isIceState(value: any): value is Status$;
export function Status$IceState$0(value: Status$): string;
export function Status$IceState$peer_id(value: Status$): string;
export function Status$IceState$1(value: Status$): string;
export function Status$IceState$state(value: Status$): string;

export class PeerCount extends _.CustomType {
  /** @deprecated */
  constructor(open: number);
  /** @deprecated */
  open: number;
}
export function Status$PeerCount(open: number): Status$;
export function Status$isPeerCount(value: any): value is Status$;
export function Status$PeerCount$0(value: Status$): number;
export function Status$PeerCount$open(value: Status$): number;

export type Status$ = SignalingJoined | SignalingRoster | SignalingLeft | PeerConnecting | PeerOpen | PeerClosed | PeerFailed | IceState | PeerCount;

export class Callbacks extends _.CustomType {
  /** @deprecated */
  constructor(
    on_peer_open: (x0: string) => undefined,
    on_peer_close: (x0: string) => undefined,
    on_document: (x0: string, x1: string) => undefined,
    on_status: (x0: Status$) => undefined,
    on_error: (x0: $p2p.P2pError$) => undefined
  );
  /** @deprecated */
  on_peer_open: (x0: string) => undefined;
  /** @deprecated */
  on_peer_close: (x0: string) => undefined;
  /** @deprecated */
  on_document: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_status: (x0: Status$) => undefined;
  /** @deprecated */
  on_error: (x0: $p2p.P2pError$) => undefined;
}
export function Callbacks$Callbacks(
  on_peer_open: (x0: string) => undefined,
  on_peer_close: (x0: string) => undefined,
  on_document: (x0: string, x1: string) => undefined,
  on_status: (x0: Status$) => undefined,
  on_error: (x0: $p2p.P2pError$) => undefined,
): Callbacks$;
export function Callbacks$isCallbacks(value: any): value is Callbacks$;
export function Callbacks$Callbacks$0(value: Callbacks$): (x0: string) => undefined;
export function Callbacks$Callbacks$on_peer_open(
  value: Callbacks$,
): (x0: string) => undefined;
export function Callbacks$Callbacks$1(value: Callbacks$): (x0: string) => undefined;
export function Callbacks$Callbacks$on_peer_close(
  value: Callbacks$,
): (x0: string) => undefined;
export function Callbacks$Callbacks$2(value: Callbacks$): (
  x0: string,
  x1: string
) => undefined;
export function Callbacks$Callbacks$on_document(value: Callbacks$): (
  x0: string,
  x1: string
) => undefined;
export function Callbacks$Callbacks$3(value: Callbacks$): (x0: Status$) => undefined;
export function Callbacks$Callbacks$on_status(
  value: Callbacks$,
): (x0: Status$) => undefined;
export function Callbacks$Callbacks$4(value: Callbacks$): (x0: $p2p.P2pError$) => undefined;
export function Callbacks$Callbacks$on_error(
  value: Callbacks$,
): (x0: $p2p.P2pError$) => undefined;

export type Callbacks$ = Callbacks;

export class PeerHooks extends _.CustomType {
  /** @deprecated */
  constructor(
    on_negotiation_needed: (x0: string) => undefined,
    on_description: (x0: string, x1: string, x2: string) => undefined,
    on_remote_description: (x0: string) => undefined,
    on_candidate: (x0: string, x1: string) => undefined,
    on_channel_open: (x0: string) => undefined,
    on_channel_close: (x0: string) => undefined,
    on_message: (x0: string, x1: string) => undefined,
    on_invalid_message: (x0: string, x1: string) => undefined,
    on_ice_state: (x0: string, x1: string) => undefined,
    on_failure: (x0: string, x1: string, x2: string) => undefined
  );
  /** @deprecated */
  on_negotiation_needed: (x0: string) => undefined;
  /** @deprecated */
  on_description: (x0: string, x1: string, x2: string) => undefined;
  /** @deprecated */
  on_remote_description: (x0: string) => undefined;
  /** @deprecated */
  on_candidate: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_channel_open: (x0: string) => undefined;
  /** @deprecated */
  on_channel_close: (x0: string) => undefined;
  /** @deprecated */
  on_message: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_invalid_message: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_ice_state: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_failure: (x0: string, x1: string, x2: string) => undefined;
}
export function PeerHooks$PeerHooks(
  on_negotiation_needed: (x0: string) => undefined,
  on_description: (x0: string, x1: string, x2: string) => undefined,
  on_remote_description: (x0: string) => undefined,
  on_candidate: (x0: string, x1: string) => undefined,
  on_channel_open: (x0: string) => undefined,
  on_channel_close: (x0: string) => undefined,
  on_message: (x0: string, x1: string) => undefined,
  on_invalid_message: (x0: string, x1: string) => undefined,
  on_ice_state: (x0: string, x1: string) => undefined,
  on_failure: (x0: string, x1: string, x2: string) => undefined,
): PeerHooks$;
export function PeerHooks$isPeerHooks(value: any): value is PeerHooks$;
export function PeerHooks$PeerHooks$0(value: PeerHooks$): (x0: string) => undefined;
export function PeerHooks$PeerHooks$on_negotiation_needed(
  value: PeerHooks$,
): (x0: string) => undefined;
export function PeerHooks$PeerHooks$1(value: PeerHooks$): (
  x0: string,
  x1: string,
  x2: string
) => undefined;
export function PeerHooks$PeerHooks$on_description(value: PeerHooks$): (
  x0: string,
  x1: string,
  x2: string
) => undefined;
export function PeerHooks$PeerHooks$2(value: PeerHooks$): (x0: string) => undefined;
export function PeerHooks$PeerHooks$on_remote_description(
  value: PeerHooks$,
): (x0: string) => undefined;
export function PeerHooks$PeerHooks$3(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$on_candidate(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$4(value: PeerHooks$): (x0: string) => undefined;
export function PeerHooks$PeerHooks$on_channel_open(
  value: PeerHooks$,
): (x0: string) => undefined;
export function PeerHooks$PeerHooks$5(value: PeerHooks$): (x0: string) => undefined;
export function PeerHooks$PeerHooks$on_channel_close(
  value: PeerHooks$,
): (x0: string) => undefined;
export function PeerHooks$PeerHooks$6(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$on_message(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$7(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$on_invalid_message(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$8(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$on_ice_state(value: PeerHooks$): (
  x0: string,
  x1: string
) => undefined;
export function PeerHooks$PeerHooks$9(value: PeerHooks$): (
  x0: string,
  x1: string,
  x2: string
) => undefined;
export function PeerHooks$PeerHooks$on_failure(value: PeerHooks$): (
  x0: string,
  x1: string,
  x2: string
) => undefined;

export type PeerHooks$ = PeerHooks;

export class Rtc extends _.CustomType {
  /** @deprecated */
  constructor(
    open: (x0: string, x1: string, x2: PeerHooks$) => undefined,
    open_channel: (x0: string, x1: string, x2: string) => undefined,
    offer: (x0: string) => undefined,
    accept_offer: (x0: string, x1: string) => undefined,
    accept_answer: (x0: string, x1: string) => undefined,
    add_candidate: (x0: string, x1: string) => undefined,
    signaling_state: (x0: string) => string,
    send: (x0: string, x1: string) => boolean,
    close: (x0: string) => undefined,
    diagnostics: (x0: string) => string
  );
  /** @deprecated */
  open: (x0: string, x1: string, x2: PeerHooks$) => undefined;
  /** @deprecated */
  open_channel: (x0: string, x1: string, x2: string) => undefined;
  /** @deprecated */
  offer: (x0: string) => undefined;
  /** @deprecated */
  accept_offer: (x0: string, x1: string) => undefined;
  /** @deprecated */
  accept_answer: (x0: string, x1: string) => undefined;
  /** @deprecated */
  add_candidate: (x0: string, x1: string) => undefined;
  /** @deprecated */
  signaling_state: (x0: string) => string;
  /** @deprecated */
  send: (x0: string, x1: string) => boolean;
  /** @deprecated */
  close: (x0: string) => undefined;
  /** @deprecated */
  diagnostics: (x0: string) => string;
}
export function Rtc$Rtc(
  open: (x0: string, x1: string, x2: PeerHooks$) => undefined,
  open_channel: (x0: string, x1: string, x2: string) => undefined,
  offer: (x0: string) => undefined,
  accept_offer: (x0: string, x1: string) => undefined,
  accept_answer: (x0: string, x1: string) => undefined,
  add_candidate: (x0: string, x1: string) => undefined,
  signaling_state: (x0: string) => string,
  send: (x0: string, x1: string) => boolean,
  close: (x0: string) => undefined,
  diagnostics: (x0: string) => string,
): Rtc$;
export function Rtc$isRtc(value: any): value is Rtc$;
export function Rtc$Rtc$0(value: Rtc$): (x0: string, x1: string, x2: PeerHooks$) => undefined;
export function Rtc$Rtc$open(
  value: Rtc$,
): (x0: string, x1: string, x2: PeerHooks$) => undefined;
export function Rtc$Rtc$1(value: Rtc$): (x0: string, x1: string, x2: string) => undefined;
export function Rtc$Rtc$open_channel(
  value: Rtc$,
): (x0: string, x1: string, x2: string) => undefined;
export function Rtc$Rtc$2(value: Rtc$): (x0: string) => undefined;
export function Rtc$Rtc$offer(value: Rtc$): (x0: string) => undefined;
export function Rtc$Rtc$3(value: Rtc$): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$accept_offer(value: Rtc$): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$4(
  value: Rtc$,
): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$accept_answer(value: Rtc$): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$5(
  value: Rtc$,
): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$add_candidate(value: Rtc$): (x0: string, x1: string) => undefined;
export function Rtc$Rtc$6(
  value: Rtc$,
): (x0: string) => string;
export function Rtc$Rtc$signaling_state(value: Rtc$): (x0: string) => string;
export function Rtc$Rtc$7(value: Rtc$): (x0: string, x1: string) => boolean;
export function Rtc$Rtc$send(value: Rtc$): (x0: string, x1: string) => boolean;
export function Rtc$Rtc$8(value: Rtc$): (x0: string) => undefined;
export function Rtc$Rtc$close(value: Rtc$): (x0: string) => undefined;
export function Rtc$Rtc$9(value: Rtc$): (x0: string) => string;
export function Rtc$Rtc$diagnostics(value: Rtc$): (x0: string) => string;

export type Rtc$ = Rtc;

export type NativeRtc$ = any;

declare class Transport extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
}

export type Transport$ = Transport;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    room: string,
    peer_id: string,
    signaling: Signaling$,
    session: $option.Option$<SignalingSession$>,
    rtc: Rtc$,
    configuration: string,
    callbacks: Callbacks$,
    peers: $dict.Dict$<string, Peer$>,
    pending_signals: _.List<Signal$>,
    closed: boolean
  );
  /** @deprecated */
  room: string;
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  signaling: Signaling$;
  /** @deprecated */
  session: $option.Option$<SignalingSession$>;
  /** @deprecated */
  rtc: Rtc$;
  /** @deprecated */
  configuration: string;
  /** @deprecated */
  callbacks: Callbacks$;
  /** @deprecated */
  peers: $dict.Dict$<string, Peer$>;
  /** @deprecated */
  pending_signals: _.List<Signal$>;
  /** @deprecated */
  closed: boolean;
}

type State$ = State;

declare class Peer extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    role: NegotiationRole$,
    announced: boolean,
    channel_requested: boolean,
    remote_offered: boolean,
    making_offer: boolean,
    ignore_offer: boolean,
    have_remote_description: boolean,
    last_remote_offer: $option.Option$<string>,
    queued_candidates: _.List<string>,
    open: boolean
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  role: NegotiationRole$;
  /** @deprecated */
  announced: boolean;
  /** @deprecated */
  channel_requested: boolean;
  /** @deprecated */
  remote_offered: boolean;
  /** @deprecated */
  making_offer: boolean;
  /** @deprecated */
  ignore_offer: boolean;
  /** @deprecated */
  have_remote_description: boolean;
  /** @deprecated */
  last_remote_offer: $option.Option$<string>;
  /** @deprecated */
  queued_candidates: _.List<string>;
  /** @deprecated */
  open: boolean;
}

type Peer$ = Peer;

declare class Offerer extends _.CustomType {}

declare class Answerer extends _.CustomType {}

type NegotiationRole$ = Offerer | Answerer;

export class TransportClosed extends _.CustomType {}
export function SendError$TransportClosed(): SendError$;
export function SendError$isTransportClosed(value: any): value is SendError$;

export class UnknownPeer extends _.CustomType {}
export function SendError$UnknownPeer(): SendError$;
export function SendError$isUnknownPeer(value: any): value is SendError$;

export class ChannelNotOpen extends _.CustomType {}
export function SendError$ChannelNotOpen(): SendError$;
export function SendError$isChannelNotOpen(value: any): value is SendError$;

export class SendFailed extends _.CustomType {}
export function SendError$SendFailed(): SendError$;
export function SendError$isSendFailed(value: any): value is SendError$;

export type SendError$ = TransportClosed | UnknownPeer | ChannelNotOpen | SendFailed;

export const document_channel_label: string;

export function signaling_session(room: string, peer_id: string): SignalingSession$;

export function session_room(session: SignalingSession$): string;

export function session_peer_id(session: SignalingSession$): string;

export function ice_server(urls: _.List<string>): IceServer$;

export function with_credentials(
  server: IceServer$,
  username: string,
  credential: string
): IceServer$;

export function public_stun_servers(): _.List<IceServer$>;

export function rtc_configuration_json(servers: _.List<IceServer$>): string;

export function document_channel_options_json(): string;

export function room_limit(): number;

export function real_rtc(): Rtc$;

export function start_with_rtc(
  room: string,
  peer_id: string,
  signaling: Signaling$,
  ice_servers: _.List<IceServer$>,
  callbacks: Callbacks$,
  rtc: Rtc$
): _.Result<Transport$, $p2p.P2pError$>;

export function start(
  room: string,
  peer_id: string,
  signaling: Signaling$,
  ice_servers: _.List<IceServer$>,
  callbacks: Callbacks$
): _.Result<Transport$, $p2p.P2pError$>;

export function local_peer_id(transport: Transport$): string;

export function room(transport: Transport$): string;

export function open_peers(transport: Transport$): _.List<string>;

export function open_peer_count(transport: Transport$): number;

export function known_peers(transport: Transport$): _.List<string>;

export function is_closed(transport: Transport$): boolean;

export function peer_diagnostics(transport: Transport$, peer_id: string): string;

export function send(transport: Transport$, peer_id: string, payload: string): _.Result<
  undefined,
  SendError$
>;

export function broadcast(transport: Transport$, payload: string): number;

export function close_peer(transport: Transport$, peer_id: string): undefined;

export function close(transport: Transport$): undefined;
