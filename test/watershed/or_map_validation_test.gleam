import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/or_map
import startest/expect
import watershed/channel
import watershed/or_map_kernel as kernel
import watershed/wire/op

fn new(mode: kernel.OrMapMode) -> kernel.OrMapState {
  kernel.new(replica_id.new("author"), mode)
}

// Set operations retain full leaf history instead of one sparse authored write.
fn sparse_writes() -> List(#(kernel.OrMapState, kernel.OrMapOperation)) {
  let assert Ok(#(tally, _, increment, _)) =
    kernel.increment(new(kernel.TallyMode), "gate", 5)
  let assert Ok(#(lww, _, set, _)) =
    kernel.set_register(new(kernel.RegisterMode), "gate", "open", 10)
  let assert Ok(#(mv, _, write, _)) =
    kernel.set_mv_register(new(kernel.MvRegisterMode), "gate", "open")
  [#(tally, increment), #(lww, set), #(mv, write)]
}

fn writes() -> List(#(kernel.OrMapState, kernel.OrMapOperation)) {
  let assert Ok(#(members, _, add, _)) =
    kernel.add_member(new(kernel.OrSetMode), "gate", "open")
  list.append(sparse_writes(), [#(members, add)])
}

fn delta(operation: kernel.OrMapOperation) -> or_map.ORMapDelta {
  case operation {
    kernel.Increment(_, _, delta)
    | kernel.SetRegister(_, _, _, delta)
    | kernel.SetMvRegister(_, _, delta)
    | kernel.AddMember(_, _, delta)
    | kernel.RemoveMember(_, _, delta)
    | kernel.Remove(_, delta) -> delta
  }
}

fn with_delta(
  operation: kernel.OrMapOperation,
  delta: or_map.ORMapDelta,
) -> kernel.OrMapOperation {
  case operation {
    kernel.Increment(key, amount, _) -> kernel.Increment(key, amount, delta)
    kernel.SetRegister(key, value, timestamp, _) ->
      kernel.SetRegister(key, value, timestamp, delta)
    kernel.SetMvRegister(key, value, _) ->
      kernel.SetMvRegister(key, value, delta)
    kernel.AddMember(key, member, _) -> kernel.AddMember(key, member, delta)
    kernel.RemoveMember(key, member, _) ->
      kernel.RemoveMember(key, member, delta)
    kernel.Remove(key, _) -> kernel.Remove(key, delta)
  }
}

fn expect_rejected(
  state: kernel.OrMapState,
  operation: kernel.OrMapOperation,
) -> Nil {
  let before = kernel.summary(state) |> json.to_string
  let applied = kernel.apply_remote(state, operation)
  applied |> expect.to_be_error()
  let retained =
    applied |> result.map(fn(pair) { pair.0 }) |> result.unwrap(state)
  retained |> expect.to_equal(state)
  kernel.summary(retained) |> json.to_string |> expect.to_equal(before)
}

pub fn remove_cannot_carry_any_write_delta_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    expect_rejected(pair.0, kernel.Remove("gate", delta(pair.1)))
  })
}

pub fn write_constructors_cannot_be_swapped_test() -> Nil {
  let assert [#(tally, increment), #(lww, set), #(mv, write), #(members, add)] =
    writes()
  [
    #(mv, kernel.Increment("gate", 5, delta(write))),
    #(lww, kernel.Increment("gate", 5, delta(set))),
    #(tally, kernel.SetRegister("gate", "open", 10, delta(increment))),
    #(mv, kernel.SetRegister("gate", "open", 10, delta(write))),
    #(tally, kernel.SetMvRegister("gate", "open", delta(increment))),
    #(lww, kernel.SetMvRegister("gate", "open", delta(set))),
    #(members, kernel.Increment("gate", 5, delta(add))),
    #(members, kernel.SetRegister("gate", "open", 10, delta(add))),
    #(members, kernel.SetMvRegister("gate", "open", delta(add))),
    #(tally, kernel.AddMember("gate", "open", delta(increment))),
    #(lww, kernel.AddMember("gate", "open", delta(set))),
    #(mv, kernel.AddMember("gate", "open", delta(write))),
  ]
  |> list.each(fn(pair) { expect_rejected(pair.0, pair.1) })
}

pub fn intent_key_value_timestamp_and_amount_must_match_test() -> Nil {
  let assert [#(tally, increment), #(lww, set), #(mv, write), #(members, add)] =
    writes()
  [
    #(tally, kernel.Increment("other", 5, delta(increment))),
    #(tally, kernel.Increment("gate", -1, delta(increment))),
    #(tally, kernel.Increment("gate", 6, delta(increment))),
    #(lww, kernel.SetRegister("other", "open", 10, delta(set))),
    #(lww, kernel.SetRegister("gate", "closed", 10, delta(set))),
    #(lww, kernel.SetRegister("gate", "open", 11, delta(set))),
    #(mv, kernel.SetMvRegister("other", "open", delta(write))),
    #(mv, kernel.SetMvRegister("gate", "closed", delta(write))),
    #(members, kernel.AddMember("other", "open", delta(add))),
    #(members, kernel.AddMember("gate", "closed", delta(add))),
  ]
  |> list.each(fn(pair) { expect_rejected(pair.0, pair.1) })
}

pub fn removal_delta_cannot_be_used_as_a_write_or_renamed_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let assert Ok(#(state, _, removed, _)) = kernel.remove(pair.0, "gate")
    expect_rejected(state, with_delta(pair.1, delta(removed)))
    expect_rejected(state, kernel.Remove("other", delta(removed)))
  })
}

pub fn operation_mode_must_match_receiving_map_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    [
      kernel.TallyMode,
      kernel.RegisterMode,
      kernel.OrSetMode,
      kernel.MvRegisterMode,
    ]
    |> list.filter(fn(mode) { mode != pair.0.mode })
    |> list.each(fn(mode) { expect_rejected(new(mode), pair.1) })
  })
}

pub fn forged_stash_is_rejected_without_queuing_or_changing_caches_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let state = pair.0
    let forged = kernel.Remove("gate", delta(pair.1))
    let replayed = kernel.apply_stashed_operation(state, forged)
    replayed |> expect.to_be_error()
    replayed
    |> result.map(fn(replay) { replay.0 })
    |> result.unwrap(state)
    |> expect.to_equal(state)
  })
}

