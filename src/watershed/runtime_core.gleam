//// Pure per-connection state machine, driven by the runtime actor.
////
//// This module owns the client half of the sequencing discipline of spillway.
//// The CSN increases on each connection and never repeats. The RSN is the last
//// sequence number that the client saw. The SN removes a duplicate. The acks
//// match in FIFO order. The local state is optimistic, for an attached channel
//// and for a detached one.
////
//// The kernel state, the operations, and the events of the map, the counter,
//// the OR-map, the registers, and the claims all pass through the closed sums
//// in `watershed/channel`. The sequencing discipline itself does not know the
//// kernels.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

import spillway/message.{type ConnectedMessage}
import spillway/types.{type SequencedDocumentMessage}

import watershed/channel.{
  type ChannelEvent, type ChannelState, type Resolution, type Snapshot,
  SequencedMeta,
}
import watershed/claims_kernel
import watershed/client_id
import watershed/counter_kernel
import watershed/directory_kernel
import watershed/g_set_kernel
import watershed/handle
import watershed/json_ot
import watershed/json_ot_kernel
import watershed/map_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/ordered_collection_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/rich_text
import watershed/rich_text_kernel
import watershed/sequence_kernel
import watershed/summary_policy.{type Policy}
import watershed/task_manager_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel
import watershed/wire
import watershed/wire/op as wire_op
import watershed/wire/summary_blob.{type SummaryBlob}

const root_address = "root"

/// Where the core reads its operations from now. A replay reads a complete,
/// ordered log, so it needs none of the protections that guard the live lane.
/// The position is one value, and not a flag, because the two positions name
/// two different behaviours.
pub type IngestPosition {
  /// The core folds historical messages at a past sequence point.
  Replaying
  /// The core reads the live lane at the newest sequence point.
  Live
}

pub type Core {
  Core(
    client_id: String,
    channels: Dict(String, ChannelState),
    channel_order: List(String),
    detached: Dict(String, ChannelState),
    next_client_sequence_number: Int,
    last_seen_sequence_number: Int,
    in_flight: List(InFlight),
    out_of_order: List(SequencedDocumentMessage),
    /// The connected roster, as the integer ids that the kernels use to
    /// tie-break. The `initialClients` field of the handshake fills it, and the
    /// sequenced `"join"` and `"leave"` system messages maintain it. Every
    /// replica thus derives the same membership at the same sequence point.
    ///
    /// The quorum of a consensus kernel comes from this roster. `pact_map`
    /// freezes a signoff list from it at the sequence point, and it accepts
    /// only after that list becomes empty. A roster that reports too few
    /// clients thus produces a pact that accepts, and the missing members never
    /// agreed.
    members: Set(Int),
    /// The roster that the current handshake reported. The core moves it into
    /// `members` when the replay completes.
    ///
    /// The core keeps it separate, and it does not apply it immediately,
    /// because that roster describes the room *now*, and a replay is about the
    /// room at an earlier time. To apply it at the hand-off is still correct.
    /// After the log ends, the client is live, and the handshake is a better
    /// record of the room than a checkpoint with whatever history the server
    /// served.
    live_members: Set(Int),
    /// The value is `True` while the core replays the historical messages, and
    /// `False` after the core is live.
    ///
    /// This flag controls the protections in `quorum_of`. Those protections
    /// exist for one hazard, and that hazard occurs on the live path only: a
    /// `join` message that the client loses, or that arrives after the
    /// operation that follows it. A replay reads a complete, ordered log, so
    /// nothing can be absent. To apply those protections during a replay is
    /// incorrect. To add *self* to the quorum of an operation that sequenced
    /// before this client joined puts the client in a room that it was not in.
    ingest: IngestPosition,
    /// The sequence number of the newest checkpoint that this client knows
    /// about. That checkpoint is the blob that the client started from, a
    /// summarize operation that it saw after that, or one that it wrote itself.
    /// The value is zero on a document that no client has summarized.
    ///
    /// The value is an upper bound, and not the exact capture point. A
    /// summarize operation that the client sees reports the sequence number of
    /// the *operation*, which is at or after the point at which the writer
    /// captured the contents of the blob. The two numbers differ by the traffic
    /// that the room wrote during the upload. That difference makes the policy
    /// a little slower, and it never makes the policy summarize two times,
    /// which is the safe direction. `summary_from_blob` is the exception. A
    /// client that loads a blob takes the number of that blob, because there
    /// the seeded state matters, and not the pointer to it.
    ///
    /// The correctness of the document does not depend on this value. It exists
    /// so that `wants_summary` can measure the drift after the last checkpoint
    /// without a request to the server.
    last_summary_sequence_number: Int,
    /// A buffer for each channel, which holds the *owed* follow-up operations
    /// that a kernel released while it applied a sequenced operation. One
    /// example is a consensus `Accept` operation in reaction to a `Set`
    /// operation from a peer. `collect_released_operations` empties this buffer
    /// after each sequenced batch. That function gives each operation a new CSN
    /// and an in-flight entry, and it gives the operation to the actor loop to
    /// submit. The buffer works for every kernel: any branch of
    /// `channel.apply_remote` can add to it, by returning owed operations.
    owed: Dict(String, List(channel.ChannelOperation)),
  )
}

pub type InFlight {
  InFlightOperation(
    client_id: String,
    client_sequence_number: Int,
    address: String,
    operation: channel.ChannelOperation,
    meta: channel.LocalOperationMeta,
  )
  InFlightAttach(
    client_id: String,
    client_sequence_number: Int,
    address: String,
    snapshot: Snapshot,
  )
}

pub type CoreError {
  AckMismatch(detail: String)
  BadOperationContents(sequence_number: Int)
  HistoryGap(detail: String)
  UnknownChannel(address: String, sequence_number: Int)
  DuplicateAttach(address: String, sequence_number: Int)
  /// A local edit used an operation of one channel type on a channel of
  /// another type, for example a `set` on a counter. This is incorrect use of
  /// the API, and the caller can retry. The document is not corrupt.
  WrongChannelType(
    address: String,
    expected: channel.ChannelType,
    actual: channel.ChannelType,
  )
  OrMapModeMismatch(address: String, detail: String)
  TaskNotAssigned(address: String, task_id: String)
  /// The kernel refused a directory edit, because the path is unknown or the
  /// subdirectory name is invalid. This is incorrect use of the API, and the
  /// caller can retry. The document is not corrupt.
  DirectoryOperationFailed(address: String, detail: String)
  SequenceOperationFailed(address: String, detail: String)
  /// The kernel refused a local text edit, because the insert index is out of
  /// bounds, or the delete range or replace range is invalid. This is
  /// incorrect use of the API, and the caller can retry. The document is not
  /// corrupt. A valid empty edit never reaches this path. The kernel reports
  /// such an edit as a success that changes nothing. See `text_kernel`.
  TextOperationFailed(address: String, detail: String)
  /// A channel snapshot in the summary does not describe a channel that this
  /// client can build. The document cannot start from that summary.
  BadSummaryChannel(address: String, detail: String)
}

pub type Bootstrapped {
  Complete(core: Core)
  MissingPrefix(core: Core, checkpoint: Int, from: Int, to: Int)
}

