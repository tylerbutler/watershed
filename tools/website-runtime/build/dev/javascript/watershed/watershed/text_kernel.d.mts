import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $text from "../../lattice_text/lattice_text/text.d.mts";
import type * as _ from "../gleam.d.mts";

export class TextState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $text.Text$,
    optimistic: $text.Text$,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $text.Text$;
  /** @deprecated */
  optimistic: $text.Text$;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function TextState$TextState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $text.Text$,
  optimistic: $text.Text$,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): TextState$;
export function TextState$isTextState(value: any): value is TextState$;
export function TextState$TextState$0(value: TextState$): $replica_id.ReplicaId$;
export function TextState$TextState$replica_id(
  value: TextState$,
): $replica_id.ReplicaId$;
export function TextState$TextState$1(value: TextState$): $text.Text$;
export function TextState$TextState$sequenced(value: TextState$): $text.Text$;
export function TextState$TextState$2(value: TextState$): $text.Text$;
export function TextState$TextState$optimistic(value: TextState$): $text.Text$;
export function TextState$TextState$3(value: TextState$): _.List<
  PendingOperation$
>;
export function TextState$TextState$pending(value: TextState$): _.List<
  PendingOperation$
>;
export function TextState$TextState$4(value: TextState$): number;
export function TextState$TextState$next_pending_message_id(value: TextState$): number;

export type TextState$ = TextState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: TextOperation$, message_id: number);
  /** @deprecated */
  operation: TextOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: TextOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): TextOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): TextOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Insert extends _.CustomType {
  /** @deprecated */
  constructor(index: number, value: string, delta: $text.Text$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: string;
  /** @deprecated */
  delta: $text.Text$;
}
export function TextOperation$Insert(
  index: number,
  value: string,
  delta: $text.Text$,
): TextOperation$;
export function TextOperation$isInsert(value: any): value is TextOperation$;
export function TextOperation$Insert$0(value: TextOperation$): number;
export function TextOperation$Insert$index(value: TextOperation$): number;
export function TextOperation$Insert$1(value: TextOperation$): string;
export function TextOperation$Insert$value(value: TextOperation$): string;
export function TextOperation$Insert$2(value: TextOperation$): $text.Text$;
export function TextOperation$Insert$delta(value: TextOperation$): $text.Text$;

export class DeleteRange extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, delta: $text.Text$);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  delta: $text.Text$;
}
export function TextOperation$DeleteRange(
  start: number,
  end: number,
  delta: $text.Text$,
): TextOperation$;
export function TextOperation$isDeleteRange(
  value: any,
): value is TextOperation$;
export function TextOperation$DeleteRange$0(value: TextOperation$): number;
export function TextOperation$DeleteRange$start(value: TextOperation$): number;
export function TextOperation$DeleteRange$1(value: TextOperation$): number;
export function TextOperation$DeleteRange$end(value: TextOperation$): number;
export function TextOperation$DeleteRange$2(value: TextOperation$): $text.Text$;
export function TextOperation$DeleteRange$delta(value: TextOperation$): $text.Text$;

export class ReplaceRange extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, value: string, delta: $text.Text$);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  value: string;
  /** @deprecated */
  delta: $text.Text$;
}
export function TextOperation$ReplaceRange(
  start: number,
  end: number,
  value: string,
  delta: $text.Text$,
): TextOperation$;
export function TextOperation$isReplaceRange(
  value: any,
): value is TextOperation$;
export function TextOperation$ReplaceRange$0(value: TextOperation$): number;
export function TextOperation$ReplaceRange$start(value: TextOperation$): number;
export function TextOperation$ReplaceRange$1(value: TextOperation$): number;
export function TextOperation$ReplaceRange$end(value: TextOperation$): number;
export function TextOperation$ReplaceRange$2(value: TextOperation$): string;
export function TextOperation$ReplaceRange$value(value: TextOperation$): string;
export function TextOperation$ReplaceRange$3(value: TextOperation$): $text.Text$;
export function TextOperation$ReplaceRange$delta(
  value: TextOperation$,
): $text.Text$;

export class Append extends _.CustomType {
  /** @deprecated */
  constructor(value: string, delta: $text.Text$);
  /** @deprecated */
  value: string;
  /** @deprecated */
  delta: $text.Text$;
}
export function TextOperation$Append(
  value: string,
  delta: $text.Text$,
): TextOperation$;
export function TextOperation$isAppend(value: any): value is TextOperation$;
export function TextOperation$Append$0(value: TextOperation$): string;
export function TextOperation$Append$value(value: TextOperation$): string;
export function TextOperation$Append$1(value: TextOperation$): $text.Text$;
export function TextOperation$Append$delta(value: TextOperation$): $text.Text$;

