import gleam/json
import gleam/option.{None}
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/or_map_kernel as kernel
import watershed/wire/op

pub fn mv_or_map_wire_stash_rollback_preserves_the_authored_operation_test() -> Nil {
  let initial = kernel.new(replica_id.new("a"), kernel.MvRegisterMode)
  let assert Ok(#(state, _, first, first_id)) =
    kernel.set_mv_register(initial, "gate", "first")
  let assert Ok(#(state, _, second, second_id)) =
    kernel.set_mv_register(state, "gate", "second")
  let assert Error(kernel.UnexpectedRollback(_)) =
    kernel.rollback(state, first, first_id)
  let assert Ok(#(state, _)) = kernel.rollback(state, second, second_id)
  kernel.get(state, "gate") |> expect.to_equal(Ok(kernel.MvRegister(["first"])))
  let assert Ok(replayed) =
    json.parse(
      op.encode_or_map_operation(second) |> json.to_string,
      op.or_map_operation_decoder(),
    )
  let assert Ok(#(state, _, outgoing, replay_id)) =
    kernel.apply_stashed_operation(state, replayed)
  outgoing |> expect.to_equal(second)
  let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
  let assert Ok(#(state, [], None)) =
    channel.ack_local(
      channel.OrMapState(state),
      channel.OrMapOperation(first),
      channel.OrMapMeta(first_id),
      meta,
    )
  let assert Ok(#(channel.OrMapState(state), [], None)) =
    channel.ack_local(
      state,
      channel.OrMapOperation(outgoing),
      channel.OrMapMeta(replay_id),
      meta,
    )
  kernel.sequenced_entries(state)
  |> expect.to_equal([#("gate", kernel.MvRegister(["second"]))])
  state.pending |> expect.to_equal([])
}

pub fn mv_or_map_channel_snapshot_attach_and_ack_test() -> Nil {
  let assert Ok(#(state, _, operation, message_id)) =
    kernel.set_mv_register(
      kernel.new(replica_id.new("a"), kernel.MvRegisterMode),
      "gate",
      "open",
    )
  let wrapped = channel.OrMapState(state)
  let snapshot = channel.attach_snapshot(wrapped)
  let assert Ok(decoded) =
    json.parse(
      channel.encode_snapshot(snapshot) |> json.to_string,
      channel.snapshot_decoder(channel.OrMapChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  let assert Ok(channel.OrMapState(loaded)) =
    channel.from_snapshot(decoded, replica: "b")
  kernel.get(loaded, "gate") |> expect.to_equal(Ok(kernel.MvRegister(["open"])))
  let attached = channel.attach_state(wrapped, replica: "a")
  channel.same_snapshot(snapshot, channel.snapshot(attached))
  |> expect.to_be_true()
  channel.handle_addresses(wrapped) |> expect.to_equal([])
  let operation = channel.OrMapOperation(operation)
  let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
  let assert Ok(#(channel.OrMapState(acked), [], None)) =
    channel.ack_local(wrapped, operation, channel.OrMapMeta(message_id), meta)
  acked.pending |> expect.to_equal([])
  kernel.sequenced_entries(acked)
  |> expect.to_equal([#("gate", kernel.MvRegister(["open"]))])
  let assert Ok(#(remote, _, [])) =
    channel.apply_remote(
      channel.new(channel.InitOrMap(kernel.MvRegisterMode), replica: "b"),
      operation,
      meta,
    )
  let assert Ok(#(_, [], [])) = channel.apply_remote(remote, operation, meta)
  let assert channel.OrMapOperation(kernel.SetMvRegister(key, value, delta)) =
    operation
  channel.same_shape(operation, operation) |> expect.to_be_true()
  channel.same_shape(
    operation,
    channel.OrMapOperation(kernel.SetMvRegister(key, "other", delta)),
  )
  |> expect.to_be_false()
  channel.same_shape(
    operation,
    channel.OrMapOperation(kernel.SetRegister(key, value, 0, delta)),
  )
  |> expect.to_be_false()
}

pub fn mv_or_map_p2p_edit_dispatch_and_mode_guard_test() -> Nil {
  let assert Ok(#(channel.OrMapState(state), events, _)) =
    channel.apply_p2p_local(
      channel.new(channel.InitOrMap(kernel.MvRegisterMode), replica: "a"),
      channel.OrMapSetMvRegisterEdit("gate", "open"),
    )
  events
  |> expect.to_equal([
    channel.OrMapEvent(kernel.MvRegisterUpdated("gate", ["open"])),
  ])
  state.pending |> expect.to_equal([])
  let assert Error(channel.UnsupportedP2p(_)) =
    channel.apply_p2p_local(
      channel.new(channel.InitOrMap(kernel.RegisterMode), replica: "a"),
      channel.OrMapSetMvRegisterEdit("gate", "open"),
    )
  Nil
}
