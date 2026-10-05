//// Pure runtime-local SharedTree checkout state.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime
import watershed/tree/schema
import watershed/tree/transaction as tree_transaction
import watershed/tree/types.{
  type CheckoutSelector, type Edit, type FieldPath, type LocalCheckoutId,
  type RevertibleId, type TreeCommitKind, type TreeError, type TreeValue,
  DocumentCheckout, InvalidHistory, LocalCheckout,
}
import watershed/tree_kernel

pub opaque type Origin {
  Origin(runtime: String, document: String, tree: String)
}

pub opaque type Checkout {
  Checkout(origin: Origin, selector: CheckoutSelector)
}

type LocalState {
  LocalState(id: LocalCheckoutId, state: tree_kernel.TreeState)
}

pub opaque type Forest {
  Forest(
    origin: Origin,
    document: tree_kernel.TreeState,
    locals: List(LocalState),
    disposed: List(LocalCheckoutId),
    active_transactions: List(CheckoutSelector),
  )
}

pub type BranchEvent {
  BranchEvent(
    checkout: CheckoutSelector,
    commit: Option(history.Commit),
    changes: tree_kernel.ChangeEvents,
  )
}

pub type ReconcileResult {
  ReconcileResult(
    forest: Forest,
    events: List(BranchEvent),
    commits: List(history.Commit),
  )
}

pub type AuthorResult {
  AuthorResult(
    forest: Forest,
    commit: Option(history.Commit),
    events: List(BranchEvent),
    compressor: fluid_ids.Compressor,
  )
}

pub opaque type BranchTransaction {
  BranchTransaction(checkout: Checkout, value: tree_transaction.Transaction)
}

pub type TransactionResult {
  TransactionNoCommit(forest: Forest, compressor: fluid_ids.Compressor)
  TransactionCommit(
    forest: Forest,
    commit: history.Commit,
    events: List(BranchEvent),
    compressor: fluid_ids.Compressor,
  )
}

pub opaque type Revertible {
  Revertible(checkout: Checkout, id: RevertibleId)
}

pub type RevertResult {
  RevertResult(
    forest: Forest,
    commit: history.Commit,
    kind: TreeCommitKind,
    events: List(BranchEvent),
    revertible: Revertible,
    compressor: fluid_ids.Compressor,
  )
}

pub fn origin(runtime: String, document: String, tree: String) -> Origin {
  Origin(runtime, document, tree)
}

pub fn new(origin: Origin, document: tree_kernel.TreeState) -> Forest {
  Forest(origin, document, [], [], [])
}

pub fn document(state: Forest) -> Checkout {
  Checkout(state.origin, DocumentCheckout)
}

pub fn update_document(
  state: Forest,
  update: fn(tree_kernel.TreeState) ->
    Result(#(tree_kernel.TreeState, payload), TreeError),
) -> Result(#(Forest, payload), TreeError) {
  use #(document, payload) <- result.try(update(state.document))
  let branch_history = tree_kernel.branch_history(document)
  use _ <- result.try(
    list.try_each(state.locals, fn(local) {
      history.inspect_local(branch_history, local.id)
      |> result.map(fn(_) { Nil })
    }),
  )
  Ok(#(
    Forest(
      ..state,
      document:,
      locals: sync_local_histories(state.locals, branch_history),
    ),
    payload,
  ))
}

pub fn fork(
  state: Forest,
  source: Checkout,
) -> Result(#(Forest, Checkout), TreeError) {
  use selector <- result.try(validate_checkout(state, source))
  use _ <- result.try(case list.contains(state.active_transactions, selector) {
    True -> Error(InvalidHistory("source checkout has an active transaction"))
    False -> Ok(Nil)
  })
  use source_state <- result.try(state_for_selector(state, selector))
  use #(branch_history, id) <- result.try(history.fork_local(
    tree_kernel.branch_history(state.document),
    selector,
  ))
  let next =
    Forest(
      ..state,
      document: tree_kernel.with_branch_history(state.document, branch_history),
      locals: [
        LocalState(
          id,
          tree_kernel.with_branch_history(source_state, branch_history),
        ),
        ..sync_local_histories(state.locals, branch_history)
      ],
    )
  Ok(#(next, Checkout(state.origin, LocalCheckout(id))))
}

