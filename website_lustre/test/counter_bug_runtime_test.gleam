import gleam/list
import gleam/option.{Some}
import gleeunit/should
import watershed_site/counter_bug/runtime

pub fn shared_map_read_modify_write_loses_one_increment_test() {
  let assert Ok(result) = runtime.run_bug()
  result.a |> should.equal(42)
  result.b |> should.equal(42)
  result.recorded |> should.equal(42)
  result.expected |> should.equal(43)
}

pub fn per_replica_map_keys_preserve_both_increments_test() {
  let assert Ok(result) = runtime.run_map_fix()
  result.a |> should.equal(43)
  result.b |> should.equal(43)
  result.recorded |> should.equal(43)
}

pub fn shared_counter_preserves_signed_deltas_test() {
  let assert Ok(result) = runtime.run_counter_fix()
  result.a |> should.equal(43)
  result.b |> should.equal(43)
  result.recorded |> should.equal(43)
}

pub fn map_fix_trace_updates_visible_operands_test() {
  let assert Ok(frames) = runtime.trace(runtime.MapFixDemo)
  let assert Ok(final) = list.last(frames)
  final.sub_a |> should.equal(Some(21))
  final.sub_b |> should.equal(Some(22))
}

pub fn counter_trace_shows_the_signed_correction_race_test() {
  let assert Ok(frames) = runtime.trace(runtime.CounterFixDemo)
  frames
  |> list.any(fn(frame) { frame.a == 44 && frame.b == 42 })
  |> should.be_true()
}
