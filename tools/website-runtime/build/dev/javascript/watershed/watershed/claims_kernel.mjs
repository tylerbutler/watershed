/// <reference types="./claims_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";

export class ClaimsState extends $CustomType {
  constructor(claims, pending) {
    super();
    this.claims = claims;
    this.pending = pending;
  }
}
export const ClaimsState$ClaimsState = (claims, pending) =>
  new ClaimsState(claims, pending);
export const ClaimsState$isClaimsState = (value) =>
  value instanceof ClaimsState;
export const ClaimsState$ClaimsState$claims = (value) => value.claims;
export const ClaimsState$ClaimsState$0 = (value) => value.claims;
export const ClaimsState$ClaimsState$pending = (value) => value.pending;
export const ClaimsState$ClaimsState$1 = (value) => value.pending;

export class ClaimEntry extends $CustomType {
  constructor(value, sequence_number) {
    super();
    this.value = value;
    this.sequence_number = sequence_number;
  }
}
export const ClaimEntry$ClaimEntry = (value, sequence_number) =>
  new ClaimEntry(value, sequence_number);
export const ClaimEntry$isClaimEntry = (value) => value instanceof ClaimEntry;
export const ClaimEntry$ClaimEntry$value = (value) => value.value;
export const ClaimEntry$ClaimEntry$0 = (value) => value.value;
export const ClaimEntry$ClaimEntry$sequence_number = (value) =>
  value.sequence_number;
export const ClaimEntry$ClaimEntry$1 = (value) => value.sequence_number;

export class Claim extends $CustomType {
  constructor(key, value, reference_sequence_number) {
    super();
    this.key = key;
    this.value = value;
    this.reference_sequence_number = reference_sequence_number;
  }
}
export const ClaimOperation$Claim = (key, value, reference_sequence_number) =>
  new Claim(key, value, reference_sequence_number);
export const ClaimOperation$isClaim = (value) => value instanceof Claim;
export const ClaimOperation$Claim$key = (value) => value.key;
export const ClaimOperation$Claim$0 = (value) => value.key;
export const ClaimOperation$Claim$value = (value) => value.value;
export const ClaimOperation$Claim$1 = (value) => value.value;
export const ClaimOperation$Claim$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const ClaimOperation$Claim$2 = (value) =>
  value.reference_sequence_number;

/**
 * The kernel emits this event when it accepts a sequenced operation. `local`
 * follows the watershed convention. The map events and the counter events
 * carry that field, and the TypeScript event does not.
 */
export class Claimed extends $CustomType {
  constructor(key, local) {
    super();
    this.key = key;
    this.local = local;
  }
}
export const ClaimEvent$Claimed = (key, local) => new Claimed(key, local);
export const ClaimEvent$isClaimed = (value) => value instanceof Claimed;
export const ClaimEvent$Claimed$key = (value) => value.key;
export const ClaimEvent$Claimed$0 = (value) => value.key;
export const ClaimEvent$Claimed$local = (value) => value.local;
export const ClaimEvent$Claimed$1 = (value) => value.local;

/**
 * The caller must send the operation. Its outcome arrives later, from
 * `ack_local`. This is the "Pending" status in TypeScript.
 */
export class Submitted extends $CustomType {
  constructor(state, operation) {
    super();
    this.state = state;
    this.operation = operation;
  }
}
export const SubmitResult$Submitted = (state, operation) =>
  new Submitted(state, operation);
export const SubmitResult$isSubmitted = (value) => value instanceof Submitted;
export const SubmitResult$Submitted$state = (value) => value.state;
export const SubmitResult$Submitted$0 = (value) => value.state;
export const SubmitResult$Submitted$operation = (value) => value.operation;
export const SubmitResult$Submitted$1 = (value) => value.operation;

/**
 * `claim_once` found a committed entry, so the caller sends nothing.
 * This value carries the committed value, which can be a JSON null.
 */
export class AlreadyClaimed extends $CustomType {
  constructor(current_value) {
    super();
    this.current_value = current_value;
  }
}
export const SubmitResult$AlreadyClaimed = (current_value) =>
  new AlreadyClaimed(current_value);
export const SubmitResult$isAlreadyClaimed = (value) =>
  value instanceof AlreadyClaimed;
export const SubmitResult$AlreadyClaimed$current_value = (value) =>
  value.current_value;
