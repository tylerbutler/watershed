//// Typed snapshots, identity references, and checkout-local tree operations.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/callback
import watershed/fluid_ids
import watershed/tree/error as tree_error
import watershed/tree/live_types as protocol
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
import watershed/tree_kernel

@internal
pub type Backend {
  Backend(
    request: fn(protocol.Request) -> Result(protocol.Response, tree_error.Error),
    subscribe: fn(fn(CommitEvent) -> Nil) ->
      Result(fn() -> Nil, tree_error.Error),
    changes: fn(fn(ChangeEvent) -> Nil) -> Result(fn() -> Nil, tree_error.Error),
    rebind: fn(protocol.ViewToken) -> Backend,
  )
}

type Encoding {
  Snapshot
  NewContent
}

type Codec(a) {
  Codec(
    encode: fn(Encoding, a) -> Result(Option(types.TreeValue), types.TreeError),
    decode: fn(Option(types.TreeValue)) -> Result(a, types.TreeError),
  )
}

pub opaque type Tree(a) {
  Tree(
    token: protocol.ViewToken,
    compiled: builder.Compiled(a),
    backend: Backend,
  )
}

pub opaque type Ref(a) {
  Ref(
    anchor: protocol.AnchorToken,
    identifier: String,
    codec: Codec(a),
    backend: Backend,
  )
}

pub opaque type Subscription {
  Subscription(cancel: fn() -> Nil)
}

pub type SourcePolicy {
  KeepSource
  DisposeSource
}

pub type TransactionError(callback_error) {
  Aborted(callback_error)
  TransactionFailed(tree_error.Error)
}

pub type CommitKind {
  DefaultCommit
  UndoCommit
  RedoCommit
}

pub type ChangeEvent {
  SchemaChanged(local: Bool)
  TreeChanged(local: Bool)
}

@internal
pub fn from_change(event: tree_kernel.TreeEvent) -> ChangeEvent {
  case event {
    tree_kernel.SchemaChanged(local) -> SchemaChanged(local)
    tree_kernel.TreeChanged(local) -> TreeChanged(local)
  }
}

pub fn subscribe_changes(
  tree: Tree(a),
  handler: fn(ChangeEvent) -> Nil,
) -> Result(Subscription, tree_error.Error) {
  tree.backend.changes(handler) |> result.map(Subscription)
}

pub type CommitOutcome {
  FullyApplied
  FullyDropped
  NewContentOnly
}

pub type RevertPolicy {
  KeepRevertible
  DisposeRevertible
}

pub type RevertibleStatus {
  RevertibleValid
  RevertibleDisposed
}

pub opaque type Revertible {
  Revertible(
    backend: Backend,
    id: types.RevertibleId,
    revision: fluid_ids.StableId,
  )
}

pub type CommitEvent {
  CommitEvent(
    kind: CommitKind,
    local: Bool,
    get_revertible: Option(
      fn(fn(Revertible) -> Nil) -> Result(Revertible, tree_error.Error),
    ),
    on_settled: Option(
      fn(fn(CommitOutcome) -> Nil) -> Result(Nil, tree_error.Error),
    ),
  )
}

@internal
pub type RevertibleIdentity =
  #(types.RevertibleId, fluid_ids.StableId)

@internal
pub fn from_commit(
  backend: Backend,
  kind: types.TreeCommitKind,
  local: Bool,
  acquire: Option(
    fn(fn(RevertibleIdentity) -> Nil) ->
      Result(RevertibleIdentity, tree_error.Error),
  ),
  settled: Option(
    fn(fn(types.TreeCommitOutcome) -> Nil) -> Result(Nil, tree_error.Error),
  ),
) -> CommitEvent {
  let wrap = fn(identity: RevertibleIdentity) {
    Revertible(backend, identity.0, identity.1)
  }
  CommitEvent(
    kind: case kind {
      types.DefaultCommit -> DefaultCommit
      types.UndoCommit -> UndoCommit
      types.RedoCommit -> RedoCommit
    },
    local: local,
    get_revertible: option.map(acquire, fn(acquire) {
      fn(on_disposed) {
        acquire(fn(identity) { on_disposed(wrap(identity)) })
        |> result.map(wrap)
      }
    }),
    on_settled: option.map(settled, fn(register) {
      fn(handler) {
        register(fn(outcome) {
          handler(case outcome {
            types.FullyApplied -> FullyApplied
            types.FullyDropped -> FullyDropped
            types.NewContentOnly -> NewContentOnly
          })
        })
      }
    }),
  )
}

