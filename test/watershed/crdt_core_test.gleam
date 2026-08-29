import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import lattice_sets/g_set.{type GSet}
import startest/expect

import watershed/channel
import watershed/crdt_core
import watershed/crdt_sim
import watershed/crdt_wire
import watershed/g_set_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/p2p
import watershed/pn_counter_kernel
import watershed/sequence_kernel
import watershed/sha256
import watershed/text_kernel
import watershed/two_p_set_kernel

const room = "trip-planning"

const compatibility = "watershed-crdt-1"

fn config(replica: String) -> crdt_core.Config {
  crdt_core.config(
    room: room,
    compatibility: compatibility,
    replica: replica,
    session: replica <> "-session",
    root: channel.InitGSet,
  )
}

fn document(replica: String) -> crdt_core.Document {
  let assert Ok(document) = crdt_core.new(config(replica))
  document
}

fn root() -> String {
  crdt_wire.root_address
}

fn mesh(names: List(String)) -> crdt_sim.Mesh {
  list.fold(names, crdt_sim.new(), fn(mesh, name) {
    crdt_sim.add(mesh, name, document(name))
  })
}

fn full_mesh(names: List(String)) -> crdt_sim.Mesh {
  list.combination_pairs(names)
  |> list.fold(mesh(names), fn(mesh, pair) {
    crdt_sim.connect(mesh, pair.0, pair.1)
  })
}

fn g_set_values(document: crdt_core.Document, address: String) -> List(String) {
  let assert Ok(channel.GSetState(kernel)) =
    crdt_core.channel_state(document, address)
  g_set_kernel.values(kernel)
}

fn or_set_values(
  document: crdt_core.Document,
  address: String,
) -> List(String) {
  let assert Ok(channel.OrSetState(kernel)) =
    crdt_core.channel_state(document, address)
  or_set_kernel.values(kernel)
}

fn counter_value(document: crdt_core.Document, address: String) -> Int {
  let assert Ok(channel.PnCounterState(kernel)) =
    crdt_core.channel_state(document, address)
  pn_counter_kernel.value(kernel)
}

/// Every peer's observable channel values, address-tagged. Kept alongside
/// the digest check in `converged`: the digest proves the replicas agree on
/// causal state, and this proves they agree on what a reader sees.
fn view(document: crdt_core.Document) -> List(#(String, String)) {
  crdt_core.descriptors(document)
  |> list.map(fn(descriptor) {
    let assert Ok(state) = crdt_core.channel_state(document, descriptor.address)
    #(descriptor.address, render(state))
  })
}

fn render(state: channel.ChannelState) -> String {
  case state {
    channel.PnCounterState(kernel) ->
      int.to_string(pn_counter_kernel.value(kernel))
    channel.OrSetState(kernel) -> string.join(or_set_kernel.values(kernel), ",")
    channel.GSetState(kernel) -> string.join(g_set_kernel.values(kernel), ",")
    channel.TwoPSetState(kernel) ->
      string.join(two_p_set_kernel.values(kernel), ",")
    channel.OrMapState(kernel) ->
      or_map_kernel.entries(kernel)
      |> list.map(fn(entry) {
        entry.0
        <> "="
        <> case entry.1 {
          or_map_kernel.Tally(value) -> int.to_string(value)
          or_map_kernel.Register(value) -> value
        }
      })
      |> string.join(",")
    channel.SequenceState(kernel) ->
      sequence_kernel.values(kernel)
      |> list.map(json.to_string)
      |> string.join(",")
    channel.TextState(kernel) -> text_kernel.value(kernel)
    channel.MapState(_)
    | channel.CounterState(_)
    | channel.RegisterCollectionState(_)
    | channel.ClaimsState(_)
    | channel.TaskManagerState(_)
    | channel.PactMapState(_)
    | channel.JsonOtState(_)
    | channel.DirectoryState(_)
    | channel.OrderedCollectionState(_)
    | channel.RichTextState(_) ->
      channel.type_to_string(channel.channel_type(state))
  }
}

/// Peers converge when they agree on both halves of the property: the
/// values a reader observes, and the digest-canonical projection that
/// anti-entropy compares. The digest is the stronger of the two — it also
/// covers tombstones and causal metadata a value view cannot see — so a
/// mesh that passes this has genuinely joined, not merely agreed on
/// output.
fn converged(mesh: crdt_sim.Mesh) -> Nil {
  crdt_sim.names(mesh)
  |> list.map(fn(name) { view(crdt_sim.document(mesh, name)) })
  |> list.unique
  |> list.length
  |> expect.to_equal(1)
  digests(mesh) |> list.length |> expect.to_equal(1)
  crdt_sim.names(mesh)
  |> list.map(fn(name) {
    crdt_core.digest_canonical_json(crdt_sim.document(mesh, name))
  })
  |> list.unique
  |> list.length
  |> expect.to_equal(1)
}

fn digests(mesh: crdt_sim.Mesh) -> List(String) {
  crdt_sim.names(mesh)
  |> list.map(fn(name) { crdt_core.digest(crdt_sim.document(mesh, name)) })
  |> list.unique
}

fn addresses(document: crdt_core.Document) -> List(String) {
  crdt_core.descriptors(document)
  |> list.map(fn(descriptor) { descriptor.address })
}

// --- identity and root ----------------------------------------------------

pub fn the_first_peer_starts_at_the_configured_empty_root_test() -> Nil {
  let document = document("peer-a")
  crdt_core.room(document) |> expect.to_equal(room)
  crdt_core.replica(document) |> expect.to_equal("peer-a")
  crdt_core.root_type(document) |> expect.to_equal(channel.GSetChannel)
  crdt_core.channel_count(document) |> expect.to_equal(1)
  addresses(document) |> expect.to_equal([root()])
  g_set_values(document, root()) |> expect.to_equal([])
  let assert Ok(descriptor) = crdt_core.descriptor(document, root())
  descriptor.created_by |> expect.to_equal("")
  Nil
}

pub fn an_ineligible_root_is_refused_test() -> Nil {
  let assert Error(p2p.UnsupportedChannel(channel.MapChannel)) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "peer-a",
      session: "s",
      root: channel.InitMap,
    ))
  Nil
}

pub fn an_unusable_identity_is_refused_test() -> Nil {
  [
    #("", "peer-a", "s"),
    #(room, "", "s"),
    #(room, "a:b", "s"),
    #(room, "a", ""),
  ]
  |> list.each(fn(triple) {
    let #(room, replica, session) = triple
    let assert Error(p2p.InvalidEnvelope(_, _)) =
      crdt_core.new(crdt_core.config(
        room: room,
        compatibility: compatibility,
        replica: replica,
        session: session,
        root: channel.InitGSet,
      ))
    Nil
  })
}

pub fn an_ineligible_channel_cannot_be_created_test() -> Nil {
  let assert Error(p2p.UnsupportedChannel(channel.MapChannel)) =
    crdt_core.create_channel(document("peer-a"), channel.InitMap)
  Nil
}

pub fn addresses_are_replica_scoped_and_positive_test() -> Nil {
  let #(mesh, first) =
    crdt_sim.create(mesh(["peer-a"]), "peer-a", channel.InitOrSet)
  let #(_, second) = crdt_sim.create(mesh, "peer-a", channel.InitGSet)
  first |> expect.to_equal("peer-a:1")
  second |> expect.to_equal("peer-a:2")
  Nil
}

// --- bootstrap ------------------------------------------------------------

pub fn three_peers_bootstrap_through_state_request_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.settle

  // A late joiner learns everything from one state exchange.
  let mesh =
    crdt_sim.add(mesh, "peer-d", document("peer-d"))
    |> crdt_sim.connect("peer-d", "peer-b")
  let mesh =
    crdt_sim.send(mesh, "peer-d", "peer-b", [crdt_core.state_request_message()])
    |> crdt_sim.settle

  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    let document = crdt_sim.document(mesh, name)
    addresses(document) |> expect.to_equal([address, root()])
    or_set_values(document, address) |> expect.to_equal(["kiwi"])
  })
  converged(mesh)
  Nil
}

