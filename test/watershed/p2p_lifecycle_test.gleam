import gleam/json
import gleam/list
import gleam/string
import startest/expect

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/result
import watershed/channel
@target(javascript)
import watershed/crdt_js
@target(javascript)
import watershed/crdt_wire
import watershed/g_set_kernel
@target(javascript)
import watershed/lww_register_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/p2p_fake
import watershed/pn_counter_kernel
@target(javascript)
import watershed/relay_fake
@target(javascript)
import watershed/schema
import watershed/sequence_kernel
import watershed/text_kernel
@target(javascript)
import watershed/transport_js
import watershed/two_p_set_kernel

// The JavaScript caller can bypass the phantom type on this existing export.
@target(javascript)
@external(javascript, "./crdt_js.mjs", "root")
fn mislabelled_lww_root(
  document: crdt_js.CrdtDocument(schema.GCounterChannel),
) -> crdt_js.Handle(schema.LwwRegisterChannel)

@target(javascript)
@external(javascript, "./crdt_js.mjs", "root")
fn mislabelled_or_map_root(
  document: crdt_js.CrdtDocument(schema.GCounterChannel),
) -> crdt_js.Handle(schema.OrMapChannel)

@target(javascript)
pub fn set_map_public_preflight_preserves_channel_and_closed_errors_test() -> Nil {
  let world = p2p_fake.new_world()
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: "set-map-wrong-kind",
      replica_label: "counter",
      compatibility_tag: "set-map/v1",
      root: p2p.g_counter_root(),
      signaling: p2p_fake.signaling(world),
    ))
  let statuses = transport_js.new_cell([])
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(_) { Nil },
      on_status: fn(status) {
        transport_js.set_cell(statuses, [
          status,
          ..transport_js.get_cell(statuses)
        ])
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  p2p_fake.settle(world)
  transport_js.set_cell(statuses, [])
  let map = mislabelled_or_map_root(document)
  let before = crdt_js.digest(document)
  let mismatch =
    p2p.ChannelTypeMismatch(
      "root",
      channel.OrMapChannel,
      channel.GCounterChannel,
    )
  crdt_js.or_map_add_member(map, "doc", "draft")
  |> expect.to_equal(Error(mismatch))
  crdt_js.or_map_remove_member(map, "doc", "draft")
  |> expect.to_equal(Error(mismatch))
  crdt_js.or_map_remove_key(map, "doc") |> expect.to_equal(Error(mismatch))
  crdt_js.or_map_value(map, "missing") |> expect.to_equal(Error(mismatch))
  transport_js.get_cell(statuses)
  |> expect.to_equal([
    crdt_js.Failed(mismatch),
    crdt_js.Failed(mismatch),
    crdt_js.Failed(mismatch),
    crdt_js.Failed(mismatch),
  ])
  crdt_js.digest(document) |> expect.to_equal(before)
  crdt_js.g_counter_value(crdt_js.root(document)) |> expect.to_equal(Ok(0))
  crdt_js.close(connection)
  crdt_js.or_map_add_member(map, "doc", "draft")
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.or_map_remove_member(map, "doc", "draft")
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.or_map_remove_key(map, "doc")
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.or_map_value(map, "missing")
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.digest(document) |> expect.to_equal(before)
}

@target(javascript)
fn lww_config(
  world: p2p_fake.World,
  clock: relay_fake.Clock,
  label: String,
) -> crdt_js.Config(schema.LwwRegisterChannel) {
  crdt_js.config(
    room_id: "lww-lifecycle",
    replica_label: label,
    compatibility_tag: "lww-register/v1",
    root: p2p.lww_register_root(),
    signaling: p2p_fake.signaling(world),
  )
  |> crdt_js.with_scheduler(relay_fake.scheduler(clock))
}

@target(javascript)
fn lww_document(
  world: p2p_fake.World,
  clock: relay_fake.Clock,
  label: String,
) -> crdt_js.CrdtDocument(schema.LwwRegisterChannel) {
  let assert Ok(document) =
    crdt_js.new_document(lww_config(world, clock, label))
  document
}

