import gleam/json
import gleam/list
import gleam/string
import startest/expect

import watershed/channel
import watershed/crdt_wire
import watershed/or_map_kernel
import watershed/p2p

const room = "trip-planning"

const replica = "replica-a"

const session = "4e65f2"

fn limits() -> crdt_wire.Limits {
  crdt_wire.default_limits()
}

fn wrap(message: crdt_wire.Message) -> crdt_wire.Envelope {
  crdt_wire.Envelope(
    room: room,
    from: replica,
    session: session,
    message: message,
  )
}

fn round_trip(message: crdt_wire.Message) -> crdt_wire.Envelope {
  let envelope = wrap(message)
  let raw = crdt_wire.envelope_to_string(envelope)
  let assert Ok(decoded) = crdt_wire.decode_envelope(raw, limits())
  decoded |> expect.to_equal(envelope)
  decoded
}

fn authored(
  init: channel.ChannelInit,
  edit: channel.P2pEdit,
) -> #(channel.ChannelState, channel.ChannelOp) {
  let assert Ok(#(state, _events, op)) =
    channel.apply_p2p_local(channel.new(init, replica: replica), edit)
  #(state, op)
}

fn descriptor(address: String, creator: String) -> crdt_wire.ChannelDescriptor {
  crdt_wire.ChannelDescriptor(
    address: address,
    channel_type: channel.GSetChannel,
    created_by: creator,
  )
}

fn g_set_entry(address: String, creator: String) -> crdt_wire.ChannelEntry {
  let #(state, _) = authored(channel.InitGSet, channel.GSetAddEdit("kiwi"))
  crdt_wire.ChannelEntry(descriptor(address, creator), channel.snapshot(state))
}

/// Replace one JSON fragment in an encoded envelope. Blunt on purpose: the
/// point is to feed the decoder bytes an honest encoder would never make.
fn tamper(raw: String, from: String, to: String) -> String {
  string.replace(raw, from, to)
}

// --- defaults -------------------------------------------------------------

pub fn version_one_limits_are_the_documented_defaults_test() {
  let limits = crdt_wire.default_limits()
  limits.room_peers |> expect.to_equal(8)
  limits.envelope_bytes |> expect.to_equal(262_144)
  limits.snapshot_bytes |> expect.to_equal(4_194_304)
  limits.channels |> expect.to_equal(1024)
  limits.buffered_deltas |> expect.to_equal(256)
  limits.recent_message_ids |> expect.to_equal(4096)
  Nil
}

pub fn protocol_version_is_exactly_one_test() {
  crdt_wire.protocol_version |> expect.to_equal(1)
  crdt_wire.root_address |> expect.to_equal("root")
  Nil
}

// --- addresses ------------------------------------------------------------

pub fn root_address_has_no_creator_test() {
  crdt_wire.address_creator("root") |> expect.to_equal(Ok(""))
  Nil
}

pub fn channel_addresses_name_their_creator_test() {
  crdt_wire.channel_address("replica-b", 7)
  |> expect.to_equal("replica-b:7")
  crdt_wire.address_creator("replica-b:7")
  |> expect.to_equal(Ok("replica-b"))
  Nil
}

pub fn malformed_addresses_are_rejected_test() {
  [
    "", "replica-b", "replica-b:", ":7", "replica-b:0", "replica-b:-1",
    "replica-b:01", "replica-b:+1", "replica-b:x", "replica-b:1:2", "Root",
  ]
  |> list.each(fn(address) {
    crdt_wire.address_creator(address) |> expect.to_equal(Error(Nil))
  })
  Nil
}

pub fn replica_ids_may_not_be_empty_or_hold_a_colon_test() {
  crdt_wire.valid_replica_id("replica-b") |> expect.to_be_true
  crdt_wire.valid_replica_id("") |> expect.to_be_false
  crdt_wire.valid_replica_id("a:b") |> expect.to_be_false
  Nil
}

// --- round trips ----------------------------------------------------------

pub fn hello_round_trips_test() {
  round_trip(crdt_wire.Hello(
    compatibility: "watershed-crdt-1",
    root: channel.OrSetChannel,
  ))
  Nil
}

pub fn channel_announcement_round_trips_test() {
  round_trip(crdt_wire.ChannelAnnounce(g_set_entry("replica-a:1", replica)))
  Nil
}

pub fn delta_round_trips_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  round_trip(crdt_wire.Delta(
    crdt_wire.MessageId(replica, 17),
    "replica-a:1",
    channel.OrSetChannel,
    op,
  ))
  Nil
}

pub fn state_request_round_trips_test() {
  round_trip(crdt_wire.StateRequest)
  Nil
}

