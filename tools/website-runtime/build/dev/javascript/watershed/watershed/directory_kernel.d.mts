import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $order from "../../gleam_stdlib/gleam/order.d.mts";
import type * as _ from "../gleam.d.mts";

export class DirectoryState extends _.CustomType {
  /** @deprecated */
  constructor(root: DirectoryNode$, next_message_id: number);
  /** @deprecated */
  root: DirectoryNode$;
  /** @deprecated */
  next_message_id: number;
}
export function DirectoryState$DirectoryState(
  root: DirectoryNode$,
  next_message_id: number,
): DirectoryState$;
export function DirectoryState$isDirectoryState(
  value: any,
): value is DirectoryState$;
export function DirectoryState$DirectoryState$0(value: DirectoryState$): DirectoryNode$;
export function DirectoryState$DirectoryState$root(
  value: DirectoryState$,
): DirectoryNode$;
export function DirectoryState$DirectoryState$1(value: DirectoryState$): number;
export function DirectoryState$DirectoryState$next_message_id(value: DirectoryState$): number;

export type DirectoryState$ = DirectoryState;

export class DirectoryNode extends _.CustomType {
  /** @deprecated */
  constructor(
    path: string,
    create: CreateInfo$,
    birth: CreateInfo$,
    creators: _.List<number>,
    detached_created: boolean,
    disposed: boolean,
    storage: StorageState$,
    subdirectories: $dict.Dict$<string, DirectoryNode$>,
    subdirectory_order: _.List<string>,
    pending_subdirectories: _.List<PendingSubdirectory$>
  );
  /** @deprecated */
  path: string;
  /** @deprecated */
  create: CreateInfo$;
  /** @deprecated */
  birth: CreateInfo$;
  /** @deprecated */
  creators: _.List<number>;
  /** @deprecated */
  detached_created: boolean;
  /** @deprecated */
  disposed: boolean;
  /** @deprecated */
  storage: StorageState$;
  /** @deprecated */
  subdirectories: $dict.Dict$<string, DirectoryNode$>;
  /** @deprecated */
  subdirectory_order: _.List<string>;
  /** @deprecated */
  pending_subdirectories: _.List<PendingSubdirectory$>;
}
export function DirectoryNode$DirectoryNode(
  path: string,
  create: CreateInfo$,
  birth: CreateInfo$,
  creators: _.List<number>,
  detached_created: boolean,
  disposed: boolean,
  storage: StorageState$,
  subdirectories: $dict.Dict$<string, DirectoryNode$>,
  subdirectory_order: _.List<string>,
  pending_subdirectories: _.List<PendingSubdirectory$>,
): DirectoryNode$;
export function DirectoryNode$isDirectoryNode(
  value: any,
): value is DirectoryNode$;
export function DirectoryNode$DirectoryNode$0(value: DirectoryNode$): string;
export function DirectoryNode$DirectoryNode$path(value: DirectoryNode$): string;
export function DirectoryNode$DirectoryNode$1(value: DirectoryNode$): CreateInfo$;
export function DirectoryNode$DirectoryNode$create(
  value: DirectoryNode$,
): CreateInfo$;
export function DirectoryNode$DirectoryNode$2(value: DirectoryNode$): CreateInfo$;
export function DirectoryNode$DirectoryNode$birth(
  value: DirectoryNode$,
): CreateInfo$;
export function DirectoryNode$DirectoryNode$3(value: DirectoryNode$): _.List<
  number
>;
export function DirectoryNode$DirectoryNode$creators(value: DirectoryNode$): _.List<
  number
>;
export function DirectoryNode$DirectoryNode$4(value: DirectoryNode$): boolean;
export function DirectoryNode$DirectoryNode$detached_created(value: DirectoryNode$): boolean;
export function DirectoryNode$DirectoryNode$5(
  value: DirectoryNode$,
): boolean;
export function DirectoryNode$DirectoryNode$disposed(value: DirectoryNode$): boolean;
export function DirectoryNode$DirectoryNode$6(
  value: DirectoryNode$,
): StorageState$;
export function DirectoryNode$DirectoryNode$storage(value: DirectoryNode$): StorageState$;
export function DirectoryNode$DirectoryNode$7(
  value: DirectoryNode$,
): $dict.Dict$<string, DirectoryNode$>;
export function DirectoryNode$DirectoryNode$subdirectories(value: DirectoryNode$): $dict.Dict$<
  string,
  DirectoryNode$
