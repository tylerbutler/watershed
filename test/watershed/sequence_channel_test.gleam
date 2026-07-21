import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/handle
import watershed/sequence_kernel

pub fn sequence_summary_round_trips_test() {
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.object([
        #("second", json.int(2)),
        #("first", json.int(1)),
      ]),
    )
  let assert Ok(state) = sequence_kernel.ack_local(state, op)
  let summary = channel.SequenceSummary(state.sequenced)
  let encoded = channel.encode_snapshot(summary)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.SequenceChannel),
    )

  channel.same_snapshot(summary, decoded) |> expect.to_be_true()
}

pub fn sequence_discovers_nested_handles_test() {
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.object([
        #(
          "items",
          json.array(
            [json.object([#("handle", handle.encode_handle("child"))])],
            fn(value) { value },
          ),
        ),
      ]),
    )
  channel.handle_addresses(channel.SequenceState(state))
  |> expect.to_equal(["child"])
}