export const SubmitResult$AlreadyClaimed$0 = (value) => value.current_value;

export class Accepted extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const ClaimOutcome$Accepted = (value) => new Accepted(value);
export const ClaimOutcome$isAccepted = (value) => value instanceof Accepted;
export const ClaimOutcome$Accepted$value = (value) => value.value;
export const ClaimOutcome$Accepted$0 = (value) => value.value;

/**
 * The claim lost the race. This value carries the current committed value.
 * It is `None` only if the key is truly unclaimed, which is the
 * `T | undefined` type in TypeScript. In practice a loss means that another
 * claim won, so the value is `Some`. The `Option` type follows the upstream
 * type. It does not represent a state that this kernel can reach on its
 * own.
 */
export class Lost extends $CustomType {
  constructor(current_value) {
    super();
    this.current_value = current_value;
  }
}
export const ClaimOutcome$Lost = (current_value) => new Lost(current_value);
export const ClaimOutcome$isLost = (value) => value instanceof Lost;
export const ClaimOutcome$Lost$current_value = (value) => value.current_value;
export const ClaimOutcome$Lost$0 = (value) => value.current_value;

export class Aborted extends $CustomType {}
export const ClaimOutcome$Aborted$const = new Aborted();
export const ClaimOutcome$Aborted = () => ClaimOutcome$Aborted$const;
export const ClaimOutcome$isAborted = (value) => value instanceof Aborted;

/**
 * A usage error on the submit side. This is the `UsageError` of the
 * TypeScript code, as data.
 */
export class AlreadyPendingLocally extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const KernelError$AlreadyPendingLocally = (key) =>
  new AlreadyPendingLocally(key);
export const KernelError$isAlreadyPendingLocally = (value) =>
  value instanceof AlreadyPendingLocally;
export const KernelError$AlreadyPendingLocally$key = (value) => value.key;
export const KernelError$AlreadyPendingLocally$0 = (value) => value.key;

/**
 * A local ack arrived, and no pending entry matches it. The TypeScript code
 * accepts that condition quietly. This kernel is strict, the same as the
 * counter kernel and the map kernel: a routing mismatch is fatal
 * divergence.
 */
export class UnexpectedAck extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAck = (operation, detail) =>
  new UnexpectedAck(operation, detail);
export const KernelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const KernelError$UnexpectedAck$operation = (value) => value.operation;
export const KernelError$UnexpectedAck$0 = (value) => value.operation;
export const KernelError$UnexpectedAck$detail = (value) => value.detail;
export const KernelError$UnexpectedAck$1 = (value) => value.detail;

export class UnexpectedRollback extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const KernelError$UnexpectedRollback = (operation, detail) =>
  new UnexpectedRollback(operation, detail);
export const KernelError$isUnexpectedRollback = (value) =>
  value instanceof UnexpectedRollback;
export const KernelError$UnexpectedRollback$operation = (value) =>
  value.operation;
export const KernelError$UnexpectedRollback$0 = (value) => value.operation;
export const KernelError$UnexpectedRollback$detail = (value) => value.detail;
export const KernelError$UnexpectedRollback$1 = (value) => value.detail;

export function new$() {
  return new ClaimsState($dict.new$(), $dict.new$());
}

/**
 * Build a state that contains committed data only, from the stored summary
 * triples `(key, value, sequence_number)`. The summary keeps the sequence
 * numbers, so the `reference_sequence_number` comparison of a compare-and-set
 * continues to work after a load. A state that you load has no pending entry.
 */
export function from_summary(entries) {
  let claims = $list.fold(
    entries,
    $dict.new$(),
    (acc, entry) => {
      let key = entry[0];
      let value = entry[1];
      let sequence_number = entry[2];
      return $dict.insert(acc, key, new ClaimEntry(value, sequence_number));
    },
  );
  return new ClaimsState(claims, $dict.new$());
}

/**
 * The committed claims to store in a summary, as `(key, value,
 * sequence_number)` triples. The function sorts them by key, so a snapshot is
 * stable.
 */