pub type Ingested {
  Ingested(
    events: List(#(String, ChannelEvent)),
    resolutions: List(#(String, Resolution)),
    request_operations_from: Option(Int),
    /// The operations that a one-operation-in-flight kernel, which is json0,
    /// released onto the wire while the runtime acked its own operation. The
    /// actor loop must submit them.
    outbound: List(wire.OutboundOperation),
  )
}

pub type Summary {
  Summary(
    sequence_number: Int,
    channels: List(#(String, Snapshot)),
    /// The connected roster at `sequence_number`, as kernel-side integer ids.
    ///
    /// Membership is checkpoint state, the same as a kernel snapshot, because
    /// the consensus kernels read it. A `PactMap` freezes a signoff list from
    /// it, and `TaskManager` checks the authorship of a volunteer against it.
    /// To replay an operation thus needs the roster *at the sequence point of
    /// that operation*. The core can rebuild that roster only from the roster
    /// of the checkpoint, advanced by the replayed `join` and `leave` messages.
    ///
    /// An empty list is correct for a replay of a document from its start,
    /// because no client had joined at sequence number zero. For a real
    /// checkpoint the value comes from the `members` field of the version 4
    /// summary blob, which the summarizing client captured with the
    /// snapshots.
    members: List(Int),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// The bootstrap seed that a fetched summary blob describes.
///
/// The load point comes from the blob, and from the blob *only*. This function
/// thus takes no `SummaryContext` value. The context of the server reports the
/// sequence number of the summarize operation, which the server assigned when
/// it sequenced that operation, after the writer captured and uploaded the
/// blob. Every operation that a peer got sequenced in that interval falls
/// between the two numbers. To seed from the context thus claims that the
/// seeded state is newer than it is, and no client replays the operations
/// between the two numbers. The served history starts after the number of the
/// context, it appears contiguous, and nothing reports a gap.
///
/// To seed from the number of the blob cannot lose those operations. When the
/// two numbers agree, the result is the same. When they differ, the interval
/// appears as a missing prefix, and `resume_bootstrap` reads it from storage.
/// The context still locates the blob, because `handle` is the tree SHA. It
/// does not describe the contents of that blob.
pub fn summary_from_blob(blob: SummaryBlob) -> Summary {
  Summary(
    sequence_number: blob.sequence_number,
    channels: list.map(blob.channels, fn(ch) { #(ch.address, ch.snapshot) }),
    members: blob.members,
  )
}

pub fn bootstrap(
  connected: ConnectedMessage,
  summary summary: Option(Summary),
) -> Result(Bootstrapped, CoreError) {
  let Summary(
    sequence_number: last_seen,
    channels: seeded,
    members: seed_members,
  ) =
    option.unwrap(
      summary,
      Summary(sequence_number: 0, channels: [], members: []),
    )
  use #(channels, channel_order) <- result.try(seed_channels(
    seeded,
    connected.client_id,
  ))

  let core =
    Core(
      client_id: connected.client_id,
      channels: channels,
      channel_order: channel_order,
      detached: dict.new(),
      next_client_sequence_number: 1,
      last_seen_sequence_number: last_seen,
      // The blob we loaded *is* the newest checkpoint we know of; a document
      // with no summary has none, and every operation in its log is
      // outstanding.
      last_summary_sequence_number: last_seen,
      in_flight: [],
      out_of_order: [],
      // Seeded from the checkpoint, **not** from the handshake's roster, and
      // advanced by the `join`/`leave` messages in the replay itself. Seeding
      // from `initialClients` — the room as it is *now* — time-shifts every
      // historical operation's membership forward, so a client replaying a
      // settled consensus proposal recomputes its quorum against a room that
      // did not exist when the proposal was made, and writes itself into it.
      members: set.from_list(seed_members),
      live_members: roster_of(connected),
      // Suppresses the live-path defences in `quorum_of` while history is
      // being reconstructed. See `ingest` on `Core`.
      ingest: Replaying,
      owed: dict.new(),
    )

  use core <- result.try(replay(core, connected.initial_messages))
  let checkpoint =
    option.unwrap(
      connected.checkpoint_sequence_number,
      core.last_seen_sequence_number,
    )
  Ok(settle_bootstrap(core, checkpoint))
}

pub fn resume_bootstrap(
  core: Core,
  checkpoint checkpoint: Int,
  deltas deltas: List(SequencedDocumentMessage),
) -> Result(Bootstrapped, CoreError) {
  let before = core.last_seen_sequence_number
  use core <- result.try(replay(core, deltas))
  case core.out_of_order != [] && core.last_seen_sequence_number == before {
    True ->
      Error(HistoryGap(
        "history catch-up made no progress past sequence number "
        <> int.to_string(before)
        <> " (server storage is missing the range)",
      ))
    False -> Ok(settle_bootstrap(core, checkpoint))
  }
}

/// Fold the historical messages into the core, with `ingest` at `Replaying` for
/// the length of the fold.
///
/// The position moves here, and not across a whole bootstrap, because
/// `Replaying` turns off the safety protections. The reconnect path reaches
/// `Ready` by a route that never passes through `settle_bootstrap`. A position
/// that a hand-off had to reset would thus stay at `Replaying` on that route,
/// and it would disable `quorum_of` for the rest of the session. To move the
/// position around the fold only makes that fault impossible: nothing outside
/// a replay can observe `Replaying`.
fn replay(
  core: Core,
  messages: List(SequencedDocumentMessage),
) -> Result(Core, CoreError) {
  use core <- result.map(
    list.try_fold(messages, Core(..core, ingest: Replaying), fn(core, msg) {
      handle_sequenced(core, msg)
      |> result.map(fn(outcome) { outcome.0 })
    }),
  )
  Core(..core, ingest: Live)
}

/// The hand-off from the replay to the live traffic.
///
/// `Complete` is the only outcome that ends a bootstrap. `MissingPrefix` asks
/// for another page, and it returns through `resume_bootstrap`. This function
/// is thus the one place that can take the roster of the handshake, exactly one
/// time, whatever number of pages the history needed.
///
/// The reconstruction before this point is exact in both routes. From sequence
/// number zero, the `join` and `leave` messages build the roster from nothing.
/// From a checkpoint, they advance the roster that the blob recorded. This
/// function is thus not a correction. It is the hand-off itself. A replay
/// reasons about the room at each historical sequence point, and after this
/// point only the current sequence point matters.
fn settle_bootstrap(core: Core, checkpoint: Int) -> Bootstrapped {
  case core.out_of_order {
    [] ->
      Complete(
        Core(
          ..core,
          last_seen_sequence_number: int.max(
            core.last_seen_sequence_number,
            checkpoint,
          ),
          members: core.live_members,
        ),
      )
    [head, ..] ->
      MissingPrefix(
        core: core,
        checkpoint: checkpoint,
        from: core.last_seen_sequence_number,
        to: head.sequence_number - 1,
      )
  }
}

/// The roster to record in a summary, as kernel-side integer ids.
///
/// `summarize` runs on a synchronized client only. At that moment
/// `core.members` *is* the roster at `core.last_seen_sequence_number`, which is
/// the sequence number that the blob records. That pair makes the checkpoint
/// roster meaningful, and it is the reason that the client captures the two
/// values together.
pub fn summary_members(core: Core) -> List(Int) {
  core.members |> set.to_list |> list.sort(by: int.compare)
}

pub fn summary_channels(core: Core) -> List(#(String, Snapshot)) {
  list.filter_map(core.channel_order, fn(address) {
    case dict.get(core.channels, address) {
      Ok(state) -> Ok(#(address, channel.snapshot(state)))
      Error(_) -> Error(Nil)
    }
  })
}

pub fn is_synced(core: Core) -> Bool {
  core.in_flight == []
}

/// How far the document moved past the newest checkpoint that this client knows
/// about. The automatic policy compares this number with its threshold, and a
/// diagnostic view can show it. On a document that no client has summarized,
/// this number is the full length of the log, which is the cost that every
/// client that joins pays.
///
/// The count is in **sequenced messages**, and not in edits. A server sequences
/// a batch of submitted operations as one message, so a burst of writes moves
/// this number much less than the number of writes. Messages are the correct
/// unit, because a client that joins replays messages.
pub fn operations_since_summary(core: Core) -> Int {
  int.max(0, core.last_seen_sequence_number - core.last_summary_sequence_number)
}

/// Whether this client must summarize now, under `policy`.
///
/// This test is stricter than `is_synced`, and that is deliberate. `is_synced`
/// reports only that there is no local edit without an ack. A summary is a
/// claim about the confirmed state at one sequence point, so every condition
/// that puts the core away from that point refuses the summary:
///
///   - `Replaying`: the core is at a historical position, and the roster that
///     it would record is the room at the checkpoint, and not the room now.
///   - `in_flight`: there is a local edit that the blob would omit, and it
///     would report nothing. `summarize` refuses in this state, so the policy
///     must not ask.
///   - `out_of_order`: a `requestOps` round is open, so the confirmed state is
///     a prefix of the state that the server already sequenced.
pub fn wants_summary(core: Core, policy: Policy) -> Bool {
  core.ingest == Live
  && core.in_flight == []
  && core.out_of_order == []
  && operations_since_summary(core) >= summary_policy.policy_threshold(policy)
}

/// How long this client waits before it acts on `wants_summary`.
///
/// The delay comes from the client id, and not from a random source. Every
/// client in the room crosses the threshold on the same operation. A derived
/// delay thus spreads the clients deterministically. A test can reproduce it,
/// and neither target needs a random number generator. The first summary that
/// sequences advances the `last_summary_sequence_number` value of every other
/// client, so the rest of the room checks again and stops.
///
/// The multiplication does necessary work. A server gives out the client ids in
/// sequence, so `id % window` puts a whole room within a few milliseconds of
/// each other. That result is deterministic, and it spreads nothing. To scramble
/// the id first turns two adjacent ids into two distant delays, which is the
/// purpose of the window. The `% 100_003` operation keeps the product inside the
/// range of integers that JavaScript represents exactly.
pub fn summary_jitter_milliseconds(core: Core, policy: Policy) -> Int {
  case summary_policy.policy_jitter_milliseconds(policy) {
    window if window <= 0 -> 0
    window -> {
      let id = int.absolute_value(client_id_to_int(core.client_id)) % 100_003
      id * 2_654_435_761 % window
    }
  }
}

pub fn build_summarize(
  core: Core,
  handle handle: String,
  message message: String,
  head head: String,
) -> #(Core, wire.OutboundOperation) {
  let client_sequence_number = core.next_client_sequence_number
  let outbound =
    wire_op.outbound_summarize_operation(
      client_sequence_number: client_sequence_number,
      reference_sequence_number: core.last_seen_sequence_number,
      handle: handle,
      message: message,
      parents: [],
      head: head,
    )
  // Our own checkpoint moves here rather than when the operation is echoed
  // back: a summarize operation carries no ack and no in-flight entry, so
  // waiting for the echo would leave the policy re-arming on every operation in
  // between.
  #(
    Core(
      ..core,
      next_client_sequence_number: client_sequence_number + 1,
      last_summary_sequence_number: core.last_seen_sequence_number,
    ),
    outbound,
  )
}

fn seed_channels(
  seeded: List(#(String, Snapshot)),
  replica replica: String,
) -> Result(#(Dict(String, ChannelState), List(String)), CoreError) {
  use #(channels, channel_order) <- result.try(
    list.try_fold(seeded, #(dict.new(), []), fn(acc, entry) {
      let #(channels, channel_order) = acc
      let #(address, snapshot) = entry
      use state <- result.try(
        channel.from_snapshot(snapshot, replica: replica)
        |> result.map_error(fn(detail) {
          BadSummaryChannel(address: address, detail: detail)
        }),
      )
      Ok(#(
        dict.insert(channels, address, state),
        list.unique(list.append(channel_order, [address])),
      ))
    }),
  )

  case dict.has_key(channels, root_address) {
    True -> Ok(#(channels, channel_order))
    False ->
      Ok(
        #(
          dict.insert(
            channels,
            root_address,
            channel.new(channel.InitMap, replica: replica),
          ),
          [root_address, ..channel_order],
        ),
      )
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

/// Enter the reconnect state. Keep the roster that the core holds, and return
/// to the replaying state.
///
/// The function does **not** replace the roster with the roster of the new
/// handshake yet, and that is deliberate. `resume_bootstrap` replays the
/// operations that sequenced while the client was absent, and the core must
/// judge those operations against the room at *that* time. That room is the
/// last roster that the client knew, advanced by the `join` and `leave`
/// messages inside the gap that it replays. To take `initialClients` here would
/// apply the room after the reconnect to the operations from before the
/// reconnect. That is the same shift in time that breaks a cold join, over a
/// shorter interval. `settle_bootstrap` takes the new roster after the gap
/// closes.
pub fn adopt_reconnect(core: Core, connected: ConnectedMessage) -> Core {
  // `members` is left exactly as it was: it is the roster at
  // `last_seen_sequence_number`, which is precisely where the replay about to
  // happen starts. The gap's own `join`/`leave` messages then advance it —
  // including the `leave` for the id we held before dropping and the `join` for
  // the one we were just assigned — so the roster arrives at the post-reconnect
  // room by walking the log rather than by being told the answer up front.
  //
  // The handshake's roster is not discarded, just deferred: `settle_bootstrap`
  // adopts `live_members` when the gap closes. That ordering is what keeps the
  // merge hazard away — nothing is unioned, so a client that left during the
  // gap cannot be resurrected, and its signoffs still drain at the sequence
  // point its `leave` actually occupies.
  Core(
    ..core,
    client_id: connected.client_id,
    live_members: roster_of(connected),
    // The gap about to be replayed is history, not live traffic, so the
    // defences in `quorum_of` must be off for it. They exist for a hazard that
    // cannot occur here — a `join` lost or reordered against the operation
    // after it — and applying them is actively wrong on this path: unioning
    // *self* into the quorum of an operation sequenced before we reconnected
    // claims a signoff for an id that did not exist when that operation was
    // made, and no other replica agrees. `go_live` clears this when the gap
    // closes.
    ingest: Replaying,
  )
}

/// The sequence number that a reconnect must send `requestOps` from. The result
/// is `None` when the handshake left nothing to catch up on.
///
/// A reconnect must ask for its own gap. `adopt_reconnect` does not replay
/// `initial_messages`, and that is deliberate. Only an inbound sequenced
/// operation can thus move `last_seen_sequence_number` up to the checkpoint of
/// the handshake, and no server sends one without a request. floodgate ignores
/// `lastSeenSequenceNumber` completely, and it removes the joining client from
/// the broadcast of the *own* join operation of that client. A client that
/// rejoins a room where no other client writes thus receives nothing at all. To
/// wait for the next edit of a peer is not a catch-up plan. It is a chance, and
/// a quiet room never gives it.
///
/// The result is `last_seen_sequence_number`, and not
/// `last_seen_sequence_number + 1`. `requestOps` excludes `from` on both
/// servers, and this value agrees with what `handle_sequenced` already asks for
/// when a live operation shows a gap.
///
/// The checkpoint is almost always ahead on a write reconnect, because floodgate
/// sequences the `join` operation of the rejoining client and reports *that*
/// operation as the checkpoint. This function thus returns `Some` also for a
/// reconnect that missed no application traffic.
pub fn catch_up_from(core: Core, checkpoint: Int) -> Option(Int) {
  case checkpoint > core.last_seen_sequence_number {
    True -> Some(core.last_seen_sequence_number)
    False -> None
  }
}

/// The hand-off from the catch-up of a reconnect to the live traffic.
///
/// This function is the equivalent of `settle_bootstrap`, for the route that
/// never passes through it. It exists so that exactly one place on this path
/// puts `ingest` back at `Live`. The replay position thus cannot outlast the
/// gap and disable `quorum_of` for the rest of the session.
pub fn go_live(core: Core) -> Core {
  Core(..core, ingest: Live)
}

/// The quorum that the core judges a sequenced operation against: the roster at
/// the sequence point of that operation, and, for a live operation only, this
/// client and the author of the operation.
///
/// The function adds those two as a protection. It does not assume that they are
/// present. A quorum without a connected client accepts too early. That was the
/// fault that this code replaced, which used a fixed `[self, author]` list and
/// never read the room. But a quorum that names a client outside the room can
/// never become empty, and the pact then never completes. This client and the
/// author are the two clients that the core knows are live: one of them is this
/// client, and the other one just had an operation sequenced. To include them
/// thus cannot stop a pact, and it covers a join message that the client lost,
/// or that arrived after the operation that follows it.
///
/// **That reasoning holds on the live path only.** A replay reads a complete,
/// ordered log, in which no join can be absent. "This client is live" is then a
/// false premise. For an operation that sequenced before this client joined,
/// the client was not in the room, and to add it to the quorum puts it in a
/// quorum that it was never part of. A settled consensus proposal then rebuilds
/// as pending on this client, and it never completes. The protections are thus
/// for the live path only.
///
/// An author of `None` is a system message, and not the client `0`. The earlier
/// code converted it to `0` and added a member that never signs off.
fn quorum_of(core: Core, author: Option(String)) -> List(Int) {
  case core.ingest {
    Replaying -> core.members |> set.to_list
    Live -> quorum_with_live_defences(core, author)
  }
}

fn quorum_with_live_defences(core: Core, author: Option(String)) -> List(Int) {
  core.members
  |> set.insert(client_id_to_int(core.client_id))
  |> fn(members) {
    case author {
      None -> members
      Some(id) -> set.insert(members, client_id_to_int(id))
    }
  }
  |> set.to_list
}

/// The connected roster that a handshake carries, as kernel-side integer ids.
/// The function adds this client, because the server builds `initialClients`
/// from the presence map of the document, and that map does not have to contain
/// the client that the server answers.
fn roster_of(connected: ConnectedMessage) -> Set(Int) {
  connected.initial_clients
  |> list.map(fn(client) { client_id_to_int(client.client_id) })
  |> set.from_list
  |> set.insert(client_id_to_int(connected.client_id))
}

pub fn resubmit(core: Core) -> #(Core, List(wire.OutboundOperation)) {
  let #(core, next_client_sequence_number, new_in_flight, outbound) =
    list.fold(
      core.in_flight,
      #(core, core.next_client_sequence_number, [], []),
      fn(acc, entry) {
        let #(core, client_sequence_number, entries, outbounds) = acc
        let #(core, next_client_sequence_number, restamped, outbound) =
          restamp_in_flight(core, entry, client_sequence_number)
        #(
          core,
          next_client_sequence_number,
          list.append(entries, restamped),
          list.append(outbounds, outbound),
        )
      },
    )

  #(
    Core(
      ..core,
      next_client_sequence_number: next_client_sequence_number,
      in_flight: new_in_flight,
    ),
    outbound,
  )
}

fn restamp_in_flight(
  core: Core,
  entry: InFlight,
  client_sequence_number: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOperation)) {
  case entry {
    InFlightOperation(
      address: address,
      operation: channel.TaskManagerOperation(operation),
      meta: meta,
      ..,
    ) ->
      restamp_task_manager(
        core,
        address,
        operation,
        meta,
        client_sequence_number,
      )
    InFlightOperation(
      address: address,
      operation: channel.DirectoryOperation(operation, message_id),
      ..,
    ) ->
      restamp_directory(
        core,
        address,
        operation,
        message_id,
        client_sequence_number,
      )
    InFlightOperation(address: address, operation: operation, meta: meta, ..) -> #(
      core,
      client_sequence_number + 1,
      [
        InFlightOperation(
          client_id: core.client_id,
          client_sequence_number: client_sequence_number,
          address: address,
          operation: operation,
          meta: meta,
        ),
      ],
      [
        wire_op.outbound_channel_operation(
          address: address,
          client_sequence_number: client_sequence_number,
          reference_sequence_number: core.last_seen_sequence_number,
          operation: operation,
        ),
      ],
    )
    InFlightAttach(address: address, snapshot: snapshot, ..) -> #(
      core,
      client_sequence_number + 1,
      [
        InFlightAttach(
          client_id: core.client_id,
          client_sequence_number: client_sequence_number,
          address: address,
          snapshot: snapshot,
        ),
      ],
      [
        wire_op.outbound_attach_operation(
          address: address,
          client_sequence_number: client_sequence_number,
          reference_sequence_number: core.last_seen_sequence_number,
          snapshot: snapshot,
        ),
      ],
    )
  }
}

