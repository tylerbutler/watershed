//// The pure, target-independent CRDT document: identity, a grow-only
//// channel registry, ack-free local edits, remote merges, canonical
//// snapshots, and digests.
////
//// Nothing here performs an effect. Every transition takes a `Document` value
//// and returns a new one, with an `Outcome` value. That outcome describes the
//// protocol messages that a transport must send, and the channel events that a
//// subscriber must see. There is no socket, no timer, no browser API, and no
//// actor. There is also no server-backed lifecycle. This module never calls
//// `runtime_core.handle_sequenced`, an `ack_local` function, a summary upload,
//// or a membership path, because a CRDT document has no sequencer.
////
//// Every entry point that reads remote data is a trust boundary. Malformed
//// input returns a typed `p2p.P2pError` value and leaves the document exactly
//// as it was. There is no partial application, and there is no panic. A `state`
//// message that this module refuses changes nothing, not even the channels
//// that decoded correctly before the bad one.
////
//// There are two snapshot shapes, and that is deliberate. `canonical_json` is
//// the full CRDT state, which is what an import must rebuild. The lattice
//// encodings contain the authoring cursor of each replica, which is the id
//// that the replica stamps its writes with and the counter that it stamps them
//// from, beside the shared causal state. To hash that state directly would
//// make the digest local to the replica. `digest` thus hashes
//// `digest_canonical_json` instead. That function gives the same document
//// without those authoring cursors, and with every merge-relevant field:
//// causal tags, tombstones, version vectors, and LWW timestamps with their
//// replica-id tie-break. Two replicas that hold the same logical state and the
//// same causal state thus share a digest, and two replicas that differ by one
//// tombstone do not.
////
//// `canonical_json` also writes that projection out, and `gleam/json` does
//// not, because two peers that compare a digest can run on different compile
//// targets. `gleam/json` and `gleam/string` order and encode JSON differently
//// on Erlang and on JavaScript. A browser replica that hashes the same state
//// differently from a BEAM replica would ask that replica for a repair without
//// an end. Every order that the lattice encodings leave to a dictionary, which
//// is the object keys, the set-shaped arrays, and the `forwardings` of a
//// sequence, is thus settled here in UTF-8 byte order before the hash.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import watershed/canonical_json
import watershed/channel.{
  type ChannelEvent, type ChannelInit, type ChannelOperation, type ChannelState,
  type ChannelType, type P2pEdit, type Snapshot,
}
import watershed/crdt_wire.{
  type ChannelDescriptor, type ChannelEntry, type Envelope, type Limits,
  type Message, type MessageId, ChannelDescriptor, ChannelEntry, MessageId,
}
import watershed/json_ot.{type JsonValue}
import watershed/p2p.{type P2pError}
import watershed/sha256
import watershed/wire

/// Everything that a replica needs to agree with its peers about the document
/// that it is in. `replica` is the CRDT authorship identity, and a collision
/// between two of them is very unlikely. `session` separates two connections of
/// one installation. A peer that claims the local `replica` value under a
/// different `session` value is a `ReplicaCollision`, and not a peer.
pub type Config {
  Config(
    room: String,
    compatibility: String,
    replica: String,
    session: String,
    root: ChannelInit,
    limits: Limits,
  )
}

/// A config carrying the version-1 default limits.
pub fn config(
  room room: String,
  compatibility compatibility: String,
  replica replica: String,
  session session: String,
  root root: ChannelInit,
) -> Config {
  Config(
    room: room,
    compatibility: compatibility,
    replica: replica,
    session: session,
    root: root,
    limits: crdt_wire.default_limits(),
  )
}

pub opaque type Document {
  Document(
    config: Config,
    /// The source of the channel addresses and of the outbound message ids. No
    /// local message and no local channel can thus use the identity of
    /// another.
    counter: Int,
    registry: Dict(String, ChannelDescriptor),
    states: Dict(String, ChannelState),
    /// The deltas that named an address before its descriptor arrived, oldest
    /// first. `limits.buffered_deltas` is the maximum count.
    buffered: Fifo(BufferedDelta),
    /// The message ids that this document accepted recently.
    /// `limits.recent_message_ids` is the maximum count. The suppression is an
    /// optimization only. To merge a delta again changes nothing, by the CRDT
    /// laws.
    recent: Recent,
  )
}

type BufferedDelta {
  BufferedDelta(
    id: MessageId,
    address: String,
    channel_type: ChannelType,
    operation: ChannelOperation,
  )
}

/// The bounded window for duplicate suppression: a `Dict` for the membership,
/// and a `Fifo` to remove the oldest id first.
///
/// A plain list cost one linear scan for each lookup *and* one linear copy for
/// each insert, at the default size of 4,096, on the path of every accepted
/// message. The dict answers `seen` without a walk. The dict and the queue hold
/// exactly the same ids, because an id that is already in the dict never enters
/// the queue a second time. An eviction thus can never remove membership that a
/// live entry still needs.
type Recent {
  Recent(seen: Dict(MessageId, Nil), queue: Fifo(MessageId))
}

/// The usual two-list queue with a size counter, which has an amortized
/// constant cost. It is in this module because `gleam/deque` is no longer in
/// the standard library, and this module is its only user. A push goes on
/// `back`. A pop takes from `front`, and the queue fills `front` again by
/// reversing `back` when `front` becomes empty.
type Fifo(element) {
  Fifo(front: List(element), back: List(element), size: Int)
}

