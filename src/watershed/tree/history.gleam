//// Pure edit history for the fixed SharedTree profile.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/shared_change
import watershed/tree/types.{
  type CheckoutSelector, type LocalCheckoutId, type RevertibleId,
  type SequencePoint, type TreeCommitKind, type TreeError, DocumentCheckout,
  InvalidHistory, LocalCheckout, LocalCheckoutId, RevertibleId,
}

const max_safe_integer = 9_007_199_254_740_991

const minimum_sequence_number = -9_007_199_254_740_991

pub type Commit {
  Commit(
    revision: fluid_ids.StableId,
    originator: fluid_ids.SessionId,
    change: shared_change.Changeset,
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
    replayed_receipts: List(SequencePoint),
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
    effects: List(shared_change.Effect),
    sequenced_effects: List(shared_change.Effect),
    trimmed_revisions: List(fluid_ids.StableId),
  )
}

pub type RevertAuthoring {
  RevertAuthoring(target: Commit, inverse: Commit, kind: TreeCommitKind)
}

pub type LocalBranch {
  LocalBranch(
    id: LocalCheckoutId,
    base: Option(fluid_ids.StableId),
    commits: List(Commit),
  )
}

pub type MintRevision(state) =
  fn(state) ->
    Result(#(fluid_ids.StableId, change.IdentityOrder, state), TreeError)

type LocalCommit {
  LocalCommit(
    original: BranchCommit,
    current: BranchCommit,
    authoring_context: List(Commit),
  )
}

type BranchCommit {
  BranchCommit(node_id: Int, commit: Commit)
}

type BranchBase {
  Sentinel
  Revision(fluid_ids.StableId)
}

type PeerState {
  PeerState(
    originator: fluid_ids.SessionId,
    base: BranchBase,
    commits: List(BranchCommit),
  )
}

type LocalState {
  LocalState(
    id: LocalCheckoutId,
    base: BranchBase,
    pin: HistoryBase,
    commits: List(BranchCommit),
  )
}

type RollbackEntry {
  RollbackEntry(
    source_node: Int,
    revision: fluid_ids.StableId,
    change: shared_change.Changeset,
  )
}

type RevertibleRecord {
  RevertibleRecord(
    id: RevertibleId,
    revision: fluid_ids.StableId,
    kind: TreeCommitKind,
    base: BranchBase,
    commits: List(BranchCommit),
  )
}

type RetainedReceipt {
  RetainedReceipt(
    revision: fluid_ids.StableId,
    commit: Option(Commit),
    point: SequencePoint,
    reference_sequence_number: Option(Int),
    minimum_sequence_number: Option(Int),
  )
}

type RebaseResult {
  RebaseResult(
    base: BranchBase,
    commits: List(BranchCommit),
    net_change: Option(shared_change.Changeset),
  )
}

type LocalRebaseResult {
  LocalRebaseResult(
    commits: List(BranchCommit),
    source_commits: List(BranchCommit),
    net_change: Option(shared_change.Changeset),
  )
}

type RepairMode {
  RequiredRepair
  OptionalRepair
}

pub opaque type History {
  History(
    local_session: fluid_ids.SessionId,
    base: HistoryBase,
    trunk: List(SequencedCommit),
    peers: List(PeerState),
    pending: List(LocalCommit),
    local_base: Option(BranchBase),
    local_authored_context: List(Commit),
    rollbacks: List(RollbackEntry),
    receipts: List(RetainedReceipt),
    replayed_receipts: List(SequencePoint),
    revertibles: List(RevertibleRecord),
    local_checkouts: List(LocalState),
    next_node_id: Int,
    next_revertible_id: Int,
    next_local_checkout_id: Int,
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
    local_base: None,
    local_authored_context: [],
    rollbacks: [],
    receipts: [],
    replayed_receipts: [],
    revertibles: [],
    local_checkouts: [],
    next_node_id: 0,
    next_revertible_id: 0,
    next_local_checkout_id: 0,
    sequence_number: 0,
    minimum_sequence_number: minimum_sequence_number,
  )
}

pub fn rebind_identity_order(
  state: History,
  identity_order: change.IdentityOrder,
) -> Result(History, TreeError) {
  use trunk <- result.try(
    list.try_map(state.trunk, fn(entry) {
      use commit <- result.try(rebind_commit(entry.commit, identity_order))
      Ok(SequencedCommit(..entry, commit:))
    }),
  )
  use peers <- result.try(
    list.try_map(state.peers, fn(peer) {
      use commits <- result.try(
        list.try_map(peer.commits, fn(entry) {
          use commit <- result.try(rebind_commit(entry.commit, identity_order))
          Ok(BranchCommit(..entry, commit:))
        }),
      )
      Ok(PeerState(..peer, commits:))
    }),
  )
  use pending <- result.try(
    list.try_map(state.pending, fn(entry) {
      use original <- result.try(rebind_commit(
        entry.original.commit,
        identity_order,
      ))
      use current <- result.try(rebind_commit(
        entry.current.commit,
        identity_order,
      ))
      use authoring_context <- result.try(
        list.try_map(entry.authoring_context, fn(commit) {
          rebind_commit(commit, identity_order)
        }),
      )
      Ok(LocalCommit(
        BranchCommit(..entry.original, commit: original),
        BranchCommit(..entry.current, commit: current),
        authoring_context,
      ))
    }),
  )
  use local_authored_context <- result.try(
    list.try_map(state.local_authored_context, fn(commit) {
      rebind_commit(commit, identity_order)
    }),
  )
  use rollbacks <- result.try(
    list.try_map(state.rollbacks, fn(entry) {
      use bound <- result.try(shared_change.rebind_identity_order(
        entry.change,
        identity_order,
        outer_revisions(entry.revision, entry.change),
      ))
      Ok(RollbackEntry(..entry, change: bound))
    }),
  )
  use receipts <- result.try(
    list.try_map(state.receipts, fn(entry) {
      use commit <- result.try(case entry.commit {
        None -> Ok(None)
        Some(commit) ->
          rebind_commit(commit, identity_order) |> result.map(Some)
      })
      Ok(RetainedReceipt(..entry, commit:))
    }),
  )
  use revertibles <- result.try(
    list.try_map(state.revertibles, fn(record) {
      use commits <- result.try(
        list.try_map(record.commits, fn(entry) {
          use commit <- result.try(rebind_commit(entry.commit, identity_order))
          Ok(BranchCommit(..entry, commit:))
        }),
      )
      Ok(RevertibleRecord(..record, commits:))
    }),
  )
  use local_checkouts <- result.try(
    list.try_map(state.local_checkouts, fn(local) {
      use commits <- result.try(
        list.try_map(local.commits, fn(entry) {
          use commit <- result.try(rebind_commit(entry.commit, identity_order))
          Ok(BranchCommit(..entry, commit:))
        }),
      )
      Ok(LocalState(..local, commits:))
    }),
  )
  Ok(
    History(
      ..state,
      trunk:,
      peers:,
      pending:,
      local_authored_context:,
      rollbacks:,
      receipts:,
      revertibles:,
      local_checkouts:,
    ),
  )
}

pub fn identity_revisions(state: History) -> List(fluid_ids.StableId) {
  let commits =
    list.append(
      list.map(state.trunk, fn(entry) { entry.commit }),
      list.append(
        list.flat_map(state.peers, fn(peer) {
          list.map(peer.commits, fn(entry) { entry.commit })
        }),
        list.append(
          list.flat_map(state.pending, fn(entry) {
            [
              entry.original.commit,
              entry.current.commit,
              ..entry.authoring_context
            ]
          }),
          state.local_authored_context,
        ),
      ),
    )
  let commits =
    list.append(
      commits,
      list.flat_map(state.receipts, fn(entry) {
        case entry.commit {
          None -> []
          Some(commit) -> [commit]
        }
      }),
    )
  let commits =
    list.append(
      commits,
      list.flat_map(state.local_checkouts, fn(local) {
        list.map(local.commits, fn(entry) { entry.commit })
      }),
    )
  let commits =
    list.append(
      commits,
      list.flat_map(state.revertibles, fn(record) {
        list.map(record.commits, fn(entry) { entry.commit })
      }),
    )
  let revisions =
    list.append(
      history_revisions(state),
      list.flat_map(commits, fn(commit) {
        shared_change.identity_revisions(commit.change)
      }),
    )
  list.append(
    revisions,
    list.flat_map(state.rollbacks, fn(entry) {
      [entry.revision, ..shared_change.identity_revisions(entry.change)]
    }),
  )
  |> list.unique
}

fn rebind_commit(
  commit: Commit,
  identity_order: change.IdentityOrder,
) -> Result(Commit, TreeError) {
  use bound <- result.try(shared_change.rebind_identity_order(
    commit.change,
    identity_order,
    outer_revisions(commit.revision, commit.change),
  ))
  Ok(Commit(..commit, change: bound))
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
  use effects <- result.try(shared_change.effects(tagged_commit(commit)))
  let node = BranchCommit(state.next_node_id, commit)
  let authoring_context = case list.last(state.pending) {
    Ok(previous) ->
      list.append(previous.authoring_context, [previous.current.commit])
    Error(Nil) -> state.local_authored_context
  }

  let next =
    History(
      ..state,
      pending: list.append(state.pending, [
        LocalCommit(node, node, authoring_context),
      ]),
      local_base: case state.pending {
        [] -> Some(trunk_head(state.trunk))
        _ -> state.local_base
      },
      local_authored_context: case state.pending {
        [] -> []
        _ -> state.local_authored_context
      },
      next_node_id: state.next_node_id + 1,
    )
  Ok(HistoryUpdate(next, effects, [], []))
}

pub fn fork_local(
  state: History,
  source: CheckoutSelector,
) -> Result(#(History, LocalCheckoutId), TreeError) {
  use #(base, pin, commits) <- result.try(checkout_position(state, source))
  let id = LocalCheckoutId(state.next_local_checkout_id)
  Ok(#(
    History(
      ..state,
      local_checkouts: [
        LocalState(id, base, pin, commits),
        ..state.local_checkouts
      ],
      next_local_checkout_id: state.next_local_checkout_id + 1,
    ),
    id,
  ))
}