fn restamp_task_manager(
  core: Core,
  address: String,
  operation: task_manager_kernel.TaskManagerOperation,
  meta: channel.LocalOperationMeta,
  client_sequence_number: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOperation)) {
  case meta, dict.get(core.channels, address) {
    channel.TaskManagerMeta(message_id), Ok(channel.TaskManagerState(kernel)) -> {
      case
        task_manager_kernel.resubmit(
          kernel,
          operation,
          message_id,
          client_sequence_number,
        )
      {
        Ok(#(kernel, Some(next_operation), Some(pending))) -> {
          let next_channel_operation =
            channel.TaskManagerOperation(next_operation)
          let next_meta = channel.TaskManagerMeta(pending.message_id)
          let core =
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            )
          #(
            core,
            client_sequence_number + 1,
            [
              InFlightOperation(
                client_id: core.client_id,
                client_sequence_number: client_sequence_number,
                address: address,
                operation: next_channel_operation,
                meta: next_meta,
              ),
            ],
            [
              wire_op.outbound_channel_operation(
                address: address,
                client_sequence_number: client_sequence_number,
                reference_sequence_number: core.last_seen_sequence_number,
                operation: next_channel_operation,
              ),
            ],
          )
        }
        Ok(#(kernel, None, None)) -> {
          let core =
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            )
          #(core, client_sequence_number, [], [])
        }
        // The kernel reports an operation without its pending record, or the
        // reverse. The runtime drops the resubmit, because it cannot stamp an
        // operation that it cannot match to an ack later. The operation was
        // never acked, so no committed data is lost.
        Ok(#(_, _, _)) -> #(core, client_sequence_number, [], [])
        // The kernel refused the resubmit. The runtime drops the operation for
        // the same reason.
        Error(_) -> #(core, client_sequence_number, [], [])
      }
    }
    // The channel is gone, or the in-flight entry carries metadata of another
    // kernel. There is nothing to stamp again.
    _, _ -> #(core, client_sequence_number, [], [])
  }
}

/// Stamp a directory operation again on a reconnect.
/// `directory_kernel.resubmit` filters the operation against the current live
/// instance of its target path. A `Some` result means that the runtime sends
/// the operation again, and the kernel can have rewritten it, because a
/// resubmit of a create adds the creator id of this client again. A `None`
/// result means that the target instance no longer exists. The runtime drops
/// the operation, and the kernel removes its pending entry.
fn restamp_directory(
  core: Core,
  address: String,
  operation: directory_kernel.DirectoryOperation,
  message_id: Int,
  client_sequence_number: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOperation)) {
  case dict.get(core.channels, address) {
    Ok(channel.DirectoryState(kernel)) -> {
      let self = client_id_to_int(core.client_id)
      let #(kernel, maybe_operation) =
        directory_kernel.resubmit(kernel, operation, message_id, self)
      let core =
        put_attached_channel(core, address, channel.DirectoryState(kernel))
      case maybe_operation {
        Some(next_operation) -> {
          let next_channel_operation =
            channel.DirectoryOperation(next_operation, message_id)
          #(
            core,
            client_sequence_number + 1,
            [
              InFlightOperation(
                client_id: core.client_id,
                client_sequence_number: client_sequence_number,
                address: address,
                operation: next_channel_operation,
                meta: channel.DirectoryMeta(message_id),
              ),
            ],
            [
              wire_op.outbound_channel_operation(
                address: address,
                client_sequence_number: client_sequence_number,
                reference_sequence_number: core.last_seen_sequence_number,
                operation: next_channel_operation,
              ),
            ],
          )
        }
        None -> #(core, client_sequence_number, [], [])
      }
    }
    // The channel is gone, or the address now names another kernel. There is
    // nothing to stamp again.
    _ -> #(core, client_sequence_number, [], [])
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn handle_sequenced(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, Ingested), CoreError) {
  let next = core.last_seen_sequence_number + 1
  case msg.sequence_number {
    sequence_number if sequence_number < next ->
      Ok(#(core, Ingested([], [], None, [])))
    sequence_number if sequence_number > next -> {
      let request = case core.out_of_order {
        [] -> Some(core.last_seen_sequence_number)
        _ -> None
      }
      let core =
        Core(..core, out_of_order: buffer_insert(core.out_of_order, msg))
      Ok(#(core, Ingested([], [], request, [])))
    }
    _ -> {
      use #(core, events, resolutions) <- result.try(apply_one(core, msg))
      use #(core, drained, drained_resolutions) <- result.try(drain_buffer(core))
      // A single-in-flight kernel (json0 or rich text) may have promoted a
      // buffered operation to the wire while acking its own operation; collect
      // and stamp those now, after every operation in this batch has been
      // applied and rebased.
      let #(core, outbound) = collect_released_operations(core)
      Ok(#(
        core,
        Ingested(
          events: list.append(events, drained),
          resolutions: list.append(resolutions, drained_resolutions),
          request_operations_from: None,
          outbound: outbound,
        ),
      ))
    }
  }
}

/// After a sequenced batch, take every follow-up operation that a channel
/// released for the actor loop to submit. The function gives each operation a
/// new CSN and an in-flight entry, so that the usual ack path reclaims it. Two
/// sources fill this list:
///
///   1. The `owed` buffer of each channel, which any branch of
///      `channel.apply_remote` can fill by returning owed operations. One
///      example is a consensus `Accept` operation.
///   2. The buffer promotion of the one-operation-in-flight kernels, which are
///      json0 and rich text. `channel.take_outbound` gives those operations.
///
/// The function returns the stamped outbound operations in channel order. In
/// each channel, the owed operations come before the operations from the kernel
/// buffer.
fn collect_released_operations(
  core: Core,
) -> #(Core, List(wire.OutboundOperation)) {
  list.fold(core.channel_order, #(core, []), fn(acc, address) {
    let #(core, outs) = acc
    let #(core, owed_outs) = drain_owed(core, address)
    let #(core, kernel_outs) = drain_kernel_outbound(core, address)
    #(core, list.append(outs, list.append(owed_outs, kernel_outs)))
  })
}

/// Take every operation from the `owed` buffer of one channel, and stamp each
/// one.
fn drain_owed(
  core: Core,
  address: String,
) -> #(Core, List(wire.OutboundOperation)) {
  case dict.get(core.owed, address) {
    Ok([_, ..] as operations) -> {
      let core = Core(..core, owed: dict.delete(core.owed, address))
      list.fold(operations, #(core, []), fn(acc, operation) {
        let #(core, outs) = acc
        let #(core, out) = stamp_outbound(core, address, operation)
        #(core, list.append(outs, [out]))
      })
    }
    _ -> #(core, [])
  }
}

/// Take the promoted buffer of a one-operation-in-flight kernel, for one
/// channel, and stamp the operation.
fn drain_kernel_outbound(
  core: Core,
  address: String,
) -> #(Core, List(wire.OutboundOperation)) {
  case dict.get(core.channels, address) {
    Error(_) -> #(core, [])
    Ok(state) ->
      case channel.take_outbound(state) {
        #(_, None) -> #(core, [])
        #(state, Some(operation)) -> {
          let core =
            Core(..core, channels: dict.insert(core.channels, address, state))
          let #(core, out) = stamp_outbound(core, address, operation)
          #(core, [out])
        }
      }
  }
}

/// Give a released operation a new CSN, record an in-flight entry so that the
/// usual ack path reclaims it, and build its outbound wire operation.
fn stamp_outbound(
  core: Core,
  address: String,
  operation: channel.ChannelOperation,
) -> #(Core, wire.OutboundOperation) {
  let client_sequence_number = core.next_client_sequence_number
  let outbound =
    wire_op.outbound_channel_operation(
      address: address,
      client_sequence_number: client_sequence_number,
      reference_sequence_number: core.last_seen_sequence_number,
      operation: operation,
    )
  let core =
    Core(
      ..core,
      next_client_sequence_number: client_sequence_number + 1,
      in_flight: list.append(core.in_flight, [
        InFlightOperation(
          client_id: core.client_id,
          client_sequence_number: client_sequence_number,
          address: address,
          operation: operation,
          meta: channel.NoMeta,
        ),
      ]),
    )
  #(core, outbound)
}

fn apply_one(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  let core = Core(..core, last_seen_sequence_number: msg.sequence_number)
  case msg.message_type {
    "op" -> handle_operation(core, msg)
    "join" -> handle_join(core, msg)
    "leave" -> handle_leave(core, msg)
    // Someone summarized. The contents are a storage handle this client has no
    // use for — it is already caught up — but the sequence number tells the
    // automatic policy that the document has a fresher checkpoint than it
    // thought, which is how a room writes one summary per crossing rather than
    // one per client. `int.max` because a summarize operation replayed out of
    // an old log must not un-summarize a document loaded from a newer blob.
    "summarize" ->
      Ok(
        #(
          Core(
            ..core,
            last_summary_sequence_number: int.max(
              core.last_summary_sequence_number,
              msg.sequence_number,
            ),
          ),
          [],
          [],
        ),
      )
    _ -> Ok(#(core, [], []))
  }
}

/// Apply a sequenced membership join, which is a `"join"` system message, by
/// adding the client that arrived to the roster. No kernel needs this message,
/// and a `"leave"` message differs there. A join only makes the quorum larger,
/// for the operations that sequence *after* it, and a pact that is already
/// pending froze its signoff list when it sequenced.
///
/// The payload of a join is an object, `{"clientId": …, "detail": {…}}`. The
/// payload of a leave is a bare string. The two system messages do not share one
/// shape.
fn handle_join(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case system_payload(msg.data, decode.at(["clientId"], decode.string)) {
    Error(Nil) -> Ok(#(core, [], []))
    Ok(joining_client_id) ->
      Ok(
        #(
          Core(
            ..core,
            members: set.insert(
              core.members,
              client_id_to_int(joining_client_id),
            ),
          ),
          [],
          [],
        ),
      )
  }
}

/// Apply a sequenced membership leave, which is a `"leave"` system message, by
/// sending the client that left to every attached channel. The server gives the
/// leave a sequence number and carries the id of that client in `data`. Every
/// replica thus settles the per-client kernel state deterministically at the
/// same `leave_sequence_number` value. That state is the queue jobs that a
/// kernel releases again, and the consensus signoffs that it removes. A channel
/// with no membership behaviour does nothing. The function ignores a malformed
/// payload, and it does not fail the whole batch.
fn handle_leave(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case system_payload(msg.data, decode.string) {
    Error(Nil) -> Ok(#(core, [], []))
    Ok(leaving_client_id) -> {
      let client_int = client_id_to_int(leaving_client_id)
      let core = Core(..core, members: set.delete(core.members, client_int))
      let #(core, events) =
        list.fold(core.channel_order, #(core, []), fn(acc, address) {
          let #(core, events) = acc
          case dict.get(core.channels, address) {
            Error(_) -> acc
            Ok(state) -> {
              let #(state, channel_events) =
                channel.on_leave(state, client_int, msg.sequence_number)
              #(
                put_attached_channel(core, address, state),
                list.append(events, tag_events(address, channel_events)),
              )
            }
          }
        })
      Ok(#(core, events, []))
    }
  }
}

/// Decode the payload of a system message. The server carries such a payload in
/// `data`, as JSON *text*, and `contents` is null on those messages. This
/// function thus parses the string, and it does not read the dynamic value. To
/// read `contents` here fails the decode against every real server, and that
/// failure reports nothing, because a malformed payload changes nothing on
/// purpose.
fn system_payload(
  data: Option(String),
  decoder: decode.Decoder(a),
) -> Result(a, Nil) {
  case data {
    None -> Error(Nil)
    Some(text) -> json.parse(text, decoder) |> result.replace_error(Nil)
  }
}

fn drain_buffer(
  core: Core,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.out_of_order {
    [head, ..rest] if head.sequence_number <= core.last_seen_sequence_number ->
      drain_buffer(Core(..core, out_of_order: rest))
    [head, ..rest]
      if head.sequence_number == core.last_seen_sequence_number + 1
    -> {
      use #(core, events, resolutions) <- result.try(apply_one(
        Core(..core, out_of_order: rest),
        head,
      ))
      use #(core, more, more_resolutions) <- result.try(drain_buffer(core))
      Ok(#(
        core,
        list.append(events, more),
        list.append(resolutions, more_resolutions),
      ))
    }
    _ -> Ok(#(core, [], []))
  }
}

fn buffer_insert(
  buffer: List(SequencedDocumentMessage),
  msg: SequencedDocumentMessage,
) -> List(SequencedDocumentMessage) {
  case buffer {
    [] -> [msg]
    [head, ..rest] ->
      case int.compare(msg.sequence_number, head.sequence_number) {
        order.Lt -> [msg, ..buffer]
        order.Eq -> buffer
        order.Gt -> [head, ..buffer_insert(rest, msg)]
      }
  }
}

