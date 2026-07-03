import gleam/list
import qcheck
import startest/expect
import watershed/counter_kernel.{type CounterOp, type CounterState, Increment}

const iterations = 1000

fn config() -> qcheck.Config {
  qcheck.default_config() |> qcheck.with_test_count(iterations)
}

fn amount_from_int(n: Int) -> Int {
  n % 21 - 10
}

fn op_generator() -> qcheck.Generator(CounterOp) {
  qcheck.small_non_negative_int()
  |> qcheck.map(fn(n) { Increment(amount_from_int(n)) })
}

fn ops_generator() -> qcheck.Generator(List(CounterOp)) {
  qcheck.generic_list(op_generator(), qcheck.small_non_negative_int())
}

fn attributed_stream_generator(
  client_count: Int,
) -> qcheck.Generator(List(#(Int, CounterOp))) {
  qcheck.generic_list(
    qcheck.tuple2(qcheck.small_non_negative_int(), op_generator())
      |> qcheck.map(fn(pair) { #(pair.0 % client_count, pair.1) }),
    qcheck.small_non_negative_int(),
  )
}

fn submit_local(state: CounterState, op: CounterOp) -> CounterState {
  case op {
    Increment(amount) -> {
      let #(state, _, _, _) = counter_kernel.increment(state, amount)
      state
    }
  }
}

fn ack_or_panic(state: CounterState, op: CounterOp) -> CounterState {
  case counter_kernel.ack_local(state, op) {
    Ok(state) -> state
    Error(_) -> panic as "ack did not match pending queue"
  }
}

fn simulate_eager(stream: List(#(Int, CounterOp)), me: Int) -> CounterState {
  let submitted =
    list.fold(stream, counter_kernel.new(), fn(state, item) {
      case item.0 == me {
        True -> submit_local(state, item.1)
        False -> state
      }
    })
  list.fold(stream, submitted, fn(state, item) {
    case item.0 == me {
      True -> ack_or_panic(state, item.1)
      False -> {
        let #(state, _) = counter_kernel.apply_remote(state, item.1)
        state
      }
    }
  })
}

fn simulate_lazy(stream: List(#(Int, CounterOp)), me: Int) -> CounterState {
  list.fold(stream, counter_kernel.new(), fn(state, item) {
    case item.0 == me {
      True -> submit_local(state, item.1) |> ack_or_panic(item.1)
      False -> {
        let #(state, _) = counter_kernel.apply_remote(state, item.1)
        state
      }
    }
  })
}

fn simulate_observer(stream: List(#(Int, CounterOp))) -> CounterState {
  list.fold(stream, counter_kernel.new(), fn(state, item) {
    let #(state, _) = counter_kernel.apply_remote(state, item.1)
    state
  })
}

pub fn convergence_across_authors_and_submit_timing_test() {
  qcheck.run(config(), attributed_stream_generator(3), fn(stream) {
    let observer = simulate_observer(stream).value
    simulate_eager(stream, 0).value |> expect.to_equal(observer)
    simulate_lazy(stream, 0).value |> expect.to_equal(observer)
    simulate_eager(stream, 1).value |> expect.to_equal(observer)
    simulate_lazy(stream, 1).value |> expect.to_equal(observer)
    simulate_eager(stream, 2).value |> expect.to_equal(observer)
    simulate_lazy(stream, 2).value |> expect.to_equal(observer)
  })
}

pub fn acking_own_ops_never_changes_optimistic_value_test() {
  qcheck.run(config(), ops_generator(), fn(ops) {
    let state = list.fold(ops, counter_kernel.new(), submit_local)
    let value = state.value
    list.fold(ops, state, fn(state, op) {
      let state = ack_or_panic(state, op)
      state.value |> expect.to_equal(value)
      state
    })
    Nil
  })
}

pub fn final_value_is_sum_of_sequenced_increments_test() {
  qcheck.run(config(), ops_generator(), fn(ops) {
    let expected =
      list.fold(ops, 0, fn(total, op) {
        case op {
          Increment(amount) -> total + amount
        }
      })

    let state =
      list.fold(ops, counter_kernel.new(), fn(state, op) {
        let #(state, _) = counter_kernel.apply_remote(state, op)
        state
      })

    state.value |> expect.to_equal(expected)
  })
}
