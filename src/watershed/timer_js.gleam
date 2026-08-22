//// One-shot timer arming against a scheduler that can run its action
//// synchronously.
////
//// An injected `Scheduler` can run the scheduled action before it returns the
//// canceller. A logical test clock and a bad real timer both do this. If the
//// caller stores that canceller, the caller holds a handle to a timer that
//// already fired, and it can later cancel a flush that is not armed.
////
//// The correct procedure is always the same. Schedule the action. Read again
//// the state that the action can have changed. Store the canceller only if
//// the timer is still necessary. This module contains that procedure, written
//// one time.
////
//// JavaScript target only.

@target(javascript)
import watershed/transport_js.{type Scheduler}

@target(javascript)
/// Schedule `action` after `delay_ms`, then give the canceller to `store`.
///
/// This function reads `wanted` again after it schedules the action, so
/// `wanted` sees every change that a synchronous action made. If `wanted` is
/// false, the function cancels the timer instead of storing the canceller. To
/// cancel a timer that already fired does nothing, so that branch is safe.
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
