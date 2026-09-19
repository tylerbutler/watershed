/// <reference types="./register_collection_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, toList, CustomType as $CustomType } from "../gleam.mjs";

export class RegisterState extends $CustomType {
  constructor(registers) {
    super();
    this.registers = registers;
  }
}
export const RegisterState$RegisterState = (registers) =>
  new RegisterState(registers);
export const RegisterState$isRegisterState = (value) =>
  value instanceof RegisterState;
export const RegisterState$RegisterState$registers = (value) => value.registers;
export const RegisterState$RegisterState$0 = (value) => value.registers;

/**
 * `atomic` is the linearizable winner. `versions` contains every value that
 * is still concurrent, in sequence order, oldest first. An invariant keeps
 * `versions` non-empty.
 */
export class Register extends $CustomType {
  constructor(atomic, versions) {
    super();
    this.atomic = atomic;
    this.versions = versions;
  }
}
export const Register$Register = (atomic, versions) =>
  new Register(atomic, versions);
export const Register$isRegister = (value) => value instanceof Register;
export const Register$Register$atomic = (value) => value.atomic;
export const Register$Register$0 = (value) => value.atomic;
export const Register$Register$versions = (value) => value.versions;
export const Register$Register$1 = (value) => value.versions;

export class VersionedValue extends $CustomType {
  constructor(value, sequence_number) {
    super();
    this.value = value;
    this.sequence_number = sequence_number;
  }
}
export const VersionedValue$VersionedValue = (value, sequence_number) =>
  new VersionedValue(value, sequence_number);
export const VersionedValue$isVersionedValue = (value) =>
  value instanceof VersionedValue;
export const VersionedValue$VersionedValue$value = (value) => value.value;
export const VersionedValue$VersionedValue$0 = (value) => value.value;
export const VersionedValue$VersionedValue$sequence_number = (value) =>
  value.sequence_number;
export const VersionedValue$VersionedValue$1 = (value) => value.sequence_number;

export class Write extends $CustomType {
  constructor(key, value, reference_sequence_number) {
    super();
    this.key = key;
    this.value = value;
    this.reference_sequence_number = reference_sequence_number;
  }
}
export const WriteOperation$Write = (key, value, reference_sequence_number) =>
  new Write(key, value, reference_sequence_number);
export const WriteOperation$isWrite = (value) => value instanceof Write;
export const WriteOperation$Write$key = (value) => value.key;
export const WriteOperation$Write$0 = (value) => value.key;
export const WriteOperation$Write$value = (value) => value.value;
export const WriteOperation$Write$1 = (value) => value.value;
export const WriteOperation$Write$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const WriteOperation$Write$2 = (value) =>
  value.reference_sequence_number;

/**
 * The kernel emits this event only when the atomic (linearizable) value
 * changes.
 */
export class AtomicChanged extends $CustomType {
  constructor(key, value, local) {
    super();
    this.key = key;
    this.value = value;
    this.local = local;
  }
}
export const RegisterEvent$AtomicChanged = (key, value, local) =>
  new AtomicChanged(key, value, local);
export const RegisterEvent$isAtomicChanged = (value) =>
  value instanceof AtomicChanged;
export const RegisterEvent$AtomicChanged$key = (value) => value.key;
export const RegisterEvent$AtomicChanged$0 = (value) => value.key;
export const RegisterEvent$AtomicChanged$value = (value) => value.value;
export const RegisterEvent$AtomicChanged$1 = (value) => value.value;
export const RegisterEvent$AtomicChanged$local = (value) => value.local;
export const RegisterEvent$AtomicChanged$2 = (value) => value.local;

/**
 * The kernel emits this event for every sequenced write, including a write
 * that does not win the atomic slot.
 */
export class VersionChanged extends $CustomType {
  constructor(key, value, local) {
    super();
    this.key = key;
    this.value = value;
    this.local = local;
  }
}
export const RegisterEvent$VersionChanged = (key, value, local) =>
  new VersionChanged(key, value, local);
export const RegisterEvent$isVersionChanged = (value) =>
  value instanceof VersionChanged;
export const RegisterEvent$VersionChanged$key = (value) => value.key;
export const RegisterEvent$VersionChanged$0 = (value) => value.key;
export const RegisterEvent$VersionChanged$value = (value) => value.value;
export const RegisterEvent$VersionChanged$1 = (value) => value.value;
export const RegisterEvent$VersionChanged$local = (value) => value.local;
export const RegisterEvent$VersionChanged$2 = (value) => value.local;

export const RegisterEvent$key = (value) => value.key;
export const RegisterEvent$local = (value) => value.local;
export const RegisterEvent$value = (value) => value.value;

export class Atomic extends $CustomType {}
export const ReadPolicy$Atomic$const = new Atomic();
export const ReadPolicy$Atomic = () => ReadPolicy$Atomic$const;
export const ReadPolicy$isAtomic = (value) => value instanceof Atomic;

export class Lww extends $CustomType {}
export const ReadPolicy$Lww$const = new Lww();
export const ReadPolicy$Lww = () => ReadPolicy$Lww$const;
export const ReadPolicy$isLww = (value) => value instanceof Lww;

