/// <reference types="./or_map_kernel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.mjs";
import * as $crdt from "../../lattice_maps/lattice_maps/crdt.mjs";
import * as $or_map from "../../lattice_maps/lattice_maps/or_map.mjs";
import * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.mjs";
import * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.mjs";
import * as $or_set from "../../lattice_sets/lattice_sets/or_set.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  makeError,
  isEqual,
} from "../gleam.mjs";
import * as $canonical_json from "../watershed/canonical_json.mjs";
import * as $mv_register_kernel from "../watershed/mv_register_kernel.mjs";
import * as $or_map_set_leaf from "../watershed/or_map_set_leaf.mjs";

const FILEPATH = "src/watershed/or_map_kernel.gleam";

export class TallyMode extends $CustomType {}
export const OrMapMode$TallyMode$const = new TallyMode();
export const OrMapMode$TallyMode = () => OrMapMode$TallyMode$const;
export const OrMapMode$isTallyMode = (value) => value instanceof TallyMode;

export class RegisterMode extends $CustomType {}
export const OrMapMode$RegisterMode$const = new RegisterMode();
export const OrMapMode$RegisterMode = () => OrMapMode$RegisterMode$const;
export const OrMapMode$isRegisterMode = (value) =>
  value instanceof RegisterMode;

export class OrSetMode extends $CustomType {}
export const OrMapMode$OrSetMode$const = new OrSetMode();
export const OrMapMode$OrSetMode = () => OrMapMode$OrSetMode$const;
export const OrMapMode$isOrSetMode = (value) => value instanceof OrSetMode;

export class MvRegisterMode extends $CustomType {}
export const OrMapMode$MvRegisterMode$const = new MvRegisterMode();
export const OrMapMode$MvRegisterMode = () => OrMapMode$MvRegisterMode$const;
export const OrMapMode$isMvRegisterMode = (value) =>
  value instanceof MvRegisterMode;

export class Tally extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const OrMapValue$Tally = ($0) => new Tally($0);
export const OrMapValue$isTally = (value) => value instanceof Tally;
export const OrMapValue$Tally$0 = (value) => value[0];

export class Register extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const OrMapValue$Register = ($0) => new Register($0);
export const OrMapValue$isRegister = (value) => value instanceof Register;
export const OrMapValue$Register$0 = (value) => value[0];

export class SetMembers extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const OrMapValue$SetMembers = ($0) => new SetMembers($0);
export const OrMapValue$isSetMembers = (value) => value instanceof SetMembers;
export const OrMapValue$SetMembers$0 = (value) => value[0];

export class MvRegister extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const OrMapValue$MvRegister = ($0) => new MvRegister($0);
export const OrMapValue$isMvRegister = (value) => value instanceof MvRegister;
export const OrMapValue$MvRegister$0 = (value) => value[0];

export class OrMapState extends $CustomType {
  constructor(replica_id, mode, sequenced, optimistic, authored, own_tallies, authored_mv_registers, register_clock, set_clocks, pending, next_pending_message_id) {
    super();
    this.replica_id = replica_id;
    this.mode = mode;
    this.sequenced = sequenced;
    this.optimistic = optimistic;
    this.authored = authored;
    this.own_tallies = own_tallies;
    this.authored_mv_registers = authored_mv_registers;
    this.register_clock = register_clock;
    this.set_clocks = set_clocks;
    this.pending = pending;
    this.next_pending_message_id = next_pending_message_id;
  }
}
export const OrMapState$OrMapState = (replica_id, mode, sequenced, optimistic, authored, own_tallies, authored_mv_registers, register_clock, set_clocks, pending, next_pending_message_id) =>
  new OrMapState(replica_id,
  mode,
  sequenced,
  optimistic,
  authored,
  own_tallies,
  authored_mv_registers,
  register_clock,
  set_clocks,
  pending,
  next_pending_message_id);
export const OrMapState$isOrMapState = (value) => value instanceof OrMapState;
export const OrMapState$OrMapState$replica_id = (value) => value.replica_id;
export const OrMapState$OrMapState$0 = (value) => value.replica_id;
export const OrMapState$OrMapState$mode = (value) => value.mode;
export const OrMapState$OrMapState$1 = (value) => value.mode;
export const OrMapState$OrMapState$sequenced = (value) => value.sequenced;
export const OrMapState$OrMapState$2 = (value) => value.sequenced;
export const OrMapState$OrMapState$optimistic = (value) => value.optimistic;
export const OrMapState$OrMapState$3 = (value) => value.optimistic;
export const OrMapState$OrMapState$authored = (value) => value.authored;
export const OrMapState$OrMapState$4 = (value) => value.authored;
export const OrMapState$OrMapState$own_tallies = (value) => value.own_tallies;
export const OrMapState$OrMapState$5 = (value) => value.own_tallies;
export const OrMapState$OrMapState$authored_mv_registers = (value) =>
  value.authored_mv_registers;
export const OrMapState$OrMapState$6 = (value) => value.authored_mv_registers;
export const OrMapState$OrMapState$register_clock = (value) =>
  value.register_clock;
export const OrMapState$OrMapState$7 = (value) => value.register_clock;
export const OrMapState$OrMapState$set_clocks = (value) => value.set_clocks;
export const OrMapState$OrMapState$8 = (value) => value.set_clocks;
export const OrMapState$OrMapState$pending = (value) => value.pending;
export const OrMapState$OrMapState$9 = (value) => value.pending;
export const OrMapState$OrMapState$next_pending_message_id = (value) =>
  value.next_pending_message_id;
export const OrMapState$OrMapState$10 = (value) =>
  value.next_pending_message_id;

export class PendingOperation extends $CustomType {
  constructor(operation, message_id) {
    super();
    this.operation = operation;
    this.message_id = message_id;
  }
}
export const PendingOperation$PendingOperation = (operation, message_id) =>
  new PendingOperation(operation, message_id);
export const PendingOperation$isPendingOperation = (value) =>
  value instanceof PendingOperation;
export const PendingOperation$PendingOperation$operation = (value) =>
  value.operation;
export const PendingOperation$PendingOperation$0 = (value) => value.operation;
export const PendingOperation$PendingOperation$message_id = (value) =>
  value.message_id;
export const PendingOperation$PendingOperation$1 = (value) => value.message_id;

export class Increment extends $CustomType {
  constructor(key, amount, delta) {
    super();
    this.key = key;
    this.amount = amount;
    this.delta = delta;
  }
}
export const OrMapOperation$Increment = (key, amount, delta) =>
  new Increment(key, amount, delta);
export const OrMapOperation$isIncrement = (value) => value instanceof Increment;
export const OrMapOperation$Increment$key = (value) => value.key;
export const OrMapOperation$Increment$0 = (value) => value.key;
export const OrMapOperation$Increment$amount = (value) => value.amount;
export const OrMapOperation$Increment$1 = (value) => value.amount;
export const OrMapOperation$Increment$delta = (value) => value.delta;
export const OrMapOperation$Increment$2 = (value) => value.delta;

export class SetRegister extends $CustomType {
  constructor(key, value, timestamp, delta) {
    super();
    this.key = key;
    this.value = value;
    this.timestamp = timestamp;
    this.delta = delta;
  }
}
export const OrMapOperation$SetRegister = (key, value, timestamp, delta) =>
  new SetRegister(key, value, timestamp, delta);
export const OrMapOperation$isSetRegister = (value) =>
  value instanceof SetRegister;
export const OrMapOperation$SetRegister$key = (value) => value.key;
export const OrMapOperation$SetRegister$0 = (value) => value.key;
export const OrMapOperation$SetRegister$value = (value) => value.value;
export const OrMapOperation$SetRegister$1 = (value) => value.value;
export const OrMapOperation$SetRegister$timestamp = (value) => value.timestamp;
export const OrMapOperation$SetRegister$2 = (value) => value.timestamp;
export const OrMapOperation$SetRegister$delta = (value) => value.delta;
export const OrMapOperation$SetRegister$3 = (value) => value.delta;

export class SetMvRegister extends $CustomType {
  constructor(key, value, delta) {
    super();
    this.key = key;
    this.value = value;
    this.delta = delta;
  }
}
export const OrMapOperation$SetMvRegister = (key, value, delta) =>
  new SetMvRegister(key, value, delta);
export const OrMapOperation$isSetMvRegister = (value) =>
  value instanceof SetMvRegister;
export const OrMapOperation$SetMvRegister$key = (value) => value.key;
export const OrMapOperation$SetMvRegister$0 = (value) => value.key;
export const OrMapOperation$SetMvRegister$value = (value) => value.value;
export const OrMapOperation$SetMvRegister$1 = (value) => value.value;
export const OrMapOperation$SetMvRegister$delta = (value) => value.delta;
export const OrMapOperation$SetMvRegister$2 = (value) => value.delta;

export class Remove extends $CustomType {
  constructor(key, delta) {
    super();
    this.key = key;
    this.delta = delta;
  }
}
export const OrMapOperation$Remove = (key, delta) => new Remove(key, delta);
export const OrMapOperation$isRemove = (value) => value instanceof Remove;
export const OrMapOperation$Remove$key = (value) => value.key;
export const OrMapOperation$Remove$0 = (value) => value.key;
export const OrMapOperation$Remove$delta = (value) => value.delta;
export const OrMapOperation$Remove$1 = (value) => value.delta;

export class AddMember extends $CustomType {
  constructor(key, member, delta) {
    super();
    this.key = key;
    this.member = member;
    this.delta = delta;
  }
}
export const OrMapOperation$AddMember = (key, member, delta) =>
  new AddMember(key, member, delta);
export const OrMapOperation$isAddMember = (value) => value instanceof AddMember;
export const OrMapOperation$AddMember$key = (value) => value.key;
export const OrMapOperation$AddMember$0 = (value) => value.key;
export const OrMapOperation$AddMember$member = (value) => value.member;
export const OrMapOperation$AddMember$1 = (value) => value.member;
export const OrMapOperation$AddMember$delta = (value) => value.delta;
export const OrMapOperation$AddMember$2 = (value) => value.delta;

export class RemoveMember extends $CustomType {
  constructor(key, member, delta) {
    super();
    this.key = key;
    this.member = member;
    this.delta = delta;
  }
}
export const OrMapOperation$RemoveMember = (key, member, delta) =>
  new RemoveMember(key, member, delta);
export const OrMapOperation$isRemoveMember = (value) =>
  value instanceof RemoveMember;
export const OrMapOperation$RemoveMember$key = (value) => value.key;
export const OrMapOperation$RemoveMember$0 = (value) => value.key;
export const OrMapOperation$RemoveMember$member = (value) => value.member;
export const OrMapOperation$RemoveMember$1 = (value) => value.member;
export const OrMapOperation$RemoveMember$delta = (value) => value.delta;
export const OrMapOperation$RemoveMember$2 = (value) => value.delta;

export const OrMapOperation$key = (value) => value.key;

export class TallyUpdated extends $CustomType {
  constructor(key, applied, new_value) {
    super();
    this.key = key;
    this.applied = applied;
    this.new_value = new_value;
  }
}
export const OrMapEvent$TallyUpdated = (key, applied, new_value) =>
  new TallyUpdated(key, applied, new_value);
