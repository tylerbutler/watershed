/// <reference types="./component_runtime.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $component from "../watershed/component.mjs";
import * as $dispatch from "../watershed/dispatch.mjs";
import * as $workspace from "../watershed/workspace.mjs";

class InstanceIdentity extends $CustomType {
  constructor(kind, version, config, child_handle) {
    super();
    this.kind = kind;
    this.version = version;
    this.config = config;
    this.child_handle = child_handle;
  }
}

export class CurrentInstance extends $CustomType {
  constructor(instance_id, identity) {
    super();
    this.instance_id = instance_id;
    this.identity = identity;
  }
}
export const CurrentInstance$CurrentInstance = (instance_id, identity) =>
  new CurrentInstance(instance_id, identity);
export const CurrentInstance$isCurrentInstance = (value) =>
  value instanceof CurrentInstance;
export const CurrentInstance$CurrentInstance$instance_id = (value) =>
  value.instance_id;
export const CurrentInstance$CurrentInstance$0 = (value) => value.instance_id;
export const CurrentInstance$CurrentInstance$identity = (value) =>
  value.identity;
export const CurrentInstance$CurrentInstance$1 = (value) => value.identity;

export class StartInstance extends $CustomType {
  constructor(entry, identity, subtree) {
    super();
    this.entry = entry;
    this.identity = identity;
    this.subtree = subtree;
  }
}
export const StartInstance$StartInstance = (entry, identity, subtree) =>
  new StartInstance(entry, identity, subtree);
export const StartInstance$isStartInstance = (value) =>
  value instanceof StartInstance;
export const StartInstance$StartInstance$entry = (value) => value.entry;
export const StartInstance$StartInstance$0 = (value) => value.entry;
export const StartInstance$StartInstance$identity = (value) => value.identity;
export const StartInstance$StartInstance$1 = (value) => value.identity;
export const StartInstance$StartInstance$subtree = (value) => value.subtree;
export const StartInstance$StartInstance$2 = (value) => value.subtree;

export class Loading extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const BlockedInstance$Loading = (entry, reason) =>
  new Loading(entry, reason);
export const BlockedInstance$isLoading = (value) => value instanceof Loading;
export const BlockedInstance$Loading$entry = (value) => value.entry;
export const BlockedInstance$Loading$0 = (value) => value.entry;
export const BlockedInstance$Loading$reason = (value) => value.reason;
export const BlockedInstance$Loading$1 = (value) => value.reason;

export class Unavailable extends $CustomType {
  constructor(entry, reason) {
    super();
    this.entry = entry;
    this.reason = reason;
  }
}
export const BlockedInstance$Unavailable = (entry, reason) =>
  new Unavailable(entry, reason);
export const BlockedInstance$isUnavailable = (value) =>
  value instanceof Unavailable;
export const BlockedInstance$Unavailable$entry = (value) => value.entry;
export const BlockedInstance$Unavailable$0 = (value) => value.entry;
export const BlockedInstance$Unavailable$reason = (value) => value.reason;
export const BlockedInstance$Unavailable$1 = (value) => value.reason;

export class Failed extends $CustomType {
  constructor(instance_id, reason) {
    super();
    this.instance_id = instance_id;
    this.reason = reason;
  }
}
export const BlockedInstance$Failed = (instance_id, reason) =>
  new Failed(instance_id, reason);
export const BlockedInstance$isFailed = (value) => value instanceof Failed;
export const BlockedInstance$Failed$instance_id = (value) => value.instance_id;
export const BlockedInstance$Failed$0 = (value) => value.instance_id;
export const BlockedInstance$Failed$reason = (value) => value.reason;
export const BlockedInstance$Failed$1 = (value) => value.reason;

class ReconcilePlan extends $CustomType {
  constructor(stop_ids, keep_ids, starts, blocked) {
    super();
    this.stop_ids = stop_ids;
    this.keep_ids = keep_ids;
    this.starts = starts;
    this.blocked = blocked;
  }
}

class DispatchTrace extends $CustomType {
  constructor(id, pending, seen_edges) {
    super();
    this.id = id;
    this.pending = pending;
    this.seen_edges = seen_edges;
  }
}

/**
 * Build the persisted identity of one manifest entry.
 */
export function identity(entry) {
  return new InstanceIdentity(
    entry.kind,
    entry.version,
    $json.to_string(entry.config),
    $json.to_string(entry.child_handle),
  );
}

function preparation_id(state) {
  if (state instanceof $workspace.Loading) {
    let entry = state.entry;
    return entry.instance_id;
  } else if (state instanceof $workspace.Prepared) {
    let entry = state.entry;
    return entry.instance_id;
  } else if (state instanceof $workspace.Unavailable) {
    let entry = state.entry;
    return entry.instance_id;
  } else {
    let instance_id = state.instance_id;
    return instance_id;
  }
}

function find_current(current, instance_id) {
  let _pipe = $list.find(
    current,
    (found) => { return found.instance_id === instance_id; },
  );
  return $option.from_result(_pipe);
}

/**
 * Plan instance starts and stops for one prepared workspace snapshot.
 *
 * Stops and starts are sorted by instance ID. A target must complete all
 * stops before it starts replacements under the same ID.
 */