pub fn forged_ack_is_rejected_even_when_pending_operation_matches_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let forged = kernel.Remove("gate", delta(pair.1))
    let state =
      kernel.OrMapState(..pair.0, pending: [kernel.PendingOperation(forged, 0)])
    let acked = kernel.ack_local_with_message_id(state, forged, 0)
    acked |> expect.to_be_error()
    acked |> result.unwrap(state) |> expect.to_equal(state)
    kernel.ack_local(state, forged) |> expect.to_be_error()
  })
}

pub fn corrupt_pending_replay_is_rejected_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let forged = kernel.Remove("gate", delta(pair.1))
    let state =
      kernel.OrMapState(..pair.0, pending: [kernel.PendingOperation(forged, 0)])
    expect_rejected(state, pair.1)
    kernel.check_cache_coherence(state) |> expect.to_be_error()
  })
}

pub fn direct_and_p2p_channels_reject_forged_operations_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let state = channel.OrMapState(pair.0)
    let operation = channel.OrMapOperation(kernel.Remove("gate", delta(pair.1)))
    let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
    let direct = channel.apply_remote(state, operation, meta)
    let p2p = channel.apply_p2p_remote(state, operation)
    case pair.0.mode {
      kernel.OrSetMode -> {
        let assert Error(channel.OrMapOperationFailed(_)) = direct
        let assert Error(channel.OrMapOperationFailed(_)) = p2p
        Nil
      }
      kernel.TallyMode | kernel.RegisterMode | kernel.MvRegisterMode -> {
        let assert Error(channel.CorruptRemoteOperation(_)) = direct
        let assert Error(channel.CorruptRemoteOperation(_)) = p2p
        Nil
      }
    }
    direct
    |> result.map(fn(applied) { applied.0 })
    |> result.unwrap(state)
    |> expect.to_equal(state)
    p2p
    |> result.map(fn(applied) { applied.0 })
    |> result.unwrap(state)
    |> expect.to_equal(state)
  })
}

pub fn wire_rejects_forged_constructor_for_all_modes_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    json.parse(
      op.encode_or_map_operation(kernel.Remove("gate", delta(pair.1)))
        |> json.to_string,
      op.or_map_operation_decoder(),
    )
    |> expect.to_be_error()
  })
}