pub fn inspect_local(
  state: History,
  id: LocalCheckoutId,
) -> Result(LocalBranch, TreeError) {
  use local <- result.try(require_local_checkout(state.local_checkouts, id))
  Ok(local_branch(local))
}

pub fn dispose_local(
  state: History,
  id: LocalCheckoutId,
) -> Result(History, TreeError) {
  Ok(
    History(
      ..state,
      local_checkouts: list.filter(state.local_checkouts, fn(local) {
        local.id != id
      }),
    ),
  )
}

pub fn append_local_checkout(
  state: History,
  id: LocalCheckoutId,
  commit: Commit,
) -> Result(HistoryUpdate, TreeError) {
  use local <- result.try(require_local_checkout(state.local_checkouts, id))
  use _ <- result.try(check(
    commit.originator == state.local_session,
    "local checkout commit originator does not match the local session",
  ))
  use _ <- result.try(check(
    !has_revision(state, commit.revision),
    "local checkout commit revision is already present",
  ))
  use effects <- result.try(shared_change.effects(tagged_commit(commit)))
  let node = BranchCommit(state.next_node_id, commit)
  let updated = LocalState(..local, commits: list.append(local.commits, [node]))
  Ok(
    HistoryUpdate(
      History(
        ..state,
        local_checkouts: replace_local_checkout(state.local_checkouts, updated),
        next_node_id: state.next_node_id + 1,
      ),
      effects,
      [],
      [],
    ),
  )
}

pub fn rebase_local(
  state: History,
  source_id: LocalCheckoutId,
  target: CheckoutSelector,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  use source <- result.try(require_local_checkout(
    state.local_checkouts,
    source_id,
  ))
  case target {
    LocalCheckout(id) if id == source_id ->
      Ok(#(HistoryUpdate(state, [], [], []), allocation))
    _ -> {
      use #(target_base, target_pin, target_commits) <- result.try(
        checkout_position(state, target),
      )
      let target_state =
        LocalState(source_id, target_base, target_pin, target_commits)
      use #(rebased, allocation, rollbacks, next_node_id) <- result.try(
        reconcile_local_ancestry(state, source, target_state, allocation, mint),
      )
      use effects <- result.try(effects_optional(rebased.net_change))
      let updated =
        LocalState(source.id, target_base, target_pin, rebased.commits)
      let next =
        History(
          ..state,
          local_checkouts: replace_local_checkout(
            state.local_checkouts,
            updated,
          ),
          rollbacks:,
          next_node_id:,
        )
      Ok(#(HistoryUpdate(next, effects, [], []), allocation))
    }
  }
}

pub fn merge_local(
  state: History,
  target: CheckoutSelector,
  source_id: LocalCheckoutId,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, List(Commit), allocation), TreeError) {
  use source <- result.try(require_local_checkout(
    state.local_checkouts,
    source_id,
  ))
  case target {
    LocalCheckout(id) if id == source_id ->
      Ok(#(HistoryUpdate(state, [], [], []), [], allocation))
    DocumentCheckout ->
      Error(InvalidHistory("document ancestry merge is not available"))
    LocalCheckout(target_id) -> {
      use target_state <- result.try(require_local_checkout(
        state.local_checkouts,
        target_id,
      ))
      use #(rebased, allocation, rollbacks, next_node_id) <- result.try(
        reconcile_local_ancestry(state, source, target_state, allocation, mint),
      )
      let surviving =
        list.map(rebased.source_commits, fn(commit) { commit.commit })
      use net_change <- result.try(
        surviving
        |> list.map(tagged_commit)
        |> compose_optional,
      )
      use effects <- result.try(effects_optional(net_change))
      let updated =
        LocalState(
          target_id,
          target_state.base,
          target_state.pin,
          rebased.commits,
        )
      let next =
        History(
          ..state,
          local_checkouts: replace_local_checkout(
            state.local_checkouts,
            updated,
          ),
          rollbacks:,
          next_node_id:,
        )
      Ok(#(HistoryUpdate(next, effects, [], []), surviving, allocation))
    }
  }
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
  use _ <- result.try(validate_receive_fields(
    state,
    point,
    reference_sequence_number,
    minimum_sequence_number,
  ))
  use #(update, allocation) <- result.try(
    case trunk_commit(state.trunk, commit.revision) {
      Some(existing) ->
        receive_duplicate(
          state,
          existing,
          commit,
          point,
          reference_sequence_number,
          minimum_sequence_number,
          allocation,
        )
      None -> {
        use _ <- result.try(check(
          minimum_sequence_number >= state.minimum_sequence_number,
          "minimum sequence number regresses",
        ))
        use _ <- result.try(validate_new_receive_order(state, point))
        case commit.originator == state.local_session {
          False ->
            receive_remote(
              state,
              commit,
              point,
              reference_sequence_number,
              minimum_sequence_number,
              allocation,
              mint,
            )
          True ->
            receive_local(
              state,
              commit,
              point,
              reference_sequence_number,
              minimum_sequence_number,
              allocation,
            )
        }
      }
    },
  )
  use #(next, trimmed, allocation) <- result.try(trim_history(
    update.history,
    allocation,
    mint,
  ))
  Ok(#(
    HistoryUpdate(
      prune_rollbacks(next),
      update.effects,
      update.sequenced_effects,
      trimmed,
    ),
    allocation,
  ))
}

fn receive_duplicate(
  state: History,
  existing: SequencedCommit,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  use receipt <- result.try(
    case
      list.find(state.receipts, fn(receipt) {
        receipt.revision == commit.revision
      })
    {
      Ok(receipt) -> Ok(receipt)
      Error(Nil) ->
        Error(InvalidHistory("duplicate commit receipt metadata is missing"))
    },
  )
  use expected_commit <- result.try(case receipt.commit {
    Some(commit) -> Ok(commit)
    None ->
      Error(InvalidHistory(
        "duplicate commit contents are unavailable after restore",
      ))
  })
  use _ <- result.try(check(
    expected_commit == commit,
    "duplicate commit contents do not match",
  ))
  case existing.point == point {
    False ->
      receive_replayed_duplicate(
        state,
        existing.commit,
        commit,
        point,
        reference_sequence_number,
        minimum_sequence_number,
        allocation,
      )
    True -> {
      use expected_reference <- result.try(
        case receipt.reference_sequence_number {
          Some(reference) -> Ok(reference)
          None ->
            Error(InvalidHistory(
              "duplicate commit reference is unavailable after restore",
            ))
        },
      )
      use _ <- result.try(check(
        expected_reference == reference_sequence_number,
        "duplicate commit reference does not match",
      ))
      use _ <- result.try(check(
        receipt.minimum_sequence_number == Some(minimum_sequence_number),
        "duplicate commit minimum sequence number does not match",
      ))
      Ok(#(HistoryUpdate(state, [], [], []), allocation))
    }
  }
}

fn receive_replayed_duplicate(
  state: History,
  retained: Commit,
  received: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  supplied_minimum: Int,
  allocation: allocation,
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  use _ <- result.try(check(
    supplied_minimum >= state.minimum_sequence_number,
    "minimum sequence number regresses",
  ))
  use _ <- result.try(validate_new_receive_order(state, point))
  let next_trunk = list.append(state.trunk, [SequencedCommit(retained, point)])
  let receipt =
    RetainedReceipt(
      received.revision,
      Some(received),
      point,
      Some(reference_sequence_number),
      Some(supplied_minimum),
    )
  let next =
    History(
      ..state,
      trunk: next_trunk,
      local_base: case state.pending {
        [] -> None
        _ -> Some(Revision(retained.revision))
      },
      receipts: replace_receipt(state.receipts, receipt),
      replayed_receipts: list.append(state.replayed_receipts, [point]),
      sequence_number: int_max(state.sequence_number, point.sequence_number),
      minimum_sequence_number: supplied_minimum,
    )
  Ok(#(HistoryUpdate(next, [], [], []), allocation))
}

fn receive_local(
  state: History,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  supplied_minimum: Int,
  allocation: allocation,
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  case state.pending {
    [] -> Error(InvalidHistory("local acknowledgement has no pending commit"))
    [LocalCommit(original, current, _), ..rest] -> {
      use _ <- result.try(check(
        original.commit.revision == commit.revision,
        "local acknowledgement is not for the oldest pending commit",
      ))
      use _ <- result.try(check(
        original.commit.originator == commit.originator,
        "local acknowledgement originator does not match",
      ))
      let sequenced = SequencedCommit(current.commit, point)
      let next =
        History(
          ..state,
          trunk: list.append(state.trunk, [sequenced]),
          pending: rest,
          local_base: case rest {
            [] -> None
            _ -> Some(Revision(current.commit.revision))
          },
          local_authored_context: case rest {
            [] -> []
            _ -> list.append(state.local_authored_context, [original.commit])
          },
          receipts: list.append(state.receipts, [
            RetainedReceipt(
              commit.revision,
              Some(commit),
              point,
              Some(reference_sequence_number),
              Some(supplied_minimum),
            ),
          ]),
          sequence_number: int_max(state.sequence_number, point.sequence_number),
          minimum_sequence_number: supplied_minimum,
        )
      use sequenced_effects <- result.try(
        shared_change.effects(tagged_commit(current.commit)),
      )
      Ok(#(HistoryUpdate(next, [], sequenced_effects, []), allocation))
    }
  }
}

fn receive_remote(
  state: History,
  commit: Commit,
  point: SequencePoint,
  reference_sequence_number: Int,
  supplied_minimum: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, allocation), TreeError) {
  use reference <- result.try(reference_base(state, reference_sequence_number))
  let peer =
    peer_state(state.peers, commit.originator)
    |> option.unwrap(PeerState(commit.originator, reference, []))
  let known_revisions = [commit.revision, ..history_revisions(state)]
  use #(authored_peer, allocation, rollbacks, next_node_id) <- result.try(
    rebase_branch(
      peer.base,
      peer.commits,
      state.trunk,
      reference,
      state.rollbacks,
      known_revisions,
      state.next_node_id,
      allocation,
      mint,
    ),
  )
  let incoming = BranchCommit(next_node_id, commit)
  let authored_commits = list.append(authored_peer.commits, [incoming])
  use #(merged_peer, allocation, rollbacks, next_node_id) <- result.try(
    rebase_branch(
      authored_peer.base,
      authored_commits,
      state.trunk,
      trunk_head(state.trunk),
      rollbacks,
      known_revisions,
      next_node_id + 1,
      allocation,
      mint,
    ),
  )
  use merged <- result.try(single_incoming_commit(merged_peer.commits, commit))
  let next_trunk = case merged {
    None -> state.trunk
    Some(merged) ->
      list.append(state.trunk, [SequencedCommit(merged.commit, point)])
  }
  let peer = case merged {
    Some(merged) if merged.node_id == incoming.node_id ->
      PeerState(commit.originator, Revision(incoming.commit.revision), [])
    _ -> PeerState(commit.originator, authored_peer.base, authored_commits)
  }
  let peers = replace_peer(state.peers, peer)
  use #(pending, local_base, effects, allocation, rollbacks, next_node_id) <- result.try(
    rebase_pending(
      state,
      next_trunk,
      rollbacks,
      known_revisions,
      next_node_id,
      allocation,
      mint,
    ),
  )
  let next =
    History(
      ..state,
      trunk: next_trunk,
      peers: peers,
      pending: pending,
      local_base: local_base,
      rollbacks: rollbacks,
      receipts: list.append(state.receipts, [
        RetainedReceipt(
          commit.revision,
          Some(commit),
          point,
          Some(reference_sequence_number),
          Some(supplied_minimum),
        ),
      ]),
      next_node_id: next_node_id,
      sequence_number: int_max(state.sequence_number, point.sequence_number),
      minimum_sequence_number: supplied_minimum,
    )
  use sequenced_effects <- result.try(case merged {
    None -> Ok([])
    Some(merged) -> shared_change.effects(tagged_branch_commit(merged))
  })
  Ok(#(HistoryUpdate(next, effects, sequenced_effects, []), allocation))
}

