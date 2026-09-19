/// <reference types="./pact_map_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
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
} from "../gleam.mjs";

export class PactMapState extends $CustomType {
  constructor(values) {
    super();
    this.values = values;
  }
}
export const PactMapState$PactMapState = (values) => new PactMapState(values);
export const PactMapState$isPactMapState = (value) =>
  value instanceof PactMapState;
export const PactMapState$PactMapState$values = (value) => value.values;
export const PactMapState$PactMapState$0 = (value) => value.values;

export class Pact extends $CustomType {
  constructor(accepted, pending) {
    super();
    this.accepted = accepted;
    this.pending = pending;
  }
}
export const Pact$Pact = (accepted, pending) => new Pact(accepted, pending);
export const Pact$isPact = (value) => value instanceof Pact;
export const Pact$Pact$accepted = (value) => value.accepted;
export const Pact$Pact$0 = (value) => value.accepted;
export const Pact$Pact$pending = (value) => value.pending;
export const Pact$Pact$1 = (value) => value.pending;

export class Accepted extends $CustomType {
  constructor(value, sequence_number) {
    super();
    this.value = value;
    this.sequence_number = sequence_number;
  }
}
export const Accepted$Accepted = (value, sequence_number) =>
  new Accepted(value, sequence_number);
export const Accepted$isAccepted = (value) => value instanceof Accepted;
export const Accepted$Accepted$value = (value) => value.value;
export const Accepted$Accepted$0 = (value) => value.value;
export const Accepted$Accepted$sequence_number = (value) =>
  value.sequence_number;
export const Accepted$Accepted$1 = (value) => value.sequence_number;

export class Pending extends $CustomType {
  constructor(value, expected_signoffs) {
    super();
    this.value = value;
    this.expected_signoffs = expected_signoffs;
  }
}
export const Pending$Pending = (value, expected_signoffs) =>
  new Pending(value, expected_signoffs);
export const Pending$isPending = (value) => value instanceof Pending;
export const Pending$Pending$value = (value) => value.value;
export const Pending$Pending$0 = (value) => value.value;
export const Pending$Pending$expected_signoffs = (value) =>
  value.expected_signoffs;
export const Pending$Pending$1 = (value) => value.expected_signoffs;

export class Set extends $CustomType {
  constructor(key, value, reference_sequence_number) {
    super();
    this.key = key;
    this.value = value;
    this.reference_sequence_number = reference_sequence_number;
  }
}
export const PactMapOperation$Set = (key, value, reference_sequence_number) =>
  new Set(key, value, reference_sequence_number);
export const PactMapOperation$isSet = (value) => value instanceof Set;
export const PactMapOperation$Set$key = (value) => value.key;
export const PactMapOperation$Set$0 = (value) => value.key;
export const PactMapOperation$Set$value = (value) => value.value;
export const PactMapOperation$Set$1 = (value) => value.value;
export const PactMapOperation$Set$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const PactMapOperation$Set$2 = (value) =>
  value.reference_sequence_number;

export class Accept extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const PactMapOperation$Accept = (key) => new Accept(key);
export const PactMapOperation$isAccept = (value) => value instanceof Accept;
export const PactMapOperation$Accept$key = (value) => value.key;
export const PactMapOperation$Accept$0 = (value) => value.key;

export const PactMapOperation$key = (value) => value.key;

export class WentPending extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const PactMapEvent$WentPending = (key) => new WentPending(key);
export const PactMapEvent$isWentPending = (value) =>
  value instanceof WentPending;
export const PactMapEvent$WentPending$key = (value) => value.key;
export const PactMapEvent$WentPending$0 = (value) => value.key;

export class WentAccepted extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const PactMapEvent$WentAccepted = (key) => new WentAccepted(key);
export const PactMapEvent$isWentAccepted = (value) =>
  value instanceof WentAccepted;
export const PactMapEvent$WentAccepted$key = (value) => value.key;
export const PactMapEvent$WentAccepted$0 = (value) => value.key;

export const PactMapEvent$key = (value) => value.key;

export class OweAccept extends $CustomType {
  constructor(operation) {
    super();
    this.operation = operation;
  }
}
export const SetReaction$OweAccept = (operation) => new OweAccept(operation);
export const SetReaction$isOweAccept = (value) => value instanceof OweAccept;
export const SetReaction$OweAccept$operation = (value) => value.operation;
export const SetReaction$OweAccept$0 = (value) => value.operation;

export class NoReaction extends $CustomType {}
export const SetReaction$NoReaction$const = new NoReaction();
export const SetReaction$NoReaction = () => SetReaction$NoReaction$const;
export const SetReaction$isNoReaction = (value) => value instanceof NoReaction;