fn handle_operation(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case wire_op.decode_operation_contents(msg.contents) {
    Error(_) -> Error(BadOperationContents(msg.sequence_number))
    Ok(wire_op.AttachOperation(address, snapshot)) ->
      case is_own_operation(core, msg.client_id) {
        True ->
          ack_own_attach(
            core,
            msg.client_id,
            msg.client_sequence_number,
            address,
            snapshot,
          )
        False -> remote_attach(core, msg.sequence_number, address, snapshot)
      }
    Ok(wire_op.ChannelOperation(address, raw_contents)) ->
      // The operation envelope carries no channel type; the registry is the
      // authoritative source, so decode against the addressed channel's own
      // grammar. Channels are always attached before their operations arrive.
      case dict.get(core.channels, address) {
        Error(_) -> Error(UnknownChannel(address, msg.sequence_number))
        Ok(state) ->
          case
            decode.run(
              raw_contents,
              wire_op.channel_operation_decoder(channel.channel_type(state)),
            )
          {
            Error(_) -> Error(BadOperationContents(msg.sequence_number))
            Ok(operation) ->
              case is_own_operation(core, msg.client_id) {
                True ->
                  ack_own_operation(
                    core,
                    msg.client_id,
                    msg.client_sequence_number,
                    address,
                    state,
                    operation,
                    msg.sequence_number,
                    msg.minimum_sequence_number,
                  )
                False ->
                  apply_remote_channel(
                    core,
                    msg.client_id,
                    msg.sequence_number,
                    msg.minimum_sequence_number,
                    msg.reference_sequence_number,
                    address,
                    state,
                    operation,
                  )
              }
          }
      }
  }
}

fn is_own_operation(core: Core, message_client_id: Option(String)) -> Bool {
  case message_client_id {
    None -> False
    Some(cid) ->
      cid == core.client_id
      || case core.in_flight {
        [head, ..] -> in_flight_client_id(head) == cid
        [] -> False
      }
  }
}

fn in_flight_client_id(entry: InFlight) -> String {
  case entry {
    InFlightOperation(client_id: client_id, ..) -> client_id
    InFlightAttach(client_id: client_id, ..) -> client_id
  }
}

fn remote_attach(
  core: Core,
  sequence_number: Int,
  address: String,
  snapshot: Snapshot,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case has_channel(core, address) {
    True -> Error(DuplicateAttach(address, sequence_number))
    False -> {
      use state <- result.try(
        channel.from_snapshot(snapshot, replica: core.client_id)
        |> result.map_error(fn(detail) {
          BadSummaryChannel(address: address, detail: detail)
        }),
      )
      Ok(#(add_attached_channel(core, address, state), [], []))
    }
  }
}

fn apply_remote_channel(
  core: Core,
  message_client_id: Option(String),
  sequence_number: Int,
  minimum_sequence_number: Int,
  reference_sequence_number: Int,
  address: String,
  state: ChannelState,
  operation: channel.ChannelOperation,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  let meta =
    SequencedMeta(
      sequence_number: sequence_number,
      last_seen_sequence_number: core.last_seen_sequence_number,
      minimum_sequence_number: minimum_sequence_number,
      author: option.map(message_client_id, client_id_to_int)
        |> option.unwrap(0),
      self: client_id_to_int(core.client_id),
      quorum: quorum_of(core, message_client_id),
      roster: set.to_list(core.members),
      reference_sequence_number: reference_sequence_number,
    )
  case channel.apply_remote(state, operation, meta) {
    Ok(#(state, events, owed)) ->
      Ok(
        #(
          enqueue_owed(
            put_attached_channel(core, address, state),
            address,
            owed,
          ),
          tag_events(address, events),
          [],
        ),
      )
    Error(channel.UnexpectedAck(detail))
    | Error(channel.WrongChannelType(detail))
    | Error(channel.CorruptRemoteOperation(detail))
    | Error(channel.UnsupportedP2p(detail)) -> Error(AckMismatch(detail))
  }
}

/// Add the owed follow-up operations that a kernel released while it applied a
/// sequenced operation, keyed by channel address. `collect_released_operations`
/// then stamps them and submits them after the current batch. This function is
/// public, so that a test can fill the buffer without a kernel that produces
/// operations.
pub fn enqueue_owed(
  core: Core,
  address: String,
  owed: List(channel.ChannelOperation),
) -> Core {
  case owed {
    [] -> core
    _ -> {
      let existing = dict.get(core.owed, address) |> result.unwrap([])
      Core(
        ..core,
        owed: dict.insert(core.owed, address, list.append(existing, owed)),
      )
    }
  }
}

fn ack_own_attach(
  core: Core,
  message_client_id: Option(String),
  client_sequence_number: Int,
  address: String,
  echoed: Snapshot,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.in_flight {
    [] ->
      Error(AckMismatch(
        "own attach sequenced with csn "
        <> int.to_string(client_sequence_number)
        <> " but in-flight queue is empty",
      ))
    [head, ..rest] ->
      case head {
        InFlightAttach(
          client_id: client_id,
          client_sequence_number: head_client_sequence_number,
          address: head_address,
          snapshot: snapshot,
        ) ->
          case
            Some(client_id) == message_client_id
            && head_client_sequence_number == client_sequence_number
            && head_address == address
            && channel.same_snapshot(snapshot, echoed)
          {
            True -> Ok(#(Core(..core, in_flight: rest), [], []))
            False ->
              Error(AckMismatch(
                "expected attach ack for csn "
                <> int.to_string(head_client_sequence_number)
                <> ", got csn "
                <> int.to_string(client_sequence_number),
              ))
          }
        InFlightOperation(
          client_sequence_number: head_client_sequence_number,
          ..,
        ) ->
          Error(AckMismatch(
            "expected channel op ack for csn "
            <> int.to_string(head_client_sequence_number)
            <> ", got attach ack for csn "
            <> int.to_string(client_sequence_number),
          ))
      }
  }
}

fn ack_own_operation(
  core: Core,
  message_client_id: Option(String),
  client_sequence_number: Int,
  address: String,
  state: ChannelState,
  echoed: channel.ChannelOperation,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.in_flight {
    [] ->
      Error(AckMismatch(
        "own op sequenced with csn "
        <> int.to_string(client_sequence_number)
        <> " but in-flight queue is empty",
      ))
    [head, ..rest] ->
      case head {
        InFlightOperation(
          client_id: client_id,
          client_sequence_number: head_client_sequence_number,
          address: head_address,
          operation: operation,
          meta: meta,
        ) ->
          case
            Some(client_id) == message_client_id
            && head_client_sequence_number == client_sequence_number
            && head_address == address
            && channel.same_shape(operation, echoed)
          {
            False ->
              Error(AckMismatch(
                "expected ack for csn "
                <> int.to_string(head_client_sequence_number)
                <> ", got csn "
                <> int.to_string(client_sequence_number),
              ))
            True -> {
              let sequenced_meta =
                SequencedMeta(
                  sequence_number: sequence_number,
                  last_seen_sequence_number: core.last_seen_sequence_number,
                  minimum_sequence_number: minimum_sequence_number,
                  author: client_id_to_int(core.client_id),
                  self: client_id_to_int(core.client_id),
                  quorum: quorum_of(core, Some(core.client_id)),
                  roster: set.to_list(core.members),
                  reference_sequence_number: core.last_seen_sequence_number,
                )
              case channel.applies_own_on_sequence(state) {
                // Consensus kernels (PactMap) take effect only on sequencing,
                // regardless of author. Reclaim the in-flight entry here, then
                // apply the operation through the same `apply_remote` path a
                // remote client would, capturing any owed follow-up (e.g. an
                // Accept).
                True ->
                  case channel.apply_remote(state, operation, sequenced_meta) {
                    Ok(#(state, events, owed)) ->
                      Ok(
                        #(
                          enqueue_owed(
                            Core(
                              ..core,
                              channels: dict.insert(
                                core.channels,
                                address,
                                state,
                              ),
                              in_flight: rest,
                            ),
                            address,
                            owed,
                          ),
                          tag_events(address, events),
                          [],
                        ),
                      )
                    Error(channel.UnexpectedAck(detail))
                    | Error(channel.WrongChannelType(detail))
                    | Error(channel.CorruptRemoteOperation(detail))
                    | Error(channel.UnsupportedP2p(detail)) ->
                      Error(AckMismatch(detail))
                  }
                False ->
                  case
                    channel.ack_local(state, operation, meta, sequenced_meta)
                  {
                    Ok(#(state, events, resolution)) ->
                      Ok(#(
                        Core(
                          ..core,
                          channels: dict.insert(core.channels, address, state),
                          in_flight: rest,
                        ),
                        tag_events(address, events),
                        tag_resolution(address, resolution),
                      ))
                    Error(channel.UnexpectedAck(detail))
                    | Error(channel.WrongChannelType(detail))
                    | Error(channel.CorruptRemoteOperation(detail))
                    | Error(channel.UnsupportedP2p(detail)) ->
                      Error(AckMismatch(detail))
                  }
              }
            }
          }
        InFlightAttach(client_sequence_number: head_client_sequence_number, ..) ->
          Error(AckMismatch(
            "expected attach ack for csn "
            <> int.to_string(head_client_sequence_number)
            <> ", got channel op ack for csn "
            <> int.to_string(client_sequence_number),
          ))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn create_detached(
  core: Core,
  address: String,
  init: channel.ChannelInit,
) -> Core {
  case address == root_address || has_channel(core, address) {
    True -> core
    False ->
      Core(
        ..core,
        detached: dict.insert(
          core.detached,
          address,
          channel.new(init, replica: core.client_id),
        ),
      )
  }
}

pub fn has_channel(core: Core, address: String) -> Bool {
  dict.has_key(core.channels, address) || dict.has_key(core.detached, address)
}

pub fn set(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation) = map_kernel.set(kernel, key, value)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(_)) -> {
      // Attaching dependencies first can reshape `core.channels`, so re-read
      // the kernel afterwards (its own type cannot change underneath us).
      let #(core, attach_outbound) = attach_dependencies(core, value)
      use located <- result.try(locate_map(core, address))
      let kernel = case located {
        Detached(kernel) | Attached(kernel) -> kernel
      }
      let #(kernel, events, operation) = map_kernel.set(kernel, key, value)
      let #(core, events, outbound) =
        stamp_attached(
          core,
          address,
          channel.MapState(kernel),
          tag_map_events(address, events),
          channel.MapOperation(operation),
          channel.NoMeta,
        )
      Ok(#(core, events, list.append(attach_outbound, outbound)))
    }
  }
}

pub fn delete(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation) = map_kernel.delete(kernel, key)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation) = map_kernel.delete(kernel, key)
      Ok(stamp_attached(
        core,
        address,
        channel.MapState(kernel),
        tag_map_events(address, events),
        channel.MapOperation(operation),
        channel.NoMeta,
      ))
    }
  }
}

pub fn clear(
  core: Core,
  address: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation) = map_kernel.clear(kernel)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation) = map_kernel.clear(kernel)
      Ok(stamp_attached(
        core,
        address,
        channel.MapState(kernel),
        tag_map_events(address, events),
        channel.MapOperation(operation),
        channel.NoMeta,
      ))
    }
  }
}

pub fn increment(
  core: Core,
  address: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_counter(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        counter_kernel.increment(kernel, amount)
      Ok(
        #(
          put_detached_channel(core, address, channel.CounterState(kernel)),
          tag_counter_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        counter_kernel.increment(kernel, amount)
      Ok(stamp_attached(
        core,
        address,
        channel.CounterState(kernel),
        tag_counter_events(address, events),
        channel.CounterOperation(operation),
        channel.CounterMeta(message_id),
      ))
    }
  }
}

