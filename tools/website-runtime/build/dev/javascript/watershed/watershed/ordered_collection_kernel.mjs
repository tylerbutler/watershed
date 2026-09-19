/// <reference types="./ordered_collection_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class OrderedState extends $CustomType {
  constructor(queue, jobs) {
    super();
    this.queue = queue;
    this.jobs = jobs;
  }
}
export const OrderedState$OrderedState = (queue, jobs) =>
  new OrderedState(queue, jobs);
export const OrderedState$isOrderedState = (value) =>
  value instanceof OrderedState;
export const OrderedState$OrderedState$queue = (value) => value.queue;
export const OrderedState$OrderedState$0 = (value) => value.queue;
export const OrderedState$OrderedState$jobs = (value) => value.jobs;
export const OrderedState$OrderedState$1 = (value) => value.jobs;

export class JobEntry extends $CustomType {
  constructor(value, owner) {
    super();
    this.value = value;
    this.owner = owner;
  }
}
export const JobEntry$JobEntry = (value, owner) => new JobEntry(value, owner);
export const JobEntry$isJobEntry = (value) => value instanceof JobEntry;
export const JobEntry$JobEntry$value = (value) => value.value;
export const JobEntry$JobEntry$0 = (value) => value.value;
export const JobEntry$JobEntry$owner = (value) => value.owner;
export const JobEntry$JobEntry$1 = (value) => value.owner;

export class Add extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const OrderedOperation$Add = (value) => new Add(value);
export const OrderedOperation$isAdd = (value) => value instanceof Add;
export const OrderedOperation$Add$value = (value) => value.value;
export const OrderedOperation$Add$0 = (value) => value.value;

export class Acquire extends $CustomType {
  constructor(acquire_id) {
    super();
    this.acquire_id = acquire_id;
  }
}
export const OrderedOperation$Acquire = (acquire_id) => new Acquire(acquire_id);
export const OrderedOperation$isAcquire = (value) => value instanceof Acquire;
export const OrderedOperation$Acquire$acquire_id = (value) => value.acquire_id;
export const OrderedOperation$Acquire$0 = (value) => value.acquire_id;

export class Complete extends $CustomType {
  constructor(acquire_id) {
    super();
    this.acquire_id = acquire_id;
  }
}
export const OrderedOperation$Complete = (acquire_id) =>
  new Complete(acquire_id);
export const OrderedOperation$isComplete = (value) => value instanceof Complete;
export const OrderedOperation$Complete$acquire_id = (value) => value.acquire_id;
export const OrderedOperation$Complete$0 = (value) => value.acquire_id;

export class Release extends $CustomType {
  constructor(acquire_id) {
    super();
    this.acquire_id = acquire_id;
  }
}
export const OrderedOperation$Release = (acquire_id) => new Release(acquire_id);
export const OrderedOperation$isRelease = (value) => value instanceof Release;
export const OrderedOperation$Release$acquire_id = (value) => value.acquire_id;
export const OrderedOperation$Release$0 = (value) => value.acquire_id;

/**
 * `newly_added` separates a new add from a release that returns an item to
 * the queue.
 */
export class Added extends $CustomType {
  constructor(value, newly_added, local) {
    super();
    this.value = value;
    this.newly_added = newly_added;
    this.local = local;
  }
}
export const OrderedEvent$Added = (value, newly_added, local) =>
  new Added(value, newly_added, local);
export const OrderedEvent$isAdded = (value) => value instanceof Added;
export const OrderedEvent$Added$value = (value) => value.value;
export const OrderedEvent$Added$0 = (value) => value.value;
export const OrderedEvent$Added$newly_added = (value) => value.newly_added;
export const OrderedEvent$Added$1 = (value) => value.newly_added;
export const OrderedEvent$Added$local = (value) => value.local;
export const OrderedEvent$Added$2 = (value) => value.local;

export class Acquired extends $CustomType {
  constructor(value, owner, local) {
    super();
    this.value = value;
    this.owner = owner;
    this.local = local;
  }
}
export const OrderedEvent$Acquired = (value, owner, local) =>
  new Acquired(value, owner, local);
export const OrderedEvent$isAcquired = (value) => value instanceof Acquired;
export const OrderedEvent$Acquired$value = (value) => value.value;
export const OrderedEvent$Acquired$0 = (value) => value.value;
export const OrderedEvent$Acquired$owner = (value) => value.owner;
export const OrderedEvent$Acquired$1 = (value) => value.owner;
export const OrderedEvent$Acquired$local = (value) => value.local;
export const OrderedEvent$Acquired$2 = (value) => value.local;

export class Completed extends $CustomType {
  constructor(value, local) {
    super();
    this.value = value;
    this.local = local;
  }
}
export const OrderedEvent$Completed = (value, local) =>
  new Completed(value, local);