@target(javascript)
fn attach_lww(
  world: p2p_fake.World,
  document: crdt_js.CrdtDocument(schema.LwwRegisterChannel),
) -> #(
  crdt_js.CrdtConnection,
  transport_js.Cell(List(Result(String, p2p.P2pError))),
) {
  let readies = transport_js.new_cell([])
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(outcome) {
        let value =
          result.try(outcome, fn(ready) {
            crdt_js.lww_register_value(crdt_js.root(ready))
          })
        transport_js.set_cell(readies, [value, ..transport_js.get_cell(readies)])
      },
      on_status: fn(_) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  #(connection, readies)
}

@target(javascript)
fn converge_lww(
  world: p2p_fake.World,
  clock: relay_fake.Clock,
  documents: List(crdt_js.CrdtDocument(schema.LwwRegisterChannel)),
  fuel: Int,
) -> Nil {
  p2p_fake.settle(world)
  case list.map(documents, crdt_js.digest) |> list.unique, fuel {
    [_], _ -> Nil
    _, 0 -> panic as "LWW register peers did not converge"
    _, _ -> {
      relay_fake.advance(clock, crdt_js.default_anti_entropy_milliseconds)
      converge_lww(world, clock, documents, fuel - 1)
    }
  }
}

@target(javascript)
fn lww_metadata(
  document: crdt_js.CrdtDocument(schema.LwwRegisterChannel),
) -> #(Int, String) {
  let assert Ok(snapshot) = crdt_js.export_snapshot(document)
  let metadata = {
    use timestamp <- decode.field("timestamp", decode.int)
    use author <- decode.field("replica_id", decode.string)
    decode.success(#(timestamp, author))
  }
  let assert Ok([metadata]) =
    json.parse(
      json.to_string(snapshot),
      decode.at(
        ["channels"],
        decode.list(decode.at(["snapshot", "state"], metadata)),
      ),
    )
  metadata
}

@target(javascript)
pub fn lww_register_public_mesh_converges_concurrent_writes_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let a = lww_document(world, clock, "a")
  let b = lww_document(world, clock, "b")
  let #(a_connection, a_readies) = attach_lww(world, a)
  let #(b_connection, b_readies) = attach_lww(world, b)
  p2p_fake.settle(world)
  transport_js.get_cell(a_readies) |> expect.to_equal([Ok("")])
  transport_js.get_cell(b_readies) |> expect.to_equal([Ok("")])

  let before = transport_js.now_milliseconds()
  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(a), "left")
  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(b), "right")
  crdt_js.lww_register_value(crdt_js.root(a)) |> expect.to_equal(Ok("left"))
  crdt_js.lww_register_value(crdt_js.root(b)) |> expect.to_equal(Ok("right"))
  { lww_metadata(a).0 >= before } |> expect.to_be_true()
  { lww_metadata(b).0 >= before } |> expect.to_be_true()

  converge_lww(world, clock, [a, b], 12)
  let assert Ok(winner) = crdt_js.lww_register_value(crdt_js.root(a))
  list.contains(["left", "right"], winner) |> expect.to_be_true()
  crdt_js.lww_register_value(crdt_js.root(b)) |> expect.to_equal(Ok(winner))
  lww_metadata(a) |> expect.to_equal(lww_metadata(b))
  crdt_js.close(a_connection)
  crdt_js.close(b_connection)
}

