import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class Auto extends _.CustomType {}
export function Mode$Auto(): Mode$;
export function Mode$isAuto(value: any): value is Mode$;

export class Server extends _.CustomType {}
export function Mode$Server(): Mode$;
export function Mode$isServer(value: any): value is Mode$;

export class Ripple extends _.CustomType {}
export function Mode$Ripple(): Mode$;
export function Mode$isRipple(value: any): value is Mode$;

export type Mode$ = Auto | Server | Ripple;

declare class Config<BYVK> extends _.CustomType {
  /** @deprecated */
  constructor(
    encode: (x0: BYVK) => $json.Json$,
    decode: $decode.Decoder$<BYVK>,
    mode: Mode$,
    heartbeat_milliseconds: number,
    ttl_milliseconds: number
  );
  /** @deprecated */
  encode: (x0: BYVK) => $json.Json$;
  /** @deprecated */
  decode: $decode.Decoder$<BYVK>;
  /** @deprecated */
  mode: Mode$;
  /** @deprecated */
  heartbeat_milliseconds: number;
  /** @deprecated */
  ttl_milliseconds: number;
}

export type Config$<BYVK> = Config<BYVK>;

export class PresenceEntry<BYVL> extends _.CustomType {
  /** @deprecated */
  constructor(session_id: string, key: string, meta: BYVL);
  /** @deprecated */
  session_id: string;
  /** @deprecated */
  key: string;
  /** @deprecated */
  meta: BYVL;
}
export function PresenceEntry$PresenceEntry<BYVL>(
  session_id: string,
  key: string,
  meta: BYVL,
): PresenceEntry$<BYVL>;
export function PresenceEntry$isPresenceEntry<BYVL>(
  value: any,
): value is PresenceEntry$<unknown>;
export function PresenceEntry$PresenceEntry$0<BYVL>(value: PresenceEntry$<BYVL>): string;
export function PresenceEntry$PresenceEntry$session_id<BYVL>(
  value: PresenceEntry$<BYVL>,
): string;
export function PresenceEntry$PresenceEntry$1<BYVL>(value: PresenceEntry$<BYVL>): string;
export function PresenceEntry$PresenceEntry$key<BYVL>(
  value: PresenceEntry$<BYVL>,
): string;
export function PresenceEntry$PresenceEntry$2<BYVL>(value: PresenceEntry$<BYVL>): BYVL;
export function PresenceEntry$PresenceEntry$meta<BYVL>(
  value: PresenceEntry$<BYVL>,
): BYVL;

export type PresenceEntry$<BYVL> = PresenceEntry<BYVL>;

declare class Tracked<BYVM> extends _.CustomType {
  /** @deprecated */
  constructor(phx_ref: string, session_id: string, key: string, meta: BYVM);
  /** @deprecated */
  phx_ref: string;
  /** @deprecated */
  session_id: string;
  /** @deprecated */
  key: string;
  /** @deprecated */
  meta: BYVM;
}

type Tracked$<BYVM> = Tracked<BYVM>;

export class Dropped extends _.CustomType {
  /** @deprecated */
  constructor(key: string, session_id: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  session_id: string;
}
export function Dropped$Dropped(key: string, session_id: string): Dropped$;
export function Dropped$isDropped(value: any): value is Dropped$;
export function Dropped$Dropped$0(value: Dropped$): string;
export function Dropped$Dropped$key(value: Dropped$): string;
export function Dropped$Dropped$1(value: Dropped$): string;
export function Dropped$Dropped$session_id(value: Dropped$): string;

export type Dropped$ = Dropped;

declare class Diff<BYVN> extends _.CustomType {
  /** @deprecated */
  constructor(
    joins: _.List<Tracked$<BYVN>>,
    leaves: _.List<Tracked$<BYVN>>,
    dropped: _.List<Dropped$>
  );
  /** @deprecated */
  joins: _.List<Tracked$<BYVN>>;
  /** @deprecated */
  leaves: _.List<Tracked$<BYVN>>;
  /** @deprecated */
  dropped: _.List<Dropped$>;
}

export type Diff$<BYVN> = Diff<BYVN>;

declare class Snapshot<BYVO> extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<Tracked$<BYVO>>, dropped: _.List<Dropped$>);
  /** @deprecated */
  entries: _.List<Tracked$<BYVO>>;
  /** @deprecated */
  dropped: _.List<Dropped$>;
}

export type Snapshot$<BYVO> = Snapshot<BYVO>;