pub fn subscribe_commits(
  tree: Tree(a),
  handler: fn(CommitEvent) -> Nil,
) -> Result(Subscription, tree_error.Error) {
  tree.backend.subscribe(handler) |> result.map(Subscription)
}

pub fn get_revertible(
  event: CommitEvent,
  on_disposed: fn(Revertible) -> Nil,
) -> Result(Revertible, tree_error.Error) {
  use acquire <- result.try(
    event.get_revertible
    |> option.to_result(tree_error.RuntimeFailure(
      "The commit does not provide a revertible",
    )),
  )
  acquire(on_disposed)
}

pub fn revertible_revision(revertible: Revertible) -> fluid_ids.StableId {
  revertible.revision
}

pub fn revertible_status(
  revertible: Revertible,
) -> Result(RevertibleStatus, tree_error.Error) {
  case revertible.backend.request(protocol.RevertibleStatus(revertible.id)) {
    Ok(protocol.RevertibleState(True)) -> Ok(RevertibleValid)
    Ok(protocol.RevertibleState(False))
    | Error(tree_error.ClosedRuntime)
    | Error(tree_error.DisposedCheckout) -> Ok(RevertibleDisposed)
    Ok(_) -> unexpected()
    Error(error) -> Error(error)
  }
}

pub fn revert(
  revertible: Revertible,
  policy: RevertPolicy,
) -> Result(Nil, tree_error.Error) {
  done(
    revertible.backend,
    protocol.Revert(revertible.id, policy == DisposeRevertible),
  )
}

pub fn dispose_revertible(
  revertible: Revertible,
) -> Result(Nil, tree_error.Error) {
  case done(revertible.backend, protocol.DisposeRevertible(revertible.id)) {
    Error(tree_error.ClosedRuntime) | Error(tree_error.DisposedCheckout) ->
      Ok(Nil)
    outcome -> outcome
  }
}

pub opaque type Constraint {
  NodeInDocument(protocol.AnchorToken)
}

pub fn node_in_document(reference: Ref(a)) -> Constraint {
  NodeInDocument(reference.anchor)
}

pub fn fork(tree: Tree(a)) -> Result(Tree(a), tree_error.Error) {
  use response <- result.try(tree.backend.request(protocol.Fork(tree.token)))
  case response {
    protocol.Bound(token) ->
      Ok(from_bound(tree.compiled, tree.backend.rebind(token), token))
    _ -> unexpected()
  }
}

pub fn rebase_onto(
  source: Tree(a),
  target: Tree(a),
) -> Result(Nil, tree_error.Error) {
  done(source.backend, protocol.Rebase(source.token, target.token))
}

pub fn merge(
  target: Tree(a),
  source: Tree(a),
  policy: SourcePolicy,
) -> Result(Nil, tree_error.Error) {
  done(
    target.backend,
    protocol.Merge(target.token, source.token, policy == DisposeSource),
  )
}

pub fn compatibility(
  tree: Tree(a),
) -> Result(schema.Compatibility, tree_error.Error) {
  use response <- result.try(
    tree.backend.request(protocol.Compatibility(tree.token)),
  )
  case response {
    protocol.SchemaCompatibility(value) -> Ok(value)
    _ -> unexpected()
  }
}

pub fn upgrade_schema(tree: Tree(a)) -> Result(Nil, tree_error.Error) {
  done(tree.backend, protocol.Upgrade(tree.token))
}

