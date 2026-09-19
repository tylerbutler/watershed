/// <reference types="./rich_text_kernel.d.mts" />
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
import * as $ot_client from "../watershed/ot_client.mjs";
import * as $rich_text from "../watershed/rich_text.mjs";

export class RichTextState extends $CustomType {
  constructor(sequenced, log, pending, outbound) {
    super();
    this.sequenced = sequenced;
    this.log = log;
    this.pending = pending;
    this.outbound = outbound;
  }
}
export const RichTextState$RichTextState = (sequenced, log, pending, outbound) =>
  new RichTextState(sequenced, log, pending, outbound);
export const RichTextState$isRichTextState = (value) =>
  value instanceof RichTextState;
export const RichTextState$RichTextState$sequenced = (value) => value.sequenced;
export const RichTextState$RichTextState$0 = (value) => value.sequenced;
export const RichTextState$RichTextState$log = (value) => value.log;
export const RichTextState$RichTextState$1 = (value) => value.log;
export const RichTextState$RichTextState$pending = (value) => value.pending;
export const RichTextState$RichTextState$2 = (value) => value.pending;
export const RichTextState$RichTextState$outbound = (value) => value.outbound;
export const RichTextState$RichTextState$3 = (value) => value.outbound;

export class RichTextWireOperation extends $CustomType {
  constructor(reference_sequence_number, delta) {
    super();
    this.reference_sequence_number = reference_sequence_number;
    this.delta = delta;
  }
}
export const RichTextWireOperation$RichTextWireOperation = (reference_sequence_number, delta) =>
  new RichTextWireOperation(reference_sequence_number, delta);
export const RichTextWireOperation$isRichTextWireOperation = (value) =>
  value instanceof RichTextWireOperation;
export const RichTextWireOperation$RichTextWireOperation$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const RichTextWireOperation$RichTextWireOperation$0 = (value) =>
  value.reference_sequence_number;
export const RichTextWireOperation$RichTextWireOperation$delta = (value) =>
  value.delta;
export const RichTextWireOperation$RichTextWireOperation$1 = (value) =>
  value.delta;

export class RichTextChanged extends $CustomType {
  constructor(delta, local) {
    super();
    this.delta = delta;
    this.local = local;
  }
}
export const RichTextEvent$RichTextChanged = (delta, local) =>
  new RichTextChanged(delta, local);
export const RichTextEvent$isRichTextChanged = (value) =>
  value instanceof RichTextChanged;
export const RichTextEvent$RichTextChanged$delta = (value) => value.delta;
export const RichTextEvent$RichTextChanged$0 = (value) => value.delta;
export const RichTextEvent$RichTextChanged$local = (value) => value.local;
export const RichTextEvent$RichTextChanged$1 = (value) => value.local;

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

export class RichTextFailure extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const KernelError$RichTextFailure = (error) =>
  new RichTextFailure(error);
export const KernelError$isRichTextFailure = (value) =>
  value instanceof RichTextFailure;
export const KernelError$RichTextFailure$error = (value) => value.error;
export const KernelError$RichTextFailure$0 = (value) => value.error;

/**
 * Start from a confirmed initial document.
 */
export function from_document(document) {
  return new RichTextState(
    document,
    $List$Empty$const,
    $ot_client.Pending$Idle$const,
    Option$None$const,
  );
}

/**
 * Start with an empty rich-text document.
 */
export function new$() {
  return from_document($rich_text.empty_document());
}

/**
 * Restore a sequenced-only summary.
 */
export function from_summary(document) {
  return from_document(document);
}

/**
 * A summary never includes optimistic local edits.
 */
export function summary(state) {
  return state.sequenced;
}

export function apply_operation(document, delta) {
  let _pipe = $rich_text.apply(document, delta);
  return $result.map_error(
    _pipe,
    (var0) => { return new RichTextFailure(var0); },
  );
}

/**
 * The optimistic document. This is the confirmed state with the pending
 * local edits after it.
 */
export function view(state) {
  let $ = state.pending;
  if ($ instanceof $ot_client.Idle) {
    return new Ok(state.sequenced);
  } else if ($ instanceof $ot_client.InFlight) {
    let delta = $.operation;
    return apply_operation(state.sequenced, delta);
  } else {
    let delta = $.operation;
    let buffered = $.buffered;
    return $result.try$(
      apply_operation(state.sequenced, delta),
      (after_delta) => { return apply_operation(after_delta, buffered); },
    );
  }
}

