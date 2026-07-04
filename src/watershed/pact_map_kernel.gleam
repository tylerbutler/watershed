//// Pure port of FluidFramework's PactMap quorum protocol.
////
//// A set first becomes pending with a frozen signoff list captured from the
//// connected quorum at set sequencing time. The value becomes accepted when
//// accept ops and/or membership leaves drain that signoff list.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
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

pub type PactMapOp {
  Set(key: String, value: Option(Json), ref_seq: Int)
  Accept(key: String)
}

pub type PactMapEvent {
  WentPending(key: String)
  WentAccepted(key: String)
}

pub type SetReaction {
  OweAccept(op: PactMapOp)
  NoReaction
}

pub type KernelError {
  UnexpectedAccept(key: String, client: Int, detail: String)
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

pub fn get(state: PactMapState, key: String) -> Option(Json) {
  case dict.get(state.values, key) {
    Ok(Pact(Some(Accepted(value, _)), _)) -> value
    _ -> None
  }
}

pub fn get_with_details(state: PactMapState, key: String) -> Option(Accepted) {
  case dict.get(state.values, key) {
    Ok(Pact(Some(accepted), _)) -> Some(accepted)
    _ -> None
  }
}

pub fn is_pending(state: PactMapState, key: String) -> Bool {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(_))) -> True
    _ -> False
  }
}

pub fn get_pending(state: PactMapState, key: String) -> Option(Option(Json)) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(Pending(value, _)))) -> Some(value)
    _ -> None
  }
}

pub fn keys(state: PactMapState) -> List(String) {
  dict.keys(state.values) |> list.sort(string.compare)
}

pub fn set(
  state: PactMapState,
  key: String,
  value: Option(Json),
  last_seen_seq: Int,
) -> Option(PactMapOp) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(_))) -> None
    _ -> Some(Set(key, value, last_seen_seq))
  }
}

pub fn delete(
  state: PactMapState,
  key: String,
  last_seen_seq: Int,
) -> Option(PactMapOp) {
  case dict.get(state.values, key) {
    Error(_) -> None
    Ok(Pact(_, Some(_))) -> None
    Ok(Pact(Some(Accepted(None, _)), None)) -> None
    Ok(_) -> Some(Set(key, None, last_seen_seq))
  }
}

pub fn apply_set(
  state: PactMapState,
  op: PactMapOp,
  seq: Int,
  connected: List(Int),
  self_id: Int,
) -> #(PactMapState, List(PactMapEvent), SetReaction) {
  case op {
    Accept(_) -> #(state, [], NoReaction)
    Set(key, value, ref_seq) -> {
      let current = dict.get(state.values, key)
      let accepted = case current {
        Ok(Pact(accepted, _)) -> accepted
        Error(_) -> None
      }
      let valid = case current {
        Error(_) -> True
        Ok(Pact(_, Some(_))) -> False
        Ok(Pact(Some(Accepted(_, accepted_seq)), None)) ->
          accepted_seq <= ref_seq
        Ok(Pact(None, None)) -> True
      }

      case valid {
        False -> #(state, [], NoReaction)
        True -> {
          let signoffs = connected |> list.sort(int_compare)
          let pact =
            Pact(accepted: accepted, pending: Some(Pending(value, signoffs)))
          let state = PactMapState(values: dict.insert(state.values, key, pact))
          let #(state, events) = case signoffs {
            [] -> settle(state, key, seq)
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
  seq: Int,
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
            [] -> settle(state, key, seq) |> Ok
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
  leave_seq: Int,
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
            let #(state, settle_events) = settle(state, key, leave_seq)
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
  seq: Int,
) -> #(PactMapState, List(PactMapEvent)) {
  case dict.get(state.values, key) {
    Ok(Pact(_, Some(Pending(value, _)))) -> {
      let state =
        PactMapState(values: dict.insert(
          state.values,
          key,
          Pact(accepted: Some(Accepted(value, seq)), pending: None),
        ))
      #(state, [WentAccepted(key)])
    }
    _ -> #(state, [])
  }
}

fn int_compare(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}
