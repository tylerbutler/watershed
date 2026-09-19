import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $crdt_core from "../watershed/crdt_core.d.mts";
import type * as $crdt_sequencer_js from "../watershed/crdt_sequencer_js.d.mts";
import type * as $crdt_wire from "../watershed/crdt_wire.d.mts";
import type * as $g_counter_kernel from "../watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../watershed/g_set_kernel.d.mts";
import type * as $lww_map_kernel from "../watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "../watershed/lww_register_kernel.d.mts";
import type * as $mv_register_kernel from "../watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "../watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../watershed/or_set_kernel.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";
import type * as $p2p_transport_js from "../watershed/p2p_transport_js.d.mts";
import type * as $pn_counter_kernel from "../watershed/pn_counter_kernel.d.mts";
import type * as $schema from "../watershed/schema.d.mts";
import type * as $sequence_kernel from "../watershed/sequence_kernel.d.mts";
import type * as $text_kernel from "../watershed/text_kernel.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";
import type * as $two_p_set_kernel from "../watershed/two_p_set_kernel.d.mts";

declare class Config extends _.CustomType {
  /** @deprecated */
  constructor(
    room: string,
    label: string,
    compatibility: string,
    root: $channel.ChannelInit$,
    signaling: $p2p_transport_js.Signaling$,
    ice_servers: _.List<$p2p_transport_js.IceServer$>,
    policy: TransportPolicy$,
    sequencer: $option.Option$<SequencerConfig$>,
    scheduler: $transport_js.Scheduler$,
    anti_entropy_interval_milliseconds: number
  );
  /** @deprecated */
  room: string;
  /** @deprecated */
  label: string;
  /** @deprecated */
  compatibility: string;
  /** @deprecated */
  root: $channel.ChannelInit$;
  /** @deprecated */
  signaling: $p2p_transport_js.Signaling$;
  /** @deprecated */
  ice_servers: _.List<$p2p_transport_js.IceServer$>;
  /** @deprecated */
  policy: TransportPolicy$;
  /** @deprecated */
  sequencer: $option.Option$<SequencerConfig$>;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  anti_entropy_interval_milliseconds: number;
}

export type Config$<BUUJ> = Config;

export class Auto extends _.CustomType {}
export function TransportPolicy$Auto(): TransportPolicy$;
export function TransportPolicy$isAuto(value: any): value is TransportPolicy$;

export class SequencedOnly extends _.CustomType {}
export function TransportPolicy$SequencedOnly(): TransportPolicy$;
export function TransportPolicy$isSequencedOnly(
  value: any,
): value is TransportPolicy$;

export class P2pOnly extends _.CustomType {}
export function TransportPolicy$P2pOnly(): TransportPolicy$;
export function TransportPolicy$isP2pOnly(
  value: any,
): value is TransportPolicy$;

export type TransportPolicy$ = Auto | SequencedOnly | P2pOnly;

export class PeerToPeer extends _.CustomType {}
export function TransportPath$PeerToPeer(): TransportPath$;
export function TransportPath$isPeerToPeer(value: any): value is TransportPath$;

export class Sequenced extends _.CustomType {}
export function TransportPath$Sequenced(): TransportPath$;
export function TransportPath$isSequenced(value: any): value is TransportPath$;

export type TransportPath$ = PeerToPeer | Sequenced;

declare class SequencerConfig extends _.CustomType {
  /** @deprecated */
  constructor(
    url: string,
    driver: $crdt_sequencer_js.Driver$,
    readiness_deadline_milliseconds: number
  );
  /** @deprecated */
  url: string;
  /** @deprecated */
  driver: $crdt_sequencer_js.Driver$;
  /** @deprecated */
  readiness_deadline_milliseconds: number;
}

export type SequencerConfig$ = SequencerConfig;

declare class CrdtDocument extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
}

export type CrdtDocument$<BUUK> = CrdtDocument;

declare class Handle extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>, address: string);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
  /** @deprecated */
  address: string;
}

export type Handle$<BUUL> = Handle;

declare class CrdtConnection extends _.CustomType {
  /** @deprecated */
  constructor(cell: $option.Option$<$transport_js.Cell$<State$>>);
  /** @deprecated */
  cell: $option.Option$<$transport_js.Cell$<State$>>;
}

export type CrdtConnection$ = CrdtConnection;

declare class Subscription extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>, id: number);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
  /** @deprecated */
  id: number;
}