fn rebase_pending(
  state: History,
  next_trunk: List(SequencedCommit),
  rollbacks: List(RollbackEntry),
  known_revisions: List(fluid_ids.StableId),
  next_node_id: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(
  #(
    List(LocalCommit),
    Option(BranchBase),
    List(shared_change.Effect),
    allocation,
    List(RollbackEntry),
    Int,
  ),
  TreeError,
) {
  case state.pending {
    [] -> {
      let added =
        next_trunk
        |> list.drop(list.length(state.trunk))
        |> list.map(fn(entry) { tagged_commit(entry.commit) })
      use net_change <- result.try(compose_optional(added))
      use effects <- result.try(effects_optional(net_change))
      Ok(#([], None, effects, allocation, rollbacks, next_node_id))
    }
    pending -> {
      use base <- result.try(require_local_base(state.local_base))
      let current = list.map(pending, fn(entry) { entry.current })
      use #(rebased, allocation, rollbacks, next_node_id) <- result.try(
        rebase_branch(
          base,
          current,
          next_trunk,
          trunk_head(next_trunk),
          rollbacks,
          known_revisions,
          next_node_id,
          allocation,
          mint,
        ),
      )
      use pending <- result.try(replace_current_pending(
        pending,
        rebased.commits,
      ))
      use effects <- result.try(effects_optional(rebased.net_change))
      Ok(#(
        pending,
        Some(rebased.base),
        effects,
        allocation,
        rollbacks,
        next_node_id,
      ))
    }
  }
}

fn rebase_branch(
  source_base: BranchBase,
  source_commits: List(BranchCommit),
  target: List(SequencedCommit),
  up_to: BranchBase,
  rollbacks: List(RollbackEntry),
  known_revisions: List(fluid_ids.StableId),
  next_node_id: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(RebaseResult, allocation, List(RollbackEntry), Int), TreeError) {
  use target_path <- result.try(commits_after_base(target, source_base))
  use up_to_index <- result.try(branch_base_index(
    target_path,
    source_base,
    up_to,
  ))
  let matched_index = case up_to_index {
    -1 -> -1
    _ ->
      advanced_base_index(
        list.drop(target_path, up_to_index + 1),
        source_commits,
        up_to_index,
        up_to_index + 1,
        up_to_index,
      )
  }
  let new_base = case item_at(target_path, matched_index) {
    Some(commit) -> Revision(commit.commit.revision)
    None -> source_base
  }
  let target_commits =
    target_path
    |> list.take(matched_index + 1)
    |> list.map(fn(entry) { entry.commit })
  let surviving_source =
    list.filter(source_commits, fn(commit) {
      !contains_revision(target_commits, commit.commit.revision)
    })
  let target_rebase_path = remove_common_prefix(source_commits, target_commits)
  let source_rebase_path =
    remove_source_common_prefix(source_commits, target_commits)
  rebase_paths(
    new_base,
    surviving_source,
    target_rebase_path,
    source_rebase_path,
    up_to_index != -1,
    rollbacks,
    known_revisions,
    next_node_id,
    allocation,
    mint,
  )
}

fn rebase_paths(
  new_base: BranchBase,
  surviving_source: List(BranchCommit),
  target_rebase_path: List(Commit),
  source_rebase_path: List(BranchCommit),
  reparent_unchanged: Bool,
  rollbacks: List(RollbackEntry),
  known_revisions: List(fluid_ids.StableId),
  next_node_id: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(RebaseResult, allocation, List(RollbackEntry), Int), TreeError) {
  case target_rebase_path {
    [] -> {
      let #(surviving_source, next_node_id) = case reparent_unchanged {
        False -> #(surviving_source, next_node_id)
        True -> reparent_commits(surviving_source, next_node_id)
      }
      Ok(#(
        RebaseResult(new_base, surviving_source, None),
        allocation,
        rollbacks,
        next_node_id,
      ))
    }
    _ -> {
      let edits = list.map(target_rebase_path, tagged_commit)
      let revision_edits =
        list.append(edits, list.map(source_rebase_path, tagged_branch_commit))
      use #(rebased, edits, _, allocation, rollbacks, next_node_id) <- result.try(
        list.try_fold(
          source_rebase_path,
          #([], edits, revision_edits, allocation, rollbacks, next_node_id),
          fn(state, commit) {
            use #(rollback, allocation, rollbacks) <- result.try(
              rollback_for(commit, state.4, known_revisions, state.3, mint)
              |> history_error("cannot create rollback: "),
            )
            let rollback_tagged =
              shared_change.TaggedChange(
                Some(rollback.revision),
                Some(commit.commit.revision),
                rollback.change,
              )
            use #(rebased_commits, edits, next_node_id) <- result.try(
              case
                branch_contains_revision(
                  surviving_source,
                  commit.commit.revision,
                )
              {
                False -> Ok(#(state.0, [rollback_tagged, ..state.1], state.5))
                True -> {
                  use over <- result.try(
                    shared_change.compose(state.1)
                    |> history_error("cannot compose rebase target: "),
                  )
                  use context <- result.try(rebase_context(state.2))
                  use rebased <- result.try(
                    shared_change.rebase(
                      tagged_branch_commit(commit),
                      shared_change.TaggedChange(None, None, over),
                      context,
                    )
                    |> history_error("cannot rebase source commit: "),
                  )
                  let current = Commit(..commit.commit, change: rebased)
                  let current_node = BranchCommit(state.5, current)
                  Ok(#(
                    list.append(state.0, [current_node]),
                    [
                      rollback_tagged,
                      shared_change.TaggedChange(None, None, over),
                      tagged_commit(current),
                    ],
                    state.5 + 1,
                  ))
                }
              },
            )
            Ok(#(
              rebased_commits,
              edits,
              [rollback_tagged, ..state.2],
              allocation,
              rollbacks,
              next_node_id,
            ))
          },
        ),
      )
      use net_change <- result.try(
        shared_change.compose(edits)
        |> history_error("cannot compose branch reconciliation: "),
      )
      Ok(#(
        RebaseResult(new_base, rebased, Some(net_change)),
        allocation,
        rollbacks,
        next_node_id,
      ))
    }
  }
}

fn reconcile_local_ancestry(
  state: History,
  source: LocalState,
  target: LocalState,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(
  #(LocalRebaseResult, allocation, List(RollbackEntry), Int),
  TreeError,
) {
  use source_ancestry <- result.try(local_ancestry(state, source))
  use target_ancestry <- result.try(local_ancestry(state, target))
  let #(source_path, target_path) =
    remove_common_ancestry(source_ancestry, target_ancestry)
  let #(full_source_path, next_node_id) =
    materialize_branch_commits(source_path, source.commits, state.next_node_id)
  let surviving_source =
    list.filter(full_source_path, fn(commit) {
      !contains_revision(target_path, commit.commit.revision)
    })
  use #(rebased, allocation, rollbacks, next_node_id) <- result.try(
    rebase_paths(
      target.base,
      surviving_source,
      target_path,
      full_source_path,
      False,
      state.rollbacks,
      history_revisions(state),
      next_node_id,
      allocation,
      mint,
    ),
  )
  Ok(#(
    LocalRebaseResult(
      list.append(target.commits, rebased.commits),
      rebased.commits,
      rebased.net_change,
    ),
    allocation,
    rollbacks,
    next_node_id,
  ))
}