export class State<BYVP> extends _.CustomType {
  /** @deprecated */
  constructor(entries: _.List<PresenceEntry$<BYVP>>);
  /** @deprecated */
  entries: _.List<PresenceEntry$<BYVP>>;
}
export function Event$State<BYVP>(
  entries: _.List<PresenceEntry$<BYVP>>,
): Event$<BYVP>;
export function Event$isState<BYVP>(value: any): value is Event$<unknown>;
export function Event$State$0<BYVP>(value: Event$<BYVP>): _.List<
  PresenceEntry$<BYVP>
>;
export function Event$State$entries<BYVP>(value: Event$<BYVP>): _.List<
  PresenceEntry$<BYVP>
>;

export class Changed<BYVP> extends _.CustomType {
  /** @deprecated */
  constructor(diff: Diff$<BYVP>, entries: _.List<PresenceEntry$<BYVP>>);
  /** @deprecated */
  diff: Diff$<BYVP>;
  /** @deprecated */
  entries: _.List<PresenceEntry$<BYVP>>;
}
export function Event$Changed<BYVP>(
  diff: Diff$<BYVP>,
  entries: _.List<PresenceEntry$<BYVP>>,
): Event$<BYVP>;
export function Event$isChanged<BYVP>(value: any): value is Event$<unknown>;
export function Event$Changed$0<BYVP>(value: Event$<BYVP>): Diff$<BYVP>;
export function Event$Changed$diff<BYVP>(value: Event$<BYVP>): Diff$<BYVP>;
export function Event$Changed$1<BYVP>(value: Event$<BYVP>): _.List<
  PresenceEntry$<BYVP>
>;
export function Event$Changed$entries<BYVP>(value: Event$<BYVP>): _.List<
  PresenceEntry$<BYVP>
>;

export class Failed extends _.CustomType {
  /** @deprecated */
  constructor(error: PresenceError$);
  /** @deprecated */
  error: PresenceError$;
}
export function Event$Failed<BYVP>(error: PresenceError$): Event$<BYVP>;
export function Event$isFailed<BYVP>(value: any): value is Event$<unknown>;
export function Event$Failed$0<BYVP>(value: Event$<BYVP>): PresenceError$;
export function Event$Failed$error<BYVP>(value: Event$<BYVP>): PresenceError$;

export type Event$<BYVP> = State<BYVP> | Changed<BYVP> | Failed;

export class UnsupportedPresence extends _.CustomType {}
export function PresenceError$UnsupportedPresence(): PresenceError$;
export function PresenceError$isUnsupportedPresence(
  value: any,
): value is PresenceError$;

export class Rejected extends _.CustomType {
  /** @deprecated */
  constructor(code: string, message: string);
  /** @deprecated */
  code: string;
  /** @deprecated */
  message: string;
}
export function PresenceError$Rejected(
  code: string,
  message: string,
): PresenceError$;
export function PresenceError$isRejected(value: any): value is PresenceError$;
export function PresenceError$Rejected$0(value: PresenceError$): string;
export function PresenceError$Rejected$code(value: PresenceError$): string;
export function PresenceError$Rejected$1(value: PresenceError$): string;
export function PresenceError$Rejected$message(value: PresenceError$): string;