>;
export function DirectoryNode$DirectoryNode$8(value: DirectoryNode$): _.List<
  string
>;
export function DirectoryNode$DirectoryNode$subdirectory_order(value: DirectoryNode$): _.List<
  string
>;
export function DirectoryNode$DirectoryNode$9(value: DirectoryNode$): _.List<
  PendingSubdirectory$
>;
export function DirectoryNode$DirectoryNode$pending_subdirectories(value: DirectoryNode$): _.List<
  PendingSubdirectory$
>;

export type DirectoryNode$ = DirectoryNode;

export class CreateInfo extends _.CustomType {
  /** @deprecated */
  constructor(sequence_number: number, client_sequence_number: number);
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  client_sequence_number: number;
}
export function CreateInfo$CreateInfo(
  sequence_number: number,
  client_sequence_number: number,
): CreateInfo$;
export function CreateInfo$isCreateInfo(value: any): value is CreateInfo$;
export function CreateInfo$CreateInfo$0(value: CreateInfo$): number;
export function CreateInfo$CreateInfo$sequence_number(value: CreateInfo$): number;
export function CreateInfo$CreateInfo$1(
  value: CreateInfo$,
): number;
export function CreateInfo$CreateInfo$client_sequence_number(value: CreateInfo$): number;

export type CreateInfo$ = CreateInfo;

export class StorageState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $dict.Dict$<string, $json.Json$>,
    insertion_order: _.List<string>,
    pending: _.List<PendingStorage$>
  );
  /** @deprecated */
  sequenced: $dict.Dict$<string, $json.Json$>;
  /** @deprecated */
  insertion_order: _.List<string>;
  /** @deprecated */
  pending: _.List<PendingStorage$>;
}
export function StorageState$StorageState(
  sequenced: $dict.Dict$<string, $json.Json$>,
  insertion_order: _.List<string>,
  pending: _.List<PendingStorage$>,
): StorageState$;
export function StorageState$isStorageState(value: any): value is StorageState$;
export function StorageState$StorageState$0(value: StorageState$): $dict.Dict$<
  string,
  $json.Json$
>;
export function StorageState$StorageState$sequenced(value: StorageState$): $dict.Dict$<
  string,
  $json.Json$
>;
export function StorageState$StorageState$1(value: StorageState$): _.List<
  string
>;
export function StorageState$StorageState$insertion_order(value: StorageState$): _.List<
  string
>;
export function StorageState$StorageState$2(value: StorageState$): _.List<
  PendingStorage$
>;
export function StorageState$StorageState$pending(value: StorageState$): _.List<
  PendingStorage$
>;

export type StorageState$ = StorageState;

export class PendingLifetime extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    sets: _.List<$json.Json$>,
    message_ids: _.List<number>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  sets: _.List<$json.Json$>;
  /** @deprecated */
  message_ids: _.List<number>;
}
export function PendingStorage$PendingLifetime(
  key: string,
  sets: _.List<$json.Json$>,
  message_ids: _.List<number>,
): PendingStorage$;
export function PendingStorage$isPendingLifetime(
  value: any,
): value is PendingStorage$;
export function PendingStorage$PendingLifetime$0(value: PendingStorage$): string;
export function PendingStorage$PendingLifetime$key(
  value: PendingStorage$,
): string;
export function PendingStorage$PendingLifetime$1(value: PendingStorage$): _.List<
  $json.Json$
>;
export function PendingStorage$PendingLifetime$sets(value: PendingStorage$): _.List<
  $json.Json$
>;
export function PendingStorage$PendingLifetime$2(value: PendingStorage$): _.List<
  number
>;
export function PendingStorage$PendingLifetime$message_ids(value: PendingStorage$): _.List<
  number
>;