export function summary_entries(state) {
  let _pipe = $dict.to_list(state.claims);
  let _pipe$1 = $list.sort(
    _pipe,
    (a, b) => { return $string.compare(a[0], b[0]); },
  );
  return $list.map(
    _pipe$1,
    (entry) => {
      let key;
      let value;
      let sequence_number;
      key = entry[0];
      value = entry[1].value;
      sequence_number = entry[1].sequence_number;
      return [key, value, sequence_number];
    },
  );
}

/**
 * The committed value for a key. The read gives committed data only, by
 * design: a pending local claim is not visible until it wins. The result is
 * `Error(Nil)` when the key is unclaimed.
 */
export function get(state, key) {
  let $ = $dict.get(state.claims, key);
  if ($ instanceof Ok) {
    let value = $[0].value;
    return new Ok(value);
  } else {
    return $;
  }
}

/**
 * Whether a committed claim exists for a key. This function separates a key
 * that no client set from a key that a client set to a JSON null. It reads
 * committed data only, the same as `get`.
 */
export function has(state, key) {
  return $dict.has_key(state.claims, key);
}

function submit_claim(state, key, value, reference_sequence_number) {
  let $ = $dict.has_key(state.pending, key);
  if ($) {
    return new Error(new AlreadyPendingLocally(key));
  } else {
    let state$1 = new ClaimsState(
      state.claims,
      $dict.insert(state.pending, key, value),
    );
    return new Ok(
      new Submitted(state$1, new Claim(key, value, reference_sequence_number)),
    );
  }
}

/**
 * The write-once submit. If a committed entry exists, the function returns
 * `AlreadyClaimed` at once and sends no operation. If none exists, the
 * function behaves as a compare-and-set against the unclaimed key, and it
 * records `reference_sequence_number = last_seen_sequence_number`.
 *
 * The check of the committed state runs *before* the pending guard. A
 * write-once claim on a committed key thus returns `AlreadyClaimed`, also
 * when a compare-and-set for that key is pending locally.
 */
export function claim_once(state, key, value, last_seen_sequence_number) {
  let $ = $dict.get(state.claims, key);
  if ($ instanceof Ok) {
    let current = $[0].value;
    return new Ok(new AlreadyClaimed(current));
  } else {
    return submit_claim(state, key, value, last_seen_sequence_number);
  }
}

/**
 * The compare-and-set submit. If the key is claimed, the function records
 * `reference_sequence_number` from the sequence number of the committed entry.
 * If the key is unclaimed, it records `last_seen_sequence_number`. The
 * function always submits, and it never returns `AlreadyClaimed` at once. The
 * sequencing of the operation decides the acceptance.
 */
export function compare_and_set_claim(
  state,
  key,
  value,
  last_seen_sequence_number
) {
  let _block;
  let $ = $dict.get(state.claims, key);
  if ($ instanceof Ok) {
    let sequence_number = $[0].sequence_number;
    _block = sequence_number;
  } else {
    _block = last_seen_sequence_number;
  }
  let reference_sequence_number = _block;
  return submit_claim(state, key, value, reference_sequence_number);
}

/**
 * The detached apply path. No other client exists, so the function applies
 * the claim directly with the sequence number 0. The runtime decides when a
 * channel is detached, the same as for the map kernel. The insert is
 * unconditional, the same as the detached compare-and-set path in
 * TypeScript.
 */
export function set_detached(state, key, value) {
  return new ClaimsState(
    $dict.insert(state.claims, key, new ClaimEntry(value, 0)),
    state.pending,
  );
}

/**
 * The acceptance rule, which is S3 and S4. The function applies it in the
 * same way to a local operation and to a remote operation. It accepts the
 * operation if the key is unclaimed, or if the `reference_sequence_number` of
 * the operation equals the sequence number of the committed entry *exactly*.
 * On an accept, it replaces the entry with the value of the operation and the
 * sequence number of the operation. It returns whether it accepted the
 * operation, so that a caller can emit an event or resolve an outcome.
 * 
 * @ignore
 */
function apply_sequenced(state, operation, sequence_number) {
  let key = operation.key;
  let value = operation.value;
  let reference_sequence_number = operation.reference_sequence_number;
  let _block;
  let $ = $dict.get(state.claims, key);
  if ($ instanceof Ok) {
    let entry_sequence_number = $[0].sequence_number;
    _block = reference_sequence_number === entry_sequence_number;
  } else {
    _block = true;
  }
  let accepted = _block;
  if (accepted) {
    return [
      new ClaimsState(
        $dict.insert(state.claims, key, new ClaimEntry(value, sequence_number)),
        state.pending,
      ),
      true,
    ];
  } else {
    return [state, false];
  }
}