pub fn concurrent_channel_creation_survives_in_every_replica_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, a_address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let #(mesh, b_address) = crdt_sim.create(mesh, "peer-b", channel.InitGSet)
  let #(mesh, c_address) =
    crdt_sim.create(mesh, "peer-c", channel.InitPnCounter)
  let mesh = crdt_sim.settle(mesh)

  let expected =
    list.sort([a_address, b_address, c_address, root()], string.compare)
  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    addresses(crdt_sim.document(mesh, name)) |> expect.to_equal(expected)
  })
  converged(mesh)
  Nil
}

// --- delivery order -------------------------------------------------------

pub fn a_delta_before_its_channel_buffers_then_applies_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("kiwi"))

  // Hold the announcement back and deliver only the delta.
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let announcements = crdt_sim.of_kind(packets, "channel")
  let deltas = crdt_sim.of_kind(packets, "delta")
  let mesh = crdt_sim.enqueue(mesh, deltas) |> crdt_sim.settle

  let held = crdt_sim.document(mesh, "peer-b")
  crdt_core.buffered_count(held) |> expect.to_equal(1)
  crdt_core.channel_count(held) |> expect.to_equal(1)

  let mesh = crdt_sim.enqueue(mesh, announcements) |> crdt_sim.settle
  let flushed = crdt_sim.document(mesh, "peer-b")
  crdt_core.buffered_count(flushed) |> expect.to_equal(0)
  or_set_values(flushed, address) |> expect.to_equal(["kiwi"])
  converged(mesh)
  Nil
}

pub fn buffered_deltas_apply_in_arrival_order_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitText)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.TextAppendEdit("wa"))
    |> crdt_sim.edit("peer-a", address, channel.TextAppendEdit("ter"))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)

  let mesh =
    crdt_sim.enqueue(mesh, crdt_sim.of_kind(packets, "delta"))
    |> crdt_sim.settle
  crdt_core.buffered_count(crdt_sim.document(mesh, "peer-b"))
  |> expect.to_equal(2)

  let mesh =
    crdt_sim.enqueue(mesh, crdt_sim.of_kind(packets, "channel"))
    |> crdt_sim.settle
  let assert Ok(channel.TextState(kernel)) =
    crdt_core.channel_state(crdt_sim.document(mesh, "peer-b"), address)
  text_kernel.value(kernel) |> expect.to_equal("water")
  crdt_core.buffered_count(crdt_sim.document(mesh, "peer-b"))
  |> expect.to_equal(0)
  converged(mesh)
  Nil
}

pub fn a_relayed_delta_keeps_its_authors_message_id_test() -> Nil {
  let mesh = mesh(["peer-a", "peer-b", "peer-c"])
  let mesh = crdt_sim.connect(mesh, "peer-a", "peer-b")
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.settle(mesh)
    |> crdt_sim.edit("peer-a", address, channel.OrSetAddEdit("fig"))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let assert [packet] = crdt_sim.of_kind(packets, "delta")
  let assert Ok(envelope) =
    crdt_wire.decode_envelope(packet.raw, crdt_wire.default_limits())

  // peer-b forwards peer-a's channel and delta to peer-c verbatim. The
  // message ID still names peer-a, and peer-c accepts it.
  let mesh =
    crdt_sim.connect(mesh, "peer-b", "peer-c")
    |> crdt_sim.enqueue(packets)
    |> crdt_sim.settle
  let mesh =
    crdt_sim.send(mesh, "peer-b", "peer-c", [
      crdt_core.state_message(crdt_sim.document(mesh, "peer-b")),
      envelope.message,
    ])
    |> crdt_sim.settle

  or_set_values(crdt_sim.document(mesh, "peer-c"), address)
  |> expect.to_equal(["fig"])
  let assert crdt_wire.Delta(id, _, _, _) = envelope.message
  id.replica |> expect.to_equal("peer-a")
  crdt_core.seen(crdt_sim.document(mesh, "peer-c"), id) |> expect.to_be_true
  Nil
}

pub fn reordered_and_duplicated_deltas_converge_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.settle(mesh)

  let mesh =
    ["kiwi", "plum", "fig"]
    |> list.fold(mesh, fn(mesh, fruit) {
      crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit(fruit))
    })
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let reordered = list.reverse(packets)
  let mesh =
    crdt_sim.enqueue(mesh, list.append(reordered, reordered))
    |> crdt_sim.settle

  or_set_values(crdt_sim.document(mesh, "peer-b"), address)
  |> expect.to_equal(["fig", "kiwi", "plum"])
  converged(mesh)
  Nil
}

pub fn duplicate_and_interleaved_state_and_deltas_converge_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitPnCounter)
  let mesh = crdt_sim.settle(mesh)

  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.PnCounterEdit(5))
    |> crdt_sim.edit("peer-b", address, channel.PnCounterEdit(7))
  let #(mesh, deltas) = crdt_sim.take_queue(mesh)

  // A full state transfer from each side, interleaved with the deltas and
  // then replayed, must not double-count or roll anything back.
  let mesh =
    crdt_sim.broadcast(mesh, "peer-a", [
      crdt_core.state_message(crdt_sim.document(mesh, "peer-a")),
    ])
  let #(mesh, states) = crdt_sim.take_queue(mesh)
  let traffic = list.append(list.append(states, deltas), states)
  let mesh =
    crdt_sim.enqueue(mesh, list.append(traffic, traffic)) |> crdt_sim.settle
  let mesh = crdt_sim.gossip_state(mesh)

  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    counter_value(crdt_sim.document(mesh, name), address)
    |> expect.to_equal(12)
  })
  converged(mesh)
  Nil
}

pub fn a_duplicate_message_id_is_suppressed_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitPnCounter)
  let mesh =
    crdt_sim.settle(mesh)
    |> crdt_sim.edit("peer-a", address, channel.PnCounterEdit(4))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let mesh =
    crdt_sim.enqueue(mesh, list.flatten([packets, packets, packets]))
    |> crdt_sim.settle

  let peer_b = crdt_sim.document(mesh, "peer-b")
  counter_value(peer_b, address) |> expect.to_equal(4)
  let assert [packet, ..] = packets
  let assert Ok(envelope) =
    crdt_wire.decode_envelope(packet.raw, crdt_wire.default_limits())
  let assert crdt_wire.Delta(id, _, _, _) = envelope.message
  crdt_core.seen(peer_b, id) |> expect.to_be_true
  Nil
}

// --- partition and repair -------------------------------------------------

pub fn a_partitioned_mesh_converges_after_one_edge_returns_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.settle(mesh)

  // Split peer-c off entirely, then edit on both sides of the split.
  let mesh =
    crdt_sim.disconnect(mesh, "peer-a", "peer-c")
    |> crdt_sim.disconnect("peer-b", "peer-c")
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-c", address, channel.OrSetAddEdit("fig"))
    |> crdt_sim.settle

  or_set_values(crdt_sim.document(mesh, "peer-b"), address)
  |> expect.to_equal(["kiwi"])
  or_set_values(crdt_sim.document(mesh, "peer-c"), address)
  |> expect.to_equal(["fig"])

  // One edge returns; the merged state fans out to the peer still behind.
  let mesh =
    crdt_sim.connect(mesh, "peer-b", "peer-c")
    |> crdt_sim.gossip_state
    |> crdt_sim.gossip_state

  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    or_set_values(crdt_sim.document(mesh, name), address)
    |> expect.to_equal(["fig", "kiwi"])
  })
  converged(mesh)
  Nil
}