export class PendingDelete extends _.CustomType {
  /** @deprecated */
  constructor(key: string, message_id: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  message_id: number;
}
export function PendingStorage$PendingDelete(
  key: string,
  message_id: number,
): PendingStorage$;
export function PendingStorage$isPendingDelete(
  value: any,
): value is PendingStorage$;
export function PendingStorage$PendingDelete$0(value: PendingStorage$): string;
export function PendingStorage$PendingDelete$key(value: PendingStorage$): string;
export function PendingStorage$PendingDelete$1(
  value: PendingStorage$,
): number;
export function PendingStorage$PendingDelete$message_id(value: PendingStorage$): number;

export class PendingClear extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}
export function PendingStorage$PendingClear(
  message_id: number,
): PendingStorage$;
export function PendingStorage$isPendingClear(
  value: any,
): value is PendingStorage$;
export function PendingStorage$PendingClear$0(value: PendingStorage$): number;
export function PendingStorage$PendingClear$message_id(value: PendingStorage$): number;

export type PendingStorage$ = PendingLifetime | PendingDelete | PendingClear;

export class PendingCreate extends _.CustomType {
  /** @deprecated */
  constructor(
    name: string,
    node: DirectoryNode$,
    message_id: number,
    folded: boolean
  );
  /** @deprecated */
  name: string;
  /** @deprecated */
  node: DirectoryNode$;
  /** @deprecated */
  message_id: number;
  /** @deprecated */
  folded: boolean;
}
export function PendingSubdirectory$PendingCreate(
  name: string,
  node: DirectoryNode$,
  message_id: number,
  folded: boolean,
): PendingSubdirectory$;
export function PendingSubdirectory$isPendingCreate(
  value: any,
): value is PendingSubdirectory$;
export function PendingSubdirectory$PendingCreate$0(value: PendingSubdirectory$): string;
export function PendingSubdirectory$PendingCreate$name(
  value: PendingSubdirectory$,
): string;
export function PendingSubdirectory$PendingCreate$1(value: PendingSubdirectory$): DirectoryNode$;
export function PendingSubdirectory$PendingCreate$node(
  value: PendingSubdirectory$,
): DirectoryNode$;
export function PendingSubdirectory$PendingCreate$2(value: PendingSubdirectory$): number;
export function PendingSubdirectory$PendingCreate$message_id(
  value: PendingSubdirectory$,
): number;
export function PendingSubdirectory$PendingCreate$3(value: PendingSubdirectory$): boolean;
export function PendingSubdirectory$PendingCreate$folded(
  value: PendingSubdirectory$,
): boolean;

export class PendingRemove extends _.CustomType {
  /** @deprecated */
  constructor(name: string, message_id: number);
  /** @deprecated */
  name: string;
  /** @deprecated */
  message_id: number;
}
export function PendingSubdirectory$PendingRemove(
  name: string,
  message_id: number,
): PendingSubdirectory$;
export function PendingSubdirectory$isPendingRemove(
  value: any,
): value is PendingSubdirectory$;
export function PendingSubdirectory$PendingRemove$0(value: PendingSubdirectory$): string;
export function PendingSubdirectory$PendingRemove$name(
  value: PendingSubdirectory$,
): string;
export function PendingSubdirectory$PendingRemove$1(value: PendingSubdirectory$): number;
export function PendingSubdirectory$PendingRemove$message_id(
  value: PendingSubdirectory$,
): number;

export type PendingSubdirectory$ = PendingCreate | PendingRemove;

export function PendingSubdirectory$name(value: PendingSubdirectory$): string;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(path: string, key: string, value: $json.Json$);
  /** @deprecated */
  path: string;
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
}
export function DirectoryOperation$Set(
  path: string,
  key: string,
  value: $json.Json$,
): DirectoryOperation$;
export function DirectoryOperation$isSet(
  value: any,
): value is DirectoryOperation$;
export function DirectoryOperation$Set$0(value: DirectoryOperation$): string;
export function DirectoryOperation$Set$path(value: DirectoryOperation$): string;
export function DirectoryOperation$Set$1(value: DirectoryOperation$): string;
export function DirectoryOperation$Set$key(value: DirectoryOperation$): string;
export function DirectoryOperation$Set$2(value: DirectoryOperation$): $json.Json$;
export function DirectoryOperation$Set$value(
  value: DirectoryOperation$,
): $json.Json$;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(path: string, key: string);
  /** @deprecated */
  path: string;
  /** @deprecated */
  key: string;
}
export function DirectoryOperation$Delete(
  path: string,
  key: string,
): DirectoryOperation$;
export function DirectoryOperation$isDelete(
  value: any,
): value is DirectoryOperation$;
export function DirectoryOperation$Delete$0(value: DirectoryOperation$): string;
export function DirectoryOperation$Delete$path(value: DirectoryOperation$): string;
export function DirectoryOperation$Delete$1(
  value: DirectoryOperation$,
): string;
export function DirectoryOperation$Delete$key(value: DirectoryOperation$): string;

