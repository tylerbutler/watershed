import gleeunit/should
import watershed_site/demo/timing

pub fn one_x_playback_uses_one_second_test() {
  timing.delay_ms(4, False, 99)
  |> should.equal(1000)
}

pub fn faster_playback_shortens_delivery_delay_test() {
  timing.delay_ms(8, False, 99)
  |> should.equal(500)
  timing.delay_ms(2, False, 99)
  |> should.equal(2000)
}

pub fn jitter_is_bounded_test() {
  timing.delay_ms(4, True, 0)
  |> should.equal(700)
  timing.delay_ms(4, True, 10_000)
  |> should.equal(1300)
}

pub fn playback_speed_has_a_minimum_test() {
  timing.delay_ms(0, False, 5000)
  |> should.equal(4000)
  timing.delay_ms(-4, True, 0)
  |> should.equal(2800)
}

pub fn next_sample_is_deterministic_and_bounded_test() {
  let first = timing.next_sample(42)
  first |> should.equal(timing.next_sample(42))

  let #(next_seed, sample) = first
  { next_seed != 42 } |> should.be_true()
  { sample >= 0 && sample <= 10_000 } |> should.be_true()
}