pub fn apply(
  state: Forest,
  checkout: Checkout,
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
  edit: Edit,
) -> Result(#(Forest, history.Commit, tree_kernel.ChangeEvents), TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  case selector {
    DocumentCheckout -> {
      use #(document, commit, events) <- result.try(tree_kernel.apply_local(
        state.document,
        revision,
        order,
        edit,
      ))
      let branch_history = tree_kernel.branch_history(document)
      Ok(#(
        Forest(
          ..state,
          document:,
          locals: sync_local_histories(state.locals, branch_history),
        ),
        commit,
        events,
      ))
    }
    LocalCheckout(id) -> {
      use local <- result.try(require_local(state.locals, id))
      use authored <- result.try(tree_kernel.author_local_change(
        local.state,
        revision,
        order,
        edit,
      ))
      use #(candidate, events) <- result.try(tree_kernel.apply_local_preview(
        local.state,
        revision,
        order,
        authored,
      ))
      let commit = history.Commit(revision, local_session(state), authored)
      use update <- result.try(history.append_local_checkout(
        tree_kernel.branch_history(state.document),
        id,
        commit,
      ))
      let candidate = tree_kernel.with_branch_history(candidate, update.history)
      let locals =
        state.locals
        |> replace_local(LocalState(id, candidate))
        |> sync_local_histories(update.history)
      Ok(#(
        Forest(
          ..state,
          document: tree_kernel.with_branch_history(
            state.document,
            update.history,
          ),
          locals:,
        ),
        commit,
        events,
      ))
    }
  }
}

/// Author an edit with the document compressor.
pub fn author(
  state: Forest,
  checkout: Checkout,
  edit: Edit,
  compressor: fluid_ids.Compressor,
) -> Result(AuthorResult, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  case selector {
    DocumentCheckout -> {
      use #(forest, #(commit, changes, compressor)) <- result.try(
        update_document(state, fn(document) {
          use #(document, commit, changes, compressor) <- result.try(
            runtime.author_edit(document, edit, compressor),
          )
          Ok(#(document, #(commit, changes, compressor)))
        }),
      )
      let events = case commit {
        None -> []
        Some(_) -> [BranchEvent(DocumentCheckout, commit, changes)]
      }
      Ok(AuthorResult(forest, commit, events, compressor))
    }
    LocalCheckout(id) -> {
      use local <- result.try(require_local(state.locals, id))
      use authored <- result.try(runtime.author_edit_change(
        local.state,
        edit,
        compressor,
      ))
      case authored {
        None -> Ok(AuthorResult(state, None, [], compressor))
        Some(authored) -> {
          use revision <- result.try(runtime.authored_revision(authored.change))
          let commit =
            history.Commit(revision, local_session(state), authored.change)
          use update <- result.try(history.append_local_checkout(
            tree_kernel.branch_history(state.document),
            id,
            commit,
          ))
          let candidate =
            tree_kernel.with_branch_history(authored.state, update.history)
          let locals =
            state.locals
            |> replace_local(LocalState(id, candidate))
            |> sync_local_histories(update.history)
          let forest =
            Forest(
              ..state,
              document: tree_kernel.with_branch_history(
                state.document,
                update.history,
              ),
              locals:,
            )
          Ok(AuthorResult(
            forest,
            Some(commit),
            [BranchEvent(selector, Some(commit), authored.events)],
            authored.compressor,
          ))
        }
      }
    }
  }
}