fn fifo_new() -> Fifo(element) {
  Fifo(front: [], back: [], size: 0)
}

fn fifo_from_list(elements: List(element)) -> Fifo(element) {
  Fifo(front: elements, back: [], size: list.length(elements))
}

fn fifo_to_list(fifo: Fifo(element)) -> List(element) {
  list.append(fifo.front, list.reverse(fifo.back))
}

fn fifo_push(fifo: Fifo(element), element: element) -> Fifo(element) {
  Fifo(..fifo, back: [element, ..fifo.back], size: fifo.size + 1)
}

fn fifo_pop(fifo: Fifo(element)) -> Result(#(element, Fifo(element)), Nil) {
  case fifo.front, fifo.back {
    [], [] -> Error(Nil)
    [], back ->
      fifo_pop(Fifo(front: list.reverse(back), back: [], size: fifo.size))
    [oldest, ..front], _ ->
      Ok(#(oldest, Fifo(..fifo, front: front, size: fifo.size - 1)))
  }
}

/// What a transition asks its transport to do next, with what changed.
/// `broadcast` goes to every peer. `reply` goes only to the peer whose message
/// produced it. The transport decides whether to forward a received message, so
/// a received message never fills `broadcast`.
pub type Outcome {
  Outcome(
    broadcast: List(Message),
    reply: List(Message),
    created: List(ChannelDescriptor),
    events: List(#(String, ChannelEvent)),
  )
}

pub fn empty_outcome() -> Outcome {
  Outcome(broadcast: [], reply: [], created: [], events: [])
}

// --- construction ---------------------------------------------------------

/// Start a document at the empty root that the config names. Every peer runs
/// this function, and so does the first peer in an empty room. The root comes
/// from `Config`, and never from a peer. Two replicas that agree on the config
/// thus agree on the root, and they exchange no message.
pub fn new(config: Config) -> Result(Document, P2pError) {
  use _ <- result.try(validate_config(config))
  use root_type <- result.try(p2p.validate(channel.init_type(config.root)))
  let descriptor =
    ChannelDescriptor(
      address: crdt_wire.root_address,
      channel_type: root_type,
      created_by: "",
    )
  Ok(Document(
    config: config,
    counter: 0,
    registry: dict.from_list([#(crdt_wire.root_address, descriptor)]),
    states: dict.from_list([
      #(
        crdt_wire.root_address,
        channel.new(config.root, replica: config.replica),
      ),
    ]),
    buffered: fifo_new(),
    recent: empty_recent(),
  ))
}

fn validate_config(config: Config) -> Result(Nil, P2pError) {
  let limits = config.limits
  case
    config.room != "",
    crdt_wire.valid_replica_id(config.replica),
    config.session != "",
    limits.channels > 0
    && limits.envelope_bytes > 0
    && limits.snapshot_bytes > 0
    && limits.room_peers > 0
    && limits.buffered_deltas >= 0
    && limits.recent_message_ids >= 0
  {
    False, _, _, _ -> Error(rejected(config.replica, "room id is empty"))
    _, False, _, _ ->
      Error(rejected(
        config.replica,
        "replica id must be non-empty and free of ':'",
      ))
    _, _, False, _ -> Error(rejected(config.replica, "session id is empty"))
    _, _, _, False -> Error(rejected(config.replica, "limits are not positive"))
    True, True, True, True -> Ok(Nil)
  }
}

// --- reads ----------------------------------------------------------------

pub fn config_of(document: Document) -> Config {
  document.config
}

pub fn room(document: Document) -> String {
  document.config.room
}

pub fn compatibility(document: Document) -> String {
  document.config.compatibility
}

pub fn replica(document: Document) -> String {
  document.config.replica
}

pub fn session(document: Document) -> String {
  document.config.session
}

pub fn limits(document: Document) -> Limits {
  document.config.limits
}

pub fn root_type(document: Document) -> ChannelType {
  channel.init_type(document.config.root)
}

/// Every registered descriptor, in canonical address order, which is UTF-8 byte
/// order. That order is the same on both targets, and the order of
/// `string.compare` is not.
pub fn descriptors(document: Document) -> List(ChannelDescriptor) {
  dict.values(document.registry)
  |> list.sort(fn(left, right) {
    canonical_json.compare(left.address, right.address)
  })
}

pub fn channel_count(document: Document) -> Int {
  dict.size(document.registry)
}

pub fn buffered_count(document: Document) -> Int {
  document.buffered.size
}

/// The number of message ids in the duplicate-suppression window. The value is
/// never more than `limits.recent_message_ids`.
pub fn recent_count(document: Document) -> Int {
  dict.size(document.recent.seen)
}

pub fn seen(document: Document, id: MessageId) -> Bool {
  dict.has_key(document.recent.seen, id)
}

pub fn descriptor(
  document: Document,
  address: String,
) -> Result(ChannelDescriptor, P2pError) {
  case dict.get(document.registry, address) {
    Error(_) ->
      Error(rejected(
        document.config.replica,
        "no channel registered at " <> address,
      ))
    Ok(descriptor) -> {
      use _ <- result.try(p2p.validate(descriptor.channel_type))
      Ok(descriptor)
    }
  }
}

/// The channel type at an address. The function refuses to name a channel whose
/// kernel cannot run without a sequencer.
pub fn channel_type(
  document: Document,
  address: String,
) -> Result(ChannelType, P2pError) {
  use descriptor <- result.try(descriptor(document, address))
  Ok(descriptor.channel_type)
}

/// The kernel state at an address. The function checks the eligibility of the
/// channel first.
pub fn channel_state(
  document: Document,
  address: String,
) -> Result(ChannelState, P2pError) {
  use _ <- result.try(descriptor(document, address))
  case dict.get(document.states, address) {
    Ok(state) -> Ok(state)
    Error(_) ->
      Error(rejected(document.config.replica, "no channel state at " <> address))
  }
}

// --- outbound messages ----------------------------------------------------

pub fn hello_message(document: Document) -> Message {
  crdt_wire.Hello(
    compatibility: document.config.compatibility,
    root: root_type(document),
  )
}

pub fn state_request_message() -> Message {
  crdt_wire.StateRequest
}

/// The whole registry of this document, with its current snapshots, in
/// canonical address order.
pub fn state_message(document: Document) -> Message {
  crdt_wire.State(entries(document))
}

pub fn digest_message(document: Document) -> Message {
  crdt_wire.Digest(digest(document))
}

pub fn rejection_message(reason: String, detail: String) -> Message {
  crdt_wire.Rejected(reason, detail)
}

/// Put an outbound message in the addressing of this document.
pub fn envelope(document: Document, message: Message) -> Envelope {
  crdt_wire.Envelope(
    room: document.config.room,
    from: document.config.replica,
    session: document.config.session,
    message: message,
  )
}

pub fn encode(document: Document, message: Message) -> String {
  crdt_wire.envelope_to_string(envelope(document, message))
}

// --- local transitions ----------------------------------------------------

/// Register a new channel under an address that comes from the identity of
/// this replica, and thus cannot collide. Then announce that channel.
pub fn create_channel(
  document: Document,
  init: ChannelInit,
) -> Result(#(Document, Outcome), P2pError) {
  use init <- result.try(p2p.validate_create(init))
  use _ <- result.try(check_capacity(document))
  let counter = document.counter + 1
  let address = crdt_wire.channel_address(document.config.replica, counter)
  let descriptor =
    ChannelDescriptor(
      address: address,
      channel_type: channel.init_type(init),
      created_by: document.config.replica,
    )
  let state = channel.new(init, replica: document.config.replica)
  let document =
    Document(
      ..document,
      counter: counter,
      registry: dict.insert(document.registry, address, descriptor),
      states: dict.insert(document.states, address, state),
    )
  let announce =
    crdt_wire.ChannelAnnounce(ChannelEntry(descriptor, channel.snapshot(state)))
  Ok(#(
    document,
    Outcome(broadcast: [announce], reply: [], created: [descriptor], events: []),
  ))
}

/// Write a local edit. The function merges it into the confirmed state and the
/// visible state in one ack-free transition, and it returns the delta to
/// broadcast.
pub fn edit(
  document: Document,
  address: String,
  edit: P2pEdit,
) -> Result(#(Document, Outcome), P2pError) {
  use descriptor <- result.try(descriptor(document, address))
  use state <- result.try(channel_state(document, address))
  case channel.apply_p2p_local(state, edit) {
    Error(error) ->
      Error(rejected(document.config.replica, channel_error_detail(error)))
    Ok(#(state, events, operation)) -> {
      let counter = document.counter + 1
      let id = MessageId(document.config.replica, counter)
      let document =
        Document(
          ..document,
          counter: counter,
          states: dict.insert(document.states, address, state),
          recent: remember(document, id),
        )
      Ok(#(
        document,
        Outcome(
          broadcast: [
            crdt_wire.Delta(id, address, descriptor.channel_type, operation),
          ],
          reply: [],
          created: [],
          events: tag(address, events),
        ),
      ))
    }
  }
}

// --- remote transitions ---------------------------------------------------

/// Decode and apply one encoded envelope. The size check, the protocol check,
/// and the shape check all run before the function changes any state.
pub fn receive_encoded(
  document: Document,
  raw: String,
) -> Result(#(Document, Outcome), P2pError) {
  use envelope <- result.try(crdt_wire.decode_envelope(
    raw,
    document.config.limits,
  ))
  receive(document, envelope)
}

/// Apply one envelope. A caller that builds an `Envelope` value directly, such
/// as a relay that replays its own log, or a test, gets the same checks as an
/// envelope from the wire. This function checks the descriptors and the channel
/// types again. It does not assume that the decoder ran.
///
/// The message id of a delta does not have to name the sender, and that is
/// deliberate. A mesh peer and a relay both forward a delta that they did not
/// write. The id identifies the message of the *author*, so the duplicate
/// suppression still works after a message takes two routes.
pub fn receive(
  document: Document,
  envelope: Envelope,
) -> Result(#(Document, Outcome), P2pError) {
  received(document, envelope, None)
}

/// `receive`, with the canonical digest that this document already has.
///
/// `Digest` is the one message whose handler reads the local digest. To compute
/// that digest, the module canonicalizes and hashes the whole document. A
/// transport with a heartbeat sends a message every 250 ms, to every peer, in
/// both directions. It thus pays that cost for each message, also for a
/// document that did not change. A caller that holds a digest cache gives it to
/// this function. Every other message goes to `receive`, and no code computes
/// the digest at all.
///
/// `local` must be `digest(document)` for *this* document. A stale value would
/// answer an anti-entropy comparison against a state that this replica no
/// longer holds. It would thus suppress a repair that the replica owes, or ask
/// for a repair that it does not need. A cache that supplies this value must
/// thus use the document itself as its key. Do not invalidate that cache by
/// hand.
pub fn receive_with_digest(
  document: Document,
  envelope: Envelope,
  digest local: String,
) -> Result(#(Document, Outcome), P2pError) {
  received(document, envelope, Some(local))
}

fn received(
  document: Document,
  envelope: Envelope,
  local: Option(String),
) -> Result(#(Document, Outcome), P2pError) {
  use _ <- result.try(case envelope.room == document.config.room {
    True -> Ok(Nil)
    False -> Error(p2p.RoomMismatch)
  })
  case
    envelope.from == document.config.replica,
    envelope.session == document.config.session
  {
    True, False -> Error(p2p.ReplicaCollision(envelope.from))
    // Our own message, fanned back to us. Merging it is a no-operation by CRDT
    // law; skipping it keeps the recent-ID window meaningful.
    True, True -> Ok(#(document, empty_outcome()))
    False, _ -> apply_message(document, envelope.from, envelope.message, local)
  }
}

fn apply_message(
  document: Document,
  from: String,
  message: Message,
  local: Option(String),
) -> Result(#(Document, Outcome), P2pError) {
  case message {
    crdt_wire.Hello(compatibility, root) -> {
      use _ <- result.try(case compatibility == document.config.compatibility {
        True -> Ok(Nil)
        False ->
          Error(p2p.CompatibilityMismatch(
            document.config.compatibility,
            compatibility,
          ))
      })
      use _ <- result.try(case root == root_type(document) {
        True -> Ok(Nil)
        False -> Error(p2p.RootMismatch(root_type(document), root))
      })
      Ok(#(document, empty_outcome()))
    }
    crdt_wire.ChannelAnnounce(entry) -> merge_entries(document, from, [entry])
    crdt_wire.Delta(id, address, channel_type, operation) ->
      apply_delta(document, from, id, address, channel_type, operation)
    crdt_wire.StateRequest ->
      Ok(#(
        document,
        Outcome(
          broadcast: [],
          reply: [state_message(document)],
          created: [],
          events: [],
        ),
      ))
    crdt_wire.State(entries) -> merge_entries(document, from, entries)
    crdt_wire.Digest(remote) ->
      case remote == option.lazy_unwrap(local, fn() { digest(document) }) {
        True -> Ok(#(document, empty_outcome()))
        False ->
          Ok(#(
            document,
            Outcome(
              broadcast: [],
              reply: [crdt_wire.StateRequest],
              created: [],
              events: [],
            ),
          ))
      }
    // A peer telling us it rejected something changes no local state; the
    // transport decides whether to close that peer.
    crdt_wire.Rejected(_, _) -> Ok(#(document, empty_outcome()))
  }
}

fn apply_delta(
  document: Document,
  from: String,
  id: MessageId,
  address: String,
  channel_type: ChannelType,
  operation: ChannelOperation,
) -> Result(#(Document, Outcome), P2pError) {
  use _ <- result.try(check_address(address, from))
  use _ <- result.try(p2p.validate(channel_type))
  case seen(document, id) {
    True -> Ok(#(document, empty_outcome()))
    False ->
      case dict.get(document.registry, address) {
        Error(_) ->
          Ok(buffer_delta(document, id, address, channel_type, operation))
        Ok(descriptor) ->
          case descriptor.channel_type == channel_type {
            False ->
              Error(rejected(
                from,
                "delta declares "
                  <> channel.type_to_string(channel_type)
                  <> " but "
                  <> address
                  <> " is registered as "
                  <> channel.type_to_string(descriptor.channel_type),
              ))
            True -> {
              use #(document, events) <- result.try(merge_operation(
                document,
                from,
                address,
                operation,
              ))
              Ok(#(
                Document(..document, recent: remember(document, id)),
                Outcome(broadcast: [], reply: [], created: [], events: events),
              ))
            }
          }
      }
  }
}

fn merge_operation(
  document: Document,
  from: String,
  address: String,
  operation: ChannelOperation,
) -> Result(#(Document, List(#(String, ChannelEvent))), P2pError) {
  use state <- result.try(channel_state(document, address))
  case channel.apply_p2p_remote(state, operation) {
    Error(error) -> Error(rejected(from, channel_error_detail(error)))
    Ok(#(state, events)) ->
      Ok(#(
        Document(
          ..document,
          states: dict.insert(document.states, address, state),
        ),
        tag(address, events),
      ))
  }
}

/// Queue a delta whose channel has no announcement yet.
///
/// The buffer is a bounded FIFO. When it is full it removes its *oldest*
/// entry, and it does not refuse the newest one. To refuse the newest entry
/// caused a permanent failure. An orphan delta names a channel that no peer
/// ever announces, because the address is forged, or because the peer left
/// before it announced. Such a delta holds its slot forever, so a full buffer
/// would refuse every valid later delta for the rest of the life of the
/// document. To remove the oldest entry limits the same memory without that
/// failure, and it costs nothing in correctness. A delta that the buffer
/// removes is one whose descriptor never arrived, and every peer that still
/// holds that channel carries the same edit in its next `state` transfer.
///
/// This function does *not* record the message id, and that is deliberate. The
/// module records the id when it applies the delta. A delta that the buffer
/// removed, or that the flush discarded, is thus not suppressed as a duplicate
/// when the sender sends it again after it announces the channel.
fn buffer_delta(
  document: Document,
  id: MessageId,
  address: String,
  channel_type: ChannelType,
  operation: ChannelOperation,
) -> #(Document, Outcome) {
  let limit = document.config.limits.buffered_deltas
  case limit <= 0 {
    True -> #(document, empty_outcome())
    False -> {
      let queued =
        fifo_push(
          document.buffered,
          BufferedDelta(id, address, channel_type, operation),
        )
      let buffered = case queued.size > limit {
        True ->
          case fifo_pop(queued) {
            Ok(#(_, rest)) -> rest
            Error(_) -> queued
          }
        False -> queued
      }
      #(Document(..document, buffered: buffered), empty_outcome())
    }
  }
}

/// Merge the channels of an announcement or a transfer. The function accepts
/// all of them or none of them. One bad entry refuses the whole message. Every
/// intermediate document is a new value, so the caller keeps the document that
/// it started with.
fn merge_entries(
  document: Document,
  from: String,
  entries: List(ChannelEntry),
) -> Result(#(Document, Outcome), P2pError) {
  list.try_fold(entries, #(document, empty_outcome()), fn(acc, entry) {
    let #(document, outcome) = acc
    use #(document, next) <- result.try(merge_entry(document, from, entry))
    Ok(#(document, combine(outcome, next)))
  })
}

fn merge_entry(
  document: Document,
  from: String,
  entry: ChannelEntry,
) -> Result(#(Document, Outcome), P2pError) {
  let descriptor = entry.descriptor
  use creator <- result.try(check_address(descriptor.address, from))
  use _ <- result.try(case creator == descriptor.created_by {
    True -> Ok(Nil)
    False ->
      Error(rejected(
        from,
        "channel "
          <> descriptor.address
          <> " claims creator "
          <> descriptor.created_by
          <> " but its address names "
          <> creator,
      ))
  })
  use _ <- result.try(p2p.validate(descriptor.channel_type))
  use _ <- result.try(
    case channel.snapshot_type(entry.snapshot) == descriptor.channel_type {
      True -> Ok(Nil)
      False ->
        Error(rejected(
          from,
          "snapshot for "
            <> descriptor.address
            <> " is a "
            <> channel.type_to_string(channel.snapshot_type(entry.snapshot))
            <> " but the descriptor declares "
            <> channel.type_to_string(descriptor.channel_type),
        ))
    },
  )
  case dict.get(document.registry, descriptor.address) {
    Ok(existing) if existing != descriptor ->
      case descriptor.address == crdt_wire.root_address {
        True ->
          Error(p2p.RootMismatch(existing.channel_type, descriptor.channel_type))
        False ->
          Error(rejected(
            from,
            "channel "
              <> descriptor.address
              <> " is already registered as "
              <> channel.type_to_string(existing.channel_type)
              <> " created by "
              <> existing.created_by,
          ))
      }
    Ok(_) -> {
      use state <- result.try(channel_state(document, descriptor.address))
      use #(document, events) <- result.try(merge_snapshot(
        document,
        from,
        descriptor.address,
        state,
        entry.snapshot,
      ))
      Ok(#(
        document,
        Outcome(broadcast: [], reply: [], created: [], events: events),
      ))
    }
    Error(_) -> {
      use _ <- result.try(check_capacity(document))
      use init <- result.try(init_for(entry.snapshot))
      let state = channel.new(init, replica: document.config.replica)
      use #(document, events) <- result.try(merge_snapshot(
        document,
        from,
        descriptor.address,
        state,
        entry.snapshot,
      ))
      let document =
        Document(
          ..document,
          registry: dict.insert(
            document.registry,
            descriptor.address,
            descriptor,
          ),
        )
      let #(document, buffered) =
        flush_buffered(
          document,
          from,
          descriptor.address,
          descriptor.channel_type,
        )
      Ok(#(
        document,
        Outcome(
          broadcast: [],
          reply: [],
          created: [descriptor],
          events: list.append(events, buffered),
        ),
      ))
    }
  }
}

