/// <reference types="./directory_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class DirectoryState extends $CustomType {
  constructor(root, next_message_id) {
    super();
    this.root = root;
    this.next_message_id = next_message_id;
  }
}
export const DirectoryState$DirectoryState = (root, next_message_id) =>
  new DirectoryState(root, next_message_id);
export const DirectoryState$isDirectoryState = (value) =>
  value instanceof DirectoryState;
export const DirectoryState$DirectoryState$root = (value) => value.root;
export const DirectoryState$DirectoryState$0 = (value) => value.root;
export const DirectoryState$DirectoryState$next_message_id = (value) =>
  value.next_message_id;
export const DirectoryState$DirectoryState$1 = (value) => value.next_message_id;

export class DirectoryNode extends $CustomType {
  constructor(path, create, birth, creators, detached_created, disposed, storage, subdirectories, subdirectory_order, pending_subdirectories) {
    super();
    this.path = path;
    this.create = create;
    this.birth = birth;
    this.creators = creators;
    this.detached_created = detached_created;
    this.disposed = disposed;
    this.storage = storage;
    this.subdirectories = subdirectories;
    this.subdirectory_order = subdirectory_order;
    this.pending_subdirectories = pending_subdirectories;
  }
}
export const DirectoryNode$DirectoryNode = (path, create, birth, creators, detached_created, disposed, storage, subdirectories, subdirectory_order, pending_subdirectories) =>
  new DirectoryNode(path,
  create,
  birth,
  creators,
  detached_created,
  disposed,
  storage,
  subdirectories,
  subdirectory_order,
  pending_subdirectories);
export const DirectoryNode$isDirectoryNode = (value) =>
  value instanceof DirectoryNode;
export const DirectoryNode$DirectoryNode$path = (value) => value.path;
export const DirectoryNode$DirectoryNode$0 = (value) => value.path;
export const DirectoryNode$DirectoryNode$create = (value) => value.create;
export const DirectoryNode$DirectoryNode$1 = (value) => value.create;
export const DirectoryNode$DirectoryNode$birth = (value) => value.birth;
export const DirectoryNode$DirectoryNode$2 = (value) => value.birth;
export const DirectoryNode$DirectoryNode$creators = (value) => value.creators;
export const DirectoryNode$DirectoryNode$3 = (value) => value.creators;
export const DirectoryNode$DirectoryNode$detached_created = (value) =>
  value.detached_created;
export const DirectoryNode$DirectoryNode$4 = (value) => value.detached_created;
export const DirectoryNode$DirectoryNode$disposed = (value) => value.disposed;
export const DirectoryNode$DirectoryNode$5 = (value) => value.disposed;
export const DirectoryNode$DirectoryNode$storage = (value) => value.storage;
export const DirectoryNode$DirectoryNode$6 = (value) => value.storage;
export const DirectoryNode$DirectoryNode$subdirectories = (value) =>
  value.subdirectories;
export const DirectoryNode$DirectoryNode$7 = (value) => value.subdirectories;
export const DirectoryNode$DirectoryNode$subdirectory_order = (value) =>
  value.subdirectory_order;
export const DirectoryNode$DirectoryNode$8 = (value) =>
  value.subdirectory_order;
export const DirectoryNode$DirectoryNode$pending_subdirectories = (value) =>
  value.pending_subdirectories;
export const DirectoryNode$DirectoryNode$9 = (value) =>
  value.pending_subdirectories;

export class CreateInfo extends $CustomType {
  constructor(sequence_number, client_sequence_number) {
    super();
    this.sequence_number = sequence_number;
    this.client_sequence_number = client_sequence_number;
  }
}
export const CreateInfo$CreateInfo = (sequence_number, client_sequence_number) =>
  new CreateInfo(sequence_number, client_sequence_number);
export const CreateInfo$isCreateInfo = (value) => value instanceof CreateInfo;
export const CreateInfo$CreateInfo$sequence_number = (value) =>
  value.sequence_number;
export const CreateInfo$CreateInfo$0 = (value) => value.sequence_number;
export const CreateInfo$CreateInfo$client_sequence_number = (value) =>
  value.client_sequence_number;
export const CreateInfo$CreateInfo$1 = (value) => value.client_sequence_number;

export class StorageState extends $CustomType {
  constructor(sequenced, insertion_order, pending) {
    super();
    this.sequenced = sequenced;
    this.insertion_order = insertion_order;
    this.pending = pending;
  }
}
export const StorageState$StorageState = (sequenced, insertion_order, pending) =>
  new StorageState(sequenced, insertion_order, pending);
export const StorageState$isStorageState = (value) =>
  value instanceof StorageState;
export const StorageState$StorageState$sequenced = (value) => value.sequenced;
export const StorageState$StorageState$0 = (value) => value.sequenced;
export const StorageState$StorageState$insertion_order = (value) =>
  value.insertion_order;
export const StorageState$StorageState$1 = (value) => value.insertion_order;
export const StorageState$StorageState$pending = (value) => value.pending;
export const StorageState$StorageState$2 = (value) => value.pending;

/**
 * One or more consecutive local sets to one key, oldest first. Each set
 * carries the `message_id` of its submission. A delete or a clear ends the
 * lifetime. A later set starts a new lifetime.
 */
export class PendingLifetime extends $CustomType {
  constructor(key, sets, message_ids) {
    super();
    this.key = key;
    this.sets = sets;
    this.message_ids = message_ids;
  }
}
export const PendingStorage$PendingLifetime = (key, sets, message_ids) =>
  new PendingLifetime(key, sets, message_ids);
export const PendingStorage$isPendingLifetime = (value) =>
  value instanceof PendingLifetime;
export const PendingStorage$PendingLifetime$key = (value) => value.key;
export const PendingStorage$PendingLifetime$0 = (value) => value.key;
export const PendingStorage$PendingLifetime$sets = (value) => value.sets;
export const PendingStorage$PendingLifetime$1 = (value) => value.sets;
export const PendingStorage$PendingLifetime$message_ids = (value) =>
  value.message_ids;
export const PendingStorage$PendingLifetime$2 = (value) => value.message_ids;

export class PendingDelete extends $CustomType {
  constructor(key, message_id) {
    super();
    this.key = key;
    this.message_id = message_id;
  }
}
export const PendingStorage$PendingDelete = (key, message_id) =>
  new PendingDelete(key, message_id);
export const PendingStorage$isPendingDelete = (value) =>
  value instanceof PendingDelete;
export const PendingStorage$PendingDelete$key = (value) => value.key;
export const PendingStorage$PendingDelete$0 = (value) => value.key;
export const PendingStorage$PendingDelete$message_id = (value) =>
  value.message_id;
export const PendingStorage$PendingDelete$1 = (value) => value.message_id;

export class PendingClear extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const PendingStorage$PendingClear = (message_id) =>
  new PendingClear(message_id);
export const PendingStorage$isPendingClear = (value) =>
  value instanceof PendingClear;
export const PendingStorage$PendingClear$message_id = (value) =>
  value.message_id;
export const PendingStorage$PendingClear$0 = (value) => value.message_id;

/**
 * A local create of `name`. `node` is the optimistic instance of this
 * create, and it is the one copy of the storage and the children while
 * `folded` is `False`.
 *
 * A concurrent remote create of the same name, or the ack of this create,
 * moves the instance into the sequenced children. `folded` then becomes
 * `True`, and `subdirectories[name]` becomes the canonical copy. `node` is
 * then a fallback only. The kernel uses it to insert the instance again if a
 * later delete removes it before this create receives its ack.
 *
 * The instance stays in exactly one canonical place: the marker while the
 * create is not folded, and `subdirectories` after that. That rule prevents
 * a drift between two copies of the storage. It follows the model of
 * FluidFramework, which keeps one `SubDirectory` object for each instance,
 * and where the pending-create entry and the sequenced map hold the *same*
 * object.
 */
export class PendingCreate extends $CustomType {
  constructor(name, node, message_id, folded) {
    super();
    this.name = name;
    this.node = node;
    this.message_id = message_id;
    this.folded = folded;
  }
}
export const PendingSubdirectory$PendingCreate = (name, node, message_id, folded) =>
  new PendingCreate(name, node, message_id, folded);
export const PendingSubdirectory$isPendingCreate = (value) =>
  value instanceof PendingCreate;
export const PendingSubdirectory$PendingCreate$name = (value) => value.name;
export const PendingSubdirectory$PendingCreate$0 = (value) => value.name;
export const PendingSubdirectory$PendingCreate$node = (value) => value.node;
export const PendingSubdirectory$PendingCreate$1 = (value) => value.node;
export const PendingSubdirectory$PendingCreate$message_id = (value) =>
  value.message_id;
export const PendingSubdirectory$PendingCreate$2 = (value) => value.message_id;
export const PendingSubdirectory$PendingCreate$folded = (value) => value.folded;
export const PendingSubdirectory$PendingCreate$3 = (value) => value.folded;

/**
 * A local delete of `name`. The kernel keeps the sequenced child and hides
 * it in the optimistic view only. The pending storage on that subtree thus
 * stays for its acks, and a rollback shows the tree again. This is D13.
 */
export class PendingRemove extends $CustomType {
  constructor(name, message_id) {
    super();
    this.name = name;
    this.message_id = message_id;
  }
}
export const PendingSubdirectory$PendingRemove = (name, message_id) =>
  new PendingRemove(name, message_id);
export const PendingSubdirectory$isPendingRemove = (value) =>
  value instanceof PendingRemove;
export const PendingSubdirectory$PendingRemove$name = (value) => value.name;
export const PendingSubdirectory$PendingRemove$0 = (value) => value.name;
export const PendingSubdirectory$PendingRemove$message_id = (value) =>
  value.message_id;
export const PendingSubdirectory$PendingRemove$1 = (value) => value.message_id;

export const PendingSubdirectory$name = (value) => value.name;

export class Set extends $CustomType {
  constructor(path, key, value) {
    super();
    this.path = path;
    this.key = key;
    this.value = value;
  }
}
export const DirectoryOperation$Set = (path, key, value) =>
  new Set(path, key, value);
export const DirectoryOperation$isSet = (value) => value instanceof Set;
export const DirectoryOperation$Set$path = (value) => value.path;
export const DirectoryOperation$Set$0 = (value) => value.path;
export const DirectoryOperation$Set$key = (value) => value.key;
export const DirectoryOperation$Set$1 = (value) => value.key;
export const DirectoryOperation$Set$value = (value) => value.value;
export const DirectoryOperation$Set$2 = (value) => value.value;

export class Delete extends $CustomType {
  constructor(path, key) {
    super();
    this.path = path;
    this.key = key;
  }
}
export const DirectoryOperation$Delete = (path, key) => new Delete(path, key);
export const DirectoryOperation$isDelete = (value) => value instanceof Delete;
export const DirectoryOperation$Delete$path = (value) => value.path;
export const DirectoryOperation$Delete$0 = (value) => value.path;
export const DirectoryOperation$Delete$key = (value) => value.key;
export const DirectoryOperation$Delete$1 = (value) => value.key;

export class Clear extends $CustomType {
  constructor(path) {
    super();
    this.path = path;
  }
}
export const DirectoryOperation$Clear = (path) => new Clear(path);
export const DirectoryOperation$isClear = (value) => value instanceof Clear;
export const DirectoryOperation$Clear$path = (value) => value.path;
export const DirectoryOperation$Clear$0 = (value) => value.path;

export class CreateSubDirectory extends $CustomType {
  constructor(path, name) {
    super();
    this.path = path;
    this.name = name;
  }
}
export const DirectoryOperation$CreateSubDirectory = (path, name) =>
  new CreateSubDirectory(path, name);
export const DirectoryOperation$isCreateSubDirectory = (value) =>
  value instanceof CreateSubDirectory;
export const DirectoryOperation$CreateSubDirectory$path = (value) => value.path;
export const DirectoryOperation$CreateSubDirectory$0 = (value) => value.path;
export const DirectoryOperation$CreateSubDirectory$name = (value) => value.name;
export const DirectoryOperation$CreateSubDirectory$1 = (value) => value.name;

export class DeleteSubDirectory extends $CustomType {
  constructor(path, name) {
    super();
    this.path = path;
    this.name = name;
  }
}
export const DirectoryOperation$DeleteSubDirectory = (path, name) =>
  new DeleteSubDirectory(path, name);
export const DirectoryOperation$isDeleteSubDirectory = (value) =>
  value instanceof DeleteSubDirectory;
export const DirectoryOperation$DeleteSubDirectory$path = (value) => value.path;
export const DirectoryOperation$DeleteSubDirectory$0 = (value) => value.path;
export const DirectoryOperation$DeleteSubDirectory$name = (value) => value.name;
export const DirectoryOperation$DeleteSubDirectory$1 = (value) => value.name;

export const DirectoryOperation$path = (value) => value.path;

export class ValueChanged extends $CustomType {
  constructor(path, key, previous_value, local) {
    super();
    this.path = path;
    this.key = key;
    this.previous_value = previous_value;
    this.local = local;
  }
}
export const DirectoryEvent$ValueChanged = (path, key, previous_value, local) =>
  new ValueChanged(path, key, previous_value, local);
export const DirectoryEvent$isValueChanged = (value) =>
  value instanceof ValueChanged;
export const DirectoryEvent$ValueChanged$path = (value) => value.path;
export const DirectoryEvent$ValueChanged$0 = (value) => value.path;
export const DirectoryEvent$ValueChanged$key = (value) => value.key;
export const DirectoryEvent$ValueChanged$1 = (value) => value.key;
export const DirectoryEvent$ValueChanged$previous_value = (value) =>
  value.previous_value;