/// Apply a signed update to the PN-counter at `address` optimistically. That
/// update is an increment or a decrement. The optimistic lifecycle is the same
/// as for `increment`.
pub fn pn_counter_update(
  core: Core,
  address: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_pn_counter(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        pn_counter_kernel.update(kernel, amount)
      Ok(
        #(
          put_detached_channel(core, address, channel.PnCounterState(kernel)),
          tag_pn_counter_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        pn_counter_kernel.update(kernel, amount)
      Ok(stamp_attached(
        core,
        address,
        channel.PnCounterState(kernel),
        tag_pn_counter_events(address, events),
        channel.PnCounterOperation(operation),
        channel.PnCounterMeta(message_id),
      ))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PactMap edits
// ─────────────────────────────────────────────────────────────────────────────

/// Propose `value` for `key` in the PactMap at `address`. `value` is a JSON
/// payload, or `None` for a delete. Unlike an optimistic kernel, a consensus
/// PactMap does **not** apply the value locally. The kernel returns the
/// operation to submit, or a `ProposeError` value when a value is already
/// pending for the key, which changes nothing. The value takes effect when the
/// `Set` operation sequences. The released-operations loop emits the `Accept`
/// operation of the setter by itself.
pub fn pact_map_set(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  pact_map_submit(core, address, fn(kernel) {
    pact_map_kernel.set(
      kernel,
      key,
      Some(value),
      core.last_seen_sequence_number,
    )
  })
}

/// Propose a delete for `key` in the PactMap at `address`. A delete writes a
/// tombstone. This function submits an operation only, the same as
/// `pact_map_set`, and the delete takes effect when that operation sequences. A
/// `ProposeError` value from the kernel changes nothing. The kernel gives that
/// result when a value is already pending, when the key is absent, and when the
/// key already holds a tombstone.
pub fn pact_map_delete(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  pact_map_submit(core, address, fn(kernel) {
    pact_map_kernel.delete(kernel, key, core.last_seen_sequence_number)
  })
}

fn pact_map_submit(
  core: Core,
  address: String,
  produce: fn(pact_map_kernel.PactMapState) ->
    Result(pact_map_kernel.PactMapOperation, pact_map_kernel.ProposeError),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_pact_map(core, address) {
    Error(core_error) -> Error(core_error)
    // A detached PactMap has no sequencer to settle a pending value, so a set
    // cannot be submitted yet; it is a no-operation until the channel is
    // attached.
    Ok(Detached(_)) -> Ok(#(core, [], []))
    Ok(Attached(kernel)) ->
      case produce(kernel) {
        // A refusal changes nothing, and the caller can retry later.
        Error(_) -> Ok(#(core, [], []))
        Ok(operation) ->
          Ok(stamp_attached(
            core,
            address,
            channel.PactMapState(kernel),
            [],
            channel.PactMapOperation(operation),
            channel.NoMeta,
          ))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConsensusOrderedCollection edits
// ─────────────────────────────────────────────────────────────────────────────

/// Append `value` to the queue at `address`. An attached channel is not
/// optimistic, and the value takes effect when the operation sequences, through
/// the ack of that operation. A detached channel applies the value immediately,
/// and its attach carries the add.
pub fn ordered_add(
  core: Core,
  address: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_ordered(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events) =
        ordered_collection_kernel.add_detached(kernel, value)
      Ok(
        #(
          put_detached_channel(
            core,
            address,
            channel.OrderedCollectionState(kernel),
          ),
          tag_ordered_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let operation = ordered_collection_kernel.add(kernel, value)
      Ok(stamp_attached(
        core,
        address,
        channel.OrderedCollectionState(kernel),
        [],
        channel.OrderedCollectionOperation(operation),
        channel.NoMeta,
      ))
    }
  }
}

/// Acquire the head of the queue at `address`, under the `acquire_id` value that
/// the caller supplies. Create that id in the runtime layer, with
/// `id.uuid_v4`. An attached channel is not optimistic. The kernel removes the
/// item when the operation sequences, and the `Acquired` event delivers it. The
/// `acquire_id` value is the key of the later `complete` or `release` call. A
/// detached channel acquires the item immediately.
pub fn ordered_acquire(
  core: Core,
  address: String,
  acquire_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  ordered_acquire_submit(core, address, acquire_id)
  |> result.map(fn(submitted) { #(submitted.0, submitted.1, submitted.2) })
}

/// The same as `ordered_acquire`, and the function also reports the immediate
/// outcome. The result is `Some` for a detached channel, where the acquire took
/// effect in this call. The result is `None` for an attached channel. There the
/// outcome arrives as an `AcquireResolved` resolution when the operation
/// sequences, keyed by `acquire_id`.
pub fn ordered_acquire_submit(
  core: Core,
  address: String,
  acquire_id: String,
) -> Result(
  #(
    Core,
    List(#(String, ChannelEvent)),
    List(wire.OutboundOperation),
    Option(ordered_collection_kernel.AcquireOutcome),
  ),
  CoreError,
) {
  case locate_ordered(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, outcome) =
        ordered_collection_kernel.acquire_detached(kernel, acquire_id)
      Ok(#(
        put_detached_channel(
          core,
          address,
          channel.OrderedCollectionState(kernel),
        ),
        tag_ordered_events(address, events),
        [],
        Some(outcome),
      ))
    }
    Ok(Attached(kernel)) -> {
      let operation = ordered_collection_kernel.acquire(acquire_id)
      let #(core, events, outbound) =
        stamp_attached(
          core,
          address,
          channel.OrderedCollectionState(kernel),
          [],
          channel.OrderedCollectionOperation(operation),
          channel.NoMeta,
        )
      Ok(#(core, events, outbound, None))
    }
  }
}

/// Complete the held job `acquire_id` in the queue at `address`, which removes
/// it. The function does nothing on a detached channel, because there is nothing
/// to complete without a sequencer.
pub fn ordered_complete(
  core: Core,
  address: String,
  acquire_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  ordered_submit(core, address, ordered_collection_kernel.complete(acquire_id))
}

/// Release the held job `acquire_id` in the queue at `address` back to the end
/// of that queue. The function does nothing on a detached channel.
pub fn ordered_release(
  core: Core,
  address: String,
  acquire_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  ordered_submit(core, address, ordered_collection_kernel.release(acquire_id))
}

fn ordered_submit(
  core: Core,
  address: String,
  operation: ordered_collection_kernel.OrderedOperation,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_ordered(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(_)) -> Ok(#(core, [], []))
    Ok(Attached(kernel)) ->
      Ok(stamp_attached(
        core,
        address,
        channel.OrderedCollectionState(kernel),
        [],
        channel.OrderedCollectionOperation(operation),
        channel.NoMeta,
      ))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SharedDirectory edits
// ─────────────────────────────────────────────────────────────────────────────

/// Set `key` to `value` in the directory at `path`. The write is optimistic. The
/// local value appears immediately, and the operation sequences and receives an
/// ack, the same as any other operation.
pub fn directory_set(
  core: Core,
  address: String,
  path: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  directory_storage_edit(core, address, Some(value), fn(kernel) {
    directory_kernel.set(kernel, path, key, value)
  })
}

pub fn directory_delete(
  core: Core,
  address: String,
  path: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  directory_storage_edit(core, address, None, fn(kernel) {
    directory_kernel.delete(kernel, path, key)
  })
}

pub fn directory_clear(
  core: Core,
  address: String,
  path: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  directory_storage_edit(core, address, None, fn(kernel) {
    directory_kernel.clear(kernel, path)
  })
}

pub fn directory_create_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  let self = client_id_to_int(core.client_id)
  directory_subdirectory_edit(core, address, fn(kernel) {
    directory_kernel.create_subdirectory(kernel, path, name, self)
  })
}

pub fn directory_delete_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  directory_subdirectory_edit(core, address, fn(kernel) {
    directory_kernel.delete_subdirectory(kernel, path, name)
  })
}

/// A storage operation, which is a `set`, a `delete`, or a `clear`, always
/// produces an outbound operation on an attached channel. The kernel returns
/// the state, the events, the operation, and the message id.
fn directory_storage_edit(
  core: Core,
  address: String,
  dependency_value: Option(Json),
  run: fn(directory_kernel.DirectoryState) ->
    Result(
      #(
        directory_kernel.DirectoryState,
        List(directory_kernel.DirectoryEvent),
        directory_kernel.DirectoryOperation,
        Int,
      ),
      directory_kernel.KernelError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_directory(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(error) ->
          Error(DirectoryOperationFailed(address, directory_detail(error)))
      }
    Ok(Attached(kernel)) -> {
      case run(kernel) {
        Ok(#(kernel, events, operation, message_id)) -> {
          let #(core, attach_outbound) = case dependency_value {
            Some(value) -> attach_dependencies(core, value)
            None -> #(core, [])
          }
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.DirectoryState(kernel),
              tag_directory_events(address, events),
              channel.DirectoryOperation(operation, message_id),
              channel.DirectoryMeta(message_id),
            )
          Ok(#(core, events, list.append(attach_outbound, outbound)))
        }
        Error(error) ->
          Error(DirectoryOperationFailed(address, directory_detail(error)))
      }
    }
  }
}

/// A subdirectory operation, which is a `create` or a `delete`, can produce no
/// outbound operation. A duplicate create, and a delete of a child that the
/// optimistic view does not contain, both update the local state and emit
/// events, and they send nothing.
fn directory_subdirectory_edit(
  core: Core,
  address: String,
  run: fn(directory_kernel.DirectoryState) ->
    Result(
      #(
        directory_kernel.DirectoryState,
        List(directory_kernel.DirectoryEvent),
        Option(directory_kernel.DirectoryOperation),
        Int,
      ),
      directory_kernel.KernelError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_directory(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(error) ->
          Error(DirectoryOperationFailed(address, directory_detail(error)))
      }
    Ok(Attached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, Some(operation), message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.DirectoryState(kernel),
            tag_directory_events(address, events),
            channel.DirectoryOperation(operation, message_id),
            channel.DirectoryMeta(message_id),
          ))
        Ok(#(kernel, events, None, _message_id)) ->
          Ok(
            #(
              put_attached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(error) ->
          Error(DirectoryOperationFailed(address, directory_detail(error)))
      }
  }
}

fn directory_detail(error: directory_kernel.KernelError) -> String {
  case error {
    directory_kernel.PathNotFound(path) -> "path not found: " <> path
    directory_kernel.InvalidName(name) -> "invalid subdirectory name: " <> name
    directory_kernel.UnexpectedAck(_, detail) -> detail
    directory_kernel.UnexpectedRollback(_, detail) -> detail
    directory_kernel.InvariantViolation(detail) -> detail
  }
}

/// Submit a json0 operation that the client wrote against the current
/// optimistic view of the channel. The one-operation-in-flight kernel sends the
/// operation immediately when no operation is in flight. If one is in flight,
/// the kernel composes the new operation into the buffer and releases it on the
/// next ack, in `collect_released_operations`. One operation is thus on the
/// wire at a time, at most.
pub fn submit_json_ot(
  core: Core,
  address: String,
  components: json_ot.Operation,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_json_ot(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case
        json_ot_kernel.submit(
          kernel,
          components,
          core.last_seen_sequence_number,
        )
      {
        Ok(#(kernel, _wire, events)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.JsonOtState(kernel)),
              tag_json_ot_events(address, events),
              [],
            ),
          )
        Error(error) -> Error(AckMismatch(json_ot_kernel_error_detail(error)))
      }
    Ok(Attached(kernel)) ->
      case
        json_ot_kernel.submit(
          kernel,
          components,
          core.last_seen_sequence_number,
        )
      {
        Ok(#(kernel, Some(wire), events)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.JsonOtState(kernel),
            tag_json_ot_events(address, events),
            channel.JsonOtOperation(wire),
            channel.NoMeta,
          ))
        Ok(#(kernel, None, events)) ->
          Ok(
            #(
              put_attached_channel(core, address, channel.JsonOtState(kernel)),
              tag_json_ot_events(address, events),
              [],
            ),
          )
        Error(error) -> Error(AckMismatch(json_ot_kernel_error_detail(error)))
      }
  }
}

/// The current optimistic json0 document of the channel. The result is `Error(Nil)`
/// when the address does not name a json0 channel, and when the core cannot
/// compute the view.
pub fn json_ot_view(
  core: Core,
  address: String,
) -> Result(json_ot.JsonValue, Nil) {
  case find_channel(core, address) {
    Ok(channel.JsonOtState(kernel)) ->
      json_ot_kernel.view(kernel) |> result.replace_error(Nil)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// Submit a rich-text delta that the client wrote against the current optimistic
/// document of the channel. The behaviour is the same as for json0. The kernel
/// sends one delta immediately, and it buffers each later delta until
/// `collect_released_operations` takes the promoted outbound operation of the
/// kernel.
pub fn submit_rich_text(
  core: Core,
  address: String,
  delta: rich_text.Delta,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_rich_text(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case
        rich_text_kernel.submit(kernel, delta, core.last_seen_sequence_number)
      {
        Ok(#(kernel, _wire, events)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.RichTextState(kernel)),
              tag_rich_text_events(address, events),
              [],
            ),
          )
        Error(error) -> Error(AckMismatch(rich_text_kernel_error_detail(error)))
      }
    Ok(Attached(kernel)) ->
      case
        rich_text_kernel.submit(kernel, delta, core.last_seen_sequence_number)
      {
        Ok(#(kernel, Some(wire), events)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.RichTextState(kernel),
            tag_rich_text_events(address, events),
            channel.RichTextOperation(wire),
            channel.NoMeta,
          ))
        Ok(#(kernel, None, events)) ->
          Ok(
            #(
              put_attached_channel(core, address, channel.RichTextState(kernel)),
              tag_rich_text_events(address, events),
              [],
            ),
          )
        Error(error) -> Error(AckMismatch(rich_text_kernel_error_detail(error)))
      }
  }
}

/// The current optimistic rich-text document of the channel. The result is
/// `Error(Nil)` when the address does not name a rich-text channel, and when the core
/// cannot compute the view.
pub fn rich_text_view(
  core: Core,
  address: String,
) -> Result(rich_text.Document, Nil) {
  case find_channel(core, address) {
    Ok(channel.RichTextState(kernel)) ->
      rich_text_kernel.view(kernel) |> result.replace_error(Nil)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

fn json_ot_kernel_error_detail(error: json_ot_kernel.KernelError) -> String {
  case error {
    json_ot_kernel.UnexpectedAck(detail) -> detail
    json_ot_kernel.OtFailure(ot) ->
      case ot {
        json_ot.BadPath(detail) -> "json0 bad path: " <> detail
        json_ot.BadValue(detail) -> "json0 bad value: " <> detail
        json_ot.UnknownSubtype(name) -> "json0 unknown subtype: " <> name
      }
  }
}

fn rich_text_kernel_error_detail(
  error: rich_text_kernel.KernelError,
) -> String {
  case error {
    rich_text_kernel.UnexpectedAck(detail) -> detail
    rich_text_kernel.RichTextFailure(algebra) ->
      case algebra {
        rich_text.Malformed(component, reason) ->
          "rich-text malformed " <> component <> ": " <> reason
        rich_text.InvalidApply(reason) -> "rich-text invalid apply: " <> reason
        rich_text.InvalidBoundary(offset) ->
          "rich-text invalid boundary at offset " <> int.to_string(offset)
      }
  }
}

pub fn or_map_increment(
  core: Core,
  address: String,
  key: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case or_map_kernel.increment(kernel, key, amount) {
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.OrMapState(kernel)),
              tag_or_map_events(address, events),
              [],
            ),
          )
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.NegativeTally(detail)) ->
          Error(AckMismatch(detail))
      }
    Ok(Attached(kernel)) ->
      case or_map_kernel.increment(kernel, key, amount) {
        Ok(#(kernel, events, operation, message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.OrMapState(kernel),
            tag_or_map_events(address, events),
            channel.OrMapOperation(operation),
            channel.OrMapMeta(message_id),
          ))
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.NegativeTally(detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn or_map_set(
  core: Core,
  address: String,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case or_map_kernel.set_register(kernel, key, value, timestamp) {
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.OrMapState(kernel)),
              tag_or_map_events(address, events),
              [],
            ),
          )
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.NegativeTally(detail)) ->
          Error(AckMismatch(detail))
      }
    Ok(Attached(_)) -> {
      let #(core, attach_outbound) =
        attach_dependencies_from_register_string(core, value)
      // Re-read the channel. Attaching the dependencies of the value rewrites
      // `core.channels`, so the kernel found above is stale.
      use located <- result.try(locate_or_map(core, address))
      let kernel = case located {
        Detached(kernel) | Attached(kernel) -> kernel
      }
      case or_map_kernel.set_register(kernel, key, value, timestamp) {
        Ok(#(kernel, events, operation, message_id)) -> {
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.OrMapState(kernel),
              tag_or_map_events(address, events),
              channel.OrMapOperation(operation),
              channel.OrMapMeta(message_id),
            )
          Ok(#(core, events, list.append(attach_outbound, outbound)))
        }
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail))
        | Error(or_map_kernel.NegativeTally(detail)) ->
          Error(AckMismatch(detail))
      }
    }
  }
}

