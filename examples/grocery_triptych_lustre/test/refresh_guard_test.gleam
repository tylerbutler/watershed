import gleeunit
import gleeunit/should

import refresh_guard

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn first_request_schedules_a_flush_test() {
  refresh_guard.request(False)
  |> should.equal(#(True, refresh_guard.ScheduleFlush))
}

pub fn repeated_request_while_pending_skips_extra_timers_test() {
  refresh_guard.request(True)
  |> should.equal(#(True, refresh_guard.NoSchedule))
}

pub fn flush_clears_the_pending_flag_test() {
  refresh_guard.flush(True)
  |> should.equal(False)
}
