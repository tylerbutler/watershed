import startest/expect
import watershed/lww_clock

pub fn clock_advances_past_observed_time_test() -> Nil {
  lww_clock.next(100, 100) |> expect.to_equal(Ok(101))
  lww_clock.next(100, 3) |> expect.to_equal(Ok(101))
  lww_clock.next(100, 200) |> expect.to_equal(Ok(200))
  lww_clock.next(9_007_199_254_740_991, 1)
  |> expect.to_equal(Error(lww_clock.ClockExhausted))
  lww_clock.next(0, -1)
  |> expect.to_equal(Error(lww_clock.InvalidTimestamp(-1)))
}

pub fn clock_rejects_unsafe_inputs_test() -> Nil {
  let unsafe = lww_clock.max_safe_timestamp + 1
  lww_clock.next(0, unsafe)
  |> expect.to_equal(Error(lww_clock.InvalidTimestamp(unsafe)))
  lww_clock.next(unsafe, 0)
  |> expect.to_equal(Error(lww_clock.InvalidTimestamp(unsafe)))
  lww_clock.next(-1, 0)
  |> expect.to_equal(Error(lww_clock.InvalidTimestamp(-1)))
}

pub fn clock_accepts_last_safe_increment_test() -> Nil {
  lww_clock.next(9_007_199_254_740_990, 0)
  |> expect.to_equal(Ok(9_007_199_254_740_991))
}