export const DirectoryEvent$ValueChanged$2 = (value) => value.previous_value;
export const DirectoryEvent$ValueChanged$local = (value) => value.local;
export const DirectoryEvent$ValueChanged$3 = (value) => value.local;

export class Cleared extends $CustomType {
  constructor(path, local) {
    super();
    this.path = path;
    this.local = local;
  }
}
export const DirectoryEvent$Cleared = (path, local) => new Cleared(path, local);
export const DirectoryEvent$isCleared = (value) => value instanceof Cleared;
export const DirectoryEvent$Cleared$path = (value) => value.path;
export const DirectoryEvent$Cleared$0 = (value) => value.path;
export const DirectoryEvent$Cleared$local = (value) => value.local;
export const DirectoryEvent$Cleared$1 = (value) => value.local;

export class SubDirectoryCreated extends $CustomType {
  constructor(path, local) {
    super();
    this.path = path;
    this.local = local;
  }
}
export const DirectoryEvent$SubDirectoryCreated = (path, local) =>
  new SubDirectoryCreated(path, local);
export const DirectoryEvent$isSubDirectoryCreated = (value) =>
  value instanceof SubDirectoryCreated;
export const DirectoryEvent$SubDirectoryCreated$path = (value) => value.path;
export const DirectoryEvent$SubDirectoryCreated$0 = (value) => value.path;
export const DirectoryEvent$SubDirectoryCreated$local = (value) => value.local;
export const DirectoryEvent$SubDirectoryCreated$1 = (value) => value.local;

export class SubDirectoryDeleted extends $CustomType {
  constructor(path, local) {
    super();
    this.path = path;
    this.local = local;
  }
}
export const DirectoryEvent$SubDirectoryDeleted = (path, local) =>
  new SubDirectoryDeleted(path, local);
export const DirectoryEvent$isSubDirectoryDeleted = (value) =>
  value instanceof SubDirectoryDeleted;
export const DirectoryEvent$SubDirectoryDeleted$path = (value) => value.path;
export const DirectoryEvent$SubDirectoryDeleted$0 = (value) => value.path;
export const DirectoryEvent$SubDirectoryDeleted$local = (value) => value.local;
export const DirectoryEvent$SubDirectoryDeleted$1 = (value) => value.local;

export class Disposed extends $CustomType {
  constructor(path) {
    super();
    this.path = path;
  }
}
export const DirectoryEvent$Disposed = (path) => new Disposed(path);
export const DirectoryEvent$isDisposed = (value) => value instanceof Disposed;
export const DirectoryEvent$Disposed$path = (value) => value.path;
export const DirectoryEvent$Disposed$0 = (value) => value.path;

export class Undisposed extends $CustomType {
  constructor(path) {
    super();
    this.path = path;
  }
}
export const DirectoryEvent$Undisposed = (path) => new Undisposed(path);
export const DirectoryEvent$isUndisposed = (value) =>
  value instanceof Undisposed;
export const DirectoryEvent$Undisposed$path = (value) => value.path;
export const DirectoryEvent$Undisposed$0 = (value) => value.path;

export const DirectoryEvent$path = (value) => value.path;

export class SequencedMeta extends $CustomType {
  constructor(author, sequence_number, reference_sequence_number, client_sequence_number) {
    super();
    this.author = author;
    this.sequence_number = sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.client_sequence_number = client_sequence_number;
  }
}
export const SequencedMeta$SequencedMeta = (author, sequence_number, reference_sequence_number, client_sequence_number) =>
  new SequencedMeta(author,
  sequence_number,
  reference_sequence_number,
  client_sequence_number);
export const SequencedMeta$isSequencedMeta = (value) =>
  value instanceof SequencedMeta;
export const SequencedMeta$SequencedMeta$author = (value) => value.author;
export const SequencedMeta$SequencedMeta$0 = (value) => value.author;
export const SequencedMeta$SequencedMeta$sequence_number = (value) =>
  value.sequence_number;
export const SequencedMeta$SequencedMeta$1 = (value) => value.sequence_number;
export const SequencedMeta$SequencedMeta$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SequencedMeta$SequencedMeta$2 = (value) =>
  value.reference_sequence_number;
export const SequencedMeta$SequencedMeta$client_sequence_number = (value) =>
  value.client_sequence_number;
export const SequencedMeta$SequencedMeta$3 = (value) =>
  value.client_sequence_number;

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

export class PathNotFound extends $CustomType {
  constructor(path) {
    super();
    this.path = path;
  }
}
export const KernelError$PathNotFound = (path) => new PathNotFound(path);
export const KernelError$isPathNotFound = (value) =>
  value instanceof PathNotFound;
export const KernelError$PathNotFound$path = (value) => value.path;
export const KernelError$PathNotFound$0 = (value) => value.path;

export class InvalidName extends $CustomType {
  constructor(name) {
    super();
    this.name = name;
  }
}
export const KernelError$InvalidName = (name) => new InvalidName(name);
export const KernelError$isInvalidName = (value) =>
  value instanceof InvalidName;
export const KernelError$InvalidName$name = (value) => value.name;
export const KernelError$InvalidName$0 = (value) => value.name;

export class InvariantViolation extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$InvariantViolation = (detail) =>
  new InvariantViolation(detail);
export const KernelError$isInvariantViolation = (value) =>
  value instanceof InvariantViolation;
export const KernelError$InvariantViolation$detail = (value) => value.detail;
export const KernelError$InvariantViolation$0 = (value) => value.detail;

class SequencedSlot extends $CustomType {}
const ChildSlot$SequencedSlot$const = new SequencedSlot();

class MarkerSlot extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}

export class DirectorySummary extends $CustomType {
  constructor(storage, create, creators, detached_created, subdirectories) {
    super();
    this.storage = storage;
    this.create = create;
    this.creators = creators;
    this.detached_created = detached_created;
    this.subdirectories = subdirectories;
  }
}
export const DirectorySummary$DirectorySummary = (storage, create, creators, detached_created, subdirectories) =>
  new DirectorySummary(storage,
  create,
  creators,
  detached_created,
  subdirectories);
export const DirectorySummary$isDirectorySummary = (value) =>
  value instanceof DirectorySummary;
export const DirectorySummary$DirectorySummary$storage = (value) =>
  value.storage;
export const DirectorySummary$DirectorySummary$0 = (value) => value.storage;
export const DirectorySummary$DirectorySummary$create = (value) => value.create;
export const DirectorySummary$DirectorySummary$1 = (value) => value.create;
export const DirectorySummary$DirectorySummary$creators = (value) =>
  value.creators;
export const DirectorySummary$DirectorySummary$2 = (value) => value.creators;
export const DirectorySummary$DirectorySummary$detached_created = (value) =>
  value.detached_created;
export const DirectorySummary$DirectorySummary$3 = (value) =>
  value.detached_created;
export const DirectorySummary$DirectorySummary$subdirectories = (value) =>
  value.subdirectories;
export const DirectorySummary$DirectorySummary$4 = (value) =>
  value.subdirectories;

function new_node(path, create, creators, detached_created) {
  return new DirectoryNode(
    path,
    create,
    create,
    creators,
    detached_created,
    false,
    new StorageState($dict.new$(), $List$Empty$const, $List$Empty$const),
    $dict.new$(),
    $List$Empty$const,
    $List$Empty$const,
  );
}

export function new$() {
  return new DirectoryState(
    new_node("/", new CreateInfo(0, 0), $List$Empty$const, true),
    0,
  );
}

/**
 * Split an absolute path into its segments, and remove the empty ones. `"/"`
 * gives `[]`.
 */
export function segments(path) {
  let _pipe = $string.split(path, "/");
  return $list.filter(_pipe, (s) => { return s !== ""; });
}

function join(path, name) {
  if (path === "/") {
    return "/" + name;
  } else {
    return (path + "/") + name;
  }
}

function pending_subdirectory_name(entry) {
  if (entry instanceof PendingCreate) {
    let name = entry.name;
    return name;
  } else {
    let name = entry.name;
    return name;
  }
}

/**
 * The most recent pending subdirectory entry for `name`, if one exists.
 * 
 * @ignore
 */
function latest_pending_subdirectory(node, name) {
  let _pipe = $list.reverse(node.pending_subdirectories);
  return $list.find(
    _pipe,
    (entry) => { return pending_subdirectory_name(entry) === name; },
  );
}

/**
 * The optimistic child with this name. The function puts the pending creates
 * and the pending deletes over the sequenced children. It treats a disposed
 * node as absent, unless `include_disposed` is true.
 * 
 * @ignore
 */
function optimistic_child(node, name, include_disposed) {
  let _block;
  let $ = latest_pending_subdirectory(node, name);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingCreate) {
      let $2 = $1.folded;
      if ($2) {
        let pending_child = $1.node;
        let $3 = $dict.get(node.subdirectories, name);
        if ($3 instanceof Ok) {
          let live = $3[0];
          let $4 = isEqual(live.birth, pending_child.birth);
          if ($4) {
            _block = new Ok(live);
          } else {
            _block = new Ok(pending_child);
          }
        } else {
          _block = new Ok(pending_child);
        }
      } else {
        let pending_child = $1.node;
        _block = new Ok(pending_child);
      }
    } else {
      _block = new Error(undefined);
    }
  } else {
    _block = $dict.get(node.subdirectories, name);
  }
  let child = _block;
  if (child instanceof Ok) {
    let found = child[0];
    if (found.disposed && !include_disposed) {
      return new Error(undefined);
    } else {
      return child;
    }
  } else {
    return child;
  }
}

function sequenced_child(node, name) {
  return $dict.get(node.subdirectories, name);
}

function put_sequenced_child(node, name, child) {
  let _block;
  let $ = $dict.has_key(node.subdirectories, name);
  if ($) {
    _block = node.subdirectory_order;
  } else {
    _block = $list.append(node.subdirectory_order, toList([name]));
  }
  let order = _block;
  return new DirectoryNode(
    node.path,
    node.create,
    node.birth,
    node.creators,
    node.detached_created,
    node.disposed,
    node.storage,
    $dict.insert(node.subdirectories, name, child),
    order,
    node.pending_subdirectories,
  );
}

function do_mark_first_create_folded(reversed, name, folded_node) {
  if (reversed instanceof $Empty) {
    return reversed;
  } else {
    let $ = reversed.head;
    if ($ instanceof PendingCreate) {
      let n = $.name;
      if (n === name) {
        let rest = reversed.tail;
        let mid = $.message_id;
        return listPrepend(new PendingCreate(n, folded_node, mid, true), rest);
      } else {
        let entry = $;
        if (entry.name === name) {
          return reversed;
        } else {
          let entry = $;
          let rest = reversed.tail;
          return listPrepend(
            entry,
            do_mark_first_create_folded(rest, name, folded_node),
          );
        }
      }
    } else {
      let entry = $;
      if (entry.name === name) {
        return reversed;
      } else {
        let entry = $;
        let rest = reversed.tail;
        return listPrepend(
          entry,
          do_mark_first_create_folded(rest, name, folded_node),
        );
      }
    }
  }
}

/**
 * Mark the most recent pending create for `name` as folded. A concurrent
 * remote create moved its instance into the sequenced children, which are now
 * the canonical copy. The kernel keeps the `node` field of the marker, as a
 * fallback for a later insert.
 * 
 * @ignore
 */
function mark_latest_pending_create_folded(pending, name, folded_node) {
  let _pipe = $list.reverse(pending);
  let _pipe$1 = do_mark_first_create_folded(_pipe, name, folded_node);
  return $list.reverse(_pipe$1);
}

function do_replace_first_create(reversed, name, child) {
  if (reversed instanceof $Empty) {
    return reversed;
  } else {
    let $ = reversed.head;
    if ($ instanceof PendingCreate) {
      let n = $.name;
      if (n === name) {
        let rest = reversed.tail;
        let mid = $.message_id;
        let folded = $.folded;
        return listPrepend(new PendingCreate(n, child, mid, folded), rest);
      } else {
        let entry = $;
        let rest = reversed.tail;
        return listPrepend(entry, do_replace_first_create(rest, name, child));
      }
    } else {
      let entry = $;
      let rest = reversed.tail;
      return listPrepend(entry, do_replace_first_create(rest, name, child));
    }
  }
}

function replace_latest_pending_create(pending, name, child) {
  let _pipe = $list.reverse(pending);
  let _pipe$1 = do_replace_first_create(_pipe, name, child);
  return $list.reverse(_pipe$1);
}

/**
 * Write `child` back to the canonical position of the live instance of `name`.
 * That position is the most recent pending create marker that is not folded
 * yet, or, if there is none, the sequenced children.
 * 
 * @ignore
 */
function put_optimistic_child(node, name, child) {
  let $ = latest_pending_subdirectory(node, name);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingCreate) {
      let $2 = $1.folded;
      if ($2) {
        let _block;
        let $3 = $dict.get(node.subdirectories, name);
        if ($3 instanceof Ok) {
          let live = $3[0];
          let $4 = isEqual(live.birth, child.birth);
          if ($4) {
            _block = put_sequenced_child(node, name, child);
          } else {
            _block = node;
          }
        } else {
          _block = node;
        }
        let node$1 = _block;
        return new DirectoryNode(
          node$1.path,
          node$1.create,
          node$1.birth,
          node$1.creators,
          node$1.detached_created,
          node$1.disposed,
          node$1.storage,
          node$1.subdirectories,
          node$1.subdirectory_order,
          mark_latest_pending_create_folded(
            node$1.pending_subdirectories,
            name,
            child,
          ),
        );
      } else {
        return new DirectoryNode(
          node.path,
          node.create,
          node.birth,
          node.creators,
          node.detached_created,
          node.disposed,
          node.storage,
          node.subdirectories,
          node.subdirectory_order,
          replace_latest_pending_create(
            node.pending_subdirectories,
            name,
            child,
          ),
        );
      }
    } else {
      return put_sequenced_child(node, name, child);
    }
  } else {
    return put_sequenced_child(node, name, child);
  }
}