/**
 * Apply a sequenced operation from another client. An accepted operation
 * replaces the entry and emits `Claimed(key, False)`. A refused operation
 * changes no state and emits nothing. A remote operation that wins a key with
 * a local pending claim does not change that pending entry, which is rule S10.
 * That entry resolves only when the local operation sequences.
 */
export function apply_remote(state, operation, sequence_number) {
  let $ = apply_sequenced(state, operation, sequence_number);
  let state$1 = $[0];
  let accepted = $[1];
  if (accepted) {
    return [state$1, toList([new Claimed(operation.key, false)])];
  } else {
    return [state$1, $List$Empty$const];
  }
}

/**
 * The local operation returns sequenced. The acceptance rule is the same as in
 * `apply_remote`. The function also removes the pending entry for the key and
 * resolves its outcome. The outcome is `Accepted`, with the submitted value,
 * if the claim won. Otherwise it is `Lost`, with the current committed value,
 * which can be absent. Unlike the map kernel and the counter kernel, an ack
 * here emits `Claimed(key, True)`, because the kernel showed nothing
 * optimistically at submit time.
 *
 * The function is strict. An ack with no matching pending entry is a routing
 * fault, and not an acceptable condition.
 */
export function ack_local(state, operation, sequence_number) {
  let $ = $dict.get(state.pending, operation.key);
  if ($ instanceof Ok) {
    let pending_value = $[0];
    let $1 = apply_sequenced(state, operation, sequence_number);
    let state$1 = $1[0];
    let accepted = $1[1];
    let state$2 = new ClaimsState(
      state$1.claims,
      $dict.delete$(state$1.pending, operation.key),
    );
    if (accepted) {
      return new Ok(
        [
          state$2,
          toList([new Claimed(operation.key, true)]),
          new Accepted(pending_value),
        ],
      );
    } else {
      return new Ok(
        [
          state$2,
          $List$Empty$const,
          new Lost($option.from_result(get(state$2, operation.key))),
        ],
      );
    }
  } else {
    return new Error(
      new UnexpectedAck(
        operation,
        ("no pending claim for key \"" + operation.key) + "\"",
      ),
    );
  }
}

/**
 * Roll back a pending local operation. The function removes its pending entry
 * and resolves the outcome as `Aborted`. It is strict about a missing pending
 * entry. The TypeScript code accepts that condition.
 */
export function rollback(state, operation) {
  let $ = $dict.has_key(state.pending, operation.key);
  if ($) {
    return new Ok(
      [
        new ClaimsState(
          state.claims,
          $dict.delete$(state.pending, operation.key),
        ),
        ClaimOutcome$Aborted$const,
      ],
    );
  } else {
    return new Error(
      new UnexpectedRollback(
        operation,
        ("no pending claim for key \"" + operation.key) + "\"",
      ),
    );
  }
}

/**
 * Register a stashed operation as pending again, which guards the key. No
 * caller waits on it. The function returns the operation without a change, for
 * the resubmission, and it keeps the original `reference_sequence_number`. It
 * returns an error if the key is already pending.
 */
export function apply_stashed_operation(state, operation) {
  let $ = $dict.has_key(state.pending, operation.key);
  if ($) {
    return new Error(new AlreadyPendingLocally(operation.key));
  } else {
    return new Ok(
      [
        new ClaimsState(
          state.claims,
          $dict.insert(state.pending, operation.key, operation.value),
        ),
        operation,
      ],
    );
  }
}

/**
 * Abort every pending claim, for example when the caller disposes the
 * channel. The function clears the pending claims and returns the aborted
 * keys, sorted, so that the result is deterministic. The runtime can then
 * resolve each waiting caller with `Aborted`.
 */
export function abort_all(state) {
  let _block;
  let _pipe = $dict.keys(state.pending);
  _block = $list.sort(_pipe, $string.compare);
  let keys = _block;
  return [new ClaimsState(state.claims, $dict.new$()), keys];
}

/**
 * The values of the pending claims, for the handle scan during a garbage
 * collection. `summary_entries` gives the committed values.
 */
export function pending_values(state) {
  return $dict.values(state.pending);
}