@target(javascript)
pub fn lww_register_same_value_newer_metadata_crosses_three_peer_chain_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let a = lww_document(world, clock, "a")
  let b = lww_document(world, clock, "b")
  let c = lww_document(world, clock, "c")
  let #(a_connection, _) = attach_lww(world, a)
  let #(b_connection, _) = attach_lww(world, b)
  let #(c_connection, _) = attach_lww(world, c)
  p2p_fake.settle(world)
  p2p_fake.sever(world, crdt_js.replica_id(a), crdt_js.replica_id(c))
  p2p_fake.settle(world)
  let observations =
    list.map([a, b, c], fn(document) {
      let events = transport_js.new_cell([])
      let subscription =
        crdt_js.subscribe_lww_register(crdt_js.root(document), fn(event) {
          transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
        })
      #(subscription, events)
    })
  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(a), "ready")
  converge_lww(world, clock, [a, b, c], 12)
  let before = crdt_js.digest(a)
  let timestamp = lww_metadata(a).0
  let deltas =
    p2p_fake.channel_payloads(world)
    |> list.filter(fn(packet) {
      let assert Ok(envelope) =
        crdt_wire.decode_envelope(packet.2, crdt_wire.default_limits())
      case envelope.message {
        crdt_wire.Delta(..) -> True
        _ -> False
      }
    })
  deltas |> expect.to_not_equal([])

  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(a), "ready")
  crdt_js.digest(a) |> expect.to_not_equal(before)
  { lww_metadata(a).0 > timestamp } |> expect.to_be_true()
  p2p_fake.settle(world)
  crdt_js.digest(b) |> expect.to_equal(crdt_js.digest(a))
  crdt_js.digest(c) |> expect.to_equal(before)
  converge_lww(world, clock, [a, b, c], 12)
  list.each(list.append(list.reverse(deltas), deltas), fn(packet) {
    let rtc = p2p_fake.rtc(world, packet.0)
    rtc.send(packet.1, packet.2) |> expect.to_be_true()
  })
  p2p_fake.settle(world)
  list.each([a, b, c], fn(document) {
    crdt_js.lww_register_value(crdt_js.root(document))
    |> expect.to_equal(Ok("ready"))
    crdt_js.digest(document) |> expect.to_not_equal(before)
    lww_metadata(document) |> expect.to_equal(lww_metadata(a))
  })
  list.each(observations, fn(observation) {
    transport_js.get_cell(observation.1)
    |> expect.to_equal([lww_register_kernel.Changed("", "ready")])
    crdt_js.unsubscribe(observation.0)
  })
  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(a), "done")
  converge_lww(world, clock, [a, b, c], 12)
  list.each(observations, fn(observation) {
    transport_js.get_cell(observation.1)
    |> expect.to_equal([lww_register_kernel.Changed("", "ready")])
  })
  list.each([a_connection, b_connection, c_connection], crdt_js.close)
}

