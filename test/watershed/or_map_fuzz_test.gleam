//// Fuzz coverage for the OR-map kernel. The model exercises TallyMode only:
//// RegisterMode uses wall-clock LWW timestamps in the runtime layer, so a
//// deterministic fuzz model would need synthetic timestamp plumbing.

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  Capabilities, ClientOp, KernelModel, Synchronize,
}
import watershed/fuzz/or_map_model.{type OrMapCommand, CmdIncrement, CmdRemove}
import watershed/fuzz/script_gen
import watershed/or_map_kernel.{Increment, TallyMode}

const client_count = 3

fn weights() -> script_gen.Weights {
  script_gen.Weights(
    ..script_gen.default_weights(),
    rollback_op: 8,
    stashed_op: 8,
  )
}

pub fn converges_and_matches_oracle_test() {
  let model = or_map_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_env(),
    client_count,
    script_gen.script_generator(model.gen_op, client_count, weights()),
  )
}

pub fn op_json_round_trips_with_and_without_delta_test() {
  let model = or_map_model.model()
  let assert Ok(#(_state, _events, op, _message_id)) =
    or_map_kernel.increment(
      or_map_kernel.new(replica_id.new("a"), TallyMode),
      "a",
      6,
    )
  let assert Increment(key, amount, delta) = op

  [CmdIncrement("a", 3, None), CmdIncrement(key, amount, Some(delta))]
  |> list.each(fn(cmd) {
    let assert Ok(decoded) =
      json.parse(json.to_string(model.op_to_json(cmd)), model.op_decoder)
    decoded |> expect.to_equal(cmd)
  })
}

fn authorless_remove_oracle(
  log: List(#(Int, OrMapCommand)),
) -> List(#(String, Int)) {
  let #(dots, tallies) =
    log
    |> list.index_map(fn(entry, i) { #(i + 1, entry) })
    |> list.fold(#(dict.new(), dict.new()), fn(state, item) {
      let #(dots, tallies) = state
      let #(seq, #(_author, cmd)) = item
      case cmd {
        CmdIncrement(key, amount, _) -> {
          let existing = dict.get(dots, key) |> result.unwrap([])
          let tally = dict.get(tallies, key) |> result.unwrap(0)
          #(
            dict.insert(dots, key, list.append(existing, [seq])),
            dict.insert(tallies, key, tally + amount),
          )
        }
        CmdRemove(key, ref_seq, _) -> {
          let remaining =
            dict.get(dots, key)
            |> result.unwrap([])
            |> list.filter(fn(dot_seq) { dot_seq > ref_seq })
          let dots = case remaining {
            [] -> dict.delete(dots, key)
            _ -> dict.insert(dots, key, remaining)
          }
          #(dots, tallies)
        }
      }
    })

  dict.keys(dots)
  |> list.sort(by: string.compare)
  |> list.filter_map(fn(key) {
    case dict.get(dots, key) {
      Ok([_, ..]) -> Ok(#(key, dict.get(tallies, key) |> result.unwrap(0)))
      _ -> Error(Nil)
    }
  })
}

pub fn oracle_author_clause_is_load_bearing_test() {
  let model = or_map_model.model()
  let script = [
    ClientOp(1, CmdIncrement("a", 5, None)),
    ClientOp(1, CmdRemove("a", 0, None)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, client_count, script) |> expect.to_be_ok

  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        oracle: Some(authorless_remove_oracle),
      ),
    )
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected an oracle without the remover-author clause to diverge"
  }
}

pub fn shared_replica_id_loses_increments_test() {
  let model = or_map_model.model()
  let buggy =
    KernelModel(..model, init: fn(_id) {
      or_map_kernel.new(replica_id.new("client-0"), TallyMode)
    })
  let script = [
    ClientOp(1, CmdIncrement("a", 3, None)),
    ClientOp(2, CmdIncrement("a", 5, None)),
    Synchronize,
  ]
  case kernel_fuzz.try_run_script(buggy, client_count, script) {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected a shared replica id to lose an increment and fail the oracle"
  }
}