export type Subscription$ = Subscription;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    label: string,
    signaling: $p2p_transport_js.Signaling$,
    ice_servers: _.List<$p2p_transport_js.IceServer$>,
    document: $crdt_core.Document$,
    transport: $option.Option$<$p2p_transport_js.Transport$>,
    peers: $dict.Dict$<string, Peer$>,
    subscriptions: _.List<Subscriber$>,
    next_subscription: number,
    on_status: (x0: Status$) => undefined,
    on_ready: (x0: _.Result<undefined, $p2p.P2pError$>) => undefined,
    readiness: $option.Option$<_.Result<undefined, $p2p.P2pError$>>,
    roster: boolean,
    bootstrap: BootstrapState$,
    deferred: _.List<Deferred$>,
    imported: boolean,
    attached: boolean,
    closed: boolean,
    policy: TransportPolicy$,
    sequencer: $option.Option$<SequencerConfig$>,
    relay: $option.Option$<$crdt_sequencer_js.Relay$>,
    phase: RelayPhase$,
    path: TransportPath$,
    published: string,
    resyncs: number,
    resync_timer: $option.Option$<() => undefined>,
    nudge_dirty: boolean,
    nudge_armed: boolean,
    nudge_timer: $option.Option$<() => undefined>,
    publish_owed: boolean,
    scheduler: $transport_js.Scheduler$,
    anti_entropy_interval_milliseconds: number,
    sync_armed: boolean,
    sync_timer: $option.Option$<() => undefined>,
    last_sync_digest: string,
    repairs: number,
    last_match: $option.Option$<string>,
    digest_cache: $transport_js.Cell$<DigestCache$>,
    deadline: $option.Option$<() => undefined>,
    recovered: boolean
  );
  /** @deprecated */
  label: string;
  /** @deprecated */
  signaling: $p2p_transport_js.Signaling$;
  /** @deprecated */
  ice_servers: _.List<$p2p_transport_js.IceServer$>;
  /** @deprecated */
  document: $crdt_core.Document$;
  /** @deprecated */
  transport: $option.Option$<$p2p_transport_js.Transport$>;
  /** @deprecated */
  peers: $dict.Dict$<string, Peer$>;
  /** @deprecated */
  subscriptions: _.List<Subscriber$>;
  /** @deprecated */
  next_subscription: number;
  /** @deprecated */
  on_status: (x0: Status$) => undefined;
  /** @deprecated */
  on_ready: (x0: _.Result<undefined, $p2p.P2pError$>) => undefined;
  /** @deprecated */
  readiness: $option.Option$<_.Result<undefined, $p2p.P2pError$>>;
  /** @deprecated */
  roster: boolean;
  /** @deprecated */
  bootstrap: BootstrapState$;
  /** @deprecated */
  deferred: _.List<Deferred$>;
  /** @deprecated */
  imported: boolean;
  /** @deprecated */
  attached: boolean;
  /** @deprecated */
  closed: boolean;
  /** @deprecated */
  policy: TransportPolicy$;
  /** @deprecated */
  sequencer: $option.Option$<SequencerConfig$>;
  /** @deprecated */
  relay: $option.Option$<$crdt_sequencer_js.Relay$>;
  /** @deprecated */
  phase: RelayPhase$;
  /** @deprecated */
  path: TransportPath$;
  /** @deprecated */
  published: string;
  /** @deprecated */
  resyncs: number;
  /** @deprecated */
  resync_timer: $option.Option$<() => undefined>;
  /** @deprecated */
  nudge_dirty: boolean;
  /** @deprecated */
  nudge_armed: boolean;
  /** @deprecated */
  nudge_timer: $option.Option$<() => undefined>;
  /** @deprecated */
  publish_owed: boolean;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  anti_entropy_interval_milliseconds: number;
  /** @deprecated */
  sync_armed: boolean;
  /** @deprecated */
  sync_timer: $option.Option$<() => undefined>;
  /** @deprecated */
  last_sync_digest: string;
  /** @deprecated */
  repairs: number;
  /** @deprecated */
  last_match: $option.Option$<string>;
  /** @deprecated */
  digest_cache: $transport_js.Cell$<DigestCache$>;
  /** @deprecated */
  deadline: $option.Option$<() => undefined>;
  /** @deprecated */
  recovered: boolean;
}

type State$ = State;

declare class DigestCache extends _.CustomType {
  /** @deprecated */
  constructor(
    taken_from: $option.Option$<$crdt_core.Document$>,
    value: string,
    computations: number
  );
  /** @deprecated */
  taken_from: $option.Option$<$crdt_core.Document$>;
  /** @deprecated */
  value: string;
  /** @deprecated */
  computations: number;
}

