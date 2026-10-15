//// Runtime-local identity and errors for typed tree access.

import watershed/tree/branch
import watershed/tree/forest
import watershed/tree/types

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