fn merge_snapshot(
  document: Document,
  from: String,
  address: String,
  state: ChannelState,
  snapshot: Snapshot,
) -> Result(#(Document, List(#(String, ChannelEvent))), P2pError) {
  case channel.merge_p2p_snapshot(state, snapshot) {
    Error(error) -> Error(rejected(from, channel_error_detail(error)))
    Ok(#(state, events)) ->
      Ok(#(
        Document(
          ..document,
          states: dict.insert(document.states, address, state),
        ),
        tag(address, events),
      ))
  }
}

/// Apply the deltas that waited on this address, oldest first, and keep only
/// the deltas that can belong to the channel that arrived.
///
/// To partition on the address alone permitted a denial of service. A forged
/// delta or a stale delta can name an address with no announcement, under the
/// wrong channel type. To merge such a delta into the announced kernel fails.
/// An announcement accepts all of its entries or none of them, so that failure
/// refused the correct `channel` message *and* kept the bad delta in the
/// buffer. Every later announcement and every later `state` transfer that
/// touched that address then failed in the same way, without an end.
///
/// The module can never apply a buffered delta whose declared type disagrees
/// with the descriptor, so it discards that delta. It also drops a delta that
/// still fails to merge, and it does not forward that delta. The module
/// accepted the delta from a peer that is not the announcer, before it knew the
/// channel, and such a delta must not be able to invalidate the
/// announcement.
fn flush_buffered(
  document: Document,
  from: String,
  address: String,
  channel_type: ChannelType,
) -> #(Document, List(#(String, ChannelEvent))) {
  let #(ready, rest) =
    list.partition(fifo_to_list(document.buffered), fn(buffered) {
      buffered.address == address
    })
  let document = Document(..document, buffered: fifo_from_list(rest))
  list.filter(ready, fn(buffered) { buffered.channel_type == channel_type })
  |> list.fold(#(document, []), fn(acc, buffered) {
    let #(document, events) = acc
    case merge_operation(document, from, address, buffered.operation) {
      Error(_) -> acc
      Ok(#(document, next)) -> #(
        Document(..document, recent: remember(document, buffered.id)),
        list.append(events, next),
      )
    }
  })
}

