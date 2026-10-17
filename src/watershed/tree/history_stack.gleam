//// Pure undo and redo stacks for application-owned entries.
//// The application acquires, reverts, and disposes each entry.

import gleam/list
import gleam/option.{type Option, None, Some}
import watershed/tree

pub type History(entry) {
  History(undo: List(entry), redo: List(entry))
}

pub type Routed(entry) {
  Routed(history: History(entry), dispose: List(entry))
}

pub fn new() -> History(entry) {
  History([], [])
}

pub fn route(
  history: History(entry),
  kind: tree.CommitKind,
  local: Bool,
  entry: Option(entry),
) -> Routed(entry) {
  case local, entry {
    False, _ | _, None -> Routed(history, [])
    True, Some(entry) -> {
      let History(undo:, redo:) = history
      case kind {
        tree.DefaultCommit -> Routed(History([entry, ..undo], []), redo)
        tree.UndoCommit -> Routed(History(undo, [entry, ..redo]), [])
        tree.RedoCommit -> Routed(History([entry, ..undo], redo), [])
      }
    }
  }
}

pub fn next_undo(history: History(entry)) -> Option(entry) {
  let History(undo:, ..) = history
  case undo {
    [entry, ..] -> Some(entry)
    [] -> None
  }
}

pub fn next_redo(history: History(entry)) -> Option(entry) {
  let History(redo:, ..) = history
  case redo {
    [entry, ..] -> Some(entry)
    [] -> None
  }
}

/// Call after a successful undo. A failed undo must retain its entry.
pub fn consume_undo(history: History(entry)) -> History(entry) {
  let History(undo:, redo:) = history
  History(list.drop(undo, 1), redo)
}

/// Call after a successful redo. A failed redo must retain its entry.
pub fn consume_redo(history: History(entry)) -> History(entry) {
  let History(undo:, redo:) = history
  History(undo, list.drop(redo, 1))
}

pub fn prune(
  history: History(entry),
  keep: fn(entry) -> Bool,
) -> History(entry) {
  let History(undo:, redo:) = history
  History(list.filter(undo, keep), list.filter(redo, keep))
}

pub fn clear(history: History(entry)) -> Routed(entry) {
  let History(undo:, redo:) = history
  Routed(new(), list.append(undo, redo))
}
