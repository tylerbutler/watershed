import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt_relay from "../watershed/crdt_relay.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export class Connection extends _.CustomType {
  /** @deprecated */
  constructor(send: (x0: string) => boolean, close: () => undefined);
  /** @deprecated */
  send: (x0: string) => boolean;
  /** @deprecated */
  close: () => undefined;
}
export function Connection$Connection(
  send: (x0: string) => boolean,
  close: () => undefined,
): Connection$;
export function Connection$isConnection(value: any): value is Connection$;
export function Connection$Connection$0(value: Connection$): (x0: string) => boolean;
export function Connection$Connection$send(
  value: Connection$,
): (x0: string) => boolean;
export function Connection$Connection$1(value: Connection$): () => undefined;
export function Connection$Connection$close(value: Connection$): () => undefined;

export type Connection$ = Connection;

export class RelayClosed extends _.CustomType {}
export function SendError$RelayClosed(): SendError$;
export function SendError$isRelayClosed(value: any): value is SendError$;

export class RelayNotReady extends _.CustomType {}
export function SendError$RelayNotReady(): SendError$;
export function SendError$isRelayNotReady(value: any): value is SendError$;

export class SendFailed extends _.CustomType {}
export function SendError$SendFailed(): SendError$;
export function SendError$isSendFailed(value: any): value is SendError$;

export type SendError$ = RelayClosed | RelayNotReady | SendFailed;

export class Handlers extends _.CustomType {
  /** @deprecated */
  constructor(
    on_message: (x0: string) => undefined,
    on_close: (x0: string) => undefined
  );
  /** @deprecated */
  on_message: (x0: string) => undefined;
  /** @deprecated */
  on_close: (x0: string) => undefined;
}
export function Handlers$Handlers(
  on_message: (x0: string) => undefined,
  on_close: (x0: string) => undefined,
): Handlers$;
export function Handlers$isHandlers(value: any): value is Handlers$;
export function Handlers$Handlers$0(value: Handlers$): (x0: string) => undefined;
export function Handlers$Handlers$on_message(
  value: Handlers$,
): (x0: string) => undefined;
export function Handlers$Handlers$1(value: Handlers$): (x0: string) => undefined;
export function Handlers$Handlers$on_close(
  value: Handlers$,
): (x0: string) => undefined;

export type Handlers$ = Handlers;

export class Driver extends _.CustomType {
  /** @deprecated */
  constructor(
    open: (x0: string, x1: Handlers$) => _.Result<Connection$, string>
  );
  /** @deprecated */
  open: (x0: string, x1: Handlers$) => _.Result<Connection$, string>;
}
export function Driver$Driver(
  open: (x0: string, x1: Handlers$) => _.Result<Connection$, string>,
): Driver$;
export function Driver$isDriver(value: any): value is Driver$;
export function Driver$Driver$0(value: Driver$): (x0: string, x1: Handlers$) => _.Result<
  Connection$,
  string
>;
export function Driver$Driver$open(value: Driver$): (x0: string, x1: Handlers$) => _.Result<
  Connection$,
  string
>;

export type Driver$ = Driver;

declare class DriverMessage extends _.CustomType {
  /** @deprecated */
  constructor(raw: string);
  /** @deprecated */
  raw: string;
}

declare class DriverClosed extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}

type DriverEvent$ = DriverMessage | DriverClosed;

export type NativeSocket$ = any;

