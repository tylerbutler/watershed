//// Runtime-local identity and errors for typed tree access.

import gleam/option.{type Option}
import watershed/tree/branch
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

pub type FieldProof {
  FieldProof(key: String, definition: schema.FieldSchema)
}

pub type Request {
  Bind(schema.ViewSchema)
  Close(ViewToken)
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
  ReferenceState(ReferenceStatus)
}

pub type ReferenceStatus {
  Attached
  Removed
  Deleted
  Invalidated
}

pub type LiveError {
  InvalidSchema(types.TreeError)
  InvalidValue(types.TreeError)
  IncompatibleView
  WrongProperty(key: String)
  WrongCardinality
  WrongKind(expected: String, actual: String)
  InvalidReference(ReferenceStatus)
  ClosedView
  DisposedCheckout
  ClosedRuntime
  ForeignOrigin
  RuntimeFailure(detail: String)
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
