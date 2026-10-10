import gleam/list
import gleam/option.{type Option, None, Some}
import watershed/tree/types

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
  kind: types.TreeCommitKind,
  local: Bool,
  entry: Option(entry),
) -> Routed(entry) {
  case local, entry {
    False, _ | _, None -> Routed(history, [])
    True, Some(entry) -> {
      let History(undo:, redo:) = history
      case kind {
        types.DefaultCommit -> Routed(History([entry, ..undo], []), redo)
        types.UndoCommit -> Routed(History(undo, [entry, ..redo]), [])
        types.RedoCommit -> Routed(History([entry, ..undo], redo), [])
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

pub fn consume_undo(history: History(entry)) -> History(entry) {
  let History(undo:, redo:) = history
  History(list.drop(undo, 1), redo)
}

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
