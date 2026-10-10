import gleam/list
import gleam/option.{type Option, None, Some}
import shared_tree_checklist_lustre/history
import watershed/tree/types

pub type Action {
  Undoing
  Redoing
}

pub type State(entry) {
  State(history: history.History(entry), action: Option(Action), pending: Int)
}

pub type Transition(entry) {
  Transition(state: State(entry), dispose: List(entry), error: Option(String))
}

pub type Close(entry, token) {
  Close(state: State(entry), unsubscribe: List(token), dispose: List(entry))
}

pub type Subscription(token) {
  Retain(token)
  Unsubscribe(token)
}

pub type Disposal(entry) {
  Disposal(state: State(entry), error: Option(String), close_ready: Bool)
}

pub fn request(
  state: State(entry),
  action: Action,
) -> #(State(entry), Option(entry)) {
  let State(history:, ..) = state
  let next = case action {
    Undoing -> history.next_undo(history)
    Redoing -> history.next_redo(history)
  }
  case next {
    None -> #(state, None)
    Some(entry) -> #(
      State(..state, action: Some(action), pending: state.pending + 1),
      Some(entry),
    )
  }
}

pub fn captured(
  state: State(entry),
  accepting: Bool,
  outcome: Result(#(types.TreeCommitKind, Bool, Option(entry)), String),
) -> Transition(entry) {
  case outcome {
    Error(detail) ->
      Transition(state, [], Some("Commit capture failed: " <> detail))
    Ok(#(kind, local, entry)) ->
      case accepting {
        True -> {
          let history.Routed(next, dispose) =
            history.route(state.history, kind, local, entry)
          Transition(State(..state, history: next), dispose, None)
        }
        False ->
          Transition(
            state,
            case entry {
              Some(entry) -> [entry]
              None -> []
            },
            None,
          )
      }
  }
}

pub fn settled(
  outcome: Result(types.TreeCommitOutcome, String),
) -> Option(String) {
  case outcome {
    Ok(types.FullyApplied) -> None
    Ok(types.FullyDropped) -> Some("Commit settlement dropped the full change")
    Ok(types.NewContentOnly) ->
      Some("Commit settlement applied only new content")
    Error(detail) -> Some("Commit settlement failed: " <> detail)
  }
}

pub fn history_finished(
  state: State(entry),
  outcome: Result(Nil, String),
) -> Transition(entry) {
  let state = State(..state, pending: decrement(state.pending))
  case outcome, state.action {
    Ok(Nil), Some(Undoing) ->
      Transition(
        State(
          ..state,
          history: history.consume_undo(state.history),
          action: None,
        ),
        [],
        None,
      )
    Ok(Nil), Some(Redoing) ->
      Transition(
        State(
          ..state,
          history: history.consume_redo(state.history),
          action: None,
        ),
        [],
        None,
      )
    Error(detail), _ ->
      Transition(
        State(..state, action: None),
        [],
        Some("History action failed: " <> detail),
      )
    _, None -> Transition(State(..state, action: None), [], None)
  }
}

pub fn close(
  state: State(entry),
  change_subscription: Option(token),
  commit_subscription: Option(token),
) -> Close(entry, token) {
  let history.Routed(empty, dispose) = history.clear(state.history)
  let unsubscribe =
    [change_subscription, commit_subscription]
    |> list.flat_map(fn(subscription) {
      case subscription {
        Some(token) -> [token]
        None -> []
      }
    })
  Close(
    State(history: empty, action: None, pending: list.length(dispose)),
    unsubscribe,
    dispose,
  )
}

pub fn subscription(accepting: Bool, token: token) -> Subscription(token) {
  case accepting {
    True -> Retain(token)
    False -> Unsubscribe(token)
  }
}

pub fn disposal_finished(
  state: State(entry),
  outcome: Result(Nil, String),
) -> Disposal(entry) {
  let state = State(..state, pending: decrement(state.pending))
  Disposal(
    state,
    case outcome {
      Ok(Nil) -> None
      Error(detail) -> Some("History disposal failed: " <> detail)
    },
    state.pending == 0,
  )
}

fn decrement(value: Int) -> Int {
  case value > 0 {
    True -> value - 1
    False -> 0
  }
}
