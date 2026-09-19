import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $ot_client from "../watershed/ot_client.d.mts";
import type * as $rich_text from "../watershed/rich_text.d.mts";

export class RichTextState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $rich_text.Document$,
    log: _.List<$ot_client.LogEntry$<$rich_text.Delta$>>,
    pending: $ot_client.Pending$<$rich_text.Delta$>,
    outbound: $option.Option$<RichTextWireOperation$>
  );
  /** @deprecated */
  sequenced: $rich_text.Document$;
  /** @deprecated */
  log: _.List<$ot_client.LogEntry$<$rich_text.Delta$>>;
  /** @deprecated */
  pending: $ot_client.Pending$<$rich_text.Delta$>;
  /** @deprecated */
  outbound: $option.Option$<RichTextWireOperation$>;
}
export function RichTextState$RichTextState(
  sequenced: $rich_text.Document$,
  log: _.List<$ot_client.LogEntry$<$rich_text.Delta$>>,
  pending: $ot_client.Pending$<$rich_text.Delta$>,
  outbound: $option.Option$<RichTextWireOperation$>,
): RichTextState$;
export function RichTextState$isRichTextState(
  value: any,
): value is RichTextState$;
export function RichTextState$RichTextState$0(value: RichTextState$): $rich_text.Document$;
export function RichTextState$RichTextState$sequenced(
  value: RichTextState$,
): $rich_text.Document$;
export function RichTextState$RichTextState$1(value: RichTextState$): _.List<
  $ot_client.LogEntry$<$rich_text.Delta$>
>;
export function RichTextState$RichTextState$log(value: RichTextState$): _.List<
  $ot_client.LogEntry$<$rich_text.Delta$>
>;
export function RichTextState$RichTextState$2(value: RichTextState$): $ot_client.Pending$<
  $rich_text.Delta$
>;
export function RichTextState$RichTextState$pending(value: RichTextState$): $ot_client.Pending$<
  $rich_text.Delta$
>;
export function RichTextState$RichTextState$3(value: RichTextState$): $option.Option$<
  RichTextWireOperation$
>;
export function RichTextState$RichTextState$outbound(value: RichTextState$): $option.Option$<
  RichTextWireOperation$
>;

export type RichTextState$ = RichTextState;

export class RichTextWireOperation extends _.CustomType {
  /** @deprecated */
  constructor(reference_sequence_number: number, delta: $rich_text.Delta$);
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  delta: $rich_text.Delta$;
}
export function RichTextWireOperation$RichTextWireOperation(
  reference_sequence_number: number,
  delta: $rich_text.Delta$,
): RichTextWireOperation$;
export function RichTextWireOperation$isRichTextWireOperation(
  value: any,
): value is RichTextWireOperation$;
export function RichTextWireOperation$RichTextWireOperation$0(value: RichTextWireOperation$): number;
export function RichTextWireOperation$RichTextWireOperation$reference_sequence_number(
  value: RichTextWireOperation$,
): number;
export function RichTextWireOperation$RichTextWireOperation$1(value: RichTextWireOperation$): $rich_text.Delta$;
export function RichTextWireOperation$RichTextWireOperation$delta(
  value: RichTextWireOperation$,
): $rich_text.Delta$;

export type RichTextWireOperation$ = RichTextWireOperation;

export class RichTextChanged extends _.CustomType {
  /** @deprecated */
  constructor(delta: $rich_text.Delta$, local: boolean);
  /** @deprecated */
  delta: $rich_text.Delta$;
  /** @deprecated */
  local: boolean;
}
export function RichTextEvent$RichTextChanged(
  delta: $rich_text.Delta$,
  local: boolean,
): RichTextEvent$;
export function RichTextEvent$isRichTextChanged(
  value: any,
): value is RichTextEvent$;
export function RichTextEvent$RichTextChanged$0(value: RichTextEvent$): $rich_text.Delta$;
export function RichTextEvent$RichTextChanged$delta(
  value: RichTextEvent$,
): $rich_text.Delta$;
export function RichTextEvent$RichTextChanged$1(value: RichTextEvent$): boolean;
export function RichTextEvent$RichTextChanged$local(value: RichTextEvent$): boolean;

export type RichTextEvent$ = RichTextChanged;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(detail: string): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class RichTextFailure extends _.CustomType {
  /** @deprecated */
  constructor(error: $rich_text.Error$);
  /** @deprecated */
  error: $rich_text.Error$;
}
export function KernelError$RichTextFailure(
  error: $rich_text.Error$,
): KernelError$;
export function KernelError$isRichTextFailure(
  value: any,
): value is KernelError$;
export function KernelError$RichTextFailure$0(value: KernelError$): $rich_text.Error$;
export function KernelError$RichTextFailure$error(
  value: KernelError$,
): $rich_text.Error$;

export type KernelError$ = UnexpectedAck | RichTextFailure;

export function from_document(document: $rich_text.Document$): RichTextState$;

export function new$(): RichTextState$;

export function from_summary(document: $rich_text.Document$): RichTextState$;

export function summary(state: RichTextState$): $rich_text.Document$;

export function apply_operation(
  document: $rich_text.Document$,
  delta: $rich_text.Delta$
): _.Result<$rich_text.Document$, KernelError$>;

export function view(state: RichTextState$): _.Result<
  $rich_text.Document$,
  KernelError$
>;

export function transform(
  a: $rich_text.Delta$,
  b: $rich_text.Delta$,
  side: $rich_text.Side$
): _.Result<$rich_text.Delta$, KernelError$>;

export function compose(a: $rich_text.Delta$, b: $rich_text.Delta$): _.Result<
  $rich_text.Delta$,
  KernelError$
>;

export function invert(delta: $rich_text.Delta$, base: $rich_text.Document$): _.Result<
  $rich_text.Delta$,
  KernelError$
>;

export function submit(
  state: RichTextState$,
  delta: $rich_text.Delta$,
  reference_sequence_number: number
): _.Result<
  [
    RichTextState$,
    $option.Option$<RichTextWireOperation$>,
    _.List<RichTextEvent$>
  ],
  KernelError$
>;

export function apply_remote(
  state: RichTextState$,
  wire: RichTextWireOperation$,
  sequence_number: number,
  minimum_sequence_number: number
): _.Result<[RichTextState$, _.List<RichTextEvent$>], KernelError$>;

export function ack_local(
  state: RichTextState$,
  x1: RichTextWireOperation$,
  sequence_number: number,
  minimum_sequence_number: number
): _.Result<[RichTextState$, _.List<RichTextEvent$>], KernelError$>;

export function take_outbound(state: RichTextState$): [
  RichTextState$,
  $option.Option$<RichTextWireOperation$>
];