export class Clear extends _.CustomType {
  /** @deprecated */
  constructor(path: string);
  /** @deprecated */
  path: string;
}
export function DirectoryOperation$Clear(path: string): DirectoryOperation$;
export function DirectoryOperation$isClear(
  value: any,
): value is DirectoryOperation$;
export function DirectoryOperation$Clear$0(value: DirectoryOperation$): string;
export function DirectoryOperation$Clear$path(value: DirectoryOperation$): string;

export class CreateSubDirectory extends _.CustomType {
  /** @deprecated */
  constructor(path: string, name: string);
  /** @deprecated */
  path: string;
  /** @deprecated */
  name: string;
}
export function DirectoryOperation$CreateSubDirectory(
  path: string,
  name: string,
): DirectoryOperation$;
export function DirectoryOperation$isCreateSubDirectory(
  value: any,
): value is DirectoryOperation$;
export function DirectoryOperation$CreateSubDirectory$0(value: DirectoryOperation$): string;
export function DirectoryOperation$CreateSubDirectory$path(
  value: DirectoryOperation$,
): string;
export function DirectoryOperation$CreateSubDirectory$1(value: DirectoryOperation$): string;
export function DirectoryOperation$CreateSubDirectory$name(
  value: DirectoryOperation$,
): string;

export class DeleteSubDirectory extends _.CustomType {
  /** @deprecated */
  constructor(path: string, name: string);
  /** @deprecated */
  path: string;
  /** @deprecated */
  name: string;
}
export function DirectoryOperation$DeleteSubDirectory(
  path: string,
  name: string,
): DirectoryOperation$;
export function DirectoryOperation$isDeleteSubDirectory(
  value: any,
): value is DirectoryOperation$;
export function DirectoryOperation$DeleteSubDirectory$0(value: DirectoryOperation$): string;
export function DirectoryOperation$DeleteSubDirectory$path(
  value: DirectoryOperation$,
): string;
export function DirectoryOperation$DeleteSubDirectory$1(value: DirectoryOperation$): string;
export function DirectoryOperation$DeleteSubDirectory$name(
  value: DirectoryOperation$,
): string;

export type DirectoryOperation$ = Set | Delete | Clear | CreateSubDirectory | DeleteSubDirectory;

export function DirectoryOperation$path(value: DirectoryOperation$): string;

export class ValueChanged extends _.CustomType {
  /** @deprecated */
  constructor(
    path: string,
    key: string,
    previous_value: $option.Option$<$json.Json$>,
    local: boolean
  );
  /** @deprecated */
  path: string;
  /** @deprecated */
  key: string;
  /** @deprecated */
  previous_value: $option.Option$<$json.Json$>;
  /** @deprecated */
  local: boolean;
}
export function DirectoryEvent$ValueChanged(
  path: string,
  key: string,
  previous_value: $option.Option$<$json.Json$>,
  local: boolean,
): DirectoryEvent$;
export function DirectoryEvent$isValueChanged(
  value: any,
): value is DirectoryEvent$;
export function DirectoryEvent$ValueChanged$0(value: DirectoryEvent$): string;
export function DirectoryEvent$ValueChanged$path(value: DirectoryEvent$): string;
export function DirectoryEvent$ValueChanged$1(
  value: DirectoryEvent$,
): string;
export function DirectoryEvent$ValueChanged$key(value: DirectoryEvent$): string;
export function DirectoryEvent$ValueChanged$2(value: DirectoryEvent$): $option.Option$<
  $json.Json$