pub fn begin_transaction(
  state: Forest,
  checkout: Checkout,
  compressor: fluid_ids.Compressor,
  constraints: List(change.ConstraintTarget),
) -> Result(#(Forest, BranchTransaction), TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use _ <- result.try(case list.contains(state.active_transactions, selector) {
    True -> Error(InvalidHistory("checkout already has an active transaction"))
    False -> Ok(Nil)
  })
  use checkout_state <- result.try(state_for_selector(state, selector))
  use value <- result.try(tree_transaction.begin(
    checkout_state,
    compressor,
    constraints,
  ))
  use state <- result.try(set_transaction_active(state, checkout, True))
  Ok(#(state, BranchTransaction(checkout, value)))
}

pub fn transaction_apply(
  open: BranchTransaction,
  edit: Edit,
) -> Result(BranchTransaction, TreeError) {
  use value <- result.try(tree_transaction.apply_edit(open.value, edit))
  Ok(BranchTransaction(..open, value:))
}

pub fn transaction_apply_with_compressor(
  open: BranchTransaction,
  edit: Edit,
  compressor: fluid_ids.Compressor,
) -> Result(BranchTransaction, TreeError) {
  use value <- result.try(tree_transaction.apply_edit_with_compressor(
    open.value,
    edit,
    compressor,
  ))
  Ok(BranchTransaction(..open, value:))
}

pub fn transaction_begin_nested(open: BranchTransaction) -> BranchTransaction {
  BranchTransaction(..open, value: tree_transaction.begin_nested(open.value))
}

pub fn transaction_abort_nested(
  open: BranchTransaction,
) -> Result(BranchTransaction, TreeError) {
  use value <- result.try(tree_transaction.abort_nested(open.value))
  Ok(BranchTransaction(..open, value:))
}

pub fn transaction_commit_nested(
  open: BranchTransaction,
) -> Result(BranchTransaction, TreeError) {
  use value <- result.try(tree_transaction.commit_nested(open.value))
  Ok(BranchTransaction(..open, value:))
}

pub fn transaction_read(
  open: BranchTransaction,
  path: FieldPath,
) -> Result(Option(TreeValue), TreeError) {
  tree_kernel.read(tree_transaction.state(open.value), path)
}

pub fn transaction_compressor(open: BranchTransaction) -> fluid_ids.Compressor {
  tree_transaction.compressor(open.value)
}

pub fn finish_transaction(
  state: Forest,
  open: BranchTransaction,
  compressor: fluid_ids.Compressor,
) -> Result(TransactionResult, TreeError) {
  use selector <- result.try(validate_checkout(state, open.checkout))
  use #(finished, changes) <- result.try(tree_transaction.finish(open.value))
  case finished {
    tree_transaction.NoCommit(checkout_state, _) -> {
      use forest <- result.try(install_checkout_state(
        state,
        selector,
        checkout_state,
        None,
      ))
      use forest <- result.try(set_transaction_active(
        forest,
        open.checkout,
        False,
      ))
      Ok(TransactionNoCommit(forest, compressor))
    }
    tree_transaction.Commit(checkout_state, _, commit) -> {
      use forest <- result.try(install_checkout_state(
        state,
        selector,
        checkout_state,
        Some(commit),
      ))
      use forest <- result.try(set_transaction_active(
        forest,
        open.checkout,
        False,
      ))
      Ok(TransactionCommit(
        forest,
        commit,
        [BranchEvent(selector, Some(commit), changes)],
        compressor,
      ))
    }
  }
}

pub fn abort_transaction(
  state: Forest,
  open: BranchTransaction,
  compressor: fluid_ids.Compressor,
) -> Result(#(Forest, fluid_ids.Compressor), TreeError) {
  use selector <- result.try(validate_checkout(state, open.checkout))
  use #(checkout_state, _) <- result.try(tree_transaction.abort(open.value))
  use forest <- result.try(install_checkout_state(
    state,
    selector,
    checkout_state,
    None,
  ))
  use forest <- result.try(set_transaction_active(forest, open.checkout, False))
  Ok(#(forest, compressor))
}

pub fn retain_revertible(
  state: Forest,
  checkout: Checkout,
  revision: fluid_ids.StableId,
  kind: TreeCommitKind,
) -> Result(#(Forest, Revertible), TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use #(branch_history, id) <- result.try(history.retain_revertible_on(
    tree_kernel.branch_history(state.document),
    selector,
    revision,
    kind,
  ))
  Ok(#(install_history(state, branch_history), Revertible(checkout, id)))
}