// --- canonical snapshots and digests --------------------------------------

/// The document as canonical JSON. The field order is fixed, the channels are
/// sorted by address, and the snapshot codec of each channel encodes that
/// channel. Two replicas that reached the same value through different delivery
/// orders produce the same bytes.
pub fn canonical_json(document: Document) -> String {
  json.to_string(
    json.object([
      #("v", json.int(crdt_wire.protocol_version)),
      #("room", json.string(document.config.room)),
      #("compatibility", json.string(document.config.compatibility)),
      #("root", json.string(channel.type_to_string(root_type(document)))),
      #(
        "channels",
        json.array(entries(document), crdt_wire.encode_channel_entry),
      ),
    ]),
  )
}

/// The digest projection: `canonical_json`, with the state of each channel
/// reduced to the part that two replicas with the same logical state *and* the
/// same causal state must agree on.
///
/// The function removes the authoring cursors of each replica only. Those are
/// the id that the replica stamps its own writes with, and the counter that it
/// stamps them from. The causal metadata, the tombstones, the pruning vectors,
/// the version vectors, the remove bounds, and the LWW timestamps with their
/// replica-id tie-break all stay. This is thus a comparison of state, and not
/// of values. A peer that has seen a removal that its neighbour has not seen
/// fails the comparison, and it receives a repair.
///
/// The bytes come from `canonical_json`, and not from `gleam/json`. The object
/// keys go out in UTF-8 byte order, a set-shaped array is ordered by the
/// canonical bytes of its elements, and every number has one form. Neither the
/// iteration order of a dictionary nor the compile target can thus move one
/// byte.
pub fn digest_canonical_json(document: Document) -> String {
  canonical_json.to_string(
    json_ot.VObject([
      #("v", json_ot.VNumber(json_ot.NInt(crdt_wire.protocol_version))),
      #("room", json_ot.VString(document.config.room)),
      #("compatibility", json_ot.VString(document.config.compatibility)),
      #("root", json_ot.VString(channel.type_to_string(root_type(document)))),
      #("channels", json_ot.VArray(list.map(entries(document), digest_entry))),
    ]),
  )
}

