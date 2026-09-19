import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as _ from "../gleam.d.mts";

export class SequenceState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $sequence.Sequence$<$json.Json$>,
    optimistic: $sequence.Sequence$<$json.Json$>,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $sequence.Sequence$<$json.Json$>;
  /** @deprecated */
  optimistic: $sequence.Sequence$<$json.Json$>;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function SequenceState$SequenceState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $sequence.Sequence$<$json.Json$>,
  optimistic: $sequence.Sequence$<$json.Json$>,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): SequenceState$;
export function SequenceState$isSequenceState(
  value: any,
): value is SequenceState$;
export function SequenceState$SequenceState$0(value: SequenceState$): $replica_id.ReplicaId$;
export function SequenceState$SequenceState$replica_id(
  value: SequenceState$,
): $replica_id.ReplicaId$;
export function SequenceState$SequenceState$1(value: SequenceState$): $sequence.Sequence$<
  $json.Json$
>;
export function SequenceState$SequenceState$sequenced(value: SequenceState$): $sequence.Sequence$<
  $json.Json$
>;
export function SequenceState$SequenceState$2(value: SequenceState$): $sequence.Sequence$<
  $json.Json$
>;
export function SequenceState$SequenceState$optimistic(value: SequenceState$): $sequence.Sequence$<
  $json.Json$
>;
export function SequenceState$SequenceState$3(value: SequenceState$): _.List<
  PendingOperation$
>;
export function SequenceState$SequenceState$pending(value: SequenceState$): _.List<
  PendingOperation$
>;
export function SequenceState$SequenceState$4(value: SequenceState$): number;
export function SequenceState$SequenceState$next_pending_message_id(value: SequenceState$): number;

export type SequenceState$ = SequenceState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: SequenceOperation$, message_id: number);
  /** @deprecated */
  operation: SequenceOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: SequenceOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): SequenceOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): SequenceOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Insert extends _.CustomType {
  /** @deprecated */
  constructor(
    index: number,
    value: $json.Json$,
    delta: $sequence.Sequence$<$json.Json$>
  );
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  delta: $sequence.Sequence$<$json.Json$>;
}
export function SequenceOperation$Insert(
  index: number,
  value: $json.Json$,
  delta: $sequence.Sequence$<$json.Json$>,
): SequenceOperation$;
export function SequenceOperation$isInsert(
  value: any,
): value is SequenceOperation$;
export function SequenceOperation$Insert$0(value: SequenceOperation$): number;
export function SequenceOperation$Insert$index(value: SequenceOperation$): number;
export function SequenceOperation$Insert$1(
  value: SequenceOperation$,
): $json.Json$;
export function SequenceOperation$Insert$value(value: SequenceOperation$): $json.Json$;
export function SequenceOperation$Insert$2(
  value: SequenceOperation$,
): $sequence.Sequence$<$json.Json$>;
export function SequenceOperation$Insert$delta(value: SequenceOperation$): $sequence.Sequence$<
  $json.Json$
>;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(index: number, delta: $sequence.Sequence$<$json.Json$>);
  /** @deprecated */
  index: number;
  /** @deprecated */
  delta: $sequence.Sequence$<$json.Json$>;
}
export function SequenceOperation$Delete(
  index: number,
  delta: $sequence.Sequence$<$json.Json$>,
): SequenceOperation$;
export function SequenceOperation$isDelete(
  value: any,
): value is SequenceOperation$;
export function SequenceOperation$Delete$0(value: SequenceOperation$): number;
export function SequenceOperation$Delete$index(value: SequenceOperation$): number;
export function SequenceOperation$Delete$1(
  value: SequenceOperation$,
): $sequence.Sequence$<$json.Json$>;
export function SequenceOperation$Delete$delta(value: SequenceOperation$): $sequence.Sequence$<
  $json.Json$
>;