function remove_sequenced_child(node, name) {
  return new DirectoryNode(
    node.path,
    node.create,
    node.birth,
    node.creators,
    node.detached_created,
    node.disposed,
    node.storage,
    $dict.delete$(node.subdirectories, name),
    $list.filter(node.subdirectory_order, (n) => { return n !== name; }),
    node.pending_subdirectories,
  );
}

function optimistic_child_reachable(node, name) {
  return optimistic_child(node, name, false);
}

function do_get(loop$node, loop$path_segments, loop$child_of) {
  while (true) {
    let node = loop$node;
    let path_segments = loop$path_segments;
    let child_of = loop$child_of;
    if (path_segments instanceof $Empty) {
      return new Ok(node);
    } else {
      let name = path_segments.head;
      let rest = path_segments.tail;
      let $ = child_of(node, name);
      if ($ instanceof Ok) {
        let child = $[0];
        loop$node = child;
        loop$path_segments = rest;
        loop$child_of = child_of;
      } else {
        return $;
      }
    }
  }
}

/**
 * Find the optimistic node at `path`, from the root.
 */
export function get_working_directory(state, path) {
  return do_get(state.root, segments(path), optimistic_child_reachable);
}

/**
 * Find the node at `path` in the sequenced data only.
 */
export function get_sequenced_directory(state, path) {
  return do_get(state.root, segments(path), sequenced_child);
}

/**
 * Update the optimistic node at `segs`, and return a result value with the
 * new state.
 * 
 * @ignore
 */
function update_optimistic(node, path_segments, f) {
  if (path_segments instanceof $Empty) {
    return new Ok(f(node));
  } else {
    let name = path_segments.head;
    let rest = path_segments.tail;
    let $ = optimistic_child(node, name, false);
    if ($ instanceof Ok) {
      let child = $[0];
      let $1 = update_optimistic(child, rest, f);
      if ($1 instanceof Ok) {
        let new_child = $1[0][0];
        let updated = $1[0][1];
        return new Ok([put_optimistic_child(node, name, new_child), updated]);
      } else {
        return $1;
      }
    } else {
      return $;
    }
  }
}

/**
 * Update the sequenced node at `segs`, and return a result value with the new
 * state.
 * 
 * @ignore
 */
function update_sequenced(node, path_segments, f) {
  if (path_segments instanceof $Empty) {
    return new Ok(f(node));
  } else {
    let name = path_segments.head;
    let rest = path_segments.tail;
    let $ = sequenced_child(node, name);
    if ($ instanceof Ok) {
      let child = $[0];
      let $1 = update_sequenced(child, rest, f);
      if ($1 instanceof Ok) {
        let new_child = $1[0][0];
        let updated = $1[0][1];
        return new Ok([put_sequenced_child(node, name, new_child), updated]);
      } else {
        return $1;
      }
    } else {
      return $;
    }
  }
}

function storage_matches_key(entry, key) {
  if (entry instanceof PendingLifetime) {
    let k = entry.key;
    return k === key;
  } else if (entry instanceof PendingDelete) {
    let k = entry.key;
    return k === key;
  } else {
    return true;
  }
}

function latest_storage_pending_for(pending, key) {
  let _pipe = $list.reverse(pending);
  return $list.find(
    _pipe,
    (entry) => { return storage_matches_key(entry, key); },
  );
}

function storage_get(storage, key) {
  let $ = latest_storage_pending_for(storage.pending, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingLifetime) {
      let sets = $1.sets;
      return $list.last(sets);
    } else if ($1 instanceof PendingDelete) {
      return new Error(undefined);
    } else {
      return new Error(undefined);
    }
  } else {
    return $dict.get(storage.sequenced, key);
  }
}

function last_storage_delete_or_clear_index(indexed, key) {
  return $list.fold(
    indexed,
    -1,
    (acc, pair) => {
      let $ = pair[1];
      if ($ instanceof PendingLifetime) {
        return acc;
      } else if ($ instanceof PendingDelete) {
        let k = $.key;
        if (k === key) {
          return pair[0];
        } else {
          return acc;
        }
      } else {
        return pair[0];
      }
    },
  );
}

function has_storage_delete_or_clear(pending, key) {
  return $list.any(
    pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        return false;
      } else if (entry instanceof PendingDelete) {
        let k = entry.key;
        return k === key;
      } else {
        return true;
      }
    },
  );
}

function storage_entries(storage) {
  let sequenced_phase = $list.filter_map(
    storage.insertion_order,
    (key) => {
      let $ = has_storage_delete_or_clear(storage.pending, key);
      if ($) {
        return new Error(undefined);
      } else {
        let _pipe = storage_get(storage, key);
        return $result.map(_pipe, (value) => { return [key, value]; });
      }
    },
  );
  let indexed = $list.index_map(
    storage.pending,
    (entry, i) => { return [i, entry]; },
  );
  let pending_phase = $list.filter_map(
    indexed,
    (pair) => {
      let index = pair[0];
      let entry = pair[1];
      if (entry instanceof PendingLifetime) {
        let key = entry.key;
        let sets = entry.sets;
        let last_dc = last_storage_delete_or_clear_index(indexed, key);
        let survives = index > last_dc;
        let already_iterated = $dict.has_key(storage.sequenced, key) && (last_dc === -1);
        let $ = survives && !already_iterated;
        if ($) {
          let _pipe = $list.last(sets);
          return $result.map(_pipe, (value) => { return [key, value]; });
        } else {
          return new Error(undefined);
        }
      } else if (entry instanceof PendingDelete) {
        return new Error(undefined);
      } else {
        return new Error(undefined);
      }
    },
  );
  return $list.append(sequenced_phase, pending_phase);
}

export function get(state, path, key) {
  let $ = get_working_directory(state, path);
  if ($ instanceof Ok) {
    let node = $[0];
    return storage_get(node.storage, key);
  } else {
    return $;
  }
}

export function has(state, path, key) {
  return $result.is_ok(get(state, path, key));
}

export function entries(state, path) {
  let $ = get_working_directory(state, path);
  if ($ instanceof Ok) {
    let node = $[0];
    return storage_entries(node.storage);
  } else {
    return $List$Empty$const;
  }
}

export function keys(state, path) {
  let _pipe = entries(state, path);
  return $list.map(_pipe, (e) => { return e[0]; });
}

export function size(state, path) {
  return $list.length(entries(state, path));
}

function compare_create_info(a, b) {
  let a_acknowledged = a.sequence_number >= 0;
  let b_acknowledged = b.sequence_number >= 0;
  if (a_acknowledged) {
    if (b_acknowledged) {
      let $ = a.sequence_number === b.sequence_number;
      if ($) {
        return $int.compare(a.client_sequence_number, b.client_sequence_number);
      } else {
        return $int.compare(a.sequence_number, b.sequence_number);
      }
    } else {
      return $order.Order$Lt$const;
    }
  } else if (b_acknowledged) {
    return $order.Order$Gt$const;
  } else {
    let $ = a.sequence_number === b.sequence_number;
    if ($) {
      return $int.compare(a.client_sequence_number, b.client_sequence_number);
    } else {
      return $int.compare(a.sequence_number, b.sequence_number);
    }
  }
}

function optimistic_subdirectory_names(node) {
  let sequenced_names = $list.filter(
    node.subdirectory_order,
    (name) => { return $result.is_ok(optimistic_child(node, name, false)); },
  );
  let _block;
  let _pipe = $list.filter_map(
    node.pending_subdirectories,
    (entry) => {
      let name = pending_subdirectory_name(entry);
      let $ = $dict.has_key(node.subdirectories, name);
      if ($) {
        return new Error(undefined);
      } else {
        let $1 = optimistic_child(node, name, false);
        if ($1 instanceof Ok) {
          return new Ok(name);
        } else {
          return $1;
        }
      }
    },
  );
  _block = $list.unique(_pipe);
  let pending_names = _block;
  let all = $list.append(sequenced_names, pending_names);
  let _pipe$1 = all;
  let _pipe$2 = $list.filter_map(
    _pipe$1,
    (name) => {
      let $ = optimistic_child(node, name, false);
      if ($ instanceof Ok) {
        let child = $[0];
        return new Ok([name, child.create]);
      } else {
        return $;
      }
    },
  );
  let _pipe$3 = $list.sort(
    _pipe$2,
    (a, b) => { return compare_create_info(a[1], b[1]); },
  );
  return $list.map(_pipe$3, (entry) => { return entry[0]; });
}

/**
 * The names of the child directories that are visible optimistically at
 * `path`. The function orders them with `seqDataComparator`. An acked
 * directory and a detached directory come before a local one with no ack, and
 * a lower `sequence_number` or `client_sequence_number` value comes first.
 */
export function subdirectories(state, path) {
  let $ = get_working_directory(state, path);
  if ($ instanceof Ok) {
    let node = $[0];
    return optimistic_subdirectory_names(node);
  } else {
    return $List$Empty$const;
  }
}

export function has_subdirectory(state, path, name) {
  let $ = get_working_directory(state, path);
  if ($ instanceof Ok) {
    let node = $[0];
    return $result.is_ok(optimistic_child(node, name, false));
  } else {
    return false;
  }
}

export function count_subdirectory(state, path) {
  return $list.length(subdirectories(state, path));
}

function do_append_to_first_lifetime(reversed, key, value, message_id) {
  if (reversed instanceof $Empty) {
    return reversed;
  } else {
    let $ = reversed.head;
    if ($ instanceof PendingLifetime) {
      let k = $.key;
      if (k === key) {
        let rest = reversed.tail;
        let sets = $.sets;
        let ids = $.message_ids;
        return listPrepend(
          new PendingLifetime(
            k,
            $list.append(sets, toList([value])),
            $list.append(ids, toList([message_id])),
          ),
          rest,
        );
      } else {
        let entry = $;
        let rest = reversed.tail;
        return listPrepend(
          entry,
          do_append_to_first_lifetime(rest, key, value, message_id),
        );
      }
    } else {
      let entry = $;
      let rest = reversed.tail;
      return listPrepend(
        entry,
        do_append_to_first_lifetime(rest, key, value, message_id),
      );
    }
  }
}

function append_to_latest_lifetime(pending, key, value, message_id) {
  let _pipe = $list.reverse(pending);
  let _pipe$1 = do_append_to_first_lifetime(_pipe, key, value, message_id);
  return $list.reverse(_pipe$1);
}

function storage_set(storage, key, value, message_id) {
  let _block;
  let $ = latest_storage_pending_for(storage.pending, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingLifetime) {
      _block = append_to_latest_lifetime(
        storage.pending,
        key,
        value,
        message_id,
      );
    } else if ($1 instanceof PendingDelete) {
      _block = $list.append(
        storage.pending,
        toList([new PendingLifetime(key, toList([value]), toList([message_id]))]),
      );
    } else {
      _block = $list.append(
        storage.pending,
        toList([new PendingLifetime(key, toList([value]), toList([message_id]))]),
      );
    }
  } else {
    _block = $list.append(
      storage.pending,
      toList([new PendingLifetime(key, toList([value]), toList([message_id]))]),
    );
  }
  let pending = _block;
  return new StorageState(storage.sequenced, storage.insertion_order, pending);
}

export function set(state, path, key, value) {
  let message_id = state.next_message_id;
  let mutate = (node) => {
    let previous = storage_get(node.storage, key);
    let storage = storage_set(node.storage, key, value, message_id);
    return [
      new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        storage,
        node.subdirectories,
        node.subdirectory_order,
        node.pending_subdirectories,
      ),
      previous,
    ];
  };
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let root = $[0][0];
    let previous = $[0][1];
    return new Ok(
      [
        new DirectoryState(root, message_id + 1),
        toList([
          new ValueChanged(path, key, $option.from_result(previous), true),
        ]),
        new Set(path, key, value),
        message_id,
      ],
    );
  } else {
    return new Error(new PathNotFound(path));
  }
}

export function delete$(state, path, key) {
  let message_id = state.next_message_id;
  let mutate = (node) => {
    let previous = storage_get(node.storage, key);
    let _block;
    let _record = node.storage;
    _block = new StorageState(
      _record.sequenced,
      _record.insertion_order,
      $list.append(
        node.storage.pending,
        toList([new PendingDelete(key, message_id)]),
      ),
    );
    let storage = _block;
    return [
      new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        storage,
        node.subdirectories,
        node.subdirectory_order,
        node.pending_subdirectories,
      ),
      previous,
    ];
  };
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let root = $[0][0];
    let previous = $[0][1];
    let _block;
    if (previous instanceof Ok) {
      let value = previous[0];
      _block = toList([new ValueChanged(path, key, new Some(value), true)]);
    } else {
      _block = $List$Empty$const;
    }
    let events = _block;
    return new Ok(
      [
        new DirectoryState(root, message_id + 1),
        events,
        new Delete(path, key),
        message_id,
      ],
    );
  } else {
    return new Error(new PathNotFound(path));
  }
}