type DigestCache$ = DigestCache;

declare class RelayOff extends _.CustomType {}

declare class RelayOpening extends _.CustomType {}

declare class RelaySyncing extends _.CustomType {}

declare class RelayPrimaryPhase extends _.CustomType {}

declare class RelayUnsupportedPhase extends _.CustomType {}

type RelayPhase$ = RelayOff | RelayOpening | RelaySyncing | RelayPrimaryPhase | RelayUnsupportedPhase;

declare class Peer extends _.CustomType {
  /** @deprecated */
  constructor(id: string, greeted: boolean);
  /** @deprecated */
  id: string;
  /** @deprecated */
  greeted: boolean;
}

type Peer$ = Peer;

export class Joining extends _.CustomType {}
export function BootstrapState$Joining(): BootstrapState$;
export function BootstrapState$isJoining(value: any): value is BootstrapState$;

export class WaitingForState extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function BootstrapState$WaitingForState(
  peer_id: string,
): BootstrapState$;
export function BootstrapState$isWaitingForState(
  value: any,
): value is BootstrapState$;
export function BootstrapState$WaitingForState$0(value: BootstrapState$): string;
export function BootstrapState$WaitingForState$peer_id(
  value: BootstrapState$,
): string;

export class Bootstrapped extends _.CustomType {}
export function BootstrapState$Bootstrapped(): BootstrapState$;
export function BootstrapState$isBootstrapped(
  value: any,
): value is BootstrapState$;

export type BootstrapState$ = Joining | WaitingForState | Bootstrapped;

declare class DeferredOpen extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}

declare class DeferredDocument extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, payload: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  payload: string;
}

declare class DeferredClose extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}

type Deferred$ = DeferredOpen | DeferredDocument | DeferredClose;

declare class Subscriber extends _.CustomType {
  /** @deprecated */
  constructor(
    id: number,
    address: string,
    handler: (x0: $channel.ChannelEvent$) => undefined
  );
  /** @deprecated */
  id: number;
  /** @deprecated */
  address: string;
  /** @deprecated */
  handler: (x0: $channel.ChannelEvent$) => undefined;
}

type Subscriber$ = Subscriber;

export class Transport extends _.CustomType {
  /** @deprecated */
  constructor(status: $p2p_transport_js.Status$);
  /** @deprecated */
  status: $p2p_transport_js.Status$;
}
export function Status$Transport(status: $p2p_transport_js.Status$): Status$;
export function Status$isTransport(value: any): value is Status$;
export function Status$Transport$0(value: Status$): $p2p_transport_js.Status$;
export function Status$Transport$status(value: Status$): $p2p_transport_js.Status$;

export class TransportError extends _.CustomType {
  /** @deprecated */
  constructor(error: $p2p.P2pError$);
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function Status$TransportError(error: $p2p.P2pError$): Status$;
export function Status$isTransportError(value: any): value is Status$;
export function Status$TransportError$0(value: Status$): $p2p.P2pError$;
export function Status$TransportError$error(value: Status$): $p2p.P2pError$;

export class Joined extends _.CustomType {
  /** @deprecated */
  constructor(room: string, replica: string);
  /** @deprecated */
  room: string;
  /** @deprecated */
  replica: string;
}
export function Status$Joined(room: string, replica: string): Status$;
export function Status$isJoined(value: any): value is Status$;
export function Status$Joined$0(value: Status$): string;
export function Status$Joined$room(value: Status$): string;
export function Status$Joined$1(value: Status$): string;
export function Status$Joined$replica(value: Status$): string;

export class RosterKnown extends _.CustomType {
  /** @deprecated */
  constructor(peers: _.List<string>);
  /** @deprecated */
  peers: _.List<string>;
}
export function Status$RosterKnown(peers: _.List<string>): Status$;
export function Status$isRosterKnown(value: any): value is Status$;
export function Status$RosterKnown$0(value: Status$): _.List<string>;
export function Status$RosterKnown$peers(value: Status$): _.List<string>;

export class AwaitingState extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$AwaitingState(peer_id: string): Status$;
export function Status$isAwaitingState(value: any): value is Status$;
export function Status$AwaitingState$0(value: Status$): string;
export function Status$AwaitingState$peer_id(value: Status$): string;

export class Ready extends _.CustomType {}
export function Status$Ready(): Status$;
export function Status$isReady(value: any): value is Status$;

export class PeerReady extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$PeerReady(peer_id: string): Status$;
export function Status$isPeerReady(value: any): value is Status$;
export function Status$PeerReady$0(value: Status$): string;
export function Status$PeerReady$peer_id(value: Status$): string;

export class PeerGone extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string);
  /** @deprecated */
  peer_id: string;
}
export function Status$PeerGone(peer_id: string): Status$;
export function Status$isPeerGone(value: any): value is Status$;
export function Status$PeerGone$0(value: Status$): string;
export function Status$PeerGone$peer_id(value: Status$): string;

