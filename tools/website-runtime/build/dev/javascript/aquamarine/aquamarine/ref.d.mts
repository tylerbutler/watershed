import type * as $process from "../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $actor from "../../gleam_otp/gleam/otp/actor.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Counter extends _.CustomType {
  /** @deprecated */
  constructor(subject: $process.Subject$<Message$>);
  /** @deprecated */
  subject: $process.Subject$<Message$>;
}

export type Counter$ = Counter;

declare class Next extends _.CustomType {
  /** @deprecated */
  constructor(reply_to: $process.Subject$<string>);
  /** @deprecated */
  reply_to: $process.Subject$<string>;
}

declare class Stop extends _.CustomType {}

export type Message$ = Next | Stop;

export function start(): _.Result<Counter$, $actor.StartError$>;

export function next(counter: Counter$): _.Result<string, undefined>;

export function stop(counter: Counter$): undefined;