/// The SHA-256 of `digest_canonical_json`, as lowercase hex. Two replicas that
/// reached the same state, through any delivery order and on either compile
/// target, get the same value.
pub fn digest(document: Document) -> String {
  sha256.hex(digest_canonical_json(document))
}

/// This function builds the entry, and `crdt_wire.encode_descriptor` does not.
/// The digest is a projection of the state, and not a wire message. A new name
/// for an envelope field must not change it.
fn digest_entry(entry: ChannelEntry) -> JsonValue {
  let ChannelDescriptor(address, channel_type, created_by) = entry.descriptor
  json_ot.VObject([
    #(
      "descriptor",
      json_ot.VObject([
        #("address", json_ot.VString(address)),
        #("channelType", json_ot.VString(channel.type_to_string(channel_type))),
        #("createdBy", json_ot.VString(created_by)),
      ]),
    ),
    #("state", projected(entry.snapshot)),
  ])
}

fn projected(snapshot: Snapshot) -> JsonValue {
  channel.encode_snapshot(snapshot)
  |> json.to_string
  |> parse_value
  |> merge_relevant
}

/// Remove the replica-local authoring cursors from one self-describing lattice
/// envelope.
///
/// The function dispatches on the `type` tag of the envelope, and not on a
/// field path. One function thus handles a channel snapshot and the CRDTs that
/// an OR-map holds inside that snapshot as *stringified* JSON. The function
/// returns a value that it does not recognize without a change, so it compares
/// an unknown encoding in full. It does not weaken that comparison quietly.
/// `lww_register` is in that group on purpose. Its `replica_id` field is the
/// tie-break half of a timestamp, and not an authoring cursor. To remove it
/// would let two different winners produce the same hash.
fn merge_relevant(value: JsonValue) -> JsonValue {
  case type_tag(value) {
    "pn_counter" ->
      map_member(value, "state", fn(state) {
        state
        |> map_member("positive", without(_, ["self_id"]))
        |> map_member("negative", without(_, ["self_id"]))
      })
    "g_counter" -> map_member(value, "state", without(_, ["self_id"]))
    "or_set" ->
      map_member(value, "state", fn(state) {
        state
        |> without(["replica_id", "counter"])
        |> map_member("entries", map_each(_, ordered))
        |> map_member("tombstones", ordered)
      })
    "g_set" -> map_member(value, "state", map_member(_, "elements", ordered))
    "two_p_set" ->
      map_member(value, "state", fn(state) {
        state
        |> map_member("added", ordered)
        |> map_member("removed", ordered)
      })
    "sequence" ->
      map_member(value, "state", fn(state) {
        state
        |> without(["self_id", "counter"])
        |> map_member("forwardings", ordered)
      })
    "or_map" ->
      map_member(value, "state", fn(state) {
        state
        |> without(["replica_id"])
        |> map_member("key_set", inner)
        |> map_member("values", or_map_values)
      })
    _ -> value
  }
}