export function clear(state, path) {
  let message_id = state.next_message_id;
  let mutate = (node) => {
    let visible = storage_entries(node.storage);
    let _block;
    let _record = node.storage;
    _block = new StorageState(
      _record.sequenced,
      _record.insertion_order,
      $list.append(node.storage.pending, toList([new PendingClear(message_id)])),
    );
    let storage = _block;
    return [
      new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        storage,
        node.subdirectories,
        node.subdirectory_order,
        node.pending_subdirectories,
      ),
      visible,
    ];
  };
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let root = $[0][0];
    let visible = $[0][1];
    let events = listPrepend(
      new Cleared(path, true),
      $list.map(
        visible,
        (e) => { return new ValueChanged(path, e[0], new Some(e[1]), true); },
      ),
    );
    return new Ok(
      [
        new DirectoryState(root, message_id + 1),
        events,
        new Clear(path),
        message_id,
      ],
    );
  } else {
    return new Error(new PathNotFound(path));
  }
}

function add_creator(creators, client) {
  let $ = $list.contains(creators, client);
  if ($) {
    return creators;
  } else {
    return $list.append(creators, toList([client]));
  }
}

/**
 * The names that can alias a child instance from this node. Those names are
 * the sequenced children and the pending-create markers. The
 * `getSubdirectoriesEvenIfDisposed` function of FluidFramework reaches both.
 * A name that a pending remove hides resolves to `Error(Nil)` in
 * `optimistic_child`, and a caller thus skips it, exactly as the iterators of
 * FluidFramework skip it.
 * 
 * @ignore
 */
function aliased_child_names(node) {
  let _block;
  let _pipe = $list.filter_map(
    node.pending_subdirectories,
    (entry) => {
      if (entry instanceof PendingCreate) {
        let name = entry.name;
        let $ = $dict.has_key(node.subdirectories, name);
        if ($) {
          return new Error(undefined);
        } else {
          return new Ok(name);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  _block = $list.unique(_pipe);
  let marker_names = _block;
  return $list.append(node.subdirectory_order, marker_names);
}

/**
 * The `undisposeSubdirectoryTree` function of FluidFramework. Clear the
 * disposed flag on this node and on every aliased child that the function
 * reaches, from the bottom up. The function includes a disposed child, because
 * a revive must reach the marker copies that the kernel retained.
 * 
 * @ignore
 */
function undispose_tree(node) {
  let $ = $list.fold(
    aliased_child_names(node),
    [node, $List$Empty$const],
    (acc, name) => {
      let node$1 = acc[0];
      let events = acc[1];
      let $1 = optimistic_child(node$1, name, true);
      if ($1 instanceof Ok) {
        let child = $1[0];
        let $2 = undispose_tree(child);
        let child$1 = $2[0];
        let ev = $2[1];
        return [
          put_optimistic_child(node$1, name, child$1),
          $list.append(events, ev),
        ];
      } else {
        return acc;
      }
    },
  );
  let node$1 = $[0];
  let child_events = $[1];
  return [
    new DirectoryNode(
      node$1.path,
      node$1.create,
      node$1.birth,
      node$1.creators,
      node$1.detached_created,
      false,
      node$1.storage,
      node$1.subdirectories,
      node$1.subdirectory_order,
      node$1.pending_subdirectories,
    ),
    listPrepend(new Undisposed(node$1.path), child_events),
  ];
}

function valid_subdirectory_name(name) {
  return (name !== "") && !$string.contains(name, "/");
}

export function create_subdirectory(state, path, name, self) {
  let $ = valid_subdirectory_name(name);
  if ($) {
    let message_id = state.next_message_id;
    let child_path = join(path, name);
    let mutate = (node) => {
      let $1 = optimistic_child(node, name, true);
      if ($1 instanceof Ok) {
        let existing = $1[0];
        let _block;
        let $3 = existing.disposed;
        if ($3) {
          _block = undispose_tree(existing);
        } else {
          _block = [existing, $List$Empty$const];
        }
        let $2 = _block;
        let revived = $2[0];
        let undispose_events = $2[1];
        let revived$1 = new DirectoryNode(
          revived.path,
          revived.create,
          revived.birth,
          add_creator(revived.creators, self),
          revived.detached_created,
          revived.disposed,
          revived.storage,
          revived.subdirectories,
          revived.subdirectory_order,
          revived.pending_subdirectories,
        );
        return [
          put_optimistic_child(node, name, revived$1),
          [false, undispose_events],
        ];
      } else {
        let child = new_node(
          child_path,
          new CreateInfo(-1, message_id),
          toList([self]),
          false,
        );
        let node$1 = new DirectoryNode(
          node.path,
          node.create,
          node.birth,
          node.creators,
          node.detached_created,
          node.disposed,
          node.storage,
          node.subdirectories,
          node.subdirectory_order,
          $list.append(
            node.pending_subdirectories,
            toList([new PendingCreate(name, child, message_id, false)]),
          ),
        );
        return [node$1, [true, $List$Empty$const]];
      }
    };
    let $1 = update_optimistic(state.root, segments(path), mutate);
    if ($1 instanceof Ok) {
      let root = $1[0][0];
      let is_new = $1[0][1][0];
      let undispose_events = $1[0][1][1];
      let state$1 = new DirectoryState(root, message_id + 1);
      if (is_new) {
        return new Ok(
          [
            state$1,
            toList([new SubDirectoryCreated(child_path, true)]),
            new Some(new CreateSubDirectory(path, name)),
            message_id,
          ],
        );
      } else {
        return new Ok(
          [
            new DirectoryState(state$1.root, message_id),
            undispose_events,
            Option$None$const,
            message_id,
          ],
        );
      }
    } else {
      return new Error(new PathNotFound(path));
    }
  } else {
    return new Error(new InvalidName(name));
  }
}

/**
 * The dispose events for a subtree. The children come first, from the bottom
 * up, and this node comes last.
 * 
 * @ignore
 */
function dispose_events_only(node) {
  let child_events = $list.flat_map(
    node.subdirectory_order,
    (name) => {
      let $ = $dict.get(node.subdirectories, name);
      if ($ instanceof Ok) {
        let child = $[0];
        return dispose_events_only(child);
      } else {
        return $List$Empty$const;
      }
    },
  );
  return $list.append(child_events, toList([new Disposed(node.path)]));
}

export function delete_subdirectory(state, path, name) {
  let message_id = state.next_message_id;
  let child_path = join(path, name);
  let mutate = (node) => {
    let $ = optimistic_child(node, name, false);
    if ($ instanceof Ok) {
      let previous = $[0];
      let dispose_events = dispose_events_only(previous);
      let node$1 = new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        node.storage,
        node.subdirectories,
        node.subdirectory_order,
        $list.append(
          node.pending_subdirectories,
          toList([new PendingRemove(name, message_id)]),
        ),
      );
      return [node$1, new Some(dispose_events)];
    } else {
      return [node, Option$None$const];
    }
  };
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1 instanceof Some) {
      let root = $[0][0];
      let dispose_events = $1[0];
      return new Ok(
        [
          new DirectoryState(root, message_id + 1),
          $list.append(
            toList([new SubDirectoryDeleted(child_path, true)]),
            dispose_events,
          ),
          new Some(new DeleteSubDirectory(path, name)),
          message_id,
        ],
      );
    } else {
      return new Ok([state, $List$Empty$const, Option$None$const, message_id]);
    }
  } else {
    return new Error(new PathNotFound(path));
  }
}

/**
 * The undispose events for a subtree. This node comes first, from the top
 * down, and the children come after it.
 * 
 * @ignore
 */
function undispose_events_only(node) {
  let child_events = $list.flat_map(
    node.subdirectory_order,
    (name) => {
      let $ = $dict.get(node.subdirectories, name);
      if ($ instanceof Ok) {
        let child = $[0];
        return undispose_events_only(child);
      } else {
        return $List$Empty$const;
      }
    },
  );
  return listPrepend(new Undisposed(node.path), child_events);
}

/**
 * The `disposeSubDirectoryTree`, `clearSubDirectorySequencedData`, and
 * `dispose` functions of FluidFramework, together.
 *
 * Walk the *optimistic* children from the bottom up. The walk skips a child
 * that a pending remove hides, and a child that is already disposed, the same
 * as the `subdirectories()` iterator of FluidFramework.
 *
 * Then reset the instance identity of this node. Set the create
 * sequence_number back to unknown, which is `-1`, and set the creators to the
 * local client only. That client stands for the create operation that it has
 * pending, or that it can send later. Then drop the sequenced storage and the
 * sequenced children, and keep every pending value. A node that a marker
 * retained thus carries a new identity when a later create revives it, and it
 * does not keep the identity of the deleted instance.
 *
 * The function writes each cleared copy back into its marker slot first, so
 * the retained aliases stay in agreement. FluidFramework changes the shared
 * objects instead.
 * 
 * @ignore
 */
function dispose_subdirectory_tree(node, self) {
  let node$1 = $list.fold(
    aliased_child_names(node),
    node,
    (node, name) => {
      let $ = optimistic_child(node, name, false);
      if ($ instanceof Ok) {
        let child = $[0];
        return put_optimistic_child(
          node,
          name,
          dispose_subdirectory_tree(child, self),
        );
      } else {
        return node;
      }
    },
  );
  return new DirectoryNode(
    node$1.path,
    new CreateInfo(-1, -1),
    node$1.birth,
    toList([self]),
    false,
    true,
    (() => {
      let _record = node$1.storage;
      return new StorageState($dict.new$(), $List$Empty$const, _record.pending);
    })(),
    $dict.new$(),
    $List$Empty$const,
    node$1.pending_subdirectories,
  );
}

/**
 * After a sequenced delete removes the instance of `name` from
 * `subdirectories`, keep a folded pending-create marker that points at the
 * cleared node. Do that only when the marker aliases *that* instance, which is
 * true when the birth values are equal. The pending entry of FluidFramework
 * holds the same object.
 *
 * A marker for a different instance keeps its own node, and the function does
 * not change it. Such a marker is not folded, or it is folded and an ack that
 * arrived between the two replaced the instance in the slot. To overwrite that
 * marker would destroy the pending data that its instance retained.
 * 
 * @ignore
 */
function sync_folded_marker(node, name, cleared) {
  let $ = latest_pending_subdirectory(node, name);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PendingCreate) {
      let $2 = $1.folded;
      if ($2) {
        let marker_node = $1.node;
        let $3 = isEqual(marker_node.birth, cleared.birth);
        if ($3) {
          return new DirectoryNode(
            node.path,
            node.create,
            node.birth,
            node.creators,
            node.detached_created,
            node.disposed,
            node.storage,
            node.subdirectories,
            node.subdirectory_order,
            mark_latest_pending_create_folded(
              node.pending_subdirectories,
              name,
              cleared,
            ),
          );
        } else {
          return node;
        }
      } else {
        return node;
      }
    } else {
      return node;
    }
  } else {
    return node;
  }
}

function has_pending_remove_named(node, name) {
  return $list.any(
    node.pending_subdirectories,
    (e) => {
      if (e instanceof PendingCreate) {
        return false;
      } else {
        let n = e.name;
        return n === name;
      }
    },
  );
}

function remote_delete_subdirectory(node, path, name, self, local) {
  let child_path = join(path, name);
  let $ = sequenced_child(node, name);
  if ($ instanceof Ok) {
    let previous = $[0];
    let cleared = dispose_subdirectory_tree(previous, self);
    let node$1 = remove_sequenced_child(node, name);
    let node$2 = sync_folded_marker(node$1, name, cleared);
    let masked = has_pending_remove_named(node$2, name);
    let _block;
    let $1 = local || masked;
    if ($1) {
      _block = $List$Empty$const;
    } else {
      _block = toList([new SubDirectoryDeleted(child_path, false)]);
    }
    let events = _block;
    return [node$2, events];
  } else {
    return [node, $List$Empty$const];
  }
}

/**
 * D12: whether this sequenced message is for the current live instance of
 * `node`. For a remote operation, where `target` is `None`, one of three
 * conditions must hold. The author is a creator. Or a client created the
 * instance while the directory was detached. Or the create sequence_number of
 * the instance is known to the other clients, which means it is not `-1`, and
 * it is before the reference sequence number of the operation.
 * 
 * @ignore
 */
function is_message_for_current_instance(node, meta, target) {
  let _block;
  if (target instanceof Some) {
    let t = target[0];
    _block = (t.path === node.path) && (isEqual(t.create, node.create));
  } else {
    _block = true;
  }
  let targets_this = _block;
  let by_creator = $list.contains(node.creators, meta.author);
  let by_detached = node.detached_created;
  let by_reference = (node.create.sequence_number !== -1) && (node.create.sequence_number <= meta.reference_sequence_number);
  return targets_this && ((by_creator || by_detached) || by_reference);
}

/**
 * Route a remote subdirectory operation to the sequenced *parent* directory at
 * `path`.
 * 
 * @ignore
 */
function apply_remote_subdirectory(state, path, meta, f) {
  let mutate = (node) => {
    let $ = is_message_for_current_instance(node, meta, Option$None$const);
    if ($) {
      return f(node);
    } else {
      return [node, $List$Empty$const];
    }
  };
  let $ = update_sequenced(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let root = $[0][0];
    let events = $[0][1];
    return [new DirectoryState(root, state.next_message_id), events];
  } else {
    return [state, $List$Empty$const];
  }
}

function has_pending_subdirectory_named(node, name) {
  return $list.any(
    node.pending_subdirectories,
    (e) => { return pending_subdirectory_name(e) === name; },
  );
}

