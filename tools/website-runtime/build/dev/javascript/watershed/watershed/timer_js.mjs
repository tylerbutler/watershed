/// <reference types="./timer_js.d.mts" />
import * as $transport_js from "../watershed/transport_js.mjs";

/**
 * Schedule `action` after `delay_milliseconds`, then give the canceller to
 * `store`.
 *
 * This function reads `wanted` again after it schedules the action, so
 * `wanted` sees every change that a synchronous action made. If `wanted` is
 * false, the function cancels the timer instead of storing the canceller. To
 * cancel a timer that already fired does nothing, so that branch is safe.
 */
export function arm(scheduler, delay_milliseconds, action, wanted, store) {
  let stop = scheduler.schedule(action, delay_milliseconds);
  let $ = wanted();
  if ($) {
    return store(stop);
  } else {
    return stop();
  }
}
