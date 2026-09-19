import gleeunit/should
import watershed_site/demo/timing

pub fn pace_uses_quarter_seconds_test() {
  timing.delay_ms(4, False, 99)
  |> should.equal(1000)
}

pub fn jitter_is_bounded_test() {
  timing.delay_ms(4, True, 0)
  |> should.equal(700)
  timing.delay_ms(4, True, 10_000)
  |> should.equal(1300)
}

pub fn pace_and_delay_have_minimums_test() {
  timing.delay_ms(0, False, 5000)
  |> should.equal(250)
  timing.delay_ms(-4, True, 0)
  |> should.equal(175)
}

pub fn next_sample_is_deterministic_and_bounded_test() {
  let first = timing.next_sample(42)
  first |> should.equal(timing.next_sample(42))

  let #(next_seed, sample) = first
  { next_seed != 42 } |> should.be_true()
  { sample >= 0 && sample <= 10_000 } |> should.be_true()
}