export class PeerRejected extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, error: $p2p.P2pError$);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function Status$PeerRejected(
  peer_id: string,
  error: $p2p.P2pError$,
): Status$;
export function Status$isPeerRejected(value: any): value is Status$;
export function Status$PeerRejected$0(value: Status$): string;
export function Status$PeerRejected$peer_id(value: Status$): string;
export function Status$PeerRejected$1(value: Status$): $p2p.P2pError$;
export function Status$PeerRejected$error(value: Status$): $p2p.P2pError$;

export class StateMerged extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, channels: number);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  channels: number;
}
export function Status$StateMerged(peer_id: string, channels: number): Status$;
export function Status$isStateMerged(value: any): value is Status$;
export function Status$StateMerged$0(value: Status$): string;
export function Status$StateMerged$peer_id(value: Status$): string;
export function Status$StateMerged$1(value: Status$): number;
export function Status$StateMerged$channels(value: Status$): number;

export class RejectedByPeer extends _.CustomType {
  /** @deprecated */
  constructor(peer_id: string, reason: string, detail: string);
  /** @deprecated */
  peer_id: string;
  /** @deprecated */
  reason: string;
  /** @deprecated */
  detail: string;
}
export function Status$RejectedByPeer(
  peer_id: string,
  reason: string,
  detail: string,
): Status$;
export function Status$isRejectedByPeer(value: any): value is Status$;
export function Status$RejectedByPeer$0(value: Status$): string;
export function Status$RejectedByPeer$peer_id(value: Status$): string;
export function Status$RejectedByPeer$1(value: Status$): string;
export function Status$RejectedByPeer$reason(value: Status$): string;
export function Status$RejectedByPeer$2(value: Status$): string;
export function Status$RejectedByPeer$detail(value: Status$): string;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(error: $p2p.P2pError$);
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function Status$Failed(error: $p2p.P2pError$): Status$;
export function Status$isFailed(value: any): value is Status$;
export function Status$Failed$0(value: Status$): $p2p.P2pError$;
export function Status$Failed$error(value: Status$): $p2p.P2pError$;

export class SubscriberFailed extends _.CustomType {
  /** @deprecated */
  constructor(address: string, detail: string);
  /** @deprecated */
  address: string;
  /** @deprecated */
  detail: string;
}
export function Status$SubscriberFailed(
  address: string,
  detail: string,
): Status$;
export function Status$isSubscriberFailed(value: any): value is Status$;
export function Status$SubscriberFailed$0(value: Status$): string;
export function Status$SubscriberFailed$address(value: Status$): string;
export function Status$SubscriberFailed$1(value: Status$): string;
export function Status$SubscriberFailed$detail(value: Status$): string;

export class RelayConnecting extends _.CustomType {
  /** @deprecated */
  constructor(url: string);
  /** @deprecated */
  url: string;
}
export function Status$RelayConnecting(url: string): Status$;
export function Status$isRelayConnecting(value: any): value is Status$;
export function Status$RelayConnecting$0(value: Status$): string;
export function Status$RelayConnecting$url(value: Status$): string;

export class RelayUnsupported extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Status$RelayUnsupported(detail: string): Status$;
export function Status$isRelayUnsupported(value: any): value is Status$;
export function Status$RelayUnsupported$0(value: Status$): string;
export function Status$RelayUnsupported$detail(value: Status$): string;

export class RelaySyncingStatus extends _.CustomType {}
export function Status$RelaySyncingStatus(): Status$;
export function Status$isRelaySyncingStatus(value: any): value is Status$;

export class RelayRecovering extends _.CustomType {}
export function Status$RelayRecovering(): Status$;
export function Status$isRelayRecovering(value: any): value is Status$;

