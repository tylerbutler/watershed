/// <reference types="./json_ot_kernel.d.mts" />
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import { Side$Lft$const, Side$Rgt$const } from "../watershed/json_ot.mjs";
import * as $ot_client from "../watershed/ot_client.mjs";
import { LogEntry } from "../watershed/ot_client.mjs";

export class JsonOtState extends $CustomType {
  constructor(sequenced, log, pending, outbound) {
    super();
    this.sequenced = sequenced;
    this.log = log;
    this.pending = pending;
    this.outbound = outbound;
  }
}
export const JsonOtState$JsonOtState = (sequenced, log, pending, outbound) =>
  new JsonOtState(sequenced, log, pending, outbound);
export const JsonOtState$isJsonOtState = (value) =>
  value instanceof JsonOtState;
export const JsonOtState$JsonOtState$sequenced = (value) => value.sequenced;
export const JsonOtState$JsonOtState$0 = (value) => value.sequenced;
export const JsonOtState$JsonOtState$log = (value) => value.log;
export const JsonOtState$JsonOtState$1 = (value) => value.log;
export const JsonOtState$JsonOtState$pending = (value) => value.pending;
export const JsonOtState$JsonOtState$2 = (value) => value.pending;
export const JsonOtState$JsonOtState$outbound = (value) => value.outbound;
export const JsonOtState$JsonOtState$3 = (value) => value.outbound;

export class JsonOtWireOperation extends $CustomType {
  constructor(reference_sequence_number, components) {
    super();
    this.reference_sequence_number = reference_sequence_number;
    this.components = components;
  }
}
export const JsonOtWireOperation$JsonOtWireOperation = (reference_sequence_number, components) =>
  new JsonOtWireOperation(reference_sequence_number, components);
export const JsonOtWireOperation$isJsonOtWireOperation = (value) =>
  value instanceof JsonOtWireOperation;
export const JsonOtWireOperation$JsonOtWireOperation$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const JsonOtWireOperation$JsonOtWireOperation$0 = (value) =>
  value.reference_sequence_number;
export const JsonOtWireOperation$JsonOtWireOperation$components = (value) =>
  value.components;
export const JsonOtWireOperation$JsonOtWireOperation$1 = (value) =>
  value.components;

export class DocumentChanged extends $CustomType {
  constructor(path, local) {
    super();
    this.path = path;
    this.local = local;
  }
}
export const JsonOtEvent$DocumentChanged = (path, local) =>
  new DocumentChanged(path, local);
export const JsonOtEvent$isDocumentChanged = (value) =>
  value instanceof DocumentChanged;
export const JsonOtEvent$DocumentChanged$path = (value) => value.path;
export const JsonOtEvent$DocumentChanged$0 = (value) => value.path;
export const JsonOtEvent$DocumentChanged$local = (value) => value.local;
export const JsonOtEvent$DocumentChanged$1 = (value) => value.local;

/**
 * An ack arrived with nothing in flight.
 */
export class UnexpectedAck extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$UnexpectedAck = (detail) => new UnexpectedAck(detail);
export const KernelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const KernelError$UnexpectedAck$detail = (value) => value.detail;
export const KernelError$UnexpectedAck$0 = (value) => value.detail;

/**
 * The pure algebra refused an apply or a transform, for example for a bad
 * path or a bad value.
 */
export class OtFailure extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const KernelError$OtFailure = (error) => new OtFailure(error);
export const KernelError$isOtFailure = (value) => value instanceof OtFailure;
export const KernelError$OtFailure$error = (value) => value.error;
export const KernelError$OtFailure$0 = (value) => value.error;

/**
 * A new kernel with an initial document value.
 */
export function from_value(document) {
  return new JsonOtState(
    document,
    $List$Empty$const,
    $ot_client.Pending$Idle$const,
    Option$None$const,
  );
}

/**
 * A new kernel over an empty object document.
 */
export function new$() {
  return from_value(new $json_ot.VObject($List$Empty$const));
}

/**
 * Load a state that contains sequenced data only, from a stored summary. A
 * summary never contains a local edit, and the concurrency window starts
 * empty.
 */
export function from_summary(document) {
  return from_value(document);
}

/**
 * The confirmed document that a summary captures. It contains the sequenced
 * data only, and no local edit.
 */
export function summary(state) {
  return state.sequenced;
}

/**
 * Apply an operation to a document. This is json0 J2 to J4.
 */
export function apply_operation(document, operation) {
  let _pipe = $json_ot.apply(document, operation);
  return $result.map_error(_pipe, (var0) => { return new OtFailure(var0); });
}

/**
 * The optimistic document: `sequenced` with the operation on the wire applied,
 * and then the buffered edits.
 */
export function view(state) {
  let $ = state.pending;
  if ($ instanceof $ot_client.Idle) {
    return new Ok(state.sequenced);
  } else if ($ instanceof $ot_client.InFlight) {
    let operation = $.operation;
    return apply_operation(state.sequenced, operation);
  } else {
    let operation = $.operation;
    let buffered = $.buffered;
    return $result.try$(
      apply_operation(state.sequenced, operation),
      (after_operation) => { return apply_operation(after_operation, buffered); },
    );
  }
}

/**
 * Transform `a` past `b` for the supplied side. This is json0 J5 to J8, and
 * it holds TP1.
 */
export function transform(a, b, side) {
  let _pipe = $json_ot.transform(a, b, side);
  return $result.map_error(_pipe, (var0) => { return new OtFailure(var0); });
}

/**
 * Compose two consecutive operations into one, which is json0 J9. The result
 * applies `b` after `a`.
 */
export function compose(a, b) {
  return $list.append(a, b);
}

/**
 * Invert an operation with the pre-images that its `od` and `ld` components
 * already carry.
 */
