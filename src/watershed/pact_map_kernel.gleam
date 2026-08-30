//// Pure port of FluidFramework's PactMap quorum protocol.
////
//// A set operation first becomes pending. When the set operation sequences,
//// the kernel records a frozen signoff list from the connected quorum. The
//// value becomes accepted when accept operations and membership leaves remove
//// every client from that signoff list.

import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type PactMapState {
  PactMapState(values: Dict(String, Pact))
}

pub type Pact {
  Pact(accepted: Option(Accepted), pending: Option(Pending))
}

pub type Accepted {
  Accepted(value: Option(Json), sequence_number: Int)
}

pub type Pending {
  Pending(value: Option(Json), expected_signoffs: List(Int))
}

pub type PactMapOperation {
  Set(key: String, value: Option(Json), reference_sequence_number: Int)
  Accept(key: String)
}

pub type PactMapEvent {
  WentPending(key: String)
  WentAccepted(key: String)
}

pub type SetReaction {
  OweAccept(operation: PactMapOperation)
  NoReaction
}

pub type KernelError {
  UnexpectedAccept(key: String, client: Int, detail: String)
}

/// The reasons that the kernel refuses to build an operation for a local
/// proposal. Each reason changes nothing, and the caller can retry later.
pub type ProposeError {
  /// A proposal for this key waits for signoffs now. One key holds one
  /// pending proposal at a time.
  ProposalAlreadyPending(key: String)
  /// A delete needs a value to delete, and this key holds none.
  KeyNotFound(key: String)
  /// A delete needs a value to delete, and a client already deleted this key.
  KeyAlreadyDeleted(key: String)
}

pub fn new() -> PactMapState {
  PactMapState(values: dict.new())
}

pub fn from_summary(entries: List(#(String, Pact))) -> PactMapState {
  let values =
    entries
    |> list.fold(dict.new(), fn(values, entry) {
      let #(key, pact) = entry
      dict.insert(values, key, pact)
    })
  PactMapState(values:)
}

pub fn summary_entries(state: PactMapState) -> List(#(String, Pact)) {
  dict.to_list(state.values) |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// The accepted value for `key`. The result is `Error(Nil)` when the key holds
/// no accepted value, and when the room accepted a delete for it.
pub fn get(state: PactMapState, key: String) -> Result(Json, Nil) {
  case dict.get(state.values, key) {
    Ok(Pact(Some(Accepted(Some(value), _)), _)) -> Ok(value)
    Ok(Pact(Some(Accepted(None, _)), _)) | Ok(Pact(None, _)) | Error(Nil) ->
      Error(Nil)
  }
}

/// The accepted entry for `key`, which is the value with its sequence number.
pub fn get_with_details(
  state: PactMapState,
  key: String,
) -> Result(Accepted, Nil) {
  case dict.get(state.values, key) {
    Ok(Pact(Some(accepted), _)) -> Ok(accepted)
    Ok(Pact(None, _)) | Error(Nil) -> Error(Nil)
  }
}

pub fn is_pending(state: PactMapState, key: String) -> Bool {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(_))) -> True
    Ok(Pact(_, None)) | Error(Nil) -> False
  }
}

/// The value that a client proposed for `key` and no room accepted yet. The
/// inner `Option` holds the proposal itself: `None` is a proposal to delete
/// the key.
pub fn get_pending(
  state: PactMapState,
  key: String,
) -> Result(Option(Json), Nil) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(Pending(value, _)))) -> Ok(value)
    Ok(Pact(_, None)) | Error(Nil) -> Error(Nil)
  }
}

/// The full pending proposal for `key`, with the signoff list that it waits
/// on. `get_pending` gives the value that is pending. This function gives the
/// clients that must sign off. Only that list can explain a stalled pact to a
/// user.
pub fn pending(state: PactMapState, key: String) -> Result(Pending, Nil) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(pending))) -> Ok(pending)
    Ok(Pact(_, None)) | Error(Nil) -> Error(Nil)
  }
}

pub fn keys(state: PactMapState) -> List(String) {
  dict.keys(state.values) |> list.sort(string.compare)
}

/// Build the operation for a local proposal. `value` is `None` for a proposal
/// to delete the key.
pub fn set(
  state: PactMapState,
  key: String,
  value: Option(Json),
  last_seen_sequence_number: Int,
) -> Result(PactMapOperation, ProposeError) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(_))) -> Error(ProposalAlreadyPending(key))
    Ok(Pact(_, None)) | Error(Nil) ->
      Ok(Set(key, value, last_seen_sequence_number))
  }
}