pub fn revertible_is_valid(state: Forest, revertible: Revertible) -> Bool {
  case validate_checkout(state, revertible.checkout) {
    Error(_) -> False
    Ok(selector) ->
      history.revertible_is_valid_on(
        tree_kernel.branch_history(state.document),
        selector,
        revertible.id,
      )
  }
}

pub fn dispose_revertible(
  state: Forest,
  revertible: Revertible,
) -> Result(Forest, TreeError) {
  use selector <- result.try(validate_checkout(state, revertible.checkout))
  use branch_history <- result.try(history.dispose_revertible(
    tree_kernel.branch_history(state.document),
    revertible.id,
  ))
  use _ <- result.try(
    case
      history.revertible_is_valid_on(
        tree_kernel.branch_history(state.document),
        selector,
        revertible.id,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidHistory(
          "revertible does not belong to the selected checkout",
        ))
    },
  )
  Ok(install_history(state, branch_history))
}

pub fn revert(
  state: Forest,
  revertible: Revertible,
  compressor: fluid_ids.Compressor,
) -> Result(RevertResult, TreeError) {
  use selector <- result.try(validate_checkout(state, revertible.checkout))
  let branch_history = tree_kernel.branch_history(state.document)
  use _ <- result.try(
    case
      history.revertible_is_valid_on(branch_history, selector, revertible.id)
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidHistory(
          "revertible does not belong to the selected checkout",
        ))
    },
  )
  use checkout_state <- result.try(state_for_selector(state, selector))
  use #(revision, order, compressor) <- result.try(
    runtime.allocate_transaction_revision(checkout_state, compressor),
  )
  use authored <- result.try(history.author_revert_on(
    branch_history,
    selector,
    revertible.id,
    revision,
    order,
  ))
  let history.RevertAuthoring(_, inverse, kind) = authored
  use #(forest, inverse, changes) <- result.try(case selector {
    DocumentCheckout -> {
      use #(checkout_state, inverse, changes) <- result.try(
        tree_kernel.apply_local_change(
          checkout_state,
          revision,
          order,
          inverse.change,
        ),
      )
      use #(forest, Nil) <- result.try(
        update_document(state, fn(_) { Ok(#(checkout_state, Nil)) }),
      )
      Ok(#(forest, inverse, changes))
    }
    LocalCheckout(_) -> {
      use #(checkout_state, changes) <- result.try(
        tree_kernel.apply_local_preview(
          checkout_state,
          revision,
          order,
          inverse.change,
        ),
      )
      use forest <- result.try(install_checkout_state(
        state,
        selector,
        checkout_state,
        Some(inverse),
      ))
      Ok(#(forest, inverse, changes))
    }
  })
  use #(forest, next) <- result.try(retain_revertible(
    forest,
    revertible.checkout,
    inverse.revision,
    kind,
  ))
  Ok(RevertResult(
    forest,
    inverse,
    kind,
    [BranchEvent(selector, Some(inverse), changes)],
    next,
    compressor,
  ))
}

pub fn rebase(
  state: Forest,
  source: Checkout,
  target: Checkout,
  allocation: allocation,
  mint: history.MintRevision(allocation),
) -> Result(#(ReconcileResult, allocation), TreeError) {
  use source_selector <- result.try(validate_checkout(state, source))
  use target_selector <- result.try(validate_checkout(state, target))
  use source_id <- result.try(require_local_selector(source_selector))
  use _ <- result.try(validate_reconcile(
    state,
    source_selector,
    target_selector,
  ))
  use source_state <- result.try(state_for_selector(state, source_selector))
  use target_state <- result.try(state_for_selector(state, target_selector))
  use _ <- result.try(require_same_schema(source_state, target_state))
  use #(update, allocation) <- result.try(history.rebase_local(
    tree_kernel.branch_history(state.document),
    source_id,
    target_selector,
    allocation,
    mint,
  ))
  use #(candidate, changes) <- result.try(tree_kernel.apply_branch_effects(
    source_state,
    update.effects,
  ))
  let branch_history = update.history
  let candidate = tree_kernel.with_branch_history(candidate, branch_history)
  let locals =
    state.locals
    |> replace_local(LocalState(source_id, candidate))
    |> sync_local_histories(branch_history)
  let forest =
    Forest(
      ..state,
      document: tree_kernel.with_branch_history(state.document, branch_history),
      locals:,
    )
  let events = case changes {
    tree_kernel.ChangeEvents([], False) -> []
    _ -> [BranchEvent(source_selector, None, changes)]
  }
  Ok(#(ReconcileResult(forest, events, []), allocation))
}