export const OrMapEvent$isTallyUpdated = (value) =>
  value instanceof TallyUpdated;
export const OrMapEvent$TallyUpdated$key = (value) => value.key;
export const OrMapEvent$TallyUpdated$0 = (value) => value.key;
export const OrMapEvent$TallyUpdated$applied = (value) => value.applied;
export const OrMapEvent$TallyUpdated$1 = (value) => value.applied;
export const OrMapEvent$TallyUpdated$new_value = (value) => value.new_value;
export const OrMapEvent$TallyUpdated$2 = (value) => value.new_value;

export class RegisterUpdated extends $CustomType {
  constructor(key, value) {
    super();
    this.key = key;
    this.value = value;
  }
}
export const OrMapEvent$RegisterUpdated = (key, value) =>
  new RegisterUpdated(key, value);
export const OrMapEvent$isRegisterUpdated = (value) =>
  value instanceof RegisterUpdated;
export const OrMapEvent$RegisterUpdated$key = (value) => value.key;
export const OrMapEvent$RegisterUpdated$0 = (value) => value.key;
export const OrMapEvent$RegisterUpdated$value = (value) => value.value;
export const OrMapEvent$RegisterUpdated$1 = (value) => value.value;

export class SetMembersUpdated extends $CustomType {
  constructor(key, members) {
    super();
    this.key = key;
    this.members = members;
  }
}
export const OrMapEvent$SetMembersUpdated = (key, members) =>
  new SetMembersUpdated(key, members);
export const OrMapEvent$isSetMembersUpdated = (value) =>
  value instanceof SetMembersUpdated;
export const OrMapEvent$SetMembersUpdated$key = (value) => value.key;
export const OrMapEvent$SetMembersUpdated$0 = (value) => value.key;
export const OrMapEvent$SetMembersUpdated$members = (value) => value.members;
export const OrMapEvent$SetMembersUpdated$1 = (value) => value.members;

export class MvRegisterUpdated extends $CustomType {
  constructor(key, values) {
    super();
    this.key = key;
    this.values = values;
  }
}
export const OrMapEvent$MvRegisterUpdated = (key, values) =>
  new MvRegisterUpdated(key, values);
export const OrMapEvent$isMvRegisterUpdated = (value) =>
  value instanceof MvRegisterUpdated;
export const OrMapEvent$MvRegisterUpdated$key = (value) => value.key;
export const OrMapEvent$MvRegisterUpdated$0 = (value) => value.key;
export const OrMapEvent$MvRegisterUpdated$values = (value) => value.values;
export const OrMapEvent$MvRegisterUpdated$1 = (value) => value.values;

export class KeyRemoved extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const OrMapEvent$KeyRemoved = (key) => new KeyRemoved(key);
export const OrMapEvent$isKeyRemoved = (value) => value instanceof KeyRemoved;
export const OrMapEvent$KeyRemoved$key = (value) => value.key;
export const OrMapEvent$KeyRemoved$0 = (value) => value.key;

export const OrMapEvent$key = (value) => value.key;

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

export class UnexpectedRollback extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$UnexpectedRollback = (detail) =>
  new UnexpectedRollback(detail);
export const KernelError$isUnexpectedRollback = (value) =>
  value instanceof UnexpectedRollback;
export const KernelError$UnexpectedRollback$detail = (value) => value.detail;
export const KernelError$UnexpectedRollback$0 = (value) => value.detail;

export class ModeMismatch extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$ModeMismatch = (detail) => new ModeMismatch(detail);
export const KernelError$isModeMismatch = (value) =>
  value instanceof ModeMismatch;
export const KernelError$ModeMismatch$detail = (value) => value.detail;
export const KernelError$ModeMismatch$0 = (value) => value.detail;

export class CorruptDelta extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$CorruptDelta = (detail) => new CorruptDelta(detail);
export const KernelError$isCorruptDelta = (value) =>
  value instanceof CorruptDelta;
export const KernelError$CorruptDelta$detail = (value) => value.detail;
export const KernelError$CorruptDelta$0 = (value) => value.detail;

export class InvalidSetState extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$InvalidSetState = (detail) =>
  new InvalidSetState(detail);
export const KernelError$isInvalidSetState = (value) =>
  value instanceof InvalidSetState;
export const KernelError$InvalidSetState$detail = (value) => value.detail;
export const KernelError$InvalidSetState$0 = (value) => value.detail;

export class CounterExhausted extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$CounterExhausted = (detail) =>
  new CounterExhausted(detail);
export const KernelError$isCounterExhausted = (value) =>
  value instanceof CounterExhausted;
export const KernelError$CounterExhausted$detail = (value) => value.detail;
export const KernelError$CounterExhausted$0 = (value) => value.detail;

/**
 * The own tally of this replica for one key moved below zero. Both halves
 * of a PN-counter are grow-only, so a count below zero is a broken state.
 */
export class NegativeTally extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const KernelError$NegativeTally = (detail) => new NegativeTally(detail);
export const KernelError$isNegativeTally = (value) =>
  value instanceof NegativeTally;
export const KernelError$NegativeTally$detail = (value) => value.detail;
export const KernelError$NegativeTally$0 = (value) => value.detail;

export const KernelError$detail = (value) => value.detail;

class KeyDelta extends $CustomType {
  constructor(author, counter, entries, tombstones, pruned) {
    super();
    this.author = author;
    this.counter = counter;
    this.entries = entries;
    this.tombstones = tombstones;
    this.pruned = pruned;
  }
}

export function mode_to_spec(mode) {
  if (mode instanceof TallyMode) {
    return $crdt.CrdtSpec$PnCounterSpec$const;
  } else if (mode instanceof RegisterMode) {
    return new $crdt.LwwRegisterSpec("");
  } else if (mode instanceof OrSetMode) {
    return $crdt.CrdtSpec$OrSetSpec$const;
  } else {
    return $crdt.CrdtSpec$MvRegisterSpec$const;
  }
}

export function spec_string_to_mode(spec) {
  if (spec === "pn_counter") {
    return new Ok(OrMapMode$TallyMode$const);
  } else if (spec === "lww_register") {
    return new Ok(OrMapMode$RegisterMode$const);
  } else if (spec === "or_set") {
    return new Ok(OrMapMode$OrSetMode$const);
  } else if (spec === "mv_register") {
    return new Ok(OrMapMode$MvRegisterMode$const);
  } else {
    return new Error(undefined);
  }
}

export function new$(replica_id, mode) {
  let empty = $or_map.new$(replica_id, mode_to_spec(mode));
  return new OrMapState(
    replica_id,
    mode,
    empty,
    empty,
    empty,
    $dict.new$(),
    $dict.new$(),
    $dict.new$(),
    $or_map_set_leaf.new_clocks(),
    $List$Empty$const,
    0,
  );
}

/**
 * Read a lattice value as a kernel value. The result is `Error(Nil)` for a
 * lattice value that no map mode holds. The value mode of the map keeps
 * such a value out, so this arm reports a broken map instead of a panic.
 * 
 * @ignore
 */
function crdt_to_value(value) {
  if (value instanceof $crdt.CrdtGCounter) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtPnCounter) {
    let counter = value[0];
    return new Ok(new Tally($pn_counter.value(counter)));
  } else if (value instanceof $crdt.CrdtLwwRegister) {
    let register = value[0];
    return new Ok(new Register($lww_register.value(register)));
  } else if (value instanceof $crdt.CrdtMvRegister) {
    let register = value[0];
    return new Ok(
      new MvRegister(
        (() => {
          let _pipe = $mv_register.value(register);
          return $list.sort(_pipe, $string.compare);
        })(),
      ),
    );
  } else if (value instanceof $crdt.CrdtGSet) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtTwoPSet) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtOrSet) {
    let members = value[0];
    return new Ok(
      new SetMembers(
        (() => {
          let _pipe = $or_set.value(members);
          let _pipe$1 = $set.to_list(_pipe);
          return $list.sort(_pipe$1, $canonical_json.compare);
        })(),
      ),
    );
  } else if (value instanceof $crdt.CrdtVersionVector) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtSequence) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtText) {
    return new Error(undefined);
  } else if (value instanceof $crdt.CrdtOrMap) {
    return new Error(undefined);
  } else {
    return new Error(undefined);
  }
}