@target(javascript)
pub fn lww_register_late_join_and_import_preserve_author_and_clock_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let future = 8_000_000_000_000_000
  { transport_js.now_milliseconds() < future } |> expect.to_be_true()
  let snapshot =
    json.object([
      #("v", json.int(1)),
      #("room", json.string("lww-lifecycle")),
      #("compatibility", json.string("lww-register/v1")),
      #("root", json.string("lwwRegister")),
      #(
        "channels",
        json.array(
          [
            json.object([
              #(
                "descriptor",
                json.object([
                  #("address", json.string("root")),
                  #("channelType", json.string("lwwRegister")),
                  #("createdBy", json.string("")),
                ]),
              ),
              #(
                "snapshot",
                json.object([
                  #("type", json.string("lww_register")),
                  #("v", json.int(2)),
                  #(
                    "state",
                    json.object([
                      #("value", json.string("saved")),
                      #("timestamp", json.int(future)),
                      #("replica_id", json.string("original-author")),
                    ]),
                  ),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let assert Ok(a) =
    crdt_js.import_snapshot(lww_config(world, clock, "a"), snapshot)
  lww_metadata(a) |> expect.to_equal(#(future, "original-author"))
  let #(a_connection, _) = attach_lww(world, a)
  p2p_fake.settle(world)

  let late = lww_document(world, clock, "late")
  let #(late_connection, readies) = attach_lww(world, late)
  transport_js.get_cell(readies) |> expect.to_equal([])
  converge_lww(world, clock, [a, late], 12)
  transport_js.get_cell(readies) |> expect.to_equal([Ok("saved")])
  lww_metadata(late) |> expect.to_equal(#(future, "original-author"))
  let assert Ok(Nil) = crdt_js.lww_register_set(crdt_js.root(late), "joined")
  lww_metadata(late)
  |> expect.to_equal(#(future + 1, crdt_js.replica_id(late)))
  converge_lww(world, clock, [a, late], 12)
  crdt_js.lww_register_value(crdt_js.root(a)) |> expect.to_equal(Ok("joined"))

  let assert Ok(exported) = crdt_js.export_snapshot(late)
  let assert Ok(restored) =
    crdt_js.import_snapshot(lww_config(world, clock, "restored"), exported)
  crdt_js.digest(restored) |> expect.to_equal(crdt_js.digest(late))
  lww_metadata(restored)
  |> expect.to_equal(#(future + 1, crdt_js.replica_id(late)))
  crdt_js.replica_id(restored) |> expect.to_not_equal(crdt_js.replica_id(late))
  let assert Ok(Nil) =
    crdt_js.lww_register_set(crdt_js.root(restored), "restored")
  lww_metadata(restored)
  |> expect.to_equal(#(future + 2, crdt_js.replica_id(restored)))
  let #(restored_connection, _) = attach_lww(world, restored)
  converge_lww(world, clock, [a, late, restored], 12)
  list.each([a, late, restored], fn(document) {
    crdt_js.lww_register_value(crdt_js.root(document))
    |> expect.to_equal(Ok("restored"))
    lww_metadata(document)
    |> expect.to_equal(#(future + 2, crdt_js.replica_id(restored)))
  })
  list.each([a_connection, late_connection, restored_connection], crdt_js.close)
}

@target(javascript)
pub fn lww_register_wrong_kind_and_closed_document_fail_test() -> Nil {
  let world = p2p_fake.new_world()
  let clock = relay_fake.new_clock()
  let assert Ok(counter_document) =
    crdt_js.new_document(crdt_js.config(
      room_id: "lww-wrong-kind",
      replica_label: "counter",
      compatibility_tag: "lww-register/v1",
      root: p2p.g_counter_root(),
      signaling: p2p_fake.signaling(world),
    ))
  let statuses = transport_js.new_cell([])
  let counter_connection =
    crdt_js.attach_with_rtc(
      counter_document,
      on_ready: fn(_) { Nil },
      on_status: fn(status) {
        transport_js.set_cell(statuses, [
          status,
          ..transport_js.get_cell(statuses)
        ])
      },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(counter_document)),
    )
  p2p_fake.settle(world)
  let mislabelled = mislabelled_lww_root(counter_document)
  let counter_digest = crdt_js.digest(counter_document)
  crdt_js.lww_register_value(mislabelled)
  |> expect.to_equal(
    Error(p2p.ChannelTypeMismatch(
      "root",
      channel.LwwRegisterChannel,
      channel.GCounterChannel,
    )),
  )
  transport_js.set_cell(statuses, [])
  crdt_js.lww_register_set(mislabelled, "wrong kind")
  |> expect.to_equal(
    Error(p2p.ChannelTypeMismatch(
      "root",
      channel.LwwRegisterChannel,
      channel.GCounterChannel,
    )),
  )
  transport_js.get_cell(statuses)
  |> expect.to_equal([
    crdt_js.Failed(p2p.ChannelTypeMismatch(
      "root",
      channel.LwwRegisterChannel,
      channel.GCounterChannel,
    )),
  ])
  crdt_js.digest(counter_document) |> expect.to_equal(counter_digest)
  crdt_js.g_counter_value(crdt_js.root(counter_document))
  |> expect.to_equal(Ok(0))
  crdt_js.close(counter_connection)
  crdt_js.lww_register_set(mislabelled, "closed wrong kind")
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.digest(counter_document) |> expect.to_equal(counter_digest)
  let document = lww_document(world, clock, "a")
  let root = crdt_js.root(document)
  let assert Ok(counter) =
    crdt_js.create_channel(document, p2p.g_counter_root())
  let before = crdt_js.digest(document)
  crdt_js.resolve_channel(
    document,
    p2p.lww_register_root(),
    crdt_js.address(counter),
  )
  |> expect.to_equal(
    Error(p2p.ChannelTypeMismatch(
      crdt_js.address(counter),
      channel.LwwRegisterChannel,
      channel.GCounterChannel,
    )),
  )
  crdt_js.digest(document) |> expect.to_equal(before)
  crdt_js.g_counter_value(counter) |> expect.to_equal(Ok(0))
  let #(connection, _) = attach_lww(world, document)
  p2p_fake.settle(world)
  let assert Ok(Nil) = crdt_js.lww_register_set(root, "open")
  crdt_js.close(connection)
  crdt_js.lww_register_value(root)
  |> expect.to_equal(Error(p2p.DocumentClosed))
  crdt_js.lww_register_set(root, "closed")
  |> expect.to_equal(Error(p2p.DocumentClosed))
}

/// Deliver every operation in order via `apply_p2p_remote`, asserting each
/// merge succeeds. Mirrors how a p2p peer folds a batch of remote operations
/// over its channel state.
fn deliver(
  state: channel.ChannelState,
  operations: List(channel.ChannelOperation),
) -> channel.ChannelState {
  list.fold(operations, state, fn(state, operation) {
    let assert Ok(#(state, _events)) =
      channel.apply_p2p_remote(state, operation)
    state
  })
}

/// Assert that delivering `operations` to a fresh replica (from `make`)
/// converges to the same `read` result regardless of delivery order, and stays
/// there even when the whole batch is redelivered a second time — exhaustively,
/// across every permutation of `operations`, not just one shuffled sample.
/// Returns the converged value so callers can also check it against a
/// hand-computed expectation.
fn assert_converges(
  make: fn() -> channel.ChannelState,
  operations: List(channel.ChannelOperation),
  read: fn(channel.ChannelState) -> a,
) -> a {
  let expected = read(deliver(make(), operations))
  list.permutations(operations)
  |> list.each(fn(order) {
    deliver(make(), order) |> read |> expect.to_equal(expected)
    deliver(make(), list.append(order, order))
    |> read
    |> expect.to_equal(expected)
  })
  expected
}

fn expect_unsupported_p2p(result: Result(a, channel.ChannelError)) -> Nil {
  case result {
    Error(channel.UnsupportedP2p(_)) -> Nil
    Ok(_)
    | Error(channel.UnexpectedAck(..))
    | Error(channel.WrongChannelType(..))
    | Error(channel.CorruptRemoteOperation(..))
    | Error(channel.OrMapOperationFailed(..)) ->
      panic as "expected Error(channel.UnsupportedP2p(_))"
  }
}

// --- local commit invariants: visible + confirmed update together, pending
// --- stays empty, for every `supports_p2p` kernel. --------------------------

pub fn pn_counter_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(7))

  events
  |> expect.to_equal([channel.PnCounterEvent(pn_counter_kernel.Updated(7, 7))])

  let assert channel.PnCounterState(kernel) = state
  kernel.pending |> expect.to_equal([])
  pn_counter_kernel.value(kernel) |> expect.to_equal(7)
  pn_counter_kernel.sequenced_value(kernel) |> expect.to_equal(7)
}

pub fn or_map_tally_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score")
  |> expect.to_equal(Ok(or_map_kernel.Tally(4)))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_register_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", "Ann", 1),
    )

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "name")
  |> expect.to_equal(Ok(or_map_kernel.Register("Ann")))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_remove_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapRemoveEdit("score"))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score") |> expect.to_equal(Error(Nil))
}

pub fn or_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))

  let assert channel.OrSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_set_kernel.values(kernel) |> expect.to_equal(["x"])
  or_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn g_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitGSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit("x"))

  let assert channel.GSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  g_set_kernel.values(kernel) |> expect.to_equal(["x"])
  g_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn two_p_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit("x"))

  let assert channel.TwoPSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  two_p_set_kernel.values(kernel) |> expect.to_equal(["x"])
  two_p_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn sequence_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([json.string("a")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("a")])
}

