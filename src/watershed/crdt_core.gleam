//// The pure, target-independent CRDT document: identity, a grow-only
//// channel registry, ack-free local edits, remote merges, canonical
//// snapshots, and digests.
////
//// Nothing here performs an effect. Every transition takes a `Document`
//// and returns a new one plus an `Outcome` describing the protocol
//// messages a transport should send and the channel events a subscriber
//// should see. No sockets, timers, browser APIs, or actors — and none of
//// the server-backed lifecycle either: this module never calls
//// `runtime_core.handle_sequenced`, any `ack_local`, summary upload, or
//// membership path, because a CRDT document has no sequencer.
////
//// Every entry point that consumes remote data is a trust boundary.
//// Malformed input returns a typed `p2p.P2pError` and leaves the document
//// exactly as it was; there is no partial application and no panic. A
//// rejected `state` message mutates nothing, not even the channels that
//// decoded cleanly before the bad one.
////
//// Snapshots come in two shapes on purpose. `canonical_json` is the full
//// CRDT state — that is what an import has to reconstruct — and the
//// lattice encodings embed each replica's own authoring cursor (the id it
//// stamps writes with and the counter it stamps them from) alongside the
//// shared causal state. Hashing that directly would make the digest
//// replica-local, so `digest` hashes `digest_canonical_json` instead: the
//// same document with those authoring cursors projected out and every
//// merge-relevant field — causal tags, tombstones, version vectors, LWW
//// timestamps and their replica-id tie-break — left intact. Two replicas
//// that hold the same logical and causal state therefore share a digest,
//// and two that differ by so much as one tombstone do not.
////
//// The projection is also written out by `canonical_json`, not by
//// `gleam/json`, because a digest is compared between peers that may not
//// share a compile target: `gleam/json` and `gleam/string` order and
//// spell JSON differently on Erlang and JavaScript, and a browser replica
//// that hashes the same state differently from a BEAM one would ask it
//// for repair forever. Every ordering the lattice encodings leave to a
//// dictionary — object keys, set-shaped arrays, sequence `forwardings` —
//// is settled here in UTF-8 byte order before hashing.

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
  type ChannelEvent, type ChannelInit, type ChannelOp, type ChannelState,
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

/// Everything a replica needs to agree with its peers about what document
/// it is in. `replica` is the collision-resistant CRDT authorship identity
/// and `session` distinguishes two connections of the same installation —
/// a peer claiming our `replica` under a different `session` is a
/// `ReplicaCollision`, not a peer.
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
    /// Stamps both channel addresses and outbound message IDs, so no local
    /// message or channel can ever reuse another's identity.
    counter: Int,
    registry: Dict(String, ChannelDescriptor),
    states: Dict(String, ChannelState),
    /// Deltas that named an address before its descriptor arrived, oldest
    /// first, bounded by `limits.buffered_deltas`.
    buffered: Fifo(BufferedDelta),
    /// Recently accepted message IDs, bounded by
    /// `limits.recent_message_ids`. Suppression is an optimization only:
    /// re-merging a delta is a no-op by CRDT law.
    recent: Recent,
  )
}

type BufferedDelta {
  BufferedDelta(
    id: MessageId,
    address: String,
    channel_type: ChannelType,
    op: ChannelOp,
  )
}

/// The bounded duplicate-suppression window: a `Dict` for membership and a
/// `Fifo` for oldest-first eviction.
///
/// A plain list cost a linear scan per lookup *and* a linear copy per
/// insert at the 4,096 default, on the hot path of every accepted message.
/// The dict answers `seen` without walking, and the dict and the queue
/// hold exactly the same ids — an id already in the dict is never queued
/// twice — so eviction can never drop membership a live entry still needs.
type Recent {
  Recent(seen: Dict(MessageId, Nil), queue: Fifo(MessageId))
}

/// The standard two-list amortized-constant queue with a size counter,
/// living here because `gleam/deque` is no longer in the stdlib and this
/// module is its only user. Pushes land on `back`; pops take from `front`,
/// refilled by reversing `back` when it runs out.
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

/// What a transition asks its transport to do next, plus what changed.
/// `broadcast` goes to every peer, `reply` goes only to the peer whose
/// message produced it. Fan-out of a received message is the transport's
/// decision, so a received message never populates `broadcast`.
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

/// Start a document at the configured empty root. Every peer runs this,
/// including the first one in an empty room: the root is derived from
/// `Config`, never learned from a peer, so two replicas that agree on the
/// config agree on the root without exchanging a message.
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

/// Every registered descriptor, in canonical address order — UTF-8 byte
/// order, which is the same on both targets, unlike `string.compare`.
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

/// How many message IDs the duplicate-suppression window is holding, never
/// above `limits.recent_message_ids`.
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

/// The channel type at an address, refusing to name a channel whose kernel
/// cannot run without a sequencer.
pub fn channel_type(
  document: Document,
  address: String,
) -> Result(ChannelType, P2pError) {
  use descriptor <- result.try(descriptor(document, address))
  Ok(descriptor.channel_type)
}

