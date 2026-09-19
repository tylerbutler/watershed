/// <reference types="./ot_client.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

export class LogEntry extends $CustomType {
  constructor(sequence_number, operation) {
    super();
    this.sequence_number = sequence_number;
    this.operation = operation;
  }
}
export const LogEntry$LogEntry = (sequence_number, operation) =>
  new LogEntry(sequence_number, operation);
export const LogEntry$isLogEntry = (value) => value instanceof LogEntry;
export const LogEntry$LogEntry$sequence_number = (value) =>
  value.sequence_number;
export const LogEntry$LogEntry$0 = (value) => value.sequence_number;
export const LogEntry$LogEntry$operation = (value) => value.operation;
export const LogEntry$LogEntry$1 = (value) => value.operation;

/**
 * No local operation waits for an acknowledgement.
 */
export class Idle extends $CustomType {}
export const Pending$Idle$const = new Idle();
export const Pending$Idle = () => Pending$Idle$const;
export const Pending$isIdle = (value) => value instanceof Idle;

/**
 * One operation is on the wire. The operation is written against the
 * sequenced state.
 */
export class InFlight extends $CustomType {
  constructor(operation) {
    super();
    this.operation = operation;
  }
}
export const Pending$InFlight = (operation) => new InFlight(operation);
export const Pending$isInFlight = (value) => value instanceof InFlight;
export const Pending$InFlight$operation = (value) => value.operation;
export const Pending$InFlight$0 = (value) => value.operation;

/**
 * One operation is on the wire, and every later local edit is composed into
 * `buffered`. `buffered` is written against the sequenced state with
 * `operation` applied.
 */
export class InFlightAndBuffered extends $CustomType {
  constructor(operation, buffered) {
    super();
    this.operation = operation;
    this.buffered = buffered;
  }
}
export const Pending$InFlightAndBuffered = (operation, buffered) =>
  new InFlightAndBuffered(operation, buffered);
export const Pending$isInFlightAndBuffered = (value) =>
  value instanceof InFlightAndBuffered;
export const Pending$InFlightAndBuffered$operation = (value) => value.operation;
export const Pending$InFlightAndBuffered$0 = (value) => value.operation;
export const Pending$InFlightAndBuffered$buffered = (value) => value.buffered;
export const Pending$InFlightAndBuffered$1 = (value) => value.buffered;

/**
 * Fold an incoming operation past every logged entry that sequenced inside its
 * `(reference_sequence_number, sequence_number)` window, in sequence_number
 * order. The function uses `transform_against` to advance the operation past
 * each entry. The incoming operation has a larger sequence number than every
 * entry in the window, so the closure of the kernel must give the incoming
 * operation the side of the later operation.
 *
 * The one-operation-in-flight invariant means that no entry in the window has
 * the author of the incoming operation. The window thus has no gap, and this
 * function puts the operation into head context.
 */
export function to_head_context(
  log,
  reference_sequence_number,
  sequence_number,
  operation,
  transform_against
) {
  let _pipe = log;
  let _pipe$1 = $list.filter(
    _pipe,
    (e) => {
      return (e.sequence_number > reference_sequence_number) && (e.sequence_number < sequence_number);
    },
  );
  let _pipe$2 = $list.sort(
    _pipe$1,
    (a, b) => { return $int.compare(a.sequence_number, b.sequence_number); },
  );
  return $list.try_fold(_pipe$2, operation, transform_against);
}

/**
 * The operation that is on the wire. The result is `Error(Nil)` when no
 * operation waits for an acknowledgement.
 */
export function in_flight(pending) {
  if (pending instanceof Idle) {
    return new Error(undefined);
  } else if (pending instanceof InFlight) {
    let operation = pending.operation;
    return new Ok(operation);
  } else {
    let operation = pending.operation;
    return new Ok(operation);
  }
}

/**
 * The composed local edits that wait behind the operation on the wire. The
 * result is `Error(Nil)` when there is no such edit.
 */
export function buffered(pending) {
  if (pending instanceof Idle) {
    return new Error(undefined);
  } else if (pending instanceof InFlight) {
    return new Error(undefined);
  } else {
    let buffered$1 = pending.buffered;
    return new Ok(buffered$1);
  }
}