pub fn sequence_delete_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.SequenceDeleteEdit(0))

  events
  |> expect.to_equal([
    channel.SequenceEvent(sequence_kernel.SequenceChanged([])),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([])
  sequence_kernel.sequenced_values(kernel) |> expect.to_equal([])
}

pub fn sequence_move_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(1, json.string("b")),
    )
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.SequenceMoveEdit(1, 0))

  events
  |> expect.to_equal([
    channel.SequenceEvent(
      sequence_kernel.SequenceChanged([json.string("b"), json.string("a")]),
    ),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel)
  |> expect.to_equal([json.string("b"), json.string("a")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("b"), json.string("a")])
}

pub fn sequence_replace_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceReplaceEdit(0, json.string("b")),
    )

  events
  |> expect.to_equal([
    channel.SequenceEvent(sequence_kernel.SequenceChanged([json.string("b")])),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([json.string("b")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("b")])
}

pub fn text_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hi"))

  events |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hi"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hi")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hi")
}

pub fn text_delete_range_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(1, 3))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hlo"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hlo")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hlo")
}

pub fn text_replace_range_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextReplaceRangeEdit(0, 5, "world"))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("world"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("world")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("world")
}

pub fn text_append_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello "))
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextAppendEdit("world"))

  events
  |> expect.to_equal([
    channel.TextEvent(text_kernel.TextChanged("hello world")),
  ])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hello world")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hello world")
}