pub fn or_map_remove(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case or_map_kernel.remove(kernel, key) {
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.OrMapState(kernel)),
              tag_or_map_events(address, events),
              [],
            ),
          )
        Error(error) -> Error(or_map_kernel_error(address, error))
      }

    Ok(Attached(kernel)) ->
      case or_map_kernel.remove(kernel, key) {
        Ok(#(kernel, events, operation, message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.OrMapState(kernel),
            tag_or_map_events(address, events),
            channel.OrMapOperation(operation),
            channel.OrMapMeta(message_id),
          ))
        Error(error) -> Error(or_map_kernel_error(address, error))
      }
  }
}

/// Convert an error of the or-map kernel into a `CoreError` value. A mode
/// mismatch is incorrect use of the API. Every other error means the pending
/// queue and the acks no longer agree.
fn or_map_kernel_error(
  address: String,
  error: or_map_kernel.KernelError,
) -> CoreError {
  case error {
    or_map_kernel.ModeMismatch(detail) -> OrMapModeMismatch(address, detail)
    or_map_kernel.UnexpectedAck(detail)
    | or_map_kernel.UnexpectedRollback(detail)
    | or_map_kernel.CorruptDelta(detail)
    | or_map_kernel.NegativeTally(detail) -> AckMismatch(detail)
  }
}

pub fn or_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_or_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        or_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.OrSetState(kernel)),
          tag_or_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        or_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.OrSetState(kernel),
        tag_or_set_events(address, events),
        channel.OrSetOperation(operation),
        channel.OrSetMeta(message_id),
      ))
    }
  }
}

pub fn or_set_remove(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_or_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        or_set_kernel.remove(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.OrSetState(kernel)),
          tag_or_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        or_set_kernel.remove(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.OrSetState(kernel),
        tag_or_set_events(address, events),
        channel.OrSetOperation(operation),
        channel.OrSetMeta(message_id),
      ))
    }
  }
}

fn mutate_sequence(
  core: Core,
  address: String,
  dependencies: Option(Json),
  mutate: fn(sequence_kernel.SequenceState) ->
    Result(
      #(
        sequence_kernel.SequenceState,
        List(sequence_kernel.SequenceEvent),
        sequence_kernel.SequenceOperation,
        Int,
      ),
      sequence_kernel.EditError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_sequence(core, address) {
    Error(error) -> Error(error)
    Ok(Detached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(SequenceOperationFailed(
            address,
            sequence_kernel.edit_error_detail(error),
          ))
        Ok(#(kernel, events, _operation, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.SequenceState(kernel)),
              tag_sequence_events(address, events),
              [],
            ),
          )
      }
    Ok(Attached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(SequenceOperationFailed(
            address,
            sequence_kernel.edit_error_detail(error),
          ))
        Ok(#(kernel, events, operation, message_id)) -> {
          let #(core, attach_outbound) = case dependencies {
            Some(value) -> attach_dependencies(core, value)
            None -> #(core, [])
          }
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.SequenceState(kernel),
              tag_sequence_events(address, events),
              channel.SequenceOperation(operation),
              channel.SequenceMeta(message_id),
            )
          Ok(#(core, events, list.append(attach_outbound, outbound)))
        }
      }
  }
}

pub fn sequence_insert(
  core: Core,
  address: String,
  index: Int,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_sequence(core, address, Some(value), sequence_kernel.insert(
    _,
    index,
    value,
  ))
}

pub fn sequence_delete(
  core: Core,
  address: String,
  index: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_sequence(core, address, None, sequence_kernel.delete(_, index))
}

pub fn sequence_move(
  core: Core,
  address: String,
  from_index: Int,
  to_index: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_sequence(core, address, None, sequence_kernel.move(
    _,
    from_index,
    to_index,
  ))
}

pub fn sequence_replace(
  core: Core,
  address: String,
  index: Int,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_sequence(core, address, Some(value), sequence_kernel.replace(
    _,
    index,
    value,
  ))
}

/// A text mutation returns an `Option(text_kernel.Submission)` value, and it
/// does not always produce an operation. A valid empty edit changes nothing.
/// See the module docs of `text_kernel`. A `Some` result updates the state,
/// emits the events, and, on an attached channel, stamps and submits one
/// channel operation. A `None` result changes no state and no submission
/// counter of the runtime, and it produces no event and no outbound operation.
fn mutate_text(
  core: Core,
  address: String,
  mutate: fn(text_kernel.TextState) ->
    Result(
      #(
        text_kernel.TextState,
        List(text_kernel.TextEvent),
        Option(text_kernel.Submission),
      ),
      text_kernel.EditError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_text(core, address) {
    Error(error) -> Error(error)
    Ok(Detached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(TextOperationFailed(
            address,
            text_kernel.edit_error_detail(error),
          ))
        Ok(#(kernel, events, _submission)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.TextState(kernel)),
              tag_text_events(address, events),
              [],
            ),
          )
      }
    Ok(Attached(kernel)) ->
      case mutate(kernel) {
        Error(error) ->
          Error(TextOperationFailed(
            address,
            text_kernel.edit_error_detail(error),
          ))
        Ok(#(
          kernel,
          events,
          Some(text_kernel.Submission(operation, message_id)),
        )) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TextState(kernel),
            tag_text_events(address, events),
            channel.TextOperation(operation),
            channel.TextMeta(message_id),
          ))
        Ok(#(kernel, events, None)) ->
          Ok(
            #(
              put_attached_channel(core, address, channel.TextState(kernel)),
              tag_text_events(address, events),
              [],
            ),
          )
      }
  }
}

pub fn text_insert(
  core: Core,
  address: String,
  index: Int,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.insert(_, index, value))
}

pub fn text_delete_range(
  core: Core,
  address: String,
  start: Int,
  end: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.delete_range(_, start, end))
}

pub fn text_replace_range(
  core: Core,
  address: String,
  start: Int,
  end: Int,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_text(core, address, text_kernel.replace_range(_, start, end, value))
}

pub fn text_append(
  core: Core,
  address: String,
  value: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  mutate_text(core, address, fn(kernel) {
    Ok(text_kernel.append(kernel, value))
  })
}

pub fn g_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_g_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        g_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.GSetState(kernel)),
          tag_g_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        g_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.GSetState(kernel),
        tag_g_set_events(address, events),
        channel.GSetOperation(operation),
        channel.GSetMeta(message_id),
      ))
    }
  }
}

pub fn two_p_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_two_p_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        two_p_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.TwoPSetState(kernel)),
          tag_two_p_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        two_p_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.TwoPSetState(kernel),
        tag_two_p_set_events(address, events),
        channel.TwoPSetOperation(operation),
        channel.TwoPSetMeta(message_id),
      ))
    }
  }
}

pub fn two_p_set_remove(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_two_p_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _operation, _message_id) =
        two_p_set_kernel.remove(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.TwoPSetState(kernel)),
          tag_two_p_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, operation, message_id) =
        two_p_set_kernel.remove(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.TwoPSetState(kernel),
        tag_two_p_set_events(address, events),
        channel.TwoPSetOperation(operation),
        channel.TwoPSetMeta(message_id),
      ))
    }
  }
}

pub fn register_write(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_register_collection(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events) =
        register_collection_kernel.write_detached(kernel, key, value)
      Ok(
        #(
          put_detached_channel(
            core,
            address,
            channel.RegisterCollectionState(kernel),
          ),
          tag_register_collection_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(_)) -> {
      // Attaching the dependencies of the value rewrites `core.channels`, so
      // the kernel found above is stale. Read it again.
      let #(core, attach_outbound) = attach_dependencies(core, value)
      use located <- result.try(locate_register_collection(core, address))
      let kernel = case located {
        Detached(kernel) | Attached(kernel) -> kernel
      }
      let operation =
        register_collection_kernel.write(
          kernel,
          key,
          value,
          core.last_seen_sequence_number,
        )
      let #(core, events, outbound) =
        stamp_attached(
          core,
          address,
          channel.RegisterCollectionState(kernel),
          [],
          channel.RegisterCollectionOperation(operation),
          channel.NoMeta,
        )
      Ok(#(core, events, list.append(attach_outbound, outbound)))
    }
  }
}

pub type ClaimSubmitResult {
  ClaimPending(
    core: Core,
    outbound: List(wire.OutboundOperation),
    immediate_outcome: Option(claims_kernel.ClaimOutcome),
  )
  ClaimAlreadyClaimed(current_value: Json)
  ClaimAlreadyPendingLocally
}

pub fn claim_once(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(ClaimSubmitResult, CoreError) {
  case locate_claims(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case claims_kernel.get(kernel, key) {
        Ok(current_value) -> Ok(ClaimAlreadyClaimed(current_value))
        Error(Nil) -> {
          let kernel = claims_kernel.set_detached(kernel, key, value)
          let core =
            put_detached_channel(core, address, channel.ClaimsState(kernel))
          Ok(ClaimPending(
            core: core,
            outbound: [],
            immediate_outcome: Some(claims_kernel.Accepted(value)),
          ))
        }
      }
    Ok(Attached(kernel)) ->
      case
        claims_kernel.claim_once(
          kernel,
          key,
          value,
          core.last_seen_sequence_number,
        )
      {
        Ok(claims_kernel.AlreadyClaimed(current_value)) ->
          Ok(ClaimAlreadyClaimed(current_value))
        Ok(claims_kernel.Submitted(kernel, operation)) -> {
          let #(core, attach_outbound) = attach_dependencies(core, value)
          let #(core, _events, outbound) =
            stamp_attached(
              core,
              address,
              channel.ClaimsState(kernel),
              [],
              channel.ClaimsOperation(operation),
              channel.NoMeta,
            )
          Ok(ClaimPending(
            core: core,
            outbound: list.append(attach_outbound, outbound),
            immediate_outcome: None,
          ))
        }
        Error(claims_kernel.AlreadyPendingLocally(_)) ->
          Ok(ClaimAlreadyPendingLocally)
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn compare_and_set_claim(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(ClaimSubmitResult, CoreError) {
  case locate_claims(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let kernel = claims_kernel.set_detached(kernel, key, value)
      let core =
        put_detached_channel(core, address, channel.ClaimsState(kernel))
      Ok(ClaimPending(
        core: core,
        outbound: [],
        immediate_outcome: Some(claims_kernel.Accepted(value)),
      ))
    }
    Ok(Attached(kernel)) ->
      case
        claims_kernel.compare_and_set_claim(
          kernel,
          key,
          value,
          core.last_seen_sequence_number,
        )
      {
        Ok(claims_kernel.Submitted(kernel, operation)) -> {
          let #(core, attach_outbound) = attach_dependencies(core, value)
          let #(core, _events, outbound) =
            stamp_attached(
              core,
              address,
              channel.ClaimsState(kernel),
              [],
              channel.ClaimsOperation(operation),
              channel.NoMeta,
            )
          Ok(ClaimPending(
            core: core,
            outbound: list.append(attach_outbound, outbound),
            immediate_outcome: None,
          ))
        }
        Ok(claims_kernel.AlreadyClaimed(current_value)) ->
          Ok(ClaimAlreadyClaimed(current_value))
        Error(claims_kernel.AlreadyPendingLocally(_)) ->
          Ok(ClaimAlreadyPendingLocally)
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn task_manager_volunteer(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(
    Core,
    List(#(String, ChannelEvent)),
    List(wire.OutboundOperation),
    task_manager_kernel.VolunteerOutcome,
  ),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, outcome) =
        task_manager_kernel.volunteer_detached(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
        )
      Ok(#(
        put_detached_channel(core, address, channel.TaskManagerState(kernel)),
        tag_task_manager_events(address, events),
        [],
        outcome,
      ))
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_client_sequence_number
      let #(kernel, operation, outcome) =
        task_manager_kernel.volunteer(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      case operation {
        None ->
          Ok(#(
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            ),
            [],
            [],
            outcome,
          ))
        Some(operation) -> {
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.TaskManagerState(kernel),
              [],
              channel.TaskManagerOperation(operation),
              channel.TaskManagerMeta(message_id),
            )
          Ok(#(core, events, outbound, outcome))
        }
      }
    }
  }
}

pub fn task_manager_abandon(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events) =
        task_manager_kernel.abandon_detached(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
        )
      Ok(
        #(
          put_detached_channel(core, address, channel.TaskManagerState(kernel)),
          tag_task_manager_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_client_sequence_number
      let #(kernel, operation, events) =
        task_manager_kernel.abandon(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      case operation {
        None ->
          Ok(
            #(
              put_attached_channel(
                core,
                address,
                channel.TaskManagerState(kernel),
              ),
              tag_task_manager_events(address, events),
              [],
            ),
          )
        Some(operation) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TaskManagerState(kernel),
            tag_task_manager_events(address, events),
            channel.TaskManagerOperation(operation),
            channel.TaskManagerMeta(message_id),
          ))
      }
    }
  }
}