pub fn rebase_with_compressor(
  state: Forest,
  source: Checkout,
  target: Checkout,
  compressor: fluid_ids.Compressor,
) -> Result(#(ReconcileResult, fluid_ids.Compressor), TreeError) {
  let revisions = tree_kernel.identity_revisions(state.document)
  rebase(state, source, target, compressor, fn(current) {
    runtime.mint_revision(current, revisions)
  })
}

pub fn merge(
  state: Forest,
  target: Checkout,
  source: Checkout,
  dispose_source: Bool,
  allocation: allocation,
  mint: history.MintRevision(allocation),
) -> Result(#(ReconcileResult, allocation), TreeError) {
  use target_selector <- result.try(validate_checkout(state, target))
  use source_selector <- result.try(validate_checkout(state, source))
  use source_id <- result.try(require_local_selector(source_selector))
  use _ <- result.try(validate_reconcile(
    state,
    source_selector,
    target_selector,
  ))
  use source_state <- result.try(state_for_selector(state, source_selector))
  use target_state <- result.try(state_for_selector(state, target_selector))
  use _ <- result.try(require_same_schema(source_state, target_state))
  use #(update, commits, allocation) <- result.try(history.merge_local(
    tree_kernel.branch_history(state.document),
    target_selector,
    source_id,
    allocation,
    mint,
  ))
  use #(target_state, events) <- result.try(
    apply_merged_commits(
      target_state,
      target_selector,
      commits,
      target_selector == DocumentCheckout,
      [],
    ),
  )
  let branch_history = update.history
  let document = case target_selector {
    DocumentCheckout ->
      tree_kernel.with_branch_history(target_state, branch_history)
    LocalCheckout(_) ->
      tree_kernel.with_branch_history(state.document, branch_history)
  }
  let locals = case target_selector {
    DocumentCheckout -> sync_local_histories(state.locals, branch_history)
    LocalCheckout(target_id) ->
      state.locals
      |> replace_local(LocalState(
        target_id,
        tree_kernel.with_branch_history(target_state, branch_history),
      ))
      |> sync_local_histories(branch_history)
  }
  let forest = Forest(..state, document:, locals:)
  use forest <- result.try(case dispose_source {
    False -> Ok(forest)
    True -> dispose(forest, source)
  })
  Ok(#(ReconcileResult(forest, events, commits), allocation))
}

/// Merge while allocating rollback revisions from the document compressor.
pub fn merge_with_compressor(
  state: Forest,
  target: Checkout,
  source: Checkout,
  dispose_source: Bool,
  compressor: fluid_ids.Compressor,
) -> Result(#(ReconcileResult, fluid_ids.Compressor), TreeError) {
  let revisions = tree_kernel.identity_revisions(state.document)
  merge(state, target, source, dispose_source, compressor, fn(current) {
    runtime.mint_revision(current, revisions)
  })
}