export type TextOperation$ = Insert | DeleteRange | ReplaceRange | Append;

export class TextChanged extends _.CustomType {
  /** @deprecated */
  constructor(value: string);
  /** @deprecated */
  value: string;
}
export function TextEvent$TextChanged(value: string): TextEvent$;
export function TextEvent$isTextChanged(value: any): value is TextEvent$;
export function TextEvent$TextChanged$0(value: TextEvent$): string;
export function TextEvent$TextChanged$value(value: TextEvent$): string;

export type TextEvent$ = TextChanged;

export class InsertOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function EditError$InsertOutOfBounds(
  index: number,
  length: number,
): EditError$;
export function EditError$isInsertOutOfBounds(value: any): value is EditError$;
export function EditError$InsertOutOfBounds$0(value: EditError$): number;
export function EditError$InsertOutOfBounds$index(value: EditError$): number;
export function EditError$InsertOutOfBounds$1(value: EditError$): number;
export function EditError$InsertOutOfBounds$length(value: EditError$): number;

export class DeleteRangeOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, length: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  length: number;
}
export function EditError$DeleteRangeOutOfBounds(
  start: number,
  end: number,
  length: number,
): EditError$;
export function EditError$isDeleteRangeOutOfBounds(
  value: any,
): value is EditError$;
export function EditError$DeleteRangeOutOfBounds$0(value: EditError$): number;
export function EditError$DeleteRangeOutOfBounds$start(value: EditError$): number;
export function EditError$DeleteRangeOutOfBounds$1(
  value: EditError$,
): number;
export function EditError$DeleteRangeOutOfBounds$end(value: EditError$): number;
export function EditError$DeleteRangeOutOfBounds$2(value: EditError$): number;
export function EditError$DeleteRangeOutOfBounds$length(value: EditError$): number;

export class ReplaceRangeOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, length: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  length: number;
}
export function EditError$ReplaceRangeOutOfBounds(
  start: number,
  end: number,
  length: number,
): EditError$;
export function EditError$isReplaceRangeOutOfBounds(
  value: any,
): value is EditError$;
export function EditError$ReplaceRangeOutOfBounds$0(value: EditError$): number;
export function EditError$ReplaceRangeOutOfBounds$start(value: EditError$): number;
export function EditError$ReplaceRangeOutOfBounds$1(
  value: EditError$,
): number;
export function EditError$ReplaceRangeOutOfBounds$end(value: EditError$): number;
export function EditError$ReplaceRangeOutOfBounds$2(
  value: EditError$,
): number;
export function EditError$ReplaceRangeOutOfBounds$length(value: EditError$): number;

export class SubstringOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, length: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  length: number;
}
export function EditError$SubstringOutOfBounds(
  start: number,
  end: number,
  length: number,
): EditError$;
export function EditError$isSubstringOutOfBounds(
  value: any,
): value is EditError$;
export function EditError$SubstringOutOfBounds$0(value: EditError$): number;
export function EditError$SubstringOutOfBounds$start(value: EditError$): number;
export function EditError$SubstringOutOfBounds$1(value: EditError$): number;
export function EditError$SubstringOutOfBounds$end(value: EditError$): number;
export function EditError$SubstringOutOfBounds$2(value: EditError$): number;
export function EditError$SubstringOutOfBounds$length(value: EditError$): number;

export type EditError$ = InsertOutOfBounds | DeleteRangeOutOfBounds | ReplaceRangeOutOfBounds | SubstringOutOfBounds;

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

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(detail: string): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;

export class AnchorOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function AnchorError$AnchorOutOfBounds(
  index: number,
  length: number,
): AnchorError$;
export function AnchorError$isAnchorOutOfBounds(
  value: any,
): value is AnchorError$;
export function AnchorError$AnchorOutOfBounds$0(value: AnchorError$): number;
export function AnchorError$AnchorOutOfBounds$index(value: AnchorError$): number;
export function AnchorError$AnchorOutOfBounds$1(
  value: AnchorError$,
): number;
export function AnchorError$AnchorOutOfBounds$length(value: AnchorError$): number;

export class UnknownAnchorTarget extends _.CustomType {}
export function AnchorError$UnknownAnchorTarget(): AnchorError$;
export function AnchorError$isUnknownAnchorTarget(
  value: any,
): value is AnchorError$;

