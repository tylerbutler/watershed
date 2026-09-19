import type * as $transport_js from "../watershed/transport_js.d.mts";

export function arm(
  scheduler: $transport_js.Scheduler$,
  delay_milliseconds: number,
  action: () => undefined,
  wanted: () => boolean,
  store: (x0: () => undefined) => undefined
): undefined;
