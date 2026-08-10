import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

import grocery_triptych_lustre/bootstrap_guard

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn failure_stays_latched_after_an_error_test() {
  bootstrap_guard.failure_latched(Some("boom"))
  |> should.equal(True)

  bootstrap_guard.failure_latched(None)
  |> should.equal(False)
}
