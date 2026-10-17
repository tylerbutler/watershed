//// Structured failures from the SharedTree application API.

import gleam/string
import watershed/container
import watershed/tree/types

pub type ReferenceStatus {
  Attached
  Removed
  Deleted
  Invalidated
}

pub type Error {
  InvalidSchema(types.TreeError)
  InvalidValue(types.TreeError)
  CreationFailed(container.CreateError)
  MissingBinding(key: String)
  InvalidHandle(detail: String)
  WrongChannel(expected: String, actual: String)
  IncompatibleView
  WrongProperty(key: String)
  WrongCardinality
  WrongKind(expected: String, actual: String)
  InvalidReference(ReferenceStatus)
  ClosedTree
  DisposedCheckout
  ClosedRuntime
  ForeignOrigin
  NotReady
  TransactionConflict(detail: String)
  ReentrantEdit
  RequestTimeout
  TransportFailed(detail: String)
  RuntimeFailure(detail: String)
}

pub fn to_string(error: Error) -> String {
  case error {
    InvalidSchema(reason) -> "Invalid tree schema: " <> string.inspect(reason)
    InvalidValue(reason) -> "Invalid tree value: " <> string.inspect(reason)
    CreationFailed(reason) -> container.error_to_string(reason)
    MissingBinding(key) -> "Missing tree binding: " <> key
    InvalidHandle(detail) -> "Invalid tree handle: " <> detail
    WrongChannel(expected, actual) ->
      "Expected channel " <> expected <> ", found " <> actual
    IncompatibleView -> "The tree schema is incompatible"
    WrongProperty(key) -> "The property is not declared: " <> key
    WrongCardinality -> "The field cardinality does not match"
    WrongKind(expected, actual) ->
      "Expected tree node " <> expected <> ", found " <> actual
    InvalidReference(status) ->
      "The tree reference is not attached: " <> string.inspect(status)
    ClosedTree -> "The tree handle is closed"
    DisposedCheckout -> "The tree checkout is disposed"
    ClosedRuntime -> "The document is closed"
    ForeignOrigin -> "The tree handles have different origins"
    NotReady -> "The document connection is not ready"
    TransactionConflict(detail) -> "Tree transaction conflict: " <> detail
    ReentrantEdit -> "Tree edits are not allowed during commit delivery"
    RequestTimeout -> "The tree request timed out"
    TransportFailed(detail) -> "Tree transport failed: " <> detail
    RuntimeFailure(detail) -> "Tree runtime failed: " <> detail
  }
}