export type AnchorError$ = AnchorOutOfBounds | UnknownAnchorTarget;

declare class TextAnchor extends _.CustomType {
  /** @deprecated */
  constructor(anchor: $sequence.Anchor$);
  /** @deprecated */
  anchor: $sequence.Anchor$;
}

export type TextAnchor$ = TextAnchor;

export class Submission extends _.CustomType {
  /** @deprecated */
  constructor(operation: TextOperation$, message_id: number);
  /** @deprecated */
  operation: TextOperation$;
  /** @deprecated */
  message_id: number;
}
export function Submission$Submission(
  operation: TextOperation$,
  message_id: number,
): Submission$;
export function Submission$isSubmission(value: any): value is Submission$;
export function Submission$Submission$0(value: Submission$): TextOperation$;
export function Submission$Submission$operation(value: Submission$): TextOperation$;
export function Submission$Submission$1(
  value: Submission$,
): number;
export function Submission$Submission$message_id(value: Submission$): number;

export type Submission$ = Submission;

export type Bias = $sequence.Bias$;

export function new$(replica_id: $replica_id.ReplicaId$): TextState$;

export function value(state: TextState$): string;

export function sequenced_value(state: TextState$): string;

export function length(state: TextState$): number;

export function substring(state: TextState$, start: number, end: number): _.Result<
  string,
  EditError$
>;

export function insert(state: TextState$, index: number, value: string): _.Result<
  [TextState$, _.List<TextEvent$>, $option.Option$<Submission$>],
  EditError$
>;

export function delete_range(state: TextState$, start: number, end: number): _.Result<
  [TextState$, _.List<TextEvent$>, $option.Option$<Submission$>],
  EditError$
>;

export function replace_range(
  state: TextState$,
  start: number,
  end: number,
  value: string
): _.Result<
  [TextState$, _.List<TextEvent$>, $option.Option$<Submission$>],
  EditError$
>;

export function append(state: TextState$, value: string): [
  TextState$,
  _.List<TextEvent$>,
  $option.Option$<Submission$>
];

export function p2p_insert(state: TextState$, index: number, value: string): _.Result<
  [TextState$, _.List<TextEvent$>, TextOperation$],
  EditError$
>;

export function p2p_delete_range(state: TextState$, start: number, end: number): _.Result<
  [TextState$, _.List<TextEvent$>, TextOperation$],
  EditError$
>;

export function p2p_replace_range(
  state: TextState$,
  start: number,
  end: number,
  value: string
): _.Result<[TextState$, _.List<TextEvent$>, TextOperation$], EditError$>;

export function p2p_append(state: TextState$, value: string): [
  TextState$,
  _.List<TextEvent$>,
  TextOperation$
];

export function p2p_merge(state: TextState$, other: $text.Text$): [
  TextState$,
  _.List<TextEvent$>
];

export function apply_remote(state: TextState$, operation: TextOperation$): [
  TextState$,
  _.List<TextEvent$>
];

export function ack_local(state: TextState$, operation: TextOperation$): _.Result<
  TextState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: TextState$,
  operation: TextOperation$,
  message_id: number
): _.Result<TextState$, KernelError$>;

export function rollback(
  state: TextState$,
  operation: TextOperation$,
  message_id: number
): _.Result<[TextState$, _.List<TextEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: TextState$,
  operation: TextOperation$
): [TextState$, _.List<TextEvent$>, TextOperation$, number];

export function promote_attach(state: TextState$): TextState$;

export function summary(state: TextState$): $json.Json$;

export function from_sequenced(
  sequenced: $text.Text$,
  replica_id: $replica_id.ReplicaId$
): TextState$;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<TextState$, $json.DecodeError$>;

export function check_cache_coherence(state: TextState$): _.Result<
  undefined,
  string
>;

export function edit_error_detail(error: EditError$): string;

export function anchor_error_detail(error: AnchorError$): string;

export function anchor_at(
  state: TextState$,
  index: number,
  bias: $sequence.Bias$
): _.Result<TextAnchor$, AnchorError$>;

export function resolve_anchor(state: TextState$, anchor: TextAnchor$): _.Result<
  number,
  AnchorError$
>;

export function start_anchor(): TextAnchor$;

export function end_anchor(): TextAnchor$;

export function anchor_to_json(anchor: TextAnchor$): $json.Json$;

export function anchor_from_json(json_string: string): _.Result<
  TextAnchor$,
  $json.DecodeError$
>;