export const OrderedEvent$isCompleted = (value) => value instanceof Completed;
export const OrderedEvent$Completed$value = (value) => value.value;
export const OrderedEvent$Completed$0 = (value) => value.value;
export const OrderedEvent$Completed$local = (value) => value.local;
export const OrderedEvent$Completed$1 = (value) => value.local;

/**
 * A notification only. The kernel releases a locally held item when the
 * leave sequences. This event changes no state.
 */
export class LocalReleased extends $CustomType {
  constructor(value, intentional) {
    super();
    this.value = value;
    this.intentional = intentional;
  }
}
export const OrderedEvent$LocalReleased = (value, intentional) =>
  new LocalReleased(value, intentional);
export const OrderedEvent$isLocalReleased = (value) =>
  value instanceof LocalReleased;
export const OrderedEvent$LocalReleased$value = (value) => value.value;
export const OrderedEvent$LocalReleased$0 = (value) => value.value;
export const OrderedEvent$LocalReleased$intentional = (value) =>
  value.intentional;
export const OrderedEvent$LocalReleased$1 = (value) => value.intentional;

export const OrderedEvent$value = (value) => value.value;

export class AcquiredItem extends $CustomType {
  constructor(acquire_id, value) {
    super();
    this.acquire_id = acquire_id;
    this.value = value;
  }
}
export const AcquireOutcome$AcquiredItem = (acquire_id, value) =>
  new AcquiredItem(acquire_id, value);
export const AcquireOutcome$isAcquiredItem = (value) =>
  value instanceof AcquiredItem;
export const AcquireOutcome$AcquiredItem$acquire_id = (value) =>
  value.acquire_id;
export const AcquireOutcome$AcquiredItem$0 = (value) => value.acquire_id;
export const AcquireOutcome$AcquiredItem$value = (value) => value.value;
export const AcquireOutcome$AcquiredItem$1 = (value) => value.value;

export class QueueEmpty extends $CustomType {}
export const AcquireOutcome$QueueEmpty$const = new QueueEmpty();
export const AcquireOutcome$QueueEmpty = () => AcquireOutcome$QueueEmpty$const;
export const AcquireOutcome$isQueueEmpty = (value) =>
  value instanceof QueueEmpty;

/**
 * The kernel never produces this event. The runtime resolves an acquire
 * that is still pending with `Aborted` when the document closes before the
 * operation sequences.
 */
export class Aborted extends $CustomType {}
export const AcquireOutcome$Aborted$const = new Aborted();
export const AcquireOutcome$Aborted = () => AcquireOutcome$Aborted$const;
export const AcquireOutcome$isAborted = (value) => value instanceof Aborted;

export function new$() {
  return new OrderedState($List$Empty$const, $dict.new$());
}

function jobs_to_dict(jobs) {
  return $list.fold(
    jobs,
    $dict.new$(),
    (acc, entry) => {
      let acquire_id = entry[0];
      let job = entry[1];
      return $dict.insert(acc, acquire_id, job);
    },
  );
}

export function from_summary(queue, jobs) {
  return new OrderedState(queue, jobs_to_dict(jobs));
}

export function summary_queue(state) {
  return state.queue;
}

function sorted_jobs(state) {
  let _pipe = $dict.to_list(state.jobs);
  return $list.sort(_pipe, (a, b) => { return $string.compare(a[0], b[0]); });
}

export function summary_jobs(state) {
  return sorted_jobs(state);
}

export function size(state) {
  return $list.length(state.queue);
}

export function add(_, value) {
  return new Add(value);
}

export function acquire(acquire_id) {
  return new Acquire(acquire_id);
}

export function complete(acquire_id) {
  return new Complete(acquire_id);
}

export function release(acquire_id) {
  return new Release(acquire_id);
}

function apply_add_core(state, value, newly_added, local) {
  let state$1 = new OrderedState(
    $list.append(state.queue, toList([value])),
    state.jobs,
  );
  return [state$1, toList([new Added(value, newly_added, local)])];
}

export function add_detached(state, value) {
  return apply_add_core(state, value, true, true);
}

function apply_acquire_core(state, acquire_id, author, local) {
  let $ = state.queue;
  if ($ instanceof $Empty) {
    return [state, $List$Empty$const, Option$None$const];
  } else {
    let value = $.head;
    let rest = $.tail;
    let state$1 = new OrderedState(
      rest,
      $dict.insert(state.jobs, acquire_id, new JobEntry(value, author)),
    );
    return [
      state$1,
      toList([new Acquired(value, author, local)]),
      new Some(value),
    ];
  }
}

export function ack_local_acquire(state, acquire_id, author) {
  let $ = apply_acquire_core(state, acquire_id, author, true);
  let state$1 = $[0];
  let events = $[1];
  let value = $[2];
  let _block;
  if (value instanceof Some) {
    let value$1 = value[0];
    _block = new AcquiredItem(acquire_id, value$1);
  } else {
    _block = AcquireOutcome$QueueEmpty$const;
  }
  let outcome = _block;
  return [state$1, events, outcome];
}