pub fn a_state_merge_keeps_local_channels_and_edits_test() -> Nil {
  let mesh = mesh(["peer-a", "peer-b"])
  let #(mesh, a_address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let #(mesh, b_address) = crdt_sim.create(mesh, "peer-b", channel.InitOrSet)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", a_address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-b", b_address, channel.OrSetAddEdit("fig"))
  let #(mesh, _dropped) = crdt_sim.take_queue(mesh)

  let mesh =
    crdt_sim.connect(mesh, "peer-a", "peer-b")
    |> crdt_sim.send("peer-a", "peer-b", [
      crdt_core.state_message(crdt_sim.document(mesh, "peer-a")),
    ])
    |> crdt_sim.settle

  let peer_b = crdt_sim.document(mesh, "peer-b")
  addresses(peer_b)
  |> expect.to_equal(list.sort([a_address, b_address, root()], string.compare))
  or_set_values(peer_b, a_address) |> expect.to_equal(["kiwi"])
  or_set_values(peer_b, b_address) |> expect.to_equal(["fig"])
  Nil
}

pub fn a_digest_mismatch_asks_for_state_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.settle(mesh)
    |> crdt_sim.edit("peer-a", address, channel.OrSetAddEdit("kiwi"))
  let #(mesh, _dropped) = crdt_sim.take_queue(mesh)

  // The behind peer answers a digest it cannot match with a state request,
  // asserted directly before the mesh settles the exchange.
  let assert Ok(#(_, outcome)) =
    crdt_core.receive(
      crdt_sim.document(mesh, "peer-b"),
      crdt_core.envelope(
        crdt_sim.document(mesh, "peer-a"),
        crdt_core.digest_message(crdt_sim.document(mesh, "peer-a")),
      ),
    )
  outcome.reply |> expect.to_equal([crdt_wire.StateRequest])

  let mesh =
    crdt_sim.broadcast(mesh, "peer-a", [
      crdt_core.digest_message(crdt_sim.document(mesh, "peer-a")),
    ])
    |> crdt_sim.settle

  or_set_values(crdt_sim.document(mesh, "peer-b"), address)
  |> expect.to_equal(["kiwi"])
  converged(mesh)
  Nil
}

/// The point of a cross-replica digest: once two peers have converged, an
/// exchange costs one message and asks for nothing. A replica-local digest
/// would have them trading full state on every round forever.
pub fn a_digest_exchange_between_converged_peers_asks_for_nothing_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.settle(mesh)
    |> crdt_sim.edit("peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-b", address, channel.OrSetRemoveEdit("kiwi"))
    |> crdt_sim.settle
  converged(mesh)

  let peer_a = crdt_sim.document(mesh, "peer-a")
  let peer_b = crdt_sim.document(mesh, "peer-b")
  let assert Ok(#(after, outcome)) =
    crdt_core.receive(
      peer_b,
      crdt_core.envelope(peer_a, crdt_core.digest_message(peer_a)),
    )
  outcome.reply |> expect.to_equal([])
  outcome.events |> expect.to_equal([])
  crdt_core.digest(after) |> expect.to_equal(crdt_core.digest(peer_b))

  // And the whole mesh exchanging digests queues no traffic at all.
  let mesh =
    crdt_sim.names(mesh)
    |> list.fold(mesh, fn(mesh, name) {
      crdt_sim.broadcast(mesh, name, [
        crdt_core.digest_message(crdt_sim.document(mesh, name)),
      ])
    })
    |> crdt_sim.settle
  crdt_sim.queue(mesh) |> expect.to_equal([])
  converged(mesh)
  Nil
}

pub fn a_matching_digest_asks_for_nothing_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.settle
  let peer_b = crdt_sim.document(mesh, "peer-b")
  let echoed = crdt_wire.Digest(crdt_core.digest(peer_b))
  let assert Ok(#(after, outcome)) =
    crdt_core.receive(
      peer_b,
      crdt_core.envelope(crdt_sim.document(mesh, "peer-a"), echoed),
    )
  outcome.reply |> expect.to_equal([])
  outcome.events |> expect.to_equal([])
  crdt_core.digest(after) |> expect.to_equal(crdt_core.digest(peer_b))
  Nil
}

/// Every eligible kernel, edited from three sides in a different order per
/// peer, ends on one digest. This is the property the whole projection
/// exists for, checked kind by kind rather than only on the mesh helper.
pub fn converged_peers_share_a_digest_for_every_eligible_kind_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, counter) = crdt_sim.create(mesh, "peer-a", channel.InitPnCounter)
  let #(mesh, tally) =
    crdt_sim.create(mesh, "peer-a", channel.InitOrMap(or_map_kernel.TallyMode))
  let #(mesh, registers) =
    crdt_sim.create(
      mesh,
      "peer-b",
      channel.InitOrMap(or_map_kernel.RegisterMode),
    )
  let #(mesh, set) = crdt_sim.create(mesh, "peer-b", channel.InitOrSet)
  let #(mesh, grow) = crdt_sim.create(mesh, "peer-c", channel.InitGSet)
  let #(mesh, two_p) = crdt_sim.create(mesh, "peer-c", channel.InitTwoPSet)
  let #(mesh, list_of) = crdt_sim.create(mesh, "peer-a", channel.InitSequence)
  let #(mesh, prose) = crdt_sim.create(mesh, "peer-b", channel.InitText)
  let mesh = crdt_sim.settle(mesh)

  let mesh =
    crdt_sim.edit(mesh, "peer-a", counter, channel.PnCounterEdit(4))
    |> crdt_sim.edit("peer-b", counter, channel.PnCounterEdit(-6))
    |> crdt_sim.edit("peer-a", tally, channel.OrMapIncrementEdit("k", 2))
    |> crdt_sim.edit("peer-c", tally, channel.OrMapIncrementEdit("k", 3))
    |> crdt_sim.edit(
      "peer-b",
      registers,
      channel.OrMapSetRegisterEdit("title", "trip", 10),
    )
    |> crdt_sim.edit("peer-b", set, channel.OrSetAddEdit("fig"))
    |> crdt_sim.edit("peer-c", set, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-a", set, channel.OrSetRemoveEdit("fig"))
    |> crdt_sim.edit("peer-a", grow, channel.GSetAddEdit("one"))
    |> crdt_sim.edit("peer-c", two_p, channel.TwoPSetAddEdit("plum"))
    |> crdt_sim.edit("peer-b", two_p, channel.TwoPSetRemoveEdit("plum"))
    |> crdt_sim.edit(
      "peer-a",
      list_of,
      channel.SequenceInsertEdit(0, json.int(1)),
    )
    |> crdt_sim.edit("peer-c", prose, channel.TextAppendEdit("hi"))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let mesh =
    crdt_sim.enqueue(mesh, list.append(list.reverse(packets), packets))
    |> crdt_sim.settle
    |> crdt_sim.gossip_state
    |> crdt_sim.gossip_state

  digests(mesh) |> list.length |> expect.to_equal(1)
  converged(mesh)
  Nil
}

/// The two snapshots do different jobs. The exported one keeps the
/// authoring cursors an import needs, so two converged replicas export
/// different bytes; the digest projection removes exactly those, so the
/// same two replicas agree.
pub fn the_export_keeps_what_the_digest_projects_out_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh =
    crdt_sim.settle(mesh)
    |> crdt_sim.edit("peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-b", address, channel.OrSetAddEdit("fig"))
    |> crdt_sim.settle
  let peer_a = crdt_sim.document(mesh, "peer-a")
  let peer_b = crdt_sim.document(mesh, "peer-b")

  crdt_core.canonical_json(peer_a)
  |> expect.to_not_equal(crdt_core.canonical_json(peer_b))
  string.contains(crdt_core.canonical_json(peer_a), "replica_id")
  |> expect.to_be_true
  crdt_core.digest_canonical_json(peer_a)
  |> expect.to_equal(crdt_core.digest_canonical_json(peer_b))
  crdt_core.digest(peer_a) |> expect.to_equal(crdt_core.digest(peer_b))

  // The projection is not blanket-blind: it still separates two replicas
  // that disagree on a tombstone the value view cannot see.
  let assert Ok(#(peer_a, _)) =
    crdt_core.edit(peer_a, address, channel.OrSetRemoveEdit("fig"))
  crdt_core.digest(peer_a) |> expect.to_not_equal(crdt_core.digest(peer_b))
  Nil
}