export class Events extends _.CustomType {
  /** @deprecated */
  constructor(
    on_connecting: () => undefined,
    on_ready: () => undefined,
    on_envelope: (x0: string) => boolean,
    on_synced: () => undefined,
    on_attested: (x0: string) => undefined,
    on_checkpoint_requested: () => undefined,
    on_unsupported: (x0: string) => undefined,
    on_dropped: (x0: string) => undefined,
    on_retry: (x0: number) => undefined,
    on_error: (x0: $p2p.P2pError$) => undefined
  );
  /** @deprecated */
  on_connecting: () => undefined;
  /** @deprecated */
  on_ready: () => undefined;
  /** @deprecated */
  on_envelope: (x0: string) => boolean;
  /** @deprecated */
  on_synced: () => undefined;
  /** @deprecated */
  on_attested: (x0: string) => undefined;
  /** @deprecated */
  on_checkpoint_requested: () => undefined;
  /** @deprecated */
  on_unsupported: (x0: string) => undefined;
  /** @deprecated */
  on_dropped: (x0: string) => undefined;
  /** @deprecated */
  on_retry: (x0: number) => undefined;
  /** @deprecated */
  on_error: (x0: $p2p.P2pError$) => undefined;
}
export function Events$Events(
  on_connecting: () => undefined,
  on_ready: () => undefined,
  on_envelope: (x0: string) => boolean,
  on_synced: () => undefined,
  on_attested: (x0: string) => undefined,
  on_checkpoint_requested: () => undefined,
  on_unsupported: (x0: string) => undefined,
  on_dropped: (x0: string) => undefined,
  on_retry: (x0: number) => undefined,
  on_error: (x0: $p2p.P2pError$) => undefined,
): Events$;
export function Events$isEvents(value: any): value is Events$;
export function Events$Events$0(value: Events$): () => undefined;
export function Events$Events$on_connecting(value: Events$): () => undefined;
export function Events$Events$1(value: Events$): () => undefined;
export function Events$Events$on_ready(value: Events$): () => undefined;
export function Events$Events$2(value: Events$): (x0: string) => boolean;
export function Events$Events$on_envelope(value: Events$): (x0: string) => boolean;
export function Events$Events$3(
  value: Events$,
): () => undefined;
export function Events$Events$on_synced(value: Events$): () => undefined;
export function Events$Events$4(value: Events$): (x0: string) => undefined;
export function Events$Events$on_attested(value: Events$): (x0: string) => undefined;
export function Events$Events$5(
  value: Events$,
): () => undefined;
export function Events$Events$on_checkpoint_requested(value: Events$): () => undefined;
export function Events$Events$6(
  value: Events$,
): (x0: string) => undefined;
export function Events$Events$on_unsupported(value: Events$): (x0: string) => undefined;
export function Events$Events$7(
  value: Events$,
): (x0: string) => undefined;
export function Events$Events$on_dropped(value: Events$): (x0: string) => undefined;
export function Events$Events$8(
  value: Events$,
): (x0: number) => undefined;
export function Events$Events$on_retry(value: Events$): (x0: number) => undefined;
export function Events$Events$9(
  value: Events$,
): (x0: $p2p.P2pError$) => undefined;
export function Events$Events$on_error(value: Events$): (x0: $p2p.P2pError$) => undefined;

export type Events$ = Events;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    url: string,
    driver: Driver$,
    scheduler: $transport_js.Scheduler$,
    retry: boolean,
    events: Events$,
    connection: $option.Option$<Connection$>,
    generation: number,
    attempt: number,
    pending: $option.Option$<() => undefined>,
    ready: boolean,
    order: number,
    stalled: boolean,
    skipped: _.List<number>,
    skips: number,
    closed: boolean
  );
  /** @deprecated */
  url: string;
  /** @deprecated */
  driver: Driver$;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  retry: boolean;
  /** @deprecated */
  events: Events$;
  /** @deprecated */
  connection: $option.Option$<Connection$>;
  /** @deprecated */
  generation: number;
  /** @deprecated */
  attempt: number;
  /** @deprecated */
  pending: $option.Option$<() => undefined>;
  /** @deprecated */
  ready: boolean;
  /** @deprecated */
  order: number;
  /** @deprecated */
  stalled: boolean;
  /** @deprecated */
  skipped: _.List<number>;
  /** @deprecated */
  skips: number;
  /** @deprecated */
  closed: boolean;
}

type State$ = State;

declare class Relay extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$>);
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
}

export type Relay$ = Relay;

export const max_reported_skips: number;

export function native_driver(): Driver$;

export function backoff_milliseconds(attempt: number): number;

export function start(
  url: string,
  driver: Driver$,
  scheduler: $transport_js.Scheduler$,
  events: Events$
): Relay$;

export function connect(relay: Relay$): undefined;

export function close(relay: Relay$): undefined;

export function healthy(relay: Relay$): undefined;

export function send_envelope(relay: Relay$, payload: string): _.Result<
  undefined,
  SendError$
>;

export function attest(relay: Relay$, digest: string): _.Result<
  undefined,
  SendError$
>;

export function declare_support(relay: Relay$): _.Result<undefined, SendError$>;

export function abort(relay: Relay$, detail: string): undefined;

export function is_ready(relay: Relay$): boolean;

export function is_closed(relay: Relay$): boolean;

export function last_order(relay: Relay$): number;

export function skipped_orders(relay: Relay$): _.List<number>;

export function skip_count(relay: Relay$): number;

export function attempts(relay: Relay$): number;

export function is_retrying(relay: Relay$): boolean;