function remote_create_subdirectory(node, path, name, meta, local) {
  let child_path = join(path, name);
  let create = new CreateInfo(meta.sequence_number, meta.client_sequence_number);
  let $ = optimistic_child(node, name, true);
  if ($ instanceof Ok) {
    let existing = $[0];
    let _block;
    let $2 = existing.disposed;
    if ($2) {
      _block = undispose_tree(existing);
    } else {
      _block = [existing, $List$Empty$const];
    }
    let $1 = _block;
    let revived = $1[0];
    let revived$1 = new DirectoryNode(
      revived.path,
      revived.create,
      revived.birth,
      add_creator(revived.creators, meta.author),
      revived.detached_created,
      revived.disposed,
      revived.storage,
      revived.subdirectories,
      revived.subdirectory_order,
      revived.pending_subdirectories,
    );
    let _block$1;
    let $3 = ((node.create.sequence_number !== -1) && (node.create.sequence_number <= meta.sequence_number)) && (revived$1.create.sequence_number === -1);
    if ($3) {
      _block$1 = new DirectoryNode(
        revived$1.path,
        create,
        revived$1.birth,
        revived$1.creators,
        revived$1.detached_created,
        revived$1.disposed,
        revived$1.storage,
        revived$1.subdirectories,
        revived$1.subdirectory_order,
        revived$1.pending_subdirectories,
      );
    } else {
      _block$1 = revived$1;
    }
    let revived$2 = _block$1;
    let node$1 = put_sequenced_child(node, name, revived$2);
    let node$2 = new DirectoryNode(
      node$1.path,
      node$1.create,
      node$1.birth,
      node$1.creators,
      node$1.detached_created,
      node$1.disposed,
      node$1.storage,
      node$1.subdirectories,
      node$1.subdirectory_order,
      mark_latest_pending_create_folded(
        node$1.pending_subdirectories,
        name,
        revived$2,
      ),
    );
    let masked = has_pending_subdirectory_named(node$2, name);
    let _block$2;
    let $4 = local || masked;
    if ($4) {
      _block$2 = $List$Empty$const;
    } else {
      _block$2 = toList([new SubDirectoryCreated(child_path, false)]);
    }
    let events = _block$2;
    return [node$2, events];
  } else {
    let child = new_node(child_path, create, toList([meta.author]), false);
    let node$1 = put_sequenced_child(node, name, child);
    let masked = has_pending_subdirectory_named(node$1, name);
    let _block;
    let $1 = local || masked;
    if ($1) {
      _block = $List$Empty$const;
    } else {
      _block = toList([new SubDirectoryCreated(child_path, false)]);
    }
    let events = _block;
    return [node$1, events];
  }
}

function has_storage_entry_for_key(pending, key) {
  return $list.any(
    pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        let k = entry.key;
        return k === key;
      } else if (entry instanceof PendingDelete) {
        let k = entry.key;
        return k === key;
      } else {
        return false;
      }
    },
  );
}

function remote_storage_clear(node, path) {
  let s = node.storage;
  let deleted = $list.filter_map(
    s.insertion_order,
    (key) => {
      let $ = has_storage_entry_for_key(s.pending, key);
      if ($) {
        return new Error(undefined);
      } else {
        let _pipe = $dict.get(s.sequenced, key);
        return $result.map(_pipe, (value) => { return [key, value]; });
      }
    },
  );
  let has_pending_clear = $list.any(
    s.pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        return false;
      } else if (entry instanceof PendingDelete) {
        return false;
      } else {
        return true;
      }
    },
  );
  let _block;
  if (has_pending_clear) {
    _block = $List$Empty$const;
  } else {
    _block = listPrepend(
      new Cleared(path, false),
      $list.map(
        deleted,
        (e) => { return new ValueChanged(path, e[0], new Some(e[1]), false); },
      ),
    );
  }
  let events = _block;
  let storage = new StorageState($dict.new$(), $List$Empty$const, s.pending);
  return [
    new DirectoryNode(
      node.path,
      node.create,
      node.birth,
      node.creators,
      node.detached_created,
      node.disposed,
      storage,
      node.subdirectories,
      node.subdirectory_order,
      node.pending_subdirectories,
    ),
    events,
  ];
}

/**
 * Route a remote storage operation to the sequenced directory at `path`, and
 * apply the stale-instance filter to that target node.
 * 
 * @ignore
 */
function apply_remote_storage(state, path, meta, f) {
  let mutate = (node) => {
    let $ = is_message_for_current_instance(node, meta, Option$None$const);
    if ($) {
      return f(node);
    } else {
      return [node, $List$Empty$const];
    }
  };
  let $ = update_sequenced(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let root = $[0][0];
    let events = $[0][1];
    return [new DirectoryState(root, state.next_message_id), events];
  } else {
    return [state, $List$Empty$const];
  }
}

function has_storage_pending_for(pending, key) {
  return $list.any(
    pending,
    (entry) => { return storage_matches_key(entry, key); },
  );
}

function remote_storage_delete(node, path, key) {
  let s = node.storage;
  let _block;
  let _pipe = $dict.get(s.sequenced, key);
  _block = $option.from_result(_pipe);
  let previous = _block;
  let storage = new StorageState(
    $dict.delete$(s.sequenced, key),
    $list.filter(s.insertion_order, (k) => { return k !== key; }),
    s.pending,
  );
  let _block$1;
  let $ = has_storage_pending_for(s.pending, key);
  if ($) {
    _block$1 = $List$Empty$const;
  } else {
    _block$1 = toList([new ValueChanged(path, key, previous, false)]);
  }
  let events = _block$1;
  return [
    new DirectoryNode(
      node.path,
      node.create,
      node.birth,
      node.creators,
      node.detached_created,
      node.disposed,
      storage,
      node.subdirectories,
      node.subdirectory_order,
      node.pending_subdirectories,
    ),
    events,
  ];
}

function remote_storage_set(node, path, key, value) {
  let s = node.storage;
  let _block;
  let _pipe = $dict.get(s.sequenced, key);
  _block = $option.from_result(_pipe);
  let previous = _block;
  let _block$1;
  let $ = $dict.has_key(s.sequenced, key);
  if ($) {
    _block$1 = s.insertion_order;
  } else {
    _block$1 = $list.append(s.insertion_order, toList([key]));
  }
  let insertion_order = _block$1;
  let storage = new StorageState(
    $dict.insert(s.sequenced, key, value),
    insertion_order,
    s.pending,
  );
  let _block$2;
  let $1 = has_storage_pending_for(s.pending, key);
  if ($1) {
    _block$2 = $List$Empty$const;
  } else {
    _block$2 = toList([new ValueChanged(path, key, previous, false)]);
  }
  let events = _block$2;
  return [
    new DirectoryNode(
      node.path,
      node.create,
      node.birth,
      node.creators,
      node.detached_created,
      node.disposed,
      storage,
      node.subdirectories,
      node.subdirectory_order,
      node.pending_subdirectories,
    ),
    events,
  ];
}

export function apply_remote(state, operation, meta, self) {
  if (operation instanceof Set) {
    let path = operation.path;
    let key = operation.key;
    let value = operation.value;
    return apply_remote_storage(
      state,
      path,
      meta,
      (node) => { return remote_storage_set(node, path, key, value); },
    );
  } else if (operation instanceof Delete) {
    let path = operation.path;
    let key = operation.key;
    return apply_remote_storage(
      state,
      path,
      meta,
      (node) => { return remote_storage_delete(node, path, key); },
    );
  } else if (operation instanceof Clear) {
    let path = operation.path;
    return apply_remote_storage(
      state,
      path,
      meta,
      (node) => { return remote_storage_clear(node, path); },
    );
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    return apply_remote_subdirectory(
      state,
      path,
      meta,
      (node) => {
        return remote_create_subdirectory(node, path, name, meta, false);
      },
    );
  } else {
    let path = operation.path;
    let name = operation.name;
    return apply_remote_subdirectory(
      state,
      path,
      meta,
      (node) => {
        return remote_delete_subdirectory(node, path, name, self, false);
      },
    );
  }
}

function ack_subdirectory_apply(state, operation, path, meta, mutate) {
  let guarded = (node) => {
    let $ = is_message_for_current_instance(node, meta, Option$None$const);
    if ($) {
      return mutate(node);
    } else {
      return [node, new Ok(undefined)];
    }
  };
  let $ = update_sequenced(state.root, segments(path), guarded);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1 instanceof Ok) {
      let root = $[0][0];
      return new Ok(new DirectoryState(root, state.next_message_id));
    } else {
      let detail = $1[0];
      return new Error(new UnexpectedAck(operation, detail));
    }
  } else {
    return new Ok(state);
  }
}

function remove_pending_subdirectory(pending, name, message_id, is_create) {
  let found = $list.any(
    pending,
    (entry) => {
      if (entry instanceof PendingCreate) {
        if (is_create) {
          let n = entry.name;
          let id = entry.message_id;
          return (n === name) && (id === message_id);
        } else {
          return is_create;
        }
      } else if (is_create) {
        return false;
      } else {
        let n = entry.name;
        let id = entry.message_id;
        return (n === name) && (id === message_id);
      }
    },
  );
  if (found) {
    return new Ok(
      $list.filter(
        pending,
        (entry) => {
          if (entry instanceof PendingCreate) {
            if (is_create) {
              let n = entry.name;
              let id = entry.message_id;
              return !((n === name) && (id === message_id));
            } else {
              return true;
            }
          } else if (is_create) {
            return true;
          } else {
            let n = entry.name;
            let id = entry.message_id;
            return !((n === name) && (id === message_id));
          }
        },
      ),
    );
  } else {
    return new Error(undefined);
  }
}

function ack_delete_subdirectory(state, operation, path, name, meta) {
  let mutate = (node) => {
    let $ = remove_pending_subdirectory(
      node.pending_subdirectories,
      name,
      meta.client_sequence_number,
      false,
    );
    if ($ instanceof Ok) {
      let rest = $[0];
      let node$1 = new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        node.storage,
        node.subdirectories,
        node.subdirectory_order,
        rest,
      );
      let $1 = sequenced_child(node$1, name);
      if ($1 instanceof Ok) {
        let previous = $1[0];
        let cleared = dispose_subdirectory_tree(previous, meta.author);
        let node$2 = remove_sequenced_child(node$1, name);
        return [sync_folded_marker(node$2, name, cleared), new Ok(undefined)];
      } else {
        return [node$1, new Ok(undefined)];
      }
    } else {
      return [node, new Ok(undefined)];
    }
  };
  return ack_subdirectory_apply(state, operation, path, meta, mutate);
}

function do_take_pending(loop$pending, loop$seen, loop$match) {
  while (true) {
    let pending = loop$pending;
    let seen = loop$seen;
    let match = loop$match;
    if (pending instanceof $Empty) {
      return new Error(undefined);
    } else {
      let entry = pending.head;
      let rest = pending.tail;
      let $ = match(entry);
      if ($ instanceof Some) {
        let value = $[0];
        return new Ok([value, $list.append($list.reverse(seen), rest)]);
      } else {
        loop$pending = rest;
        loop$seen = listPrepend(entry, seen);
        loop$match = match;
      }
    }
  }
}

/**
 * Remove the pending create for `name` that carries `message_id`. Return its
 * node, and whether the kernel had folded that node into the sequenced
 * children.
 * 
 * @ignore
 */
function take_pending_create_by_id(pending, name, message_id) {
  return do_take_pending(
    pending,
    $List$Empty$const,
    (e) => {
      if (e instanceof PendingCreate) {
        let n = e.name;
        let id = e.message_id;
        if ((n === name) && (id === message_id)) {
          let node = e.node;
          let folded = e.folded;
          return new Some([node, folded]);
        } else {
          return Option$None$const;
        }
      } else {
        return Option$None$const;
      }
    },
  );
}

function ack_create_subdirectory(state, operation, path, name, meta) {
  let create = new CreateInfo(meta.sequence_number, meta.client_sequence_number);
  let mutate = (orig_node) => {
    let $ = take_pending_create_by_id(
      orig_node.pending_subdirectories,
      name,
      meta.client_sequence_number,
    );
    if ($ instanceof Ok) {
      let rest = $[0][1];
      let marker_node = $[0][0][0];
      let node = new DirectoryNode(
        orig_node.path,
        orig_node.create,
        orig_node.birth,
        orig_node.creators,
        orig_node.detached_created,
        orig_node.disposed,
        orig_node.storage,
        orig_node.subdirectories,
        orig_node.subdirectory_order,
        rest,
      );
      let $1 = sequenced_child(node, name);
      if ($1 instanceof Ok) {
        return [node, new Ok(undefined)];
      } else {
        let _block;
        let $3 = marker_node.disposed;
        if ($3) {
          _block = undispose_tree(marker_node);
        } else {
          _block = [marker_node, $List$Empty$const];
        }
        let $2 = _block;
        let child = $2[0];
        let _block$1;
        let $4 = ((node.create.sequence_number !== -1) && (node.create.sequence_number <= meta.sequence_number)) && (child.create.sequence_number === -1);
        if ($4) {
          _block$1 = new DirectoryNode(
            child.path,
            create,
            child.birth,
            child.creators,
            child.detached_created,
            child.disposed,
            child.storage,
            child.subdirectories,
            child.subdirectory_order,
            child.pending_subdirectories,
          );
        } else {
          _block$1 = child;
        }
        let child$1 = _block$1;
        return [put_sequenced_child(node, name, child$1), new Ok(undefined)];
      }
    } else {
      return [orig_node, new Ok(undefined)];
    }
  };
  return ack_subdirectory_apply(state, operation, path, meta, mutate);
}

