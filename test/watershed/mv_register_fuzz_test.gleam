import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lattice_core/replica_id
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  AddClient, ClientOperation, Deliver, Disconnect, KernelModel, Reconnect,
  RollbackOperation, Sequence, StashedOperation, Synchronize,
}
import watershed/fuzz/mv_register_model.{MvCommand}
import watershed/fuzz/script_gen
import watershed/mv_register_kernel as mv

pub fn mv_register_causal_scripts_test() -> Nil {
  let a = MvCommand("a", None)
  let b = MvCommand("b", None)
  let c = MvCommand("c", None)
  let resolve = MvCommand("resolved", None)
  let #(_, _, old, _) = mv.set(mv.new(replica_id.new("client-1")), "a")
  let replay = MvCommand("a", Some(old.delta))
  [
    [ClientOperation(1, a), ClientOperation(2, b), Synchronize],
    [
      ClientOperation(1, a),
      ClientOperation(2, b),
      Synchronize,
      ClientOperation(1, resolve),
      Synchronize,
    ],
    [
      ClientOperation(1, a),
      ClientOperation(2, b),
      Sequence(2),
      Deliver(1, 2),
      ClientOperation(3, c),
      ClientOperation(1, resolve),
      Synchronize,
    ],
    [
      ClientOperation(1, a),
      Synchronize,
      ClientOperation(1, resolve),
      Synchronize,
      StashedOperation(1, replay),
      Synchronize,
    ],
    [RollbackOperation(1, a), ClientOperation(1, b), Synchronize],
    [
      ClientOperation(1, a),
      Sequence(1),
      ClientOperation(2, b),
      AddClient,
      Synchronize,
    ],
    [ClientOperation(1, a), ClientOperation(2, a), Synchronize],
    [
      Disconnect(1),
      ClientOperation(1, a),
      ClientOperation(2, b),
      Synchronize,
      Reconnect(1),
      Synchronize,
    ],
  ]
  |> list.each(fn(script) {
    let assert Ok(_) =
      kernel_fuzz.try_run_script(mv_register_model.model(), 4, script)
  })
}

pub fn mv_register_generated_convergence_test() -> Nil {
  let model = mv_register_model.model()
  let weights =
    script_gen.Weights(
      ..script_gen.default_weights(),
      rollback_operation: 8,
      stashed_operation: 8,
    )
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    4,
    script_gen.script_generator(model.gen_operation, 4, weights),
  )
}

pub fn mv_register_model_preserves_serialized_delta_test() -> Nil {
  let model = mv_register_model.model()
  let #(_, _, operation, _) = mv.set(mv.new(replica_id.new("a")), "x")
  [MvCommand("x", None), MvCommand("x", Some(operation.delta))]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> expect.to_equal(Ok(command))
  })
}

pub fn mv_register_oracle_catches_a_dropped_alternative_test() -> Nil {
  let model = mv_register_model.model()
  let buggy = KernelModel(..model, apply_remote: fn(state, _, _) { Ok(state) })
  kernel_fuzz.try_run_script(buggy, 3, [
    ClientOperation(1, MvCommand("same", None)),
    ClientOperation(2, MvCommand("same", None)),
    Synchronize,
  ])
  |> result.is_error
  |> expect.to_be_true()
}