export function reconcile(current, prepared) {
  let sorted_current = $list.sort(
    current,
    (a, b) => { return $string.compare(a.instance_id, b.instance_id); },
  );
  let sorted_prepared = $list.sort(
    prepared,
    (a, b) => { return $string.compare(preparation_id(a), preparation_id(b)); },
  );
  let keep_ids = $list.filter_map(
    sorted_prepared,
    (state) => {
      if (state instanceof $workspace.Loading) {
        return new Error(undefined);
      } else if (state instanceof $workspace.Prepared) {
        let entry = state.entry;
        let wanted = identity(entry);
        let $ = find_current(sorted_current, entry.instance_id);
        if ($ instanceof Some) {
          let found = $[0];
          if (isEqual(found.identity, wanted)) {
            return new Ok(entry.instance_id);
          } else {
            return new Error(undefined);
          }
        } else {
          return new Error(undefined);
        }
      } else if (state instanceof $workspace.Unavailable) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
  let starts$1 = $list.filter_map(
    sorted_prepared,
    (state) => {
      if (state instanceof $workspace.Loading) {
        return new Error(undefined);
      } else if (state instanceof $workspace.Prepared) {
        let entry = state.entry;
        let subtree = state.subtree;
        let wanted = identity(entry);
        let $ = find_current(sorted_current, entry.instance_id);
        if ($ instanceof Some) {
          let found = $[0];
          if (isEqual(found.identity, wanted)) {
            return new Error(undefined);
          } else {
            return new Ok(new StartInstance(entry, wanted, subtree));
          }
        } else {
          return new Ok(new StartInstance(entry, wanted, subtree));
        }
      } else if (state instanceof $workspace.Unavailable) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
  let stop_ids = $list.filter_map(
    sorted_current,
    (found) => {
      let matching = $list.find(
        sorted_prepared,
        (state) => { return preparation_id(state) === found.instance_id; },
      );
      if (matching instanceof Ok) {
        let $ = matching[0];
        if ($ instanceof $workspace.Prepared) {
          let entry = $.entry;
          let $1 = isEqual(identity(entry), found.identity);
          if ($1) {
            return new Error(undefined);
          } else {
            return new Ok(found.instance_id);
          }
        } else {
          return new Ok(found.instance_id);
        }
      } else {
        return new Ok(found.instance_id);
      }
    },
  );
  let blocked$1 = $list.filter_map(
    sorted_prepared,
    (state) => {
      if (state instanceof $workspace.Loading) {
        let entry = state.entry;
        let reason = state.reason;
        return new Ok(new Loading(entry, reason));
      } else if (state instanceof $workspace.Prepared) {
        return new Error(undefined);
      } else if (state instanceof $workspace.Unavailable) {
        let entry = state.entry;
        let reason = state.reason;
        return new Ok(new Unavailable(entry, reason));
      } else {
        let instance_id = state.instance_id;
        let reason = state.reason;
        return new Ok(new Failed(instance_id, reason));
      }
    },
  );
  return new ReconcilePlan(stop_ids, keep_ids, starts$1, blocked$1);
}

/**
 * The instance IDs to stop before applying the starts.
 */
export function stops(plan) {
  return plan.stop_ids;
}

/**
 * The instance IDs whose running values remain valid.
 */
export function keeps(plan) {
  return plan.keep_ids;
}

/**
 * The prepared instances to start.
 */
export function starts(plan) {
  return plan.starts;
}

/**
 * The stored instances that cannot start yet.
 */
export function blocked(plan) {
  return plan.blocked;
}

/**
 * Start an empty dispatch trace.
 */
export function new_trace(id) {
  return new DispatchTrace(id, $List$Empty$const, $List$Empty$const);
}

/**
 * The stable ID of a dispatch trace.
 */
export function trace_id(trace) {
  return trace.id;
}

/**
 * Add deliveries in graph order and ignore edges already scheduled.
 */
export function enqueue(trace, deliveries) {
  let $ = $list.fold(
    deliveries,
    [$List$Empty$const, trace.seen_edges],
    (acc, delivery) => {
      let edge_id = delivery.edge_id;
      let $1 = $list.contains(acc[1], edge_id);
      if ($1) {
        return acc;
      } else {
        return [listPrepend(delivery, acc[0]), listPrepend(edge_id, acc[1])];
      }
    },
  );
  let accepted = $[0];
  let seen_edges$1 = $[1];
  return new DispatchTrace(
    trace.id,
    $list.append(trace.pending, $list.reverse(accepted)),
    seen_edges$1,
  );
}

/**
 * Take the next delivery from a trace.
 */
export function next(trace) {
  let $ = trace.pending;
  if ($ instanceof $Empty) {
    return [Option$None$const, trace];
  } else {
    let first = $.head;
    let rest = $.tail;
    return [
      new Some(first),
      new DispatchTrace(trace.id, rest, trace.seen_edges),
    ];
  }
}

/**
 * Whether a trace has no queued deliveries.
 */
export function is_empty(trace) {
  return trace.pending instanceof $Empty;
}

/**
 * Edge IDs already scheduled by this trace, in scheduling order.
 */
export function seen_edges(trace) {
  return $list.reverse(trace.seen_edges);
}