export class Move extends _.CustomType {
  /** @deprecated */
  constructor(
    from_index: number,
    to_index: number,
    delta: $sequence.Sequence$<$json.Json$>
  );
  /** @deprecated */
  from_index: number;
  /** @deprecated */
  to_index: number;
  /** @deprecated */
  delta: $sequence.Sequence$<$json.Json$>;
}
export function SequenceOperation$Move(
  from_index: number,
  to_index: number,
  delta: $sequence.Sequence$<$json.Json$>,
): SequenceOperation$;
export function SequenceOperation$isMove(
  value: any,
): value is SequenceOperation$;
export function SequenceOperation$Move$0(value: SequenceOperation$): number;
export function SequenceOperation$Move$from_index(value: SequenceOperation$): number;
export function SequenceOperation$Move$1(
  value: SequenceOperation$,
): number;
export function SequenceOperation$Move$to_index(value: SequenceOperation$): number;
export function SequenceOperation$Move$2(
  value: SequenceOperation$,
): $sequence.Sequence$<$json.Json$>;
export function SequenceOperation$Move$delta(value: SequenceOperation$): $sequence.Sequence$<
  $json.Json$
>;

export class Replace extends _.CustomType {
  /** @deprecated */
  constructor(
    index: number,
    value: $json.Json$,
    delta: $sequence.Sequence$<$json.Json$>
  );
  /** @deprecated */
  index: number;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  delta: $sequence.Sequence$<$json.Json$>;
}
export function SequenceOperation$Replace(
  index: number,
  value: $json.Json$,
  delta: $sequence.Sequence$<$json.Json$>,
): SequenceOperation$;
export function SequenceOperation$isReplace(
  value: any,
): value is SequenceOperation$;
export function SequenceOperation$Replace$0(value: SequenceOperation$): number;
export function SequenceOperation$Replace$index(value: SequenceOperation$): number;
export function SequenceOperation$Replace$1(
  value: SequenceOperation$,
): $json.Json$;
export function SequenceOperation$Replace$value(value: SequenceOperation$): $json.Json$;
export function SequenceOperation$Replace$2(
  value: SequenceOperation$,
): $sequence.Sequence$<$json.Json$>;
export function SequenceOperation$Replace$delta(value: SequenceOperation$): $sequence.Sequence$<
  $json.Json$
>;

export type SequenceOperation$ = Insert | Delete | Move | Replace;

export class SequenceChanged extends _.CustomType {
  /** @deprecated */
  constructor(values: _.List<$json.Json$>);
  /** @deprecated */
  values: _.List<$json.Json$>;
}
export function SequenceEvent$SequenceChanged(
  values: _.List<$json.Json$>,
): SequenceEvent$;
export function SequenceEvent$isSequenceChanged(
  value: any,
): value is SequenceEvent$;
export function SequenceEvent$SequenceChanged$0(value: SequenceEvent$): _.List<
  $json.Json$
>;
export function SequenceEvent$SequenceChanged$values(value: SequenceEvent$): _.List<
  $json.Json$
>;

export type SequenceEvent$ = SequenceChanged;

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

export class DeleteOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function EditError$DeleteOutOfBounds(
  index: number,
  length: number,
): EditError$;
export function EditError$isDeleteOutOfBounds(value: any): value is EditError$;
export function EditError$DeleteOutOfBounds$0(value: EditError$): number;
export function EditError$DeleteOutOfBounds$index(value: EditError$): number;
export function EditError$DeleteOutOfBounds$1(value: EditError$): number;
export function EditError$DeleteOutOfBounds$length(value: EditError$): number;

export class MoveFromOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function EditError$MoveFromOutOfBounds(
  index: number,
  length: number,
): EditError$;
export function EditError$isMoveFromOutOfBounds(
  value: any,
): value is EditError$;
export function EditError$MoveFromOutOfBounds$0(value: EditError$): number;
export function EditError$MoveFromOutOfBounds$index(value: EditError$): number;
export function EditError$MoveFromOutOfBounds$1(value: EditError$): number;
export function EditError$MoveFromOutOfBounds$length(value: EditError$): number;