pub fn text_empty_edit_still_commits_an_operation_test() -> Nil {
  // Unlike the server-backed `insert`, the p2p path always reports an operation
  // — there is no pending queue to spare from a content-free entry, so even a
  // no-operation edit (inserting "") is harmless to commit and broadcast.
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, operation)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, ""))

  events |> expect.to_equal([])
  case operation {
    channel.TextOperation(text_kernel.Insert(0, "", _delta)) -> Nil
    channel.TextOperation(text_kernel.Insert(..))
    | channel.TextOperation(text_kernel.DeleteRange(..))
    | channel.TextOperation(text_kernel.ReplaceRange(..))
    | channel.TextOperation(text_kernel.Append(..))
    | channel.MapOperation(..)
    | channel.CounterOperation(..)
    | channel.PnCounterOperation(..)
    | channel.GCounterOperation(..)
    | channel.LwwRegisterOperation(..)
    | channel.MvRegisterOperation(..)
    | channel.OrMapOperation(..)
    | channel.OrSetOperation(..)
    | channel.GSetOperation(..)
    | channel.TwoPSetOperation(..)
    | channel.RegisterCollectionOperation(..)
    | channel.ClaimsOperation(..)
    | channel.TaskManagerOperation(..)
    | channel.PactMapOperation(..)
    | channel.JsonOtOperation(..)
    | channel.DirectoryOperation(..)
    | channel.OrderedCollectionOperation(..)
    | channel.SequenceOperation(..)
    | channel.RichTextOperation(..) ->
      panic as "expected an Insert(0, \"\", _) op even for an empty edit"
  }

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("")
}

// --- dispatch rejection: ineligible channels and mismatched edits/operations.
// -----

pub fn apply_p2p_local_rejects_ineligible_channel_test() -> Nil {
  let state = channel.new(channel.InitMap, replica: "a")
  channel.apply_p2p_local(state, channel.PnCounterEdit(1))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_ineligible_channel_test() -> Nil {
  let state = channel.new(channel.InitMap, replica: "a")
  let counter = channel.new(channel.InitPnCounter, replica: "b")
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(counter, channel.PnCounterEdit(1))

  channel.apply_p2p_remote(state, operation) |> expect_unsupported_p2p
}

pub fn apply_p2p_local_rejects_mismatched_edit_test() -> Nil {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_mismatched_operation_test() -> Nil {
  let pn_counter_state = channel.new(channel.InitPnCounter, replica: "a")
  let text_state = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(_, _, text_operation)) =
    channel.apply_p2p_local(text_state, channel.TextAppendEdit("z"))

  channel.apply_p2p_remote(pn_counter_state, text_operation)
  |> expect_unsupported_p2p
}

pub fn or_map_increment_against_register_mode_is_rejected_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapIncrementEdit("k", 1))
  |> expect_unsupported_p2p
}

pub fn or_map_set_register_against_tally_mode_is_rejected_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapSetRegisterEdit("k", "v", 1))
  |> expect_unsupported_p2p
}

pub fn sequence_edit_out_of_bounds_is_rejected_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  channel.apply_p2p_local(state, channel.SequenceDeleteEdit(0))
  |> expect_unsupported_p2p
}

pub fn text_edit_out_of_bounds_is_rejected_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(0, 1))
  |> expect_unsupported_p2p
}