function map_entries(map, mode) {
  let _pipe = $or_map.keys(map);
  let _pipe$1 = $list.sort(
    _pipe,
    (() => {
      if (mode instanceof TallyMode) {
        return $string.compare;
      } else if (mode instanceof RegisterMode) {
        return $string.compare;
      } else if (mode instanceof OrSetMode) {
        return $canonical_json.compare;
      } else {
        return $string.compare;
      }
    })(),
  );
  return $list.filter_map(
    _pipe$1,
    (key) => {
      let $ = $or_map.get(map, key);
      if ($ instanceof Ok) {
        let value = $[0];
        let _pipe$2 = crdt_to_value(value);
        return $result.map(_pipe$2, (value) => { return [key, value]; });
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function entries(state) {
  return map_entries(state.optimistic, state.mode);
}

export function keys(state) {
  let _pipe = entries(state);
  return $list.map(_pipe, (entry) => { return entry[0]; });
}

/**
 * The visible value for a key. The result is `Error(Nil)` when the map holds
 * no value for that key.
 */
export function get(state, key) {
  let $ = $or_map.get(state.optimistic, key);
  if ($ instanceof Ok) {
    let value = $[0];
    return crdt_to_value(value);
  } else {
    return new Error(undefined);
  }
}

export function sequenced_entries(state) {
  return map_entries(state.sequenced, state.mode);
}

/**
 * The visible tally for a key. The result is zero when the map holds no
 * tally there.
 * 
 * @ignore
 */
function tally_of(state, key) {
  let $ = get(state, key);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Tally) {
      let value = $1[0];
      return value;
    } else if ($1 instanceof Register) {
      return 0;
    } else if ($1 instanceof SetMembers) {
      return 0;
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}

function composition_error(error) {
  if (error instanceof $crdt.TypeMismatch) {
    return new CorruptDelta($string.inspect(error));
  } else if (error instanceof $crdt.SchemaMismatch) {
    return new CorruptDelta($string.inspect(error));
  } else if (error instanceof $crdt.AtKey) {
    let key = error.key;
    let cause = error.cause;
    let $ = composition_error(cause);
    if ($ instanceof CounterExhausted) {
      let detail = $.detail;
      return new CounterExhausted((key + ": ") + detail);
    } else {
      let other = $;
      return new CorruptDelta((key + ": ") + $string.inspect(other));
    }
  } else if (error instanceof $crdt.TimestampNotAdvanced) {
    return new CorruptDelta($string.inspect(error));
  } else if (error instanceof $crdt.ConflictingWrite) {
    return new CorruptDelta($string.inspect(error));
  } else if (error instanceof $crdt.ClockExhausted) {
    let key = error.key;
    return new CounterExhausted("OR-map clock exhausted: " + key);
  } else {
    return new CorruptDelta($string.inspect(error));
  }
}

function apply_legacy_delta(map, delta) {
  let $ = $or_map.apply_delta(map, delta);
  if ($ instanceof Ok) {
    return $;
  } else {
    let $1 = $[0];
    if ($1 instanceof $crdt.TypeMismatch) {
      let expected = $1.expected;
      let found = $1.found;
      return new Error(
        new CorruptDelta((("expected " + expected) + " delta, found ") + found),
      );
    } else {
      let error = $1;
      return new Error(composition_error(error));
    }
  }
}

function set_error(error) {
  if (error instanceof $or_map_set_leaf.InvalidState) {
    let detail = error.detail;
    return new InvalidSetState(detail);
  } else {
    let detail = error.detail;
    return new CounterExhausted(detail);
  }
}

function spec_to_mode(spec) {
  if (spec instanceof $crdt.GCounterSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else if (spec instanceof $crdt.PnCounterSpec) {
    return new Ok(OrMapMode$TallyMode$const);
  } else if (spec instanceof $crdt.LwwRegisterSpec) {
    let $ = spec.initial_value;
    if ($ === "") {
      return new Ok(OrMapMode$RegisterMode$const);
    } else {
      return new Error(
        new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
      );
    }
  } else if (spec instanceof $crdt.MvRegisterSpec) {
    return new Ok(OrMapMode$MvRegisterMode$const);
  } else if (spec instanceof $crdt.GSetSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else if (spec instanceof $crdt.TwoPSetSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else if (spec instanceof $crdt.OrSetSpec) {
    return new Ok(OrMapMode$OrSetMode$const);
  } else if (spec instanceof $crdt.SequenceSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else if (spec instanceof $crdt.TextSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else if (spec instanceof $crdt.OrMapSpec) {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  } else {
    return new Error(
      new ModeMismatch("unsupported map value spec: " + $string.inspect(spec)),
    );
  }
}

function native_mode(map) {
  return spec_to_mode($or_map.spec(map));
}

function apply_delta(map, delta) {
  return $result.try$(
    native_mode(map),
    (mode) => {
      if (mode instanceof TallyMode) {
        return apply_legacy_delta(map, delta);
      } else if (mode instanceof RegisterMode) {
        return apply_legacy_delta(map, delta);
      } else if (mode instanceof OrSetMode) {
        return $result.try$(
          (() => {
            let _pipe = $or_map_set_leaf.validate_state(map);
            return $result.map_error(_pipe, set_error);
          })(),
          (_) => {
            return $result.try$(
              (() => {
                let _pipe = $or_map_set_leaf.decode_delta(
                  (() => {
                    let _pipe = $or_map.delta_to_json(delta);
                    return $json.to_string(_pipe);
                  })(),
                );
                return $result.map_error(_pipe, set_error);
              })(),
              (_) => {
                let _pipe = $or_map_set_leaf.apply_delta(map, delta);
                return $result.map_error(_pipe, set_error);
              },
            );
          },
        );
      } else {
        return apply_legacy_delta(map, delta);
      }
    },
  );
}

/**
 * Keep the key counter above all issued and observed tags. The authored map
 * can contain rolled-back values, so only its sparse delta updates the view.
 * 
 * @ignore
 */
function update_with_delta(state, key, value) {
  return $result.try$(
    (() => {
      let _pipe = $or_map.merge(state.authored, state.optimistic);
      return $result.replace_error(
        _pipe,
        new ModeMismatch("authored map has a different mode"),
      );
    })(),
    (map) => {
      let $ = $or_map.update_with_delta(map, key, (_) => { return value; });
      if ($ instanceof Ok) {
        return $;
      } else {
        let $1 = $[0];
        if ($1 instanceof $crdt.TypeMismatch) {
          let expected = $1.expected;
          let found = $1.found;
          return new Error(
            new ModeMismatch(
              (("expected " + expected) + " value, found ") + found,
            ),
          );
        } else {
          let error = $1;
          return new Error(composition_error(error));
        }
      }
    },
  );
}

/**
 * Build the PN-counter leaf that holds the own tally of this replica for one
 * key. Both counts are magnitudes, so both must be zero or more.
 * 
 * @ignore
 */
function own_tally_counter(replica_id, positive, negative) {
  return $result.try$(
    (() => {
      let _pipe = $pn_counter.new$(replica_id);
      let _pipe$1 = $pn_counter.increment(_pipe, positive);
      return $result.replace_error(
        _pipe$1,
        new NegativeTally("positive tally is " + $int.to_string(positive)),
      );
    })(),
    (counter) => {
      let _pipe = $pn_counter.decrement(counter, negative);
      return $result.replace_error(
        _pipe,
        new NegativeTally("negative tally is " + $int.to_string(negative)),
      );
    },
  );
}

export function increment(state, key, amount) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    let _block;
    let _pipe = $dict.get(state.own_tallies, key);
    _block = $result.unwrap(_pipe, [0, 0]);
    let $1 = _block;
    let positive = $1[0];
    let negative = $1[1];
    let _block$1;
    let $3 = amount >= 0;
    if ($3) {
      _block$1 = [positive + amount, negative];
    } else {
      _block$1 = [positive, negative + (0 - amount)];
    }
    let $2 = _block$1;
    let new_positive = $2[0];
    let new_negative = $2[1];
    return $result.try$(
      own_tally_counter(state.replica_id, new_positive, new_negative),
      (own_counter) => {
        return $result.try$(
          update_with_delta(state, key, new $crdt.CrdtPnCounter(own_counter)),
          (_use0) => {
            let authored = _use0[0];
            let delta = _use0[1];
            return $result.try$(
              apply_delta(state.optimistic, delta),
              (optimistic) => {
                let message_id = state.next_pending_message_id;
                let operation = new Increment(key, amount, delta);
                let new_state = new OrMapState(
                  state.replica_id,
                  state.mode,
                  state.sequenced,
                  optimistic,
                  authored,
                  $dict.insert(
                    state.own_tallies,
                    key,
                    [new_positive, new_negative],
                  ),
                  state.authored_mv_registers,
                  state.register_clock,
                  state.set_clocks,
                  $list.append(
                    state.pending,
                    toList([new PendingOperation(operation, message_id)]),
                  ),
                  message_id + 1,
                );
                let new_value = tally_of(new_state, key);
                return new Ok(
                  [
                    new_state,
                    toList([new TallyUpdated(key, amount, new_value)]),
                    operation,
                    message_id,
                  ],
                );
              },
            );
          },
        );
      },
    );
  } else if ($ instanceof RegisterMode) {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  } else if ($ instanceof OrSetMode) {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  } else {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  }
}

function entry_value(entries, key) {
  let _pipe = entries;
  let _pipe$1 = $list.find(_pipe, (entry) => { return entry[0] === key; });
  return $result.map(_pipe$1, (entry) => { return entry[1]; });
}

function events_between(before, after) {
  let _block;
  let $ = $list.any(
    $list.append(before, after),
    (entry) => {
      let $1 = entry[1];
      if ($1 instanceof Tally) {
        return false;
      } else if ($1 instanceof Register) {
        return false;
      } else if ($1 instanceof SetMembers) {
        return true;
      } else {
        return false;
      }
    },
  );
  if ($) {
    _block = $canonical_json.compare;
  } else {
    _block = $string.compare;
  }
  let compare = _block;
  let _block$1;
  let _pipe = $list.append(
    $list.map(before, (entry) => { return entry[0]; }),
    $list.map(after, (entry) => { return entry[0]; }),
  );
  let _pipe$1 = $list.unique(_pipe);
  _block$1 = $list.sort(_pipe$1, compare);
  let keys$1 = _block$1;
  return $list.filter_map(
    keys$1,
    (key) => {
      let $1 = entry_value(before, key);
      let $2 = entry_value(after, key);
      if ($1 instanceof Ok) {
        if ($2 instanceof Ok) {
          let $3 = $1[0];
          if ($3 instanceof Tally) {
            let $4 = $2[0];
            if ($4 instanceof Tally) {
              let old = $3[0];
              let new$1 = $4[0];
              let $5 = old === new$1;
              if ($5) {
                return new Error(undefined);
              } else {
                return new Ok(new TallyUpdated(key, new$1 - old, new$1));
              }
            } else if ($4 instanceof Register) {
              return new Error(undefined);
            } else if ($4 instanceof SetMembers) {
              return new Error(undefined);
            } else {
              return new Error(undefined);
            }
          } else if ($3 instanceof Register) {
            let $4 = $2[0];
            if ($4 instanceof Tally) {
              return new Error(undefined);
            } else if ($4 instanceof Register) {
              let old = $3[0];
              let new$1 = $4[0];
              let $5 = old === new$1;
              if ($5) {
                return new Error(undefined);
              } else {
                return new Ok(new RegisterUpdated(key, new$1));
              }
            } else if ($4 instanceof SetMembers) {
              return new Error(undefined);
            } else {
              return new Error(undefined);
            }
          } else if ($3 instanceof SetMembers) {
            let $4 = $2[0];
            if ($4 instanceof Tally) {
              return new Error(undefined);
            } else if ($4 instanceof Register) {
              return new Error(undefined);
            } else if ($4 instanceof SetMembers) {
              let old = $3[0];
              let new$1 = $4[0];
              let $5 = isEqual(old, new$1);
              if ($5) {
                return new Error(undefined);
              } else {
                return new Ok(new SetMembersUpdated(key, new$1));
              }
            } else {
              return new Error(undefined);
            }
          } else {
            let $4 = $2[0];
            if ($4 instanceof Tally) {
              return new Error(undefined);
            } else if ($4 instanceof Register) {
              return new Error(undefined);
            } else if ($4 instanceof SetMembers) {
              return new Error(undefined);
            } else {
              let old = $3[0];
              let new$1 = $4[0];
              let $5 = isEqual(old, new$1);
              if ($5) {
                return new Error(undefined);
              } else {
                return new Ok(new MvRegisterUpdated(key, new$1));
              }
            }
          }
        } else {
          return new Ok(new KeyRemoved(key));
        }
      } else if ($2 instanceof Ok) {
        let $3 = $2[0];
        if ($3 instanceof Tally) {
          let value = $3[0];
          return new Ok(new TallyUpdated(key, value, value));
        } else if ($3 instanceof Register) {
          let value = $3[0];
          return new Ok(new RegisterUpdated(key, value));
        } else if ($3 instanceof SetMembers) {
          let members = $3[0];
          return new Ok(new SetMembersUpdated(key, members));
        } else {
          let values = $3[0];
          return new Ok(new MvRegisterUpdated(key, values));
        }
      } else {
        return $1;
      }
    },
  );
}

/**
 * Record a timestamp as seen for a key. The clock keeps the maximum.
 * 
 * @ignore
 */
function observe(clock, key, timestamp) {
  let $ = $dict.get(clock, key);
  if ($ instanceof Ok) {
    let seen = $[0];
    if (seen >= timestamp) {
      return clock;
    } else {
      return $dict.insert(clock, key, timestamp);
    }
  } else {
    return $dict.insert(clock, key, timestamp);
  }
}

/**
 * The timestamp for a local register write. The result is the wall clock,
 * unless this replica has already seen that instant or a later one for this
 * key. In that condition the result is one tick after the newest timestamp
 * that it has seen. The result is also above the configured default at zero.
 *
 * This is the complete fix for a lost second write in the same millisecond.
 * You cannot make that fix by changing the more-than comparison of
 * `lww_register` to a more-than-or-equal comparison. That comparison makes the
 * merge commutative, and the `replica_id` tie-break below it settles the
 * writes from different replicas that are truly concurrent. Only the *stamping*
 * side knows that these two writes are ordered.
 * 
 * @ignore
 */
function stamp(clock, key, wall_clock) {
  let wall_clock$1 = $int.max(1, wall_clock);
  let $ = $dict.get(clock, key);
  if ($ instanceof Ok) {
    let seen = $[0];
    if (seen >= wall_clock$1) {
      return seen + 1;
    } else {
      return wall_clock$1;
    }
  } else {
    return wall_clock$1;
  }
}

export function set_register(state, key, value, timestamp) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  } else if ($ instanceof RegisterMode) {
    let before = entries(state);
    let timestamp$1 = stamp(state.register_clock, key, timestamp);
    let register = $lww_register.new$(value, timestamp$1, state.replica_id);
    return $result.try$(
      update_with_delta(state, key, new $crdt.CrdtLwwRegister(register)),
      (_use0) => {
        let authored = _use0[0];
        let delta = _use0[1];
        return $result.try$(
          apply_delta(state.optimistic, delta),
          (optimistic) => {
            let message_id = state.next_pending_message_id;
            let operation = new SetRegister(key, value, timestamp$1, delta);
            let new_state = new OrMapState(
              state.replica_id,
              state.mode,
              state.sequenced,
              optimistic,
              authored,
              state.own_tallies,
              state.authored_mv_registers,
              observe(state.register_clock, key, timestamp$1),
              state.set_clocks,
              $list.append(
                state.pending,
                toList([new PendingOperation(operation, message_id)]),
              ),
              message_id + 1,
            );
            return new Ok(
              [
                new_state,
                events_between(before, entries(new_state)),
                operation,
                message_id,
              ],
            );
          },
        );
      },
    );
  } else if ($ instanceof OrSetMode) {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  } else {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  }
}

/**
 * Record the timestamp that the write of a peer used. The next local write to
 * that key is thus above it. Without this record the two writes could be
 * equal, and the replica-id tie-break would then decide.
 * 
 * @ignore
 */
function observe_operation(clock, operation) {
  if (operation instanceof Increment) {
    return clock;
  } else if (operation instanceof SetRegister) {
    let key = operation.key;
    let timestamp = operation.timestamp;
    return observe(clock, key, timestamp);
  } else if (operation instanceof SetMvRegister) {
    return clock;
  } else if (operation instanceof Remove) {
    return clock;
  } else if (operation instanceof AddMember) {
    return clock;
  } else {
    return clock;
  }
}

function remove_legacy(state, key) {
  let before = entries(state);
  let $ = $or_map.remove_with_delta(state.optimistic, key);
  let delta = $[1];
  return $result.try$(
    apply_delta(state.optimistic, delta),
    (optimistic) => {
      let message_id = state.next_pending_message_id;
      let operation = new Remove(key, delta);
      let new_state = new OrMapState(
        state.replica_id,
        state.mode,
        state.sequenced,
        optimistic,
        state.authored,
        state.own_tallies,
        state.authored_mv_registers,
        state.register_clock,
        state.set_clocks,
        $list.append(
          state.pending,
          toList([new PendingOperation(operation, message_id)]),
        ),
        message_id + 1,
      );
      return new Ok(
        [
          new_state,
          events_between(before, entries(new_state)),
          operation,
          message_id,
        ],
      );
    },
  );
}

function retain_set_clocks(state) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return new Ok(state);
  } else if ($ instanceof RegisterMode) {
    return new Ok(state);
  } else if ($ instanceof OrSetMode) {
    return $result.try$(
      (() => {
        let _pipe = $or_map_set_leaf.observe_state(
          state.set_clocks,
          state.sequenced,
        );
        return $result.map_error(_pipe, set_error);
      })(),
      (clocks) => {
        return $result.try$(
          (() => {
            let _pipe = $or_map_set_leaf.observe_state(clocks, state.optimistic);
            return $result.map_error(_pipe, set_error);
          })(),
          (clocks) => {
            return $result.try$(
              (() => {
                let _pipe = $or_map_set_leaf.retain_counter_floor(
                  state.sequenced,
                  clocks,
                  state.replica_id,
                );
                return $result.map_error(_pipe, set_error);
              })(),
              (sequenced) => {
                return $result.try$(
                  (() => {
                    let _pipe = $or_map_set_leaf.retain_counter_floor(
                      state.optimistic,
                      clocks,
                      state.replica_id,
                    );
                    return $result.map_error(_pipe, set_error);
                  })(),
                  (optimistic) => {
                    return new Ok(
                      new OrMapState(
                        state.replica_id,
                        state.mode,
                        sequenced,
                        optimistic,
                        state.authored,
                        state.own_tallies,
                        state.authored_mv_registers,
                        state.register_clock,
                        clocks,
                        state.pending,
                        state.next_pending_message_id,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  } else {
    return new Ok(state);
  }
}

function tag_decoder() {
  return $decode.field(
    "r",
    $decode.string,
    (author) => {
      return $decode.field(
        "c",
        $decode.int,
        (counter) => { return $decode.success([author, counter]); },
      );
    },
  );
}

function write_matches(operation, spec, author, key, leaf) {
  if (operation instanceof Increment) {
    let intent_key = operation.key;
    let amount = operation.amount;
    let half = $decode.field(
      "self_id",
      $decode.string,
      (self) => {
        return $decode.field(
          "counts",
          $decode.dict($decode.string, $decode.int),
          (counts) => { return $decode.success([self, counts]); },
        );
      },
    );
    let decoder = $decode.at(
      toList(["state"]),
      $decode.field(
        "positive",
        half,
        (positive) => {
          return $decode.field(
            "negative",
            half,
            (negative) => {
              return $decode.success(
                (((positive[0] === author) && (negative[0] === author)) && $list.all(
                  $list.append(
                    $dict.to_list(positive[1]),
                    $dict.to_list(negative[1]),
                  ),
                  (count) => { return (count[0] === author) && (count[1] >= 0); },
                )) && (() => {
                  let $ = amount >= 0;
                  if ($) {
                    return $result.unwrap($dict.get(positive[1], author), 0) >= amount;
                  } else {
                    return $result.unwrap($dict.get(negative[1], author), 0) >= (0 - amount);
                  }
                })(),
              );
            },
          );
        },
      ),
    );
    return ((spec === "pn_counter") && (key === intent_key)) && (isEqual(
      $json.parse(leaf, decoder),
      new Ok(true)
    ));
  } else if (operation instanceof SetRegister) {
    let intent_key = operation.key;
    let value = operation.value;
    let timestamp = operation.timestamp;
    let decoder = $decode.at(
      toList(["state"]),
      $decode.field(
        "replica_id",
        $decode.string,
        (actual_author) => {
          return $decode.field(
            "value",
            $decode.string,
            (actual_value) => {
              return $decode.field(
                "timestamp",
                $decode.int,
                (actual_timestamp) => {
                  return $decode.success(
                    ((actual_author === author) && (actual_value === value)) && (actual_timestamp === timestamp),
                  );
                },
              );
            },
          );
        },
      ),
    );
    return ((spec === "lww_register") && (key === intent_key)) && (isEqual(
      $json.parse(leaf, decoder),
      new Ok(true)
    ));
  } else if (operation instanceof SetMvRegister) {
    let intent_key = operation.key;
    let value = operation.value;
    let decoder = $decode.at(
      toList(["state"]),
      $decode.field(
        "replica_id",
        $decode.string,
        (actual_author) => {
          return $decode.field(
            "entries",
            $decode.list(
              $decode.field(
                "tag",
                tag_decoder(),
                (tag) => {
                  return $decode.field(
                    "value",
                    $decode.string,
                    (value) => { return $decode.success([tag, value]); },
                  );
                },
              ),
            ),
            (entries) => {
              return $decode.field(
                "vclock",
                $decode.dict($decode.string, $decode.int),
                (clock) => {
                  return $decode.success(
                    (() => {
                      if (entries instanceof $Empty) {
                        return false;
                      } else {
                        let $ = entries.tail;
                        if ($ instanceof $Empty) {
                          let actual_value = entries.head[1];
                          let tag_author = entries.head[0][0];
                          let counter = entries.head[0][1];
                          return (((actual_author === author) && (tag_author === author)) && (actual_value === value)) && (isEqual(
                            $dict.get(clock, author),
                            new Ok(counter)
                          ));
                        } else {
                          return false;
                        }
                      }
                    })(),
                  );
                },
              );
            },
          );
        },
      ),
    );
    return (((spec === "mv_register") && (key === intent_key)) && $result.is_ok(
      $mv_register_kernel.decode_crdt(leaf),
    )) && (isEqual($json.parse(leaf, decoder), new Ok(true)));
  } else if (operation instanceof Remove) {
    return false;
  } else if (operation instanceof AddMember) {
    return false;
  } else {
    return false;
  }
}

function key_delta_decoder() {
  return $decode.at(
    toList(["state"]),
    $decode.field(
      "replica_id",
      $decode.string,
      (author) => {
        return $decode.field(
          "counter",
          $decode.int,
          (counter) => {
            return $decode.field(
              "entries",
              $decode.then$(
                $decode.list(
                  $decode.field(
                    "value",
                    $decode.string,
                    (key) => {
                      return $decode.field(
                        "tags",
                        $decode.list(tag_decoder()),
                        (tags) => { return $decode.success([key, tags]); },
                      );
                    },
                  ),
                ),
                (entries) => {
                  return $decode.success($dict.from_list(entries));
                },
              ),
              (entries) => {
                return $decode.field(
                  "tombstones",
                  $decode.list(tag_decoder()),
                  (tombstones) => {
                    return $decode.field(
                      "pruned",
                      $version_vector.decoder(),
                      (pruned) => {
                        return $decode.success(
                          new KeyDelta(
                            author,
                            counter,
                            entries,
                            tombstones,
                            pruned,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
}

function operation_delta(operation) {
  if (operation instanceof Increment) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof SetRegister) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof SetMvRegister) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof Remove) {
    let delta = operation.delta;
    return delta;
  } else if (operation instanceof AddMember) {
    let delta = operation.delta;
    return delta;
  } else {
    let delta = operation.delta;
    return delta;
  }
}

function validated_key_delta(operation) {
  let metadata = $decode.at(
    toList(["state"]),
    $decode.field(
      "replica_id",
      $decode.string,
      (author) => {
        return $decode.field(
          "spec",
          $decode.string,
          (spec) => {
            return $decode.field(
              "entries",
              $decode.list(
                $decode.field(
                  "key",
                  $decode.string,
                  (key) => {
                    return $decode.field(
                      "membership",
                      $decode.string,
                      (membership) => {
                        return $decode.field(
                          "value",
                          $decode.optional($decode.string),
                          (leaf) => {
                            return $decode.success([key, membership, leaf]);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              (entries) => { return $decode.success([author, spec, entries]); },
            );
          },
        );
      },
    ),
  );
  return $result.try$(
    (() => {
      let _pipe = $json.parse(
        (() => {
          let _pipe = operation_delta(operation);
          let _pipe$1 = $or_map.delta_to_json(_pipe);
          return $json.to_string(_pipe$1);
        })(),
        metadata,
      );
      return $result.map_error(
        _pipe,
        (error) => { return new CorruptDelta($string.inspect(error)); },
      );
    })(),
    (_use0) => {
      let author = _use0[0];
      let encoded_spec = _use0[1];
      let entries$1 = _use0[2];
      return $result.try$(
        (() => {
          let _pipe = $crdt.spec_from_json_with(encoded_spec, $decode.string);
          return $result.map_error(
            _pipe,
            (error) => { return new CorruptDelta($string.inspect(error)); },
          );
        })(),
        (spec) => {
          return $result.try$(
            spec_to_mode(spec),
            (_) => {
              if (entries$1 instanceof $Empty) {
                if (operation instanceof Remove) {
                  return new Ok(
                    new KeyDelta(
                      author,
                      0,
                      $dict.new$(),
                      $List$Empty$const,
                      $version_vector.new$(),
                    ),
                  );
                } else {
                  return new Error(
                    new CorruptDelta(
                      "operation intent does not match its delta",
                    ),
                  );
                }
              } else {
                let $ = entries$1.tail;
                if ($ instanceof $Empty) {
                  let key = entries$1.head[0];
                  let membership = entries$1.head[1];
                  let leaf = entries$1.head[2];
                  return $result.try$(
                    (() => {
                      let _pipe = $json.parse(membership, key_delta_decoder());
                      return $result.map_error(
                        _pipe,
                        (error) => {
                          return new CorruptDelta($string.inspect(error));
                        },
                      );
                    })(),
                    (keys) => {
                      let valid = (((keys.counter >= 0) && $version_vector.is_empty(
                        keys.pruned,
                      )) && $list.all(
                        keys.tombstones,
                        (tag) => {
                          return (tag[1] > 0) && (tag[1] <= keys.counter);
                        },
                      )) && (() => {
                        let $1 = $dict.to_list(keys.entries);
                        if (leaf instanceof Some) {
                          if ($1 instanceof $Empty) {
                            return false;
                          } else {
                            let $2 = $1.tail;
                            if ($2 instanceof $Empty) {
                              let $3 = $1.head[1];
                              if ($3 instanceof $Empty) {
                                return false;
                              } else {
                                let $4 = $3.tail;
                                if ($4 instanceof $Empty) {
                                  let encoded = leaf[0];
                                  let added_key = $1.head[0];
                                  let tag_author = $3.head[0];
                                  let counter = $3.head[1];
                                  return (((((key === added_key) && (tag_author === keys.author)) && (counter > 0)) && (counter === keys.counter)) && (keys.tombstones instanceof $Empty)) && (() => {
                                    let $5 = $crdt.delta_from_json(encoded);
                                    if ($5 instanceof Ok) {
                                      let $6 = $5[0];
                                      if ($6 instanceof $crdt.NoChange) {
                                        return false;
                                      } else if ($6 instanceof $crdt.StateDelta) {
                                        let value = $6[0];
                                        return write_matches(
                                          operation,
                                          $crdt.spec_name(spec),
                                          author,
                                          key,
                                          (() => {
                                            let _pipe = $crdt.to_json(value);
                                            return $json.to_string(_pipe);
                                          })(),
                                        );
                                      } else {
                                        return false;
                                      }
                                    } else {
                                      return false;
                                    }
                                  })();
                                } else {
                                  return false;
                                }
                              }
                            } else {
                              return false;
                            }
                          }
                        } else if (
                          $1 instanceof $Empty &&
                          operation instanceof Remove
                        ) {
                          let intent_key = operation.key;
                          return key === intent_key;
                        } else {
                          return false;
                        }
                      })();
                      if (valid) {
                        return new Ok(keys);
                      } else {
                        return new Error(
                          new CorruptDelta(
                            "operation intent does not match its delta",
                          ),
                        );
                      }
                    },
                  );
                } else {
                  return new Error(
                    new CorruptDelta(
                      "operation intent does not match its delta",
                    ),
                  );
                }
              }
            },
          );
        },
      );
    },
  );
}

/**
 * Validate typed operations before native merges can normalize their state.
 * 
 * @ignore
 */
export function validate_operation(mode, operation) {
  if (mode instanceof TallyMode) {
    if (operation instanceof Increment) {
      let _pipe = validated_key_delta(operation);
      return $result.replace(_pipe, undefined);
    } else if (operation instanceof SetRegister) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof SetMvRegister) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof Remove) {
      let _pipe = validated_key_delta(operation);
      return $result.replace(_pipe, undefined);
    } else if (operation instanceof AddMember) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    }
  } else if (mode instanceof RegisterMode) {
    if (operation instanceof Increment) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof SetRegister) {
      let _pipe = validated_key_delta(operation);
      return $result.replace(_pipe, undefined);
    } else if (operation instanceof SetMvRegister) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof Remove) {
      let _pipe = validated_key_delta(operation);
      return $result.replace(_pipe, undefined);
    } else if (operation instanceof AddMember) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    }
  } else if (mode instanceof OrSetMode) {
    if (operation instanceof Increment) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof SetRegister) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof SetMvRegister) {
      return new Error(
        new ModeMismatch("operation does not match the channel mode"),
      );
    } else if (operation instanceof Remove) {
      let key = operation.key;
      let delta = operation.delta;
      let _pipe = $or_map_set_leaf.validate_intent(
        delta,
        key,
        $or_map_set_leaf.Intent$RemoveKey$const,
      );
      return $result.map_error(_pipe, set_error);
    } else if (operation instanceof AddMember) {
      let key = operation.key;
      let member = operation.member;
      let delta = operation.delta;
      let _pipe = $or_map_set_leaf.validate_intent(
        delta,
        key,
        new $or_map_set_leaf.AddMember(member),
      );
      return $result.map_error(_pipe, set_error);
    } else {
      let key = operation.key;
      let member = operation.member;
      let delta = operation.delta;
      let _pipe = $or_map_set_leaf.validate_intent(
        delta,
        key,
        new $or_map_set_leaf.RemoveMember(member),
      );
      return $result.map_error(_pipe, set_error);
    }
  } else if (operation instanceof Increment) {
    return new Error(
      new ModeMismatch("operation does not match the channel mode"),
    );
  } else if (operation instanceof SetRegister) {
    return new Error(
      new ModeMismatch("operation does not match the channel mode"),
    );
  } else if (operation instanceof SetMvRegister) {
    let _pipe = validated_key_delta(operation);
    return $result.replace(_pipe, undefined);
  } else if (operation instanceof Remove) {
    let _pipe = validated_key_delta(operation);
    return $result.replace(_pipe, undefined);
  } else if (operation instanceof AddMember) {
    return new Error(
      new ModeMismatch("operation does not match the channel mode"),
    );
  } else {
    return new Error(
      new ModeMismatch("operation does not match the channel mode"),
    );
  }
}

function edit_set(state, key, intent, confirmed) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return new Error(new ModeMismatch("member edits require OrSetMode"));
  } else if ($ instanceof RegisterMode) {
    return new Error(new ModeMismatch("member edits require OrSetMode"));
  } else if ($ instanceof OrSetMode) {
    let before = entries(state);
    return $result.try$(
      retain_set_clocks(state),
      (state) => {
        return $result.try$(
          (() => {
            let _block;
            if (intent instanceof $or_map_set_leaf.AddMember) {
              let member = intent.member;
              _block = $or_map_set_leaf.add(
                state.optimistic,
                state.set_clocks,
                state.replica_id,
                key,
                member,
              );
            } else if (intent instanceof $or_map_set_leaf.RemoveMember) {
              let member = intent.member;
              _block = $or_map_set_leaf.remove_member(
                state.optimistic,
                state.set_clocks,
                state.replica_id,
                key,
                member,
              );
            } else {
              _block = $or_map_set_leaf.remove_key(
                state.optimistic,
                state.set_clocks,
                state.replica_id,
                key,
              );
            }
            let _pipe = _block;
            return $result.map_error(_pipe, set_error);
          })(),
          (_use0) => {
            let delta = _use0[0];
            let clocks = _use0[1];
            let _block;
            if (intent instanceof $or_map_set_leaf.AddMember) {
              let member = intent.member;
              _block = new AddMember(key, member, delta);
            } else if (intent instanceof $or_map_set_leaf.RemoveMember) {
              let member = intent.member;
              _block = new RemoveMember(key, member, delta);
            } else {
              _block = new Remove(key, delta);
            }
            let operation = _block;
            return $result.try$(
              validate_operation(state.mode, operation),
              (_) => {
                return $result.try$(
                  retain_set_clocks(
                    new OrMapState(
                      state.replica_id,
                      state.mode,
                      state.sequenced,
                      state.optimistic,
                      state.authored,
                      state.own_tallies,
                      state.authored_mv_registers,
                      state.register_clock,
                      clocks,
                      state.pending,
                      state.next_pending_message_id,
                    ),
                  ),
                  (state) => {
                    return $result.try$(
                      apply_delta(state.optimistic, delta),
                      (optimistic) => {
                        return $result.try$(
                          (() => {
                            if (confirmed) {
                              return apply_delta(state.sequenced, delta);
                            } else {
                              return new Ok(state.sequenced);
                            }
                          })(),
                          (sequenced) => {
                            let message_id = state.next_pending_message_id;
                            let _block$1;
                            if (confirmed) {
                              _block$1 = state.pending;
                            } else {
                              _block$1 = $list.append(
                                state.pending,
                                toList([
                                  new PendingOperation(operation, message_id),
                                ]),
                              );
                            }
                            let pending = _block$1;
                            return $result.try$(
                              retain_set_clocks(
                                new OrMapState(
                                  state.replica_id,
                                  state.mode,
                                  sequenced,
                                  optimistic,
                                  state.authored,
                                  state.own_tallies,
                                  state.authored_mv_registers,
                                  state.register_clock,
                                  state.set_clocks,
                                  pending,
                                  (() => {
                                    if (confirmed) {
                                      return message_id;
                                    } else {
                                      return message_id + 1;
                                    }
                                  })(),
                                ),
                              ),
                              (new_state) => {
                                return new Ok(
                                  [
                                    new_state,
                                    events_between(before, entries(new_state)),
                                    operation,
                                    message_id,
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
              },
            );
          },
        );
      },
    );
  } else {
    return new Error(new ModeMismatch("member edits require OrSetMode"));
  }
}

export function remove(state, key) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return remove_legacy(state, key);
  } else if ($ instanceof RegisterMode) {
    return remove_legacy(state, key);
  } else if ($ instanceof OrSetMode) {
    return edit_set(state, key, $or_map_set_leaf.Intent$RemoveKey$const, false);
  } else {
    return remove_legacy(state, key);
  }
}

/**
 * The ack-free p2p form of `increment`. It writes the same delta, but it
 * merges that delta into the confirmed state and the visible state
 * immediately. It queues no pending entry for a later ack.
 */
export function p2p_increment(state, key, amount) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    let _block;
    let _pipe = $dict.get(state.own_tallies, key);
    _block = $result.unwrap(_pipe, [0, 0]);
    let $1 = _block;
    let positive = $1[0];
    let negative = $1[1];
    let _block$1;
    let $3 = amount >= 0;
    if ($3) {
      _block$1 = [positive + amount, negative];
    } else {
      _block$1 = [positive, negative + (0 - amount)];
    }
    let $2 = _block$1;
    let new_positive = $2[0];
    let new_negative = $2[1];
    return $result.try$(
      own_tally_counter(state.replica_id, new_positive, new_negative),
      (own_counter) => {
        return $result.try$(
          update_with_delta(state, key, new $crdt.CrdtPnCounter(own_counter)),
          (_use0) => {
            let authored = _use0[0];
            let delta = _use0[1];
            return $result.try$(
              apply_delta(state.sequenced, delta),
              (sequenced) => {
                return $result.try$(
                  apply_delta(state.optimistic, delta),
                  (optimistic) => {
                    let operation = new Increment(key, amount, delta);
                    let new_state = new OrMapState(
                      state.replica_id,
                      state.mode,
                      sequenced,
                      optimistic,
                      authored,
                      $dict.insert(
                        state.own_tallies,
                        key,
                        [new_positive, new_negative],
                      ),
                      state.authored_mv_registers,
                      state.register_clock,
                      state.set_clocks,
                      state.pending,
                      state.next_pending_message_id,
                    );
                    let new_value = tally_of(new_state, key);
                    return new Ok(
                      [
                        new_state,
                        toList([new TallyUpdated(key, amount, new_value)]),
                        operation,
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
  } else if ($ instanceof RegisterMode) {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  } else if ($ instanceof OrSetMode) {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  } else {
    return new Error(new ModeMismatch("increment requires TallyMode"));
  }
}

/**
 * The ack-free p2p form of `set_register`. See `p2p_increment`.
 */
export function p2p_set_register(state, key, value, timestamp) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  } else if ($ instanceof RegisterMode) {
    let before = entries(state);
    let timestamp$1 = stamp(state.register_clock, key, timestamp);
    let register = $lww_register.new$(value, timestamp$1, state.replica_id);
    return $result.try$(
      update_with_delta(state, key, new $crdt.CrdtLwwRegister(register)),
      (_use0) => {
        let authored = _use0[0];
        let delta = _use0[1];
        return $result.try$(
          apply_delta(state.sequenced, delta),
          (sequenced) => {
            return $result.try$(
              apply_delta(state.optimistic, delta),
              (optimistic) => {
                let operation = new SetRegister(key, value, timestamp$1, delta);
                let new_state = new OrMapState(
                  state.replica_id,
                  state.mode,
                  sequenced,
                  optimistic,
                  authored,
                  state.own_tallies,
                  state.authored_mv_registers,
                  observe(state.register_clock, key, timestamp$1),
                  state.set_clocks,
                  state.pending,
                  state.next_pending_message_id,
                );
                return new Ok(
                  [
                    new_state,
                    events_between(before, entries(new_state)),
                    operation,
                  ],
                );
              },
            );
          },
        );
      },
    );
  } else if ($ instanceof OrSetMode) {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  } else {
    return new Error(new ModeMismatch("set_register requires RegisterMode"));
  }
}

function write_mv_register(state, key, value) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return new Error(
      new ModeMismatch("set_mv_register requires MvRegisterMode"),
    );
  } else if ($ instanceof RegisterMode) {
    return new Error(
      new ModeMismatch("set_mv_register requires MvRegisterMode"),
    );
  } else if ($ instanceof OrSetMode) {
    return new Error(
      new ModeMismatch("set_mv_register requires MvRegisterMode"),
    );
  } else {
    let _block;
    let _pipe = $dict.get(state.authored_mv_registers, key);
    _block = $result.unwrap(_pipe, $mv_register.new$(state.replica_id));
    let authored = _block;
    let _block$1;
    let _pipe$1 = $or_map.get(state.optimistic, key);
    _block$1 = $result.unwrap(
      _pipe$1,
      new $crdt.CrdtMvRegister($mv_register.new$(state.replica_id)),
    );
    let $1 = _block$1;
    let visible;
    if ($1 instanceof $crdt.CrdtMvRegister) {
      visible = $1[0];
    } else {
      throw makeError(
        "let_assert",
        FILEPATH,
        "watershed/or_map_kernel",
        534,
        "write_mv_register",
        "Pattern match failed, no pattern matched the value.",
        {
          value: $1,
          start: 17638,
          end: 17802,
          pattern_start: 17649,
          pattern_end: 17677
        }
      )
    }
    let _block$2;
    let _pipe$2 = $mv_register.merge(authored, visible);
    _block$2 = $mv_register.set_with_delta(_pipe$2, value);
    let $2 = _block$2;
    let written = $2[0];
    return $result.try$(
      update_with_delta(state, key, new $crdt.CrdtMvRegister(written)),
      (_use0) => {
        let updated = _use0[0];
        let delta = _use0[1];
        return new Ok([updated, delta, written]);
      },
    );
  }
}

export function set_mv_register(state, key, value) {
  return $result.try$(
    write_mv_register(state, key, value),
    (_use0) => {
      let authored_map = _use0[0];
      let delta = _use0[1];
      let authored = _use0[2];
      return $result.try$(
        apply_delta(state.optimistic, delta),
        (optimistic) => {
          let message_id = state.next_pending_message_id;
          let operation = new SetMvRegister(key, value, delta);
          let next = new OrMapState(
            state.replica_id,
            state.mode,
            state.sequenced,
            optimistic,
            authored_map,
            state.own_tallies,
            $dict.insert(state.authored_mv_registers, key, authored),
            state.register_clock,
            state.set_clocks,
            $list.append(
              state.pending,
              toList([new PendingOperation(operation, message_id)]),
            ),
            message_id + 1,
          );
          return new Ok(
            [
              next,
              events_between(entries(state), entries(next)),
              operation,
              message_id,
            ],
          );
        },
      );
    },
  );
}

/**
 * The ack-free p2p form of `set_mv_register`.
 */
export function p2p_set_mv_register(state, key, value) {
  return $result.try$(
    write_mv_register(state, key, value),
    (_use0) => {
      let authored_map = _use0[0];
      let delta = _use0[1];
      let authored = _use0[2];
      return $result.try$(
        apply_delta(state.optimistic, delta),
        (optimistic) => {
          return $result.try$(
            apply_delta(state.sequenced, delta),
            (sequenced) => {
              let next = new OrMapState(
                state.replica_id,
                state.mode,
                sequenced,
                optimistic,
                authored_map,
                state.own_tallies,
                $dict.insert(state.authored_mv_registers, key, authored),
                state.register_clock,
                state.set_clocks,
                state.pending,
                state.next_pending_message_id,
              );
              return new Ok(
                [
                  next,
                  events_between(entries(state), entries(next)),
                  new SetMvRegister(key, value, delta),
                ],
              );
            },
          );
        },
      );
    },
  );
}

function p2p_remove_legacy(state, key) {
  let before = entries(state);
  let $ = $or_map.remove_with_delta(state.optimistic, key);
  let delta = $[1];
  return $result.try$(
    apply_delta(state.sequenced, delta),
    (sequenced) => {
      return $result.try$(
        apply_delta(state.optimistic, delta),
        (optimistic) => {
          let operation = new Remove(key, delta);
          let new_state = new OrMapState(
            state.replica_id,
            state.mode,
            sequenced,
            optimistic,
            state.authored,
            state.own_tallies,
            state.authored_mv_registers,
            state.register_clock,
            state.set_clocks,
            state.pending,
            state.next_pending_message_id,
          );
          return new Ok(
            [new_state, events_between(before, entries(new_state)), operation],
          );
        },
      );
    },
  );
}

/**
 * The ack-free p2p form of `remove`.
 */
export function p2p_remove(state, key) {
  let $ = state.mode;
  if ($ instanceof TallyMode) {
    return p2p_remove_legacy(state, key);
  } else if ($ instanceof RegisterMode) {
    return p2p_remove_legacy(state, key);
  } else if ($ instanceof OrSetMode) {
    let _pipe = edit_set(
      state,
      key,
      $or_map_set_leaf.Intent$RemoveKey$const,
      true,
    );
    return $result.map(_pipe, (edit) => { return [edit[0], edit[1], edit[2]]; });
  } else {
    return p2p_remove_legacy(state, key);
  }
}

export function add_member(state, key, member) {
  return edit_set(state, key, new $or_map_set_leaf.AddMember(member), false);
}

export function remove_member(state, key, member) {
  return edit_set(state, key, new $or_map_set_leaf.RemoveMember(member), false);
}

export function p2p_add_member(state, key, member) {
  let _pipe = edit_set(state, key, new $or_map_set_leaf.AddMember(member), true);
  return $result.map(_pipe, (edit) => { return [edit[0], edit[1], edit[2]]; });
}

export function p2p_remove_member(state, key, member) {
  let _pipe = edit_set(
    state,
    key,
    new $or_map_set_leaf.RemoveMember(member),
    true,
  );
  return $result.map(_pipe, (edit) => { return [edit[0], edit[1], edit[2]]; });
}

function observe_set_operation(state, operation) {
  return $result.try$(
    validate_operation(state.mode, operation),
    (_) => {
      let $ = state.mode;
      if ($ instanceof TallyMode) {
        return new Ok(state);
      } else if ($ instanceof RegisterMode) {
        return new Ok(state);
      } else if ($ instanceof OrSetMode) {
        return $result.try$(
          (() => {
            let _pipe = $or_map_set_leaf.observe_delta(
              state.set_clocks,
              operation_delta(operation),
            );
            return $result.map_error(_pipe, set_error);
          })(),
          (clocks) => {
            return retain_set_clocks(
              new OrMapState(
                state.replica_id,
                state.mode,
                state.sequenced,
                state.optimistic,
                state.authored,
                state.own_tallies,
                state.authored_mv_registers,
                state.register_clock,
                clocks,
                state.pending,
                state.next_pending_message_id,
              ),
            );
          },
        );
      } else {
        return new Ok(state);
      }
    },
  );
}

/**
 * `LWWRegister` is opaque and has no accessor for its timestamp. But `to_json`
 * publishes the timestamp that the register merged on. The clock is thus
 * rebuilt from the value of the register, and not from a value that this
 * module invents.
 * 
 * @ignore
 */
function register_timestamp(register) {
  let _pipe = $json.parse(
    $json.to_string($lww_register.to_json(register)),
    $decode.at(toList(["state", "timestamp"]), $decode.int),
  );
  return $result.replace_error(_pipe, undefined);
}

/**
 * Add the timestamp of every merged register to the clock, and keep the
 * maximum for each key. A `TallyMode` map holds no register, so the function
 * skips the whole map and does not walk it.
 * 
 * @ignore
 */
function observe_registers(clock, mode, map) {
  if (mode instanceof TallyMode) {
    return clock;
  } else if (mode instanceof RegisterMode) {
    return $list.fold(
      $or_map.keys(map),
      clock,
      (clock, key) => {
        let $ = $or_map.get(map, key);
        if ($ instanceof Ok) {
          let $1 = $[0];
          if ($1 instanceof $crdt.CrdtGCounter) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtPnCounter) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtLwwRegister) {
            let register = $1[0];
            let $2 = register_timestamp(register);
            if ($2 instanceof Ok) {
              let timestamp = $2[0];
              return observe(clock, key, timestamp);
            } else {
              return clock;
            }
          } else if ($1 instanceof $crdt.CrdtMvRegister) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtGSet) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtTwoPSet) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtOrSet) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtVersionVector) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtSequence) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtText) {
            return clock;
          } else if ($1 instanceof $crdt.CrdtOrMap) {
            return clock;
          } else {
            return clock;
          }
        } else {
          return clock;
        }
      },
    );
  } else if (mode instanceof OrSetMode) {
    return clock;
  } else {
    return clock;
  }
}

function decode_mv_registers(source, replica_id) {
  return $result.try$(
    $json.parse(source, $decode.at(toList(["v"]), $decode.int)),
    (version) => {
      let _block;
      if (version === 1) {
        _block = $decode.at(
          toList(["state", "values"]),
          $decode.list(
            $decode.field(
              "key",
              $decode.string,
              (key) => {
                return $decode.field(
                  "crdt",
                  $decode.string,
                  (encoded) => {
                    return $decode.success([key, new Some(encoded)]);
                  },
                );
              },
            ),
          ),
        );
      } else if (version === 2) {
        _block = $decode.at(
          toList(["state", "values"]),
          $decode.list(
            $decode.field(
              "key",
              $decode.string,
              (key) => {
                return $decode.field(
                  "crdt",
                  $decode.string,
                  (encoded) => {
                    return $decode.success([key, new Some(encoded)]);
                  },
                );
              },
            ),
          ),
        );
      } else {
        _block = $decode.at(
          toList(["state", "entries"]),
          $decode.list(
            $decode.field(
              "key",
              $decode.string,
              (key) => {
                return $decode.field(
                  "value",
                  $decode.optional($decode.string),
                  (encoded) => { return $decode.success([key, encoded]); },
                );
              },
            ),
          ),
        );
      }
      let decoder = _block;
      return $result.try$(
        $json.parse(source, decoder),
        (leaves) => {
          return $list.try_fold(
            leaves,
            $dict.new$(),
            (registers, leaf) => {
              let $ = leaf[1];
              if ($ instanceof Some) {
                let encoded = $[0];
                return $result.try$(
                  $mv_register_kernel.decode_crdt(encoded),
                  (register) => {
                    return new Ok(
                      $dict.insert(
                        registers,
                        leaf[0],
                        $mv_register.merge(
                          $mv_register.new$(replica_id),
                          register,
                        ),
                      ),
                    );
                  },
                );
              } else {
                return new Ok(registers);
              }
            },
          );
        },
      );
    },
  );
}

function observe_mv_registers(authored, mode, map, replica_id) {
  if (mode instanceof TallyMode) {
    return new Ok(authored);
  } else if (mode instanceof RegisterMode) {
    return new Ok(authored);
  } else if (mode instanceof OrSetMode) {
    return new Ok(authored);
  } else {
    return $result.try$(
      (() => {
        let _pipe = decode_mv_registers(
          (() => {
            let _pipe = $or_map.to_json(map);
            return $json.to_string(_pipe);
          })(),
          replica_id,
        );
        return $result.map_error(
          _pipe,
          (error) => { return new CorruptDelta($string.inspect(error)); },
        );
      })(),
      (registers) => {
        return new Ok($dict.combine(authored, registers, $mv_register.merge));
      },
    );
  }
}

function apply_operation(map, operation) {
  return $result.try$(
    native_mode(map),
    (mode) => {
      return $result.try$(
        validate_operation(mode, operation),
        (_) => { return apply_delta(map, operation_delta(operation)); },
      );
    },
  );
}

function replay_pending(sequenced, pending) {
  return $result.try$(
    native_mode(sequenced),
    (mode) => {
      return $result.try$(
        (() => {
          if (mode instanceof TallyMode) {
            return new Ok(undefined);
          } else if (mode instanceof RegisterMode) {
            return new Ok(undefined);
          } else if (mode instanceof OrSetMode) {
            let _pipe = $or_map_set_leaf.validate_state(sequenced);
            return $result.map_error(_pipe, set_error);
          } else {
            return new Ok(undefined);
          }
        })(),
        (_) => {
          return $list.try_fold(
            pending,
            sequenced,
            (acc, pending) => { return apply_operation(acc, pending.operation); },
          );
        },
      );
    },
  );
}

function merge_map(mode, left, right) {
  return $result.try$(
    native_mode(left),
    (left_mode) => {
      return $result.try$(
        native_mode(right),
        (right_mode) => {
          let $ = (isEqual(left_mode, mode)) && (isEqual(right_mode, mode));
          if ($) {
            if (mode instanceof TallyMode) {
              let _pipe = $or_map.merge(left, right);
              return $result.replace_error(
                _pipe,
                new ModeMismatch(
                  "merged value spec does not match the channel mode",
                ),
              );
            } else if (mode instanceof RegisterMode) {
              let _pipe = $or_map.merge(left, right);
              return $result.replace_error(
                _pipe,
                new ModeMismatch(
                  "merged value spec does not match the channel mode",
                ),
              );
            } else if (mode instanceof OrSetMode) {
              return $result.try$(
                (() => {
                  let _pipe = $or_map_set_leaf.validate_state(left);
                  return $result.map_error(_pipe, set_error);
                })(),
                (_) => {
                  return $result.try$(
                    (() => {
                      let _pipe = $or_map_set_leaf.validate_state(right);
                      return $result.map_error(_pipe, set_error);
                    })(),
                    (_) => {
                      let _pipe = $or_map_set_leaf.merge(left, right);
                      return $result.map_error(_pipe, set_error);
                    },
                  );
                },
              );
            } else {
              let _pipe = $or_map.merge(left, right);
              return $result.replace_error(
                _pipe,
                new ModeMismatch(
                  "merged value spec does not match the channel mode",
                ),
              );
            }
          } else {
            return new Error(
              new ModeMismatch(
                "summary value spec does not match requested mode",
              ),
            );
          }
        },
      );
    },
  );
}

/**
 * Merge the full confirmed CRDT state of a peer into this state. This is the
 * ack-free equivalent of `apply_remote`. It takes a `state` or `channel`
 * snapshot, not one delta. A lattice merge is a join, so it never discards a
 * winner.
 *
 * In `RegisterMode` the function adds the timestamp of each merged register to
 * `register_clock`. A replica that starts from a peer with a clock that ran
 * ahead thus still wins its own next write to those keys. It does not lose
 * that write. The function reads each timestamp through
 * `lww_register.to_json`, because `LWWRegister` is opaque and gives access to
 * `value` only. That is one JSON round trip for each register. The function
 * thus runs on a merge, which is a bootstrap or a repair, and not on the path
 * of each operation.
 */
export function p2p_merge(state, other) {
  let before = entries(state);
  return $result.try$(
    retain_set_clocks(state),
    (state) => {
      let $ = merge_map(state.mode, state.sequenced, other);
      if ($ instanceof Ok) {
        let sequenced = $[0];
        return $result.try$(
          observe_mv_registers(
            state.authored_mv_registers,
            state.mode,
            other,
            state.replica_id,
          ),
          (authored) => {
            return $result.try$(
              replay_pending(sequenced, state.pending),
              (optimistic) => {
                return $result.try$(
                  observe_mv_registers(
                    authored,
                    state.mode,
                    optimistic,
                    state.replica_id,
                  ),
                  (authored) => {
                    let new_state = new OrMapState(
                      state.replica_id,
                      state.mode,
                      sequenced,
                      optimistic,
                      state.authored,
                      state.own_tallies,
                      authored,
                      observe_registers(
                        state.register_clock,
                        state.mode,
                        optimistic,
                      ),
                      state.set_clocks,
                      state.pending,
                      state.next_pending_message_id,
                    );
                    return $result.try$(
                      retain_set_clocks(new_state),
                      (new_state) => {
                        return new Ok(
                          [
                            new_state,
                            events_between(before, entries(new_state)),
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
      } else {
        let $1 = $[0];
        if ($1 instanceof ModeMismatch) {
          return new Error(
            new ModeMismatch(
              "merged value spec does not match the channel mode",
            ),
          );
        } else {
          return $;
        }
      }
    },
  );
}

function validate_state_operation(state, operation) {
  return validate_operation(state.mode, operation);
}

export function apply_remote(state, operation) {
  let before = entries(state);
  return $result.try$(
    validate_state_operation(state, operation),
    (_) => {
      return $result.try$(
        observe_set_operation(state, operation),
        (state) => {
          let delta = operation_delta(operation);
          return $result.try$(
            apply_delta(state.sequenced, delta),
            (sequenced) => {
              return $result.try$(
                replay_pending(sequenced, state.pending),
                (optimistic) => {
                  return $result.try$(
                    observe_mv_registers(
                      state.authored_mv_registers,
                      state.mode,
                      optimistic,
                      state.replica_id,
                    ),
                    (authored) => {
                      let new_state = new OrMapState(
                        state.replica_id,
                        state.mode,
                        sequenced,
                        optimistic,
                        state.authored,
                        state.own_tallies,
                        authored,
                        observe_operation(state.register_clock, operation),
                        state.set_clocks,
                        state.pending,
                        state.next_pending_message_id,
                      );
                      return $result.try$(
                        retain_set_clocks(new_state),
                        (new_state) => {
                          return new Ok(
                            [
                              new_state,
                              events_between(before, entries(new_state)),
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
        },
      );
    },
  );
}

function do_ack(state, operation, expected_message_id) {
  let $ = state.pending;
  if ($ instanceof $Empty) {
    return new Error(new UnexpectedAck("pending queue is empty"));
  } else {
    let rest = $.tail;
    let pending_operation = $.head.operation;
    let pending_message_id = $.head.message_id;
    let _block;
    if (expected_message_id instanceof Some) {
      let message_id = expected_message_id[0];
      _block = message_id === pending_message_id;
    } else {
      _block = true;
    }
    let message_id_matches = _block;
    let $1 = (isEqual(pending_operation, operation)) && message_id_matches;
    if ($1) {
      return $result.try$(
        validate_state_operation(state, operation),
        (_) => {
          return $result.try$(
            observe_set_operation(state, operation),
            (state) => {
              return $result.try$(
                apply_delta(state.sequenced, operation_delta(operation)),
                (sequenced) => {
                  return retain_set_clocks(
                    new OrMapState(
                      state.replica_id,
                      state.mode,
                      sequenced,
                      state.optimistic,
                      state.authored,
                      state.own_tallies,
                      state.authored_mv_registers,
                      state.register_clock,
                      state.set_clocks,
                      rest,
                      state.next_pending_message_id,
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } else {
      return new Error(
        new UnexpectedAck(
          (("expected pending op with message id " + $int.to_string(
            pending_message_id,
          )) + ", got message id ") + (() => {
            if (expected_message_id instanceof Some) {
              let message_id = expected_message_id[0];
              return $int.to_string(message_id);
            } else {
              return "unvalidated";
            }
          })(),
        ),
      );
    }
  }
}

export function ack_local(state, operation) {
  return do_ack(state, operation, Option$None$const);
}

export function ack_local_with_message_id(state, operation, message_id) {
  return do_ack(state, operation, new Some(message_id));
}

function rollback_own_tallies(own_tallies, operation) {
  if (operation instanceof Increment) {
    let key = operation.key;
    let amount = operation.amount;
    let _block;
    let _pipe = $dict.get(own_tallies, key);
    _block = $result.unwrap(_pipe, [0, 0]);
    let $ = _block;
    let positive = $[0];
    let negative = $[1];
    let _block$1;
    let $1 = amount >= 0;
    if ($1) {
      _block$1 = [positive - amount, negative];
    } else {
      _block$1 = [positive, negative - (0 - amount)];
    }
    let next = _block$1;
    return $dict.insert(own_tallies, key, next);
  } else if (operation instanceof SetRegister) {
    return own_tallies;
  } else if (operation instanceof SetMvRegister) {
    return own_tallies;
  } else if (operation instanceof Remove) {
    return own_tallies;
  } else if (operation instanceof AddMember) {
    return own_tallies;
  } else {
    return own_tallies;
  }
}

function pop_last(pending) {
  if (pending instanceof $Empty) {
    return new Error(undefined);
  } else {
    let $ = pending.tail;
    if ($ instanceof $Empty) {
      let only = pending.head;
      return new Ok([only, $List$Empty$const]);
    } else {
      let head = pending.head;
      let rest = $;
      let $1 = pop_last(rest);
      if ($1 instanceof Ok) {
        let last = $1[0][0];
        let init = $1[0][1];
        return new Ok([last, listPrepend(head, init)]);
      } else {
        return new Error(undefined);
      }
    }
  }
}

export function rollback(state, operation, message_id) {
  let $ = pop_last(state.pending);
  if ($ instanceof Ok) {
    let rest = $[0][1];
    let pending_operation = $[0][0].operation;
    let pending_message_id = $[0][0].message_id;
    let $1 = (isEqual(pending_operation, operation)) && (pending_message_id === message_id);
    if ($1) {
      return $result.try$(
        validate_state_operation(state, operation),
        (_) => {
          let before = entries(state);
          return $result.try$(
            validate_operation(state.mode, operation),
            (_) => {
              return $result.try$(
                retain_set_clocks(state),
                (state) => {
                  let own_tallies = rollback_own_tallies(
                    state.own_tallies,
                    operation,
                  );
                  return $result.try$(
                    replay_pending(state.sequenced, rest),
                    (optimistic) => {
                      let new_state = new OrMapState(
                        state.replica_id,
                        state.mode,
                        state.sequenced,
                        optimistic,
                        state.authored,
                        own_tallies,
                        state.authored_mv_registers,
                        state.register_clock,
                        state.set_clocks,
                        rest,
                        state.next_pending_message_id,
                      );
                      return new Ok(
                        [new_state, events_between(before, entries(new_state))],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    } else {
      return new Error(
        new UnexpectedRollback(
          (("expected newest pending op with message id " + $int.to_string(
            pending_message_id,
          )) + ", got message id ") + $int.to_string(message_id),
        ),
      );
    }
  } else {
    return new Error(new UnexpectedRollback("pending queue is empty"));
  }
}

export function apply_stashed_operation(state, operation) {
  let before = entries(state);
  return $result.try$(
    observe_set_operation(state, operation),
    (state) => {
      let delta = operation_delta(operation);
      return $result.try$(
        validate_state_operation(state, operation),
        (_) => {
          return $result.try$(
            apply_delta(state.optimistic, delta),
            (optimistic) => {
              return $result.try$(
                apply_delta(state.authored, delta),
                (authored_map) => {
                  return $result.try$(
                    observe_mv_registers(
                      state.authored_mv_registers,
                      state.mode,
                      optimistic,
                      state.replica_id,
                    ),
                    (authored) => {
                      let message_id = state.next_pending_message_id;
                      let new_state = new OrMapState(
                        state.replica_id,
                        state.mode,
                        state.sequenced,
                        optimistic,
                        authored_map,
                        state.own_tallies,
                        authored,
                        state.register_clock,
                        state.set_clocks,
                        $list.append(
                          state.pending,
                          toList([new PendingOperation(operation, message_id)]),
                        ),
                        message_id + 1,
                      );
                      return $result.try$(
                        retain_set_clocks(new_state),
                        (new_state) => {
                          return new Ok(
                            [
                              new_state,
                              events_between(before, entries(new_state)),
                              operation,
                              message_id,
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
        },
      );
    },
  );
}

export function promote_attach(state) {
  return new OrMapState(
    state.replica_id,
    state.mode,
    state.optimistic,
    state.optimistic,
    state.authored,
    state.own_tallies,
    state.authored_mv_registers,
    state.register_clock,
    state.set_clocks,
    $List$Empty$const,
    state.next_pending_message_id,
  );
}

export function summary(state) {
  return $or_map.to_json(state.sequenced);
}

function unsupported_spec_error(spec) {
  return new $json.UnableToDecode(
    toList([
      new $decode.DecodeError(
        "pn_counter, lww_register, or_set, or mv_register",
        spec,
        toList(["state", "crdt_spec"]),
      ),
    ]),
  );
}

function from_legacy_summary(parsed, mode, replica_id, spec, authored) {
  return $result.try$(
    (() => {
      let _pipe = $or_map.merge(
        $or_map.new$(replica_id, mode_to_spec(mode)),
        parsed,
      );
      return $result.map_error(
        _pipe,
        (_) => { return unsupported_spec_error(spec); },
      );
    })(),
    (sequenced) => {
      return new Ok(
        new OrMapState(
          replica_id,
          mode,
          sequenced,
          sequenced,
          sequenced,
          $dict.new$(),
          authored,
          $dict.new$(),
          $or_map_set_leaf.new_clocks(),
          $List$Empty$const,
          0,
        ),
      );
    },
  );
}

function set_decode_error(error) {
  return new $json.UnableToDecode(
    toList([
      new $decode.DecodeError(
        "valid OR-set map state",
        $string.inspect(error),
        toList(["state"]),
      ),
    ]),
  );
}

export function from_sequenced(sequenced, mode, replica_id) {
  let $ = merge_map(
    mode,
    $or_map.new$(replica_id, mode_to_spec(mode)),
    sequenced,
  );
  if ($ instanceof Ok) {
    let rebranded = $[0];
    return $result.try$(
      observe_mv_registers($dict.new$(), mode, rebranded, replica_id),
      (authored) => {
        return retain_set_clocks(
          new OrMapState(
            replica_id,
            mode,
            rebranded,
            rebranded,
            rebranded,
            $dict.new$(),
            authored,
            $dict.new$(),
            $or_map_set_leaf.new_clocks(),
            $List$Empty$const,
            0,
          ),
        );
      },
    );
  } else {
    return $;
  }
}

export function from_summary(summary_json, replica_id) {
  return $result.try$(
    $json.parse(summary_json, $decode.at(toList(["v"]), $decode.int)),
    (version) => {
      return $result.try$(
        (() => {
          if (version === 1) {
            return $json.parse(
              summary_json,
              $decode.at(toList(["state", "crdt_spec"]), $decode.string),
            );
          } else if (version === 2) {
            return $json.parse(
              summary_json,
              $decode.at(toList(["state", "crdt_spec"]), $decode.string),
            );
          } else {
            return $result.try$(
              $or_map.from_json(summary_json),
              (map) => {
                return $result.try$(
                  (() => {
                    let _pipe = native_mode(map);
                    return $result.map_error(_pipe, set_decode_error);
                  })(),
                  (mode) => {
                    return new Ok($crdt.spec_name(mode_to_spec(mode)));
                  },
                );
              },
            );
          }
        })(),
        (spec) => {
          return $result.try$(
            (() => {
              let _pipe = spec_string_to_mode(spec);
              return $result.map_error(
                _pipe,
                (_) => { return unsupported_spec_error(spec); },
              );
            })(),
            (mode) => {
              return $result.try$(
                (() => {
                  if (mode instanceof TallyMode) {
                    return new Ok($dict.new$());
                  } else if (mode instanceof RegisterMode) {
                    return new Ok($dict.new$());
                  } else if (mode instanceof OrSetMode) {
                    return new Ok($dict.new$());
                  } else {
                    return decode_mv_registers(summary_json, replica_id);
                  }
                })(),
                (authored) => {
                  return $result.try$(
                    (() => {
                      if (mode instanceof TallyMode) {
                        if (version === 1) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else if (version === 2) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else {
                          return $or_map.from_json(summary_json);
                        }
                      } else if (mode instanceof RegisterMode) {
                        if (version === 1) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else if (version === 2) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else {
                          return $or_map.from_json(summary_json);
                        }
                      } else if (mode instanceof OrSetMode) {
                        let _pipe = $or_map_set_leaf.decode_state(summary_json);
                        return $result.map_error(
                          _pipe,
                          (error) => {
                            return set_decode_error(set_error(error));
                          },
                        );
                      } else {
                        if (version === 1) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else if (version === 2) {
                          return $or_map.import_legacy(
                            summary_json,
                            mode_to_spec(mode),
                            $decode.string,
                            replica_id,
                          );
                        } else {
                          return $or_map.from_json(summary_json);
                        }
                      }
                    })(),
                    (parsed) => {
                      if (mode instanceof TallyMode) {
                        return from_legacy_summary(
                          parsed,
                          mode,
                          replica_id,
                          spec,
                          authored,
                        );
                      } else if (mode instanceof RegisterMode) {
                        return from_legacy_summary(
                          parsed,
                          mode,
                          replica_id,
                          spec,
                          authored,
                        );
                      } else if (mode instanceof OrSetMode) {
                        let _pipe = from_sequenced(parsed, mode, replica_id);
                        return $result.map_error(_pipe, set_decode_error);
                      } else {
                        return from_legacy_summary(
                          parsed,
                          mode,
                          replica_id,
                          spec,
                          authored,
                        );
                      }
                    },
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

export function check_cache_coherence(state) {
  let $ = replay_pending(state.sequenced, state.pending);
  if ($ instanceof Ok) {
    let recomputed = $[0];
    let $1 = isEqual(recomputed, state.optimistic);
    if ($1) {
      return new Ok(undefined);
    } else {
      return new Error("optimistic cache diverged from sequenced + pending");
    }
  } else {
    return new Error("a pending operation has an invalid delta");
  }
}

/**
 * Bind the operation intent to one sparse delta. Call this for decoded wire
 * operations and direct kernel input. Validation does not depend on delivery
 * order, so duplicate delivery and stash replay remain valid.
 */
export function validate_operation_intent(operation) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(
        (() => {
          let _pipe = operation_delta(operation);
          let _pipe$1 = $or_map.delta_to_json(_pipe);
          return $json.to_string(_pipe$1);
        })(),
        $decode.at(toList(["state", "spec"]), $decode.string),
      );
      return $result.map_error(
        _pipe,
        (error) => { return new CorruptDelta($string.inspect(error)); },
      );
    })(),
    (spec) => {
      return $result.try$(
        (() => {
          let _pipe = $crdt.spec_from_json_with(spec, $decode.string);
          return $result.map_error(
            _pipe,
            (error) => { return new CorruptDelta($string.inspect(error)); },
          );
        })(),
        (spec) => {
          return $result.try$(
            spec_to_mode(spec),
            (mode) => { return validate_operation(mode, operation); },
          );
        },
      );
    },
  );
}