/// The values of an OR-map: an array of `{key, crdt}` pairs. The `crdt` field
/// of a pair is a nested CRDT envelope, as a string. The function projects each
/// pair, and then it orders the array, because that array comes from a
/// dictionary and the order of a dictionary is not part of the state.
fn or_map_values(value: JsonValue) -> JsonValue {
  case value {
    json_ot.VArray(items) ->
      json_ot.VArray(list.map(items, map_member(_, "crdt", inner)))
      |> ordered
    other -> other
  }
}

/// Project a CRDT envelope that another envelope carries as a JSON string, and
/// write it back as a canonical string, so that the shape stays the same. The
/// function does not change a string that is not valid JSON.
fn inner(value: JsonValue) -> JsonValue {
  case value {
    json_ot.VString(raw) ->
      case json.parse(raw, json_ot.decoder()) {
        Ok(parsed) ->
          json_ot.VString(canonical_json.to_string(merge_relevant(parsed)))
        Error(_) -> value
      }
    other -> other
  }
}

fn parse_value(raw: String) -> JsonValue {
  json.parse(raw, json_ot.decoder())
  |> result.unwrap(json_ot.VString(raw))
}

fn type_tag(value: JsonValue) -> String {
  case value {
    json_ot.VObject(members) ->
      case list.key_find(members, "type") {
        Ok(json_ot.VString(tag)) -> tag
        Ok(_) -> ""
        Error(Nil) -> ""
      }
    json_ot.VNull -> ""
    json_ot.VBool(_) -> ""
    json_ot.VNumber(_) -> ""
    json_ot.VString(_) -> ""
    json_ot.VArray(_) -> ""
  }
}