>;
export function DirectoryEvent$ValueChanged$previous_value(value: DirectoryEvent$): $option.Option$<
  $json.Json$
>;
export function DirectoryEvent$ValueChanged$3(value: DirectoryEvent$): boolean;
export function DirectoryEvent$ValueChanged$local(value: DirectoryEvent$): boolean;

export class Cleared extends _.CustomType {
  /** @deprecated */
  constructor(path: string, local: boolean);
  /** @deprecated */
  path: string;
  /** @deprecated */
  local: boolean;
}
export function DirectoryEvent$Cleared(
  path: string,
  local: boolean,
): DirectoryEvent$;
export function DirectoryEvent$isCleared(value: any): value is DirectoryEvent$;
export function DirectoryEvent$Cleared$0(value: DirectoryEvent$): string;
export function DirectoryEvent$Cleared$path(value: DirectoryEvent$): string;
export function DirectoryEvent$Cleared$1(value: DirectoryEvent$): boolean;
export function DirectoryEvent$Cleared$local(value: DirectoryEvent$): boolean;

export class SubDirectoryCreated extends _.CustomType {
  /** @deprecated */
  constructor(path: string, local: boolean);
  /** @deprecated */
  path: string;
  /** @deprecated */
  local: boolean;
}
export function DirectoryEvent$SubDirectoryCreated(
  path: string,
  local: boolean,
): DirectoryEvent$;
export function DirectoryEvent$isSubDirectoryCreated(
  value: any,
): value is DirectoryEvent$;
export function DirectoryEvent$SubDirectoryCreated$0(value: DirectoryEvent$): string;
export function DirectoryEvent$SubDirectoryCreated$path(
  value: DirectoryEvent$,
): string;
export function DirectoryEvent$SubDirectoryCreated$1(value: DirectoryEvent$): boolean;
export function DirectoryEvent$SubDirectoryCreated$local(
  value: DirectoryEvent$,
): boolean;

export class SubDirectoryDeleted extends _.CustomType {
  /** @deprecated */
  constructor(path: string, local: boolean);
  /** @deprecated */
  path: string;
  /** @deprecated */
  local: boolean;
}
export function DirectoryEvent$SubDirectoryDeleted(
  path: string,
  local: boolean,
): DirectoryEvent$;
export function DirectoryEvent$isSubDirectoryDeleted(
  value: any,
): value is DirectoryEvent$;
export function DirectoryEvent$SubDirectoryDeleted$0(value: DirectoryEvent$): string;
export function DirectoryEvent$SubDirectoryDeleted$path(
  value: DirectoryEvent$,
): string;
export function DirectoryEvent$SubDirectoryDeleted$1(value: DirectoryEvent$): boolean;
export function DirectoryEvent$SubDirectoryDeleted$local(
  value: DirectoryEvent$,
): boolean;

export class Disposed extends _.CustomType {
  /** @deprecated */
  constructor(path: string);
  /** @deprecated */
  path: string;
}
export function DirectoryEvent$Disposed(path: string): DirectoryEvent$;
export function DirectoryEvent$isDisposed(value: any): value is DirectoryEvent$;
export function DirectoryEvent$Disposed$0(value: DirectoryEvent$): string;
export function DirectoryEvent$Disposed$path(value: DirectoryEvent$): string;

export class Undisposed extends _.CustomType {
  /** @deprecated */
  constructor(path: string);
  /** @deprecated */
  path: string;
}
export function DirectoryEvent$Undisposed(path: string): DirectoryEvent$;
export function DirectoryEvent$isUndisposed(
  value: any,
): value is DirectoryEvent$;
export function DirectoryEvent$Undisposed$0(value: DirectoryEvent$): string;
export function DirectoryEvent$Undisposed$path(value: DirectoryEvent$): string;

export type DirectoryEvent$ = ValueChanged | Cleared | SubDirectoryCreated | SubDirectoryDeleted | Disposed | Undisposed;

export function DirectoryEvent$path(value: DirectoryEvent$): string;

