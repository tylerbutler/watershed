//// Runtime-local identity and errors for typed tree access.

import gleam/option.{type Option}
import watershed/tree/branch
import watershed/tree/error
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

pub type FieldProof {
  FieldProof(key: String, definition: schema.FieldSchema)
}

pub type Request {
  Bind(schema.ViewSchema)
  Inspect(schema.ViewSchema)
  Close(ViewToken)
  BranchStatus(ViewToken)
  Fork(ViewToken)
  Rebase(ViewToken, ViewToken)
  Merge(ViewToken, ViewToken, Bool)
  Compatibility(ViewToken)
  Upgrade(ViewToken)
  Begin(ViewToken, List(AnchorToken))
  Commit(ViewToken)
  Abort(ViewToken)
  Revert(types.RevertibleId, Bool)
  DisposeRevertible(types.RevertibleId)
  RevertibleStatus(types.RevertibleId)
  RootRead(ViewToken)
  RootReplace(ViewToken, Option(types.TreeValue))
  RootAcquire(ViewToken, schema.Cardinality)
  Read(AnchorToken)
  Status(AnchorToken)
  PropertyRead(AnchorToken, FieldProof)
  PropertySet(AnchorToken, FieldProof, Option(types.TreeValue))
  ChildAcquire(AnchorToken, FieldProof)
  ArrayRead(AnchorToken, Int)
  ArrayAcquire(AnchorToken, Int)
  ArrayInsert(AnchorToken, Int, List(types.TreeValue))
  ArrayRemove(AnchorToken, Int, Int)
  ArrayMove(AnchorToken, Int, Int, AnchorToken, Int)
  ArrayRemoveNode(AnchorToken, AnchorToken)
  ArrayMoveBefore(AnchorToken, AnchorToken, AnchorToken, Option(AnchorToken))
  MapRead(AnchorToken, String)
  MapAcquire(AnchorToken, String)
  MapSet(AnchorToken, String, types.TreeValue)
  MapDelete(AnchorToken, String)
  Narrow(AnchorToken, List(String))
}

pub type NodeEvidence {
  NodeEvidence(
    anchor: AnchorToken,
    identifier: String,
    snapshot: types.TreeValue,
  )
}

pub type Response {
  Bound(ViewToken)
  Done
  Snapshot(Option(types.TreeValue))
  Acquired(Option(NodeEvidence))
  ReferenceState(error.ReferenceStatus)
  SchemaCompatibility(schema.Compatibility)
  RevertibleState(Bool)
  BranchState(types.TreeBranchStatus)
}

@internal
pub fn writes(request: Request) -> Bool {
  case request {
    RootReplace(_, _)
    | Fork(_)
    | Rebase(_, _)
    | Merge(_, _, _)
    | Upgrade(_)
    | Begin(_, _)
    | Commit(_)
    | Abort(_)
    | Revert(_, _)
    | PropertySet(_, _, _)
    | ArrayInsert(_, _, _)
    | ArrayRemove(_, _, _)
    | ArrayMove(_, _, _, _, _)
    | ArrayRemoveNode(_, _)
    | ArrayMoveBefore(_, _, _, _)
    | MapSet(_, _, _)
    | MapDelete(_, _) -> True
    _ -> False
  }
}

@internal
pub fn checkout(token: ViewToken) -> types.CheckoutSelector {
  token.checkout
}

@internal
pub fn same_origin(first: ViewToken, second: ViewToken) -> Bool {
  first.origin == second.origin
}

pub opaque type ViewToken {
  ViewToken(
    origin: branch.Origin,
    checkout: types.CheckoutSelector,
    ordinal: Int,
  )
}

pub opaque type AnchorToken {
  AnchorToken(view: ViewToken, ordinal: Int)
}

pub type IdentityChange {
  Promote(before: forest.NodeRef, after: forest.NodeRef)
  Discard(reference: forest.NodeRef)
  Forget(reference: forest.NodeRef)
}

@internal
pub fn view_token(
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  ordinal: Int,
) -> ViewToken {
  ViewToken(origin, checkout, ordinal)
}

@internal
pub fn anchor_token(view: ViewToken, ordinal: Int) -> AnchorToken {
  AnchorToken(view, ordinal)
}

@internal
pub fn anchor_view(token: AnchorToken) -> ViewToken {
  token.view
}

@internal
pub fn view_matches(
  token: ViewToken,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
) -> Bool {
  token.origin == origin && token.checkout == checkout
}