function do_split_storage(loop$pending, loop$key, loop$seen) {
  while (true) {
    let pending = loop$pending;
    let key = loop$key;
    let seen = loop$seen;
    if (pending instanceof $Empty) {
      return new Error(undefined);
    } else {
      let $ = pending.head;
      if ($ instanceof PendingLifetime) {
        let k = $.key;
        if (k === key) {
          let entry = $;
          let rest = pending.tail;
          return new Ok([$list.reverse(seen), entry, rest]);
        } else {
          let entry = $;
          let rest = pending.tail;
          loop$pending = rest;
          loop$key = key;
          loop$seen = listPrepend(entry, seen);
        }
      } else if ($ instanceof PendingDelete) {
        let k = $.key;
        if (k === key) {
          let entry = $;
          let rest = pending.tail;
          return new Ok([$list.reverse(seen), entry, rest]);
        } else {
          let entry = $;
          let rest = pending.tail;
          loop$pending = rest;
          loop$key = key;
          loop$seen = listPrepend(entry, seen);
        }
      } else {
        let entry = $;
        let rest = pending.tail;
        loop$pending = rest;
        loop$key = key;
        loop$seen = listPrepend(entry, seen);
      }
    }
  }
}

function split_storage_at_first_for_key(pending, key) {
  return do_split_storage(pending, key, $List$Empty$const);
}

/**
 * The pending storage message ids on one node. The function does not
 * recurse.
 * 
 * @ignore
 */
function storage_pending_ids(storage) {
  return $list.flat_map(
    storage.pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        let ids = entry.message_ids;
        return ids;
      } else if (entry instanceof PendingDelete) {
        let id = entry.message_id;
        return toList([id]);
      } else {
        let id = entry.message_id;
        return toList([id]);
      }
    },
  );
}

/**
 * Commit one acked storage operation against the storage of a node.
 *
 * The message id of the ack selects the pending entry. That id replaces the
 * object-identity check of FluidFramework on `localOpMetadata`, which is
 * `pendingEntry === localOpMetadata` with the guard `targetSubdir === this`.
 *
 * An id that is no longer present means that the pending entry of this
 * operation went away with a replaced instance of this path, at a create dedup
 * or at a delete. The ack is thus stale, and the function does nothing and
 * returns `Ok(None)`. To match by key alone would incorrectly consume the
 * pending entry of a *later* operation on the current instance.
 *
 * An id that is present but out of FIFO position is a true protocol
 * violation.
 * 
 * @ignore
 */
function ack_storage_node(storage, operation, ack_id) {
  let present = $list.contains(storage_pending_ids(storage), ack_id);
  if (operation instanceof Set) {
    let key = operation.key;
    let $ = split_storage_at_first_for_key(storage.pending, key);
    if ($ instanceof Ok) {
      let $1 = $[0][1];
      if ($1 instanceof PendingLifetime) {
        let $2 = $1.sets;
        if ($2 instanceof $Empty) {
          if (!present) {
            return new Ok(Option$None$const);
          } else {
            return new Error("expected pending lifetime for key " + key);
          }
        } else {
          let $3 = $1.message_ids;
          if ($3 instanceof $Empty) {
            if (!present) {
              return new Ok(Option$None$const);
            } else {
              return new Error("expected pending lifetime for key " + key);
            }
          } else {
            let head_id = $3.head;
            if (head_id === ack_id) {
              let before = $[0][0];
              let after = $[0][2];
              let acked = $2.head;
              let rest_sets = $2.tail;
              let rest_ids = $3.tail;
              let _block;
              if (rest_sets instanceof $Empty) {
                _block = $list.append(before, after);
              } else {
                _block = $list.append(
                  before,
                  listPrepend(
                    new PendingLifetime(key, rest_sets, rest_ids),
                    after,
                  ),
                );
              }
              let pending = _block;
              let _block$1;
              let $4 = $dict.has_key(storage.sequenced, key);
              if ($4) {
                _block$1 = storage.insertion_order;
              } else {
                _block$1 = $list.append(storage.insertion_order, toList([key]));
              }
              let insertion_order = _block$1;
              return new Ok(
                new Some(
                  new StorageState(
                    $dict.insert(storage.sequenced, key, acked),
                    insertion_order,
                    pending,
                  ),
                ),
              );
            } else if (!present) {
              return new Ok(Option$None$const);
            } else {
              return new Error("expected pending lifetime for key " + key);
            }
          }
        }
      } else if (!present) {
        return new Ok(Option$None$const);
      } else {
        return new Error("expected pending lifetime for key " + key);
      }
    } else if (!present) {
      return new Ok(Option$None$const);
    } else {
      return new Error("expected pending lifetime for key " + key);
    }
  } else if (operation instanceof Delete) {
    let key = operation.key;
    let $ = split_storage_at_first_for_key(storage.pending, key);
    if ($ instanceof Ok) {
      let $1 = $[0][1];
      if ($1 instanceof PendingDelete) {
        let id = $1.message_id;
        if (id === ack_id) {
          let before = $[0][0];
          let after = $[0][2];
          return new Ok(
            new Some(
              new StorageState(
                $dict.delete$(storage.sequenced, key),
                $list.filter(
                  storage.insertion_order,
                  (k) => { return k !== key; },
                ),
                $list.append(before, after),
              ),
            ),
          );
        } else if (!present) {
          return new Ok(Option$None$const);
        } else {
          return new Error("expected pending delete for key " + key);
        }
      } else if (!present) {
        return new Ok(Option$None$const);
      } else {
        return new Error("expected pending delete for key " + key);
      }
    } else if (!present) {
      return new Ok(Option$None$const);
    } else {
      return new Error("expected pending delete for key " + key);
    }
  } else if (operation instanceof Clear) {
    let $ = storage.pending;
    if ($ instanceof $Empty) {
      if (!present) {
        return new Ok(Option$None$const);
      } else {
        return new Error("expected pending clear at queue head");
      }
    } else {
      let $1 = $.head;
      if ($1 instanceof PendingClear) {
        let id = $1.message_id;
        if (id === ack_id) {
          let rest = $.tail;
          return new Ok(
            new Some(new StorageState($dict.new$(), $List$Empty$const, rest)),
          );
        } else if (!present) {
          return new Ok(Option$None$const);
        } else {
          return new Error("expected pending clear at queue head");
        }
      } else if (!present) {
        return new Ok(Option$None$const);
      } else {
        return new Error("expected pending clear at queue head");
      }
    }
  } else if (operation instanceof CreateSubDirectory) {
    return new Error("non-storage op in ack_storage_node");
  } else {
    return new Error("non-storage op in ack_storage_node");
  }
}

function ack_storage(state, operation, path, meta) {
  let mutate = (node) => {
    let $ = is_message_for_current_instance(node, meta, Option$None$const);
    if ($) {
      let $1 = ack_storage_node(
        node.storage,
        operation,
        meta.client_sequence_number,
      );
      if ($1 instanceof Ok) {
        let $2 = $1[0];
        if ($2 instanceof Some) {
          let storage = $2[0];
          return [
            new DirectoryNode(
              node.path,
              node.create,
              node.birth,
              node.creators,
              node.detached_created,
              node.disposed,
              storage,
              node.subdirectories,
              node.subdirectory_order,
              node.pending_subdirectories,
            ),
            new Ok(undefined),
          ];
        } else {
          return [node, new Ok(undefined)];
        }
      } else {
        let detail = $1[0];
        return [node, new Error(detail)];
      }
    } else {
      return [node, new Ok(undefined)];
    }
  };
  let $ = update_sequenced(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1 instanceof Ok) {
      let root = $[0][0];
      return new Ok(new DirectoryState(root, state.next_message_id));
    } else {
      let detail = $1[0];
      return new Error(new UnexpectedAck(operation, detail));
    }
  } else {
    return new Ok(state);
  }
}

/**
 * Commit an acked local operation, which moves it from `pending` to
 * `sequenced`. The acks arrive in submission order, which is FIFO. A mismatch
 * is fatal. An ack emits no event, because the optimistic view already showed
 * the operation at submit time.
 */
export function ack_local(state, operation, meta) {
  if (operation instanceof Set) {
    let path = operation.path;
    return ack_storage(state, operation, path, meta);
  } else if (operation instanceof Delete) {
    let path = operation.path;
    return ack_storage(state, operation, path, meta);
  } else if (operation instanceof Clear) {
    let path = operation.path;
    return ack_storage(state, operation, path, meta);
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    return ack_create_subdirectory(state, operation, path, name, meta);
  } else {
    let path = operation.path;
    let name = operation.name;
    return ack_delete_subdirectory(state, operation, path, name, meta);
  }
}

function node_pending_ids(node) {
  let storage_ids = storage_pending_ids(node.storage);
  let subdirectory_ids = $list.flat_map(
    node.pending_subdirectories,
    (entry) => {
      if (entry instanceof PendingCreate) {
        let child = entry.node;
        let id = entry.message_id;
        return listPrepend(id, node_pending_ids(child));
      } else {
        let id = entry.message_id;
        return toList([id]);
      }
    },
  );
  let child_ids = $list.flat_map(
    node.subdirectory_order,
    (name) => {
      let $ = $dict.get(node.subdirectories, name);
      if ($ instanceof Ok) {
        let child = $[0];
        return node_pending_ids(child);
      } else {
        return $List$Empty$const;
      }
    },
  );
  return $list.flatten(toList([storage_ids, subdirectory_ids, child_ids]));
}

/**
 * The highest pending message id in the whole tree. That id belongs to the
 * operation that the client submitted last, which is the operation that a LIFO
 * rollback removes.
 */
export function last_pending_message_id(state) {
  let $ = node_pending_ids(state.root);
  if ($ instanceof $Empty) {
    return new Error(undefined);
  } else {
    let message_ids = $;
    return new Ok($list.fold(message_ids, -1, $int.max));
  }
}

function rollback_subdirectory_apply(state, operation, path, mutate) {
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1 instanceof Ok) {
      let root = $[0][0];
      let events = $1[0];
      return new Ok([new DirectoryState(root, state.next_message_id), events]);
    } else {
      let detail = $1[0];
      return new Error(new UnexpectedRollback(operation, detail));
    }
  } else {
    return new Error(
      new UnexpectedRollback(operation, "no directory at path " + path),
    );
  }
}

function rollback_remove(state, operation, path, name, message_id) {
  let child_path = join(path, name);
  let mutate = (node) => {
    let $ = remove_pending_subdirectory(
      node.pending_subdirectories,
      name,
      message_id,
      false,
    );
    if ($ instanceof Ok) {
      let pending = $[0];
      let node$1 = new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        node.storage,
        node.subdirectories,
        node.subdirectory_order,
        pending,
      );
      let _block;
      let $1 = optimistic_child(node$1, name, false);
      if ($1 instanceof Ok) {
        let child = $1[0];
        _block = undispose_events_only(child);
      } else {
        _block = toList([new Undisposed(child_path)]);
      }
      let undispose = _block;
      return [
        node$1,
        new Ok(
          $list.append(
            undispose,
            toList([new SubDirectoryCreated(child_path, true)]),
          ),
        ),
      ];
    } else {
      return [node, new Error("no pending delete for " + name)];
    }
  };
  return rollback_subdirectory_apply(state, operation, path, mutate);
}

function rollback_create(state, operation, path, name, message_id) {
  let child_path = join(path, name);
  let mutate = (node) => {
    let $ = take_pending_create_by_id(
      node.pending_subdirectories,
      name,
      message_id,
    );
    if ($ instanceof Ok) {
      let pending = $[0][1];
      let folded = $[0][0][1];
      let node$1 = new DirectoryNode(
        node.path,
        node.create,
        node.birth,
        node.creators,
        node.detached_created,
        node.disposed,
        node.storage,
        node.subdirectories,
        node.subdirectory_order,
        pending,
      );
      if (folded) {
        return [node$1, new Ok($List$Empty$const)];
      } else {
        return [
          node$1,
          new Ok(
            toList([
              new SubDirectoryDeleted(child_path, true),
              new Disposed(child_path),
            ]),
          ),
        ];
      }
    } else {
      return [node, new Error("no pending create for " + name)];
    }
  };
  return rollback_subdirectory_apply(state, operation, path, mutate);
}

function remove_pending_entry(pending, target) {
  let $ = $list.contains(pending, target);
  if ($) {
    return new Ok($list.filter(pending, (e) => { return !isEqual(e, target); }));
  } else {
    return new Error(undefined);
  }
}

function rollback_storage(state, operation, path, f) {
  let mutate = (node) => {
    let $ = f(node);
    if ($ instanceof Ok) {
      let node$1 = $[0][0];
      let events = $[0][1];
      return [node$1, new Ok(events)];
    } else {
      let detail = $[0];
      return [node, new Error(detail)];
    }
  };
  let $ = update_optimistic(state.root, segments(path), mutate);
  if ($ instanceof Ok) {
    let $1 = $[0][1];
    if ($1 instanceof Ok) {
      let root = $[0][0];
      let events = $1[0];
      return new Ok([new DirectoryState(root, state.next_message_id), events]);
    } else {
      let detail = $1[0];
      return new Error(new UnexpectedRollback(operation, detail));
    }
  } else {
    return new Error(
      new UnexpectedRollback(operation, "no directory at path " + path),
    );
  }
}

function rollback_clear(state, operation, path, message_id) {
  return rollback_storage(
    state,
    operation,
    path,
    (node) => {
      let storage_state = node.storage;
      let $ = remove_pending_entry(
        storage_state.pending,
        new PendingClear(message_id),
      );
      if ($ instanceof Ok) {
        let pending = $[0];
        let storage = new StorageState(
          storage_state.sequenced,
          storage_state.insertion_order,
          pending,
        );
        let node$1 = new DirectoryNode(
          node.path,
          node.create,
          node.birth,
          node.creators,
          node.detached_created,
          node.disposed,
          storage,
          node.subdirectories,
          node.subdirectory_order,
          node.pending_subdirectories,
        );
        return new Ok([node$1, $List$Empty$const]);
      } else {
        return new Error("no pending clear");
      }
    },
  );
}

