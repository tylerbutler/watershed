//// Pure edit history for the fixed SharedTree profile.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/types.{type SequencePoint, type TreeError, InvalidHistory}

const max_safe_integer = 9_007_199_254_740_991

const minimum_sequence_number = -9_007_199_254_740_991

pub type Commit {
  Commit(
    revision: fluid_ids.StableId,
    originator: fluid_ids.SessionId,
    change: change.Changeset,
  )
}

pub type SequencedCommit {
  SequencedCommit(commit: Commit, point: SequencePoint)
}

pub type HistoryBase {
  InitialBase
  SequencedBase(point: SequencePoint)
}

pub type PeerBranch {
  PeerBranch(
    originator: fluid_ids.SessionId,
    base: Option(fluid_ids.StableId),
    commits: List(Commit),
  )
}

pub type HistorySnapshot {
  HistorySnapshot(
    base: HistoryBase,
    trunk: List(SequencedCommit),
    peers: List(PeerBranch),
    sequence_number: Int,
    minimum_sequence_number: Int,
  )
}

pub type HistoryView {
  HistoryView(
    sequenced: HistorySnapshot,
    pending: List(Commit),
    longest_branch_length: Int,
  )
}

pub type HistoryUpdate {
  HistoryUpdate(
    history: History,
    delta: Option(forest.Delta),
    trimmed_revisions: List(fluid_ids.StableId),
  )
}

