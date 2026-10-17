import gleam/javascript/promise
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/tree/error
import watershed/tree/typed
import watershed/tree/types as tree_types
import watershed/tree_kernel

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

pub type CommitEvent {
  CommitEvent(
    kind: tree_types.TreeCommitKind,
    local: Bool,
    revertible: Option(watershed.TreeRevertible),
  )
}

pub fn create(
  config: container.CreateConfig,
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
  created: fn(Result(String, typed.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use outcome <- promise.map(watershed.create_tree_container(
      config,
      definition,
      builder,
      initial_root,
    ))
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn create_dev(
  base_url: String,
  tenant: String,
  secret: String,
  definition: typed.Schema(s, r),
  builder: typed.Builder(s, input),
  initial_root: Option(input),
  created: fn(Result(String, typed.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use token <- promise.map(watershed.dev_token(
      secret: secret,
      tenant: tenant,
      document: "",
      user_id: "shared-tree-checklist",
    ))
    use outcome <- promise.map(watershed.create_tree_container(
      container.CreateConfig(base_url, tenant, token),
      definition,
      builder,
      initial_root,
    ))
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn open(
  document: watershed.Document(root),
  definition: typed.Schema(s, r),
  opened: fn(Result(watershed.SharedTree(s, r), typed.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = {
    use root <- result.try(
      watershed.resolve_root(document)
      |> result.map_error(typed.AccessFailed),
    )
    use handle <- result.try(
      watershed.get(root, "tree")
      |> result.replace_error("tree handle is absent")
      |> result.map_error(typed.AccessFailed),
    )
    watershed.resolve_tree(document, handle, definition)
  }
  queue_microtask(fn() { dispatch(opened(outcome)) })
}

pub fn subscribe(
  tree: watershed.SharedTree(s, r),
  subscribed: fn(watershed.SubscriptionToken) -> msg,
  changed: fn(tree_kernel.TreeEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      queue_microtask(fn() { dispatch(changed(event)) })
    })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

pub fn subscribe_commits(
  tree: watershed.SharedTree(s, r),
  subscribed: fn(watershed.SubscriptionToken) -> msg,
  committed: fn(Result(CommitEvent, error.Error)) -> msg,
  settled: fn(Result(tree_types.TreeCommitOutcome, error.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let watershed.TreeCommitEvent(kind, local, get_revertible, on_settled) =
        event
      let captured = case get_revertible {
        None -> Ok(CommitEvent(kind, local, None))
        Some(acquire) ->
          acquire()
          |> result.map(fn(revertible) {
            CommitEvent(kind, local, Some(revertible))
          })
      }
      queue_microtask(fn() { dispatch(committed(captured)) })
      case on_settled {
        None -> Nil
        Some(register) ->
          case
            register(fn(outcome) {
              queue_microtask(fn() { dispatch(settled(Ok(outcome))) })
            })
          {
            Ok(Nil) -> Nil
            Error(error) ->
              queue_microtask(fn() { dispatch(settled(Error(error))) })
          }
      }
    })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

pub fn unsubscribe(subscription: watershed.SubscriptionToken) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.unsubscribe(subscription)
}

pub fn read_root(
  tree: watershed.SharedTree(s, r),
  read: fn(Result(Option(r), typed.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = watershed.tree_read_root(tree)
  queue_microtask(fn() { dispatch(read(outcome)) })
}

pub fn transaction(
  tree: watershed.SharedTree(s, r),
  constraints: List(watershed.TreeTransactionConstraint),
  callback: fn(watershed.SharedTree(s, r)) -> Result(value, callback_error),
  completed: fn(Result(value, watershed.TreeTransactionError(callback_error))) ->
    msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = watershed.tree_transaction(tree, constraints, callback)
  queue_microtask(fn() { dispatch(completed(outcome)) })
}

pub fn revert(
  revertible: watershed.TreeRevertible,
  dispose: Bool,
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  perform(fn() { watershed.tree_revert(revertible, dispose) }, completed)
}

pub fn dispose_revertible(
  revertible: watershed.TreeRevertible,
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  perform(fn() { watershed.tree_dispose_revertible(revertible) }, completed)
}

pub fn perform(
  operation: fn() -> Result(value, error),
  completed: fn(Result(value, error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = operation()
  queue_microtask(fn() { dispatch(completed(outcome)) })
}
