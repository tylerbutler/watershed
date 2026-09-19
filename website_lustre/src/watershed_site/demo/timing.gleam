import gleam/int

const sample_limit = 10_000

const seed_limit = 1_000_003

pub fn delay_ms(pace_quarters: Int, jitter: Bool, sample: Int) -> Int {
  let base = playback_ms(pace_quarters, 1000)

  case jitter {
    False -> base
    True -> {
      let sample = int.clamp(sample, 0, sample_limit)
      int.max(50, base * { 7000 + sample * 6000 / sample_limit } / 10_000)
    }
  }
}

pub fn playback_ms(pace_quarters: Int, duration: Int) -> Int {
  int.max(1, duration) * 4 / int.max(1, pace_quarters)
}

pub fn next_sample(seed: Int) -> #(Int, Int) {
  let seed = positive_remainder(seed, seed_limit)
  let next_seed = { seed * 241 + 157 } % seed_limit
  #(next_seed, next_seed % { sample_limit + 1 })
}

fn positive_remainder(value: Int, divisor: Int) -> Int {
  let remainder = value % divisor

  case remainder < 0 {
    True -> remainder + divisor
    False -> remainder
  }
}