pub fn dispose(state: Forest, checkout: Checkout) -> Result(Forest, TreeError) {
  use _ <- result.try(case checkout.origin == state.origin {
    True -> Ok(Nil)
    False -> Error(InvalidHistory("checkout origin does not match"))
  })
  case checkout.selector {
    DocumentCheckout ->
      Error(InvalidHistory("document checkout cannot be disposed"))
    LocalCheckout(id) ->
      case list.contains(state.disposed, id) {
        True -> Ok(state)
        False -> {
          let branch_history =
            history.dispose_checkout_revertibles(
              tree_kernel.branch_history(state.document),
              LocalCheckout(id),
            )
          use branch_history <- result.try(history.dispose_local(
            branch_history,
            id,
          ))
          Ok(
            Forest(
              ..state,
              document: tree_kernel.with_branch_history(
                state.document,
                branch_history,
              ),
              locals: state.locals
                |> list.filter(fn(local) { local.id != id })
                |> sync_local_histories(branch_history),
              disposed: [id, ..state.disposed],
              active_transactions: list.filter(
                state.active_transactions,
                fn(selector) { selector != LocalCheckout(id) },
              ),
            ),
          )
        }
      }
  }
}

pub fn set_transaction_active(
  state: Forest,
  checkout: Checkout,
  active: Bool,
) -> Result(Forest, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  let active_transactions = case active {
    True -> [selector, ..state.active_transactions] |> list.unique
    False ->
      list.filter(state.active_transactions, fn(current) { current != selector })
  }
  Ok(Forest(..state, active_transactions:))
}

pub fn read(
  state: Forest,
  checkout: Checkout,
  path: FieldPath,
) -> Result(Option(TreeValue), TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use checkout <- result.try(state_for_selector(state, selector))
  tree_kernel.read(checkout, path)
}

pub fn reference_at(
  state: Forest,
  checkout: Checkout,
  path: FieldPath,
) -> Result(forest.NodeRef, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use checkout <- result.try(state_for_selector(state, selector))
  tree_kernel.reference_at(checkout, path)
}

pub fn visible_data(
  state: Forest,
  checkout: Checkout,
) -> Result(forest.ForestData, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use checkout <- result.try(state_for_selector(state, selector))
  tree_kernel.visible_data(checkout)
}

pub fn history_view(
  state: Forest,
  checkout: Checkout,
) -> Result(history.HistoryView, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use checkout <- result.try(state_for_selector(state, selector))
  Ok(tree_kernel.history_view(checkout))
}

pub fn local_history(
  state: Forest,
  checkout: Checkout,
) -> Result(history.LocalBranch, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use id <- result.try(require_local_selector(selector))
  history.inspect_local(tree_kernel.branch_history(state.document), id)
}

pub fn stored_schema(
  state: Forest,
  checkout: Checkout,
) -> Result(schema.StoredSchema, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  use checkout <- result.try(state_for_selector(state, selector))
  Ok(tree_kernel.stored_schema(checkout))
}

fn local_session(state: Forest) -> fluid_ids.SessionId {
  history.local_session(tree_kernel.branch_history(state.document))
}

fn install_checkout_state(
  state: Forest,
  selector: CheckoutSelector,
  checkout_state: tree_kernel.TreeState,
  commit: Option(history.Commit),
) -> Result(Forest, TreeError) {
  let shared_history = tree_kernel.branch_history(state.document)
  use shared_history <- result.try(case selector, commit {
    _, None -> Ok(shared_history)
    DocumentCheckout, Some(commit) ->
      history.append_local(shared_history, commit)
      |> result.map(fn(update) { update.history })
    LocalCheckout(id), Some(commit) ->
      history.append_local_checkout(shared_history, id, commit)
      |> result.map(fn(update) { update.history })
  })
  let checkout_state =
    tree_kernel.with_branch_history(checkout_state, shared_history)
  case selector {
    DocumentCheckout ->
      Ok(
        Forest(
          ..state,
          document: checkout_state,
          locals: sync_local_histories(state.locals, shared_history),
        ),
      )
    LocalCheckout(id) ->
      Ok(
        Forest(
          ..state,
          document: tree_kernel.with_branch_history(
            state.document,
            shared_history,
          ),
          locals: state.locals
            |> replace_local(LocalState(id, checkout_state))
            |> sync_local_histories(shared_history),
        ),
      )
  }
}

