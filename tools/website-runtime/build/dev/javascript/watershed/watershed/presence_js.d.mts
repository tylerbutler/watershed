import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $watershed from "../watershed.d.mts";
import type * as $presence from "../watershed/presence.d.mts";
import type * as $runtime from "../watershed/runtime.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

declare class Handle<BZQU> extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<Driver$<BZQU>>);
  /** @deprecated */
  cell: $transport_js.Cell$<Driver$<BZQU>>;
}

export type Handle$<BZQU> = Handle<BZQU>;

declare class Driver<BZQV> extends _.CustomType {
  /** @deprecated */
  constructor(
    runtime: $runtime.Runtime$,
    broadcast: (x0: $json.Json$) => undefined,
    config: $presence.Config$<BZQV>,
    on_event: (x0: $presence.Event$<BZQV>) => undefined,
    scheduler: $transport_js.Scheduler$,
    meta: BZQV,
    mode: $option.Option$<$presence.Mode$>,
    session: $option.Option$<string>,
    key: string,
    implementation: Implementation$<BZQV>,
    stopped: boolean
  );
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  broadcast: (x0: $json.Json$) => undefined;
  /** @deprecated */
  config: $presence.Config$<BZQV>;
  /** @deprecated */
  on_event: (x0: $presence.Event$<BZQV>) => undefined;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  meta: BZQV;
  /** @deprecated */
  mode: $option.Option$<$presence.Mode$>;
  /** @deprecated */
  session: $option.Option$<string>;
  /** @deprecated */
  key: string;
  /** @deprecated */
  implementation: Implementation$<BZQV>;
  /** @deprecated */
  stopped: boolean;
}

type Driver$<BZQV> = Driver<BZQV>;

declare class Unresolved extends _.CustomType {}

declare class ServerPresence<BZQW> extends _.CustomType {
  /** @deprecated */
  constructor(tracker: $presence.Tracker$<BZQW>);
  /** @deprecated */
  tracker: $presence.Tracker$<BZQW>;
}

declare class RipplePresence<BZQW> extends _.CustomType {
  /** @deprecated */
  constructor(
    sessions: $presence.Sessions$<BZQW>,
    cancel: $option.Option$<() => undefined>
  );
  /** @deprecated */
  sessions: $presence.Sessions$<BZQW>;
  /** @deprecated */
  cancel: $option.Option$<() => undefined>;
}

type Implementation$<BZQW> = Unresolved | ServerPresence<BZQW> | RipplePresence<
  BZQW
>;

export function start_with_scheduler<BZRF>(
  document: $watershed.Document$<any>,
  config: $presence.Config$<BZRF>,
  initial: BZRF,
  on_event: (x0: $presence.Event$<BZRF>) => undefined,
  scheduler: $transport_js.Scheduler$
): Handle$<BZRF>;

export function start<BZQZ>(
  document: $watershed.Document$<any>,
  config: $presence.Config$<BZQZ>,
  initial: BZQZ,
  on_event: (x0: $presence.Event$<BZQZ>) => undefined
): Handle$<BZQZ>;

export function update<BZRJ>(handle: Handle$<BZRJ>, meta: BZRJ): undefined;

export function stop(handle: Handle$<any>): undefined;

export function mode(handle: Handle$<any>): $option.Option$<$presence.Mode$>;

export function local_session(handle: Handle$<any>): $option.Option$<string>;