pub fn transaction(
  tree: Tree(a),
  constraints: List(Constraint),
  callback: fn(Tree(a)) -> Result(value, callback_error),
) -> Result(value, TransactionError(callback_error)) {
  let anchors =
    list.map(constraints, fn(value) {
      let NodeInDocument(anchor) = value
      anchor
    })
  use _ <- result.try(
    done(tree.backend, protocol.Begin(tree.token, anchors))
    |> result.map_error(TransactionFailed),
  )
  case callback.capture(fn() { callback(tree) }) {
    Ok(Ok(value)) ->
      case done(tree.backend, protocol.Commit(tree.token)) {
        Ok(Nil) -> Ok(value)
        Error(error) -> Error(transaction_failure(tree, error))
      }
    Ok(Error(error)) ->
      case done(tree.backend, protocol.Abort(tree.token)) {
        Ok(Nil) -> Error(Aborted(error))
        Error(error) -> Error(TransactionFailed(error))
      }
    Error(reason) ->
      Error(transaction_failure(tree, tree_error.RuntimeFailure(reason)))
  }
}

fn transaction_failure(
  tree: Tree(a),
  cause: tree_error.Error,
) -> TransactionError(e) {
  TransactionFailed(case done(tree.backend, protocol.Abort(tree.token)) {
    Ok(Nil) -> cause
    Error(rollback) -> tree_error.TransactionRollbackFailed(cause, rollback)
  })
}

@internal
pub fn bind(
  compiled: builder.Compiled(a),
  backend: Backend,
) -> Result(Tree(a), tree_error.Error) {
  use response <- result.try(
    backend.request(protocol.Bind(builder.view(compiled))),
  )
  case response {
    protocol.Bound(token) -> Ok(from_bound(compiled, backend, token))
    _ -> unexpected()
  }
}

@internal
pub fn from_bound(
  compiled: builder.Compiled(a),
  backend: Backend,
  token: protocol.ViewToken,
) -> Tree(a) {
  Tree(token, compiled, backend)
}

fn unexpected() -> Result(a, tree_error.Error) {
  Error(tree_error.RuntimeFailure("Unexpected typed tree response"))
}

fn codec(compiled: builder.Compiled(a)) -> Codec(a) {
  Codec(
    fn(mode, value) {
      case mode {
        Snapshot -> builder.encode(compiled, value)
        NewContent -> builder.encode_new(compiled, value)
      }
    },
    builder.decode(compiled, _),
  )
}

fn absent() -> types.TreeError {
  types.InvalidEdit([], "Required typed value is absent")
}

fn unwrap(optional: Codec(Option(a))) -> Codec(a) {
  Codec(fn(mode, value) { optional.encode(mode, Some(value)) }, fn(snapshot) {
    use value <- result.try(optional.decode(snapshot))
    option.to_result(value, absent())
  })
}

fn snapshot(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
) -> Result(a, tree_error.Error) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Snapshot(value) ->
      codec.decode(value) |> result.map_error(tree_error.InvalidValue)
    _ -> unexpected()
  }
}

fn done(
  backend: Backend,
  request: protocol.Request,
) -> Result(Nil, tree_error.Error) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Done -> Ok(Nil)
    _ -> unexpected()
  }
}

fn evidence(
  backend: Backend,
  codec: Codec(a),
  node: protocol.NodeEvidence,
  view: protocol.ViewToken,
) -> Result(Ref(a), tree_error.Error) {
  use _ <- result.try(case protocol.anchor_view(node.anchor) == view {
    True -> Ok(Nil)
    False -> Error(tree_error.ForeignOrigin)
  })
  use _ <- result.try(case node.snapshot {
    types.ObjectValue(_, _) | types.ArrayValue(_, _) | types.MapValue(_, _) ->
      Ok(Nil)
    _ -> Error(tree_error.WrongKind("composite", node.identifier))
  })
  use _ <- result.try(
    case schema.value_identifier(node.snapshot) == node.identifier {
      True -> Ok(Nil)
      False ->
        Error(tree_error.RuntimeFailure(
          "Node evidence has an incorrect identifier",
        ))
    },
  )
  use _ <- result.try(
    codec.decode(Some(node.snapshot))
    |> result.map_error(tree_error.InvalidValue),
  )
  Ok(Ref(node.anchor, node.identifier, codec, backend))
}