// --- canonical snapshots --------------------------------------------------

pub fn registry_creation_order_does_not_change_the_digest_test() -> Nil {
  let forward =
    list.fold(
      [channel.InitOrSet, channel.InitGSet, channel.InitPnCounter],
      document("peer-a"),
      fn(document, init) {
        let assert Ok(#(document, _)) = crdt_core.create_channel(document, init)
        document
      },
    )
  // The same three channels, registered by the same replica in the reverse
  // order, land on different addresses, so compare a replica that learned
  // both orders instead: canonical order is by address, not arrival.
  let entries = state_entries(forward)
  let shuffled = list.reverse(entries)
  let left = merge_into(document("peer-b"), forward, entries)
  let right = merge_into(document("peer-b"), forward, shuffled)
  crdt_core.canonical_json(left)
  |> expect.to_equal(crdt_core.canonical_json(right))
  crdt_core.digest(left) |> expect.to_equal(crdt_core.digest(right))
  Nil
}

fn state_entries(document: crdt_core.Document) -> List(crdt_wire.ChannelEntry) {
  let assert crdt_wire.State(entries) = crdt_core.state_message(document)
  entries
}

fn merge_into(
  target: crdt_core.Document,
  source: crdt_core.Document,
  entries: List(crdt_wire.ChannelEntry),
) -> crdt_core.Document {
  let assert Ok(#(target, _)) =
    crdt_core.receive(
      target,
      crdt_core.envelope(source, crdt_wire.State(entries)),
    )
  target
}

pub fn different_delivery_orders_reach_the_same_canonical_json_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.settle(mesh)
  let mesh =
    crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("kiwi"))
    |> crdt_sim.edit("peer-b", address, channel.OrSetAddEdit("fig"))
    |> crdt_sim.edit("peer-c", address, channel.OrSetAddEdit("plum"))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let settled = crdt_sim.enqueue(mesh, packets) |> crdt_sim.settle
  let reversed =
    crdt_sim.enqueue(mesh, list.reverse(packets)) |> crdt_sim.settle

  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    crdt_core.canonical_json(crdt_sim.document(settled, name))
    |> expect.to_equal(
      crdt_core.canonical_json(crdt_sim.document(reversed, name)),
    )
  })
  Nil
}

pub fn a_snapshot_round_trips_through_export_and_import_test() -> Nil {
  let mesh = full_mesh(["peer-a"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("fig"))
  let exported = crdt_core.canonical_json(crdt_sim.document(mesh, "peer-a"))

  let assert Ok(#(loaded, outcome)) =
    crdt_core.import_snapshot(document("peer-z"), exported)
  or_set_values(loaded, address) |> expect.to_equal(["fig"])
  list.length(outcome.created) |> expect.to_equal(1)
  view(loaded) |> expect.to_equal(view(crdt_sim.document(mesh, "peer-a")))
  Nil
}

pub fn importing_the_same_snapshot_twice_changes_nothing_test() -> Nil {
  let mesh = full_mesh(["peer-a"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("fig"))
  let exported = crdt_core.canonical_json(crdt_sim.document(mesh, "peer-a"))
  let assert Ok(#(once, _)) =
    crdt_core.import_snapshot(document("peer-z"), exported)
  let assert Ok(#(twice, _)) = crdt_core.import_snapshot(once, exported)
  crdt_core.digest(twice) |> expect.to_equal(crdt_core.digest(once))
  Nil
}

pub fn a_digest_is_lowercase_sha256_hex_test() -> Nil {
  let digest = sha256.hex("watershed")
  string.length(digest) |> expect.to_equal(64)
  digest |> expect.to_equal(string.lowercase(digest))
  digest
  |> expect.to_equal(
    "1fa5ec1566b77ed14cbc9ab8f91b070b4284fa6220ece15d68072bcc9d2155d3",
  )
  sha256.hex("watershed.")
  |> expect.to_not_equal(digest)
  Nil
}

/// A document built out of everything the two targets used to disagree
/// about, pinned to one hash that both of them must produce.
///
/// Erlang and JavaScript each encode and order JSON their own way:
/// `string.compare` sorts an astral character below `U+FFFD` on one and
/// above it on the other, `json.float(2.0)` writes `2.0` on one and `2` on
/// the other, `1.0e-5` on one and `0.00001` on the other, an integer past
/// 2^53 is exact on one and a double on the other, a control character
/// escapes as `\u000B` or `\u000b`, and a `Dict` iterates in term order on
/// one and hash order on the other. Every one of those is in here —
/// astral and CJK and fullwidth keys, an integral float inside a sequence,
/// a float from the small band, two numbers past 2^53, a vertical tab, and
/// a sequence `forwardings` map big enough that the two targets genuinely
/// list it in different orders. Both targets run this file, so a hash that
/// is right on one and wrong on the other fails the suite rather than
/// stranding a browser peer and a BEAM peer in permanent repair.
///
/// This is a canary, not a contract: it is expected to fail if the digest
/// projection or a lattice encoding changes on purpose. Re-pin it then —
/// after checking the new hash is the same on `--target erlang` and
/// `--target javascript`.
/// One golden digest per channel type: a single deterministic edit on a
/// single-channel document, pinned to the exact projection hash. The
/// behavioral digest tests only compare replicas to each other, so a
/// lattice_* internal field rename that moved every digest in lockstep
/// would pass them; these byte-level pins catch it per channel type.
///
/// A canary like the fixture document below: re-pin deliberately, after
/// checking the new hashes match on `--target erlang` and
/// `--target javascript`.
pub fn each_channel_type_pins_its_digest_projection_test() -> Nil {
  [
    #(
      channel.InitPnCounter,
      channel.PnCounterEdit(3),
      "188bd947061bfedd6799f945261dbd2d7ede4b2cd6e7fd417a82c8572562d163",
    ),
    #(
      channel.InitOrMap(or_map_kernel.TallyMode),
      channel.OrMapIncrementEdit("votes", 2),
      "ed14587690180b1ab5bd13772f4c6aba53a2f6ccd78af483cf7ec935539f08ee",
    ),
    #(
      channel.InitOrMap(or_map_kernel.RegisterMode),
      channel.OrMapSetRegisterEdit("city", "Oslo", 9),
      "8fe2a610d6f37fea15d031a73ffb04283b8c12b1c5faa35138c45b5ef63136f6",
    ),
    #(
      channel.InitOrSet,
      channel.OrSetAddEdit("fig"),
      "f215d884d02bb01b6fc2249b9d412de54dcb0557344e7a5208fa51cf43cbf597",
    ),
    #(
      channel.InitGSet,
      channel.GSetAddEdit("fig"),
      "04d614ecab716c5002dfe1f9c1b7e498798b1c4285272b6ab0a015952129f760",
    ),
    #(
      channel.InitTwoPSet,
      channel.TwoPSetRemoveEdit("fig"),
      "f6d68f2b55abc4295837fa2106df09d67a082e59aaf4fc072c758a30c0617096",
    ),
    #(
      channel.InitSequence,
      channel.SequenceInsertEdit(0, json.string("fig")),
      "6cb5a3c8e7fda40061b830f39c67364c58b00ade4bcc4e5133ebeeae7eecaac1",
    ),
    #(
      channel.InitText,
      channel.TextAppendEdit("fig"),
      "4256362bbb48fd0daefbb607c294d5e7a3f81a33cacceca900c2127bc7c1a461",
    ),
  ]
  |> list.each(fn(fixture) {
    let #(init, edit, pinned) = fixture
    let assert Ok(document) =
      crdt_core.new(crdt_core.config(
        room: room,
        compatibility: compatibility,
        replica: "peer-a",
        session: "peer-a-session",
        root: init,
      ))
    let assert Ok(#(document, _)) = crdt_core.edit(document, root(), edit)
    crdt_core.digest(document) |> expect.to_equal(pinned)
  })
  Nil
}

