import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $p2p_transport_js from "../watershed/p2p_transport_js.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export type Pool$ = any;

declare class Hello extends _.CustomType {
  /** @deprecated */
  constructor(from: string);
  /** @deprecated */
  from: string;
}

declare class Ack extends _.CustomType {
  /** @deprecated */
  constructor(from: string, to: string);
  /** @deprecated */
  from: string;
  /** @deprecated */
  to: string;
}

declare class Bye extends _.CustomType {
  /** @deprecated */
  constructor(from: string);
  /** @deprecated */
  from: string;
}

declare class Forward extends _.CustomType {
  /** @deprecated */
  constructor(
    from: string,
    to: string,
    payload: $p2p_transport_js.SignalPayload$
  );
  /** @deprecated */
  from: string;
  /** @deprecated */
  to: string;
  /** @deprecated */
  payload: $p2p_transport_js.SignalPayload$;
}

type Frame$ = Hello | Ack | Bye | Forward;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    pool: $option.Option$<Pool$>,
    seen: $set.Set$<string>,
    window: $option.Option$<$transport_js.TimerId$>,
    backstop: $option.Option$<$transport_js.TimerId$>,
    roster: boolean,
    failed: boolean,
    closed: boolean
  );
  /** @deprecated */
  pool: $option.Option$<Pool$>;
  /** @deprecated */
  seen: $set.Set$<string>;
  /** @deprecated */
  window: $option.Option$<$transport_js.TimerId$>;
  /** @deprecated */
  backstop: $option.Option$<$transport_js.TimerId$>;
  /** @deprecated */
  roster: boolean;
  /** @deprecated */
  failed: boolean;
  /** @deprecated */
  closed: boolean;
}

type State$ = State;

export const default_roster_timeout_milliseconds: number;

export const default_roster_window_milliseconds: number;

export const default_relays: _.List<string>;

export function nostr_signaling_with_timing(
  relays: _.List<string>,
  on_failure: (x0: string) => undefined,
  roster_window_milliseconds: number,
  roster_timeout_milliseconds: number
): $p2p_transport_js.Signaling$;

export function nostr_signaling(
  relays: _.List<string>,
  on_failure: (x0: string) => undefined
): $p2p_transport_js.Signaling$;
