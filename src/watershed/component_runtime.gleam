//// Pure lifecycle and dispatch-trace planning for component runtimes.
////
//// A target adapter owns running values, callbacks, and subscriptions. This
//// module compares those running values with a prepared workspace and keeps
//// one trace from scheduling the same graph edge more than once.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import watershed/component
import watershed/dispatch
import watershed/workspace

/// The persisted identity of one component instance.
///
/// A change to any field requires a restart. Layout and graph data are not
/// part of this value, so those edits do not restart a component.
pub opaque type InstanceIdentity {
  InstanceIdentity(
    kind: String,
    version: Int,
    config: String,
    child_handle: String,
  )
}

/// One instance that a target runtime has started.
pub type CurrentInstance {
  CurrentInstance(instance_id: String, identity: InstanceIdentity)
}

/// One prepared instance that the target runtime must start.
pub type StartInstance(subtree) {
  StartInstance(
    entry: workspace.ManifestEntry,
    identity: InstanceIdentity,
    subtree: subtree,
  )
}

/// One stored instance that cannot start yet.
pub type BlockedInstance {
  Loading(entry: workspace.ManifestEntry, reason: String)
  Unavailable(entry: workspace.ManifestEntry, reason: component.LookupError)
  Failed(instance_id: String, reason: workspace.PreparationError)
}

/// The lifecycle changes needed to match one prepared workspace snapshot.
pub opaque type ReconcilePlan(subtree) {
  ReconcilePlan(
    stop_ids: List(String),
    keep_ids: List(String),
    starts: List(StartInstance(subtree)),
    blocked: List(BlockedInstance),
  )
}

/// Build the persisted identity of one manifest entry.
pub fn identity(entry: workspace.ManifestEntry) -> InstanceIdentity {
  InstanceIdentity(
    kind: entry.kind,
    version: entry.version,
    config: json.to_string(entry.config),
    child_handle: json.to_string(entry.child_handle),
  )
}

/// Plan instance starts and stops for one prepared workspace snapshot.
///
/// Stops and starts are sorted by instance ID. A target must complete all
/// stops before it starts replacements under the same ID.
pub fn reconcile(
  current: List(CurrentInstance),
  prepared: List(workspace.PreparationState(subtree)),
) -> ReconcilePlan(subtree) {
  let sorted_current =
    list.sort(current, fn(a, b) { string.compare(a.instance_id, b.instance_id) })
  let sorted_prepared =
    list.sort(prepared, fn(a, b) {
      string.compare(preparation_id(a), preparation_id(b))
    })

  let keep_ids =
    list.filter_map(sorted_prepared, fn(state) {
      case state {
        workspace.Prepared(entry, _) -> {
          let wanted = identity(entry)
          case find_current(sorted_current, entry.instance_id) {
            Some(found) if found.identity == wanted -> Ok(entry.instance_id)
            _ -> Error(Nil)
          }
        }
        workspace.Loading(_, _)
        | workspace.Unavailable(_, _)
        | workspace.Failed(_, _) -> Error(Nil)
      }
    })

  let starts =
    list.filter_map(sorted_prepared, fn(state) {
      case state {
        workspace.Prepared(entry, subtree) -> {
          let wanted = identity(entry)
          case find_current(sorted_current, entry.instance_id) {
            Some(found) if found.identity == wanted -> Error(Nil)
            _ -> Ok(StartInstance(entry, wanted, subtree))
          }
        }
        workspace.Loading(_, _)
        | workspace.Unavailable(_, _)
        | workspace.Failed(_, _) -> Error(Nil)
      }
    })

  let stop_ids =
    list.filter_map(sorted_current, fn(found) {
      let matching =
        list.find(sorted_prepared, fn(state) {
          preparation_id(state) == found.instance_id
        })
      case matching {
        Ok(workspace.Prepared(entry, _)) -> {
          case identity(entry) == found.identity {
            True -> Error(Nil)
            False -> Ok(found.instance_id)
          }
        }
        Ok(_) | Error(Nil) -> Ok(found.instance_id)
      }
    })

  let blocked =
    list.filter_map(sorted_prepared, fn(state) {
      case state {
        workspace.Loading(entry, reason) -> Ok(Loading(entry, reason))
        workspace.Unavailable(entry, reason) -> Ok(Unavailable(entry, reason))
        workspace.Failed(instance_id, reason) -> Ok(Failed(instance_id, reason))
        workspace.Prepared(_, _) -> Error(Nil)
      }
    })

  ReconcilePlan(stop_ids, keep_ids, starts, blocked)
}

/// The instance IDs to stop before applying the starts.
pub fn stops(plan: ReconcilePlan(subtree)) -> List(String) {
  plan.stop_ids
}

/// The instance IDs whose running values remain valid.
pub fn keeps(plan: ReconcilePlan(subtree)) -> List(String) {
  plan.keep_ids
}

/// The prepared instances to start.
pub fn starts(plan: ReconcilePlan(subtree)) -> List(StartInstance(subtree)) {
  plan.starts
}

/// The stored instances that cannot start yet.
pub fn blocked(plan: ReconcilePlan(subtree)) -> List(BlockedInstance) {
  plan.blocked
}

/// One dispatch trace with a FIFO delivery queue.
pub opaque type DispatchTrace {
  DispatchTrace(
    id: String,
    pending: List(dispatch.Delivery),
    seen_edges: List(String),
  )
}

/// Start an empty dispatch trace.
pub fn new_trace(id: String) -> DispatchTrace {
  DispatchTrace(id: id, pending: [], seen_edges: [])
}

/// The stable ID of a dispatch trace.
pub fn trace_id(trace: DispatchTrace) -> String {
  trace.id
}

/// Add deliveries in graph order and ignore edges already scheduled.
pub fn enqueue(
  trace: DispatchTrace,
  deliveries: List(dispatch.Delivery),
) -> DispatchTrace {
  let #(accepted, seen_edges) =
    list.fold(deliveries, #([], trace.seen_edges), fn(acc, delivery) {
      let dispatch.Delivery(edge_id:, ..) = delivery
      case list.contains(acc.1, edge_id) {
        True -> acc
        False -> #([delivery, ..acc.0], [edge_id, ..acc.1])
      }
    })
  DispatchTrace(
    ..trace,
    pending: list.append(trace.pending, list.reverse(accepted)),
    seen_edges: seen_edges,
  )
}

/// Take the next delivery from a trace.
pub fn next(
  trace: DispatchTrace,
) -> #(Option(dispatch.Delivery), DispatchTrace) {
  case trace.pending {
    [] -> #(None, trace)
    [first, ..rest] -> #(Some(first), DispatchTrace(..trace, pending: rest))
  }
}

/// Whether a trace has no queued deliveries.
pub fn is_empty(trace: DispatchTrace) -> Bool {
  trace.pending == []
}

/// Edge IDs already scheduled by this trace, in scheduling order.
pub fn seen_edges(trace: DispatchTrace) -> List(String) {
  list.reverse(trace.seen_edges)
}

fn preparation_id(state: workspace.PreparationState(subtree)) -> String {
  case state {
    workspace.Loading(entry, _)
    | workspace.Prepared(entry, _)
    | workspace.Unavailable(entry, _) -> entry.instance_id
    workspace.Failed(instance_id, _) -> instance_id
  }
}

fn find_current(
  current: List(CurrentInstance),
  instance_id: String,
) -> Option(CurrentInstance) {
  list.find(current, fn(found) { found.instance_id == instance_id })
  |> result_to_option
}

fn result_to_option(result: Result(a, Nil)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}