fn replace_nested(
  operation: kernel.OrMapOperation,
  field: String,
  transform: fn(String) -> String,
) -> kernel.OrMapOperation {
  let source = or_map.delta_to_json(delta(operation)) |> json.to_string
  let decoder = case field {
    "key_set_delta" -> decode.at(["state", field], decode.string)
    _ ->
      decode.at(
        ["state", "value_deltas"],
        decode.list(decode.field("crdt", decode.string, decode.success)),
      )
      |> decode.map(fn(leaves) {
        let assert [leaf] = leaves
        leaf
      })
  }
  let assert Ok(encoded) = json.parse(source, decoder)
  let corrupted =
    string.replace(
      source,
      json.string(encoded) |> json.to_string,
      json.string(transform(encoded)) |> json.to_string,
    )
  let assert Ok(delta) = or_map.delta_from_json(corrupted)
  with_delta(operation, delta)
}

pub fn malformed_key_tags_and_pruning_are_rejected_before_apply_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    [
      fn(source) { string.replace(source, "\"c\":1", "\"c\":0") },
      fn(source) { string.replace(source, "\"counter\":1", "\"counter\":-1") },
      fn(source) {
        string.replace(source, "\"clocks\":{}", "\"clocks\":{\"author\":1}")
      },
    ]
    |> list.each(fn(corrupt) {
      expect_rejected(pair.0, replace_nested(pair.1, "key_set_delta", corrupt))
    })
  })
}

