import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

import grocery_triptych_lustre/bootstrap_guard

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn late_success_keeps_failure_feedback_test() {
  let failed_feedback = Some(bootstrap_guard.warning("connection failed: boom"))

  bootstrap_guard.failure_latched(Some("boom"))
  |> should.equal(True)

  bootstrap_guard.success_feedback(
    Some("boom"),
    failed_feedback,
    "grow_only handle ensured",
  )
  |> should.equal(failed_feedback)
}

pub fn success_feedback_updates_when_not_failed_test() {
  bootstrap_guard.failure_latched(None)
  |> should.equal(False)

  bootstrap_guard.success_feedback(None, None, "grow_only handle ensured")
  |> should.equal(Some(bootstrap_guard.info("grow_only handle ensured")))
}