fn local_ancestry(
  state: History,
  local: LocalState,
) -> Result(List(Commit), TreeError) {
  use base <- result.try(commits_through_pin(state, local.pin))
  Ok(list.append(base, list.map(local.commits, fn(commit) { commit.commit })))
}

fn remove_common_ancestry(
  source: List(Commit),
  target: List(Commit),
) -> #(List(Commit), List(Commit)) {
  case source, target {
    [source, ..source_rest], [target, ..target_rest] ->
      case source == target {
        True -> remove_common_ancestry(source_rest, target_rest)
        False -> #([source, ..source_rest], [target, ..target_rest])
      }
    _, _ -> #(source, target)
  }
}

fn materialize_branch_commits(
  commits: List(Commit),
  existing: List(BranchCommit),
  next_node_id: Int,
) -> #(List(BranchCommit), Int) {
  case commits {
    [] -> #([], next_node_id)
    [commit, ..rest] -> {
      let #(node, next_node_id) = case
        list.find(existing, fn(entry) { entry.commit == commit })
      {
        Ok(entry) -> #(entry, next_node_id)
        Error(Nil) -> #(BranchCommit(next_node_id, commit), next_node_id + 1)
      }
      let #(rest, next_node_id) =
        materialize_branch_commits(rest, existing, next_node_id)
      #([node, ..rest], next_node_id)
    }
  }
}

fn reparent_commits(
  commits: List(BranchCommit),
  next_node_id: Int,
) -> #(List(BranchCommit), Int) {
  case commits {
    [] -> #([], next_node_id)
    [first, ..rest] -> {
      let node = BranchCommit(next_node_id, first.commit)
      let #(rest, next_node_id) = reparent_commits(rest, next_node_id + 1)
      #([node, ..rest], next_node_id)
    }
  }
}