/// The kernel state at an address, eligibility-checked first.
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

/// This document's whole registry and current snapshots, in canonical
/// address order.
pub fn state_message(document: Document) -> Message {
  crdt_wire.State(entries(document))
}

pub fn digest_message(document: Document) -> Message {
  crdt_wire.Digest(digest(document))
}

pub fn rejection_message(reason: String, detail: String) -> Message {
  crdt_wire.Rejected(reason, detail)
}

/// Wrap an outbound message in this document's addressing.
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

/// Register a new channel under a collision-free address derived from this
/// replica's identity, and announce it.
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

/// Author a local edit: merge it into confirmed and visible state in one
/// ack-free transition and hand back the delta to broadcast.
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
    Ok(#(state, events, op)) -> {
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
            crdt_wire.Delta(id, address, descriptor.channel_type, op),
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

/// Decode and apply one encoded envelope. The size, protocol, and shape
/// checks all run before any state is touched.
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

/// Apply one envelope. Callers that build an `Envelope` directly (a relay
/// replaying its own log, a test) get the same validation as one that
/// arrived over the wire: this re-checks descriptors and channel types
/// rather than trusting the decoder to have run.
///
/// A delta's message ID is deliberately not required to name the sender:
/// a mesh peer and a relay both forward deltas they did not author, and
/// the ID identifies the *author's* message so duplicate suppression
/// still works after a message takes two routes.
pub fn receive(
  document: Document,
  envelope: Envelope,
) -> Result(#(Document, Outcome), P2pError) {
  received(document, envelope, None)
}

/// `receive`, told the canonical digest this document already has.
///
/// `Digest` is the one message whose handling reads the local digest, and
/// computing it canonicalizes and hashes the whole document. A transport
/// that heartbeats — every 250ms, to every peer, in both directions —
/// pays that per message for a document that has not moved since the last
/// one. A caller holding a digest cache passes it here; every other
/// message is `receive` exactly, and the digest is not computed at all.
///
/// `local` must be `digest(document)` for *this* document. A stale one
/// would answer an anti-entropy comparison against a state this replica
/// no longer holds — suppressing a repair it owes, or asking for one it
/// does not — so a cache that feeds this has to be keyed on the document
/// itself rather than invalidated by hand.
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
    // Our own message, fanned back to us. Merging it is a no-op by CRDT
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
    crdt_wire.Delta(id, address, channel_type, op) ->
      apply_delta(document, from, id, address, channel_type, op)
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
  op: ChannelOp,
) -> Result(#(Document, Outcome), P2pError) {
  use _ <- result.try(check_address(address, from))
  use _ <- result.try(p2p.validate(channel_type))
  case seen(document, id) {
    True -> Ok(#(document, empty_outcome()))
    False ->
      case dict.get(document.registry, address) {
        Error(_) -> Ok(buffer_delta(document, id, address, channel_type, op))
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
              use #(document, events) <- result.try(merge_op(
                document,
                from,
                address,
                op,
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

fn merge_op(
  document: Document,
  from: String,
  address: String,
  op: ChannelOp,
) -> Result(#(Document, List(#(String, ChannelEvent))), P2pError) {
  use state <- result.try(channel_state(document, address))
  case channel.apply_p2p_remote(state, op) {
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

/// Queue a delta whose channel has not been announced yet.
///
/// The buffer is a bounded FIFO that evicts its *oldest* entry when full,
/// rather than rejecting the newest arrival. Rejecting was a wedge: an
/// orphan delta for a channel that is never announced — a forged address,
/// a peer that left before it announced — occupies its slot forever, so a
/// full buffer would refuse every legitimate later delta for the rest of
/// the document's life. Dropping the oldest bounds the same memory without
/// that failure mode, and costs nothing in correctness: a dropped delta is
/// one whose descriptor never arrived, and any peer still holding that
/// channel carries the same edit in its next `state` transfer.
///
/// The message ID is deliberately *not* remembered here. It is remembered
/// when the delta is actually applied, so a delta that was evicted, or
/// discarded at flush time, is not suppressed as a duplicate when the
/// sender re-sends it after announcing the channel.
fn buffer_delta(
  document: Document,
  id: MessageId,
  address: String,
  channel_type: ChannelType,
  op: ChannelOp,
) -> #(Document, Outcome) {
  let limit = document.config.limits.buffered_deltas
  case limit <= 0 {
    True -> #(document, empty_outcome())
    False -> {
      let queued =
        fifo_push(
          document.buffered,
          BufferedDelta(id, address, channel_type, op),
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

/// Merge announced or transferred channels. All-or-nothing: a bad entry
/// rejects the whole message, and because every intermediate document is a
/// fresh value the caller keeps the one it started with.
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

/// Apply the deltas that were waiting on this address, oldest first,
/// keeping only the ones that can possibly belong to the channel that just
/// arrived.
///
/// Partitioning on the address alone was a denial of service. A forged or
/// stale delta can name an unannounced address under the wrong channel
/// type; merging it into the announced kernel fails, and because an
/// announcement is all-or-nothing that failure rejected the genuine
/// `channel` message *and* left the poison in the buffer, so every later
/// announcement and every later `state` transfer touching that address
/// failed the same way, forever. A buffered delta whose declared type
/// disagrees with the descriptor can never be applied to it, so it is
/// discarded, and one that still fails to merge is dropped rather than
/// propagated: it was accepted speculatively from a peer that is not the
/// announcer, and it must not be able to invalidate the announcement.
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
    case merge_op(document, from, address, buffered.op) {
      Error(_) -> acc
      Ok(#(document, next)) -> #(
        Document(..document, recent: remember(document, buffered.id)),
        list.append(events, next),
      )
    }
  })
}

// --- canonical snapshots and digests --------------------------------------

/// The document as canonical JSON: fixed field order, channels sorted by
/// address, each channel encoded by its own snapshot codec. Two replicas
/// that reached the same value by different delivery orders produce the
/// same bytes.
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

/// The digest projection: `canonical_json` with every channel state reduced
/// to the part two replicas holding the same logical *and* causal state
/// must agree on.
///
/// The only things removed are each replica's authoring cursors — the id it
/// stamps its own writes with and the counter it stamps them from. Causal
/// metadata, tombstones, pruning and version vectors, remove bounds, and
/// LWW timestamps with their replica-id tie-break all survive, so this is
/// a comparison of state, not of values: a peer that has seen a removal
/// its neighbour has not still fails the comparison and gets repaired.
///
/// The bytes come from `canonical_json`, not from `gleam/json`: object
/// keys are emitted in UTF-8 byte order, set-shaped arrays are ordered by
/// their canonical bytes, and every number has one spelling — so neither a
/// dictionary's iteration order nor the compile target can move a byte.
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

/// SHA-256 of `digest_canonical_json`, lowercase hex. Equal for two
/// replicas that reached the same state by any delivery order, on either
/// compile target.
pub fn digest(document: Document) -> String {
  sha256.hex(digest_canonical_json(document))
}

/// Built here rather than through `crdt_wire.encode_descriptor`: the
/// digest is a projection of state, not a wire message, and it should not
/// move because an envelope field was renamed.
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

/// Strip the replica-local authoring cursors from one self-describing
/// lattice envelope.
///
/// Dispatch is on the envelope's own `type` tag rather than on a field
/// path, so the same function handles a channel snapshot and the CRDTs an
/// OR-map nests inside it as *stringified* JSON. Anything unrecognised is
/// returned untouched: an unknown encoding is compared in full rather than
/// silently weakened. `lww_register` is deliberately in that group — its
/// `replica_id` is the tie-break half of a timestamp, not an authoring
/// cursor, and dropping it would let two genuinely different winners hash
/// alike.
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

/// An OR-map's values: an array of `{key, crdt}` pairs whose `crdt` is a
/// nested CRDT envelope carried as a string. Project each one, then order
/// the array, because it comes from a dictionary and a dictionary's order
/// is not part of the state.
fn or_map_values(value: JsonValue) -> JsonValue {
  case value {
    json_ot.VArray(items) ->
      json_ot.VArray(list.map(items, map_member(_, "crdt", inner)))
      |> ordered
    other -> other
  }
}

/// Project a CRDT envelope that is carried as a JSON string inside another
/// one, re-stringifying it canonically so the shape is preserved. A string
/// that does not parse as JSON is left exactly as it is.
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
        _ -> ""
      }
    _ -> ""
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

/// Order a set-shaped array by its canonical bytes. Only used on fields
/// the CRDT itself defines as a set or a map, never on a sequence's
/// segments, where order *is* the state.
fn ordered(value: JsonValue) -> JsonValue {
  case value {
    json_ot.VArray(items) -> json_ot.VArray(canonical_json.sorted(items))
    other -> other
  }
}

/// Merge an exported snapshot back in. Size, room, protocol, compatibility,
/// and root are checked before a single channel is touched, and the merge
/// is a join: local channels and local edits survive it.
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

/// The initializer that reconstructs an empty channel able to receive this
/// snapshot. OR-map carries its value mode in the snapshot, so a merge can
/// reject a mode mismatch instead of loading into the wrong kernel.
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
  case channel.type_from_string(raw) {
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

/// Refuse an oversize snapshot on its byte length, before it is parsed.
/// A caller that hands us a hostile file must not be able to spend our
/// parser on it first; this is the same guard `decode_envelope` puts in
/// front of an envelope.
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

/// Record an accepted message ID, evicting the oldest once the window is
/// full. An ID already in the window is not queued a second time, which is
/// what keeps the dictionary and the FIFO holding exactly the same set.
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
    channel.CorruptRemoteOp(detail) -> detail
    channel.UnexpectedAck(detail) -> detail
    channel.WrongChannelType(detail) -> detail
  }
}

fn rejected(from: String, detail: String) -> P2pError {
  p2p.InvalidEnvelope(from, detail)
}