export class MoveToOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length_after_removal: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length_after_removal: number;
}
export function EditError$MoveToOutOfBounds(
  index: number,
  length_after_removal: number,
): EditError$;
export function EditError$isMoveToOutOfBounds(value: any): value is EditError$;
export function EditError$MoveToOutOfBounds$0(value: EditError$): number;
export function EditError$MoveToOutOfBounds$index(value: EditError$): number;
export function EditError$MoveToOutOfBounds$1(value: EditError$): number;
export function EditError$MoveToOutOfBounds$length_after_removal(value: EditError$): number;

export class ReplaceOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(index: number, length: number);
  /** @deprecated */
  index: number;
  /** @deprecated */
  length: number;
}
export function EditError$ReplaceOutOfBounds(
  index: number,
  length: number,
): EditError$;
export function EditError$isReplaceOutOfBounds(value: any): value is EditError$;
export function EditError$ReplaceOutOfBounds$0(value: EditError$): number;
export function EditError$ReplaceOutOfBounds$index(value: EditError$): number;
export function EditError$ReplaceOutOfBounds$1(value: EditError$): number;
export function EditError$ReplaceOutOfBounds$length(value: EditError$): number;

export type EditError$ = InsertOutOfBounds | DeleteOutOfBounds | MoveFromOutOfBounds | MoveToOutOfBounds | ReplaceOutOfBounds;

export function EditError$index(value: EditError$): number;

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

export function new$(replica_id: $replica_id.ReplicaId$): SequenceState$;

export function values(state: SequenceState$): _.List<$json.Json$>;

export function sequenced_values(state: SequenceState$): _.List<$json.Json$>;

export function length(state: SequenceState$): number;

export function insert(state: SequenceState$, index: number, value: $json.Json$): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$, number],
  EditError$
>;

export function delete$(state: SequenceState$, index: number): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$, number],
  EditError$
>;

export function move(
  state: SequenceState$,
  from_index: number,
  to_index: number
): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$, number],
  EditError$
>;

export function replace(
  state: SequenceState$,
  index: number,
  value: $json.Json$
): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$, number],
  EditError$
>;

export function p2p_merge(
  state: SequenceState$,
  other: $sequence.Sequence$<$json.Json$>
): [SequenceState$, _.List<SequenceEvent$>];

export function apply_remote(
  state: SequenceState$,
  operation: SequenceOperation$
): [SequenceState$, _.List<SequenceEvent$>];

export function p2p_insert(
  state: SequenceState$,
  index: number,
  value: $json.Json$
): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$],
  EditError$
>;

export function p2p_delete(state: SequenceState$, index: number): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$],
  EditError$
>;

export function p2p_move(
  state: SequenceState$,
  from_index: number,
  to_index: number
): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$],
  EditError$
>;

export function p2p_replace(
  state: SequenceState$,
  index: number,
  value: $json.Json$
): _.Result<
  [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$],
  EditError$
>;

export function ack_local(state: SequenceState$, operation: SequenceOperation$): _.Result<
  SequenceState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: SequenceState$,
  operation: SequenceOperation$,
  message_id: number
): _.Result<SequenceState$, KernelError$>;

export function rollback(
  state: SequenceState$,
  operation: SequenceOperation$,
  message_id: number
): _.Result<[SequenceState$, _.List<SequenceEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: SequenceState$,
  operation: SequenceOperation$
): [SequenceState$, _.List<SequenceEvent$>, SequenceOperation$, number];

export function promote_attach(state: SequenceState$): SequenceState$;

export function summary(state: SequenceState$): $json.Json$;

export function from_sequenced(
  sequenced: $sequence.Sequence$<$json.Json$>,
  replica_id: $replica_id.ReplicaId$
): SequenceState$;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<SequenceState$, $json.DecodeError$>;

export function check_cache_coherence(state: SequenceState$): _.Result<
  undefined,
  string
>;

export function edit_error_detail(error: EditError$): string;