/**
 * Record a local edit. The edit becomes the operation on the wire when the
 * wire slot is free. The edit joins the buffer in every other case, through
 * `compose`. The second element of the result is the operation to send, and it
 * is `None` when the kernel must hold the edit.
 */
export function hold_local(pending, edit, compose) {
  if (pending instanceof Idle) {
    return new Ok([new InFlight(edit), new Some(edit)]);
  } else if (pending instanceof InFlight) {
    let operation = pending.operation;
    return new Ok([new InFlightAndBuffered(operation, edit), Option$None$const]);
  } else {
    let operation = pending.operation;
    let buffered$1 = pending.buffered;
    return $result.try$(
      compose(buffered$1, edit),
      (composed) => {
        return new Ok(
          [new InFlightAndBuffered(operation, composed), Option$None$const],
        );
      },
    );
  }
}

/**
 * Rebase every unacknowledged local operation past an incoming remote
 * operation. The function returns the rebased local operations and the remote
 * operation advanced past all of them. The visible remote event of the kernel
 * must use that advanced operation.
 *
 * The kernel rebases the operation on the wire first, and then the buffer,
 * which lives one context deeper. The function advances the remote operation
 * past each layer in that order, so every rebase is well formed.
 *
 * A pending local operation sequences after the remote operation, because the
 * client reads the sequenced stream in order. The `rebase_local` closure must
 * thus give the local operation the side of the later operation, and
 * `advance_remote` must give the remote operation the side of the earlier
 * operation.
 */
export function rebase_pending(pending, remote, rebase_local, advance_remote) {
  if (pending instanceof Idle) {
    return new Ok([Pending$Idle$const, remote]);
  } else if (pending instanceof InFlight) {
    let operation = pending.operation;
    return $result.try$(
      rebase_local(operation, remote),
      (rebased) => {
        return $result.try$(
          advance_remote(remote, operation),
          (advanced) => { return new Ok([new InFlight(rebased), advanced]); },
        );
      },
    );
  } else {
    let operation = pending.operation;
    let buffered$1 = pending.buffered;
    return $result.try$(
      rebase_local(operation, remote),
      (rebased_operation) => {
        return $result.try$(
          advance_remote(remote, operation),
          (after_operation) => {
            return $result.try$(
              rebase_local(buffered$1, after_operation),
              (rebased_buffer) => {
                return $result.try$(
                  advance_remote(after_operation, buffered$1),
                  (advanced) => {
                    return new Ok(
                      [
                        new InFlightAndBuffered(
                          rebased_operation,
                          rebased_buffer,
                        ),
                        advanced,
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/**
 * Drop the log entries that no future window can contain. The
 * `reference_sequence_number` of an operation is the minimum sequence number
 * (MSN) or more, so an entry at the MSN or below it is dead.
 */
export function gc_log(log, minimum_sequence_number) {
  return $list.filter(
    log,
    (e) => { return e.sequence_number > minimum_sequence_number; },
  );
}

/**
 * Retire the operation that the server acknowledged. A buffered edit becomes
 * the next operation on the wire, and the function builds its wire envelope.
 * The reference sequence of that envelope is the `sequence_number` of the
 * acknowledgement, because the buffer is written against `sequenced` with the
 * acknowledged operation applied.
 *
 * The second element of the result is `None` when there was no buffered edit.
 * This is a plain function over a `Pending` value and a wire constructor, and
 * not over kernel state, so every kernel can share it whatever the shape of
 * its state record is.
 */
export function promote_buffer(pending, sequence_number, make_wire) {
  if (pending instanceof Idle) {
    return [Pending$Idle$const, Option$None$const];
  } else if (pending instanceof InFlight) {
    return [Pending$Idle$const, Option$None$const];
  } else {
    let buffered$1 = pending.buffered;
    return [
      new InFlight(buffered$1),
      new Some(make_wire(sequence_number, buffered$1)),
    ];
  }
}

/**
 * Take the value from a pending `Option` slot, for example the `outbound`
 * field of a kernel. The function returns the value, if there is one, and the
 * empty slot. A second call has no more effect.
 */
export function take_pending(pending) {
  if (pending instanceof Some) {
    let value = pending[0];
    return [Option$None$const, new Some(value)];
  } else {
    return [Option$None$const, Option$None$const];
  }
}