export class UnexpectedAccept extends $CustomType {
  constructor(key, client, detail) {
    super();
    this.key = key;
    this.client = client;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAccept = (key, client, detail) =>
  new UnexpectedAccept(key, client, detail);
export const KernelError$isUnexpectedAccept = (value) =>
  value instanceof UnexpectedAccept;
export const KernelError$UnexpectedAccept$key = (value) => value.key;
export const KernelError$UnexpectedAccept$0 = (value) => value.key;
export const KernelError$UnexpectedAccept$client = (value) => value.client;
export const KernelError$UnexpectedAccept$1 = (value) => value.client;
export const KernelError$UnexpectedAccept$detail = (value) => value.detail;
export const KernelError$UnexpectedAccept$2 = (value) => value.detail;

/**
 * A proposal for this key waits for signoffs now. One key holds one
 * pending proposal at a time.
 */
export class ProposalAlreadyPending extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const ProposeError$ProposalAlreadyPending = (key) =>
  new ProposalAlreadyPending(key);
export const ProposeError$isProposalAlreadyPending = (value) =>
  value instanceof ProposalAlreadyPending;
export const ProposeError$ProposalAlreadyPending$key = (value) => value.key;
export const ProposeError$ProposalAlreadyPending$0 = (value) => value.key;

/**
 * A delete needs a value to delete, and this key holds none.
 */
export class KeyNotFound extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const ProposeError$KeyNotFound = (key) => new KeyNotFound(key);
export const ProposeError$isKeyNotFound = (value) =>
  value instanceof KeyNotFound;
export const ProposeError$KeyNotFound$key = (value) => value.key;
export const ProposeError$KeyNotFound$0 = (value) => value.key;

/**
 * A delete needs a value to delete, and a client already deleted this key.
 */
export class KeyAlreadyDeleted extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const ProposeError$KeyAlreadyDeleted = (key) =>
  new KeyAlreadyDeleted(key);
export const ProposeError$isKeyAlreadyDeleted = (value) =>
  value instanceof KeyAlreadyDeleted;
export const ProposeError$KeyAlreadyDeleted$key = (value) => value.key;
export const ProposeError$KeyAlreadyDeleted$0 = (value) => value.key;

export const ProposeError$key = (value) => value.key;

export function new$() {
  return new PactMapState($dict.new$());
}

export function from_summary(entries) {
  let _block;
  let _pipe = entries;
  _block = $list.fold(
    _pipe,
    $dict.new$(),
    (values, entry) => {
      let key = entry[0];
      let pact = entry[1];
      return $dict.insert(values, key, pact);
    },
  );
  let values = _block;
  return new PactMapState(values);
}

export function summary_entries(state) {
  let _pipe = $dict.to_list(state.values);
  return $list.sort(_pipe, (a, b) => { return $string.compare(a[0], b[0]); });
}

/**
 * The accepted value for `key`. The result is `Error(Nil)` when the key holds
 * no accepted value, and when the room accepted a delete for it.
 */
export function get(state, key) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].accepted;
    if ($1 instanceof Some) {
      let $2 = $1[0].value;
      if ($2 instanceof Some) {
        let value = $2[0];
        return new Ok(value);
      } else {
        return new Error(undefined);
      }
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The accepted entry for `key`, which is the value with its sequence number.
 */
export function get_with_details(state, key) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].accepted;
    if ($1 instanceof Some) {
      let accepted = $1[0];
      return new Ok(accepted);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function is_pending(state, key) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}

/**
 * The value that a client proposed for `key` and no room accepted yet. The
 * inner `Option` holds the proposal itself: `None` is a proposal to delete
 * the key.
 */
export function get_pending(state, key) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      let value = $1[0].value;
      return new Ok(value);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * The full pending proposal for `key`, with the signoff list that it waits
 * on. `get_pending` gives the value that is pending. This function gives the
 * clients that must sign off. Only that list can explain a stalled pact to a
 * user.
 */
export function pending(state, key) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      let pending$1 = $1[0];
      return new Ok(pending$1);
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function keys(state) {
  let _pipe = $dict.keys(state.values);
  return $list.sort(_pipe, $string.compare);
}

/**
 * Build the operation for a local proposal. `value` is `None` for a proposal
 * to delete the key.
 */
export function set(state, key, value, last_seen_sequence_number) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      return new Error(new ProposalAlreadyPending(key));
    } else {
      return new Ok(new Set(key, value, last_seen_sequence_number));
    }
  } else {
    return new Ok(new Set(key, value, last_seen_sequence_number));
  }
}

/**
 * Build the operation for a local delete proposal. A delete needs a value to
 * delete, so an absent key and an already deleted key are both refusals.
 */
export function delete$(state, key, last_seen_sequence_number) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      return new Error(new ProposalAlreadyPending(key));
    } else {
      let $2 = $[0].accepted;
      if ($2 instanceof Some) {
        let $3 = $2[0].value;
        if ($3 instanceof Some) {
          return new Ok(
            new Set(key, Option$None$const, last_seen_sequence_number),
          );
        } else {
          return new Error(new KeyAlreadyDeleted(key));
        }
      } else {
        return new Ok(
          new Set(key, Option$None$const, last_seen_sequence_number),
        );
      }
    }
  } else {
    return new Error(new KeyNotFound(key));
  }
}