export class RelayPrimary extends _.CustomType {
  /** @deprecated */
  constructor(digest: string);
  /** @deprecated */
  digest: string;
}
export function Status$RelayPrimary(digest: string): Status$;
export function Status$isRelayPrimary(value: any): value is Status$;
export function Status$RelayPrimary$0(value: Status$): string;
export function Status$RelayPrimary$digest(value: Status$): string;

export class RelayCheckpointRequested extends _.CustomType {}
export function Status$RelayCheckpointRequested(): Status$;
export function Status$isRelayCheckpointRequested(value: any): value is Status$;

export class RelayCheckpointed extends _.CustomType {
  /** @deprecated */
  constructor(digest: string);
  /** @deprecated */
  digest: string;
}
export function Status$RelayCheckpointed(digest: string): Status$;
export function Status$isRelayCheckpointed(value: any): value is Status$;
export function Status$RelayCheckpointed$0(value: Status$): string;
export function Status$RelayCheckpointed$digest(value: Status$): string;

export class RelayFallback extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function Status$RelayFallback(detail: string): Status$;
export function Status$isRelayFallback(value: any): value is Status$;
export function Status$RelayFallback$0(value: Status$): string;
export function Status$RelayFallback$detail(value: Status$): string;

export class RelayRetry extends _.CustomType {
  /** @deprecated */
  constructor(delay_milliseconds: number);
  /** @deprecated */
  delay_milliseconds: number;
}
export function Status$RelayRetry(delay_milliseconds: number): Status$;
export function Status$isRelayRetry(value: any): value is Status$;
export function Status$RelayRetry$0(value: Status$): number;
export function Status$RelayRetry$delay_milliseconds(value: Status$): number;