pub fn task_manager_complete(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      case
        task_manager_kernel.assigned(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          True,
        )
      {
        False -> Error(TaskNotAssigned(address, task_id))
        True -> {
          let #(kernel, events) =
            task_manager_kernel.complete_detached(kernel, task_id)
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.TaskManagerState(kernel),
              ),
              tag_task_manager_events(address, events),
              [],
            ),
          )
        }
      }
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_client_sequence_number
      case
        task_manager_kernel.complete(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      {
        Ok(#(kernel, operation)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TaskManagerState(kernel),
            [],
            channel.TaskManagerOperation(operation),
            channel.TaskManagerMeta(message_id),
          ))
        Error(task_manager_kernel.NotAssigned(_)) ->
          Error(TaskNotAssigned(address, task_id))
        Error(task_manager_kernel.UnexpectedAck(_, detail))
        | Error(task_manager_kernel.UnexpectedRollback(_, detail))
        | Error(task_manager_kernel.UnexpectedResubmit(_, detail)) ->
          Error(AckMismatch(detail))
      }
    }
  }
}

/// The position of the target channel of an edit. This type holds the kernel
/// after the type check.
type Located(kernel) {
  Detached(kernel)
  Attached(kernel)
}

fn locate_map(
  core: Core,
  address: String,
) -> Result(Located(map_kernel.MapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.MapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.MapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.MapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_counter(
  core: Core,
  address: String,
) -> Result(Located(counter_kernel.CounterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.CounterState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.CounterState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.CounterChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_pn_counter(
  core: Core,
  address: String,
) -> Result(Located(pn_counter_kernel.PnCounterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.PnCounterState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.PnCounterState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.PnCounterChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_pact_map(
  core: Core,
  address: String,
) -> Result(Located(pact_map_kernel.PactMapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.PactMapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.PactMapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.PactMapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_ordered(
  core: Core,
  address: String,
) -> Result(Located(ordered_collection_kernel.OrderedState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.OrderedCollectionState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.OrderedCollectionState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.OrderedCollectionChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_or_map(
  core: Core,
  address: String,
) -> Result(Located(or_map_kernel.OrMapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.OrMapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.OrMapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.OrMapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_or_set(
  core: Core,
  address: String,
) -> Result(Located(or_set_kernel.OrSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.OrSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.OrSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.OrSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_sequence(
  core: Core,
  address: String,
) -> Result(Located(sequence_kernel.SequenceState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.SequenceState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.SequenceState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.SequenceChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_text(
  core: Core,
  address: String,
) -> Result(Located(text_kernel.TextState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TextState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TextState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TextChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_g_set(
  core: Core,
  address: String,
) -> Result(Located(g_set_kernel.GSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.GSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.GSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.GSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_two_p_set(
  core: Core,
  address: String,
) -> Result(Located(two_p_set_kernel.TwoPSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TwoPSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TwoPSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TwoPSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_register_collection(
  core: Core,
  address: String,
) -> Result(Located(register_collection_kernel.RegisterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.RegisterCollectionState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.RegisterCollectionState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.RegisterCollectionChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_claims(
  core: Core,
  address: String,
) -> Result(Located(claims_kernel.ClaimsState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.ClaimsState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.ClaimsState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.ClaimsChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_task_manager(
  core: Core,
  address: String,
) -> Result(Located(task_manager_kernel.TaskManagerState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TaskManagerState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TaskManagerState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TaskManagerChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_json_ot(
  core: Core,
  address: String,
) -> Result(Located(json_ot_kernel.JsonOtState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.JsonOtState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.JsonOtState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.JsonOtChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_rich_text(
  core: Core,
  address: String,
) -> Result(Located(rich_text_kernel.RichTextState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.RichTextState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.RichTextState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.RichTextChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_directory(
  core: Core,
  address: String,
) -> Result(Located(directory_kernel.DirectoryState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.DirectoryState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.DirectoryState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.DirectoryChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_channel(
  core: Core,
  address: String,
) -> Result(Located(ChannelState), CoreError) {
  case dict.get(core.detached, address) {
    Ok(state) -> Ok(Detached(state))
    Error(_) ->
      case dict.get(core.channels, address) {
        Ok(state) -> Ok(Attached(state))
        Error(_) ->
          Error(UnknownChannel(address, core.last_seen_sequence_number))
      }
  }
}

/// Check that `address` resolves to the channel type that the caller
/// requested.
pub fn require_channel_type(
  core: Core,
  address: String,
  expected: channel.ChannelType,
) -> Result(Nil, CoreError) {
  use located <- result.try(locate_channel(core, address))
  let state = case located {
    Detached(state) | Attached(state) -> state
  }
  let actual = channel.channel_type(state)
  case actual == expected {
    True -> Ok(Nil)
    False -> Error(WrongChannelType(address, expected, actual))
  }
}

fn attach_dependencies(
  core: Core,
  value: Json,
) -> #(Core, List(wire.OutboundOperation)) {
  let #(order, _) =
    collect_attach_order(core, handle.collect_handle_addresses(value), [])
  submit_attaches(core, order)
}

fn attach_dependencies_from_register_string(
  core: Core,
  value: String,
) -> #(Core, List(wire.OutboundOperation)) {
  case json.parse(value, wire.json_value_decoder()) {
    Ok(json_value) -> attach_dependencies(core, json_value)
    Error(_) -> #(core, [])
  }
}

fn collect_attach_order(
  core: Core,
  addresses: List(String),
  visited: List(String),
) -> #(List(String), List(String)) {
  list.fold(addresses, #([], visited), fn(acc, address) {
    let #(order, visited) = acc
    let #(next, visited) = collect_attach_for(core, address, visited)
    #(list.append(order, next), visited)
  })
}

fn collect_attach_for(
  core: Core,
  address: String,
  visited: List(String),
) -> #(List(String), List(String)) {
  case list.any(visited, fn(seen) { seen == address }) {
    True -> #([], visited)
    False -> {
      let visited = [address, ..visited]
      case dict.get(core.detached, address) {
        Error(_) -> #([], visited)
        Ok(state) -> {
          let deps = channel.handle_addresses(state)
          let #(order, visited) = collect_attach_order(core, deps, visited)
          #(list.append(order, [address]), visited)
        }
      }
    }
  }
}

fn submit_attaches(
  core: Core,
  addresses: List(String),
) -> #(Core, List(wire.OutboundOperation)) {
  list.fold(addresses, #(core, []), fn(acc, address) {
    let #(core, outbound) = acc
    case dict.get(core.detached, address) {
      Error(_) -> #(core, outbound)
      Ok(state) -> {
        let snapshot = channel.attach_snapshot(state)
        let client_sequence_number = core.next_client_sequence_number
        let outbound_operation =
          wire_op.outbound_attach_operation(
            address: address,
            client_sequence_number: client_sequence_number,
            reference_sequence_number: core.last_seen_sequence_number,
            snapshot: snapshot,
          )
        let core =
          Core(
            ..core,
            channels: dict.insert(
              core.channels,
              address,
              channel.attach_state(state, replica: core.client_id),
            ),
            channel_order: list.unique(
              list.append(core.channel_order, [address]),
            ),
            detached: dict.delete(core.detached, address),
            next_client_sequence_number: client_sequence_number + 1,
            in_flight: list.append(core.in_flight, [
              InFlightAttach(
                client_id: core.client_id,
                client_sequence_number: client_sequence_number,
                address: address,
                snapshot: snapshot,
              ),
            ]),
          )
        #(core, list.append(outbound, [outbound_operation]))
      }
    }
  })
}

fn stamp_attached(
  core: Core,
  address: String,
  state: ChannelState,
  events: List(#(String, ChannelEvent)),
  operation: channel.ChannelOperation,
  meta: channel.LocalOperationMeta,
) -> #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOperation)) {
  let client_sequence_number = core.next_client_sequence_number
  let outbound =
    wire_op.outbound_channel_operation(
      address: address,
      client_sequence_number: client_sequence_number,
      reference_sequence_number: core.last_seen_sequence_number,
      operation: operation,
    )
  let core =
    Core(
      ..core,
      channels: dict.insert(core.channels, address, state),
      next_client_sequence_number: client_sequence_number + 1,
      in_flight: list.append(core.in_flight, [
        InFlightOperation(
          client_id: core.client_id,
          client_sequence_number: client_sequence_number,
          address: address,
          operation: operation,
          meta: meta,
        ),
      ]),
    )
  #(core, events, [outbound])
}

fn tag_events(
  address: String,
  events: List(ChannelEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, event) })
}

fn tag_resolution(
  address: String,
  resolution: Option(Resolution),
) -> List(#(String, Resolution)) {
  case resolution {
    Some(resolution) -> [#(address, resolution)]
    None -> []
  }
}

fn tag_map_events(
  address: String,
  events: List(map_kernel.MapEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.MapEvent(event)) })
}

fn tag_counter_events(
  address: String,
  events: List(counter_kernel.CounterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.CounterEvent(event)) })
}

fn tag_pn_counter_events(
  address: String,
  events: List(pn_counter_kernel.PnCounterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.PnCounterEvent(event)) })
}

fn tag_json_ot_events(
  address: String,
  events: List(json_ot_kernel.JsonOtEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.JsonOtEvent(event)) })
}

fn tag_rich_text_events(
  address: String,
  events: List(rich_text_kernel.RichTextEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.RichTextEvent(event)) })
}

fn tag_ordered_events(
  address: String,
  events: List(ordered_collection_kernel.OrderedEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) {
    #(address, channel.OrderedCollectionEvent(event))
  })
}

fn tag_directory_events(
  address: String,
  events: List(directory_kernel.DirectoryEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.DirectoryEvent(event)) })
}

fn tag_or_map_events(
  address: String,
  events: List(or_map_kernel.OrMapEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.OrMapEvent(event)) })
}

fn tag_or_set_events(
  address: String,
  events: List(or_set_kernel.OrSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.OrSetEvent(event)) })
}

fn tag_sequence_events(
  address: String,
  events: List(sequence_kernel.SequenceEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.SequenceEvent(event)) })
}

fn tag_text_events(
  address: String,
  events: List(text_kernel.TextEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TextEvent(event)) })
}

fn tag_g_set_events(
  address: String,
  events: List(g_set_kernel.GSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.GSetEvent(event)) })
}

fn tag_two_p_set_events(
  address: String,
  events: List(two_p_set_kernel.TwoPSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TwoPSetEvent(event)) })
}

fn tag_register_collection_events(
  address: String,
  events: List(register_collection_kernel.RegisterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) {
    #(address, channel.RegisterCollectionEvent(event))
  })
}