export function new$() {
  return new RegisterState($dict.new$());
}

/**
 * Build the committed state from the summary entries. The summary contains
 * the sequence numbers, so the atomic compare-and-set and the version pruning
 * continue to work after a load.
 */
export function from_summary(entries) {
  let registers = $list.fold(
    entries,
    $dict.new$(),
    (acc, entry) => {
      let key = entry[0];
      let register = entry[1];
      return $dict.insert(acc, key, register);
    },
  );
  return new RegisterState(registers);
}

/**
 * The summary entries in a stable order, sorted by key.
 */
export function summary_registers(state) {
  let _pipe = $dict.to_list(state.registers);
  return $list.sort(_pipe, (a, b) => { return $string.compare(a[0], b[0]); });
}

/**
 * The committed value for `key` under `policy`. The result is `Error(Nil)` if
 * the key has no sequenced data. This read gives committed data only, and a
 * pending local write is not visible.
 */
export function read(state, key, policy) {
  let $ = $dict.get(state.registers, key);
  if ($ instanceof Ok) {
    let atomic = $[0].atomic;
    let versions = $[0].versions;
    if (policy instanceof Atomic) {
      return new Ok(atomic.value);
    } else {
      let $1 = $list.last(versions);
      if ($1 instanceof Ok) {
        let value = $1[0].value;
        return new Ok(value);
      } else {
        return $1;
      }
    }
  } else {
    return $;
  }
}

/**
 * Every committed version for `key`, oldest first. The result is `Error(Nil)`
 * if the key is absent.
 */
export function read_versions(state, key) {
  let $ = $dict.get(state.registers, key);
  if ($ instanceof Ok) {
    let versions = $[0].versions;
    return new Ok($list.map(versions, (version) => { return version.value; }));
  } else {
    return $;
  }
}

export function keys(state) {
  let _pipe = $dict.keys(state.registers);
  return $list.sort(_pipe, $string.compare);
}

/**
 * The attached submit path. Build an operation with the last-seen sequence
 * number that the runtime supplies. The state does not change, because a read
 * is not optimistic.
 */
export function write(_, key, value, last_seen_sequence_number) {
  return new Write(key, value, last_seen_sequence_number);
}

function apply_write(
  state,
  key,
  value,
  reference_sequence_number,
  sequence_number,
  local
) {
  let new_version = new VersionedValue(value, sequence_number);
  let _block;
  let $1 = $dict.get(state.registers, key);
  if ($1 instanceof Ok) {
    let atomic = $1[0].atomic;
    let versions = $1[0].versions;
    let is_winner = reference_sequence_number >= atomic.sequence_number;
    let _block$1;
    if (is_winner) {
      _block$1 = new_version;
    } else {
      _block$1 = atomic;
    }
    let atomic$1 = _block$1;
    let _block$2;
    let _pipe = versions;
    let _pipe$1 = $list.drop_while(
      _pipe,
      (version) => {
        return version.sequence_number <= reference_sequence_number;
      },
    );
    _block$2 = $list.append(_pipe$1, toList([new_version]));
    let versions$1 = _block$2;
    _block = [new Register(atomic$1, versions$1), is_winner];
  } else {
    _block = [new Register(new_version, toList([new_version])), true];
  }
  let $ = _block;
  let register = $[0];
  let is_winner = $[1];
  let state$1 = new RegisterState($dict.insert(state.registers, key, register));
  let _block$1;
  if (is_winner) {
    _block$1 = toList([
      new AtomicChanged(key, value, local),
      new VersionChanged(key, value, local),
    ]);
  } else {
    _block$1 = toList([new VersionChanged(key, value, local)]);
  }
  let events = _block$1;
  return [state$1, is_winner, events];
}

/**
 * The detached apply path. There is no sequencer yet, so
 * `reference_sequence_number` and `sequence_number` are both zero.
 */
export function write_detached(state, key, value) {
  let $ = apply_write(state, key, value, 0, 0, true);
  let state$1 = $[0];
  let events = $[2];
  return [state$1, events];
}

export function apply_remote(state, operation, sequence_number) {
  let $ = apply_write(
    state,
    operation.key,
    operation.value,
    operation.reference_sequence_number,
    sequence_number,
    false,
  );
  let state$1 = $[0];
  let events = $[2];
  return [state$1, events];
}

export function ack_local(state, operation, sequence_number) {
  let $ = apply_write(
    state,
    operation.key,
    operation.value,
    operation.reference_sequence_number,
    sequence_number,
    true,
  );
  let state$1 = $[0];
  let is_winner = $[1];
  let events = $[2];
  return [state$1, events, is_winner];
}

/**
 * A rollback resolves the deferred write result as false. There is no pending
 * kernel state to undo, because a write is not visible until its ack.
 */
export function rollback(state, _) {
  return [state, false];
}

/**
 * The kernel resubmits a stashed operation without a change. In particular, it
 * keeps `reference_sequence_number`.
 */
export function apply_stashed_operation(state, operation) {
  return [state, operation];
}
