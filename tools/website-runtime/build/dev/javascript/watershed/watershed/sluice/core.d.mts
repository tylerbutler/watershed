import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $set from "../../../gleam_stdlib/gleam/set.d.mts";
import type * as $sequencing from "../../../spillway/spillway/sequencing.d.mts";
import type * as $types from "../../../spillway/spillway/types.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $frame from "../../watershed/sluice/frame.d.mts";

export class Outbound extends _.CustomType {
  /** @deprecated */
  constructor(client_id: string, event: string, payload: $json.Json$);
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  event: string;
  /** @deprecated */
  payload: $json.Json$;
}
export function Outbound$Outbound(
  client_id: string,
  event: string,
  payload: $json.Json$,
): Outbound$;
export function Outbound$isOutbound(value: any): value is Outbound$;
export function Outbound$Outbound$0(value: Outbound$): string;
export function Outbound$Outbound$client_id(value: Outbound$): string;
export function Outbound$Outbound$1(value: Outbound$): string;
export function Outbound$Outbound$event(value: Outbound$): string;
export function Outbound$Outbound$2(value: Outbound$): $json.Json$;
export function Outbound$Outbound$payload(value: Outbound$): $json.Json$;

export type Outbound$ = Outbound;

declare class ClientEntry extends _.CustomType {
  /** @deprecated */
  constructor(client: $types.Client$, scopes: _.List<string>);
  /** @deprecated */
  client: $types.Client$;
  /** @deprecated */
  scopes: _.List<string>;
}

type ClientEntry$ = ClientEntry;

declare class Sluice extends _.CustomType {
  /** @deprecated */
  constructor(
    document_id: string,
    tenant_id: string,
    sequence_state: $sequencing.SequenceState$,
    log: _.List<$frame.Sequenced$>,
    clients: $dict.Dict$<string, ClientEntry$>,
    presence: $dict.Dict$<string, $frame.PresenceMeta$>,
    next_presence_ref: number,
    presence_supported: boolean,
    paused: $set.Set$<string>,
    next_client_number: number,
    now_milliseconds: number,
    outbox: _.List<Outbound$>
  );
  /** @deprecated */
  document_id: string;
  /** @deprecated */
  tenant_id: string;
  /** @deprecated */
  sequence_state: $sequencing.SequenceState$;
  /** @deprecated */
  log: _.List<$frame.Sequenced$>;
  /** @deprecated */
  clients: $dict.Dict$<string, ClientEntry$>;
  /** @deprecated */
  presence: $dict.Dict$<string, $frame.PresenceMeta$>;
  /** @deprecated */
  next_presence_ref: number;
  /** @deprecated */
  presence_supported: boolean;
  /** @deprecated */
  paused: $set.Set$<string>;
  /** @deprecated */
  next_client_number: number;
  /** @deprecated */
  now_milliseconds: number;
  /** @deprecated */
  outbox: _.List<Outbound$>;
}

export type Sluice$ = Sluice;

export function new$(tenant_id: string, document_id: string): Sluice$;

export function set_presence_supported(sluice: Sluice$, supported: boolean): Sluice$;

export function now(sluice: Sluice$): number;

export function advance(sluice: Sluice$, milliseconds: number): Sluice$;

export function register(sluice: Sluice$): [Sluice$, string];

export function connected_ids(sluice: Sluice$): _.List<string>;

export function disconnect(sluice: Sluice$, client_id: string): Sluice$;

export function pause(sluice: Sluice$, client_id: string): Sluice$;

export function resume(sluice: Sluice$, client_id: string): Sluice$;

export function handle(
  sluice: Sluice$,
  client_id: string,
  event: string,
  payload: $dynamic.Dynamic$
): Sluice$;

export function take(sluice: Sluice$): [Sluice$, _.Result<Outbound$, undefined>];

export function peek(sluice: Sluice$): _.Result<Outbound$, undefined>;

export function has_pending(sluice: Sluice$): boolean;

export function outbox(sluice: Sluice$): _.List<Outbound$>;

export function sequence_number(sluice: Sluice$): number;