fn tag_task_manager_events(
  address: String,
  events: List(task_manager_kernel.TaskManagerEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TaskManagerEvent(event)) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

pub fn get(core: Core, address: String, key: String) -> Result(Json, Nil) {
  case find_channel(core, address) {
    Ok(channel.MapState(kernel)) -> map_kernel.get(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

pub fn has(core: Core, address: String, key: String) -> Bool {
  result.is_ok(get(core, address, key))
}

pub fn size(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Ok(channel.MapState(kernel)) -> map_kernel.size(kernel)
    Ok(_) | Error(Nil) -> 0
  }
}

pub fn keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.MapState(kernel)) -> map_kernel.keys(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn entries(core: Core, address: String) -> List(#(String, Json)) {
  case find_channel(core, address) {
    Ok(channel.MapState(kernel)) -> map_kernel.entries(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

/// The current optimistic value of the counter. The result is `Error(Nil)` when the
/// address does not exist, and when it does not name a counter channel.
pub fn counter_value(core: Core, address: String) -> Result(Int, Nil) {
  case find_channel(core, address) {
    Ok(channel.CounterState(kernel)) -> Ok(kernel.value)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The current optimistic value of the PN-counter. The result is `Error(Nil)` when the
/// address does not exist, and when it does not name a PN-counter channel.
pub fn pn_counter_value(core: Core, address: String) -> Result(Int, Nil) {
  case find_channel(core, address) {
    Ok(channel.PnCounterState(kernel)) -> Ok(pn_counter_kernel.value(kernel))
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The accepted value for `key` in the PactMap at `address`. The result is
/// `Error(Nil)` when the key has no accepted value, because it is still pending or it
/// is absent, and when the address does not name a PactMap channel.
pub fn pact_map_get(
  core: Core,
  address: String,
  key: String,
) -> Result(Json, Nil) {
  case find_channel(core, address) {
    Ok(channel.PactMapState(kernel)) -> pact_map_kernel.get(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The accepted entry for `key`, which is the value with its sequence number.
/// The result is `Error(Nil)` when the key is absent.
pub fn pact_map_get_with_details(
  core: Core,
  address: String,
  key: String,
) -> Result(pact_map_kernel.Accepted, Nil) {
  case find_channel(core, address) {
    Ok(channel.PactMapState(kernel)) ->
      pact_map_kernel.get_with_details(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The pending proposal for `key`, which is its value with the signoff list that
/// it still waits on. The result is `Error(Nil)` when nothing is pending, and when the
/// address does not name a PactMap.
///
/// The kernel freezes the signoff list from the connected roster when the `Set`
/// operation sequences. That list thus names the room at that moment, and not
/// the room now.
pub fn pact_map_pending(
  core: Core,
  address: String,
  key: String,
) -> Result(pact_map_kernel.Pending, Nil) {
  case find_channel(core, address) {
    Ok(channel.PactMapState(kernel)) -> pact_map_kernel.pending(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// Whether `key` has a pending value now, which a client proposed and no room
/// has accepted yet.
pub fn pact_map_is_pending(core: Core, address: String, key: String) -> Bool {
  case find_channel(core, address) {
    Ok(channel.PactMapState(kernel)) -> pact_map_kernel.is_pending(kernel, key)
    Ok(_) | Error(Nil) -> False
  }
}

/// Every key with an accepted pact or a pending pact, sorted.
pub fn pact_map_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.PactMapState(kernel)) -> pact_map_kernel.keys(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

/// The number of items that wait in the queue at `address`. The count does not
/// include an acquired job. The result is `Error(Nil)` when the address does not
/// exist, and when it does not name an ordered collection.
pub fn ordered_size(core: Core, address: String) -> Result(Int, Nil) {
  case find_channel(core, address) {
    Ok(channel.OrderedCollectionState(kernel)) ->
      Ok(ordered_collection_kernel.size(kernel))
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The values in the queue at `address`, which no client acquired yet, front
/// first.
pub fn ordered_queue(core: Core, address: String) -> List(Json) {
  case find_channel(core, address) {
    Ok(channel.OrderedCollectionState(kernel)) ->
      ordered_collection_kernel.summary_queue(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

/// The jobs that clients hold at `address` now, keyed by acquire id and sorted
/// by that id.
pub fn ordered_jobs(
  core: Core,
  address: String,
) -> List(#(String, ordered_collection_kernel.JobEntry)) {
  case find_channel(core, address) {
    Ok(channel.OrderedCollectionState(kernel)) ->
      ordered_collection_kernel.summary_jobs(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn or_map_value(
  core: Core,
  address: String,
  key: String,
) -> Result(or_map_kernel.OrMapValue, Nil) {
  case find_channel(core, address) {
    Ok(channel.OrMapState(kernel)) -> or_map_kernel.get(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

pub fn or_map_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.OrMapState(kernel)) -> or_map_kernel.keys(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn or_map_entries(
  core: Core,
  address: String,
) -> List(#(String, or_map_kernel.OrMapValue)) {
  case find_channel(core, address) {
    Ok(channel.OrMapState(kernel)) -> or_map_kernel.entries(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn or_set_contains(core: Core, address: String, element: String) -> Bool {
  case find_channel(core, address) {
    Ok(channel.OrSetState(kernel)) -> or_set_kernel.contains(kernel, element)
    Ok(_) | Error(Nil) -> False
  }
}

pub fn or_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.OrSetState(kernel)) -> or_set_kernel.values(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn sequence_values(core: Core, address: String) -> List(Json) {
  case find_channel(core, address) {
    Ok(channel.SequenceState(kernel)) -> sequence_kernel.values(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn sequence_length(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Ok(channel.SequenceState(kernel)) -> sequence_kernel.length(kernel)
    Ok(_) | Error(Nil) -> 0
  }
}

/// The current visible optimistic string of the text channel. The result is `""`
/// when the address does not exist, and when it does not name a text
/// channel.
pub fn text_value(core: Core, address: String) -> String {
  case find_channel(core, address) {
    Ok(channel.TextState(kernel)) -> text_kernel.value(kernel)
    Ok(_) | Error(Nil) -> ""
  }
}

/// The current optimistic grapheme count of the text channel. The result is `0`
/// when the address does not exist, and when it does not name a text
/// channel.
pub fn text_length(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Ok(channel.TextState(kernel)) -> text_kernel.length(kernel)
    Ok(_) | Error(Nil) -> 0
  }
}

/// The graphemes in `[start, end)` of the optimistic string of the text channel.
/// The result is an error string when the range `start..end` is invalid, when
/// the address does not exist, and when the address does not name a text
/// channel.
pub fn text_substring(
  core: Core,
  address: String,
  start: Int,
  end: Int,
) -> Result(String, String) {
  case find_channel(core, address) {
    Ok(channel.TextState(kernel)) ->
      case text_kernel.substring(kernel, start, end) {
        Ok(value) -> Ok(value)
        Error(error) -> Error(text_kernel.edit_error_detail(error))
      }
    Ok(_) | Error(Nil) ->
      Error(
        "text substring requires a text channel at "
        <> address
        <> ", found none",
      )
  }
}

/// Create a stable anchor at the gap at `index`. `bias` selects the adjacent
/// grapheme that the anchor binds to. `Before` binds it to the grapheme after
/// the gap, and `After` binds it to the grapheme before the gap. See
/// `text_kernel.Bias`. The result is an error string when the index is out of
/// bounds, when the address does not exist, and when the address does not name a
/// text channel.
pub fn text_anchor_at(
  core: Core,
  address: String,
  index: Int,
  bias: text_kernel.Bias,
) -> Result(text_kernel.TextAnchor, String) {
  case find_channel(core, address) {
    Ok(channel.TextState(kernel)) ->
      case text_kernel.anchor_at(kernel, index, bias) {
        Ok(anchor) -> Ok(anchor)
        Error(error) -> Error(text_kernel.anchor_error_detail(error))
      }
    Ok(_) | Error(Nil) ->
      Error(
        "text anchor_at requires a text channel at "
        <> address
        <> ", found none",
      )
  }
}

/// Resolve an anchor to a current optimistic grapheme index. The result is an
/// error string when the anchor target is stale or unknown, when the address
/// does not exist, and when the address does not name a text channel.
pub fn text_resolve_anchor(
  core: Core,
  address: String,
  anchor: text_kernel.TextAnchor,
) -> Result(Int, String) {
  case find_channel(core, address) {
    Ok(channel.TextState(kernel)) ->
      case text_kernel.resolve_anchor(kernel, anchor) {
        Ok(index) -> Ok(index)
        Error(error) -> Error(text_kernel.anchor_error_detail(error))
      }
    Ok(_) | Error(Nil) ->
      Error(
        "text resolve_anchor requires a text channel at "
        <> address
        <> ", found none",
      )
  }
}

/// An anchor at the start of the text. It always resolves to 0. The function is
/// pure. It needs no `Core` value and no address, because the anchor carries no
/// document state.
pub fn text_start_anchor() -> text_kernel.TextAnchor {
  text_kernel.start_anchor()
}

/// An anchor at the end of the text. It always resolves to the current grapheme
/// count, and it moves as the text becomes longer. The function is pure, the
/// same as `text_start_anchor`.
pub fn text_end_anchor() -> text_kernel.TextAnchor {
  text_kernel.end_anchor()
}

/// Encode an anchor as a self-describing JSON value, for example to send it
/// through presence for a shared cursor.
pub fn text_anchor_to_json(anchor: text_kernel.TextAnchor) -> Json {
  text_kernel.anchor_to_json(anchor)
}

/// Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
/// result is an error string for malformed JSON.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(text_kernel.TextAnchor, String) {
  case text_kernel.anchor_from_json(json_string) {
    Ok(anchor) -> Ok(anchor)
    Error(error) ->
      Error("invalid anchor JSON: " <> format_json_decode_error(error))
  }
}

/// Format a `json.DecodeError` value as a string for a person to read. The
/// function follows the variant pattern of `roost/frame.gleam`.
fn format_json_decode_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(byte) -> "unexpected byte: " <> byte
    json.UnexpectedSequence(bytes) -> "unexpected sequence: " <> bytes
    json.UnableToDecode(errors) ->
      "unable to decode: "
      <> string.join(
        list.map(errors, fn(e) {
          "expected "
          <> e.expected
          <> ", found "
          <> e.found
          <> case e.path {
            [] -> ""
            path -> " at " <> string.join(path, ".")
          }
        }),
        "; ",
      )
  }
}

pub fn g_set_contains(core: Core, address: String, element: String) -> Bool {
  case find_channel(core, address) {
    Ok(channel.GSetState(kernel)) -> g_set_kernel.contains(kernel, element)
    Ok(_) | Error(Nil) -> False
  }
}

pub fn g_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.GSetState(kernel)) -> g_set_kernel.values(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn two_p_set_contains(
  core: Core,
  address: String,
  element: String,
) -> Bool {
  case find_channel(core, address) {
    Ok(channel.TwoPSetState(kernel)) ->
      two_p_set_kernel.contains(kernel, element)
    Ok(_) | Error(Nil) -> False
  }
}

pub fn two_p_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.TwoPSetState(kernel)) -> two_p_set_kernel.values(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

/// An optimistic read of a directory key at `path`, with the pending edits
/// applied.
pub fn directory_get(
  core: Core,
  address: String,
  path: String,
  key: String,
) -> Result(Json, Nil) {
  case find_channel(core, address) {
    Ok(channel.DirectoryState(kernel)) ->
      directory_kernel.get(kernel, path, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

/// The optimistic `#(key, value)` entries of the directory at `path`, in
/// order.
pub fn directory_entries(
  core: Core,
  address: String,
  path: String,
) -> List(#(String, Json)) {
  case find_channel(core, address) {
    Ok(channel.DirectoryState(kernel)) -> directory_kernel.entries(kernel, path)
    Ok(_) | Error(Nil) -> []
  }
}

/// The names of the optimistic child directories of the directory at `path`, in
/// order.
pub fn directory_subdirectories(
  core: Core,
  address: String,
  path: String,
) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.DirectoryState(kernel)) ->
      directory_kernel.subdirectories(kernel, path)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn directory_has_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Bool {
  case find_channel(core, address) {
    Ok(channel.DirectoryState(kernel)) ->
      directory_kernel.has_subdirectory(kernel, path, name)
    Ok(_) | Error(Nil) -> False
  }
}

pub fn register_read(
  core: Core,
  address: String,
  key: String,
  policy: register_collection_kernel.ReadPolicy,
) -> Result(Json, Nil) {
  case find_channel(core, address) {
    Ok(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.read(kernel, key, policy)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

pub fn register_versions(
  core: Core,
  address: String,
  key: String,
) -> Result(List(Json), Nil) {
  case find_channel(core, address) {
    Ok(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.read_versions(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

pub fn register_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Ok(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.keys(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

pub fn get_claim(
  core: Core,
  address: String,
  key: String,
) -> Result(Json, Nil) {
  case find_channel(core, address) {
    Ok(channel.ClaimsState(kernel)) -> claims_kernel.get(kernel, key)
    Ok(_) | Error(Nil) -> Error(Nil)
  }
}

pub fn has_claim(core: Core, address: String, key: String) -> Bool {
  case find_channel(core, address) {
    Ok(channel.ClaimsState(kernel)) -> claims_kernel.has(kernel, key)
    Ok(_) | Error(Nil) -> False
  }
}

pub fn task_manager_assigned(
  core: Core,
  address: String,
  task_id: String,
) -> Bool {
  case find_channel(core, address) {
    Ok(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.assigned(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        True,
      )
    Ok(_) | Error(Nil) -> False
  }
}

pub fn task_manager_queued(
  core: Core,
  address: String,
  task_id: String,
) -> Bool {
  case find_channel(core, address) {
    Ok(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.queued(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        True,
      )
    Ok(_) | Error(Nil) -> False
  }
}

pub fn task_manager_queues(
  core: Core,
  address: String,
) -> List(#(String, List(Int))) {
  case find_channel(core, address) {
    Ok(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.summary_queues(kernel)
    Ok(_) | Error(Nil) -> []
  }
}

fn find_channel(core: Core, address: String) -> Result(ChannelState, Nil) {
  dict.get(core.channels, address)
  |> result.lazy_or(fn() { dict.get(core.detached, address) })
}

fn put_attached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(..core, channels: dict.insert(core.channels, address, state))
}

fn put_detached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(..core, detached: dict.insert(core.detached, address, state))
}

fn add_attached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(
    ..core,
    channels: dict.insert(core.channels, address, state),
    channel_order: list.unique(list.append(core.channel_order, [address])),
  )
}

fn client_id_to_int(client_id: String) -> Int {
  client_id.to_int(client_id)
}