fn rollback_for(
  commit: BranchCommit,
  rollbacks: List(RollbackEntry),
  known_revisions: List(fluid_ids.StableId),
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(RollbackEntry, allocation, List(RollbackEntry)), TreeError) {
  case list.find(rollbacks, fn(entry) { entry.source_node == commit.node_id }) {
    Ok(entry) -> Ok(#(entry, allocation, rollbacks))
    Error(Nil) -> {
      use #(revision, identity_order, allocation) <- result.try(mint(allocation))
      use _ <- result.try(check(
        !list.contains(known_revisions, revision)
          && !list.any(rollbacks, fn(entry) { entry.revision == revision }),
        "rollback revision is already in use",
      ))
      use bound <- result.try(shared_change.rebind_identity_order(
        commit.commit.change,
        identity_order,
        [
          revision,
          ..outer_revisions(commit.commit.revision, commit.commit.change)
        ]
          |> list.unique,
      ))
      use inverse <- result.try(shared_change.invert(
        shared_change.TaggedChange(Some(commit.commit.revision), None, bound),
        True,
        revision,
      ))
      let entry = RollbackEntry(commit.node_id, revision, inverse)
      Ok(#(entry, allocation, [entry, ..rollbacks]))
    }
  }
}

fn rebase_context(
  tagged: List(shared_change.TaggedChange),
) -> Result(change.RebaseContext, TreeError) {
  use revisions <- result.try(
    list.try_fold(tagged, [], fn(revisions, tagged) {
      list.try_fold(
        shared_change.revision_infos(tagged),
        revisions,
        add_revision_info,
      )
    }),
  )
  change.rebase_context(revisions)
}

fn add_revision_info(
  revisions: List(change.RevisionInfo),
  info: change.RevisionInfo,
) -> Result(List(change.RevisionInfo), TreeError) {
  case
    list.find(revisions, fn(existing) { existing.revision == info.revision })
  {
    Error(Nil) -> Ok(list.append(revisions, [info]))
    Ok(existing) ->
      case existing.rollback_of == info.rollback_of {
        True -> Ok(revisions)
        False ->
          Error(InvalidHistory("rebase rollback metadata does not match"))
      }
  }
}

fn advanced_base_index(
  target: List(SequencedCommit),
  source: List(BranchCommit),
  up_to_index: Int,
  index: Int,
  matched: Int,
) -> Int {
  case target {
    [] -> matched
    [first, ..rest] -> {
      let found = branch_contains_revision(source, first.commit.revision)
      case found, index > up_to_index {
        True, _ ->
          advanced_base_index(rest, source, up_to_index, index + 1, index)
        False, True -> matched
        False, False ->
          advanced_base_index(rest, source, up_to_index, index + 1, matched)
      }
    }
  }
}

fn commits_after_base(
  target: List(SequencedCommit),
  base: BranchBase,
) -> Result(List(SequencedCommit), TreeError) {
  case base {
    Sentinel -> Ok(target)
    Revision(revision) -> commits_after_revision(target, revision)
  }
}

fn commits_after_revision(
  target: List(SequencedCommit),
  revision: fluid_ids.StableId,
) -> Result(List(SequencedCommit), TreeError) {
  case target {
    [] -> Error(InvalidHistory("branch base is not retained on the trunk"))
    [first, ..rest] ->
      case first.commit.revision == revision {
        True ->
          case commits_after_revision(rest, revision) {
            Ok(after) -> Ok(after)
            Error(_) -> Ok(rest)
          }
        False -> commits_after_revision(rest, revision)
      }
  }
}

fn branch_base_index(
  target: List(SequencedCommit),
  source_base: BranchBase,
  base: BranchBase,
) -> Result(Int, TreeError) {
  case base == source_base {
    True -> Ok(-1)
    False ->
      case base {
        Sentinel ->
          case source_base {
            Revision(_) -> Ok(-1)
            Sentinel ->
              Error(InvalidHistory(
                "target branch base precedes the source base",
              ))
          }
        Revision(revision) ->
          case sequenced_revision_index(target, revision, 0) {
            Ok(index) -> Ok(index)
            Error(_) ->
              case source_base {
                Revision(_) -> Ok(-1)
                Sentinel ->
                  Error(InvalidHistory("target branch base is not on the trunk"))
              }
          }
      }
  }
}

fn sequenced_revision_index(
  commits: List(SequencedCommit),
  revision: fluid_ids.StableId,
  index: Int,
) -> Result(Int, TreeError) {
  latest_sequenced_revision_index(commits, revision, index, None)
}

fn latest_sequenced_revision_index(
  commits: List(SequencedCommit),
  revision: fluid_ids.StableId,
  index: Int,
  found: Option(Int),
) -> Result(Int, TreeError) {
  case commits {
    [] ->
      case found {
        Some(index) -> Ok(index)
        None -> Error(InvalidHistory("target branch base is not on the trunk"))
      }
    [first, ..rest] ->
      latest_sequenced_revision_index(
        rest,
        revision,
        index + 1,
        case first.commit.revision == revision {
          True -> Some(index)
          False -> found
        },
      )
  }
}

fn remove_common_prefix(
  source: List(BranchCommit),
  target: List(Commit),
) -> List(Commit) {
  case source, target {
    [source, ..source_rest], [target, ..target_rest] ->
      case source.commit.revision == target.revision {
        True -> remove_common_prefix(source_rest, target_rest)
        False -> [target, ..target_rest]
      }
    _, target -> target
  }
}

fn remove_source_common_prefix(
  source: List(BranchCommit),
  target: List(Commit),
) -> List(BranchCommit) {
  case source, target {
    [source, ..source_rest], [target, ..target_rest] ->
      case source.commit.revision == target.revision {
        True -> remove_source_common_prefix(source_rest, target_rest)
        False -> [source, ..source_rest]
      }
    source, _ -> source
  }
}

fn replace_current_pending(
  pending: List(LocalCommit),
  current: List(BranchCommit),
) -> Result(List(LocalCommit), TreeError) {
  case pending, current {
    [], [] -> Ok([])
    [local, ..pending], [commit, ..current] -> {
      use _ <- result.try(check(
        local.original.commit.revision == commit.commit.revision,
        "rebased pending revision does not match its original commit",
      ))
      use rest <- result.try(replace_current_pending(pending, current))
      Ok([LocalCommit(local.original, commit, local.authoring_context), ..rest])
    }
    _, _ -> Error(InvalidHistory("rebase changed the pending commit count"))
  }
}

fn single_incoming_commit(
  commits: List(BranchCommit),
  incoming: Commit,
) -> Result(Option(BranchCommit), TreeError) {
  case commits {
    [] -> Ok(None)
    [commit] -> {
      use _ <- result.try(check(
        commit.commit.revision == incoming.revision,
        "peer reconciliation produced an unexpected trunk commit",
      ))
      Ok(Some(commit))
    }
    _ ->
      Error(InvalidHistory(
        "peer reconciliation produced more than one trunk commit",
      ))
  }
}

fn reference_base(
  state: History,
  sequence_number: Int,
) -> Result(BranchBase, TreeError) {
  let base_sequence = case state.base {
    InitialBase -> minimum_sequence_number
    SequencedBase(point) -> point.sequence_number
  }
  use _ <- result.try(check(
    sequence_number >= base_sequence,
    "reference sequence number precedes retained history",
  ))
  Ok(
    list.fold(state.trunk, Sentinel, fn(base, entry) {
      case entry.point.sequence_number <= sequence_number {
        True -> Revision(entry.commit.revision)
        False -> base
      }
    }),
  )
}

pub fn authoring_commits(
  state: History,
  originator: fluid_ids.SessionId,
  reference_sequence_number: Int,
  revision: fluid_ids.StableId,
) -> Result(List(Commit), TreeError) {
  case replayed_authoring_commits(state, originator, revision) {
    Some(context) -> Ok(context)
    None ->
      case
        originator == state.local_session,
        pending_authoring_context(state.pending, revision)
      {
        True, Some(context) -> Ok(context)
        _, _ ->
          remote_authoring_commits(state, originator, reference_sequence_number)
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn replayed_authoring_commits(
  state: History,
  originator: fluid_ids.SessionId,
  revision: fluid_ids.StableId,
) -> Option(List(Commit)) {
  use before <- option.then(commits_before_revision(state.trunk, revision, []))
  case peer_state(state.peers, originator) {
    Some(peer) ->
      case branch_commits_before_revision(peer.commits, revision, []) {
        Some(commits) ->
          case commits_through_base(state.trunk, peer.base) {
            Ok(ancestry) -> Some(list.append(ancestry, commits))
            Error(_) -> Some(before)
          }
        None -> Some(before)
      }
    None -> Some(before)
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn commits_before_revision(
  commits: List(SequencedCommit),
  revision: fluid_ids.StableId,
  before: List(Commit),
) -> Option(List(Commit)) {
  case commits {
    [] -> None
    [first, ..rest] ->
      case first.commit.revision == revision {
        True -> Some(list.reverse(before))
        False ->
          commits_before_revision(rest, revision, [first.commit, ..before])
      }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn branch_commits_before_revision(
  commits: List(BranchCommit),
  revision: fluid_ids.StableId,
  before: List(Commit),
) -> Option(List(Commit)) {
  case commits {
    [] -> None
    [first, ..rest] ->
      case first.commit.revision == revision {
        True -> Some(list.reverse(before))
        False ->
          branch_commits_before_revision(rest, revision, [
            first.commit,
            ..before
          ])
      }
  }
}

fn remote_authoring_commits(
  state: History,
  originator: fluid_ids.SessionId,
  reference_sequence_number: Int,
) -> Result(List(Commit), TreeError) {
  use reference <- result.try(reference_base(state, reference_sequence_number))
  case peer_state(state.peers, originator) {
    None -> commits_through_base(state.trunk, reference)
    Some(peer) -> {
      use target_path <- result.try(commits_after_base(state.trunk, peer.base))
      use up_to_index <- result.try(branch_base_index(
        target_path,
        peer.base,
        reference,
      ))
      let matched_index = case up_to_index {
        -1 -> -1
        _ ->
          advanced_base_index(
            list.drop(target_path, up_to_index + 1),
            peer.commits,
            up_to_index,
            up_to_index + 1,
            up_to_index,
          )
      }
      let new_base = case item_at(target_path, matched_index) {
        Some(commit) -> Revision(commit.commit.revision)
        None -> peer.base
      }
      let target_commits =
        target_path
        |> list.take(matched_index + 1)
        |> list.map(fn(entry) { entry.commit })
      let source =
        peer.commits
        |> list.filter(fn(commit) {
          !contains_revision(target_commits, commit.commit.revision)
        })
      case remove_common_prefix(peer.commits, target_commits) {
        [] -> {
          use ancestry <- result.try(commits_through_base(state.trunk, new_base))
          Ok(list.append(
            ancestry,
            list.map(source, fn(commit) { commit.commit }),
          ))
        }
        _ -> commits_through_base(state.trunk, reference)
      }
    }
  }
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn pending_authoring_context(
  pending: List(LocalCommit),
  revision: fluid_ids.StableId,
) -> Option(List(Commit)) {
  case pending {
    [] -> None
    [first, ..rest] ->
      case first.original.commit.revision == revision {
        True -> Some(first.authoring_context)
        False -> pending_authoring_context(rest, revision)
      }
  }
}

fn commits_through_base(
  trunk: List(SequencedCommit),
  base: BranchBase,
) -> Result(List(Commit), TreeError) {
  case base {
    Sentinel -> Ok([])
    Revision(revision) -> commits_through_revision(trunk, revision)
  }
}

fn commits_through_pin(
  state: History,
  pin: HistoryBase,
) -> Result(List(Commit), TreeError) {
  case pin == state.base {
    True -> Ok([])
    False ->
      case pin {
        InitialBase ->
          Error(InvalidHistory("local checkout pin precedes retained history"))
        SequencedBase(point) ->
          commits_through_point(state.trunk, state.replayed_receipts, point, [])
      }
  }
}

fn commits_through_point(
  trunk: List(SequencedCommit),
  replayed_receipts: List(SequencePoint),
  point: SequencePoint,
  before: List(Commit),
) -> Result(List(Commit), TreeError) {
  case trunk {
    [] -> Error(InvalidHistory("local checkout pin is not retained"))
    [first, ..rest] -> {
      let semantic_through = case
        list.contains(replayed_receipts, first.point)
        || contains_revision(before, first.commit.revision)
      {
        True -> before
        False -> [first.commit, ..before]
      }
      case first.point == point {
        True -> Ok(list.reverse(semantic_through))
        False ->
          commits_through_point(
            rest,
            replayed_receipts,
            point,
            semantic_through,
          )
      }
    }
  }
}

fn compose_optional(
  tagged: List(shared_change.TaggedChange),
) -> Result(Option(shared_change.Changeset), TreeError) {
  case tagged {
    [] -> Ok(None)
    _ -> shared_change.compose(tagged) |> result.map(Some)
  }
}

fn effects_optional(
  maybe_change: Option(shared_change.Changeset),
) -> Result(List(shared_change.Effect), TreeError) {
  case maybe_change {
    None -> Ok([])
    Some(changeset) ->
      shared_change.effects(shared_change.TaggedChange(None, None, changeset))
  }
}

fn tagged_commit(commit: Commit) -> shared_change.TaggedChange {
  shared_change.TaggedChange(Some(commit.revision), None, commit.change)
}

fn tagged_branch_commit(commit: BranchCommit) -> shared_change.TaggedChange {
  tagged_commit(commit.commit)
}

pub fn retain_revertible(
  state: History,
  revision: fluid_ids.StableId,
  kind: TreeCommitKind,
) -> Result(#(History, RevertibleId), TreeError) {
  use _ <- result.try(check(
    !list.any(state.revertibles, fn(record) { record.revision == revision }),
    "revertible revision is already retained",
  ))
  use #(base, commits, next_node_id) <- result.try(revertible_position(
    state,
    revision,
  ))
  let id = RevertibleId(state.next_revertible_id)
  let record = RevertibleRecord(id, revision, kind, base, commits)
  Ok(#(
    History(
      ..state,
      revertibles: [record, ..state.revertibles],
      next_node_id:,
      next_revertible_id: state.next_revertible_id + 1,
    ),
    id,
  ))
}

pub fn revertible_is_valid(state: History, id: RevertibleId) -> Bool {
  list.any(state.revertibles, fn(record) { record.id == id })
}

pub fn dispose_revertible(
  state: History,
  id: RevertibleId,
) -> Result(History, TreeError) {
  use _ <- result.try(check(
    revertible_is_valid(state, id),
    "revertible is already disposed",
  ))
  Ok(
    History(
      ..state,
      revertibles: list.filter(state.revertibles, fn(record) { record.id != id }),
    ),
  )
}

pub fn author_revert(
  state: History,
  id: RevertibleId,
  inverse_revision: fluid_ids.StableId,
  identity_order: change.IdentityOrder,
) -> Result(RevertAuthoring, TreeError) {
  use state <- result.try(rebind_identity_order(state, identity_order))
  use _ <- result.try(check(
    !has_revision(state, inverse_revision),
    "revert revision is already present",
  ))
  use record <- result.try(
    case list.find(state.revertibles, fn(record) { record.id == id }) {
      Ok(record) -> Ok(record)
      Error(Nil) -> Error(InvalidHistory("revertible is already disposed"))
    },
  )
  use _ <- result.try(case list.last(record.commits) {
    Ok(_) -> Ok(Nil)
    Error(Nil) -> Error(InvalidHistory("revertible has no target commit"))
  })
  use #(current_target, later) <- result.try(
    current_branch(state, record.revision)
    |> commit_and_after(record.revision),
  )
  use target_change <- result.try(shared_change.rebind_identity_order(
    current_target.change,
    identity_order,
    [
      inverse_revision,
      ..outer_revisions(current_target.revision, current_target.change)
    ]
      |> list.unique,
  ))
  let target = Commit(..current_target, change: target_change)
  use later <- result.try(
    list.try_map(later, fn(commit) { rebind_commit(commit, identity_order) }),
  )
  use inverse <- result.try(shared_change.invert(
    shared_change.TaggedChange(Some(target.revision), None, target.change),
    False,
    inverse_revision,
  ))
  let inverse_tag =
    shared_change.TaggedChange(Some(inverse_revision), None, inverse)
  use context <- result.try(
    rebase_context([
      tagged_commit(target),
      inverse_tag,
      ..list.map(later, tagged_commit)
    ]),
  )
  use inverse <- result.try(
    list.try_fold(later, inverse, fn(inverse, commit) {
      shared_change.rebase(
        shared_change.TaggedChange(Some(inverse_revision), None, inverse),
        tagged_commit(commit),
        context,
      )
      |> history_error("cannot rebase revert: ")
    }),
  )
  let kind = case record.kind {
    types.UndoCommit -> types.RedoCommit
    types.DefaultCommit | types.RedoCommit -> types.UndoCommit
  }
  Ok(RevertAuthoring(
    target,
    Commit(inverse_revision, state.local_session, inverse),
    kind,
  ))
}

fn current_branch(
  state: History,
  revision: fluid_ids.StableId,
) -> List(Commit) {
  let pending = list.map(state.pending, fn(entry) { entry.current.commit })
  let visible =
    list.append(list.map(state.trunk, fn(entry) { entry.commit }), pending)
  case contains_revision(visible, revision) {
    True -> visible
    False ->
      case
        list.find(state.peers, fn(peer) {
          branch_contains_revision(peer.commits, revision)
        })
      {
        Ok(peer) -> list.map(peer.commits, fn(entry) { entry.commit })
        Error(Nil) -> visible
      }
  }
}

fn commit_and_after(
  commits: List(Commit),
  revision: fluid_ids.StableId,
) -> Result(#(Commit, List(Commit)), TreeError) {
  case commits {
    [] ->
      Error(InvalidHistory("revertible target is not on the visible branch"))
    [first, ..rest] ->
      case first.revision == revision {
        True ->
          case commit_and_after(rest, revision) {
            Ok(found) -> Ok(found)
            Error(_) -> Ok(#(first, rest))
          }
        False -> commit_and_after(rest, revision)
      }
  }
}

fn revertible_position(
  state: History,
  revision: fluid_ids.StableId,
) -> Result(#(BranchBase, List(BranchCommit), Int), TreeError) {
  case pending_revertible_position(state.pending, state.local_base, revision) {
    Some(position) -> Ok(#(position.0, position.1, state.next_node_id))
    None ->
      case peer_revertible_position(state.peers, revision) {
        Some(position) -> Ok(#(position.0, position.1, state.next_node_id))
        None ->
          trunk_revertible_position(
            state.trunk,
            Sentinel,
            revision,
            state.next_node_id,
          )
      }
  }
}

fn pending_revertible_position(
  pending: List(LocalCommit),
  base: Option(BranchBase),
  revision: fluid_ids.StableId,
) -> Option(#(BranchBase, List(BranchCommit))) {
  pending_revertible_prefix(
    pending,
    option.unwrap(base, Sentinel),
    revision,
    [],
  )
}

fn pending_revertible_prefix(
  pending: List(LocalCommit),
  base: BranchBase,
  revision: fluid_ids.StableId,
  before: List(BranchCommit),
) -> Option(#(BranchBase, List(BranchCommit))) {
  case pending {
    [] -> None
    [first, ..rest] ->
      case first.original.commit.revision == revision {
        True -> Some(#(base, list.reverse([first.current, ..before])))
        False ->
          pending_revertible_prefix(rest, base, revision, [
            first.current,
            ..before
          ])
      }
  }
}

fn peer_revertible_position(
  peers: List(PeerState),
  revision: fluid_ids.StableId,
) -> Option(#(BranchBase, List(BranchCommit))) {
  case peers {
    [] -> None
    [peer, ..rest] ->
      case branch_revertible_position(peer.commits, peer.base, revision) {
        Some(position) -> Some(position)
        None -> peer_revertible_position(rest, revision)
      }
  }
}

fn branch_revertible_position(
  commits: List(BranchCommit),
  base: BranchBase,
  revision: fluid_ids.StableId,
) -> Option(#(BranchBase, List(BranchCommit))) {
  branch_revertible_prefix(commits, base, revision, [])
}

fn branch_revertible_prefix(
  commits: List(BranchCommit),
  base: BranchBase,
  revision: fluid_ids.StableId,
  before: List(BranchCommit),
) -> Option(#(BranchBase, List(BranchCommit))) {
  case commits {
    [] -> None
    [first, ..rest] ->
      case first.commit.revision == revision {
        True -> Some(#(base, list.reverse([first, ..before])))
        False ->
          branch_revertible_prefix(rest, base, revision, [first, ..before])
      }
  }
}

fn trunk_revertible_position(
  trunk: List(SequencedCommit),
  base: BranchBase,
  revision: fluid_ids.StableId,
  node_id: Int,
) -> Result(#(BranchBase, List(BranchCommit), Int), TreeError) {
  case trunk {
    [] -> Error(InvalidHistory("revertible revision is not retained"))
    [first, ..rest] ->
      case first.commit.revision == revision {
        True -> Ok(#(base, [BranchCommit(node_id, first.commit)], node_id + 1))
        False ->
          trunk_revertible_position(
            rest,
            Revision(first.commit.revision),
            revision,
            node_id,
          )
      }
  }
}

fn retained_nodes(state: History) -> List(Int) {
  list.append(
    state.revertibles
      |> list.flat_map(fn(record) {
        list.map(record.commits, fn(commit) { commit.node_id })
      }),
    state.local_checkouts
      |> list.flat_map(fn(local) {
        list.map(local.commits, fn(commit) { commit.node_id })
      }),
  )
}

fn prune_rollbacks(state: History) -> History {
  let live_nodes =
    list.append(
      retained_nodes(state),
      list.append(
        list.map(state.pending, fn(entry) { entry.current.node_id }),
        list.flat_map(state.peers, fn(peer) {
          list.map(peer.commits, fn(commit) { commit.node_id })
        }),
      ),
    )
  History(
    ..state,
    rollbacks: list.filter(state.rollbacks, fn(entry) {
      list.contains(live_nodes, entry.source_node)
    }),
  )
}

fn trim_history(
  state: History,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(History, List(fluid_ids.StableId), allocation), TreeError) {
  let desired =
    last_index_where(state.trunk, fn(entry) {
      entry.point.sequence_number <= state.minimum_sequence_number
    })
  use desired <- result.try(
    list.try_fold(state.revertibles, desired, fn(desired, record) {
      use retained <- result.try(case record.base {
        Sentinel -> Ok(-1)
        Revision(revision) -> sequenced_revision_index(state.trunk, revision, 0)
      })
      Ok(int_min(desired, retained))
    }),
  )
  use desired <- result.try(
    list.try_fold(state.local_checkouts, desired, fn(desired, local) {
      use retained <- result.try(local_pin_index(state, local.pin))
      Ok(int_min(desired, retained - 1))
    }),
  )
  case item_at(state.trunk, desired) {
    None -> Ok(#(state, [], allocation))
    Some(new_base) -> {
      let base = Revision(new_base.commit.revision)
      let known_revisions = history_revisions(state)
      use #(peers, allocation, rollbacks, next_node_id) <- result.try(
        list.try_fold(
          state.peers,
          #([], allocation, state.rollbacks, state.next_node_id),
          fn(output, peer) {
            use #(rebased, allocation, rollbacks, next_node_id) <- result.try(
              rebase_branch(
                peer.base,
                peer.commits,
                state.trunk,
                base,
                output.2,
                known_revisions,
                output.3,
                output.1,
                mint,
              ),
            )
            Ok(#(
              list.append(output.0, [
                PeerState(
                  peer.originator,
                  case rebased.base == base {
                    True -> Sentinel
                    False -> rebased.base
                  },
                  rebased.commits,
                ),
              ]),
              allocation,
              rollbacks,
              next_node_id,
            ))
          },
        ),
      )
      let removed = list.take(state.trunk, desired + 1)
      let retained = list.drop(state.trunk, desired + 1)
      let next =
        History(
          ..state,
          base: SequencedBase(new_base.point),
          trunk: retained,
          peers: peers,
          rollbacks: rollbacks,
          receipts: list.filter(state.receipts, fn(receipt) {
            trunk_commit(retained, receipt.revision) != None
          }),
          replayed_receipts: list.filter(state.replayed_receipts, fn(point) {
            list.any(retained, fn(entry) { entry.point == point })
          }),
          revertibles: list.map(state.revertibles, fn(record) {
            RevertibleRecord(..record, base: case record.base == base {
              True -> Sentinel
              False -> record.base
            })
          }),
          local_checkouts: list.map(state.local_checkouts, fn(local) {
            LocalState(..local, base: case local.base == base {
              True -> Sentinel
              False -> local.base
            })
          }),
          next_node_id: next_node_id,
          local_base: case state.local_base {
            Some(local_base) if local_base == base -> Some(Sentinel)
            other -> other
          },
        )
      Ok(#(
        next,
        list.map(removed, fn(entry) { entry.commit.revision }),
        allocation,
      ))
    }
  }
}

fn last_index_where(values: List(a), predicate: fn(a) -> Bool) -> Int {
  last_index_where_loop(values, predicate, 0, -1)
}

fn last_index_where_loop(
  values: List(a),
  predicate: fn(a) -> Bool,
  index: Int,
  found: Int,
) -> Int {
  case values {
    [] -> found
    [first, ..rest] ->
      last_index_where_loop(rest, predicate, index + 1, case predicate(first) {
        True -> index
        False -> found
      })
  }
}

pub fn advance_minimum(
  state: History,
  sequence_number: Int,
  minimum_sequence_number: Int,
  allocation: allocation,
  mint: MintRevision(allocation),
) -> Result(#(HistoryUpdate, allocation), TreeError) {
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
  let updated = History(..state, sequence_number:, minimum_sequence_number:)
  use #(next, trimmed, allocation) <- result.try(trim_history(
    updated,
    allocation,
    mint,
  ))
  Ok(#(HistoryUpdate(prune_rollbacks(next), [], [], trimmed), allocation))
}

pub fn advance_processed(
  state: History,
  sequence_number: Int,
) -> Result(History, TreeError) {
  use _ <- result.try(validate_safe(
    sequence_number,
    "processed sequence number is outside the safe integer range",
  ))
  use _ <- result.try(check(
    sequence_number >= state.sequence_number,
    "processed sequence number regresses",
  ))
  Ok(History(..state, sequence_number:))
}

pub fn pending(state: History) -> List(Commit) {
  list.map(state.pending, fn(entry) { entry.current.commit })
}

pub fn inspect(state: History) -> HistoryView {
  HistoryView(
    sequenced: HistorySnapshot(
      state.base,
      state.trunk,
      state.peers
        |> list.sort(fn(left, right) {
          string.compare(
            fluid_ids.session_id_to_string(left.originator),
            fluid_ids.session_id_to_string(right.originator),
          )
        })
        |> list.map(peer_branch),
      state.sequence_number,
      state.minimum_sequence_number,
      state.replayed_receipts,
    ),
    pending: pending(state),
    longest_branch_length: longest_branch(state),
  )
}

@internal
pub fn inspect_rollback_revisions(state: History) -> List(fluid_ids.StableId) {
  list.map(state.rollbacks, fn(entry) { entry.revision })
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
  let #(peers, next_node_id) = restore_peers(snapshot.peers, 0)
  Ok(History(
    local_session:,
    base: snapshot.base,
    trunk: snapshot.trunk,
    peers: peers,
    pending: [],
    local_base: None,
    local_authored_context: [],
    rollbacks: [],
    receipts: list.map(snapshot.trunk, fn(entry) {
      RetainedReceipt(
        entry.commit.revision,
        Some(authored_receipt_commit(snapshot.peers, entry.commit)),
        entry.point,
        None,
        None,
      )
    }),
    replayed_receipts: snapshot.replayed_receipts,
    revertibles: [],
    local_checkouts: [],
    next_node_id: next_node_id,
    next_revertible_id: 0,
    next_local_checkout_id: 0,
    sequence_number: snapshot.sequence_number,
    minimum_sequence_number: snapshot.minimum_sequence_number,
  ))
}

fn authored_receipt_commit(peers: List(PeerBranch), trunk: Commit) -> Commit {
  peers
  |> list.flat_map(fn(peer) { peer.commits })
  |> list.find(fn(commit) { commit.revision == trunk.revision })
  |> result.unwrap(trunk)
}

fn restore_peers(
  peers: List(PeerBranch),
  next_node_id: Int,
) -> #(List(PeerState), Int) {
  case peers {
    [] -> #([], next_node_id)
    [peer, ..rest] -> {
      let #(commits, next_node_id) = restore_commits(peer.commits, next_node_id)
      let #(rest, next_node_id) = restore_peers(rest, next_node_id)
      #(
        [
          PeerState(
            peer.originator,
            option.unwrap(option.map(peer.base, Revision), Sentinel),
            commits,
          ),
          ..rest
        ],
        next_node_id,
      )
    }
  }
}

fn restore_commits(
  commits: List(Commit),
  next_node_id: Int,
) -> #(List(BranchCommit), Int) {
  case commits {
    [] -> #([], next_node_id)
    [commit, ..rest] -> {
      let node_id = next_node_id
      let #(rest, next_node_id) = restore_commits(rest, next_node_id + 1)
      #([BranchCommit(node_id, commit), ..rest], next_node_id)
    }
  }
}

pub fn resubmit(
  state: History,
  repair: List(#(fluid_ids.StableId, List(forest.Build))),
) -> Result(List(Commit), TreeError) {
  use _ <- result.try(check(
    list.length(list.unique(list.map(repair, fn(entry) { entry.0 })))
      == list.length(repair),
    "resubmission repair contains a duplicate revision",
  ))
  use commits <- result.try(
    list.try_map(state.pending, fn(entry) {
      let commit = entry.current.commit
      let provided = case list.key_find(repair, commit.revision) {
        Ok(builds) -> builds
        Error(Nil) -> []
      }
      use updated <- result.try(update_refreshers(commit.change, provided))
      Ok(Commit(..commit, change: updated))
    }),
  )
  use _ <- result.try(
    list.try_each(repair, fn(entry) {
      check(
        list.any(state.pending, fn(local) {
          local.current.commit.revision == entry.0
        }),
        "resubmission repair names a commit that is not pending",
      )
    }),
  )
  Ok(commits)
}

fn outer_revisions(
  revision: fluid_ids.StableId,
  changeset: shared_change.Changeset,
) -> List(fluid_ids.StableId) {
  [revision, ..shared_change.identity_revisions(changeset)] |> list.unique
}

fn unavailable_roots(
  data: change.Changeset,
  prior_builds: List(forest.Build),
  detached: List(types.AtomId),
) -> Result(#(List(types.AtomId), List(forest.Build)), TreeError) {
  let available = list.append(prior_builds, change.to_data(data).builds)
  use roots <- result.try(change.relevant_removed_roots(data))
  Ok(#(
    list.filter(roots, fn(root) {
      !list.contains(detached, root)
      && !list.any(available, fn(build) { build_covers(build, root) })
    }),
    available,
  ))
}

fn update_refreshers(
  changeset: shared_change.Changeset,
  repair: List(forest.Build),
) -> Result(shared_change.Changeset, TreeError) {
  use _ <- result.try(check(
    list.length(list.unique(list.map(repair, fn(build) { build.id })))
      == list.length(repair),
    "resubmission repair contains a duplicate root",
  ))
  use #(items, _, _, used, _) <- result.try(
    changeset
    |> shared_change.to_changes
    |> list.try_fold(#([], [], [], [], RequiredRepair), fn(state, item) {
      case item {
        shared_change.SchemaChange(_, _, _) ->
          Ok(#(list.append(state.0, [item]), state.1, state.2, state.3, state.4))
        shared_change.DataChange(data) -> {
          use #(roots, available) <- result.try(unavailable_roots(
            data,
            state.1,
            state.2,
          ))
          let roots =
            list.filter(roots, fn(root) {
              !list.any(state.3, fn(supplied) { build_covers(supplied, root) })
            })
          let supplied =
            list.filter(repair, fn(build) {
              list.any(roots, fn(root) { build.id == root })
            })
          use _ <- result.try(case state.4 {
            RequiredRepair -> validate_repair_roots(roots, supplied)
            OptionalRepair -> Ok(Nil)
          })
          let refreshed_roots = list.map(supplied, fn(build) { build.id })
          use updated <- result.try(change.update_refreshers(
            data,
            refreshed_roots,
            supplied,
          ))
          use detached_roots <- result.try(change.detached_roots(data))
          Ok(#(
            list.append(state.0, [shared_change.DataChange(updated)]),
            available,
            list.append(state.2, detached_roots) |> list.unique,
            list.append(state.3, supplied),
            OptionalRepair,
          ))
        }
      }
    }),
  )
  use _ <- result.try(
    list.try_each(repair, fn(build) {
      check(
        list.any(used, fn(value) { value.id == build.id }),
        "resubmission repair contains an extraneous root",
      )
    }),
  )
  shared_change.from_changes(items)
}

pub fn build_covers(build: forest.Build, root: types.AtomId) -> Bool {
  build.id.revision == root.revision
  && root.local_id >= build.id.local_id
  && root.local_id < build.id.local_id + list.length(build.trees)
}

fn validate_repair_roots(
  roots: List(types.AtomId),
  repair: List(forest.Build),
) -> Result(Nil, TreeError) {
  use _ <- result.try(check(
    list.length(list.unique(list.map(repair, fn(build) { build.id })))
      == list.length(repair),
    "resubmission repair contains a duplicate root",
  ))
  use _ <- result.try(
    list.try_each(roots, fn(root) {
      check(
        list.any(repair, fn(build) { build.id == root }),
        "resubmission repair is missing a removed root",
      )
    }),
  )
  list.try_each(repair, fn(build) {
    use _ <- result.try(check(
      list.length(build.trees) == 1,
      "resubmission repair root must contain one tree",
    ))
    check(
      list.contains(roots, build.id),
      "resubmission repair contains an extraneous root",
    )
  })
}

fn validate_receive_fields(
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
    supplied_minimum <= point.sequence_number,
    "minimum sequence number exceeds the received sequence number",
  ))
  Ok(Nil)
}