export function transform(a, b, side) {
  let _pipe = $rich_text.transform(a, b, side);
  return $result.map_error(
    _pipe,
    (var0) => { return new RichTextFailure(var0); },
  );
}

export function compose(a, b) {
  let _pipe = $rich_text.compose(a, b);
  return $result.map_error(
    _pipe,
    (var0) => { return new RichTextFailure(var0); },
  );
}

export function invert(delta, base) {
  let _pipe = $rich_text.invert(delta, base);
  return $result.map_error(
    _pipe,
    (var0) => { return new RichTextFailure(var0); },
  );
}

/**
 * Apply a local edit optimistically. The kernel releases only the first
 * pending edit to the caller. It composes each later edit into the one
 * buffer.
 */
export function submit(state, delta, reference_sequence_number) {
  return $result.try$(
    (() => {
      let _pipe = $rich_text.delta_operations(delta);
      return $result.map_error(
        _pipe,
        (var0) => { return new RichTextFailure(var0); },
      );
    })(),
    (delta) => {
      return $result.try$(
        view(state),
        (current) => {
          return $result.try$(
            apply_operation(current, delta),
            (_) => {
              let events = toList([new RichTextChanged(delta, true)]);
              return $result.try$(
                $ot_client.hold_local(state.pending, delta, compose),
                (_use0) => {
                  let pending = _use0[0];
                  let to_send = _use0[1];
                  return new Ok(
                    [
                      new RichTextState(
                        state.sequenced,
                        state.log,
                        pending,
                        state.outbound,
                      ),
                      $option.map(
                        to_send,
                        (_capture) => {
                          return new RichTextWireOperation(
                            reference_sequence_number,
                            _capture,
                          );
                        },
                      ),
                      events,
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

/**
 * Integrate a sequenced operation from another author. The kernel advances
 * the emitted delta through every pending local layer. That delta is thus the
 * exact change to the optimistic editor view, and not only the change to the
 * confirmed document.
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
      wire.delta,
      (current, entry) => {
        return transform(current, entry.operation, $rich_text.Side$Left$const);
      },
    ),
    (head_delta) => {
      return $result.try$(
        apply_operation(state.sequenced, head_delta),
        (sequenced) => {
          return $result.try$(
            $ot_client.rebase_pending(
              state.pending,
              head_delta,
              (local, remote) => {
                return transform(local, remote, $rich_text.Side$Left$const);
              },
              (remote, local) => {
                return transform(remote, local, $rich_text.Side$Right$const);
              },
            ),
            (_use0) => {
              let pending = _use0[0];
              let remote_after_pending = _use0[1];
              let log = $ot_client.gc_log(
                $list.append(
                  state.log,
                  toList([new $ot_client.LogEntry(sequence_number, head_delta)]),
                ),
                minimum_sequence_number,
              );
              let state$1 = new RichTextState(
                sequenced,
                log,
                pending,
                state.outbound,
              );
              return new Ok(
                [
                  state$1,
                  toList([new RichTextChanged(remote_after_pending, false)]),
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
 * Commit the operation on the wire, which the kernel can have rebased. The
 * function ignores the echoed body on purpose, because the FIFO order of the
 * acknowledgement identifies the operation.
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
              toList([new $ot_client.LogEntry(sequence_number, in_flight)]),
            ),
            minimum_sequence_number,
          );
          let $ = $ot_client.promote_buffer(
            state.pending,
            sequence_number,
            (var0, var1) => { return new RichTextWireOperation(var0, var1); },
          );
          let pending = $[0];
          let outbound = $[1];
          return new Ok(
            [
              new RichTextState(sequenced, log, pending, outbound),
              $List$Empty$const,
            ],
          );
        },
      );
    },
  );
}

/**
 * Take the operation that an acknowledgement released. After that, each
 * further call gives `None`.
 */
export function take_outbound(state) {
  let $ = $ot_client.take_pending(state.outbound);
  let outbound = $[0];
  let taken = $[1];
  return [
    new RichTextState(state.sequenced, state.log, state.pending, outbound),
    taken,
  ];
}