fn acquire(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
  view: protocol.ViewToken,
) -> Result(Option(Ref(a)), tree_error.Error) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Acquired(None) -> Ok(None)
    protocol.Acquired(Some(node)) ->
      evidence(backend, codec, node, view) |> result.map(Some)
    _ -> unexpected()
  }
}

fn require(reference: Option(Ref(a))) -> Result(Ref(a), tree_error.Error) {
  option.to_result(reference, tree_error.InvalidValue(absent()))
}

pub fn read_root(view: Tree(a)) -> Result(a, tree_error.Error) {
  snapshot(view.backend, protocol.RootRead(view.token), codec(view.compiled))
}

pub fn replace_root(view: Tree(a), value: a) -> Result(Nil, tree_error.Error) {
  replace(view, value, Snapshot)
}

pub fn replace_root_new(
  view: Tree(a),
  value: a,
) -> Result(Nil, tree_error.Error) {
  replace(view, value, NewContent)
}

fn replace(
  view: Tree(a),
  value: a,
  mode: Encoding,
) -> Result(Nil, tree_error.Error) {
  use encoded <- result.try(
    codec(view.compiled).encode(mode, value)
    |> result.map_error(tree_error.InvalidValue),
  )
  done(view.backend, protocol.RootReplace(view.token, encoded))
}

pub fn required_root(view: Tree(a)) -> Result(Ref(a), tree_error.Error) {
  use _ <- result.try(cardinality(
    builder.root_cardinality(view.compiled),
    schema.Required,
  ))
  use reference <- result.try(acquire(
    view.backend,
    protocol.RootAcquire(view.token, schema.Required),
    codec(view.compiled),
    view.token,
  ))
  require(reference)
}

pub fn optional_root(
  view: Tree(Option(a)),
) -> Result(Option(Ref(a)), tree_error.Error) {
  use _ <- result.try(cardinality(
    builder.root_cardinality(view.compiled),
    schema.Optional,
  ))
  acquire(
    view.backend,
    protocol.RootAcquire(view.token, schema.Optional),
    unwrap(codec(view.compiled)),
    view.token,
  )
}

pub fn read(reference: Ref(a)) -> Result(a, tree_error.Error) {
  snapshot(reference.backend, protocol.Read(reference.anchor), reference.codec)
}

pub fn status(
  reference: Ref(a),
) -> Result(tree_error.ReferenceStatus, tree_error.Error) {
  use response <- result.try(
    reference.backend.request(protocol.Status(reference.anchor)),
  )
  case response {
    protocol.ReferenceState(status) -> Ok(status)
    _ -> unexpected()
  }
}

pub fn dispose(view: Tree(a)) -> Result(Nil, tree_error.Error) {
  case done(view.backend, protocol.Close(view.token)) {
    Error(tree_error.ClosedRuntime) -> Ok(Nil)
    outcome -> outcome
  }
}

fn property_codec(
  property: builder.Property(record, a),
) -> Result(Codec(a), tree_error.Error) {
  builder.property_root(property)
  |> builder.compile
  |> result.map(codec)
  |> result.map_error(tree_error.InvalidSchema)
}

fn proof(property: builder.Property(record, a)) -> protocol.FieldProof {
  let #(key, field) = builder.property_definition(property)
  protocol.FieldProof(key, field)
}

fn cardinality(
  actual: schema.Cardinality,
  expected: schema.Cardinality,
) -> Result(Nil, tree_error.Error) {
  case actual == expected {
    True -> Ok(Nil)
    False -> Error(tree_error.WrongCardinality)
  }
}

pub fn get(
  reference: Ref(record),
  property: builder.Property(record, a),
) -> Result(a, tree_error.Error) {
  use codec <- result.try(property_codec(property))
  snapshot(
    reference.backend,
    protocol.PropertyRead(reference.anchor, proof(property)),
    codec,
  )
}

pub fn set(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
) -> Result(Nil, tree_error.Error) {
  set_property(reference, property, value, Snapshot)
}

pub fn set_new(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
) -> Result(Nil, tree_error.Error) {
  set_property(reference, property, value, NewContent)
}