// --- convergence: operations authored via `apply_p2p_local` on distinct
// replicas --- converge on a third replica no matter the delivery order, and
// survive --- a full redelivery of the batch (idempotence).
// --------------------------

fn pn_counter_operation(
  replica: String,
  amount: Int,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitPnCounter, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(amount))
  operation
}

pub fn pn_counter_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    pn_counter_operation("a", 5),
    pn_counter_operation("b", -2),
    pn_counter_operation("c", 10),
  ]
  let read = fn(state) {
    let assert channel.PnCounterState(kernel) = state
    #(
      pn_counter_kernel.value(kernel),
      pn_counter_kernel.sequenced_value(kernel),
      kernel.pending == [],
    )
  }

  assert_converges(
    fn() { channel.new(channel.InitPnCounter, replica: "z") },
    operations,
    read,
  )
  |> expect.to_equal(#(13, 13, True))
}

fn or_map_increment_operation(
  replica: String,
  amount: Int,
) -> channel.ChannelOperation {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", amount))
  operation
}

pub fn or_map_tally_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    or_map_increment_operation("a", 3),
    or_map_increment_operation("b", -1),
    or_map_increment_operation("c", 4),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "score"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "z")
    },
    operations,
    read,
  )
  |> expect.to_equal(#(Ok(or_map_kernel.Tally(6)), True))
}

fn or_map_register_operation(
  replica: String,
  value: String,
  timestamp: Int,
) -> channel.ChannelOperation {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", value, timestamp),
    )
  operation
}

pub fn or_map_register_p2p_converges_on_highest_timestamp_test() -> Nil {
  let operations = [
    or_map_register_operation("a", "first", 5),
    or_map_register_operation("b", "second", 10),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "name"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "z")
    },
    operations,
    read,
  )
  |> expect.to_equal(#(Ok(or_map_kernel.Register("second")), True))
}

fn or_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitOrSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit(element))
  operation
}

pub fn or_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    or_set_add_operation("a", "x"),
    or_set_add_operation("b", "y"),
    or_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.OrSetState(kernel) = state
    #(or_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitOrSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn or_set_add_then_observed_remove_converges_across_order_test() -> Nil {
  let state_a = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(_, _, add_operation)) =
    channel.apply_p2p_local(state_a, channel.OrSetAddEdit("x"))

  let state_b = channel.new(channel.InitOrSet, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, add_operation)
  let assert Ok(#(state_b, _, remove_operation)) =
    channel.apply_p2p_local(state_b, channel.OrSetRemoveEdit("x"))

  // The remove edit itself commits immediately too: no pending entry.
  let assert channel.OrSetState(remove_kernel) = state_b
  remove_kernel.pending |> expect.to_equal([])
  or_set_kernel.values(remove_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.OrSetState(kernel) = state
    #(or_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitOrSet, replica: "o") },
    [add_operation, remove_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

fn g_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitGSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit(element))
  operation
}

pub fn g_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    g_set_add_operation("a", "x"),
    g_set_add_operation("b", "y"),
    g_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.GSetState(kernel) = state
    #(g_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitGSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

fn two_p_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitTwoPSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit(element))
  operation
}