pub fn state_round_trips_and_sorts_by_address_test() {
  let entries = [
    g_set_entry("replica-b:2", "replica-b"),
    g_set_entry("replica-a:1", replica),
  ]
  let decoded = round_trip(crdt_wire.State(crdt_wire.sort_entries(entries)))
  let assert crdt_wire.State(decoded) = decoded.message
  list.map(decoded, fn(entry) { entry.descriptor.address })
  |> expect.to_equal(["replica-a:1", "replica-b:2"])
  Nil
}

pub fn state_encoding_ignores_entry_order_test() {
  let left = [
    g_set_entry("replica-b:2", "replica-b"),
    g_set_entry("replica-a:1", replica),
  ]
  let right = list.reverse(left)
  crdt_wire.envelope_to_string(wrap(crdt_wire.State(left)))
  |> expect.to_equal(crdt_wire.envelope_to_string(wrap(crdt_wire.State(right))))
  Nil
}

/// A replica id outside the basic plane orders one way by UTF-8 bytes and
/// the other way by UTF-16 code units, which is the difference between
/// `string.compare` on Erlang and on JavaScript. Both targets run this
/// file, so a target-dependent comparator here puts two peers' `state`
/// messages in different orders and fails on one of them.
pub fn state_entries_sort_by_utf8_bytes_on_every_target_test() {
  let entries = [
    g_set_entry("peer-𝄞:1", "peer-𝄞"),
    g_set_entry("peer-\u{FFFD}:1", "peer-\u{FFFD}"),
    g_set_entry("peer-a:1", "peer-a"),
  ]
  crdt_wire.sort_entries(entries)
  |> list.map(fn(entry) { entry.descriptor.address })
  |> expect.to_equal(["peer-a:1", "peer-\u{FFFD}:1", "peer-𝄞:1"])
  Nil
}

pub fn digest_round_trips_test() {
  round_trip(crdt_wire.Digest("0f1e2d"))
  Nil
}

pub fn rejection_round_trips_test() {
  round_trip(crdt_wire.Rejected("unsupported-channel", "map is not p2p"))
  Nil
}

pub fn every_eligible_channel_type_round_trips_a_delta_test() {
  [
    #(channel.InitPnCounter, channel.PnCounterEdit(3)),
    #(
      channel.InitOrMap(or_map_kernel.RegisterMode),
      channel.OrMapSetRegisterEdit("k", "v", 9),
    ),
    #(channel.InitOrSet, channel.OrSetAddEdit("a")),
    #(channel.InitGSet, channel.GSetAddEdit("a")),
    #(channel.InitTwoPSet, channel.TwoPSetAddEdit("a")),
    #(channel.InitSequence, channel.SequenceInsertEdit(0, json.string("a"))),
    #(channel.InitText, channel.TextInsertEdit(0, "a")),
  ]
  |> list.each(fn(pair) {
    let #(init, edit) = pair
    let #(state, op) = authored(init, edit)
    let channel_type = channel.init_type(init)
    round_trip(crdt_wire.Delta(
      crdt_wire.MessageId(replica, 1),
      "replica-a:1",
      channel_type,
      op,
    ))
    round_trip(
      crdt_wire.ChannelAnnounce(crdt_wire.ChannelEntry(
        crdt_wire.ChannelDescriptor("replica-a:1", channel_type, replica),
        channel.snapshot(state),
      )),
    )
  })
  Nil
}

pub fn envelope_field_order_is_fixed_test() {
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.StateRequest))
  raw
  |> expect.to_equal(
    "{\"v\":1,\"room\":\"trip-planning\",\"from\":\"replica-a\",\"session\":\"4e65f2\",\"message\":{\"type\":\"stateRequest\"}}",
  )
  Nil
}

// --- rejections -----------------------------------------------------------

pub fn malformed_json_is_rejected_test() {
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_wire.decode_envelope("{not json", limits())
  Nil
}

pub fn a_non_envelope_object_is_rejected_test() {
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_wire.decode_envelope("{\"hello\":true}", limits())
  Nil
}

pub fn another_protocol_version_is_rejected_test() {
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.StateRequest))
  let assert Error(p2p.ProtocolMismatch(1, 2)) =
    crdt_wire.decode_envelope(tamper(raw, "\"v\":1", "\"v\":2"), limits())
  Nil
}

pub fn an_unknown_message_type_is_rejected_test() {
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.StateRequest))
  let assert Error(p2p.InvalidEnvelope(from, _)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"stateRequest\"", "\"gossip\""),
      limits(),
    )
  from |> expect.to_equal(replica)
  Nil
}

pub fn an_empty_sender_identity_is_rejected_test() {
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.StateRequest))
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"from\":\"replica-a\"", "\"from\":\"\""),
      limits(),
    )
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"session\":\"4e65f2\"", "\"session\":\"\""),
      limits(),
    )
  Nil
}

pub fn an_unsupported_channel_type_is_rejected_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 1),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  let assert Error(p2p.UnsupportedChannel(channel.MapChannel)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"channelType\":\"orset\"", "\"channelType\":\"map\""),
      limits(),
    )
  Nil
}