fn map_member(
  value: JsonValue,
  name: String,
  transform: fn(JsonValue) -> JsonValue,
) -> JsonValue {
  case value {
    json_ot.VObject(members) ->
      json_ot.VObject(
        list.map(members, fn(member) {
          case member.0 == name {
            True -> #(member.0, transform(member.1))
            False -> member
          }
        }),
      )
    other -> other
  }
}

fn map_each(
  value: JsonValue,
  transform: fn(JsonValue) -> JsonValue,
) -> JsonValue {
  case value {
    json_ot.VObject(members) ->
      json_ot.VObject(
        list.map(members, fn(member) { #(member.0, transform(member.1)) }),
      )
    other -> other
  }
}

fn without(value: JsonValue, names: List(String)) -> JsonValue {
  case value {
    json_ot.VObject(members) ->
      json_ot.VObject(
        list.filter(members, fn(member) { !list.contains(names, member.0) }),
      )
    other -> other
  }
}

/// Order a set-shaped array by the canonical bytes of its elements. Use this
/// function on a field that the CRDT defines as a set or as a map only. Never
/// use it on the segments of a sequence, where the order *is* the state.
fn ordered(value: JsonValue) -> JsonValue {
  case value {
    json_ot.VArray(items) -> json_ot.VArray(canonical_json.sorted(items))
    other -> other
  }
}

/// Merge an exported snapshot back into the document. The function checks the
/// size, the room, the protocol, the compatibility, and the root, before it
/// touches one channel. The merge is a join, so the local channels and the
/// local edits all stay.
pub fn import_snapshot(
  document: Document,
  raw: String,
) -> Result(#(Document, Outcome), P2pError) {
  use _ <- result.try(check_snapshot_size(document, raw))
  let from = document.config.replica
  use snapshot <- result.try(
    json.parse(raw, canonical_decoder())
    |> result.replace_error(rejected(from, "malformed canonical snapshot")),
  )
  let CanonicalSnapshot(version, room, compatibility, root, channels) = snapshot
  use _ <- result.try(case version == crdt_wire.protocol_version {
    True -> Ok(Nil)
    False -> Error(p2p.ProtocolMismatch(crdt_wire.protocol_version, version))
  })
  use _ <- result.try(case room == document.config.room {
    True -> Ok(Nil)
    False -> Error(p2p.RoomMismatch)
  })
  use _ <- result.try(case compatibility == document.config.compatibility {
    True -> Ok(Nil)
    False ->
      Error(p2p.CompatibilityMismatch(
        document.config.compatibility,
        compatibility,
      ))
  })
  use root <- result.try(eligible_type(root, from))
  use _ <- result.try(case root == root_type(document) {
    True -> Ok(Nil)
    False -> Error(p2p.RootMismatch(root_type(document), root))
  })
  use entries <- result.try(
    list.try_map(channels, fn(entry) {
      crdt_wire.decode_channel_entry(entry, from, document.config.limits)
    }),
  )
  merge_entries(document, from, entries)
}

type CanonicalSnapshot {
  CanonicalSnapshot(
    version: Int,
    room: String,
    compatibility: String,
    root: String,
    channels: List(Json),
  )
}

fn canonical_decoder() -> Decoder(CanonicalSnapshot) {
  use version <- decode.field("v", decode.int)
  use room <- decode.field("room", decode.string)
  use compatibility <- decode.field("compatibility", decode.string)
  use root <- decode.field("root", decode.string)
  use channels <- decode.field(
    "channels",
    decode.list(wire.json_value_decoder()),
  )
  decode.success(CanonicalSnapshot(version, room, compatibility, root, channels))
}

// --- helpers --------------------------------------------------------------

fn entries(document: Document) -> List(ChannelEntry) {
  descriptors(document)
  |> list.filter_map(fn(descriptor) {
    case dict.get(document.states, descriptor.address) {
      Ok(state) -> Ok(ChannelEntry(descriptor, channel.snapshot(state)))
      Error(_) -> Error(Nil)
    }
  })
}

/// The initializer that builds an empty channel that can receive this snapshot.
/// An OR-map carries its value mode in the snapshot, so a merge can refuse a
/// mode mismatch, and it does not load the data into the wrong kernel.
fn init_for(snapshot: Snapshot) -> Result(ChannelInit, P2pError) {
  case snapshot {
    channel.PnCounterSnapshot(_) -> Ok(channel.InitPnCounter)
    channel.OrMapSnapshot(mode, _) -> Ok(channel.InitOrMap(mode))
    channel.OrSetSnapshot(_) -> Ok(channel.InitOrSet)
    channel.GSetSnapshot(_) -> Ok(channel.InitGSet)
    channel.TwoPSetSnapshot(_) -> Ok(channel.InitTwoPSet)
    channel.SequenceSummary(_) -> Ok(channel.InitSequence)
    channel.TextSummary(_) -> Ok(channel.InitText)
    other -> Error(p2p.UnsupportedChannel(channel.snapshot_type(other)))
  }
}

fn eligible_type(raw: String, from: String) -> Result(ChannelType, P2pError) {
  case channel.string_to_type(raw) {
    Error(_) -> Error(rejected(from, "unknown channel type " <> raw))
    Ok(channel_type) -> p2p.validate(channel_type)
  }
}

fn check_address(address: String, from: String) -> Result(String, P2pError) {
  crdt_wire.address_creator(address)
  |> result.replace_error(rejected(from, "invalid channel address " <> address))
}

fn check_capacity(document: Document) -> Result(Nil, P2pError) {
  case dict.size(document.registry) >= document.config.limits.channels {
    False -> Ok(Nil)
    True ->
      Error(rejected(
        document.config.replica,
        "document already holds its limit of "
          <> int.to_string(document.config.limits.channels)
          <> " channels",
      ))
  }
}

/// Refuse an oversize snapshot by its byte length, before the module parses it.
/// A caller that gives the module a hostile file must not be able to run the
/// parser on that file first. `decode_envelope` puts the same check in front of
/// an envelope.
fn check_snapshot_size(
  document: Document,
  raw: String,
) -> Result(Nil, P2pError) {
  let bytes = bit_array.byte_size(<<raw:utf8>>)
  let limit = document.config.limits.snapshot_bytes
  case bytes > limit {
    True -> Error(p2p.SnapshotTooLarge(bytes, limit))
    False -> Ok(Nil)
  }
}

fn empty_recent() -> Recent {
  Recent(seen: dict.new(), queue: fifo_new())
}

/// Record an accepted message id, and remove the oldest id when the window is
/// full. An id that is already in the window does not enter the queue a second
/// time. The dictionary and the FIFO thus hold exactly the same set.
fn remember(document: Document, id: MessageId) -> Recent {
  let limit = document.config.limits.recent_message_ids
  let recent = document.recent
  case limit <= 0, dict.has_key(recent.seen, id) {
    True, _ -> empty_recent()
    False, True -> recent
    False, False ->
      Recent(
        seen: dict.insert(recent.seen, id, Nil),
        queue: fifo_push(recent.queue, id),
      )
      |> evict(limit)
  }
}

fn evict(recent: Recent, limit: Int) -> Recent {
  case dict.size(recent.seen) > limit {
    False -> recent
    True ->
      case fifo_pop(recent.queue) {
        Error(_) -> recent
        Ok(#(oldest, queue)) ->
          evict(
            Recent(seen: dict.delete(recent.seen, oldest), queue: queue),
            limit,
          )
      }
  }
}

fn tag(
  address: String,
  events: List(ChannelEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, event) })
}

fn combine(left: Outcome, right: Outcome) -> Outcome {
  Outcome(
    broadcast: list.append(left.broadcast, right.broadcast),
    reply: list.append(left.reply, right.reply),
    created: list.append(left.created, right.created),
    events: list.append(left.events, right.events),
  )
}

fn channel_error_detail(error: channel.ChannelError) -> String {
  case error {
    channel.UnsupportedP2p(detail) -> detail
    channel.CorruptRemoteOperation(detail) -> detail
    channel.UnexpectedAck(detail) -> detail
    channel.WrongChannelType(detail) -> detail
  }
}

fn rejected(from: String, detail: String) -> P2pError {
  p2p.InvalidEnvelope(from, detail)
}
