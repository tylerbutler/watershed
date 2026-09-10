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