pub fn an_unknown_channel_type_is_rejected_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 1),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  let assert Error(p2p.InvalidEnvelope(_, _)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"channelType\":\"orset\"", "\"channelType\":\"quantum\""),
      limits(),
    )
  Nil
}

/// Local counters start at 1, so zero is as forged as a negative one.
pub fn a_non_positive_message_counter_is_rejected_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 4),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  ["[\"replica-a\",-4]", "[\"replica-a\",0]"]
  |> list.each(fn(forged) {
    let assert Error(p2p.InvalidEnvelope(_, detail)) =
      crdt_wire.decode_envelope(
        tamper(raw, "[\"replica-a\",4]", forged),
        limits(),
      )
    string.contains(detail, "message id") |> expect.to_be_true
  })
  Nil
}

pub fn a_malformed_message_id_is_rejected_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 4),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  [
    tamper(raw, "[\"replica-a\",4]", "[\"replica-a\"]"),
    tamper(raw, "[\"replica-a\",4]", "[\"replica-a\",4,9]"),
    tamper(raw, "[\"replica-a\",4]", "[4,\"replica-a\"]"),
    tamper(raw, "[\"replica-a\",4]", "\"replica-a:4\""),
  ]
  |> list.each(fn(raw) {
    let assert Error(p2p.InvalidEnvelope(_, _)) =
      crdt_wire.decode_envelope(raw, limits())
    Nil
  })
  Nil
}

pub fn a_delta_naming_an_invalid_address_is_rejected_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 1),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"address\":\"replica-a:1\"", "\"address\":\"replica-a:0\""),
      limits(),
    )
  string.contains(detail, "invalid address") |> expect.to_be_true
  Nil
}

pub fn delta_contents_must_match_the_declared_channel_type_test() {
  let #(_, op) = authored(channel.InitOrSet, channel.OrSetAddEdit("plum"))
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.Delta(
        crdt_wire.MessageId(replica, 1),
        "replica-a:1",
        channel.OrSetChannel,
        op,
      )),
    )
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"channelType\":\"orset\"", "\"channelType\":\"text\""),
      limits(),
    )
  string.contains(detail, "do not match channel type") |> expect.to_be_true
  Nil
}

pub fn a_snapshot_must_match_the_declared_channel_type_test() {
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.ChannelAnnounce(g_set_entry("replica-a:1", replica))),
    )
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"channelType\":\"g-set\"", "\"channelType\":\"pnCounter\""),
      limits(),
    )
  string.contains(detail, "does not match channel type") |> expect.to_be_true
  Nil
}

pub fn a_forged_descriptor_creator_is_rejected_test() {
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.ChannelAnnounce(g_set_entry("replica-a:1", replica))),
    )
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(
      tamper(raw, "\"createdBy\":\"replica-a\"", "\"createdBy\":\"replica-z\""),
      limits(),
    )
  string.contains(detail, "claims creator") |> expect.to_be_true
  Nil
}

pub fn a_state_repeating_an_address_is_rejected_test() {
  let entry = g_set_entry("replica-a:1", replica)
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.State([entry, entry])))
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(raw, limits())
  string.contains(detail, "repeats a channel address") |> expect.to_be_true
  Nil
}

pub fn an_oversize_envelope_is_rejected_before_decoding_test() {
  let raw = crdt_wire.envelope_to_string(wrap(crdt_wire.StateRequest))
  let tiny = crdt_wire.Limits(..limits(), envelope_bytes: 8)
  let assert Error(p2p.InvalidEnvelope(_, detail)) =
    crdt_wire.decode_envelope(raw, tiny)
  string.contains(detail, "exceeds the 8 byte limit") |> expect.to_be_true
  Nil
}

pub fn an_oversize_snapshot_is_rejected_test() {
  let raw =
    crdt_wire.envelope_to_string(
      wrap(crdt_wire.ChannelAnnounce(g_set_entry("replica-a:1", replica))),
    )
  let tiny = crdt_wire.Limits(..limits(), snapshot_bytes: 4)
  let assert Error(p2p.SnapshotTooLarge(bytes, 4)) =
    crdt_wire.decode_envelope(raw, tiny)
  { bytes > 4 } |> expect.to_be_true
  Nil
}

pub fn message_types_carry_their_wire_tag_test() {
  crdt_wire.message_type(crdt_wire.StateRequest)
  |> expect.to_equal("stateRequest")
  crdt_wire.message_type(crdt_wire.Digest("x")) |> expect.to_equal("digest")
  crdt_wire.message_type(crdt_wire.Rejected("a", "b"))
  |> expect.to_equal("error")
  crdt_wire.message_type(crdt_wire.State([])) |> expect.to_equal("state")
  crdt_wire.message_type(
    crdt_wire.ChannelAnnounce(g_set_entry("replica-a:1", replica)),
  )
  |> expect.to_equal("channel")
  Nil
}
