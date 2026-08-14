//// One-shot timer arming against a scheduler that may run its action
//// synchronously.
////
//// An injected `Scheduler` — a logical test clock, or a pathological real
//// timer — is allowed to run the scheduled action *before* handing back
//// its canceller. A caller that stored the canceller anyway would be
//// holding a handle to a timer that already fired, and would later cancel
//// a flush that is not armed. The ritual that avoids this is always the
//// same: schedule, re-read the state the action may have changed, and
//// only store the canceller if the timer is still wanted. This module is
//// that ritual, written once.
////
//// JavaScript target only.

@target(javascript)
import watershed/transport_js.{type Scheduler}

@target(javascript)
/// Schedule `action` after `delay_ms`, then hand the canceller to `store`
/// — unless `wanted` (re-evaluated after scheduling, so it sees anything
/// a synchronous action changed) says the timer is no longer needed, in
/// which case it is cancelled instead. Cancelling a timer that already
/// fired is a no-op, so the stale branch is safe either way.
pub fn arm(
  scheduler scheduler: Scheduler,
  delay_ms delay_ms: Int,
  action action: fn() -> Nil,
  wanted wanted: fn() -> Bool,
  store store: fn(fn() -> Nil) -> Nil,
) -> Nil {
  let stop = scheduler.schedule(action, delay_ms)
  case wanted() {
    True -> store(stop)
    False -> stop()
  }
}