fn set_property(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
  mode: Encoding,
) -> Result(Nil, tree_error.Error) {
  use codec <- result.try(property_codec(property))
  use value <- result.try(
    codec.encode(mode, value) |> result.map_error(tree_error.InvalidValue),
  )
  done(
    reference.backend,
    protocol.PropertySet(reference.anchor, proof(property), value),
  )
}

pub fn child(
  reference: Ref(record),
  property: builder.Property(record, a),
) -> Result(Ref(a), tree_error.Error) {
  use _ <- result.try(cardinality(
    proof(property).definition.cardinality,
    schema.Required,
  ))
  use codec <- result.try(property_codec(property))
  use child <- result.try(acquire(
    reference.backend,
    protocol.ChildAcquire(reference.anchor, proof(property)),
    codec,
    protocol.anchor_view(reference.anchor),
  ))
  require(child)
}

pub fn optional_child(
  reference: Ref(record),
  property: builder.Property(record, Option(a)),
) -> Result(Option(Ref(a)), tree_error.Error) {
  use _ <- result.try(cardinality(
    proof(property).definition.cardinality,
    schema.Optional,
  ))
  use codec <- result.try(property_codec(property))
  acquire(
    reference.backend,
    protocol.ChildAcquire(reference.anchor, proof(property)),
    unwrap(codec),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn narrow(
  reference: Ref(sum),
  node: builder.Node(a),
) -> Result(Option(Ref(a)), tree_error.Error) {
  use compiled <- result.try(
    builder.compile(builder.root(node))
    |> result.map_error(tree_error.InvalidSchema),
  )
  acquire(
    reference.backend,
    protocol.Narrow(reference.anchor, builder.allowed_types(node)),
    codec(compiled),
    protocol.anchor_view(reference.anchor),
  )
}

fn array_codec(reference: Ref(List(a))) -> Codec(a) {
  Codec(
    fn(mode, value) {
      use encoded <- result.try(reference.codec.encode(mode, [value]))
      case encoded {
        Some(types.ArrayValue(identifier, [value]))
          if identifier == reference.identifier
        -> Ok(Some(value))
        _ ->
          Error(types.CorruptData("typed tree", "Invalid array codec result"))
      }
    },
    fn(snapshot) {
      use value <- result.try(option.to_result(snapshot, absent()))
      use values <- result.try(
        reference.codec.decode(
          Some(types.ArrayValue(reference.identifier, [value])),
        ),
      )
      case values {
        [value] -> Ok(value)
        _ ->
          Error(types.CorruptData("typed tree", "Invalid array codec result"))
      }
    },
  )
}

fn optional_snapshot(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
) -> Result(Option(a), tree_error.Error) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Snapshot(None) -> Ok(None)
    protocol.Snapshot(Some(value)) ->
      codec.decode(Some(value))
      |> result.map(Some)
      |> result.map_error(tree_error.InvalidValue)
    _ -> unexpected()
  }
}

pub fn array_get(
  reference: Ref(List(a)),
  index: Int,
) -> Result(Option(a), tree_error.Error) {
  optional_snapshot(
    reference.backend,
    protocol.ArrayRead(reference.anchor, index),
    array_codec(reference),
  )
}