pub fn mv_write_requires_the_new_authored_entry_not_just_visible_text_test() -> Nil {
  let assert [_, _, #(state, operation), _] = writes()
  [
    fn(source) {
      string.replace(
        source,
        "\"vclock\":{\"author\":1}",
        "\"vclock\":{\"author\":2}",
      )
    },
    fn(source) {
      string.replace(
        source,
        "\"vclock\":{\"author\":1}",
        "\"vclock\":{\"author\":1,\"other\":-1}",
      )
    },
    fn(source) {
      string.replace(
        source,
        "\"entries\":[{\"tag\":{\"r\":\"author\",\"c\":1},\"value\":\"open\"}]",
        "\"entries\":[]",
      )
    },
    fn(source) { string.replace(source, "\"author\"", "\"other\"") },
  ]
  |> list.each(fn(corrupt) {
    expect_rejected(state, replace_nested(operation, "crdt", corrupt))
  })
}

pub fn write_leaf_author_must_match_key_author_test() -> Nil {
  sparse_writes()
  |> list.each(fn(pair) {
    expect_rejected(
      pair.0,
      replace_nested(pair.1, "key_set_delta", fn(source) {
        string.replace(source, "\"r\":\"author\"", "\"r\":\"other\"")
      }),
    )
    expect_rejected(
      pair.0,
      replace_nested(pair.1, "crdt", fn(source) {
        string.replace(source, "\"author\"", "\"other\"")
      }),
    )
  })
}

pub fn removal_requires_matching_bounds_and_positive_tombstones_test() -> Nil {
  sparse_writes()
  |> list.each(fn(pair) {
    let assert Ok(#(_, _, removed, _)) = kernel.remove(pair.0, "gate")
    expect_rejected(
      pair.0,
      replace_nested(removed, "key_set_delta", fn(source) {
        string.replace(source, "\"c\":1", "\"c\":0")
      }),
    )
    expect_rejected(
      pair.0,
      replace_nested(removed, "key_set_delta", fn(source) {
        string.replace(source, "\"c\":1", "\"c\":2")
      }),
    )
    expect_rejected(
      pair.0,
      replace_nested(removed, "key_set_delta", fn(source) {
        string.replace(source, "\"counter\":1", "\"counter\":0")
      }),
    )
  })
}

pub fn set_removal_requires_bounded_key_and_leaf_tombstones_test() -> Nil {
  let assert Ok(#(state, _, _, _)) =
    kernel.add_member(new(kernel.OrSetMode), "gate", "open")
  let assert Ok(#(_, _, removed, _)) = kernel.remove(state, "gate")
  [
    fn(source) { string.replace(source, "\"c\":1", "\"c\":0") },
    fn(source) { string.replace(source, "\"c\":2", "\"c\":3") },
    fn(source) { string.replace(source, "\"counter\":2", "\"counter\":0") },
  ]
  |> list.each(fn(corrupt) {
    expect_rejected(state, replace_nested(removed, "key_set_delta", corrupt))
  })
  expect_rejected(
    state,
    replace_nested(removed, "crdt", fn(source) {
      string.replace(source, "\"c\":1", "\"c\":0")
    }),
  )
  let source =
    or_map.delta_to_json(delta(removed))
    |> json.to_string
    |> string.replace("\"author\":2", "\"author\":0")
  let assert Ok(unbounded) = or_map.delta_from_json(source)
  expect_rejected(state, with_delta(removed, unbounded))
}

pub fn set_history_survives_wire_and_both_channel_paths_test() -> Nil {
  let assert Ok(#(_, _, first)) =
    kernel.p2p_add_member(new(kernel.OrSetMode), "gate", "open")
  let assert Ok(#(writer, _)) =
    kernel.apply_remote(
      kernel.new(replica_id.new("other"), kernel.OrSetMode),
      first,
    )
  let assert Ok(#(writer, _, second)) =
    kernel.p2p_add_member(writer, "gate", "closed")
  let assert Ok(#(writer, _, member_removal)) =
    kernel.p2p_remove_member(writer, "gate", "open")
  let assert Ok(#(_, _, key_removal)) = kernel.p2p_remove(writer, "gate")
  let initial =
    channel.OrMapState(kernel.new(replica_id.new("peer"), kernel.OrSetMode))
  let _ =
    list.fold(
      [
        #(first, [#("gate", kernel.SetMembers(["open"]))]),
        #(second, [#("gate", kernel.SetMembers(["closed", "open"]))]),
        #(member_removal, [#("gate", kernel.SetMembers(["closed"]))]),
        #(key_removal, []),
      ],
      #(initial, initial),
      fn(channels, step) {
        let assert Ok(operation) =
          json.parse(
            op.encode_or_map_operation(step.0) |> json.to_string,
            op.or_map_operation_decoder(),
          )
        operation |> expect.to_equal(step.0)
        let operation = channel.OrMapOperation(operation)
        let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
        let assert Ok(#(channel.OrMapState(direct), _, _)) =
          channel.apply_remote(channels.0, operation, meta)
        let assert Ok(#(channel.OrMapState(p2p), _)) =
          channel.apply_p2p_remote(channels.1, operation)
        list.each([direct, p2p], fn(state) {
          kernel.entries(state) |> expect.to_equal(step.1)
          kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
        })
        #(channel.OrMapState(direct), channel.OrMapState(p2p))
      },
    )
  Nil
}

pub fn removal_cannot_relabel_tombstones_for_another_known_key_test() -> Nil {
  sparse_writes()
  |> list.each(fn(pair) {
    let assert Ok(state) = kernel.ack_local(pair.0, pair.1)
    let assert Ok(#(_, _, removed, _)) = kernel.remove(state, "gate")
    let source =
      or_map.delta_to_json(delta(removed))
      |> json.to_string
      |> string.replace("\"gate\"", "\"other\"")
    let assert Ok(relabeled) = or_map.delta_from_json(source)
    let forged = kernel.Remove("other", relabeled)
    [pair.0, state]
    |> list.each(fn(state) {
      expect_rejected(state, forged)
      kernel.apply_stashed_operation(state, forged) |> expect.to_be_error()
      let matching_pending =
        kernel.OrMapState(..state, pending: [kernel.PendingOperation(forged, 0)])
      kernel.ack_local(matching_pending, forged) |> expect.to_be_error()
    })
  })
}

pub fn relabeled_removal_before_add_is_rejected_and_add_survives_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let assert Ok(author) = kernel.ack_local(pair.0, pair.1)
    let assert Ok(#(_, _, removed, _)) = kernel.remove(author, "gate")
    let peer = kernel.new(replica_id.new("peer"), author.mode)
    let forged = kernel.Remove("other", delta(removed))
    let applied = kernel.apply_remote(peer, forged)
    let retained =
      applied |> result.map(fn(pair) { pair.0 }) |> result.unwrap(peer)
    let assert Ok(#(received, _)) = kernel.apply_remote(retained, pair.1)
    kernel.get(received, "gate")
    |> expect.to_equal(kernel.get(author, "gate"))
    let assert Error(error) = applied
    case author.mode {
      kernel.OrSetMode -> {
        let assert kernel.InvalidSetState(_) = error
        Nil
      }
      kernel.TallyMode | kernel.RegisterMode | kernel.MvRegisterMode -> {
        let assert kernel.CorruptDelta(_) = error
        Nil
      }
    }
    retained |> expect.to_equal(peer)
    kernel.validate_operation(author.mode, forged) |> expect.to_be_error()
    json.parse(
      op.encode_or_map_operation(forged) |> json.to_string,
      op.or_map_operation_decoder(),
    )
    |> expect.to_be_error()
  })
}

pub fn valid_removal_before_add_converges_with_ordered_delivery_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let assert Ok(author) = kernel.ack_local(pair.0, pair.1)
    let assert Ok(#(author, _, removed, id)) = kernel.remove(author, "gate")
    let assert Ok(author) =
      kernel.ack_local_with_message_id(author, removed, id)
    let assert Ok(removed) =
      json.parse(
        op.encode_or_map_operation(removed) |> json.to_string,
        op.or_map_operation_decoder(),
      )
    let peer = kernel.new(replica_id.new("peer"), author.mode)
    [[removed, pair.1, removed, pair.1], [pair.1, removed]]
    |> list.each(fn(operations) {
      let received =
        list.fold(operations, peer, fn(state, operation) {
          let assert Ok(#(state, _)) = kernel.apply_remote(state, operation)
          state
        })
      kernel.entries(received) |> expect.to_equal([])
      kernel.sequenced_entries(received) |> expect.to_equal([])
      kernel.entries(received) |> expect.to_equal(kernel.entries(author))
      kernel.check_cache_coherence(received) |> expect.to_equal(Ok(Nil))
    })
  })
}

pub fn write_delta_cannot_also_remove_or_write_another_key_test() -> Nil {
  writes()
  |> list.each(fn(pair) {
    let assert Ok(#(_, _, removed, _)) = kernel.remove(pair.0, "gate")
    let assert Ok(mixed) = or_map.merge_deltas(delta(pair.1), delta(removed))
    expect_rejected(pair.0, with_delta(pair.1, mixed))
    let assert Ok(#(_, _, other, _)) = case pair.0.mode {
      kernel.TallyMode -> kernel.increment(pair.0, "other", 1)
      kernel.RegisterMode -> kernel.set_register(pair.0, "other", "extra", 20)
      kernel.OrSetMode -> kernel.add_member(pair.0, "other", "extra")
      kernel.MvRegisterMode -> kernel.set_mv_register(pair.0, "other", "extra")
    }
    let assert Ok(mixed) = or_map.merge_deltas(delta(pair.1), delta(other))
    expect_rejected(pair.0, with_delta(pair.1, mixed))
  })
}

pub fn cumulative_tallies_allow_reordering_duplicates_and_zero_test() -> Nil {
  let assert Ok(#(author, _, first, _)) =
    kernel.increment(new(kernel.TallyMode), "gate", -3)
  let assert Ok(#(author, _, second, _)) = kernel.increment(author, "gate", 5)
  let assert Ok(#(_, _, third, _)) = kernel.increment(author, "gate", 0)
  let peer = new(kernel.TallyMode)
  let peer =
    list.fold([third, first, second, third], peer, fn(peer, operation) {
      let assert Ok(#(peer, _)) = kernel.apply_remote(peer, operation)
      peer
    })
  kernel.get(peer, "gate") |> expect.to_equal(Ok(kernel.Tally(2)))
  writes()
  |> list.each(fn(pair) {
    let state = new(pair.0.mode)
    let assert Ok(#(state, _, stashed, id)) =
      kernel.apply_stashed_operation(state, pair.1)
    let assert Ok(state) = kernel.ack_local_with_message_id(state, stashed, id)
    let assert Ok(#(state, [])) = kernel.apply_remote(state, stashed)
    let assert Ok(#(_, _, absent, _)) = kernel.remove(state, "absent")
    let assert Ok(#(unchanged, [])) = kernel.apply_remote(state, absent)
    kernel.entries(unchanged) |> expect.to_equal(kernel.entries(state))
  })
}