export class SequencedMeta extends _.CustomType {
  /** @deprecated */
  constructor(
    author: number,
    sequence_number: number,
    reference_sequence_number: number,
    client_sequence_number: number
  );
  /** @deprecated */
  author: number;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  client_sequence_number: number;
}
export function SequencedMeta$SequencedMeta(
  author: number,
  sequence_number: number,
  reference_sequence_number: number,
  client_sequence_number: number,
): SequencedMeta$;
export function SequencedMeta$isSequencedMeta(
  value: any,
): value is SequencedMeta$;
export function SequencedMeta$SequencedMeta$0(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$author(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$1(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$sequence_number(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$2(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$reference_sequence_number(value: SequencedMeta$): number;
export function SequencedMeta$SequencedMeta$3(
  value: SequencedMeta$,
): number;
export function SequencedMeta$SequencedMeta$client_sequence_number(value: SequencedMeta$): number;

export type SequencedMeta$ = SequencedMeta;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: DirectoryOperation$, detail: string);
  /** @deprecated */
  operation: DirectoryOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: DirectoryOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): DirectoryOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): DirectoryOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: DirectoryOperation$, detail: string);
  /** @deprecated */
  operation: DirectoryOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: DirectoryOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): DirectoryOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): DirectoryOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export class PathNotFound extends _.CustomType {
  /** @deprecated */
  constructor(path: string);
  /** @deprecated */
  path: string;
}
export function KernelError$PathNotFound(path: string): KernelError$;
export function KernelError$isPathNotFound(value: any): value is KernelError$;
export function KernelError$PathNotFound$0(value: KernelError$): string;
export function KernelError$PathNotFound$path(value: KernelError$): string;

export class InvalidName extends _.CustomType {
  /** @deprecated */
  constructor(name: string);
  /** @deprecated */
  name: string;
}
export function KernelError$InvalidName(name: string): KernelError$;
export function KernelError$isInvalidName(value: any): value is KernelError$;
export function KernelError$InvalidName$0(value: KernelError$): string;
export function KernelError$InvalidName$name(value: KernelError$): string;

export class InvariantViolation extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$InvariantViolation(detail: string): KernelError$;
export function KernelError$isInvariantViolation(
  value: any,
): value is KernelError$;
export function KernelError$InvariantViolation$0(value: KernelError$): string;
export function KernelError$InvariantViolation$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback | PathNotFound | InvalidName | InvariantViolation;

declare class SequencedSlot extends _.CustomType {}

declare class MarkerSlot extends _.CustomType {
  /** @deprecated */
  constructor(message_id: number);
  /** @deprecated */
  message_id: number;
}

type ChildSlot$ = SequencedSlot | MarkerSlot;

export class DirectorySummary extends _.CustomType {
  /** @deprecated */
  constructor(
    storage: _.List<[string, $json.Json$]>,
    create: CreateInfo$,
    creators: _.List<number>,
    detached_created: boolean,
    subdirectories: _.List<[string, DirectorySummary$]>
  );
  /** @deprecated */
  storage: _.List<[string, $json.Json$]>;
  /** @deprecated */
  create: CreateInfo$;
  /** @deprecated */
  creators: _.List<number>;
  /** @deprecated */
  detached_created: boolean;
  /** @deprecated */
  subdirectories: _.List<[string, DirectorySummary$]>;
}
export function DirectorySummary$DirectorySummary(
  storage: _.List<[string, $json.Json$]>,
  create: CreateInfo$,
  creators: _.List<number>,
  detached_created: boolean,
  subdirectories: _.List<[string, DirectorySummary$]>,
): DirectorySummary$;
export function DirectorySummary$isDirectorySummary(
  value: any,
): value is DirectorySummary$;
export function DirectorySummary$DirectorySummary$0(value: DirectorySummary$): _.List<
  [string, $json.Json$]
>;
export function DirectorySummary$DirectorySummary$storage(value: DirectorySummary$): _.List<
  [string, $json.Json$]
>;
export function DirectorySummary$DirectorySummary$1(value: DirectorySummary$): CreateInfo$;
export function DirectorySummary$DirectorySummary$create(
  value: DirectorySummary$,
): CreateInfo$;
export function DirectorySummary$DirectorySummary$2(value: DirectorySummary$): _.List<
  number