pub fn array_node(
  reference: Ref(List(a)),
  index: Int,
) -> Result(Option(Ref(a)), tree_error.Error) {
  acquire(
    reference.backend,
    protocol.ArrayAcquire(reference.anchor, index),
    array_codec(reference),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn array_insert(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
) -> Result(Nil, tree_error.Error) {
  insert(reference, index, values, Snapshot)
}

pub fn array_insert_new(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
) -> Result(Nil, tree_error.Error) {
  insert(reference, index, values, NewContent)
}

fn insert(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
  mode: Encoding,
) -> Result(Nil, tree_error.Error) {
  use encoded <- result.try(
    reference.codec.encode(mode, values)
    |> result.map_error(tree_error.InvalidValue),
  )
  case encoded {
    Some(types.ArrayValue(identifier, values))
      if identifier == reference.identifier
    ->
      done(
        reference.backend,
        protocol.ArrayInsert(reference.anchor, index, values),
      )
    _ -> Error(tree_error.WrongKind("array", reference.identifier))
  }
}

pub fn array_remove(
  reference: Ref(List(a)),
  start: Int,
  end: Int,
) -> Result(Nil, tree_error.Error) {
  done(reference.backend, protocol.ArrayRemove(reference.anchor, start, end))
}

pub fn array_move(
  source: Ref(List(a)),
  start: Int,
  end: Int,
  destination: Ref(List(a)),
  gap: Int,
) -> Result(Nil, tree_error.Error) {
  done(
    source.backend,
    protocol.ArrayMove(source.anchor, start, end, destination.anchor, gap),
  )
}

pub fn array_remove_node(
  source: Ref(List(a)),
  item: Ref(a),
) -> Result(Nil, tree_error.Error) {
  done(source.backend, protocol.ArrayRemoveNode(source.anchor, item.anchor))
}

pub fn array_move_before(
  source: Ref(List(a)),
  item: Ref(a),
  destination: Ref(List(a)),
  before: Option(Ref(a)),
) -> Result(Nil, tree_error.Error) {
  done(
    source.backend,
    protocol.ArrayMoveBefore(
      source.anchor,
      item.anchor,
      destination.anchor,
      option.map(before, fn(reference) { reference.anchor }),
    ),
  )
}

fn map_codec(reference: Ref(Dict(String, a))) -> Codec(a) {
  Codec(
    fn(mode, value) {
      use encoded <- result.try(reference.codec.encode(
        mode,
        dict.from_list([#("", value)]),
      ))
      case encoded {
        Some(types.MapValue(identifier, [#("", value)]))
          if identifier == reference.identifier
        -> Ok(Some(value))
        _ -> Error(types.CorruptData("typed tree", "Invalid map codec result"))
      }
    },
    fn(snapshot) {
      use value <- result.try(option.to_result(snapshot, absent()))
      use values <- result.try(
        reference.codec.decode(
          Some(types.MapValue(reference.identifier, [#("", value)])),
        ),
      )
      dict.get(values, "")
      |> result.map_error(fn(_) {
        types.CorruptData("typed tree", "Invalid map codec result")
      })
    },
  )
}

pub fn map_get(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Option(a), tree_error.Error) {
  optional_snapshot(
    reference.backend,
    protocol.MapRead(reference.anchor, key),
    map_codec(reference),
  )
}

pub fn map_node(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Option(Ref(a)), tree_error.Error) {
  acquire(
    reference.backend,
    protocol.MapAcquire(reference.anchor, key),
    map_codec(reference),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn map_set(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
) -> Result(Nil, tree_error.Error) {
  set_map(reference, key, value, Snapshot)
}

pub fn map_set_new(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
) -> Result(Nil, tree_error.Error) {
  set_map(reference, key, value, NewContent)
}

fn set_map(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
  mode: Encoding,
) -> Result(Nil, tree_error.Error) {
  use encoded <- result.try(
    map_codec(reference).encode(mode, value)
    |> result.map_error(tree_error.InvalidValue),
  )
  case encoded {
    Some(value) ->
      done(reference.backend, protocol.MapSet(reference.anchor, key, value))
    None -> Error(tree_error.InvalidValue(absent()))
  }
}

pub fn map_delete(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Nil, tree_error.Error) {
  done(reference.backend, protocol.MapDelete(reference.anchor, key))
}

pub fn observe(
  view: Tree(a),
  handler: fn(Result(a, tree_error.Error)) -> Nil,
) -> Result(Subscription, tree_error.Error) {
  use _ <- result.try(read_root(view))
  use cancel <- result.try(
    view.backend.subscribe(fn(_) { handler(read_root(view)) }),
  )
  Ok(Subscription(cancel))
}

pub fn observe_node(
  reference: Ref(a),
  handler: fn(Result(a, tree_error.Error)) -> Nil,
) -> Result(Subscription, tree_error.Error) {
  use _ <- result.try(read(reference))
  use cancel <- result.try(
    reference.backend.subscribe(fn(_) { handler(read(reference)) }),
  )
  Ok(Subscription(cancel))
}

pub fn unsubscribe(subscription: Subscription) -> Nil {
  subscription.cancel()
}