/// Build the operation for a local delete proposal. A delete needs a value to
/// delete, so an absent key and an already deleted key are both refusals.
pub fn delete(
  state: PactMapState,
  key: String,
  last_seen_sequence_number: Int,
) -> Result(PactMapOperation, ProposeError) {
  case dict.get(state.values, key) {
    Error(Nil) -> Error(KeyNotFound(key))
    Ok(Pact(_, Some(_))) -> Error(ProposalAlreadyPending(key))
    Ok(Pact(Some(Accepted(None, _)), None)) -> Error(KeyAlreadyDeleted(key))
    Ok(Pact(Some(Accepted(Some(_), _)), None)) | Ok(Pact(None, None)) ->
      Ok(Set(key, None, last_seen_sequence_number))
  }
}

pub fn apply_set(
  state: PactMapState,
  operation: PactMapOperation,
  sequence_number: Int,
  connected: List(Int),
  self_id: Int,
) -> #(PactMapState, List(PactMapEvent), SetReaction) {
  case operation {
    Accept(_) -> #(state, [], NoReaction)
    Set(key, value, reference_sequence_number) -> {
      let current = dict.get(state.values, key)
      let accepted = case current {
        Ok(Pact(accepted, _)) -> accepted
        Error(_) -> None
      }
      let valid = case current {
        Error(_) -> True
        Ok(Pact(_, Some(_))) -> False
        Ok(Pact(Some(Accepted(_, accepted_sequence_number)), None)) ->
          accepted_sequence_number <= reference_sequence_number
        Ok(Pact(None, None)) -> True
      }

      case valid {
        False -> #(state, [], NoReaction)
        True -> {
          let signoffs = connected |> list.sort(int.compare)
          let pact =
            Pact(accepted: accepted, pending: Some(Pending(value, signoffs)))
          let state = PactMapState(values: dict.insert(state.values, key, pact))
          let #(state, events) = case signoffs {
            [] -> settle(state, key, sequence_number)
            _ -> #(state, [WentPending(key)])
          }
          let reaction = case list.contains(signoffs, self_id) {
            True -> OweAccept(Accept(key))
            False -> NoReaction
          }
          #(state, events, reaction)
        }
      }
    }
  }
}

pub fn apply_accept(
  state: PactMapState,
  key: String,
  from_client: Int,
  sequence_number: Int,
) -> Result(#(PactMapState, List(PactMapEvent)), KernelError) {
  case dict.get(state.values, key) {
    Error(_) -> Ok(#(state, []))
    Ok(Pact(_, None)) -> Ok(#(state, []))
    Ok(Pact(accepted, Some(Pending(value, signoffs)))) -> {
      case list.contains(signoffs, from_client) {
        False ->
          Error(UnexpectedAccept(
            key,
            from_client,
            "client was not expected to sign off",
          ))
        True -> {
          let signoffs = list.filter(signoffs, fn(id) { id != from_client })
          let state =
            PactMapState(values: dict.insert(
              state.values,
              key,
              Pact(accepted: accepted, pending: Some(Pending(value, signoffs))),
            ))
          case signoffs {
            [] -> settle(state, key, sequence_number) |> Ok
            _ -> Ok(#(state, []))
          }
        }
      }
    }
  }
}

pub fn remove_member(
  state: PactMapState,
  client_id: Int,
  leave_sequence_number: Int,
) -> #(PactMapState, List(PactMapEvent)) {
  summary_entries(state)
  |> list.fold(#(state, []), fn(acc, entry) {
    let #(state, events) = acc
    let #(key, pact) = entry
    case pact {
      Pact(_, None) -> acc
      Pact(accepted, Some(Pending(value, signoffs))) -> {
        let signoffs = list.filter(signoffs, fn(id) { id != client_id })
        let state =
          PactMapState(values: dict.insert(
            state.values,
            key,
            Pact(accepted: accepted, pending: Some(Pending(value, signoffs))),
          ))
        case signoffs {
          [] -> {
            let #(state, settle_events) =
              settle(state, key, leave_sequence_number)
            #(state, list.append(events, settle_events))
          }
          _ -> #(state, events)
        }
      }
    }
  })
}

fn settle(
  state: PactMapState,
  key: String,
  sequence_number: Int,
) -> #(PactMapState, List(PactMapEvent)) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(Pending(value, _)))) -> {
      let state =
        PactMapState(values: dict.insert(
          state.values,
          key,
          Pact(accepted: Some(Accepted(value, sequence_number)), pending: None),
        ))
      #(state, [WentAccepted(key)])
    }
    Ok(Pact(_, None)) | Error(Nil) -> #(state, [])
  }
}
