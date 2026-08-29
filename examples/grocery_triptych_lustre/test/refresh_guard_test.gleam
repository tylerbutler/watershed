import gleeunit
import gleeunit/should

import grocery_triptych_lustre/refresh_guard

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn stale_generation_is_rejected_test() -> Nil {
  let #(state1, generation1) = refresh_guard.request(refresh_guard.idle())
  let #(state2, _) = refresh_guard.request(state1)

  refresh_guard.flush(state2, generation1)
  |> should.equal(#(state2, False))
}

pub fn latest_generation_flushes_and_clears_pending_state_test() -> Nil {
  let #(state1, _) = refresh_guard.request(refresh_guard.idle())
  let #(state2, generation2) = refresh_guard.request(state1)

  refresh_guard.flush(state2, generation2)
  |> should.equal(#(
    refresh_guard.State(current_generation: 2, pending: False),
    True,
  ))
}

pub fn new_request_after_completed_flush_schedules_and_accepts_normally_test() -> Nil {
  let #(state1, generation1) = refresh_guard.request(refresh_guard.idle())
  let assert #(cleared, True) = refresh_guard.flush(state1, generation1)
  let #(state2, generation2) = refresh_guard.request(cleared)

  #(state2, generation2)
  |> should.equal(#(
    refresh_guard.State(current_generation: 2, pending: True),
    2,
  ))

  refresh_guard.flush(state2, generation2)
  |> should.equal(#(
    refresh_guard.State(current_generation: 2, pending: False),
    True,
  ))
}
