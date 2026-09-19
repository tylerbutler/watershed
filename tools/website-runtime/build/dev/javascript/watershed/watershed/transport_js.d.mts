import type * as $promise from "../../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as _ from "../gleam.d.mts";

export type Channel$ = any;

export type Cell$<BDLH> = any;

export type TimerId$ = any;

export class Scheduler extends _.CustomType {
  /** @deprecated */
  constructor(
    now_milliseconds: () => number,
    schedule: (x0: () => undefined, x1: number) => () => undefined
  );
  /** @deprecated */
  now_milliseconds: () => number;
  /** @deprecated */
  schedule: (x0: () => undefined, x1: number) => () => undefined;
}
export function Scheduler$Scheduler(
  now_milliseconds: () => number,
  schedule: (x0: () => undefined, x1: number) => () => undefined,
): Scheduler$;
export function Scheduler$isScheduler(value: any): value is Scheduler$;
export function Scheduler$Scheduler$0(value: Scheduler$): () => number;
export function Scheduler$Scheduler$now_milliseconds(value: Scheduler$): () => number;
export function Scheduler$Scheduler$1(
  value: Scheduler$,
): (x0: () => undefined, x1: number) => () => undefined;
export function Scheduler$Scheduler$schedule(value: Scheduler$): (
  x0: () => undefined,
  x1: number
) => () => undefined;

export type Scheduler$ = Scheduler;

export function connect(
  url: string,
  topic: string,
  join_payload: string,
  on_event: (x0: string, x1: string) => undefined,
  on_join: () => undefined,
  on_close: () => undefined
): Channel$;

export function push(channel: Channel$, event: string, payload: string): undefined;

export function drop_socket(channel: Channel$): undefined;

export function hold_socket(channel: Channel$): undefined;

export function resume_socket(channel: Channel$): undefined;

export function close(channel: Channel$): undefined;

export function new_cell<BDLI>(value: BDLI): Cell$<BDLI>;

export function get_cell<BDLK>(cell: Cell$<BDLK>): BDLK;

export function set_cell<BDLM>(cell: Cell$<BDLM>, value: BDLM): undefined;

export function now_milliseconds(): number;

export function set_timer(action: () => undefined, milliseconds: number): TimerId$;

export function clear_timer(id: TimerId$): undefined;

export function real_scheduler(): Scheduler$;

export function mint_dev_token(
  secret: string,
  tenant: string,
  document: string,
  user_id: string
): $promise.Promise$<string>;