pub fn two_p_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    two_p_set_add_operation("a", "x"),
    two_p_set_add_operation("b", "y"),
    two_p_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.TwoPSetState(kernel) = state
    #(two_p_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitTwoPSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn two_p_set_add_then_remove_converges_across_order_test() -> Nil {
  let state_a = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state_a, _, add_operation)) =
    channel.apply_p2p_local(state_a, channel.TwoPSetAddEdit("x"))
  let assert Ok(#(state_a, _, remove_operation)) =
    channel.apply_p2p_local(state_a, channel.TwoPSetRemoveEdit("x"))

  // The remove edit itself commits immediately too: no pending entry.
  let assert channel.TwoPSetState(remove_kernel) = state_a
  remove_kernel.pending |> expect.to_equal([])
  two_p_set_kernel.values(remove_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.TwoPSetState(kernel) = state
    #(two_p_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitTwoPSet, replica: "o") },
    [add_operation, remove_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

/// Three replicas concurrently insert a distinct element at index 0, none
/// having observed the others yet — the sequence CRDT's identities (not
/// index) must give every replica's insert a stable position so delivery
/// order never matters.
pub fn sequence_concurrent_inserts_converge_across_order_test() -> Nil {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitSequence, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(
        state,
        channel.SequenceInsertEdit(0, json.string(value)),
      )
    operation
  }
  let operations = [
    insert_at("a", "a"),
    insert_at("b", "b"),
    insert_at("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  let #(values, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitSequence, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  list.length(values) |> expect.to_equal(3)
  list.contains(values, json.string("a")) |> expect.to_equal(True)
  list.contains(values, json.string("b")) |> expect.to_equal(True)
  list.contains(values, json.string("c")) |> expect.to_equal(True)
}

pub fn sequence_delete_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(state_b, _, delete_operation)) =
    channel.apply_p2p_local(state_b, channel.SequenceDeleteEdit(0))

  // The delete edit itself commits immediately too: no pending entry.
  let assert channel.SequenceState(delete_kernel) = state_b
  delete_kernel.pending |> expect.to_equal([])
  sequence_kernel.values(delete_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_operation, delete_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

pub fn sequence_replace_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(_, _, replace_operation)) =
    channel.apply_p2p_local(
      state_b,
      channel.SequenceReplaceEdit(0, json.string("y")),
    )

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_operation, replace_operation],
    read,
  )
  |> expect.to_equal(#([json.string("y")], True))
}

/// A move authored on top of two already-merged concurrent inserts. The
/// move operation's identity refers to the item it targets, so it is delivered
/// here alongside the inserts it depends on; every order (and a full
/// redelivered duplicate of the batch) must still converge.
pub fn sequence_move_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state_a, _, insert_a_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(_, _, insert_b_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(1, json.string("b")),
    )

  let state_c = channel.new(channel.InitSequence, replica: "c")
  let assert Ok(#(state_c, _)) =
    channel.apply_p2p_remote(state_c, insert_a_operation)
  let assert Ok(#(state_c, _)) =
    channel.apply_p2p_remote(state_c, insert_b_operation)
  let assert Ok(#(_, _, move_operation)) =
    channel.apply_p2p_local(state_c, channel.SequenceMoveEdit(1, 0))

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_a_operation, insert_b_operation, move_operation],
    read,
  )
  |> expect.to_equal(#([json.string("b"), json.string("a")], True))
}

/// Three replicas concurrently insert a distinct character at index 0, none
/// having observed the others yet.
pub fn text_concurrent_inserts_converge_across_order_test() -> Nil {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(state, channel.TextInsertEdit(0, value))
    operation
  }
  let operations = [
    insert_at("a", "a"),
    insert_at("b", "b"),
    insert_at("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}

pub fn text_delete_range_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(state_b, _, delete_operation)) =
    channel.apply_p2p_local(state_b, channel.TextDeleteRangeEdit(1, 3))

  // The delete edit itself commits immediately too: no pending entry.
  let assert channel.TextState(delete_kernel) = state_b
  delete_kernel.pending |> expect.to_equal([])
  text_kernel.value(delete_kernel) |> expect.to_equal("hlo")

  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitText, replica: "o") },
    [insert_operation, delete_operation],
    read,
  )
  |> expect.to_equal(#("hlo", True))
}

pub fn text_replace_range_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(_, _, replace_operation)) =
    channel.apply_p2p_local(
      state_b,
      channel.TextReplaceRangeEdit(0, 5, "world"),
    )

  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitText, replica: "o") },
    [insert_operation, replace_operation],
    read,
  )
  |> expect.to_equal(#("world", True))
}

/// Three replicas concurrently append a distinct character, none having
/// observed the others yet — `append` inserts at the end anchor, so this
/// is the same identity-based, order-independent guarantee as
/// `text_concurrent_inserts_converge_across_order_test`.
pub fn text_append_concurrent_converges_across_order_test() -> Nil {
  let append_operation = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(state, channel.TextAppendEdit(value))
    operation
  }
  let operations = [
    append_operation("a", "a"),
    append_operation("b", "b"),
    append_operation("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}