export class DecodeFailed extends _.CustomType {
  /** @deprecated */
  constructor(key: string, session_id: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  session_id: string;
}
export function PresenceError$DecodeFailed(
  key: string,
  session_id: string,
): PresenceError$;
export function PresenceError$isDecodeFailed(
  value: any,
): value is PresenceError$;
export function PresenceError$DecodeFailed$0(value: PresenceError$): string;
export function PresenceError$DecodeFailed$key(value: PresenceError$): string;
export function PresenceError$DecodeFailed$1(value: PresenceError$): string;
export function PresenceError$DecodeFailed$session_id(value: PresenceError$): string;

export type PresenceError$ = UnsupportedPresence | Rejected | DecodeFailed;

declare class Tracker<BYVQ> extends _.CustomType {
  /** @deprecated */
  constructor(
    entries: $option.Option$<$dict.Dict$<string, Tracked$<BYVQ>>>,
    pending: _.List<Diff$<BYVQ>>
  );
  /** @deprecated */
  entries: $option.Option$<$dict.Dict$<string, Tracked$<BYVQ>>>;
  /** @deprecated */
  pending: _.List<Diff$<BYVQ>>;
}

export type Tracker$<BYVQ> = Tracker<BYVQ>;

declare class Sessions<BYVR> extends _.CustomType {
  /** @deprecated */
  constructor(entries: $dict.Dict$<string, Live$<BYVR>>);
  /** @deprecated */
  entries: $dict.Dict$<string, Live$<BYVR>>;
}

export type Sessions$<BYVR> = Sessions<BYVR>;

declare class Live<BYVS> extends _.CustomType {
  /** @deprecated */
  constructor(key: string, meta: BYVS, last_seen: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  meta: BYVS;
  /** @deprecated */
  last_seen: number;
}

type Live$<BYVS> = Live<BYVS>;

export const reserved_meta_fields: _.List<string>;

export const ripple_type: string;

export const event_join: string;

export const event_update: string;

export const event_leave: string;

export const event_state: string;

export const event_diff: string;

export const event_error: string;

export function config<BYVT>(
  encode: (x0: BYVT) => $json.Json$,
  decode: $decode.Decoder$<BYVT>
): Config$<BYVT>;

export function with_mode<BYVW>(config: Config$<BYVW>, mode: Mode$): Config$<
  BYVW
>;

export function with_ripple_timing<BYVZ>(
  config: Config$<BYVZ>,
  heartbeat_milliseconds: number,
  ttl_milliseconds: number
): Config$<BYVZ>;

export function config_mode(config: Config$<any>): Mode$;

export function config_encode<BYWE>(config: Config$<BYWE>): (x0: BYWE) => $json.Json$;

export function config_decoder<BYWG>(config: Config$<BYWG>): $decode.Decoder$<
  BYWG
>;

export function config_heartbeat_milliseconds(config: Config$<any>): number;

export function config_ttl_milliseconds(config: Config$<any>): number;

export function diff_joins<BYWN>(diff: Diff$<BYWN>): _.List<
  PresenceEntry$<BYWN>
>;

export function diff_leaves<BYWR>(diff: Diff$<BYWR>): _.List<
  PresenceEntry$<BYWR>
>;

export function diff_is_empty(diff: Diff$<any>): boolean;

export function by_key<BYWX>(entries: _.List<PresenceEntry$<BYWX>>, key: string): _.List<
  PresenceEntry$<BYWX>
>;

export function remote_entries<BYXC>(
  entries: _.List<PresenceEntry$<BYXC>>,
  local_session: string
): _.List<PresenceEntry$<BYXC>>;

export function tracker(): Tracker$<any>;

export function reset<BYXJ>(x0: Tracker$<BYXJ>): Tracker$<BYXJ>;

export function is_synced(tracker: Tracker$<any>): boolean;

export function tracker_entries<BYXO>(tracker: Tracker$<BYXO>): _.List<
  PresenceEntry$<BYXO>
>;

export function apply_diff<BYXY>(tracker: Tracker$<BYXY>, diff: Diff$<BYXY>): [
  Tracker$<BYXY>,
  _.List<Event$<BYXY>>
];

export function apply_state<BYXS>(
  tracker: Tracker$<BYXS>,
  snapshot: Snapshot$<BYXS>
): [Tracker$<BYXS>, _.List<Event$<BYXS>>];

export function sessions(): Sessions$<any>;

export function no_change(): Diff$<any>;

export function observe_session<BYYI>(
  sessions: Sessions$<BYYI>,
  session_id: string,
  key: string,
  meta: BYYI,
  now: number
): [Sessions$<BYYI>, Diff$<BYYI>];

export function expire_sessions<BYYM>(
  sessions: Sessions$<BYYM>,
  ttl_milliseconds: number,
  now: number
): [Sessions$<BYYM>, Diff$<BYYM>];

export function forget_session<BYYQ>(
  sessions: Sessions$<BYYQ>,
  session_id: string
): [Sessions$<BYYQ>, Diff$<BYYQ>];

export function session_entries<BYYU>(sessions: Sessions$<BYYU>): _.List<
  PresenceEntry$<BYYU>
>;

export function encode_command<BYYY>(
  encode: (x0: BYYY) => $json.Json$,
  meta: BYYY
): $json.Json$;

export function encode_leave(): $json.Json$;

export function presence_state_decoder<BYYZ>(meta: $decode.Decoder$<BYYZ>): $decode.Decoder$<
  Snapshot$<BYYZ>
>;

export function presence_diff_decoder<BYZD>(meta: $decode.Decoder$<BYZD>): $decode.Decoder$<
  Diff$<BYZD>
>;

export function presence_error_decoder(): $decode.Decoder$<PresenceError$>;

export function encode_ripple<BYZI>(
  key: string,
  encode: (x0: BYZI) => $json.Json$,
  meta: BYZI
): $json.Json$;

export function ripple_decoder<BYZJ>(meta: $decode.Decoder$<BYZJ>): $decode.Decoder$<
  [string, BYZJ]
>;

export function color_for(user: string): string;

export function short_name(user: string): string;