fn install_history(state: Forest, branch_history: history.History) -> Forest {
  Forest(
    ..state,
    document: tree_kernel.with_branch_history(state.document, branch_history),
    locals: sync_local_histories(state.locals, branch_history),
  )
}

fn apply_merged_commits(
  state: tree_kernel.TreeState,
  selector: CheckoutSelector,
  commits: List(history.Commit),
  document_pending: Bool,
  events: List(BranchEvent),
) -> Result(#(tree_kernel.TreeState, List(BranchEvent)), TreeError) {
  case commits {
    [] -> Ok(#(state, list.reverse(events)))
    [commit, ..rest] -> {
      use #(state, changes) <- result.try(case document_pending {
        True -> tree_kernel.apply_merged_pending_commit(state, commit)
        False -> tree_kernel.apply_branch_commit(state, commit)
      })
      apply_merged_commits(state, selector, rest, document_pending, [
        BranchEvent(selector, Some(commit), changes),
        ..events
      ])
    }
  }
}

fn require_local_selector(
  selector: CheckoutSelector,
) -> Result(LocalCheckoutId, TreeError) {
  case selector {
    DocumentCheckout ->
      Error(InvalidHistory("document checkout cannot be a branch source"))
    LocalCheckout(id) -> Ok(id)
  }
}

fn validate_reconcile(
  state: Forest,
  source: CheckoutSelector,
  target: CheckoutSelector,
) -> Result(Nil, TreeError) {
  case
    list.contains(state.active_transactions, source)
    || list.contains(state.active_transactions, target)
  {
    True -> Error(InvalidHistory("affected checkout has an active transaction"))
    False -> Ok(Nil)
  }
}

fn require_same_schema(
  source: tree_kernel.TreeState,
  target: tree_kernel.TreeState,
) -> Result(Nil, TreeError) {
  case tree_kernel.stored_schema(source) == tree_kernel.stored_schema(target) {
    True -> Ok(Nil)
    False -> Error(InvalidHistory("checkout schemas cannot be reconciled"))
  }
}

fn validate_checkout(
  state: Forest,
  checkout: Checkout,
) -> Result(CheckoutSelector, TreeError) {
  use _ <- result.try(case checkout.origin == state.origin {
    True -> Ok(Nil)
    False -> Error(InvalidHistory("checkout origin does not match"))
  })
  case checkout.selector {
    DocumentCheckout -> Ok(DocumentCheckout)
    LocalCheckout(id) ->
      case list.contains(state.disposed, id) {
        True -> Error(InvalidHistory("local checkout is disposed"))
        False -> {
          use _ <- result.try(require_local(state.locals, id))
          Ok(LocalCheckout(id))
        }
      }
  }
}

pub fn checkout_state(
  state: Forest,
  checkout: Checkout,
) -> Result(tree_kernel.TreeState, TreeError) {
  use selector <- result.try(validate_checkout(state, checkout))
  state_for_selector(state, selector)
}

fn state_for_selector(
  state: Forest,
  selector: CheckoutSelector,
) -> Result(tree_kernel.TreeState, TreeError) {
  case selector {
    DocumentCheckout -> Ok(state.document)
    LocalCheckout(id) -> {
      use local <- result.try(require_local(state.locals, id))
      Ok(local.state)
    }
  }
}

fn require_local(
  locals: List(LocalState),
  id: LocalCheckoutId,
) -> Result(LocalState, TreeError) {
  list.find(locals, fn(local) { local.id == id })
  |> result.map_error(fn(_) { InvalidHistory("local checkout is not live") })
}

fn replace_local(
  locals: List(LocalState),
  replacement: LocalState,
) -> List(LocalState) {
  [replacement, ..list.filter(locals, fn(local) { local.id != replacement.id })]
}

fn sync_local_histories(
  locals: List(LocalState),
  branch_history: history.History,
) -> List(LocalState) {
  list.map(locals, fn(local) {
    LocalState(
      ..local,
      state: tree_kernel.with_branch_history(local.state, branch_history),
    )
  })
}