fn validate_new_receive_order(
  state: History,
  point: SequencePoint,
) -> Result(Nil, TreeError) {
  use _ <- result.try(check(
    point.sequence_number >= state.sequence_number,
    "received sequence number precedes the processed watermark",
  ))
  let latest = latest_tree_point(state)
  use _ <- result.try(case latest {
    None -> Ok(Nil)
    Some(previous) ->
      check(
        compare_points(previous, point) == order.Lt,
        "received sequence point is not after retained history",
      )
  })
  case point.sequence_number == state.sequence_number {
    False -> Ok(Nil)
    True ->
      case latest {
        Some(previous) ->
          check(
            previous.sequence_number == point.sequence_number,
            "received sequence does not continue the processed batch",
          )
        None ->
          Error(InvalidHistory(
            "received sequence does not continue the processed batch",
          ))
      }
  }
}

fn latest_tree_point(state: History) -> Option(SequencePoint) {
  case list.last(state.trunk) {
    Ok(entry) -> Some(entry.point)
    Error(Nil) ->
      case state.base {
        InitialBase -> None
        SequencedBase(point) -> Some(point)
      }
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
  use base_point <- result.try(case snapshot.base {
    InitialBase -> Ok(None)
    SequencedBase(point) -> {
      use _ <- result.try(validate_point(point))
      use _ <- result.try(check(
        point.sequence_number <= snapshot.sequence_number,
        "snapshot base exceeds its sequence number",
      ))
      Ok(Some(point))
    }
  })
  use _ <- result.try(
    list.try_fold(snapshot.trunk, base_point, fn(previous, entry) {
      use _ <- result.try(validate_point(entry.point))
      use _ <- result.try(check(
        entry.point.sequence_number <= snapshot.sequence_number,
        "snapshot trunk point exceeds its sequence number",
      ))
      use _ <- result.try(case previous {
        None -> Ok(Nil)
        Some(point) ->
          check(
            compare_points(point, entry.point) == order.Lt,
            "snapshot trunk points are not ordered",
          )
      })
      Ok(Some(entry.point))
    }),
  )
  use _ <- result.try(check(
    list.length(
      list.unique(list.map(snapshot.peers, fn(peer) { peer.originator })),
    )
      == list.length(snapshot.peers),
    "snapshot contains duplicate peer branches",
  ))
  use _ <- result.try(check(
    list.length(list.unique(snapshot.replayed_receipts))
      == list.length(snapshot.replayed_receipts),
    "snapshot contains duplicate replay receipts",
  ))
  use _ <- result.try(
    list.try_each(snapshot.replayed_receipts, fn(point) {
      check(
        list.any(snapshot.trunk, fn(entry) { entry.point == point }),
        "snapshot replay receipt is not retained",
      )
    }),
  )
  use _ <- result.try(
    validate_consistent_revisions(
      list.map(snapshot.trunk, fn(entry) { entry.commit }),
    ),
  )
  use _ <- result.try(
    list.try_each(snapshot.peers, fn(peer) {
      use ancestry <- result.try(case peer.base {
        None -> Ok([])
        Some(revision) -> commits_through_revision(snapshot.trunk, revision)
      })
      use _ <- result.try(
        list.try_each(peer.commits, fn(commit) {
          check(
            commit.originator == peer.originator,
            "snapshot peer commit originator does not match its branch",
          )
        }),
      )
      validate_consistent_revisions(list.append(ancestry, peer.commits))
    }),
  )
  let commits =
    list.append(
      list.map(snapshot.trunk, fn(entry) { entry.commit }),
      list.flat_map(snapshot.peers, fn(peer) { peer.commits }),
    )
  use _ <- result.try(
    list.try_fold(commits, [], fn(origins, commit) {
      case list.key_find(origins, commit.revision) {
        Error(Nil) -> Ok([#(commit.revision, commit.originator), ..origins])
        Ok(originator) -> {
          use _ <- result.try(check(
            originator == commit.originator,
            "snapshot revision has conflicting originators",
          ))
          Ok(origins)
        }
      }
    }),
  )
  Ok(Nil)
}

fn commits_through_revision(
  trunk: List(SequencedCommit),
  revision: fluid_ids.StableId,
) -> Result(List(Commit), TreeError) {
  use index <- result.try(sequenced_revision_index(trunk, revision, 0))
  Ok(
    trunk
    |> list.take(index + 1)
    |> list.map(fn(entry) { entry.commit }),
  )
}

fn validate_consistent_revisions(
  commits: List(Commit),
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_fold(commits, [], fn(seen, commit) {
      case list.key_find(seen, commit.revision) {
        Error(Nil) -> Ok([#(commit.revision, commit), ..seen])
        Ok(existing) -> {
          use _ <- result.try(check(
            existing == commit,
            "snapshot ancestry path has conflicting revision contents",
          ))
          Ok(seen)
        }
      }
    }),
  )
  Ok(Nil)
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

fn history_error(
  value: Result(a, TreeError),
  prefix: String,
) -> Result(a, TreeError) {
  value
  |> result.map_error(fn(error) {
    case error {
      InvalidHistory(detail) -> InvalidHistory(prefix <> detail)
      other -> other
    }
  })
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
  || list.any(state.pending, fn(entry) {
    entry.original.commit.revision == revision
  })
  || list.any(state.peers, fn(peer) {
    list.any(peer.commits, fn(commit) { commit.commit.revision == revision })
  })
  || list.any(state.revertibles, fn(record) { record.revision == revision })
  || list.any(state.local_checkouts, fn(local) {
    branch_contains_revision(local.commits, revision)
  })
}

fn history_revisions(state: History) -> List(fluid_ids.StableId) {
  list.append(
    list.map(state.trunk, fn(entry) { entry.commit.revision }),
    list.append(
      list.flat_map(state.pending, fn(entry) {
        [entry.original.commit.revision, entry.current.commit.revision]
      }),
      list.flat_map(state.peers, fn(peer) {
        list.map(peer.commits, fn(commit) { commit.commit.revision })
      }),
    ),
  )
  |> list.append(
    list.map(state.local_authored_context, fn(commit) { commit.revision }),
  )
  |> list.append(list.map(state.revertibles, fn(record) { record.revision }))
  |> list.append(
    list.flat_map(state.local_checkouts, fn(local) {
      list.map(local.commits, fn(commit) { commit.commit.revision })
    }),
  )
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn trunk_commit(
  trunk: List(SequencedCommit),
  revision: fluid_ids.StableId,
) -> Option(SequencedCommit) {
  trunk
  |> list.reverse
  |> list.find(fn(entry) { entry.commit.revision == revision })
  |> result.map(Some)
  |> result.unwrap(None)
}

fn trunk_head(trunk: List(SequencedCommit)) -> BranchBase {
  case list.last(trunk) {
    Ok(entry) -> Revision(entry.commit.revision)
    Error(Nil) -> Sentinel
  }
}

fn require_local_base(
  base: Option(BranchBase),
) -> Result(BranchBase, TreeError) {
  case base {
    Some(base) -> Ok(base)
    None -> Error(InvalidHistory("pending branch has no base"))
  }
}

fn checkout_position(
  state: History,
  selector: CheckoutSelector,
) -> Result(#(BranchBase, HistoryBase, List(BranchCommit)), TreeError) {
  case selector {
    DocumentCheckout -> {
      use pin <- result.try(document_checkout_pin(state))
      Ok(#(
        option.unwrap(state.local_base, trunk_head(state.trunk)),
        pin,
        list.map(state.pending, fn(entry) { entry.current }),
      ))
    }
    LocalCheckout(id) -> {
      use local <- result.try(require_local_checkout(state.local_checkouts, id))
      Ok(#(local.base, local.pin, local.commits))
    }
  }
}

fn document_checkout_pin(state: History) -> Result(HistoryBase, TreeError) {
  case state.pending {
    [] ->
      case list.last(state.trunk) {
        Ok(entry) -> Ok(SequencedBase(entry.point))
        Error(Nil) -> Ok(state.base)
      }
    _ -> {
      use base <- result.try(require_local_base(state.local_base))
      case base {
        Sentinel -> Ok(state.base)
        Revision(revision) -> revision_pin(state.trunk, revision, None)
      }
    }
  }
}

fn revision_pin(
  trunk: List(SequencedCommit),
  revision: fluid_ids.StableId,
  found: Option(HistoryBase),
) -> Result(HistoryBase, TreeError) {
  case trunk {
    [] ->
      case found {
        Some(pin) -> Ok(pin)
        None -> Error(InvalidHistory("local checkout pin is not retained"))
      }
    [first, ..rest] ->
      revision_pin(rest, revision, case first.commit.revision == revision {
        True -> Some(SequencedBase(first.point))
        False -> found
      })
  }
}

fn local_pin_index(state: History, pin: HistoryBase) -> Result(Int, TreeError) {
  case pin == state.base {
    True -> Ok(-1)
    False ->
      case pin {
        InitialBase ->
          Error(InvalidHistory("local checkout pin precedes retained history"))
        SequencedBase(point) -> sequenced_point_index(state.trunk, point, 0)
      }
  }
}

fn sequenced_point_index(
  trunk: List(SequencedCommit),
  point: SequencePoint,
  index: Int,
) -> Result(Int, TreeError) {
  case trunk {
    [] -> Error(InvalidHistory("local checkout pin is not retained"))
    [first, ..rest] ->
      case first.point == point {
        True -> Ok(index)
        False -> sequenced_point_index(rest, point, index + 1)
      }
  }
}

fn require_local_checkout(
  checkouts: List(LocalState),
  id: LocalCheckoutId,
) -> Result(LocalState, TreeError) {
  case list.find(checkouts, fn(local) { local.id == id }) {
    Ok(local) -> Ok(local)
    Error(Nil) -> Error(InvalidHistory("local checkout is disposed"))
  }
}

fn replace_local_checkout(
  checkouts: List(LocalState),
  updated: LocalState,
) -> List(LocalState) {
  case checkouts {
    [] -> [updated]
    [first, ..rest] ->
      case first.id == updated.id {
        True -> [updated, ..rest]
        False -> [first, ..replace_local_checkout(rest, updated)]
      }
  }
}

fn local_branch(local: LocalState) -> LocalBranch {
  LocalBranch(
    local.id,
    case local.base {
      Sentinel -> None
      Revision(revision) -> Some(revision)
    },
    list.map(local.commits, fn(commit) { commit.commit }),
  )
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil).
fn peer_state(
  peers: List(PeerState),
  originator: fluid_ids.SessionId,
) -> Option(PeerState) {
  list.find(peers, fn(peer) { peer.originator == originator })
  |> result.map(Some)
  |> result.unwrap(None)
}

fn replace_peer(peers: List(PeerState), updated: PeerState) -> List(PeerState) {
  case peers {
    [] -> [updated]
    [first, ..rest] ->
      case first.originator == updated.originator {
        True -> [updated, ..rest]
        False -> [first, ..replace_peer(rest, updated)]
      }
  }
}

fn replace_receipt(
  receipts: List(RetainedReceipt),
  updated: RetainedReceipt,
) -> List(RetainedReceipt) {
  case receipts {
    [] -> [updated]
    [first, ..rest] ->
      case first.revision == updated.revision {
        True -> [updated, ..rest]
        False -> [first, ..replace_receipt(rest, updated)]
      }
  }
}

fn peer_branch(peer: PeerState) -> PeerBranch {
  PeerBranch(
    peer.originator,
    case peer.base {
      Sentinel -> None
      Revision(revision) -> Some(revision)
    },
    list.map(peer.commits, fn(commit) { commit.commit }),
  )
}

fn contains_revision(
  commits: List(Commit),
  revision: fluid_ids.StableId,
) -> Bool {
  list.any(commits, fn(commit) { commit.revision == revision })
}

fn branch_contains_revision(
  commits: List(BranchCommit),
  revision: fluid_ids.StableId,
) -> Bool {
  list.any(commits, fn(commit) { commit.commit.revision == revision })
}

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil). change.nth is a copy of this helper.
// Use list.drop, then list.first.
fn item_at(items: List(a), index: Int) -> Option(a) {
  case index < 0, items {
    True, _ -> None
    False, [] -> None
    False, [first, ..rest] ->
      case index == 0 {
        True -> Some(first)
        False -> item_at(rest, index - 1)
      }
  }
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

fn int_min(left: Int, right: Int) -> Int {
  case left < right {
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
