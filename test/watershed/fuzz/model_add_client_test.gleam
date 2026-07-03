//// F2: proves the real production models (`counter_model`, `map_model`)
//// wire up `load_from_synced`, not just the harness's own toy model in
//// `add_client_test.gleam`. Before this capability is wired, `AddClient`
//// fails loudly (see `kernel_fuzz.add_client`), which is exactly the
//// signal these tests are written against first.

import gleam/json
import watershed/counter_kernel.{Increment}
import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz.{AddClient, ClientOp, Synchronize}
import watershed/fuzz/map_model
import watershed/map_kernel.{Set}

pub fn counter_add_client_joins_and_converges_test() {
  let script = [
    ClientOp(1, Increment(5)),
    Synchronize,
    AddClient,
    ClientOp(2, Increment(-3)),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(counter_model.model(), 3, script)
  |> expect_ok
}

pub fn map_add_client_joins_and_converges_test() {
  let script = [
    ClientOp(1, Set("a", json.int(1))),
    ClientOp(2, Set("b", json.int(2))),
    Synchronize,
    AddClient,
    ClientOp(1, Set("c", json.int(3))),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(map_model.model(), 3, script)
  |> expect_ok
}

fn expect_ok(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}
