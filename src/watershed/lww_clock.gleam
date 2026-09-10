//// A bounded logical clock for LWW data structures.
////
//// The runtime supplies wall-clock milliseconds. The clock moves forward when
//// the wall clock moves backwards or repeats, and it never leaves JavaScript's
//// exact-integer range.

import gleam/int

pub const max_safe_timestamp = 9_007_199_254_740_991

pub type ClockError {
  InvalidTimestamp(value: Int)
  ClockExhausted
}

/// Return a timestamp greater than every observed timestamp and at least as
/// large as the current wall clock.
pub fn next(last_seen: Int, wall_clock: Int) -> Result(Int, ClockError) {
  case validate(last_seen), validate(wall_clock) {
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
    Ok(Nil), Ok(Nil) ->
      case last_seen == max_safe_timestamp {
        True -> Error(ClockExhausted)
        False -> Ok(int.max(wall_clock, last_seen + 1))
      }
  }
}

fn validate(value: Int) -> Result(Nil, ClockError) {
  case value < 0 {
    True -> Error(InvalidTimestamp(value))
    False -> Ok(Nil)
  }
}