function rollback_delete(state, operation, path, key, message_id) {
  return rollback_storage(
    state,
    operation,
    path,
    (node) => {
      let storage_state = node.storage;
      let $ = remove_pending_entry(
        storage_state.pending,
        new PendingDelete(key, message_id),
      );
      if ($ instanceof Ok) {
        let pending = $[0];
        let storage = new StorageState(
          storage_state.sequenced,
          storage_state.insertion_order,
          pending,
        );
        let node$1 = new DirectoryNode(
          node.path,
          node.create,
          node.birth,
          node.creators,
          node.detached_created,
          node.disposed,
          storage,
          node.subdirectories,
          node.subdirectory_order,
          node.pending_subdirectories,
        );
        let _block;
        let $1 = storage_get(storage, key);
        if ($1 instanceof Ok) {
          let restored = $1[0];
          _block = toList([
            new ValueChanged(path, key, new Some(restored), true),
          ]);
        } else {
          _block = $List$Empty$const;
        }
        let events = _block;
        return new Ok([node$1, events]);
      } else {
        return new Error("no pending delete for key " + key);
      }
    },
  );
}

function drop_last(xs) {
  let $ = $list.reverse(xs);
  if ($ instanceof $Empty) {
    return $;
  } else {
    let rest = $.tail;
    return $list.reverse(rest);
  }
}

function do_remove_last_set(loop$reversed, loop$key, loop$message_id, loop$seen) {
  while (true) {
    let reversed = loop$reversed;
    let key = loop$key;
    let message_id = loop$message_id;
    let seen = loop$seen;
    if (reversed instanceof $Empty) {
      return new Error(undefined);
    } else {
      let $ = reversed.head;
      if ($ instanceof PendingLifetime) {
        let k = $.key;
        if (k === key) {
          let rest = reversed.tail;
          let sets = $.sets;
          let ids = $.message_ids;
          let $1 = isEqual($list.last(ids), new Ok(message_id));
          if ($1) {
            let new_sets = drop_last(sets);
            let new_ids = drop_last(ids);
            let _block;
            let _pipe = $list.last(sets);
            _block = $option.from_result(_pipe);
            let removed = _block;
            if (new_ids instanceof $Empty) {
              return new Ok([$list.append($list.reverse(seen), rest), removed]);
            } else {
              return new Ok(
                [
                  $list.append(
                    $list.reverse(seen),
                    listPrepend(new PendingLifetime(k, new_sets, new_ids), rest),
                  ),
                  removed,
                ],
              );
            }
          } else {
            return new Error(undefined);
          }
        } else {
          let entry = $;
          let rest = reversed.tail;
          loop$reversed = rest;
          loop$key = key;
          loop$message_id = message_id;
          loop$seen = listPrepend(entry, seen);
        }
      } else {
        let entry = $;
        let rest = reversed.tail;
        loop$reversed = rest;
        loop$key = key;
        loop$message_id = message_id;
        loop$seen = listPrepend(entry, seen);
      }
    }
  }
}

/**
 * Remove the most recent set that carries `message_id`, from the newest
 * lifetime of `key`.
 * 
 * @ignore
 */
function remove_last_lifetime_set(pending, key, message_id) {
  let _pipe = $list.reverse(pending);
  let _pipe$1 = do_remove_last_set(_pipe, key, message_id, $List$Empty$const);
  return $result.map(
    _pipe$1,
    (pair) => {
      let reversed = pair[0];
      let value = pair[1];
      return [$list.reverse(reversed), value];
    },
  );
}

function rollback_set(state, operation, path, key, message_id) {
  return rollback_storage(
    state,
    operation,
    path,
    (node) => {
      let storage_state = node.storage;
      let $ = remove_last_lifetime_set(storage_state.pending, key, message_id);
      if ($ instanceof Ok) {
        let pending = $[0][0];
        let storage = new StorageState(
          storage_state.sequenced,
          storage_state.insertion_order,
          pending,
        );
        let node$1 = new DirectoryNode(
          node.path,
          node.create,
          node.birth,
          node.creators,
          node.detached_created,
          node.disposed,
          storage,
          node.subdirectories,
          node.subdirectory_order,
          node.pending_subdirectories,
        );
        let previous = storage_get(storage, key);
        return new Ok(
          [
            node$1,
            toList([
              new ValueChanged(path, key, $option.from_result(previous), true),
            ]),
          ],
        );
      } else {
        return new Error("no pending set for key " + key);
      }
    },
  );
}

export function rollback(state, operation, message_id) {
  if (operation instanceof Set) {
    let path = operation.path;
    let key = operation.key;
    return rollback_set(state, operation, path, key, message_id);
  } else if (operation instanceof Delete) {
    let path = operation.path;
    let key = operation.key;
    return rollback_delete(state, operation, path, key, message_id);
  } else if (operation instanceof Clear) {
    let path = operation.path;
    return rollback_clear(state, operation, path, message_id);
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    return rollback_create(state, operation, path, name, message_id);
  } else {
    let path = operation.path;
    let name = operation.name;
    return rollback_remove(state, operation, path, name, message_id);
  }
}

/**
 * Write `child` back into the slot that the candidate came from. A write to a
 * sequenced slot also updates a folded marker that aliases that instance,
 * which follows the shared object of FluidFramework. This function is the
 * counterpart of `put_optimistic_child`.
 * 
 * @ignore
 */
function put_candidate_child(node, name, slot, child) {
  if (slot instanceof SequencedSlot) {
    let node$1 = put_sequenced_child(node, name, child);
    return sync_folded_marker(node$1, name, child);
  } else {
    let id = slot.message_id;
    return new DirectoryNode(
      node.path,
      node.create,
      node.birth,
      node.creators,
      node.detached_created,
      node.disposed,
      node.storage,
      node.subdirectories,
      node.subdirectory_order,
      $list.map(
        node.pending_subdirectories,
        (entry) => {
          if (entry instanceof PendingCreate) {
            let n = entry.name;
            let entry_id = entry.message_id;
            if ((n === name) && (entry_id === id)) {
              let folded = entry.folded;
              return new PendingCreate(n, child, entry_id, folded);
            } else {
              return entry;
            }
          } else {
            return entry;
          }
        },
      ),
    );
  }
}

/**
 * Every retained instance that can answer to `name` under `node`, newest
 * lifecycle first, with the slot that it canonically lives in. Unlike
 * `optimistic_child`, this function also returns an instance that a later
 * pending entry *hides*, for example an old sequenced instance under a pending
 * remove and a pending create. The `localOpMetadata` value of FluidFramework
 * holds a direct object reference, and a lookup by path cannot reproduce that
 * reference. A resubmit must find the exact instance whose pending entry it is
 * deciding about.
 * 
 * @ignore
 */