export function invert(operation) {
  return $json_ot.invert(operation);
}

function events_for(operation, local) {
  return $list.map(
    operation,
    (component) => { return new DocumentChanged(component.path, local); },
  );
}

/**
 * Write a local edit against the current optimistic view.
 *
 * If no operation is in flight, the edit goes on the wire, and the function
 * returns it as a wire operation to send. That operation carries
 * `reference_sequence_number`, which is the last sequence number that the
 * client received.
 *
 * If an operation is in flight, the function composes the edit into the buffer
 * and holds it until an ack retires the operation on the wire. One operation
 * is thus on the wire at most. `Ok(#(state, None, events))` means that there
 * is nothing to send yet.
 */
export function submit(state, components, reference_sequence_number) {
  return $result.try$(
    view(state),
    (current) => {
      return $result.try$(
        apply_operation(current, components),
        (_) => {
          return $result.try$(
            $ot_client.hold_local(
              state.pending,
              components,
              (buffered, edit) => { return new Ok(compose(buffered, edit)); },
            ),
            (_use0) => {
              let pending = _use0[0];
              let to_send = _use0[1];
              return new Ok(
                [
                  new JsonOtState(
                    state.sequenced,
                    state.log,
                    pending,
                    state.outbound,
                  ),
                  $option.map(
                    to_send,
                    (_capture) => {
                      return new JsonOtWireOperation(
                        reference_sequence_number,
                        _capture,
                      );
                    },
                  ),
                  events_for(components, true),
                ],
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Apply a sequenced operation that another client wrote. `sequence_number` is
 * its sequence number, and `minimum_sequence_number` is the minimum sequence
 * number, which the log garbage collection uses.
 *
 * The kernel transforms the operation into head context past every operation
 * that sequenced in `(reference_sequence_number, sequence_number)`. No
 * operation in that window can come from the same author, because one
 * operation is in flight at most, so the window has no gap. The kernel then
 * applies the operation, logs it, and rebases every unacknowledged local edit
 * past it.
 *
 * The incoming operation sequenced after every operation in its window, so it
 * is `Rgt` there. It sequenced before the operation on the wire and before the
 * buffer, which are not sequenced yet, so it is `Lft` against each of them.
 */
export function apply_remote(
  state,
  wire,
  sequence_number,
  minimum_sequence_number
) {
  return $result.try$(
    $ot_client.to_head_context(
      state.log,
      wire.reference_sequence_number,
      sequence_number,
      wire.components,
      (current, e) => { return transform(current, e.operation, Side$Rgt$const); },
    ),
    (operation_head) => {
      return $result.try$(
        apply_operation(state.sequenced, operation_head),
        (sequenced) => {
          return $result.try$(
            $ot_client.rebase_pending(
              state.pending,
              operation_head,
              (local, remote) => {
                return transform(local, remote, Side$Rgt$const);
              },
              (remote, local) => {
                return transform(remote, local, Side$Lft$const);
              },
            ),
            (_use0) => {
              let pending = _use0[0];
              let log = $ot_client.gc_log(
                $list.append(
                  state.log,
                  toList([new LogEntry(sequence_number, operation_head)]),
                ),
                minimum_sequence_number,
              );
              let state$1 = new JsonOtState(
                sequenced,
                log,
                pending,
                state.outbound,
              );
              return new Ok([state$1, events_for(operation_head, false)]);
            },
          );
        },
      );
    },
  );
}

/**
 * Commit the local operation after the server sequences it. That operation is
 * the current operation on the wire, which the kernel already rebased past
 * every concurrent remote operation. The kernel thus applies it to `sequenced`
 * and logs it in head context.
 *
 * If there is a buffer, the kernel releases it as the next operation on the
 * wire and puts it in `outbound`, for the runtime to send with
 * `take_outbound`. That operation carries `reference_sequence_number =
 * sequence_number`, because the buffer is expressed against `sequenced` with
 * the acked operation applied. The optimistic view does not change, so the
 * kernel emits no event.
 *
 * The `_wire` value that the sequencer echoes is the original operation that
 * the client submitted. The sequencer never transforms, so that value does not
 * equal the rebased operation on the wire. The kernel uses it for the FIFO
 * order only.
 */
export function ack_local(state, _, sequence_number, minimum_sequence_number) {
  return $result.try$(
    (() => {
      let _pipe = $ot_client.in_flight(state.pending);
      return $result.replace_error(
        _pipe,
        new UnexpectedAck("ack with nothing in flight"),
      );
    })(),
    (in_flight) => {
      return $result.try$(
        apply_operation(state.sequenced, in_flight),
        (sequenced) => {
          let log = $ot_client.gc_log(
            $list.append(
              state.log,
              toList([new LogEntry(sequence_number, in_flight)]),
            ),
            minimum_sequence_number,
          );
          let $ = $ot_client.promote_buffer(
            state.pending,
            sequence_number,
            (var0, var1) => { return new JsonOtWireOperation(var0, var1); },
          );
          let pending = $[0];
          let to_send = $[1];
          let state$1 = new JsonOtState(sequenced, log, pending, to_send);
          return new Ok([state$1, $List$Empty$const]);
        },
      );
    },
  );
}

/**
 * Take the operation that `ack_local` released onto the wire, which is a
 * buffer that became the new operation on the wire. The function returns the
 * operation to send and empties the pending slot. The result is `None` when
 * there is no such operation. A second call has no more effect.
 */
export function take_outbound(state) {
  let $ = $ot_client.take_pending(state.outbound);
  let outbound = $[0];
  let taken = $[1];
  return [
    new JsonOtState(state.sequenced, state.log, state.pending, outbound),
    taken,
  ];
}
