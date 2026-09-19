import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/counter_kernel
import watershed/map_kernel

const key = "boats-locked"

const base = 41

pub type Demo {
  BugDemo
  MapFixDemo
  CounterFixDemo
}

pub type Outcome {
  Outcome(
    a: Int,
    b: Int,
    recorded: Int,
    expected: Int,
    sub_a: Option(Int),
    sub_b: Option(Int),
  )
}

pub type LogLine {
  LogLine(text: String, tone: String)
}

pub type Frame {
  Frame(
    a: Int,
    b: Int,
    sub_a: Option(Int),
    sub_b: Option(Int),
    caption: String,
    chips: List(String),
    log: List(LogLine),
    outcome: Option(Outcome),
  )
}

pub fn trace(demo: Demo) -> Result(List(Frame), String) {
  case demo {
    BugDemo -> bug_trace()
    MapFixDemo -> map_fix_trace()
    CounterFixDemo -> counter_fix_trace()
  }
}

pub fn run_bug() -> Result(Outcome, String) {
  final_outcome(bug_trace())
}

pub fn run_map_fix() -> Result(Outcome, String) {
  final_outcome(map_fix_trace())
}

pub fn run_counter_fix() -> Result(Outcome, String) {
  final_outcome(counter_fix_trace())
}

fn bug_trace() -> Result(List(Frame), String) {
  let seed = map_kernel.from_sequenced([#(key, json.int(base))])
  let #(a_pending, _, operation_a) =
    map_kernel.set(seed, key, json.int(base + 1))
  let #(b_pending, _, operation_b) =
    map_kernel.set(seed, key, json.int(base + 1))
  use a <- result.try(ack_map(a_pending, operation_a))
  let #(b, _) = map_kernel.apply_remote(b_pending, operation_a)
  let #(a, _) = map_kernel.apply_remote(a, operation_b)
  use b <- result.try(ack_map(b, operation_b))
  use value_a <- result.try(read(a, key))
  use value_b <- result.try(read(b, key))
  let outcome = Outcome(value_a, value_b, value_a, base + 2, None, None)
  Ok([
    Frame(
      41,
      41,
      None,
      None,
      "A boat locks through each house at the same moment. Both read the tally: 41.",
      [],
      [
        LogLine("A reads boats-locked → 41", ""),
        LogLine("B reads boats-locked → 41", ""),
      ],
      None,
    ),
    Frame(
      42,
      41,
      None,
      None,
      "A writes the shared value first: 41 + 1 = 42.",
      [],
      [LogLine("A writes boats-locked = 41 + 1 = 42 · sent", "pending")],
      None,
    ),
    Frame(
      42,
      42,
      None,
      None,
      "Each house does read-modify-write on the same cell. Both send set(42).",
      [],
      [
        LogLine("A writes boats-locked = 41 + 1 = 42 · sent", "pending"),
        LogLine("B writes boats-locked = 41 + 1 = 42 · sent", "pending"),
      ],
      None,
    ),
    Frame(
      42,
      42,
      None,
      None,
      "The sequencer orders A, then B. Last write wins.",
      ["SN 1 · A set 42", "SN 2 · B set 42"],
      [
        LogLine("A writes boats-locked = 42 · sent", "pending"),
        LogLine("B writes boats-locked = 42 · sent", "pending"),
      ],
      None,
    ),
    Frame(
      value_a,
      value_b,
      None,
      None,
      "Two boats locked through. The tally moved by one. One boat vanished — LWW overwrote a read-modify-write.",
      ["SN 1 · A set 42", "SN 2 · B set 42"],
      [LogLine("converged: boats-locked = 42", "lost")],
      Some(outcome),
    ),
  ])
}

fn map_fix_trace() -> Result(List(Frame), String) {
  let key_a = key <> "/a"
  let key_b = key <> "/b"
  let seed =
    map_kernel.from_sequenced([
      #(key_a, json.int(20)),
      #(key_b, json.int(21)),
    ])
  let #(a_pending, _, operation_a) = map_kernel.set(seed, key_a, json.int(21))
  let #(b_pending, _, operation_b) = map_kernel.set(seed, key_b, json.int(22))
  use a_pending_total <- result.try(total(a_pending, key_a, key_b))
  use b_pending_total <- result.try(total(b_pending, key_a, key_b))
  use a <- result.try(ack_map(a_pending, operation_a))
  let #(b, _) = map_kernel.apply_remote(b_pending, operation_a)
  let #(a, _) = map_kernel.apply_remote(a, operation_b)
  use b <- result.try(ack_map(b, operation_b))
  use a_total <- result.try(total(a, key_a, key_b))
  use b_total <- result.try(total(b, key_a, key_b))
  let outcome = Outcome(a_total, b_total, a_total, base + 2, Some(21), Some(22))
  Ok([
    Frame(
      41,
      41,
      Some(20),
      Some(21),
      "Same start (20 + 21 = 41), but each house tallies its own column.",
      [],
      [
        LogLine("A reads boats-locked/a → 20", ""),
        LogLine("B reads boats-locked/b → 21", ""),
      ],
      None,
    ),
    Frame(
      a_pending_total,
      b_pending_total,
      Some(21),
      Some(22),
      "The two writes touch different keys — they cannot overwrite each other.",
      [],
      [
        LogLine("A writes boats-locked/a = 21 · sent", "pending"),
        LogLine("B writes boats-locked/b = 22 · sent", "pending"),
      ],
      None,
    ),
    Frame(
      a_pending_total,
      b_pending_total,
      Some(21),
      Some(22),
      "The sequencer preserves both independent writes.",
      ["SN 1 · A set /a=21", "SN 2 · B set /b=22"],
      [
        LogLine("A writes boats-locked/a = 21 · sent", "pending"),
        LogLine("B writes boats-locked/b = 22 · sent", "pending"),
      ],
      None,
    ),
    Frame(
      a_total,
      b_total,
      Some(21),
      Some(22),
      "Both boats counted: 43. SharedCounter keeps one tally per replica; their signed deltas commute.",
      ["SN 1 · A set /a=21", "SN 2 · B set /b=22"],
      [LogLine("converged: 21 + 22 = 43", "seq")],
      Some(outcome),
    ),
  ])
}

fn counter_fix_trace() -> Result(List(Frame), String) {
  let #(a_pending, _, operation_a, _) =
    counter_kernel.increment(counter_kernel.from_summary(base), 1)
  let #(b_pending, _, operation_b, _) =
    counter_kernel.increment(counter_kernel.from_summary(base), 1)
  use a <- result.try(ack_counter(a_pending, operation_a))
  let #(b, _) = counter_kernel.apply_remote(b_pending, operation_a)
  let #(a, _) = counter_kernel.apply_remote(a, operation_b)
  use b <- result.try(ack_counter(b, operation_b))
  let first_a = a.value
  let first_b = b.value
  let #(a_pending, _, operation_a, _) = counter_kernel.increment(a, 1)
  let #(b_pending, _, operation_b, _) = counter_kernel.increment(b, -1)
  let #(a, _) = counter_kernel.apply_remote(a_pending, operation_b)
  use b <- result.try(ack_counter(b_pending, operation_b))
  use a <- result.try(ack_counter(a, operation_a))
  let #(b, _) = counter_kernel.apply_remote(b, operation_a)
  let outcome = Outcome(a.value, b.value, a.value, base + 2, None, None)
  Ok([
    Frame(
      42,
      41,
      None,
      None,
      "A sends increment +1. The operation carries a delta, not 42.",
      [],
      [LogLine("A sends increment +1 · optimistic 42", "pending")],
      None,
    ),
    Frame(
      42,
      42,
      None,
      None,
      "Both houses send +1. There is no replacement value to overwrite.",
      [],
      [
        LogLine("A sends increment +1 · optimistic 42", "pending"),
        LogLine("B sends increment +1 · optimistic 42", "pending"),
      ],
      None,
    ),
    Frame(
      first_a,
      first_b,
      None,
      None,
      "Both deltas land on both replicas: 43. No boat lost.",
      ["SN 1 · A inc +1", "SN 2 · B inc +1"],
      [LogLine("converged: 41 + 1 + 1 = 43", "seq")],
      None,
    ),
    Frame(
      a_pending.value,
      b_pending.value,
      None,
      None,
      "For a moment the replicas read 44 and 42. Another +1 races a −1 correction.",
      ["SN 1 · A inc +1", "SN 2 · B inc +1"],
      [
        LogLine("A sends increment +1 · optimistic 44", "pending"),
        LogLine("B sends increment −1 · optimistic 42", "pending"),
      ],
      None,
    ),
    Frame(
      a.value,
      b.value,
      None,
      None,
      "Every signed delta counted, in the order the sequencer picked. This is SharedCounter.",
      [
        "SN 1 · A inc +1",
        "SN 2 · B inc +1",
        "SN 3 · B inc −1",
        "SN 4 · A inc +1",
      ],
      [LogLine("converged: 43 + 1 − 1 = 43", "seq")],
      Some(outcome),
    ),
  ])
}

fn final_outcome(
  frames: Result(List(Frame), String),
) -> Result(Outcome, String) {
  use frames <- result.try(frames)
  use frame <- result.try(
    list.last(frames) |> result.replace_error("The trace is empty."),
  )
  option.to_result(frame.outcome, "The trace has no final outcome.")
}

fn ack_map(
  state: map_kernel.MapState,
  operation: map_kernel.MapOperation,
) -> Result(map_kernel.MapState, String) {
  map_kernel.ack_local(state, operation)
  |> result.map_error(fn(reason) { string.inspect(reason) })
}

fn ack_counter(
  state: counter_kernel.CounterState,
  operation: counter_kernel.CounterOperation,
) -> Result(counter_kernel.CounterState, String) {
  counter_kernel.ack_local(state, operation)
  |> result.map_error(fn(reason) { string.inspect(reason) })
}

fn total(
  state: map_kernel.MapState,
  key_a: String,
  key_b: String,
) -> Result(Int, String) {
  use a <- result.try(read(state, key_a))
  use b <- result.try(read(state, key_b))
  Ok(a + b)
}

fn read(state: map_kernel.MapState, name: String) -> Result(Int, String) {
  use value <- result.try(
    map_kernel.get(state, name)
    |> result.map_error(fn(_) { "Missing counter value: " <> name }),
  )
  json.parse(json.to_string(value), decode.int)
  |> result.map_error(fn(_) { "Invalid counter value: " <> name })
}