function candidate_children(node, name) {
  let _block;
  let _pipe = $list.reverse(node.pending_subdirectories);
  _block = $list.filter_map(
    _pipe,
    (entry) => {
      if (entry instanceof PendingCreate) {
        let n = entry.name;
        if (n === name) {
          let child = entry.node;
          let id = entry.message_id;
          let folded = entry.folded;
          let aliased = folded && (() => {
            let $ = $dict.get(node.subdirectories, name);
            if ($ instanceof Ok) {
              let live = $[0];
              return isEqual(live.birth, child.birth);
            } else {
              return false;
            }
          })();
          if (aliased) {
            return new Error(undefined);
          } else {
            return new Ok([new MarkerSlot(id), child]);
          }
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
  let marker_candidates = _block;
  let _block$1;
  let _pipe$1 = $dict.get(node.subdirectories, name);
  let _pipe$2 = $result.map(
    _pipe$1,
    (child) => { return toList([[ChildSlot$SequencedSlot$const, child]]); },
  );
  _block$1 = $result.unwrap(_pipe$2, $List$Empty$const);
  let sequenced_candidate = _block$1;
  return $list.append(marker_candidates, sequenced_candidate);
}

/**
 * A depth-first search and update over the retained instances. At each path
 * segment the function tries every candidate instance (see
 * `candidate_children`), until the target of one subtree satisfies `f`. It
 * then writes the new nodes back along that branch. `f` returns `Error(Nil)`
 * to say "this is not the instance". The whole traversal thus replaces the
 * step in FluidFramework that follows the metadata object reference to the
 * position of the pending entry.
 * 
 * @ignore
 */
function update_retained_instance(node, segs, f) {
  if (segs instanceof $Empty) {
    return f(node);
  } else {
    let name = segs.head;
    let rest = segs.tail;
    return $list.fold(
      candidate_children(node, name),
      new Error(undefined),
      (acc, cand) => {
        if (acc instanceof Ok) {
          return acc;
        } else {
          let slot = cand[0];
          let child = cand[1];
          let $ = update_retained_instance(child, rest, f);
          if ($ instanceof Ok) {
            let new_child = $[0][0];
            let r = $[0][1];
            return new Ok([put_candidate_child(node, name, slot, new_child), r]);
          } else {
            return new Error(undefined);
          }
        }
      },
    );
  }
}

/**
 * Remove the one pending storage entry that carries `message_id`. That entry
 * is one set inside a lifetime, and the function removes the lifetime when it
 * becomes empty. Or that entry is the matching delete or clear.
 * 
 * @ignore
 */
function strip_storage_pending(pending, message_id) {
  return $list.filter_map(
    pending,
    (entry) => {
      if (entry instanceof PendingLifetime) {
        let key = entry.key;
        let sets = entry.sets;
        let ids = entry.message_ids;
        let $ = $list.contains(ids, message_id);
        if ($) {
          let _block;
          let _pipe = $list.zip(sets, ids);
          _block = $list.filter(
            _pipe,
            (pair) => { return pair[1] !== message_id; },
          );
          let kept = _block;
          if (kept instanceof $Empty) {
            return new Error(undefined);
          } else {
            return new Ok(
              new PendingLifetime(
                key,
                $list.map(kept, (pair) => { return pair[0]; }),
                $list.map(kept, (pair) => { return pair[1]; }),
              ),
            );
          }
        } else {
          return new Ok(entry);
        }
      } else if (entry instanceof PendingDelete) {
        let id = entry.message_id;
        if (id === message_id) {
          return new Error(undefined);
        } else {
          return new Ok(entry);
        }
      } else {
        let id = entry.message_id;
        if (id === message_id) {
          return new Error(undefined);
        } else {
          return new Ok(entry);
        }
      }
    },
  );
}

/**
 * Remove the pending entry behind a dropped resubmit, from the position at
 * which it still exists. The function searches *every* retained instance, and
 * it includes the disposed ones, because the drop usually happened because
 * the instance is disposed. The operation of that entry will never sequence.
 * To keep the entry would let a later revive of the retained instance show an
 * optimistic edit that no other client sees.
 * 
 * @ignore
 */
function strip_dropped_pending(state, operation, message_id) {
  let _block;
  if (operation instanceof Set) {
    let path = operation.path;
    _block = [
      path,
      (node) => {
        let $1 = $list.contains(storage_pending_ids(node.storage), message_id);
        if ($1) {
          return new Ok(
            [
              new DirectoryNode(
                node.path,
                node.create,
                node.birth,
                node.creators,
                node.detached_created,
                node.disposed,
                (() => {
                  let _record = node.storage;
                  return new StorageState(
                    _record.sequenced,
                    _record.insertion_order,
                    strip_storage_pending(node.storage.pending, message_id),
                  );
                })(),
                node.subdirectories,
                node.subdirectory_order,
                node.pending_subdirectories,
              ),
              undefined,
            ],
          );
        } else {
          return new Error(undefined);
        }
      },
    ];
  } else if (operation instanceof Delete) {
    let path = operation.path;
    _block = [
      path,
      (node) => {
        let $1 = $list.contains(storage_pending_ids(node.storage), message_id);
        if ($1) {
          return new Ok(
            [
              new DirectoryNode(
                node.path,
                node.create,
                node.birth,
                node.creators,
                node.detached_created,
                node.disposed,
                (() => {
                  let _record = node.storage;
                  return new StorageState(
                    _record.sequenced,
                    _record.insertion_order,
                    strip_storage_pending(node.storage.pending, message_id),
                  );
                })(),
                node.subdirectories,
                node.subdirectory_order,
                node.pending_subdirectories,
              ),
              undefined,
            ],
          );
        } else {
          return new Error(undefined);
        }
      },
    ];
  } else if (operation instanceof Clear) {
    let path = operation.path;
    _block = [
      path,
      (node) => {
        let $1 = $list.contains(storage_pending_ids(node.storage), message_id);
        if ($1) {
          return new Ok(
            [
              new DirectoryNode(
                node.path,
                node.create,
                node.birth,
                node.creators,
                node.detached_created,
                node.disposed,
                (() => {
                  let _record = node.storage;
                  return new StorageState(
                    _record.sequenced,
                    _record.insertion_order,
                    strip_storage_pending(node.storage.pending, message_id),
                  );
                })(),
                node.subdirectories,
                node.subdirectory_order,
                node.pending_subdirectories,
              ),
              undefined,
            ],
          );
        } else {
          return new Error(undefined);
        }
      },
    ];
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    _block = [
      path,
      (node) => {
        let $1 = remove_pending_subdirectory(
          node.pending_subdirectories,
          name,
          message_id,
          true,
        );
        if ($1 instanceof Ok) {
          let rest = $1[0];
          return new Ok(
            [
              new DirectoryNode(
                node.path,
                node.create,
                node.birth,
                node.creators,
                node.detached_created,
                node.disposed,
                node.storage,
                node.subdirectories,
                node.subdirectory_order,
                rest,
              ),
              undefined,
            ],
          );
        } else {
          return new Error(undefined);
        }
      },
    ];
  } else {
    let path = operation.path;
    let name = operation.name;
    _block = [
      path,
      (node) => {
        let $1 = remove_pending_subdirectory(
          node.pending_subdirectories,
          name,
          message_id,
          false,
        );
        if ($1 instanceof Ok) {
          let rest = $1[0];
          return new Ok(
            [
              new DirectoryNode(
                node.path,
                node.create,
                node.birth,
                node.creators,
                node.detached_created,
                node.disposed,
                node.storage,
                node.subdirectories,
                node.subdirectory_order,
                rest,
              ),
              undefined,
            ],
          );
        } else {
          return new Error(undefined);
        }
      },
    ];
  }
  let $ = _block;
  let path = $[0];
  let mutate = $[1];
  let $1 = update_retained_instance(state.root, segments(path), mutate);
  if ($1 instanceof Ok) {
    let root = $1[0][0];
    return new DirectoryState(root, state.next_message_id);
  } else {
    return state;
  }
}

/**
 * The most recent pending create entry for `name`, and the function skips a
 * later pending remove. FluidFramework uses `findLast` in
 * `resubmitSubDirectoryMessage`.
 * 
 * @ignore
 */
function find_latest_pending_create(pending, name) {
  let _pipe = $list.reverse(pending);
  return $list.find_map(
    _pipe,
    (entry) => {
      if (entry instanceof PendingCreate) {
        let n = entry.name;
        if (n === name) {
          let node = entry.node;
          let folded = entry.folded;
          return new Ok([node, folded]);
        } else {
          return new Error(undefined);
        }
      } else {
        return new Error(undefined);
      }
    },
  );
}

/**
 * Whether the pending storage of this node still holds the pending entry of
 * `operation`. This is the check in `resubmitKeyMessage` and
 * `resubmitClearMessage` of FluidFramework. A set checks the identity of the
 * submission, which is `keySets.includes(localOpMetadata)` in FluidFramework
 * and the message id here. A delete and a clear match by their kind, and by
 * their key, only.
 * 
 * @ignore
 */
function storage_pending_matches(pending, operation, message_id) {
  return $list.any(
    pending,
    (entry) => {
      if (operation instanceof Set) {
        let key = operation.key;
        if (entry instanceof PendingLifetime) {
          let k = entry.key;
          let ids = entry.message_ids;
          return (k === key) && $list.contains(ids, message_id);
        } else if (entry instanceof PendingDelete) {
          return false;
        } else {
          return false;
        }
      } else if (operation instanceof Delete) {
        let key = operation.key;
        if (entry instanceof PendingLifetime) {
          return false;
        } else if (entry instanceof PendingDelete) {
          let k = entry.key;
          return k === key;
        } else {
          return false;
        }
      } else if (operation instanceof Clear) {
        if (entry instanceof PendingLifetime) {
          return false;
        } else if (entry instanceof PendingDelete) {
          return false;
        } else {
          return true;
        }
      } else if (operation instanceof CreateSubDirectory) {
        return false;
      } else {
        return false;
      }
    },
  );
}

/**
 * The routing of the `reSubmitCore` function of FluidFramework, which is D14.
 * Decide whether the pending operation behind `operation` and `message_id` is
 * still worth a resubmit, and apply the state effects that FluidFramework
 * applies at resubmit time.
 *
 * The function finds each target on the *retained instance*. The traversal
 * includes a disposed marker alias, because the `localOpMetadata` value of
 * FluidFramework holds the object itself, and not a path. The function then
 * checks `!targetSubdir.disposed`, and it checks the pending entry, the same
 * as `resubmitKeyMessage` and `resubmitSubDirectoryMessage`.
 *
 * A resubmit of a create records the current client id as a creator, and it
 * undisposes the retained pending tree. A storage operation that is *after*
 * that create in the same reconnect batch thus finds its target alive, and it
 * resubmits too. To drop such an operation while its pending entry stays on
 * the retained node would leave a pending entry that never receives an ack,
 * and that only this client can see.
 *
 * When the function DOES drop an operation, it also removes the pending entry
 * of that operation from the retained instance. See `strip_dropped_pending`.
 * This is one deliberate difference from FluidFramework, which keeps the entry
 * on the disposed object. That operation will never sequence. If a later
 * create ack revives the retained instance, the entry that remains appears as
 * an optimistic edit that no other client sees. To drop the operation and its
 * pending entry together thus keeps the revive convergent.
 */
export function resubmit(state, operation, message_id, self) {
  if (operation instanceof Set) {
    let path = operation.path;
    let locate = (node) => {
      let $ = (!node.disposed && $list.contains(
        storage_pending_ids(node.storage),
        message_id,
      )) && storage_pending_matches(node.storage.pending, operation, message_id);
      if ($) {
        return new Ok([node, undefined]);
      } else {
        return new Error(undefined);
      }
    };
    let $ = update_retained_instance(state.root, segments(path), locate);
    if ($ instanceof Ok) {
      return [state, new Some(operation)];
    } else {
      return [
        strip_dropped_pending(state, operation, message_id),
        Option$None$const,
      ];
    }
  } else if (operation instanceof Delete) {
    let path = operation.path;
    let locate = (node) => {
      let $ = (!node.disposed && $list.contains(
        storage_pending_ids(node.storage),
        message_id,
      )) && storage_pending_matches(node.storage.pending, operation, message_id);
      if ($) {
        return new Ok([node, undefined]);
      } else {
        return new Error(undefined);
      }
    };
    let $ = update_retained_instance(state.root, segments(path), locate);
    if ($ instanceof Ok) {
      return [state, new Some(operation)];
    } else {
      return [
        strip_dropped_pending(state, operation, message_id),
        Option$None$const,
      ];
    }
  } else if (operation instanceof Clear) {
    let path = operation.path;
    let locate = (node) => {
      let $ = (!node.disposed && $list.contains(
        storage_pending_ids(node.storage),
        message_id,
      )) && storage_pending_matches(node.storage.pending, operation, message_id);
      if ($) {
        return new Ok([node, undefined]);
      } else {
        return new Error(undefined);
      }
    };
    let $ = update_retained_instance(state.root, segments(path), locate);
    if ($ instanceof Ok) {
      return [state, new Some(operation)];
    } else {
      return [
        strip_dropped_pending(state, operation, message_id),
        Option$None$const,
      ];
    }
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    let revive = (node) => {
      let owns_marker = $list.any(
        node.pending_subdirectories,
        (entry) => {
          if (entry instanceof PendingCreate) {
            let n = entry.name;
            let id = entry.message_id;
            return (n === name) && (id === message_id);
          } else {
            return false;
          }
        },
      );
      let $ = !node.disposed && owns_marker;
      if ($) {
        let $1 = find_latest_pending_create(node.pending_subdirectories, name);
        if ($1 instanceof Ok) {
          let marker_node = $1[0][0];
          let folded = $1[0][1];
          let slot_aliased = folded && (() => {
            let $2 = $dict.get(node.subdirectories, name);
            if ($2 instanceof Ok) {
              let live = $2[0];
              return isEqual(live.birth, marker_node.birth);
            } else {
              return false;
            }
          })();
          let _block;
          if (slot_aliased) {
            let $2 = $dict.get(node.subdirectories, name);
            if ($2 instanceof Ok) {
              let live = $2[0];
              _block = live;
            } else {
              _block = marker_node;
            }
          } else {
            _block = marker_node;
          }
          let child = _block;
          let child$1 = new DirectoryNode(
            child.path,
            child.create,
            child.birth,
            add_creator(child.creators, self),
            child.detached_created,
            child.disposed,
            child.storage,
            child.subdirectories,
            child.subdirectory_order,
            child.pending_subdirectories,
          );
          let $2 = undispose_tree(child$1);
          let child$2 = $2[0];
          let _block$1;
          if (slot_aliased) {
            _block$1 = put_sequenced_child(node, name, child$2);
          } else {
            _block$1 = node;
          }
          let node$1 = _block$1;
          return new Ok(
            [
              new DirectoryNode(
                node$1.path,
                node$1.create,
                node$1.birth,
                node$1.creators,
                node$1.detached_created,
                node$1.disposed,
                node$1.storage,
                node$1.subdirectories,
                node$1.subdirectory_order,
                replace_latest_pending_create(
                  node$1.pending_subdirectories,
                  name,
                  child$2,
                ),
              ),
              undefined,
            ],
          );
        } else {
          return $1;
        }
      } else {
        return new Error(undefined);
      }
    };
    let $ = update_retained_instance(state.root, segments(path), revive);
    if ($ instanceof Ok) {
      let root = $[0][0];
      return [
        new DirectoryState(root, state.next_message_id),
        new Some(operation),
      ];
    } else {
      return [
        strip_dropped_pending(state, operation, message_id),
        Option$None$const,
      ];
    }
  } else {
    let path = operation.path;
    let name = operation.name;
    let locate = (node) => {
      let owns_remove = $list.any(
        node.pending_subdirectories,
        (entry) => {
          if (entry instanceof PendingCreate) {
            return false;
          } else {
            let n = entry.name;
            let id = entry.message_id;
            return (n === name) && (id === message_id);
          }
        },
      );
      let $ = !node.disposed && owns_remove;
      if ($) {
        return new Ok([node, undefined]);
      } else {
        return new Error(undefined);
      }
    };
    let $ = update_retained_instance(state.root, segments(path), locate);
    if ($ instanceof Ok) {
      return [state, new Some(operation)];
    } else {
      return [
        strip_dropped_pending(state, operation, message_id),
        Option$None$const,
      ];
    }
  }
}

function some_operation(r) {
  return $result.map(
    r,
    (tuple) => {
      let state = tuple[0];
      let events = tuple[1];
      let operation = tuple[2];
      let id = tuple[3];
      return [state, events, new Some(operation), id];
    },
  );
}

export function apply_stashed_operation(state, operation, self) {
  if (operation instanceof Set) {
    let path = operation.path;
    let key = operation.key;
    let value = operation.value;
    return some_operation(set(state, path, key, value));
  } else if (operation instanceof Delete) {
    let path = operation.path;
    let key = operation.key;
    return some_operation(delete$(state, path, key));
  } else if (operation instanceof Clear) {
    let path = operation.path;
    return some_operation(clear(state, path));
  } else if (operation instanceof CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    return create_subdirectory(state, path, name, self);
  } else {
    let path = operation.path;
    let name = operation.name;
    return delete_subdirectory(state, path, name);
  }
}

function summary_node(node) {
  let storage = $list.filter_map(
    node.storage.insertion_order,
    (key) => {
      let $ = $dict.get(node.storage.sequenced, key);
      if ($ instanceof Ok) {
        let value = $[0];
        return new Ok([key, value]);
      } else {
        return new Error(undefined);
      }
    },
  );
  let subdirectories$1 = $list.filter_map(
    node.subdirectory_order,
    (name) => {
      let $ = $dict.get(node.subdirectories, name);
      if ($ instanceof Ok) {
        let child = $[0];
        return new Ok([name, summary_node(child)]);
      } else {
        return new Error(undefined);
      }
    },
  );
  return new DirectorySummary(
    storage,
    node.create,
    node.creators,
    node.detached_created,
    subdirectories$1,
  );
}

export function summary_tree(state) {
  return summary_node(state.root);
}

function load_node(path, summary) {
  let $ = $list.fold(
    summary.storage,
    [$dict.new$(), $List$Empty$const],
    (acc, entry) => {
      let d = acc[0];
      let o = acc[1];
      let key = entry[0];
      let value = entry[1];
      let _block;
      let $1 = $dict.has_key(d, key);
      if ($1) {
        _block = o;
      } else {
        _block = listPrepend(key, o);
      }
      let o$1 = _block;
      return [$dict.insert(d, key, value), o$1];
    },
  );
  let sequenced = $[0];
  let order = $[1];
  let $1 = $list.fold(
    summary.subdirectories,
    [$dict.new$(), $List$Empty$const],
    (acc, entry) => {
      let d = acc[0];
      let o = acc[1];
      let name = entry[0];
      let child_summary = entry[1];
      let child = load_node(join(path, name), child_summary);
      return [$dict.insert(d, name, child), listPrepend(name, o)];
    },
  );
  let subdirectories$1 = $1[0];
  let subdirectory_order = $1[1];
  return new DirectoryNode(
    path,
    summary.create,
    summary.create,
    summary.creators,
    summary.detached_created,
    false,
    new StorageState(sequenced, $list.reverse(order), $List$Empty$const),
    subdirectories$1,
    $list.reverse(subdirectory_order),
    $List$Empty$const,
  );
}

export function from_summary(summary) {
  return new DirectoryState(load_node("/", summary), 0);
}

function check_node(node) {
  let path_ok = $list.all(
    $dict.to_list(node.subdirectories),
    (pair) => {
      let name = pair[0];
      let child = pair[1];
      return child.path === join(node.path, name);
    },
  );
  if (path_ok) {
    let visible = optimistic_subdirectory_names(node);
    let $ = $list.length(visible) === $list.length($list.unique(visible));
    if ($) {
      return $list.try_fold(
        $dict.values(node.subdirectories),
        undefined,
        (_, child) => { return check_node(child); },
      );
    } else {
      return new Error(
        new InvariantViolation("duplicate visible child under " + node.path),
      );
    }
  } else {
    return new Error(
      new InvariantViolation("child path mismatch under " + node.path),
    );
  }
}

export function check_invariants(state) {
  return check_node(state.root);
}
