import type * as $process from "../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $actor from "../../gleam_otp/gleam/otp/actor.d.mts";
import type * as $codec from "../aquamarine/codec.d.mts";
import type * as $ref from "../aquamarine/ref.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Heartbeat extends _.CustomType {
  /** @deprecated */
  constructor(subject: $process.Subject$<Message$>);
  /** @deprecated */
  subject: $process.Subject$<Message$>;
}

export type Heartbeat$ = Heartbeat;

declare class Tick extends _.CustomType {}

declare class Stop extends _.CustomType {}

export type Message$ = Tick | Stop;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    self: $process.Subject$<Message$>,
    send_fn: (x0: string) => _.Result<undefined, undefined>,
    interval_ms: number,
    counter: $ref.Counter$,
    codec: $codec.Codec$
  );
  /** @deprecated */
  self: $process.Subject$<Message$>;
  /** @deprecated */
  send_fn: (x0: string) => _.Result<undefined, undefined>;
  /** @deprecated */
  interval_ms: number;
  /** @deprecated */
  counter: $ref.Counter$;
  /** @deprecated */
  codec: $codec.Codec$;
}

type State$ = State;

export function start(
  send_fn: (x0: string) => _.Result<undefined, undefined>,
  interval_ms: number,
  counter: $ref.Counter$,
  codec: $codec.Codec$
): _.Result<Heartbeat$, $actor.StartError$>;

export function stop(hb: Heartbeat$): undefined;
