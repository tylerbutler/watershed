import gleam/javascript/promise
import gleam/option.{type Option}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
import watershed/tree_kernel

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

pub fn create(
  config: container.CreateConfig,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use outcome <- promise.map(watershed.create_tree_container(
      config,
      stored,
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
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
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
      stored,
      initial_root,
    ))
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn open(
  document: watershed.Document(root),
  view: tree_schema.ViewSchema,
  opened: fn(Result(watershed.SharedTree, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  queue_microtask(fn() {
    let outcome = {
      use root <- result.try(watershed.resolve_root(document))
      use handle <- result.try(
        watershed.get(root, "tree")
        |> result.replace_error("tree handle is absent"),
      )
      watershed.resolve_tree(document, handle, view)
    }
    dispatch(opened(outcome))
  })
}

pub fn subscribe(
  tree: watershed.SharedTree,
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

pub fn unsubscribe(subscription: watershed.SubscriptionToken) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.unsubscribe(subscription)
}

pub fn read_root(
  tree: watershed.SharedTree,
  read: fn(Result(Option(tree_types.TreeValue), String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  queue_microtask(fn() { dispatch(read(watershed.tree_get(tree, []))) })
}

pub fn perform(
  operation: fn() -> Result(Nil, String),
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = operation()
  queue_microtask(fn() { dispatch(completed(outcome)) })
}