function settle(state, key, sequence_number) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      let value = $1[0].value;
      let state$1 = new PactMapState(
        $dict.insert(
          state.values,
          key,
          new Pact(
            new Some(new Accepted(value, sequence_number)),
            Option$None$const,
          ),
        ),
      );
      return [state$1, toList([new WentAccepted(key)])];
    } else {
      return [state, $List$Empty$const];
    }
  } else {
    return [state, $List$Empty$const];
  }
}

export function apply_set(state, operation, sequence_number, connected, self_id) {
  if (operation instanceof Set) {
    let key = operation.key;
    let value = operation.value;
    let reference_sequence_number = operation.reference_sequence_number;
    let current = $dict.get(state.values, key);
    let _block;
    if (current instanceof Ok) {
      let accepted = current[0].accepted;
      _block = accepted;
    } else {
      _block = Option$None$const;
    }
    let accepted = _block;
    let _block$1;
    if (current instanceof Ok) {
      let $ = current[0].pending;
      if ($ instanceof Some) {
        _block$1 = false;
      } else {
        let $1 = current[0].accepted;
        if ($1 instanceof Some) {
          let accepted_sequence_number = $1[0].sequence_number;
          _block$1 = accepted_sequence_number <= reference_sequence_number;
        } else {
          _block$1 = true;
        }
      }
    } else {
      _block$1 = true;
    }
    let valid = _block$1;
    if (valid) {
      let _block$2;
      let _pipe = connected;
      _block$2 = $list.sort(_pipe, $int.compare);
      let signoffs = _block$2;
      let pact = new Pact(accepted, new Some(new Pending(value, signoffs)));
      let state$1 = new PactMapState($dict.insert(state.values, key, pact));
      let _block$3;
      if (signoffs instanceof $Empty) {
        _block$3 = settle(state$1, key, sequence_number);
      } else {
        _block$3 = [state$1, toList([new WentPending(key)])];
      }
      let $ = _block$3;
      let state$2 = $[0];
      let events = $[1];
      let _block$4;
      let $1 = $list.contains(signoffs, self_id);
      if ($1) {
        _block$4 = new OweAccept(new Accept(key));
      } else {
        _block$4 = SetReaction$NoReaction$const;
      }
      let reaction = _block$4;
      return [state$2, events, reaction];
    } else {
      return [state, $List$Empty$const, SetReaction$NoReaction$const];
    }
  } else {
    return [state, $List$Empty$const, SetReaction$NoReaction$const];
  }
}

export function apply_accept(state, key, from_client, sequence_number) {
  let $ = $dict.get(state.values, key);
  if ($ instanceof Ok) {
    let $1 = $[0].pending;
    if ($1 instanceof Some) {
      let accepted = $[0].accepted;
      let value = $1[0].value;
      let signoffs = $1[0].expected_signoffs;
      let $2 = $list.contains(signoffs, from_client);
      if ($2) {
        let signoffs$1 = $list.filter(
          signoffs,
          (id) => { return id !== from_client; },
        );
        let state$1 = new PactMapState(
          $dict.insert(
            state.values,
            key,
            new Pact(accepted, new Some(new Pending(value, signoffs$1))),
          ),
        );
        if (signoffs$1 instanceof $Empty) {
          let _pipe = settle(state$1, key, sequence_number);
          return new Ok(_pipe);
        } else {
          return new Ok([state$1, $List$Empty$const]);
        }
      } else {
        return new Error(
          new UnexpectedAccept(
            key,
            from_client,
            "client was not expected to sign off",
          ),
        );
      }
    } else {
      return new Ok([state, $List$Empty$const]);
    }
  } else {
    return new Ok([state, $List$Empty$const]);
  }
}

export function remove_member(state, client_id, leave_sequence_number) {
  let _pipe = summary_entries(state);
  return $list.fold(
    _pipe,
    [state, $List$Empty$const],
    (acc, entry) => {
      let state$1 = acc[0];
      let events = acc[1];
      let key = entry[0];
      let pact = entry[1];
      let $ = pact.pending;
      if ($ instanceof Some) {
        let accepted = pact.accepted;
        let value = $[0].value;
        let signoffs = $[0].expected_signoffs;
        let signoffs$1 = $list.filter(
          signoffs,
          (id) => { return id !== client_id; },
        );
        let state$2 = new PactMapState(
          $dict.insert(
            state$1.values,
            key,
            new Pact(accepted, new Some(new Pending(value, signoffs$1))),
          ),
        );
        if (signoffs$1 instanceof $Empty) {
          let $1 = settle(state$2, key, leave_sequence_number);
          let state$3 = $1[0];
          let settle_events = $1[1];
          return [state$3, $list.append(events, settle_events)];
        } else {
          return [state$2, events];
        }
      } else {
        return acc;
      }
    },
  );
}
