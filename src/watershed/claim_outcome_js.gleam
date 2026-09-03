//// JavaScript adapter for claim submission outcomes.

@target(javascript)
import gleam/javascript/promise
@target(javascript)
import gleam/option.{Some}
@target(javascript)
import watershed/claims_kernel
@target(javascript)
import watershed/runtime

@target(javascript)
/// Observe the outcome of one claim submission.
///
/// Pending replies resolve from their promise. Immediate replies call
/// `resolved` before this function returns.
pub fn observe(
  reply: runtime.ClaimSubmitReply,
  resolved: fn(claims_kernel.ClaimOutcome) -> Nil,
) -> Nil {
  case reply {
    runtime.Pending(outcome) -> {
      let _ = promise.map(outcome, resolved)
      Nil
    }
    runtime.AlreadyClaimed(current_value) ->
      resolved(claims_kernel.Lost(Some(current_value)))
    runtime.AlreadyPendingLocally -> resolved(claims_kernel.Aborted)
    runtime.WrongChannelType -> resolved(claims_kernel.Aborted)
  }
}