export class RelayRejected extends _.CustomType {
  /** @deprecated */
  constructor(from: string, error: $p2p.P2pError$);
  /** @deprecated */
  from: string;
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function Status$RelayRejected(
  from: string,
  error: $p2p.P2pError$,
): Status$;
export function Status$isRelayRejected(value: any): value is Status$;
export function Status$RelayRejected$0(value: Status$): string;
export function Status$RelayRejected$from(value: Status$): string;
export function Status$RelayRejected$1(value: Status$): $p2p.P2pError$;
export function Status$RelayRejected$error(value: Status$): $p2p.P2pError$;

export class RelayFailed extends _.CustomType {
  /** @deprecated */
  constructor(error: $p2p.P2pError$);
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function Status$RelayFailed(error: $p2p.P2pError$): Status$;
export function Status$isRelayFailed(value: any): value is Status$;
export function Status$RelayFailed$0(value: Status$): $p2p.P2pError$;
export function Status$RelayFailed$error(value: Status$): $p2p.P2pError$;

export type Status$ = Transport | TransportError | Joined | RosterKnown | AwaitingState | Ready | PeerReady | PeerGone | PeerRejected | StateMerged | RejectedByPeer | Failed | SubscriberFailed | RelayConnecting | RelayUnsupported | RelaySyncingStatus | RelayRecovering | RelayPrimary | RelayCheckpointRequested | RelayCheckpointed | RelayFallback | RelayRetry | RelayRejected | RelayFailed;

export type TextAnchor = $text_kernel.TextAnchor$;

export type Bias = $sequence.Bias$;

export const default_readiness_deadline_milliseconds: number;

export const default_anti_entropy_milliseconds: number;

export const bias_before: $sequence.Bias$;

export const bias_after: $sequence.Bias$;

export function sequencer(url: string): SequencerConfig$;

export function with_relay_driver(
  config: SequencerConfig$,
  driver: $crdt_sequencer_js.Driver$
): SequencerConfig$;

export function with_readiness_deadline_milliseconds(
  config: SequencerConfig$,
  deadline_milliseconds: number
): SequencerConfig$;

export function sequencer_url(config: SequencerConfig$): string;

export function config<BUUM>(
  room_id: string,
  replica_label: string,
  compatibility_tag: string,
  root: $p2p.CrdtKind$<BUUM>,
  signaling: $p2p_transport_js.Signaling$
): Config$<BUUM>;

export function with_transport_policy<BUUP>(
  config: Config$<BUUP>,
  policy: TransportPolicy$
): Config$<BUUP>;

export function with_sequencer<BUUS>(
  config: Config$<BUUS>,
  sequencer: SequencerConfig$
): Config$<BUUS>;

export function with_ice_servers<BUUV>(
  config: Config$<BUUV>,
  servers: _.List<$p2p_transport_js.IceServer$>
): Config$<BUUV>;

export function with_scheduler<BUUZ>(
  config: Config$<BUUZ>,
  scheduler: $transport_js.Scheduler$
): Config$<BUUZ>;

export function with_anti_entropy_interval_milliseconds<BUVC>(
  config: Config$<BUVC>,
  interval_milliseconds: number
): Config$<BUVC>;

export function config_room(config: Config$<any>): string;

export function config_compatibility(config: Config$<any>): string;

export function new_document<BUVL>(config: Config$<BUVL>): _.Result<
  CrdtDocument$<BUVL>,
  $p2p.P2pError$
>;

export function attach_with_rtc<BUWA>(
  document: CrdtDocument$<BUWA>,
  on_ready: (x0: _.Result<CrdtDocument$<BUWA>, $p2p.P2pError$>) => undefined,
  on_status: (x0: Status$) => undefined,
  rtc: $p2p_transport_js.Rtc$
): CrdtConnection$;

export function attach<BUVV>(
  document: CrdtDocument$<BUVV>,
  on_ready: (x0: _.Result<CrdtDocument$<BUVV>, $p2p.P2pError$>) => undefined,
  on_status: (x0: Status$) => undefined
): CrdtConnection$;

export function connect<BUVQ>(
  config: Config$<BUVQ>,
  on_ready: (x0: _.Result<CrdtDocument$<BUVQ>, $p2p.P2pError$>) => undefined,
  on_status: (x0: Status$) => undefined
): CrdtConnection$;

export function close(connection: CrdtConnection$): undefined;

export function subscribe(
  handle: Handle$<any>,
  handler: (x0: $channel.ChannelEvent$) => undefined
): Subscription$;

export function unsubscribe(subscription: Subscription$): undefined;

export function subscribe_pn_counter(
  handle: Handle$<$schema.PnCounterChannel$>,
  handler: (x0: $pn_counter_kernel.PnCounterEvent$) => undefined
): Subscription$;

export function subscribe_or_map(
  handle: Handle$<$schema.OrMapChannel$>,
  handler: (x0: $or_map_kernel.OrMapEvent$) => undefined
): Subscription$;

export function subscribe_or_set(
  handle: Handle$<$schema.OrSetChannel$>,
  handler: (x0: $or_set_kernel.OrSetEvent$) => undefined
): Subscription$;

export function subscribe_g_set(
  handle: Handle$<$schema.GSetChannel$>,
  handler: (x0: $g_set_kernel.GSetEvent$) => undefined
): Subscription$;

export function subscribe_two_p_set(
  handle: Handle$<$schema.TwoPSetChannel$>,
  handler: (x0: $two_p_set_kernel.TwoPSetEvent$) => undefined
): Subscription$;

export function subscribe_sequence(
  handle: Handle$<$schema.SequenceChannel$>,
  handler: (x0: $sequence_kernel.SequenceEvent$) => undefined
): Subscription$;

export function subscribe_text(
  handle: Handle$<$schema.TextChannel$>,
  handler: (x0: $text_kernel.TextEvent$) => undefined
): Subscription$;

export function root<BUZH>(document: CrdtDocument$<BUZH>): Handle$<BUZH>;

export function address(handle: Handle$<any>): string;

export function create_channel<BUZO>(
  document: CrdtDocument$<any>,
  kind: $p2p.CrdtKind$<BUZO>
): _.Result<Handle$<BUZO>, $p2p.P2pError$>;

export function resolve_channel<BUZV>(
  document: CrdtDocument$<any>,
  kind: $p2p.CrdtKind$<BUZV>,
  address: string
): _.Result<Handle$<BUZV>, $p2p.P2pError$>;

export function addresses(document: CrdtDocument$<any>): _.List<string>;

export function mv_register_set(
  handle: Handle$<$schema.MvRegisterChannel$>,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function mv_register_values(handle: Handle$<$schema.MvRegisterChannel$>): _.Result<
  _.List<string>,
  $p2p.P2pError$
>;

export function subscribe_mv_register(
  handle: Handle$<$schema.MvRegisterChannel$>,
  handler: (x0: $mv_register_kernel.MvRegisterEvent$) => undefined
): Subscription$;

export function lww_register_set(
  handle: Handle$<$schema.LwwRegisterChannel$>,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function lww_register_value(handle: Handle$<$schema.LwwRegisterChannel$>): _.Result<
  string,
  $p2p.P2pError$
>;

export function subscribe_lww_register(
  handle: Handle$<$schema.LwwRegisterChannel$>,
  handler: (x0: $lww_register_kernel.LwwRegisterEvent$) => undefined
): Subscription$;

export function lww_map_set(
  handle: Handle$<$schema.LwwMapChannel$>,
  key: string,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function lww_map_remove(
  handle: Handle$<$schema.LwwMapChannel$>,
  key: string
): _.Result<undefined, $p2p.P2pError$>;

export function lww_map_get(
  handle: Handle$<$schema.LwwMapChannel$>,
  key: string
): _.Result<_.Result<string, undefined>, $p2p.P2pError$>;

export function lww_map_entries(handle: Handle$<$schema.LwwMapChannel$>): _.Result<
  _.List<[string, string]>,
  $p2p.P2pError$
>;

export function lww_map_keys(handle: Handle$<$schema.LwwMapChannel$>): _.Result<
  _.List<string>,
  $p2p.P2pError$
>;

export function subscribe_lww_map(
  handle: Handle$<$schema.LwwMapChannel$>,
  handler: (x0: $lww_map_kernel.LwwMapEvent$) => undefined
): Subscription$;

export function g_counter_increment(
  handle: Handle$<$schema.GCounterChannel$>,
  amount: number
): _.Result<undefined, $p2p.P2pError$>;

export function g_counter_value(handle: Handle$<$schema.GCounterChannel$>): _.Result<
  number,
  $p2p.P2pError$
>;

export function subscribe_g_counter(
  handle: Handle$<$schema.GCounterChannel$>,
  handler: (x0: $g_counter_kernel.GCounterEvent$) => undefined
): Subscription$;

export function pn_counter_update(
  handle: Handle$<$schema.PnCounterChannel$>,
  amount: number
): _.Result<undefined, $p2p.P2pError$>;

export function pn_counter_increment(
  handle: Handle$<$schema.PnCounterChannel$>,
  amount: number
): _.Result<undefined, $p2p.P2pError$>;

export function pn_counter_decrement(
  handle: Handle$<$schema.PnCounterChannel$>,
  amount: number
): _.Result<undefined, $p2p.P2pError$>;

export function pn_counter_value(handle: Handle$<$schema.PnCounterChannel$>): _.Result<
  number,
  $p2p.P2pError$
>;

export function or_map_set(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_increment(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string,
  amount: number
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_set_mv_register(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_value(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string
): _.Result<_.Result<$or_map_kernel.OrMapValue$, undefined>, $p2p.P2pError$>;

export function or_map_values(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string
): _.Result<_.Result<_.List<string>, undefined>, $p2p.P2pError$>;

export function or_map_remove(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_add_member(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string,
  member: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_remove_member(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string,
  member: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_remove_key(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_map_tally(
  handle: Handle$<$schema.OrMapChannel$>,
  key: string
): _.Result<number, $p2p.P2pError$>;

export function or_map_entries(handle: Handle$<$schema.OrMapChannel$>): _.Result<
  _.List<[string, $or_map_kernel.OrMapValue$]>,
  $p2p.P2pError$
>;

export function or_set_add(
  handle: Handle$<$schema.OrSetChannel$>,
  element: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_set_remove(
  handle: Handle$<$schema.OrSetChannel$>,
  element: string
): _.Result<undefined, $p2p.P2pError$>;

export function or_set_contains(
  handle: Handle$<$schema.OrSetChannel$>,
  element: string
): _.Result<boolean, $p2p.P2pError$>;

export function or_set_values(handle: Handle$<$schema.OrSetChannel$>): _.Result<
  _.List<string>,
  $p2p.P2pError$
>;

export function g_set_add(
  handle: Handle$<$schema.GSetChannel$>,
  element: string
): _.Result<undefined, $p2p.P2pError$>;

export function g_set_contains(
  handle: Handle$<$schema.GSetChannel$>,
  element: string
): _.Result<boolean, $p2p.P2pError$>;

export function g_set_values(handle: Handle$<$schema.GSetChannel$>): _.Result<
  _.List<string>,
  $p2p.P2pError$
>;

export function two_p_set_add(
  handle: Handle$<$schema.TwoPSetChannel$>,
  element: string
): _.Result<undefined, $p2p.P2pError$>;

export function two_p_set_remove(
  handle: Handle$<$schema.TwoPSetChannel$>,
  element: string
): _.Result<undefined, $p2p.P2pError$>;

export function two_p_set_contains(
  handle: Handle$<$schema.TwoPSetChannel$>,
  element: string
): _.Result<boolean, $p2p.P2pError$>;

export function two_p_set_values(handle: Handle$<$schema.TwoPSetChannel$>): _.Result<
  _.List<string>,
  $p2p.P2pError$
>;

export function sequence_insert(
  handle: Handle$<$schema.SequenceChannel$>,
  index: number,
  value: $json.Json$
): _.Result<undefined, $p2p.P2pError$>;

export function sequence_delete(
  handle: Handle$<$schema.SequenceChannel$>,
  index: number
): _.Result<undefined, $p2p.P2pError$>;

export function sequence_move(
  handle: Handle$<$schema.SequenceChannel$>,
  from: number,
  to: number
): _.Result<undefined, $p2p.P2pError$>;

export function sequence_replace(
  handle: Handle$<$schema.SequenceChannel$>,
  index: number,
  value: $json.Json$
): _.Result<undefined, $p2p.P2pError$>;

export function sequence_values(handle: Handle$<$schema.SequenceChannel$>): _.Result<
  _.List<$json.Json$>,
  $p2p.P2pError$
>;

export function text_insert(
  handle: Handle$<$schema.TextChannel$>,
  index: number,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function text_delete_range(
  handle: Handle$<$schema.TextChannel$>,
  start: number,
  end: number
): _.Result<undefined, $p2p.P2pError$>;

export function text_replace_range(
  handle: Handle$<$schema.TextChannel$>,
  start: number,
  end: number,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function text_append(
  handle: Handle$<$schema.TextChannel$>,
  value: string
): _.Result<undefined, $p2p.P2pError$>;

export function text_value(handle: Handle$<$schema.TextChannel$>): _.Result<
  string,
  $p2p.P2pError$
>;

export function text_length(handle: Handle$<$schema.TextChannel$>): _.Result<
  number,
  $p2p.P2pError$
>;

export function text_anchor_at(
  handle: Handle$<$schema.TextChannel$>,
  index: number,
  bias: $sequence.Bias$
): _.Result<$text_kernel.TextAnchor$, $p2p.P2pError$>;

export function text_resolve_anchor(
  handle: Handle$<$schema.TextChannel$>,
  anchor: $text_kernel.TextAnchor$
): _.Result<number, $p2p.P2pError$>;

export function text_start_anchor(): $text_kernel.TextAnchor$;

export function text_end_anchor(): $text_kernel.TextAnchor$;

export function text_anchor_to_json(anchor: $text_kernel.TextAnchor$): $json.Json$;

export function text_anchor_from_json(json_string: string): _.Result<
  $text_kernel.TextAnchor$,
  $p2p.P2pError$
>;

export function export_snapshot(document: CrdtDocument$<any>): _.Result<
  $json.Json$,
  $p2p.P2pError$
>;

export function merge_snapshot(
  document: CrdtDocument$<any>,
  snapshot: $json.Json$
): _.Result<$crdt_core.Outcome$, $p2p.P2pError$>;

export function import_snapshot<BVHW>(
  config: Config$<BVHW>,
  snapshot: $json.Json$
): _.Result<CrdtDocument$<BVHW>, $p2p.P2pError$>;

export function room(document: CrdtDocument$<any>): string;

export function room_id(document: CrdtDocument$<any>): string;

export function compatibility_tag(document: CrdtDocument$<any>): string;

export function replica_id(document: CrdtDocument$<any>): string;

export function replica_label(document: CrdtDocument$<any>): string;

export function digest(document: CrdtDocument$<any>): string;

export function digest_computations(document: CrdtDocument$<any>): number;

export function peers(document: CrdtDocument$<any>): _.List<string>;

export function peer_count(document: CrdtDocument$<any>): number;

export function bootstrap_state(document: CrdtDocument$<any>): BootstrapState$;

export function repair_count(document: CrdtDocument$<any>): number;

export function last_digest_match(document: CrdtDocument$<any>): $option.Option$<
  string
>;

export function readiness(document: CrdtDocument$<any>): $option.Option$<
  _.Result<undefined, $p2p.P2pError$>
>;

export function readiness_resolved(document: CrdtDocument$<any>): boolean;

export function is_closed(document: CrdtDocument$<any>): boolean;

export function policy(document: CrdtDocument$<any>): TransportPolicy$;

export function effective_path(document: CrdtDocument$<any>): TransportPath$;

export function relay_is_primary(document: CrdtDocument$<any>): boolean;

export function relay_attached_lane(document: CrdtDocument$<any>): boolean;

export function describe_error(error: $p2p.P2pError$): string;