pub fn a_pinned_document_digest_is_identical_on_every_target_test() -> Nil {
  let document = fixture_document()

  crdt_core.digest(document)
  |> expect.to_equal(
    "29a2003f235159dc130cd16720289e99b2c6bed079755b87279a1533846b93df",
  )

  // What the hash is made of, spelled out: one canonical form per value,
  // whatever the target's own JSON encoder would have written.
  let canonical = crdt_core.digest_canonical_json(document)
  string.contains(canonical, "\\u000b") |> expect.to_be_true
  string.contains(canonical, "\\u000B") |> expect.to_be_false
  string.contains(canonical, "\"value\":2}") |> expect.to_be_true
  string.contains(canonical, "\"value\":2.0") |> expect.to_be_false
  string.contains(canonical, "\"value\":0.00001}") |> expect.to_be_true
  string.contains(canonical, "1.0e-5") |> expect.to_be_false
  string.contains(canonical, "\"value\":12345678901234567000}")
  |> expect.to_be_true
  string.contains(canonical, "12345678901234567168") |> expect.to_be_false
  string.contains(canonical, "\"value\":9007199254740992000}")
  |> expect.to_be_true
  string.contains(canonical, "9007199254740992123") |> expect.to_be_false
  Nil
}

/// The fixture document, built by one replica in a fixed order and then
/// merged into a second one, so the pinned hash covers a state that
/// arrived over the wire rather than only one authored locally.
///
/// `forwardings` is injected rather than authored: it is filled by the
/// sequence CRDT's compaction, which nothing in watershed calls yet, so
/// the only way to pin its ordering today is to hand a replica a snapshot
/// that already carries one. The replacement is asserted, so a change to
/// the export shape breaks this loudly instead of quietly testing nothing.
fn fixture_document() -> crdt_core.Document {
  let assert Ok(author) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "peer-a",
      session: "peer-a-session",
      root: channel.InitGSet,
    ))
  let assert Ok(#(author, _)) =
    crdt_core.create_channel(author, channel.InitOrSet)
  let assert Ok(#(author, _)) =
    crdt_core.create_channel(author, channel.InitSequence)
  let assert Ok(#(author, _)) =
    crdt_core.create_channel(
      author,
      channel.InitOrMap(or_map_kernel.RegisterMode),
    )
  let assert Ok(#(author, _)) =
    crdt_core.create_channel(author, channel.InitText)
  let set = "peer-a:1"
  let sequence = "peer-a:2"
  let registers = "peer-a:3"
  let prose = "peer-a:4"

  let author =
    [
      #(root(), channel.GSetAddEdit("𝄞")),
      #(root(), channel.GSetAddEdit("全")),
      #(root(), channel.GSetAddEdit("Ａ")),
      #(root(), channel.GSetAddEdit("\u{FFFD}")),
      #(set, channel.OrSetAddEdit("𝄞")),
      #(set, channel.OrSetAddEdit("全")),
      #(set, channel.OrSetAddEdit("Ａ")),
      #(set, channel.OrSetAddEdit("\u{FFFD}\u{000B}")),
      #(set, channel.OrSetRemoveEdit("全")),
      #(sequence, channel.SequenceInsertEdit(0, json.int(1))),
      #(sequence, channel.SequenceInsertEdit(1, json.float(2.0))),
      #(sequence, channel.SequenceInsertEdit(2, json.string("𝄞全"))),
      // A float in the band Erlang writes as `1.0e-5` and JavaScript as
      // `0.00001`, and two numbers past 2^53, where JavaScript holds a
      // double and Erlang an exact integer. Both used to hash apart.
      #(sequence, channel.SequenceInsertEdit(3, json.float(1.0e-5))),
      #(
        sequence,
        channel.SequenceInsertEdit(4, json.float(1.2345678901234567e19)),
      ),
      #(
        sequence,
        channel.SequenceInsertEdit(
          5,
          json.int({ 9_007_199_254_740_991 + 1 } * 1000 + 123),
        ),
      ),
      #(sequence, channel.SequenceMoveEdit(0, 2)),
      #(registers, channel.OrMapSetRegisterEdit("𝄞", "Ａ\u{000B}", 10)),
      #(registers, channel.OrMapSetRegisterEdit("全", "全", 11)),
      #(prose, channel.TextAppendEdit("𝄞全Ａ")),
    ]
    |> list.fold(author, fn(document, edit) {
      let assert Ok(#(document, _)) = crdt_core.edit(document, edit.0, edit.1)
      document
    })

  let exported = crdt_core.canonical_json(author)
  let injected =
    string.replace(exported, empty_forwardings, fixture_forwardings)
  injected |> expect.to_not_equal(exported)

  let assert Ok(#(merged, _)) =
    crdt_core.import_snapshot(document("peer-b"), injected)

  // Two more authors, whose replica ids — and so whose channel addresses —
  // order one way by UTF-8 bytes and the other way by UTF-16 code units.
  // That pins the registry's own ordering, not just the ordering inside a
  // channel state.
  ["peer-\u{FFFD}", "peer-𝄞"]
  |> list.fold(merged, fn(document, replica) {
    let assert Ok(other) =
      crdt_core.new(crdt_core.config(
        room: room,
        compatibility: compatibility,
        replica: replica,
        session: replica <> "-session",
        root: channel.InitGSet,
      ))
    let assert Ok(#(other, _)) =
      crdt_core.create_channel(other, channel.InitTwoPSet)
    let assert Ok(#(other, _)) =
      crdt_core.edit(other, replica <> ":1", channel.TwoPSetAddEdit("𝄞"))
    let assert Ok(#(other, _)) =
      crdt_core.edit(other, replica <> ":1", channel.TwoPSetAddEdit("\u{FFFD}"))
    let assert Ok(#(other, _)) =
      crdt_core.edit(other, replica <> ":1", channel.TwoPSetRemoveEdit("𝄞"))
    let assert Ok(#(document, _)) =
      crdt_core.import_snapshot(document, crdt_core.canonical_json(other))
    document
  })
}

const empty_forwardings = "\"forwardings\":[]"

/// Six entries, chosen because the Erlang and JavaScript `Dict`
/// implementations really do iterate them in different orders — without
/// the projection's ordering the two targets hash different bytes.
const fixture_forwardings = "\"forwardings\":[{\"id\":{\"replica_id\":\"peer-alpha\",\"counter\":3},\"left\":null,\"right\":null},{\"id\":{\"replica_id\":\"peer-beta\",\"counter\":11},\"left\":null,\"right\":null},{\"id\":{\"replica_id\":\"peer-gamma\",\"counter\":2},\"left\":null,\"right\":null},{\"id\":{\"replica_id\":\"zeta\",\"counter\":1},\"left\":null,\"right\":null},{\"id\":{\"replica_id\":\"delta\",\"counter\":7},\"left\":null,\"right\":null},{\"id\":{\"replica_id\":\"omega\",\"counter\":5},\"left\":null,\"right\":null}]"

/// An oversize snapshot is refused on its byte length, before the parser
/// ever sees it, and leaves the document untouched.
pub fn the_snapshot_limit_rejects_an_oversize_import_test() -> Nil {
  let mesh = full_mesh(["peer-a"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("fig"))
  let exported = crdt_core.canonical_json(crdt_sim.document(mesh, "peer-a"))

  let limits = crdt_wire.Limits(..crdt_wire.default_limits(), snapshot_bytes: 8)
  let local = limited("peer-z", limits)
  let before = crdt_core.digest(local)
  let assert Error(p2p.SnapshotTooLarge(bytes, 8)) =
    crdt_core.import_snapshot(local, exported)
  { bytes > 8 } |> expect.to_be_true
  crdt_core.digest(local) |> expect.to_equal(before)
  crdt_core.channel_count(local) |> expect.to_equal(1)
  let assert Error(_) = crdt_core.channel_state(local, address)

  // Malformed input over the limit is refused on size, not on shape: the
  // guard runs before the parse.
  let assert Error(p2p.SnapshotTooLarge(_, 8)) =
    crdt_core.import_snapshot(local, "{\"v\":1,\"room\":\"not json enough")
  Nil
}

/// A replica that bootstrapped from a peer whose wall clock ran ahead must
/// still win its own next write. A *delta* carries the timestamp it was
/// stamped with, so the delta path already learns it; a snapshot does not,
/// so this goes through a state transfer, where the clock has to be
/// rebuilt from the merged registers themselves. Without that, peer-b's
/// write is stamped at 10, loses to the merged 5,000,000, and vanishes.
pub fn a_bootstrapped_replica_wins_its_first_register_write_test() -> Nil {
  let assert Ok(#(peer_a, created)) =
    crdt_core.create_channel(
      document("peer-a"),
      channel.InitOrMap(or_map_kernel.RegisterMode),
    )
  let assert [descriptor] = created.created
  let address = descriptor.address
  let assert Ok(#(peer_a, _)) =
    crdt_core.edit(
      peer_a,
      address,
      channel.OrMapSetRegisterEdit("title", "ahead", 5_000_000),
    )

  let assert Ok(#(peer_b, _)) =
    crdt_core.receive(
      document("peer-b"),
      crdt_core.envelope(peer_a, crdt_core.state_message(peer_a)),
    )
  register_value(peer_b, address, "title") |> expect.to_equal("ahead")

  let assert Ok(#(peer_b, edited)) =
    crdt_core.edit(
      peer_b,
      address,
      channel.OrMapSetRegisterEdit("title", "mine", 10),
    )
  register_value(peer_b, address, "title") |> expect.to_equal("mine")

  // And it is a real write, not a local illusion: it wins at the replica
  // that stamped 5,000,000 too.
  let assert [delta] = edited.broadcast
  let assert Ok(#(peer_a, _)) =
    crdt_core.receive(peer_a, crdt_core.envelope(peer_b, delta))
  register_value(peer_a, address, "title") |> expect.to_equal("mine")
  crdt_core.digest(peer_a) |> expect.to_equal(crdt_core.digest(peer_b))
  Nil
}

fn register_value(
  document: crdt_core.Document,
  address: String,
  key: String,
) -> String {
  let assert Ok(channel.OrMapState(kernel)) =
    crdt_core.channel_state(document, address)
  let assert Ok(or_map_kernel.Register(value)) =
    list.key_find(or_map_kernel.entries(kernel), key)
  value
}

// --- rejections -----------------------------------------------------------

fn reject(
  document: crdt_core.Document,
  envelope: crdt_wire.Envelope,
) -> p2p.P2pError {
  let before = crdt_core.digest(document)
  let assert Error(error) = crdt_core.receive(document, envelope)
  crdt_core.digest(document) |> expect.to_equal(before)
  error
}

fn foreign(
  replica: String,
  room: String,
  compatibility: String,
) -> crdt_core.Document {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: replica,
      session: replica <> "-session",
      root: channel.InitGSet,
    ))
  document
}

pub fn another_room_is_rejected_before_merge_test() -> Nil {
  let peer = foreign("peer-b", "other-room", compatibility)
  reject(
    document("peer-a"),
    crdt_core.envelope(peer, crdt_core.state_message(peer)),
  )
  |> expect.to_equal(p2p.RoomMismatch)
  Nil
}

pub fn another_compatibility_tag_is_rejected_before_merge_test() -> Nil {
  let peer = foreign("peer-b", room, "watershed-crdt-9")
  reject(
    document("peer-a"),
    crdt_core.envelope(peer, crdt_core.hello_message(peer)),
  )
  |> expect.to_equal(p2p.CompatibilityMismatch(
    compatibility,
    "watershed-crdt-9",
  ))
  Nil
}

pub fn another_root_kind_is_rejected_before_merge_test() -> Nil {
  let assert Ok(peer) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "peer-b",
      session: "peer-b-session",
      root: channel.InitOrSet,
    ))
  reject(
    document("peer-a"),
    crdt_core.envelope(peer, crdt_core.hello_message(peer)),
  )
  |> expect.to_equal(p2p.RootMismatch(channel.GSetChannel, channel.OrSetChannel))

  // A state transfer carrying a foreign root is refused the same way.
  reject(
    document("peer-a"),
    crdt_core.envelope(peer, crdt_core.state_message(peer)),
  )
  |> expect.to_equal(p2p.RootMismatch(channel.GSetChannel, channel.OrSetChannel))
  Nil
}

pub fn another_protocol_version_is_rejected_before_merge_test() -> Nil {
  let peer = document("peer-b")
  let raw =
    string.replace(
      crdt_core.encode(peer, crdt_core.state_message(peer)),
      "\"v\":1",
      "\"v\":7",
    )
  let document = document("peer-a")
  let before = crdt_core.digest(document)
  let assert Error(p2p.ProtocolMismatch(1, 7)) =
    crdt_core.receive_encoded(document, raw)
  crdt_core.digest(document) |> expect.to_equal(before)
  Nil
}

pub fn a_replica_id_claimed_by_another_session_is_rejected_test() -> Nil {
  let assert Ok(impostor) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "peer-a",
      session: "another-session",
      root: channel.InitGSet,
    ))
  reject(
    document("peer-a"),
    crdt_core.envelope(impostor, crdt_core.state_message(impostor)),
  )
  |> expect.to_equal(p2p.ReplicaCollision("peer-a"))
  Nil
}

pub fn a_forged_descriptor_conflict_is_rejected_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-b", channel.InitGSet)
  let mesh = crdt_sim.settle(mesh)
  let peer_b = crdt_sim.document(mesh, "peer-b")

  // Same address, different kind: only a forged or corrupt message can
  // produce this, because the address names its creator.
  let assert Ok(#(_, outcome)) =
    crdt_core.create_channel(document("peer-b"), channel.InitOrSet)
  let assert [_] = outcome.created
  let assert crdt_wire.State([entry, ..]) =
    crdt_core.state_message(forged_or_set())
  let forged =
    crdt_wire.ChannelAnnounce(crdt_wire.ChannelEntry(
      crdt_wire.ChannelDescriptor(address, channel.OrSetChannel, "peer-b"),
      entry.snapshot,
    ))
  let assert p2p.InvalidEnvelope(_, detail) =
    reject(
      crdt_sim.document(mesh, "peer-a"),
      crdt_core.envelope(peer_b, forged),
    )
  string.contains(detail, "already registered") |> expect.to_be_true
  Nil
}

fn forged_or_set() -> crdt_core.Document {
  let assert Ok(document) =
    crdt_core.new(crdt_core.config(
      room: room,
      compatibility: compatibility,
      replica: "peer-b",
      session: "peer-b-session",
      root: channel.InitOrSet,
    ))
  document
}

pub fn an_unsupported_remote_channel_is_rejected_test() -> Nil {
  let peer = document("peer-b")
  let entry =
    crdt_wire.ChannelEntry(
      crdt_wire.ChannelDescriptor("peer-b:1", channel.MapChannel, "peer-b"),
      channel.MapSnapshot([]),
    )
  reject(
    document("peer-a"),
    crdt_core.envelope(peer, crdt_wire.ChannelAnnounce(entry)),
  )
  |> expect.to_equal(p2p.UnsupportedChannel(channel.MapChannel))
  Nil
}

pub fn a_descriptor_whose_snapshot_is_a_different_kind_is_rejected_test() -> Nil {
  let peer = document("peer-b")
  let entry =
    crdt_wire.ChannelEntry(
      crdt_wire.ChannelDescriptor("peer-b:1", channel.OrSetChannel, "peer-b"),
      channel.GSetSnapshot(g_set_snapshot()),
    )
  let assert p2p.InvalidEnvelope(_, detail) =
    reject(
      document("peer-a"),
      crdt_core.envelope(peer, crdt_wire.ChannelAnnounce(entry)),
    )
  string.contains(detail, "descriptor declares") |> expect.to_be_true
  Nil
}

fn g_set_snapshot() -> GSet(String) {
  let assert channel.GSetSnapshot(state) =
    channel.snapshot(channel.new(channel.InitGSet, replica: "peer-b"))
  state
}

pub fn a_forged_creator_is_rejected_by_the_core_too_test() -> Nil {
  let peer = document("peer-b")
  let entry =
    crdt_wire.ChannelEntry(
      crdt_wire.ChannelDescriptor("peer-b:1", channel.GSetChannel, "peer-z"),
      channel.GSetSnapshot(g_set_snapshot()),
    )
  let assert p2p.InvalidEnvelope(_, detail) =
    reject(
      document("peer-a"),
      crdt_core.envelope(peer, crdt_wire.ChannelAnnounce(entry)),
    )
  string.contains(detail, "claims creator") |> expect.to_be_true
  Nil
}

pub fn a_delta_for_a_differently_typed_address_is_rejected_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-b", channel.InitGSet)
  let mesh = crdt_sim.settle(mesh)
  let peer_b = crdt_sim.document(mesh, "peer-b")
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(
      channel.new(channel.InitOrSet, replica: "peer-b"),
      channel.OrSetAddEdit("fig"),
    )
  let message =
    crdt_wire.Delta(
      crdt_wire.MessageId("peer-b", 99),
      address,
      channel.OrSetChannel,
      op,
    )
  let assert p2p.InvalidEnvelope(_, detail) =
    reject(
      crdt_sim.document(mesh, "peer-a"),
      crdt_core.envelope(peer_b, message),
    )
  string.contains(detail, "is registered as") |> expect.to_be_true
  Nil
}

pub fn an_edit_for_the_wrong_kernel_is_rejected_test() -> Nil {
  let document = document("peer-a")
  let before = crdt_core.digest(document)
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_core.edit(document, root(), channel.TextAppendEdit("nope"))
  crdt_core.digest(document) |> expect.to_equal(before)
  Nil
}

pub fn an_unknown_address_cannot_be_resolved_test() -> Nil {
  let document = document("peer-a")
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_core.channel_state(document, "peer-a:1")
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_core.channel_type(document, "peer-a:1")
  Nil
}

// --- limits ---------------------------------------------------------------

fn limited(replica: String, limits: crdt_wire.Limits) -> crdt_core.Document {
  let assert Ok(document) =
    crdt_core.new(crdt_core.Config(..config(replica), limits: limits))
  document
}

pub fn the_channel_limit_rejects_a_local_creation_test() -> Nil {
  let limits = crdt_wire.Limits(..crdt_wire.default_limits(), channels: 2)
  let document = limited("peer-a", limits)
  let assert Ok(#(document, _)) =
    crdt_core.create_channel(document, channel.InitOrSet)
  let before = crdt_core.digest(document)
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_core.create_channel(document, channel.InitGSet)
  string.contains(detail, "limit of 2 channels") |> expect.to_be_true
  crdt_core.digest(document) |> expect.to_equal(before)
  Nil
}

pub fn the_channel_limit_rejects_a_remote_announcement_test() -> Nil {
  let limits = crdt_wire.Limits(..crdt_wire.default_limits(), channels: 1)
  let local = limited("peer-a", limits)
  let assert Ok(#(peer, outcome)) =
    crdt_core.create_channel(document("peer-b"), channel.InitGSet)
  let assert [message] = outcome.broadcast
  let assert p2p.InvalidEnvelope(_, detail) =
    reject(local, crdt_core.envelope(peer, message))
  string.contains(detail, "limit of 1 channels") |> expect.to_be_true
  Nil
}

/// The buffer is a bounded FIFO that drops its oldest entry, not a gate
/// that shuts. Rejecting the newest arrival let a single orphan delta for a
/// channel nobody ever announces wedge the buffer permanently.
pub fn the_delta_buffer_evicts_the_oldest_orphan_test() -> Nil {
  let limits =
    crdt_wire.Limits(..crdt_wire.default_limits(), buffered_deltas: 2)
  let local = limited("peer-a", limits)
  let assert Ok(#(peer, created)) =
    crdt_core.create_channel(document("peer-b"), channel.InitOrSet)
  let assert [descriptor] = created.created
  let assert [announce] = created.broadcast
  let #(peer, deltas) =
    ["one", "two", "three"]
    |> list.fold(#(peer, []), fn(acc, fruit) {
      let #(peer, deltas) = acc
      let assert Ok(#(peer, edited)) =
        crdt_core.edit(peer, descriptor.address, channel.OrSetAddEdit(fruit))
      let assert [delta] = edited.broadcast
      #(peer, list.append(deltas, [delta]))
    })

  // Three orphan deltas, buffer of two: none is rejected, and the buffer
  // never grows past its bound.
  let local =
    list.fold(deltas, local, fn(local, delta) {
      let assert Ok(#(local, _)) =
        crdt_core.receive(local, crdt_core.envelope(peer, delta))
      { crdt_core.buffered_count(local) <= 2 } |> expect.to_be_true
      local
    })
  crdt_core.buffered_count(local) |> expect.to_equal(2)

  // The announcement drains the two survivors; the evicted oldest is the
  // one missing, and it comes back with the next state transfer.
  let assert Ok(#(local, _)) =
    crdt_core.receive(local, crdt_core.envelope(peer, announce))
  crdt_core.buffered_count(local) |> expect.to_equal(0)
  or_set_values(local, descriptor.address) |> expect.to_equal(["three", "two"])
  let assert Ok(#(local, _)) =
    crdt_core.receive(
      local,
      crdt_core.envelope(peer, crdt_core.state_message(peer)),
    )
  or_set_values(local, descriptor.address)
  |> expect.to_equal(["one", "three", "two"])
  Nil
}

/// Version one buffers exactly 256 pre-descriptor deltas.
pub fn the_default_delta_buffer_holds_256_test() -> Nil {
  crdt_wire.default_limits().buffered_deltas |> expect.to_equal(256)
  Nil
}

/// A delta that declared the wrong channel type used to sit in the buffer
/// as poison: the genuine announcement tried to merge it, failed, and was
/// rejected whole — leaving the poison in place so every later
/// announcement and state transfer for that address failed the same way.
pub fn a_mistyped_buffered_delta_cannot_poison_its_channel_test() -> Nil {
  let local = document("peer-a")
  let assert Ok(#(peer, created)) =
    crdt_core.create_channel(document("peer-b"), channel.InitGSet)
  let assert [descriptor] = created.created
  let assert [announce] = created.broadcast
  let assert Ok(#(peer, edited)) =
    crdt_core.edit(peer, descriptor.address, channel.GSetAddEdit("fig"))
  let assert [genuine] = edited.broadcast

  let assert Ok(#(_, _, poison_op)) =
    channel.apply_p2p_local(
      channel.new(channel.InitOrSet, replica: "peer-c"),
      channel.OrSetAddEdit("poison"),
    )
  let poison =
    crdt_wire.Delta(
      crdt_wire.MessageId("peer-c", 1),
      descriptor.address,
      channel.OrSetChannel,
      poison_op,
    )
  let forger = foreign("peer-c", room, compatibility)

  // Both land before the descriptor does.
  let assert Ok(#(local, _)) =
    crdt_core.receive(local, crdt_core.envelope(forger, poison))
  let assert Ok(#(local, _)) =
    crdt_core.receive(local, crdt_core.envelope(peer, genuine))
  crdt_core.buffered_count(local) |> expect.to_equal(2)

  // The announcement still succeeds, the genuine delta applies, and the
  // poison is gone rather than waiting for the next message.
  let assert Ok(#(local, outcome)) =
    crdt_core.receive(local, crdt_core.envelope(peer, announce))
  list.length(outcome.created) |> expect.to_equal(1)
  crdt_core.buffered_count(local) |> expect.to_equal(0)
  g_set_values(local, descriptor.address) |> expect.to_equal(["fig"])

  // And a later state transfer for the same address is unaffected.
  let assert Ok(#(local, _)) =
    crdt_core.receive(
      local,
      crdt_core.envelope(peer, crdt_core.state_message(peer)),
    )
  g_set_values(local, descriptor.address) |> expect.to_equal(["fig"])
  Nil
}

/// The suppression window is bounded and evicts oldest-first. Suppression
/// is only an optimization, so an evicted id simply merges again — which is
/// a no-op by CRDT law, asserted here rather than assumed.
pub fn the_recent_message_window_evicts_oldest_first_test() -> Nil {
  let limits =
    crdt_wire.Limits(..crdt_wire.default_limits(), recent_message_ids: 2)
  let local = limited("peer-a", limits)
  let assert Ok(#(peer, created)) =
    crdt_core.create_channel(document("peer-b"), channel.InitOrSet)
  let assert [announce] = created.broadcast
  let assert [descriptor] = created.created
  let assert Ok(#(local, _)) =
    crdt_core.receive(local, crdt_core.envelope(peer, announce))

  let #(peer, deltas) =
    ["one", "two", "three"]
    |> list.fold(#(peer, []), fn(acc, fruit) {
      let #(peer, deltas) = acc
      let assert Ok(#(peer, edited)) =
        crdt_core.edit(peer, descriptor.address, channel.OrSetAddEdit(fruit))
      let assert [delta] = edited.broadcast
      #(peer, list.append(deltas, [delta]))
    })
  let local =
    list.fold(deltas, local, fn(local, delta) {
      let assert Ok(#(local, _)) =
        crdt_core.receive(local, crdt_core.envelope(peer, delta))
      { crdt_core.recent_count(local) <= 2 } |> expect.to_be_true
      local
    })

  crdt_core.recent_count(local) |> expect.to_equal(2)
  let assert [first, second, third] = list.map(deltas, delta_id)
  crdt_core.seen(local, first) |> expect.to_be_false
  crdt_core.seen(local, second) |> expect.to_be_true
  crdt_core.seen(local, third) |> expect.to_be_true

  let before = crdt_core.digest(local)
  let assert [oldest, ..] = deltas
  let assert Ok(#(replayed, _)) =
    crdt_core.receive(local, crdt_core.envelope(peer, oldest))
  crdt_core.digest(replayed) |> expect.to_equal(before)
  or_set_values(replayed, descriptor.address)
  |> expect.to_equal(["one", "three", "two"])
  Nil
}

fn delta_id(message: crdt_wire.Message) -> crdt_wire.MessageId {
  let assert crdt_wire.Delta(id, _, _, _) = message
  id
}

pub fn the_envelope_limit_rejects_an_oversize_payload_test() -> Nil {
  let limits =
    crdt_wire.Limits(..crdt_wire.default_limits(), envelope_bytes: 16)
  let local = limited("peer-a", limits)
  let peer = document("peer-b")
  let raw = crdt_core.encode(peer, crdt_core.state_message(peer))
  let before = crdt_core.digest(local)
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_core.receive_encoded(local, raw)
  string.contains(detail, "exceeds the 16 byte limit") |> expect.to_be_true
  crdt_core.digest(local) |> expect.to_equal(before)
  Nil
}

pub fn the_snapshot_limit_rejects_an_oversize_channel_test() -> Nil {
  let limits = crdt_wire.Limits(..crdt_wire.default_limits(), snapshot_bytes: 8)
  let local = limited("peer-a", limits)
  let peer = document("peer-b")
  let raw = crdt_core.encode(peer, crdt_core.state_message(peer))
  let before = crdt_core.digest(local)
  let assert Error(p2p.SnapshotTooLarge(_, 8)) =
    crdt_core.receive_encoded(local, raw)
  crdt_core.digest(local) |> expect.to_equal(before)
  Nil
}

pub fn malformed_json_leaves_valid_local_state_alone_test() -> Nil {
  let mesh = full_mesh(["peer-a"])
  let #(mesh, address) = crdt_sim.create(mesh, "peer-a", channel.InitOrSet)
  let mesh = crdt_sim.edit(mesh, "peer-a", address, channel.OrSetAddEdit("fig"))
  let document = crdt_sim.document(mesh, "peer-a")
  let before = crdt_core.digest(document)
  ["", "{", "[]", "{\"v\":1}", "null"]
  |> list.each(fn(raw) {
    let assert Error(_) = crdt_core.receive_encoded(document, raw)
    Nil
  })
  crdt_core.digest(document) |> expect.to_equal(before)
  or_set_values(document, address) |> expect.to_equal(["fig"])
  Nil
}

pub fn a_rejected_state_message_merges_none_of_its_channels_test() -> Nil {
  let peer = document("peer-b")
  let assert Ok(#(peer, first)) =
    crdt_core.create_channel(peer, channel.InitOrSet)
  let assert [good] = first.created
  let assert crdt_wire.State(entries) = crdt_core.state_message(peer)
  let poisoned =
    crdt_wire.State(
      list.append(entries, [
        crdt_wire.ChannelEntry(
          crdt_wire.ChannelDescriptor("peer-b:9", channel.MapChannel, "peer-b"),
          channel.MapSnapshot([]),
        ),
      ]),
    )
  let document = document("peer-a")
  reject(document, crdt_core.envelope(peer, poisoned))
  |> expect.to_equal(p2p.UnsupportedChannel(channel.MapChannel))
  crdt_core.channel_count(document) |> expect.to_equal(1)
  let assert Error(_) = crdt_core.channel_state(document, good.address)
  Nil
}

// --- multi kind convergence -----------------------------------------------

pub fn every_eligible_kind_converges_across_a_three_peer_mesh_test() -> Nil {
  let mesh = full_mesh(["peer-a", "peer-b", "peer-c"])
  let #(mesh, counter) = crdt_sim.create(mesh, "peer-a", channel.InitPnCounter)
  let #(mesh, tally) =
    crdt_sim.create(mesh, "peer-a", channel.InitOrMap(or_map_kernel.TallyMode))
  let #(mesh, set) = crdt_sim.create(mesh, "peer-b", channel.InitOrSet)
  let #(mesh, two_p) = crdt_sim.create(mesh, "peer-b", channel.InitTwoPSet)
  let #(mesh, text) = crdt_sim.create(mesh, "peer-c", channel.InitText)
  let mesh = crdt_sim.settle(mesh)

  let mesh =
    crdt_sim.edit(mesh, "peer-a", counter, channel.PnCounterEdit(4))
    |> crdt_sim.edit("peer-b", counter, channel.PnCounterEdit(6))
    |> crdt_sim.edit("peer-a", tally, channel.OrMapIncrementEdit("k", 2))
    |> crdt_sim.edit("peer-c", tally, channel.OrMapIncrementEdit("k", 3))
    |> crdt_sim.edit("peer-b", set, channel.OrSetAddEdit("fig"))
    |> crdt_sim.edit("peer-c", two_p, channel.TwoPSetAddEdit("plum"))
    |> crdt_sim.edit("peer-a", text, channel.TextAppendEdit("hi"))
  let #(mesh, packets) = crdt_sim.take_queue(mesh)
  let mesh =
    crdt_sim.enqueue(mesh, list.append(list.reverse(packets), packets))
    |> crdt_sim.settle
    |> crdt_sim.gossip_state

  crdt_sim.names(mesh)
  |> list.each(fn(name) {
    let document = crdt_sim.document(mesh, name)
    counter_value(document, counter) |> expect.to_equal(10)
    let assert Ok(channel.OrMapState(kernel)) =
      crdt_core.channel_state(document, tally)
    or_map_kernel.entries(kernel)
    |> expect.to_equal([#("k", or_map_kernel.Tally(5))])
  })
  converged(mesh)
  Nil
}

pub fn hello_carries_the_compatibility_tag_and_root_test() -> Nil {
  let document = document("peer-a")
  let assert crdt_wire.Hello(compatibility_tag, root_kind) =
    crdt_core.hello_message(document)
  compatibility_tag |> expect.to_equal(compatibility)
  root_kind |> expect.to_equal(channel.GSetChannel)
  Nil
}