>;
export function DirectorySummary$DirectorySummary$creators(value: DirectorySummary$): _.List<
  number
>;
export function DirectorySummary$DirectorySummary$3(value: DirectorySummary$): boolean;
export function DirectorySummary$DirectorySummary$detached_created(
  value: DirectorySummary$,
): boolean;
export function DirectorySummary$DirectorySummary$4(value: DirectorySummary$): _.List<
  [string, DirectorySummary$]
>;
export function DirectorySummary$DirectorySummary$subdirectories(value: DirectorySummary$): _.List<
  [string, DirectorySummary$]
>;

export type DirectorySummary$ = DirectorySummary;

export function new$(): DirectoryState$;

export function segments(path: string): _.List<string>;

export function get_working_directory(state: DirectoryState$, path: string): _.Result<
  DirectoryNode$,
  undefined
>;

export function get_sequenced_directory(state: DirectoryState$, path: string): _.Result<
  DirectoryNode$,
  undefined
>;

export function get(state: DirectoryState$, path: string, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has(state: DirectoryState$, path: string, key: string): boolean;

export function entries(state: DirectoryState$, path: string): _.List<
  [string, $json.Json$]
>;

export function keys(state: DirectoryState$, path: string): _.List<string>;

export function size(state: DirectoryState$, path: string): number;

export function subdirectories(state: DirectoryState$, path: string): _.List<
  string
>;

export function has_subdirectory(
  state: DirectoryState$,
  path: string,
  name: string
): boolean;

export function count_subdirectory(state: DirectoryState$, path: string): number;

export function set(
  state: DirectoryState$,
  path: string,
  key: string,
  value: $json.Json$
): _.Result<
  [DirectoryState$, _.List<DirectoryEvent$>, DirectoryOperation$, number],
  KernelError$
>;

export function delete$(state: DirectoryState$, path: string, key: string): _.Result<
  [DirectoryState$, _.List<DirectoryEvent$>, DirectoryOperation$, number],
  KernelError$
>;

export function clear(state: DirectoryState$, path: string): _.Result<
  [DirectoryState$, _.List<DirectoryEvent$>, DirectoryOperation$, number],
  KernelError$
>;

export function create_subdirectory(
  state: DirectoryState$,
  path: string,
  name: string,
  self: number
): _.Result<
  [
    DirectoryState$,
    _.List<DirectoryEvent$>,
    $option.Option$<DirectoryOperation$>,
    number
  ],
  KernelError$
>;

export function delete_subdirectory(
  state: DirectoryState$,
  path: string,
  name: string
): _.Result<
  [
    DirectoryState$,
    _.List<DirectoryEvent$>,
    $option.Option$<DirectoryOperation$>,
    number
  ],
  KernelError$
>;

export function apply_remote(
  state: DirectoryState$,
  operation: DirectoryOperation$,
  meta: SequencedMeta$,
  self: number
): [DirectoryState$, _.List<DirectoryEvent$>];

export function ack_local(
  state: DirectoryState$,
  operation: DirectoryOperation$,
  meta: SequencedMeta$
): _.Result<DirectoryState$, KernelError$>;

export function last_pending_message_id(state: DirectoryState$): _.Result<
  number,
  undefined
>;

export function rollback(
  state: DirectoryState$,
  operation: DirectoryOperation$,
  message_id: number
): _.Result<[DirectoryState$, _.List<DirectoryEvent$>], KernelError$>;

export function resubmit(
  state: DirectoryState$,
  operation: DirectoryOperation$,
  message_id: number,
  self: number
): [DirectoryState$, $option.Option$<DirectoryOperation$>];

export function apply_stashed_operation(
  state: DirectoryState$,
  operation: DirectoryOperation$,
  self: number
): _.Result<
  [
    DirectoryState$,
    _.List<DirectoryEvent$>,
    $option.Option$<DirectoryOperation$>,
    number
  ],
  KernelError$
>;

export function summary_tree(state: DirectoryState$): DirectorySummary$;

export function from_summary(summary: DirectorySummary$): DirectoryState$;

export function check_invariants(state: DirectoryState$): _.Result<
  undefined,
  KernelError$
>;
