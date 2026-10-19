import gleam/javascript/promise
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/tree
import watershed/tree/error
import watershed/tree/schema_builder as builder

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

pub type CommitEvent {
  CommitEvent(
    kind: tree.CommitKind,
    local: Bool,
    revertible: Option(tree.Revertible),
  )
}

pub fn create(
  config: container.CreateConfig,
  declaration: builder.Root(a),
  initial: a,
  created: fn(Result(String, error.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use outcome <- promise.map(watershed.create_tree_container(
      config,
      declaration,
      initial,
    ))
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn create_dev(
  base_url: String,
  tenant: String,
  secret: String,
  declaration: builder.Root(a),
  initial: a,
  created: fn(Result(String, error.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  case builder.compile(declaration) {
    Error(reason) ->
      queue_microtask(fn() {
        dispatch(created(Error(error.InvalidSchema(reason))))
      })
    Ok(compiled) -> {
      let _ = {
        use token <- promise.map(watershed.dev_token(
          secret: secret,
          tenant: tenant,
          document: "",
          user_id: "shared-tree-checklist",
        ))
        use outcome <- promise.map(
          watershed.create_tree_container_from_compiled(
            container.CreateConfig(base_url, tenant, token),
            compiled,
            initial,
            container.layout(),
          ),
        )
        queue_microtask(fn() { dispatch(created(outcome)) })
      }
      Nil
    }
  }
}

pub fn open(
  document: watershed.Document(root),
  declaration: builder.Root(a),
  opened: fn(Result(tree.Tree(a), error.Error)) -> msg,
) -> Effect(msg) {
  perform(fn() { watershed.open_tree(document, declaration) }, opened)
}

pub fn subscribe_changes(
  handle: tree.Tree(a),
  subscribed: fn(Result(tree.Subscription, error.Error)) -> msg,
  changed: fn(tree.ChangeEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    tree.subscribe_changes(handle, fn(event) {
      queue_microtask(fn() { dispatch(changed(event)) })
    })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

pub fn subscribe_commits(
  handle: tree.Tree(a),
  subscribed: fn(Result(tree.Subscription, error.Error)) -> msg,
  committed: fn(Result(CommitEvent, error.Error)) -> msg,
  settled: fn(Result(tree.CommitOutcome, error.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    tree.subscribe_commits(handle, fn(event) {
      let tree.CommitEvent(kind, local, get_revertible, on_settled) = event
      let captured = case get_revertible {
        None -> Ok(CommitEvent(kind, local, None))
        Some(acquire) ->
          acquire(fn(_) { Nil })
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

pub fn unsubscribe(subscription: tree.Subscription) -> Effect(msg) {
  use _dispatch <- effect.from
  tree.unsubscribe(subscription)
}

pub fn read_root(
  handle: tree.Tree(a),
  read: fn(Result(a, error.Error)) -> msg,
) -> Effect(msg) {
  perform(fn() { tree.read_root(handle) }, read)
}

pub fn observe(
  handle: tree.Tree(a),
  subscribed: fn(Result(tree.Subscription, error.Error)) -> msg,
  changed: fn(Result(a, error.Error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    tree.observe(handle, fn(value) {
      queue_microtask(fn() { dispatch(changed(value)) })
    })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

pub fn transaction(
  handle: tree.Tree(a),
  constraints: List(tree.Constraint),
  callback: fn(tree.Tree(a)) -> Result(value, callback_error),
  completed: fn(Result(value, tree.TransactionError(callback_error))) -> msg,
) -> Effect(msg) {
  perform(fn() { tree.transaction(handle, constraints, callback) }, completed)
}

pub fn revert(
  revertible: tree.Revertible,
  policy: tree.RevertPolicy,
  completed: fn(Result(Nil, error.Error)) -> msg,
) -> Effect(msg) {
  perform(fn() { tree.revert(revertible, policy) }, completed)
}

pub fn dispose_revertible(
  revertible: tree.Revertible,
  completed: fn(Result(Nil, error.Error)) -> msg,
) -> Effect(msg) {
  perform(fn() { tree.dispose_revertible(revertible) }, completed)
}

pub fn dispose(
  handle: tree.Tree(a),
  completed: fn(Result(Nil, error.Error)) -> msg,
) -> Effect(msg) {
  perform(fn() { tree.dispose(handle) }, completed)
}

pub fn perform(
  operation: fn() -> Result(value, error),
  completed: fn(Result(value, error)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = operation()
  queue_microtask(fn() { dispatch(completed(outcome)) })
}
