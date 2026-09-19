import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt_signaling from "../watershed/crdt_signaling.d.mts";
import type * as $p2p_transport_js from "../watershed/p2p_transport_js.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export type NativeSocket$ = any;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    socket: $option.Option$<NativeSocket$>,
    deadline: $option.Option$<$transport_js.TimerId$>,
    roster: boolean,
    failed: boolean,
    closed: boolean
  );
  /** @deprecated */
  socket: $option.Option$<NativeSocket$>;
  /** @deprecated */
  deadline: $option.Option$<$transport_js.TimerId$>;
  /** @deprecated */
  roster: boolean;
  /** @deprecated */
  failed: boolean;
  /** @deprecated */
  closed: boolean;
}

type State$ = State;

export const default_roster_timeout_milliseconds: number;

export function websocket_signaling_with_timeout(
  url: string,
  on_failure: (x0: string) => undefined,
  roster_timeout_milliseconds: number
): $p2p_transport_js.Signaling$;

export function websocket_signaling(
  url: string,
  on_failure: (x0: string) => undefined
): $p2p_transport_js.Signaling$;