export function acquire_detached(state, acquire_id) {
  return ack_local_acquire(state, acquire_id, Option$None$const);
}

export function apply_add(state, value) {
  return apply_add_core(state, value, true, false);
}

export function apply_acquire(state, acquire_id, author) {
  return apply_acquire_core(state, acquire_id, author, false);
}

function apply_complete_core(state, acquire_id, local) {
  let $ = $dict.get(state.jobs, acquire_id);
  if ($ instanceof Ok) {
    let value = $[0].value;
    let state$1 = new OrderedState(
      state.queue,
      $dict.delete$(state.jobs, acquire_id),
    );
    return [state$1, toList([new Completed(value, local)])];
  } else {
    return [state, $List$Empty$const];
  }
}

export function apply_complete(state, acquire_id) {
  return apply_complete_core(state, acquire_id, false);
}

function apply_release_core(state, acquire_id, local) {
  let $ = $dict.get(state.jobs, acquire_id);
  if ($ instanceof Ok) {
    let value = $[0].value;
    let state$1 = new OrderedState(
      state.queue,
      $dict.delete$(state.jobs, acquire_id),
    );
    return apply_add_core(state$1, value, false, local);
  } else {
    return [state, $List$Empty$const];
  }
}

export function apply_release(state, acquire_id) {
  return apply_release_core(state, acquire_id, false);
}

export function apply_remote(state, operation, author) {
  if (operation instanceof Add) {
    let value = operation.value;
    return apply_add_core(state, value, true, false);
  } else if (operation instanceof Acquire) {
    let acquire_id = operation.acquire_id;
    let $ = apply_acquire_core(state, acquire_id, new Some(author), false);
    let state$1 = $[0];
    let events = $[1];
    return [state$1, events];
  } else if (operation instanceof Complete) {
    let acquire_id = operation.acquire_id;
    return apply_complete_core(state, acquire_id, false);
  } else {
    let acquire_id = operation.acquire_id;
    return apply_release_core(state, acquire_id, false);
  }
}

export function ack_local(state, operation, author) {
  if (operation instanceof Add) {
    let value = operation.value;
    let $ = apply_add_core(state, value, true, true);
    let state$1 = $[0];
    let events = $[1];
    return [state$1, events, Option$None$const];
  } else if (operation instanceof Acquire) {
    let acquire_id = operation.acquire_id;
    let $ = ack_local_acquire(state, acquire_id, new Some(author));
    let state$1 = $[0];
    let events = $[1];
    let outcome = $[2];
    return [state$1, events, new Some(outcome)];
  } else if (operation instanceof Complete) {
    let acquire_id = operation.acquire_id;
    let $ = apply_complete_core(state, acquire_id, true);
    let state$1 = $[0];
    let events = $[1];
    return [state$1, events, Option$None$const];
  } else {
    let acquire_id = operation.acquire_id;
    let $ = apply_release_core(state, acquire_id, true);
    let state$1 = $[0];
    let events = $[1];
    return [state$1, events, Option$None$const];
  }
}

export function remove_client(state, owner) {
  let _block;
  let _pipe = sorted_jobs(state);
  _block = $list.fold(
    _pipe,
    [state.jobs, $List$Empty$const],
    (acc, entry) => {
      let jobs = acc[0];
      let returned_values = acc[1];
      let acquire_id;
      let value;
      let job_owner;
      acquire_id = entry[0];
      value = entry[1].value;
      job_owner = entry[1].owner;
      let $1 = isEqual(job_owner, owner);
      if ($1) {
        return [
          $dict.delete$(jobs, acquire_id),
          $list.append(returned_values, toList([value])),
        ];
      } else {
        return acc;
      }
    },
  );
  let $ = _block;
  let jobs = $[0];
  let returned_values = $[1];
  let queue = $list.append(state.queue, returned_values);
  let _block$1;
  let _pipe$1 = returned_values;
  _block$1 = $list.map(
    _pipe$1,
    (value) => { return new Added(value, false, false); },
  );
  let events = _block$1;
  return [new OrderedState(queue, jobs), events];
}

export function on_disconnect_notify(state, owner) {
  let _pipe = sorted_jobs(state);
  return $list.filter_map(
    _pipe,
    (entry) => {
      let value;
      let job_owner;
      value = entry[1].value;
      job_owner = entry[1].owner;
      let $ = isEqual(job_owner, owner);
      if ($) {
        return new Ok(new LocalReleased(value, false));
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function rollback(state, _) {
  return [state, AcquireOutcome$QueueEmpty$const];
}

export function apply_stashed_operation(state, operation) {
  return [state, operation];
}