pub type MintRevision(state) =
  fn(state) ->
    Result(#(fluid_ids.StableId, change.IdentityOrder, state), TreeError)

type LocalCommit {
  LocalCommit(original: Commit, current: Commit)
}

pub opaque type History {
  History(
    local_session: fluid_ids.SessionId,
    base: HistoryBase,
    trunk: List(SequencedCommit),
    peers: List(PeerBranch),
    pending: List(LocalCommit),
    sequence_number: Int,
    minimum_sequence_number: Int,
  )
}

pub fn new(local_session: fluid_ids.SessionId) -> History {
  History(
    local_session:,
    base: InitialBase,
    trunk: [],
    peers: [],
    pending: [],
    sequence_number: 0,
    minimum_sequence_number: minimum_sequence_number,
  )
}

pub fn append_local(
  state: History,
  commit: Commit,
) -> Result(HistoryUpdate, TreeError) {
  use _ <- result.try(check(
    commit.originator == state.local_session,
    "local commit originator does not match the local session",
  ))
  use _ <- result.try(check(
    !has_revision(state, commit.revision),
    "local commit revision is already present",
  ))
  use delta <- result.try(
    change.into_delta(change.TaggedChange(
      Some(commit.revision),
      None,
      commit.change,
    )),
  )
  let next =
    History(
      ..state,
      pending: list.append(state.pending, [LocalCommit(commit, commit)]),
    )
  Ok(HistoryUpdate(next, Some(delta), []))
}

pub fn receive(
  state: History,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  let _ = mint
  use _ <- result.try(validate_receive(
    state,
    point,
    reference_sequence_number,
    minimum_sequence_number,
  ))
  case commit.originator == state.local_session {
    False ->
      Error(InvalidHistory("remote history reconciliation is not available"))
    True ->
      receive_local(state, commit, point, minimum_sequence_number, allocation)
  }
}

fn receive_local(
  state: History,
  commit: Commit,
  point: SequencePoint,
  supplied_minimum: Int,
  allocation: allocation,
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  case trunk_commit(state.trunk, commit.revision) {
    Some(existing) -> {
      use _ <- result.try(check(
        existing.commit.originator == commit.originator,
        "duplicate commit originator does not match",
      ))
      let next =
        History(
          ..state,
          sequence_number: int_max(state.sequence_number, point.sequence_number),
          minimum_sequence_number: supplied_minimum,
        )
      Ok(#(HistoryUpdate(next, None, []), allocation))
    }
    None ->
      case state.pending {
        [] ->
          Error(InvalidHistory("local acknowledgement has no pending commit"))
        [LocalCommit(original, current), ..rest] -> {
          use _ <- result.try(check(
            original.revision == commit.revision,
            "local acknowledgement is not for the oldest pending commit",
          ))
          use _ <- result.try(check(
            original.originator == commit.originator,
            "local acknowledgement originator does not match",
          ))
          let sequenced = SequencedCommit(current, point)
          let next =
            History(
              ..state,
              trunk: list.append(state.trunk, [sequenced]),
              pending: rest,
              sequence_number: int_max(
                state.sequence_number,
                point.sequence_number,
              ),
              minimum_sequence_number: supplied_minimum,
            )
          Ok(#(HistoryUpdate(next, None, []), allocation))
        }
      }
  }
}

pub fn advance_minimum(
  state: History,
  sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  let _ = mint
  use _ <- result.try(validate_safe(
    sequence_number,
    "processed sequence number is outside the safe integer range",
  ))
  use _ <- result.try(validate_safe(
    minimum_sequence_number,
    "minimum sequence number is outside the safe integer range",
  ))
  use _ <- result.try(check(
    sequence_number >= state.sequence_number,
    "processed sequence number regresses",
  ))
  use _ <- result.try(check(
    minimum_sequence_number >= state.minimum_sequence_number,
    "minimum sequence number regresses",
  ))
  use _ <- result.try(check(
    minimum_sequence_number <= sequence_number,
    "minimum sequence number exceeds the processed sequence number",
  ))
  let next = History(..state, sequence_number:, minimum_sequence_number:)
  Ok(#(HistoryUpdate(next, None, []), allocation))
}

pub fn pending(state: History) -> List(Commit) {
  list.map(state.pending, fn(entry) { entry.current })
}

pub fn inspect(state: History) -> HistoryView {
  HistoryView(
    sequenced: HistorySnapshot(
      state.base,
      state.trunk,
      state.peers,
      state.sequence_number,
      state.minimum_sequence_number,
    ),
    pending: pending(state),
    longest_branch_length: longest_branch(state),
  )
}

pub fn snapshot(state: History) -> Result(HistorySnapshot, TreeError) {
  use _ <- result.try(check(
    list.is_empty(state.pending),
    "cannot snapshot history with pending local commits",
  ))
  Ok(inspect(state).sequenced)
}

pub fn restore(
  snapshot: HistorySnapshot,
  local_session: fluid_ids.SessionId,
) -> Result(History, TreeError) {
  use _ <- result.try(validate_snapshot(snapshot))
  Ok(History(
    local_session:,
    base: snapshot.base,
    trunk: snapshot.trunk,
    peers: snapshot.peers,
    pending: [],
    sequence_number: snapshot.sequence_number,
    minimum_sequence_number: snapshot.minimum_sequence_number,
  ))
}

pub fn resubmit(
  state: History,
  repair: List(#(fluid_ids.StableId, List(forest.Build))),
) -> Result(List(Commit), TreeError) {
  let _ = state
  let _ = repair
  Error(InvalidHistory("resubmission is not available"))
}

fn validate_receive(
  state: History,
  point: SequencePoint,
  reference_sequence_number: Int,
  supplied_minimum: Int,
) -> Result(Nil, TreeError) {
  use _ <- result.try(validate_point(point))
  use _ <- result.try(validate_safe(
    reference_sequence_number,
    "reference sequence number is outside the safe integer range",
  ))
  use _ <- result.try(validate_safe(
    supplied_minimum,
    "minimum sequence number is outside the safe integer range",
  ))
  use _ <- result.try(check(
    reference_sequence_number <= state.sequence_number,
    "reference sequence number is in unprocessed history",
  ))
  use _ <- result.try(check(
    supplied_minimum >= state.minimum_sequence_number,
    "minimum sequence number regresses",
  ))
  use _ <- result.try(check(
    supplied_minimum <= point.sequence_number,
    "minimum sequence number exceeds the received sequence number",
  ))
  case list.last(state.trunk) {
    Error(Nil) -> Ok(Nil)
    Ok(last) ->
      check(
        compare_points(last.point, point) == order.Lt,
        "received sequence point is not after the trunk head",
      )
  }
}

fn validate_snapshot(snapshot: HistorySnapshot) -> Result(Nil, TreeError) {
  use _ <- result.try(validate_safe(
    snapshot.sequence_number,
    "snapshot sequence number is outside the safe integer range",
  ))
  use _ <- result.try(validate_safe(
    snapshot.minimum_sequence_number,
    "snapshot minimum sequence number is outside the safe integer range",
  ))
  use _ <- result.try(check(
    snapshot.minimum_sequence_number <= snapshot.sequence_number,
    "snapshot minimum sequence number exceeds its sequence number",
  ))
  list.try_fold(snapshot.trunk, None, fn(previous, entry) {
    use _ <- result.try(validate_point(entry.point))
    use _ <- result.try(case previous {
      None -> Ok(Nil)
      Some(point) ->
        check(
          compare_points(point, entry.point) == order.Lt,
          "snapshot trunk points are not ordered",
        )
    })
    Ok(Some(entry.point))
  })
  |> result.map(fn(_) { Nil })
}

fn validate_point(point: SequencePoint) -> Result(Nil, TreeError) {
  use _ <- result.try(validate_safe(
    point.sequence_number,
    "sequence number is outside the safe integer range",
  ))
  use _ <- result.try(validate_safe(
    point.index_in_batch,
    "batch index is outside the safe integer range",
  ))
  check(point.index_in_batch >= 0, "batch index is negative")
}

fn validate_safe(value: Int, detail: String) -> Result(Nil, TreeError) {
  check(value >= -max_safe_integer && value <= max_safe_integer, detail)
}

fn compare_points(left: SequencePoint, right: SequencePoint) -> order.Order {
  case left.sequence_number < right.sequence_number {
    True -> order.Lt
    False ->
      case left.sequence_number > right.sequence_number {
        True -> order.Gt
        False ->
          case left.index_in_batch < right.index_in_batch {
            True -> order.Lt
            False ->
              case left.index_in_batch > right.index_in_batch {
                True -> order.Gt
                False -> order.Eq
              }
          }
      }
  }
}

fn has_revision(state: History, revision: fluid_ids.StableId) -> Bool {
  trunk_commit(state.trunk, revision) != None
  || list.any(state.pending, fn(entry) { entry.original.revision == revision })
  || list.any(state.peers, fn(peer) {
    list.any(peer.commits, fn(commit) { commit.revision == revision })
  })
}

fn trunk_commit(
  trunk: List(SequencedCommit),
  revision: fluid_ids.StableId,
) -> Option(SequencedCommit) {
  list.find(trunk, fn(entry) { entry.commit.revision == revision })
  |> result.map(Some)
  |> result.unwrap(None)
}

fn longest_branch(state: History) -> Int {
  list.fold(state.peers, list.length(state.pending), fn(longest, peer) {
    int_max(longest, list.length(peer.commits))
  })
}

fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}

fn check(valid: Bool, detail: String) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(InvalidHistory(detail))
  }
}
