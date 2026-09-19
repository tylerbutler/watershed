/// <reference types="./crdt.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.mjs";
import * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.mjs";
import * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.mjs";
import * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $g_set from "../../lattice_sets/lattice_sets/g_set.mjs";
import * as $or_set from "../../lattice_sets/lattice_sets/or_set.mjs";
import * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.mjs";
import * as $text from "../../lattice_text/lattice_text/text.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $lww from "../lattice_maps/internal/lww_map_engine.mjs";
import * as $observed from "../lattice_maps/internal/or_map_engine.mjs";

export class CrdtGCounter extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtGCounter = ($0) => new CrdtGCounter($0);
export const Crdt$isCrdtGCounter = (value) => value instanceof CrdtGCounter;
export const Crdt$CrdtGCounter$0 = (value) => value[0];

export class CrdtPnCounter extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtPnCounter = ($0) => new CrdtPnCounter($0);
export const Crdt$isCrdtPnCounter = (value) => value instanceof CrdtPnCounter;
export const Crdt$CrdtPnCounter$0 = (value) => value[0];

export class CrdtLwwRegister extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtLwwRegister = ($0) => new CrdtLwwRegister($0);
export const Crdt$isCrdtLwwRegister = (value) =>
  value instanceof CrdtLwwRegister;
export const Crdt$CrdtLwwRegister$0 = (value) => value[0];

export class CrdtMvRegister extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtMvRegister = ($0) => new CrdtMvRegister($0);
export const Crdt$isCrdtMvRegister = (value) => value instanceof CrdtMvRegister;
export const Crdt$CrdtMvRegister$0 = (value) => value[0];

export class CrdtGSet extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtGSet = ($0) => new CrdtGSet($0);
export const Crdt$isCrdtGSet = (value) => value instanceof CrdtGSet;
export const Crdt$CrdtGSet$0 = (value) => value[0];

export class CrdtTwoPSet extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtTwoPSet = ($0) => new CrdtTwoPSet($0);
export const Crdt$isCrdtTwoPSet = (value) => value instanceof CrdtTwoPSet;
export const Crdt$CrdtTwoPSet$0 = (value) => value[0];

export class CrdtOrSet extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtOrSet = ($0) => new CrdtOrSet($0);
export const Crdt$isCrdtOrSet = (value) => value instanceof CrdtOrSet;
export const Crdt$CrdtOrSet$0 = (value) => value[0];

export class CrdtVersionVector extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtVersionVector = ($0) => new CrdtVersionVector($0);
export const Crdt$isCrdtVersionVector = (value) =>
  value instanceof CrdtVersionVector;
export const Crdt$CrdtVersionVector$0 = (value) => value[0];

export class CrdtSequence extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtSequence = ($0) => new CrdtSequence($0);
export const Crdt$isCrdtSequence = (value) => value instanceof CrdtSequence;
export const Crdt$CrdtSequence$0 = (value) => value[0];

export class CrdtText extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtText = ($0) => new CrdtText($0);
export const Crdt$isCrdtText = (value) => value instanceof CrdtText;
export const Crdt$CrdtText$0 = (value) => value[0];

export class CrdtOrMap extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtOrMap = ($0) => new CrdtOrMap($0);
export const Crdt$isCrdtOrMap = (value) => value instanceof CrdtOrMap;
export const Crdt$CrdtOrMap$0 = (value) => value[0];

export class CrdtLwwMap extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Crdt$CrdtLwwMap = ($0) => new CrdtLwwMap($0);
export const Crdt$isCrdtLwwMap = (value) => value instanceof CrdtLwwMap;
export const Crdt$CrdtLwwMap$0 = (value) => value[0];

export class GCounterSpec extends $CustomType {}
export const CrdtSpec$GCounterSpec$const = new GCounterSpec();
export const CrdtSpec$GCounterSpec = () => CrdtSpec$GCounterSpec$const;
export const CrdtSpec$isGCounterSpec = (value) => value instanceof GCounterSpec;

export class PnCounterSpec extends $CustomType {}
export const CrdtSpec$PnCounterSpec$const = new PnCounterSpec();
export const CrdtSpec$PnCounterSpec = () => CrdtSpec$PnCounterSpec$const;
export const CrdtSpec$isPnCounterSpec = (value) =>
  value instanceof PnCounterSpec;

export class LwwRegisterSpec extends $CustomType {
  constructor(initial_value) {
    super();
    this.initial_value = initial_value;
  }
}
export const CrdtSpec$LwwRegisterSpec = (initial_value) =>
  new LwwRegisterSpec(initial_value);
export const CrdtSpec$isLwwRegisterSpec = (value) =>
  value instanceof LwwRegisterSpec;
export const CrdtSpec$LwwRegisterSpec$initial_value = (value) =>
  value.initial_value;
export const CrdtSpec$LwwRegisterSpec$0 = (value) => value.initial_value;

export class MvRegisterSpec extends $CustomType {}
export const CrdtSpec$MvRegisterSpec$const = new MvRegisterSpec();
export const CrdtSpec$MvRegisterSpec = () => CrdtSpec$MvRegisterSpec$const;
export const CrdtSpec$isMvRegisterSpec = (value) =>
  value instanceof MvRegisterSpec;

export class GSetSpec extends $CustomType {}
export const CrdtSpec$GSetSpec$const = new GSetSpec();
export const CrdtSpec$GSetSpec = () => CrdtSpec$GSetSpec$const;
export const CrdtSpec$isGSetSpec = (value) => value instanceof GSetSpec;

export class TwoPSetSpec extends $CustomType {}
export const CrdtSpec$TwoPSetSpec$const = new TwoPSetSpec();
export const CrdtSpec$TwoPSetSpec = () => CrdtSpec$TwoPSetSpec$const;
export const CrdtSpec$isTwoPSetSpec = (value) => value instanceof TwoPSetSpec;

export class OrSetSpec extends $CustomType {}
export const CrdtSpec$OrSetSpec$const = new OrSetSpec();
export const CrdtSpec$OrSetSpec = () => CrdtSpec$OrSetSpec$const;
export const CrdtSpec$isOrSetSpec = (value) => value instanceof OrSetSpec;

export class SequenceSpec extends $CustomType {}
export const CrdtSpec$SequenceSpec$const = new SequenceSpec();
export const CrdtSpec$SequenceSpec = () => CrdtSpec$SequenceSpec$const;
export const CrdtSpec$isSequenceSpec = (value) => value instanceof SequenceSpec;

export class TextSpec extends $CustomType {}
export const CrdtSpec$TextSpec$const = new TextSpec();
export const CrdtSpec$TextSpec = () => CrdtSpec$TextSpec$const;
export const CrdtSpec$isTextSpec = (value) => value instanceof TextSpec;

export class OrMapSpec extends $CustomType {
  constructor(child_spec) {
    super();
    this.child_spec = child_spec;
  }
}
export const CrdtSpec$OrMapSpec = (child_spec) => new OrMapSpec(child_spec);
export const CrdtSpec$isOrMapSpec = (value) => value instanceof OrMapSpec;
export const CrdtSpec$OrMapSpec$child_spec = (value) => value.child_spec;
export const CrdtSpec$OrMapSpec$0 = (value) => value.child_spec;

export class LwwMapSpec extends $CustomType {
  constructor(child_spec) {
    super();
    this.child_spec = child_spec;
  }
}
export const CrdtSpec$LwwMapSpec = (child_spec) => new LwwMapSpec(child_spec);
export const CrdtSpec$isLwwMapSpec = (value) => value instanceof LwwMapSpec;
export const CrdtSpec$LwwMapSpec$child_spec = (value) => value.child_spec;
export const CrdtSpec$LwwMapSpec$0 = (value) => value.child_spec;

export class NoChange extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const CrdtDelta$NoChange = ($0) => new NoChange($0);
export const CrdtDelta$isNoChange = (value) => value instanceof NoChange;
export const CrdtDelta$NoChange$0 = (value) => value[0];

export class StateDelta extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const CrdtDelta$StateDelta = ($0) => new StateDelta($0);
export const CrdtDelta$isStateDelta = (value) => value instanceof StateDelta;
export const CrdtDelta$StateDelta$0 = (value) => value[0];

export class OrMapChange extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const CrdtDelta$OrMapChange = ($0) => new OrMapChange($0);
export const CrdtDelta$isOrMapChange = (value) => value instanceof OrMapChange;
export const CrdtDelta$OrMapChange$0 = (value) => value[0];

class ORMap extends $CustomType {
  constructor(replica, spec, state) {
    super();
    this.replica = replica;
    this.spec = spec;
    this.state = state;
  }
}

class ORMapDelta extends $CustomType {
  constructor(replica, spec, state) {
    super();
    this.replica = replica;
    this.spec = spec;
    this.state = state;
  }
}

class LWWMap extends $CustomType {
  constructor(replica, spec, state) {
    super();
    this.replica = replica;
    this.spec = spec;
    this.state = state;
  }
}

export class TypeMismatch extends $CustomType {
  constructor(expected, found) {
    super();
    this.expected = expected;
    this.found = found;
  }
}
export const MergeError$TypeMismatch = (expected, found) =>
  new TypeMismatch(expected, found);
export const MergeError$isTypeMismatch = (value) =>
  value instanceof TypeMismatch;
export const MergeError$TypeMismatch$expected = (value) => value.expected;
export const MergeError$TypeMismatch$0 = (value) => value.expected;
export const MergeError$TypeMismatch$found = (value) => value.found;
export const MergeError$TypeMismatch$1 = (value) => value.found;

export class SchemaMismatch extends $CustomType {}
export const MergeError$SchemaMismatch$const = new SchemaMismatch();
export const MergeError$SchemaMismatch = () => MergeError$SchemaMismatch$const;
export const MergeError$isSchemaMismatch = (value) =>
  value instanceof SchemaMismatch;

export class AtKey extends $CustomType {
  constructor(key, cause) {
    super();
    this.key = key;
    this.cause = cause;
  }
}
export const MergeError$AtKey = (key, cause) => new AtKey(key, cause);
export const MergeError$isAtKey = (value) => value instanceof AtKey;
export const MergeError$AtKey$key = (value) => value.key;
export const MergeError$AtKey$0 = (value) => value.key;
export const MergeError$AtKey$cause = (value) => value.cause;
export const MergeError$AtKey$1 = (value) => value.cause;

export class TimestampNotAdvanced extends $CustomType {
  constructor(key, timestamp, floor) {
    super();
    this.key = key;
    this.timestamp = timestamp;
    this.floor = floor;
  }
}
export const MergeError$TimestampNotAdvanced = (key, timestamp, floor) =>
  new TimestampNotAdvanced(key, timestamp, floor);
export const MergeError$isTimestampNotAdvanced = (value) =>
  value instanceof TimestampNotAdvanced;
export const MergeError$TimestampNotAdvanced$key = (value) => value.key;
export const MergeError$TimestampNotAdvanced$0 = (value) => value.key;
export const MergeError$TimestampNotAdvanced$timestamp = (value) =>
  value.timestamp;
export const MergeError$TimestampNotAdvanced$1 = (value) => value.timestamp;
export const MergeError$TimestampNotAdvanced$floor = (value) => value.floor;
export const MergeError$TimestampNotAdvanced$2 = (value) => value.floor;

export class ConflictingWrite extends $CustomType {
  constructor(key, timestamp) {
    super();
    this.key = key;
    this.timestamp = timestamp;
  }
}
export const MergeError$ConflictingWrite = (key, timestamp) =>
  new ConflictingWrite(key, timestamp);
export const MergeError$isConflictingWrite = (value) =>
  value instanceof ConflictingWrite;
export const MergeError$ConflictingWrite$key = (value) => value.key;
export const MergeError$ConflictingWrite$0 = (value) => value.key;
export const MergeError$ConflictingWrite$timestamp = (value) => value.timestamp;
export const MergeError$ConflictingWrite$1 = (value) => value.timestamp;

export class ClockExhausted extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const MergeError$ClockExhausted = (key) => new ClockExhausted(key);
export const MergeError$isClockExhausted = (value) =>
  value instanceof ClockExhausted;
export const MergeError$ClockExhausted$key = (value) => value.key;
export const MergeError$ClockExhausted$0 = (value) => value.key;

export class InvalidTimestamp extends $CustomType {
  constructor(key, timestamp) {
    super();
    this.key = key;
    this.timestamp = timestamp;
  }
}
export const MergeError$InvalidTimestamp = (key, timestamp) =>
  new InvalidTimestamp(key, timestamp);
export const MergeError$isInvalidTimestamp = (value) =>
  value instanceof InvalidTimestamp;
export const MergeError$InvalidTimestamp$key = (value) => value.key;
export const MergeError$InvalidTimestamp$0 = (value) => value.key;
export const MergeError$InvalidTimestamp$timestamp = (value) => value.timestamp;
export const MergeError$InvalidTimestamp$1 = (value) => value.timestamp;

export class CallbackError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const UpdateError$CallbackError = ($0) => new CallbackError($0);
export const UpdateError$isCallbackError = (value) =>
  value instanceof CallbackError;
export const UpdateError$CallbackError$0 = (value) => value[0];

export class CompositionError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const UpdateError$CompositionError = ($0) => new CompositionError($0);
export const UpdateError$isCompositionError = (value) =>
  value instanceof CompositionError;
export const UpdateError$CompositionError$0 = (value) => value[0];

export class EditContext extends $CustomType {
  constructor(replica_id) {
    super();
    this.replica_id = replica_id;
  }
}
export const EditContext$EditContext = (replica_id) =>
  new EditContext(replica_id);
export const EditContext$isEditContext = (value) =>
  value instanceof EditContext;
export const EditContext$EditContext$replica_id = (value) => value.replica_id;
export const EditContext$EditContext$0 = (value) => value.replica_id;

/**
 * Return the dispatch discriminator.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.default_crdt(crdt.TextSpec, replica_id.new("A"))
 * crdt.type_name(state) // -> "text"
 * ```
 */
export function type_name(value) {
  if (value instanceof CrdtGCounter) {
    return "g_counter";
  } else if (value instanceof CrdtPnCounter) {
    return "pn_counter";
  } else if (value instanceof CrdtLwwRegister) {
    return "lww_register";
  } else if (value instanceof CrdtMvRegister) {
    return "mv_register";
  } else if (value instanceof CrdtGSet) {
    return "g_set";
  } else if (value instanceof CrdtTwoPSet) {
    return "two_p_set";
  } else if (value instanceof CrdtOrSet) {
    return "or_set";
  } else if (value instanceof CrdtVersionVector) {
    return "version_vector";
  } else if (value instanceof CrdtSequence) {
    return "sequence";
  } else if (value instanceof CrdtText) {
    return "text";
  } else if (value instanceof CrdtOrMap) {
    return "or_map";
  } else {
    return "lww_map";
  }
}

/**
 * Return a schema's outer discriminator.
 *
 * This name alone does not identify a complete recursive schema or its defaults.
 *
 * ## Examples
 *
 * ```gleam
 * crdt.spec_name(crdt.OrMapSpec(crdt.LwwRegisterSpec(42))) // -> "or_map"
 * ```
 */
export function spec_name(spec) {
  if (spec instanceof GCounterSpec) {
    return "g_counter";
  } else if (spec instanceof PnCounterSpec) {
    return "pn_counter";
  } else if (spec instanceof LwwRegisterSpec) {
    return "lww_register";
  } else if (spec instanceof MvRegisterSpec) {
    return "mv_register";
  } else if (spec instanceof GSetSpec) {
    return "g_set";
  } else if (spec instanceof TwoPSetSpec) {
    return "two_p_set";
  } else if (spec instanceof OrSetSpec) {
    return "or_set";
  } else if (spec instanceof SequenceSpec) {
    return "sequence";
  } else if (spec instanceof TextSpec) {
    return "text";
  } else if (spec instanceof OrMapSpec) {
    return "or_map";
  } else {
    return "lww_map";
  }
}

export function lww_new(replica, spec) {
  return new LWWMap(replica, spec, $lww.new$());
}

export function or_new(replica, spec) {
  return new ORMap(replica, spec, $observed.new$());
}

/**
 * Create a valid empty/default child for the configured schema.
 *
 * Maps start without entries; Sequence and Text start empty. A register uses
 * its configured initial value at timestamp zero.
 *
 * ## Examples
 *
 * ```gleam
 * let assert crdt.CrdtLwwRegister(register) =
 *   crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new("A"))
 * lww_register.value(register) // -> 42
 * ```
 */
export function default_crdt(spec, replica) {
  if (spec instanceof GCounterSpec) {
    return new CrdtGCounter($g_counter.new$(replica));
  } else if (spec instanceof PnCounterSpec) {
    return new CrdtPnCounter($pn_counter.new$(replica));
  } else if (spec instanceof LwwRegisterSpec) {
    let initial = spec.initial_value;
    return new CrdtLwwRegister($lww_register.new$(initial, 0, replica));
  } else if (spec instanceof MvRegisterSpec) {
    return new CrdtMvRegister($mv_register.new$(replica));
  } else if (spec instanceof GSetSpec) {
    return new CrdtGSet($g_set.new$());
  } else if (spec instanceof TwoPSetSpec) {
    return new CrdtTwoPSet($two_p_set.new$());
  } else if (spec instanceof OrSetSpec) {
    return new CrdtOrSet($or_set.new$(replica));
  } else if (spec instanceof SequenceSpec) {
    return new CrdtSequence($sequence.new$(replica));
  } else if (spec instanceof TextSpec) {
    return new CrdtText($text.new$(replica));
  } else if (spec instanceof OrMapSpec) {
    let child = spec.child_spec;
    return new CrdtOrMap(or_new(replica, child));
  } else {
    let child = spec.child_spec;
    return new CrdtLwwMap(lww_new(replica, child));
  }
}

/**
 * Check complete recursive schema agreement.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.default_crdt(
 *   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new("A"),
 * )
 * crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
 * // -> True
 * crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(0)))
 * // -> False
 * ```
 */
export function matches_spec(value, spec) {
  if (spec instanceof OrMapSpec && value instanceof CrdtOrMap) {
    let child = spec.child_spec;
    let map = value[0];
    return isEqual(map.spec, child);
  } else if (spec instanceof LwwMapSpec && value instanceof CrdtLwwMap) {
    let child = spec.child_spec;
    let map = value[0];
    return isEqual(map.spec, child);
  } else {
    return type_name(value) === spec_name(spec);
  }
}

function check_spec(value, spec) {
  return $bool.guard(
    matches_spec(value, spec),
    new Ok(undefined),
    () => {
      let $ = type_name(value) === spec_name(spec);
      if ($) {
        return new Error(MergeError$SchemaMismatch$const);
      } else {
        return new Error(new TypeMismatch(spec_name(spec), type_name(value)));
      }
    },
  );
}

function same_spec(a, b) {
  return $bool.guard(
    isEqual(a, b),
    new Ok(undefined),
    () => {
      let $ = spec_name(a) === spec_name(b);
      if ($) {
        return new Error(MergeError$SchemaMismatch$const);
      } else {
        return new Error(new TypeMismatch(spec_name(a), spec_name(b)));
      }
    },
  );
}

/**
 * The delta identity is explicit; configured initial values are not bottoms.
 *
 * The replica argument does not affect `NoChange`. It is not an authored write.
 *
 * ## Examples
 *
 * ```gleam
 * crdt.default_delta(crdt.LwwRegisterSpec(42), replica_id.new("A"))
 * // -> crdt.NoChange(crdt.LwwRegisterSpec(42))
 * ```
 */
export function default_delta(spec, _) {
  return new NoChange(spec);
}

/**
 * Return whether this delta has no leaf or membership changes.
 *
 * A `StateDelta` is not treated as empty, even if its child looks like a default.
 * An ORMap update that returns `NoChange` still refreshes outer membership.
 *
 * ## Examples
 *
 * ```gleam
 * crdt.is_empty_delta(crdt.NoChange(crdt.LwwRegisterSpec(42))) // -> True
 * ```
 */
export function is_empty_delta(value) {
  if (value instanceof NoChange) {
    return true;
  } else if (value instanceof StateDelta) {
    return false;
  } else {
    let delta = value[0];
    return $dict.is_empty(delta.state.entries) && (delta.state.clock === 0);
  }
}

export function lww_bind(map, replica) {
  return new LWWMap(replica, map.spec, map.state);
}

function generation_parts(generation) {
  if (generation instanceof $observed.Initial) {
    return toList(["initial"]);
  } else {
    let clock = generation.clock;
    let creator = generation.creator;
    return toList([
      "generation",
      $int.to_string(clock),
      $replica_id.to_string(creator),
    ]);
  }
}

function frame(value) {
  return ($int.to_string($string.byte_size(value)) + ":") + value;
}

function scope(replica, parts) {
  return $replica_id.new$(
    ("lattice-map:" + frame($replica_id.to_string(replica))) + $string.concat(
      $list.map(parts, frame),
    ),
  );
}

function or_identity(replica, key, generation) {
  return scope(
    replica,
    listPrepend("or", listPrepend(key, generation_parts(generation))),
  );
}

function membership_identity(replica, key, generation) {
  return scope(
    replica,
    listPrepend("or-membership", listPrepend(key, generation_parts(generation))),
  );
}

function option_bind(value, replica) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return new Some(bind(value$1, replica));
  } else {
    return value;
  }
}

export function or_bind(map, replica) {
  return new ORMap(
    replica,
    map.spec,
    (() => {
      let _record = map.state;
      return new $observed.State(
        _record.clock,
        $dict.map_values(
          map.state.entries,
          (key, entry) => {
            return new $observed.Entry(
              entry.generation,
              $or_set.merge(
                $or_set.new$(
                  membership_identity(replica, key, entry.generation),
                ),
                entry.membership,
              ),
              option_bind(
                entry.value,
                or_identity(replica, key, entry.generation),
              ),
            );
          },
        ),
      );
    })(),
  );
}

/**
 * Bind local editing identity without changing historical IDs or write authors.
 *
 * Use this after loading or adopting a remote state. It does not author a new
 * LWWRegister write; use `lww_register.set` for that operation.
 *
 * ## Examples
 *
 * ```gleam
 * let original = crdt.CrdtLwwRegister(
 *   lww_register.new("Old write", 1, replica_id.new("A")),
 * )
 * crdt.bind(original, replica_id.new("B")) // -> original
 * ```
 */
export function bind(value, replica) {
  if (value instanceof CrdtGCounter) {
    let c = value[0];
    return new CrdtGCounter($g_counter.merge($g_counter.new$(replica), c));
  } else if (value instanceof CrdtPnCounter) {
    let c = value[0];
    return new CrdtPnCounter($pn_counter.merge($pn_counter.new$(replica), c));
  } else if (value instanceof CrdtLwwRegister) {
    return value;
  } else if (value instanceof CrdtMvRegister) {
    let c = value[0];
    return new CrdtMvRegister($mv_register.merge($mv_register.new$(replica), c));
  } else if (value instanceof CrdtGSet) {
    return value;
  } else if (value instanceof CrdtTwoPSet) {
    return value;
  } else if (value instanceof CrdtOrSet) {
    let c = value[0];
    return new CrdtOrSet($or_set.merge($or_set.new$(replica), c));
  } else if (value instanceof CrdtVersionVector) {
    return value;
  } else if (value instanceof CrdtSequence) {
    let c = value[0];
    return new CrdtSequence($sequence.bind(c, replica));
  } else if (value instanceof CrdtText) {
    let c = value[0];
    return new CrdtText($text.bind(c, replica));
  } else if (value instanceof CrdtOrMap) {
    let c = value[0];
    return new CrdtOrMap(or_bind(c, replica));
  } else {
    let c = value[0];
    return new CrdtLwwMap(lww_bind(c, replica));
  }
}

function lww_error(error) {
  if (error instanceof $lww.TimestampNotAdvanced) {
    let key = error.key;
    let timestamp = error.timestamp;
    let floor = error.floor;
    return new TimestampNotAdvanced(key, timestamp, floor);
  } else if (error instanceof $lww.ConflictingWrite) {
    let key = error.key;
    let timestamp = error.timestamp;
    return new ConflictingWrite(key, timestamp);
  } else {
    let key = error.key;
    let timestamp = error.timestamp;
    return new InvalidTimestamp(key, timestamp);
  }
}

export function lww_merge_as(a, b, replica) {
  return $result.try$(
    same_spec(a.spec, b.spec),
    (_) => {
      return $result.try$(
        (() => {
          let _pipe = $lww.merge(
            a.state,
            b.state,
            (a, b) => { return isEqual(a, b); },
          );
          return $result.map_error(_pipe, lww_error);
        })(),
        (state) => { return new Ok(new LWWMap(replica, a.spec, state)); },
      );
    },
  );
}

export function or_merge_as(a, b, replica) {
  return $result.try$(
    same_spec(a.spec, b.spec),
    (_) => {
      return $result.try$(
        $observed.join(
          a.state,
          b.state,
          (key, generation, left, right) => {
            let identity = or_identity(replica, key, generation);
            let _block;
            if (left instanceof Some) {
              if (right instanceof Some) {
                let a$1 = left[0];
                let b$1 = right[0];
                let _pipe = merge(a$1, b$1, identity);
                _block = $result.map(
                  _pipe,
                  (var0) => { return new Some(var0); },
                );
              } else {
                let a$1 = left[0];
                _block = new Ok(new Some(bind(a$1, identity)));
              }
            } else if (right instanceof Some) {
              let b$1 = right[0];
              _block = new Ok(new Some(bind(b$1, identity)));
            } else {
              _block = new Ok(Option$None$const);
            }
            let value = _block;
            return $result.map_error(
              value,
              (_capture) => { return new AtKey(key, _capture); },
            );
          },
        ),
        (state) => {
          return new Ok(or_bind(new ORMap(replica, a.spec, state), replica));
        },
      );
    },
  );
}

/**
 * Merge states with an explicit receiving identity, including incoming-only children.
 *
 * ORMaps join children within the winning generation. LWWMaps select atomic
 * child assignments instead. Different variants or recursive schemas return
 * `Error`; a mismatch is never replaced by a default state.
 *
 * ## Examples
 *
 * ```gleam
 * let a = crdt.default_crdt(
 *   crdt.OrMapSpec(crdt.TextSpec), replica_id.new("A"),
 * )
 * let b = crdt.default_crdt(
 *   crdt.OrMapSpec(crdt.TextSpec), replica_id.new("B"),
 * )
 * let local = replica_id.new("C")
 * let assert Ok(crdt.CrdtOrMap(merged)) = crdt.merge(a, b, local)
 * or_map.replica_id(merged) // -> local
 * ```
 */
export function merge(a, b, replica) {
  let _block;
  if (a instanceof CrdtGCounter) {
    if (b instanceof CrdtGCounter) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtGCounter($g_counter.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtPnCounter) {
    if (b instanceof CrdtPnCounter) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtPnCounter($pn_counter.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtLwwRegister) {
    if (b instanceof CrdtLwwRegister) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtLwwRegister($lww_register.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtMvRegister) {
    if (b instanceof CrdtMvRegister) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtMvRegister($mv_register.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtGSet) {
    if (b instanceof CrdtGSet) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtGSet($g_set.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtTwoPSet) {
    if (b instanceof CrdtTwoPSet) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtTwoPSet($two_p_set.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtOrSet) {
    if (b instanceof CrdtOrSet) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtOrSet($or_set.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtVersionVector) {
    if (b instanceof CrdtVersionVector) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtVersionVector($version_vector.merge(a$1, b$1)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtSequence) {
    if (b instanceof CrdtSequence) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtSequence($sequence.merge(a$1, b$1, replica)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtText) {
    if (b instanceof CrdtText) {
      let a$1 = a[0];
      let b$1 = b[0];
      _block = new Ok(new CrdtText($text.merge(a$1, b$1, replica)));
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (a instanceof CrdtOrMap) {
    if (b instanceof CrdtOrMap) {
      let a$1 = a[0];
      let b$1 = b[0];
      let _pipe = or_merge_as(a$1, b$1, replica);
      _block = $result.map(_pipe, (var0) => { return new CrdtOrMap(var0); });
    } else {
      _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
    }
  } else if (b instanceof CrdtLwwMap) {
    let a$1 = a[0];
    let b$1 = b[0];
    let _pipe = lww_merge_as(a$1, b$1, replica);
    _block = $result.map(_pipe, (var0) => { return new CrdtLwwMap(var0); });
  } else {
    _block = new Error(new TypeMismatch(type_name(a), type_name(b)));
  }
  let merged = _block;
  return $result.map(merged, (_capture) => { return bind(_capture, replica); });
}

/**
 * Validate a delta against the complete child schema.
 *
 * ## Examples
 *
 * ```gleam
 * let delta = crdt.NoChange(crdt.LwwRegisterSpec(42))
 * crdt.matches_delta(delta, crdt.LwwRegisterSpec(42)) // -> True
 * crdt.matches_delta(delta, crdt.LwwRegisterSpec(0)) // -> False
 * ```
 */
export function matches_delta(delta, spec) {
  if (delta instanceof NoChange) {
    let given = delta[0];
    return isEqual(given, spec);
  } else if (delta instanceof StateDelta) {
    let value = delta[0];
    return matches_spec(value, spec);
  } else {
    let delta$1 = delta[0];
    return isEqual(spec, new OrMapSpec(delta$1.spec));
  }
}

function check_delta(delta, spec) {
  if (delta instanceof NoChange) {
    let given = delta[0];
    return same_spec(spec, given);
  } else if (delta instanceof StateDelta) {
    let value = delta[0];
    return check_spec(value, spec);
  } else {
    let delta$1 = delta[0];
    return same_spec(spec, new OrMapSpec(delta$1.spec));
  }
}

function map_default(spec, identity) {
  if (spec instanceof LwwRegisterSpec) {
    let initial = spec.initial_value;
    return new CrdtLwwRegister(
      $lww_register.new$(initial, 0, $replica_id.new$("lattice-map:default")),
    );
  } else {
    return default_crdt(spec, identity);
  }
}

export function or_apply_delta(map, delta) {
  return $result.try$(
    same_spec(map.spec, delta.spec),
    (_) => {
      return $result.try$(
        $observed.join(
          map.state,
          delta.state,
          (key, generation, left, right) => {
            let identity = or_identity(map.replica, key, generation);
            let _block;
            if (right instanceof Some) {
              if (left instanceof None) {
                let $ = right[0];
                if ($ instanceof StateDelta) {
                  let value = $[0];
                  _block = $result.try$(
                    check_spec(value, map.spec),
                    (_) => { return new Ok(new Some(bind(value, identity))); },
                  );
                } else {
                  let change = $;
                  let _block$1;
                  if (left instanceof Some) {
                    let value = left[0];
                    _block$1 = value;
                  } else {
                    _block$1 = map_default(map.spec, identity);
                  }
                  let baseline = _block$1;
                  let _pipe = apply_delta(baseline, change, map.spec, identity);
                  _block = $result.map(
                    _pipe,
                    (var0) => { return new Some(var0); },
                  );
                }
              } else {
                let change = right[0];
                let _block$1;
                if (left instanceof Some) {
                  let value = left[0];
                  _block$1 = value;
                } else {
                  _block$1 = map_default(map.spec, identity);
                }
                let baseline = _block$1;
                let _pipe = apply_delta(baseline, change, map.spec, identity);
                _block = $result.map(
                  _pipe,
                  (var0) => { return new Some(var0); },
                );
              }
            } else if (left instanceof Some) {
              let value = left[0];
              _block = new Ok(new Some(bind(value, identity)));
            } else {
              _block = new Ok(Option$None$const);
            }
            let value = _block;
            return $result.map_error(
              value,
              (_capture) => { return new AtKey(key, _capture); },
            );
          },
        ),
        (state) => {
          return new Ok(
            or_bind(new ORMap(map.replica, map.spec, state), map.replica),
          );
        },
      );
    },
  );
}

/**
 * Apply a typed change without trusting a caller-supplied replacement state.
 *
 * The current state and the delta must both match `spec`. The returned state is
 * bound to `replica`; nested ORMap changes retain their generation checks.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let before = sequence.new(local)
 * let assert Ok(#(after, change)) =
 *   sequence.insert_with_delta(before, 0, 42)
 * crdt.apply_delta(
 *   crdt.CrdtSequence(before), crdt.StateDelta(crdt.CrdtSequence(change)),
 *   crdt.SequenceSpec, local,
 * )
 * // -> Ok(crdt.CrdtSequence(after))
 * ```
 */
export function apply_delta(value, delta, spec, replica) {
  return $result.try$(
    check_spec(value, spec),
    (_) => {
      return $result.try$(
        check_delta(delta, spec),
        (_) => {
          if (delta instanceof NoChange) {
            return new Ok(bind(value, replica));
          } else if (delta instanceof StateDelta) {
            let change = delta[0];
            return merge(value, change, replica);
          } else if (value instanceof CrdtOrMap) {
            let change = delta[0];
            let map = value[0];
            let _pipe = or_apply_delta(or_bind(map, replica), change);
            return $result.map(_pipe, (var0) => { return new CrdtOrMap(var0); });
          } else {
            return new Error(new TypeMismatch("or_map", type_name(value)));
          }
        },
      );
    },
  );
}

export function or_merge_deltas(a, b) {
  return $result.try$(
    same_spec(a.spec, b.spec),
    (_) => {
      return $result.try$(
        $observed.join(
          a.state,
          b.state,
          (key, generation, left, right) => {
            let _block;
            if (left instanceof Some) {
              if (right instanceof Some) {
                let a_delta = left[0];
                let b_delta = right[0];
                let _pipe = merge_deltas(
                  a_delta,
                  b_delta,
                  a.spec,
                  or_identity(a.replica, key, generation),
                );
                _block = $result.map(
                  _pipe,
                  (var0) => { return new Some(var0); },
                );
              } else {
                let value = left[0];
                _block = new Ok(new Some(value));
              }
            } else if (right instanceof Some) {
              let value = right[0];
              _block = new Ok(new Some(value));
            } else {
              _block = new Ok(Option$None$const);
            }
            let value = _block;
            return $result.map_error(
              value,
              (_capture) => { return new AtKey(key, _capture); },
            );
          },
        ),
        (state) => { return new Ok(new ORMapDelta(a.replica, a.spec, state)); },
      );
    },
  );
}

/**
 * Batch sparse ORMap changes without expanding them to child snapshots.
 *
 * A batch that includes an explicit `StateDelta` snapshot may remain a snapshot.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let map = or_map.new(local, crdt.LwwRegisterSpec(42))
 * let assert Ok(#(_, change)) =
 *   or_map.update_with_delta(map, "answer", fn(value) { value })
 * let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 * crdt.merge_deltas(
 *   crdt.NoChange(schema), crdt.OrMapChange(change), schema, local,
 * )
 * // -> Ok(crdt.OrMapChange(change))
 * ```
 */
export function merge_deltas(a, b, spec, replica) {
  return $result.try$(
    check_delta(a, spec),
    (_) => {
      return $result.try$(
        check_delta(b, spec),
        (_) => {
          if (a instanceof NoChange) {
            return new Ok(b);
          } else if (a instanceof StateDelta) {
            if (b instanceof NoChange) {
              return new Ok(a);
            } else if (b instanceof StateDelta) {
              let other = b;
              let a$1 = a[0];
              let _pipe = apply_delta(a$1, other, spec, replica);
              return $result.map(
                _pipe,
                (var0) => { return new StateDelta(var0); },
              );
            } else {
              let other = b;
              let a$1 = a[0];
              let _pipe = apply_delta(a$1, other, spec, replica);
              return $result.map(
                _pipe,
                (var0) => { return new StateDelta(var0); },
              );
            }
          } else if (b instanceof NoChange) {
            return new Ok(a);
          } else if (b instanceof StateDelta) {
            let other = a;
            let b$1 = b[0];
            let _pipe = apply_delta(b$1, other, spec, replica);
            return $result.map(
              _pipe,
              (var0) => { return new StateDelta(var0); },
            );
          } else {
            let a$1 = a[0];
            let b$1 = b[0];
            let _pipe = or_merge_deltas(a$1, b$1);
            return $result.map(
              _pipe,
              (var0) => { return new OrMapChange(var0); },
            );
          }
        },
      );
    },
  );
}

export function or_replica(map) {
  return map.replica;
}

export function or_spec(map) {
  return map.spec;
}

export function or_get(map, key) {
  return $result.try$(
    $dict.get(map.state.entries, key),
    (entry) => {
      let $ = $observed.active(entry, key);
      let $1 = entry.value;
      if ($ && $1 instanceof Some) {
        let value = $1[0];
        return new Ok(
          bind(value, or_identity(map.replica, key, entry.generation)),
        );
      } else {
        return new Error(undefined);
      }
    },
  );
}

export function or_keys(map) {
  return $dict.fold(
    map.state.entries,
    $List$Empty$const,
    (keys, key, entry) => {
      let $ = $observed.active(entry, key);
      let $1 = entry.value;
      if ($ && $1 instanceof Some) {
        return listPrepend(key, keys);
      } else {
        return keys;
      }
    },
  );
}

export function or_values(map) {
  return $list.filter_map(
    or_keys(map),
    (_capture) => { return or_get(map, _capture); },
  );
}

export function or_value_count(map) {
  return $dict.fold(
    map.state.entries,
    0,
    (count, _, entry) => {
      let $ = entry.value;
      if ($ instanceof Some) {
        return count + 1;
      } else {
        return count;
      }
    },
  );
}

export function or_empty_delta(map) {
  return new ORMapDelta(map.replica, map.spec, $observed.new$());
}

export function or_update_delta(map, key, callback) {
  let _block;
  let $ = $dict.get(map.state.entries, key);
  if ($ instanceof Ok) {
    let entry = $[0];
    _block = !$observed.active(entry, key);
  } else {
    _block = false;
  }
  let needs_generation = _block;
  return $bool.guard(
    needs_generation && (map.state.clock >= 9_007_199_254_740_991),
    new Error(new CompositionError(new ClockExhausted(key))),
    () => {
      let entry = $observed.prepare(map.state, key, map.replica);
      let identity = or_identity(map.replica, key, entry.generation);
      let _block$1;
      let $1 = entry.value;
      if ($1 instanceof Some) {
        let value = $1[0];
        _block$1 = bind(value, identity);
      } else {
        _block$1 = map_default(map.spec, identity);
      }
      let current = _block$1;
      return $result.try$(
        (() => {
          let _pipe = callback(current, new EditContext(identity));
          return $result.map_error(
            _pipe,
            (var0) => { return new CallbackError(var0); },
          );
        })(),
        (change) => {
          return $result.try$(
            (() => {
              let _pipe = check_delta(change, map.spec);
              return $result.map_error(
                _pipe,
                (error) => {
                  return new CompositionError(new AtKey(key, error));
                },
              );
            })(),
            (_) => {
              return $result.try$(
                (() => {
                  let _block$2;
                  let $2 = entry.value;
                  let $3 = map.spec;
                  if ($2 instanceof None && $3 instanceof LwwRegisterSpec) {
                    let _pipe = apply_delta(current, change, map.spec, identity);
                    _block$2 = $result.map(
                      _pipe,
                      (var0) => { return new StateDelta(var0); },
                    );
                  } else {
                    _block$2 = new Ok(change);
                  }
                  let _pipe = _block$2;
                  return $result.map_error(
                    _pipe,
                    (error) => {
                      return new CompositionError(new AtKey(key, error));
                    },
                  );
                })(),
                (change) => {
                  let membership = $or_set.merge(
                    $or_set.new$(
                      membership_identity(map.replica, key, entry.generation),
                    ),
                    entry.membership,
                  );
                  let $2 = $or_set.add_with_delta(membership, key);
                  let membership_delta = $2[1];
                  let delta = new ORMapDelta(
                    map.replica,
                    map.spec,
                    $observed.singleton(
                      key,
                      new $observed.Entry(
                        entry.generation,
                        membership_delta,
                        new Some(change),
                      ),
                      map.state.clock,
                    ),
                  );
                  return $result.try$(
                    (() => {
                      let _pipe = or_apply_delta(map, delta);
                      return $result.map_error(
                        _pipe,
                        (var0) => { return new CompositionError(var0); },
                      );
                    })(),
                    (updated) => { return new Ok([updated, delta]); },
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

export function or_update_with_delta(map, key, callback) {
  let outcome = or_update_delta(
    map,
    key,
    (value, _) => { return new Ok(new StateDelta(callback(value))); },
  );
  if (outcome instanceof Ok) {
    return outcome;
  } else {
    let $ = outcome[0];
    if ($ instanceof CallbackError) {
      let error = $[0];
      return new Error(error);
    } else {
      let $1 = $[0];
      if ($1 instanceof AtKey) {
        let $2 = $1.cause;
        if ($2 instanceof TypeMismatch) {
          let expected = $2.expected;
          let found = $2.found;
          return new Error(new TypeMismatch(expected, found));
        } else {
          let error = $1;
          return new Error(error);
        }
      } else {
        let error = $1;
        return new Error(error);
      }
    }
  }
}

export function or_remove_with_delta(map, key) {
  let $ = $observed.remove(map.state, key);
  let state = $[0];
  let delta = $[1];
  return [
    new ORMap(map.replica, map.spec, state),
    new ORMapDelta(map.replica, map.spec, delta),
  ];
}

export function or_prune(map, stable) {
  return new ORMap(map.replica, map.spec, $observed.prune(map.state, stable));
}

export function lww_replica(map) {
  return map.replica;
}

export function lww_spec(map) {
  return map.spec;
}

export function lww_get(map, key) {
  let $ = $dict.get(map.state.entries, key);
  if ($ instanceof Ok) {
    let $1 = $[0].value;
    if ($1 instanceof Some) {
      let timestamp = $[0].timestamp;
      let value = $1[0];
      return new Ok(
        bind(
          value,
          scope(
            map.replica,
            toList(["lww-view", key, $int.to_string(timestamp)]),
          ),
        ),
      );
    } else {
      return new Error(undefined);
    }
  } else {
    return new Error(undefined);
  }
}

export function lww_set(map, key, value, timestamp) {
  return $result.try$(
    (() => {
      let _pipe = check_spec(value, map.spec);
      return $result.map_error(
        _pipe,
        (_capture) => { return new AtKey(key, _capture); },
      );
    })(),
    (_) => {
      let _block;
      if (value instanceof CrdtOrMap) {
        let child = value[0];
        _block = new CrdtOrMap(or_bind(child, child.replica));
      } else {
        _block = value;
      }
      let value$1 = _block;
      return $result.try$(
        (() => {
          let _pipe = $lww.put(
            map.state,
            key,
            new $lww.Entry(
              new Some(value$1),
              timestamp,
              new $lww.Modern(map.replica),
            ),
            (a, b) => { return isEqual(a, b); },
          );
          return $result.map_error(_pipe, lww_error);
        })(),
        (state) => { return new Ok(new LWWMap(map.replica, map.spec, state)); },
      );
    },
  );
}

export function lww_update(map, key, timestamp, callback) {
  return $result.try$(
    (() => {
      let _pipe = $lww.check_timestamp(map.state, key, timestamp);
      return $result.map_error(
        _pipe,
        (error) => { return new CompositionError(lww_error(error)); },
      );
    })(),
    (_) => {
      let identity = scope(
        map.replica,
        toList(["lww-write", key, $int.to_string(timestamp)]),
      );
      let _block;
      let $ = $dict.get(map.state.entries, key);
      if ($ instanceof Ok) {
        let $1 = $[0].value;
        if ($1 instanceof Some) {
          let value = $1[0];
          _block = bind(value, identity);
        } else {
          _block = default_crdt(map.spec, identity);
        }
      } else {
        _block = default_crdt(map.spec, identity);
      }
      let current = _block;
      return $result.try$(
        (() => {
          let _pipe = callback(current, new EditContext(identity));
          return $result.map_error(
            _pipe,
            (var0) => { return new CallbackError(var0); },
          );
        })(),
        (value) => {
          let _pipe = lww_set(map, key, value, timestamp);
          return $result.map_error(
            _pipe,
            (var0) => { return new CompositionError(var0); },
          );
        },
      );
    },
  );
}

export function lww_remove(map, key, timestamp) {
  return $result.try$(
    (() => {
      let _pipe = $lww.put(
        map.state,
        key,
        new $lww.Entry(
          Option$None$const,
          timestamp,
          new $lww.Modern(map.replica),
        ),
        (a, b) => { return isEqual(a, b); },
      );
      return $result.map_error(_pipe, lww_error);
    })(),
    (state) => { return new Ok(new LWWMap(map.replica, map.spec, state)); },
  );
}

export function lww_keys(map) {
  return $dict.fold(
    map.state.entries,
    $List$Empty$const,
    (keys, key, entry) => {
      let $ = entry.value;
      if ($ instanceof Some) {
        return listPrepend(key, keys);
      } else {
        return keys;
      }
    },
  );
}

export function lww_values(map) {
  return $list.filter_map(
    lww_keys(map),
    (_capture) => { return lww_get(map, _capture); },
  );
}

export function lww_tombstone_count(map) {
  return $dict.size(map.state.entries) - $list.length(lww_keys(map));
}

export function lww_pruned_timestamp(map) {
  return map.state.pruned_timestamp;
}

export function lww_prune(map, stable) {
  return new LWWMap(map.replica, map.spec, $lww.prune(map.state, stable));
}

function invalid(expected, found, path) {
  return new $json.UnableToDecode(
    toList([new $decode.DecodeError(expected, found, path)]),
  );
}

function json_at_key(error, key) {
  if (error instanceof $json.UnableToDecode) {
    let errors = error[0];
    return new $json.UnableToDecode(
      $list.map(
        errors,
        (error) => {
          return new $decode.DecodeError(
            error.expected,
            error.found,
            listPrepend("entries", listPrepend(key, error.path)),
          );
        },
      ),
    );
  } else {
    return error;
  }
}

function envelope(kind, version, state) {
  return $json.object(
    toList([
      ["type", $json.string(kind)],
      ["v", $json.int(version)],
      ["state", state],
    ]),
  );
}

function check_envelope(input, kind, versions) {
  let decoder = $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => { return $decode.success([tag, version]); },
      );
    },
  );
  return $result.try$(
    $json.parse(input, decoder),
    (_use0) => {
      let tag = _use0[0];
      let version = _use0[1];
      let $ = (tag === kind) && $list.contains(versions, version);
      if ($) {
        return new Ok(undefined);
      } else {
        return new Error(
          invalid(
            kind + " supported protocol version",
            (tag + ":") + $int.to_string(version),
            $List$Empty$const,
          ),
        );
      }
    },
  );
}

function embedded(value) {
  return $json.string($json.to_string(value));
}

function optional_json(value, encode) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return encode(value$1);
  } else {
    return $json.null$();
  }
}

function parse_optional(value, parser) {
  if (value instanceof Some) {
    let value$1 = value[0];
    return $result.map(parser(value$1), (var0) => { return new Some(var0); });
  } else {
    return new Ok(Option$None$const);
  }
}

function unique_pairs(pairs) {
  let entries = $dict.from_list(pairs);
  let $ = $dict.size(entries) === $list.length(pairs);
  if ($) {
    return new Ok(entries);
  } else {
    return new Error(
      invalid("unique keys", "duplicate key", toList(["entries"])),
    );
  }
}

/**
 * Encode a recursive schema, including the register's configured initial value.
 *
 * ## Examples
 *
 * ```gleam
 * let schema = crdt.OrMapSpec(crdt.LwwMapSpec(crdt.LwwRegisterSpec(42)))
 * let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
 * crdt.spec_from_json_with(encoded, decode.int) // -> Ok(schema)
 * ```
 */
export function spec_to_json_with(spec, encode) {
  let _block;
  if (spec instanceof LwwRegisterSpec) {
    let initial = spec.initial_value;
    _block = toList([["initial", encode(initial)]]);
  } else if (spec instanceof OrMapSpec) {
    let child = spec.child_spec;
    _block = toList([["child", embedded(spec_to_json_with(child, encode))]]);
  } else if (spec instanceof LwwMapSpec) {
    let child = spec.child_spec;
    _block = toList([["child", embedded(spec_to_json_with(child, encode))]]);
  } else {
    _block = $List$Empty$const;
  }
  let fields = _block;
  return $json.object(
    listPrepend(["type", $json.string(spec_name(spec))], fields),
  );
}

/**
 * Decode a complete recursive schema.
 *
 * The payload decoder also decodes configured register initial values.
 *
 * ## Examples
 *
 * ```gleam
 * let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
 * let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
 * let assert Ok(decoded) = crdt.spec_from_json_with(encoded, decode.int)
 * decoded == schema // -> True
 * ```
 */
export function spec_from_json_with(input, decoder) {
  return $result.try$(
    $json.parse(
      input,
      $decode.field(
        "type",
        $decode.string,
        (kind) => { return $decode.success(kind); },
      ),
    ),
    (kind) => {
      if (kind === "g_counter") {
        return new Ok(CrdtSpec$GCounterSpec$const);
      } else if (kind === "pn_counter") {
        return new Ok(CrdtSpec$PnCounterSpec$const);
      } else if (kind === "lww_register") {
        return $json.parse(
          input,
          $decode.field(
            "initial",
            decoder,
            (initial) => {
              return $decode.success(new LwwRegisterSpec(initial));
            },
          ),
        );
      } else if (kind === "mv_register") {
        return new Ok(CrdtSpec$MvRegisterSpec$const);
      } else if (kind === "g_set") {
        return new Ok(CrdtSpec$GSetSpec$const);
      } else if (kind === "two_p_set") {
        return new Ok(CrdtSpec$TwoPSetSpec$const);
      } else if (kind === "or_set") {
        return new Ok(CrdtSpec$OrSetSpec$const);
      } else if (kind === "sequence") {
        return new Ok(CrdtSpec$SequenceSpec$const);
      } else if (kind === "text") {
        return new Ok(CrdtSpec$TextSpec$const);
      } else if (kind === "or_map") {
        return $result.try$(
          $json.parse(
            input,
            $decode.field(
              "child",
              $decode.string,
              (child) => { return $decode.success(child); },
            ),
          ),
          (child) => {
            return $result.try$(
              spec_from_json_with(child, decoder),
              (child) => {
                return new Ok(
                  (() => {
                    if (kind === "or_map") {
                      return new OrMapSpec(child);
                    } else {
                      return new LwwMapSpec(child);
                    }
                  })(),
                );
              },
            );
          },
        );
      } else if (kind === "lww_map") {
        return $result.try$(
          $json.parse(
            input,
            $decode.field(
              "child",
              $decode.string,
              (child) => { return $decode.success(child); },
            ),
          ),
          (child) => {
            return $result.try$(
              spec_from_json_with(child, decoder),
              (child) => {
                return new Ok(
                  (() => {
                    if (kind === "or_map") {
                      return new OrMapSpec(child);
                    } else {
                      return new LwwMapSpec(child);
                    }
                  })(),
                );
              },
            );
          },
        );
      } else {
        return new Error(invalid("known child schema", kind, toList(["type"])));
      }
    },
  );
}

function provenance_json(provenance) {
  if (provenance instanceof $lww.Modern) {
    let writer = provenance.writer;
    return $json.object(
      toList([
        ["kind", $json.string("modern")],
        ["writer", $json.string($replica_id.to_string(writer))],
      ]),
    );
  } else {
    let tie_key = provenance.tie_key;
    return $json.object(
      toList([
        ["kind", $json.string("legacy")],
        ["tie_key", $json.string(tie_key)],
      ]),
    );
  }
}

function generation_json(generation) {
  if (generation instanceof $observed.Initial) {
    return $json.object(
      toList([["clock", $json.int(0)], ["creator", $json.null$()]]),
    );
  } else {
    let clock = generation.clock;
    let creator = generation.creator;
    return $json.object(
      toList([
        ["clock", $json.int(clock)],
        ["creator", $json.string($replica_id.to_string(creator))],
      ]),
    );
  }
}

function or_state_json(replica, spec, state, encode, encode_child) {
  return $json.object(
    toList([
      ["replica_id", $json.string($replica_id.to_string(replica))],
      ["spec", embedded(spec_to_json_with(spec, encode))],
      ["clock", $json.int(state.clock)],
      [
        "entries",
        $json.array(
          $dict.to_list(state.entries),
          (pair) => {
            let key = pair[0];
            let entry = pair[1];
            return $json.object(
              toList([
                ["key", $json.string(key)],
                ["generation", generation_json(entry.generation)],
                [
                  "membership",
                  embedded($or_set.to_json_with(entry.membership, $json.string)),
                ],
                [
                  "value",
                  optional_json(
                    entry.value,
                    (child) => { return embedded(encode_child(child)); },
                  ),
                ],
              ]),
            );
          },
        ),
      ],
    ]),
  );
}

export function lww_to_json_with(map, encode) {
  return envelope(
    "lww_map",
    3,
    $json.object(
      toList([
        ["replica_id", $json.string($replica_id.to_string(map.replica))],
        ["spec", embedded(spec_to_json_with(map.spec, encode))],
        ["pruned_timestamp", $json.int(map.state.pruned_timestamp)],
        [
          "entries",
          $json.array(
            $dict.to_list(map.state.entries),
            (pair) => {
              let key = pair[0];
              let entry = pair[1];
              return $json.object(
                toList([
                  ["key", $json.string(key)],
                  ["timestamp", $json.int(entry.timestamp)],
                  ["provenance", provenance_json(entry.provenance)],
                  [
                    "value",
                    optional_json(
                      entry.value,
                      (child) => {
                        return embedded(to_json_with(child, encode));
                      },
                    ),
                  ],
                ]),
              );
            },
          ),
        ],
      ]),
    ),
  );
}

export function or_to_json_with(map, encode) {
  return envelope(
    "or_map",
    3,
    or_state_json(
      map.replica,
      map.spec,
      map.state,
      encode,
      (_capture) => { return to_json_with(_capture, encode); },
    ),
  );
}

/**
 * Encode generic payloads. Text has a distinct dispatch envelope.
 *
 * The encoder is used at every generic payload position, including map schema
 * defaults. Generic ORSet values use their value/tag-entry protocol.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.default_crdt(
 *   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new("A"),
 * )
 * let encoded = crdt.to_json_with(state, json.int) |> json.to_string
 * crdt.from_json_with(encoded, decode.int) // -> Ok(state)
 * ```
 */
export function to_json_with(value, encode) {
  if (value instanceof CrdtGCounter) {
    let value$1 = value[0];
    return $g_counter.to_json(value$1);
  } else if (value instanceof CrdtPnCounter) {
    let value$1 = value[0];
    return $pn_counter.to_json(value$1);
  } else if (value instanceof CrdtLwwRegister) {
    let value$1 = value[0];
    return $lww_register.to_json_with(value$1, encode);
  } else if (value instanceof CrdtMvRegister) {
    let value$1 = value[0];
    return $mv_register.to_json_with(value$1, encode);
  } else if (value instanceof CrdtGSet) {
    let value$1 = value[0];
    return $g_set.to_json_with(value$1, encode);
  } else if (value instanceof CrdtTwoPSet) {
    let value$1 = value[0];
    return $two_p_set.to_json_with(value$1, encode);
  } else if (value instanceof CrdtOrSet) {
    let value$1 = value[0];
    return $or_set.to_json_with(value$1, encode);
  } else if (value instanceof CrdtVersionVector) {
    let value$1 = value[0];
    return $version_vector.to_json(value$1);
  } else if (value instanceof CrdtSequence) {
    let value$1 = value[0];
    return $sequence.to_json(value$1, encode);
  } else if (value instanceof CrdtText) {
    let value$1 = value[0];
    return envelope("text", 1, embedded($text.to_json(value$1)));
  } else if (value instanceof CrdtOrMap) {
    let value$1 = value[0];
    return or_to_json_with(value$1, encode);
  } else {
    let value$1 = value[0];
    return lww_to_json_with(value$1, encode);
  }
}

/**
 * Encode String payloads, preserving existing standalone leaf formats.
 *
 * Maps use the modern recursive protocols. Text uses a distinct dispatch
 * wrapper around its unchanged standalone Sequence envelope.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.CrdtGSet(g_set.new() |> g_set.add("ready"))
 * let encoded = state |> crdt.to_json |> json.to_string
 * crdt.from_json(encoded) // -> Ok(state)
 * ```
 */
export function to_json(value) {
  if (value instanceof CrdtOrSet) {
    let value$1 = value[0];
    return $or_set.to_json(value$1);
  } else {
    return to_json_with(value, $json.string);
  }
}

function provenance_decoder() {
  return $decode.field(
    "kind",
    $decode.string,
    (kind) => {
      if (kind === "modern") {
        return $decode.field(
          "writer",
          $decode.string,
          (writer) => {
            return $decode.success(new $lww.Modern($replica_id.new$(writer)));
          },
        );
      } else if (kind === "legacy") {
        return $decode.field(
          "tie_key",
          $decode.string,
          (tie_key) => { return $decode.success(new $lww.Legacy(tie_key)); },
        );
      } else {
        return $decode.failure(
          new $lww.Legacy(""),
          "modern or legacy provenance",
        );
      }
    },
  );
}

function generation_decoder() {
  return $decode.field(
    "clock",
    $decode.int,
    (clock) => {
      return $decode.field(
        "creator",
        $decode.optional($decode.string),
        (creator) => {
          if (creator instanceof Some) {
            let clock$1 = clock;
            if ((clock$1 > 0) && (clock$1 <= 9_007_199_254_740_991)) {
              let creator$1 = creator[0];
              return $decode.success(
                new $observed.Generation(clock$1, $replica_id.new$(creator$1)),
              );
            } else {
              return $decode.failure(
                $observed.Generation$Initial$const,
                "Initial or positive safe generation with creator",
              );
            }
          } else if (clock === 0) {
            return $decode.success($observed.Generation$Initial$const);
          } else {
            return $decode.failure(
              $observed.Generation$Initial$const,
              "Initial or positive safe generation with creator",
            );
          }
        },
      );
    },
  );
}

function parse_or_state(input, decoder, parse_child) {
  let entry_decoder = $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "generation",
        generation_decoder(),
        (generation) => {
          return $decode.field(
            "membership",
            $decode.string,
            (membership) => {
              return $decode.field(
                "value",
                $decode.optional($decode.string),
                (value) => {
                  return $decode.success([key, generation, membership, value]);
                },
              );
            },
          );
        },
      );
    },
  );
  return $result.try$(
    $json.parse(
      input,
      $decode.field(
        "state",
        $decode.field(
          "replica_id",
          $decode.string,
          (replica) => {
            return $decode.field(
              "spec",
              $decode.string,
              (spec) => {
                return $decode.field(
                  "clock",
                  $decode.int,
                  (clock) => {
                    return $decode.field(
                      "entries",
                      $decode.list(entry_decoder),
                      (entries) => {
                        return $decode.success([replica, spec, clock, entries]);
                      },
                    );
                  },
                );
              },
            );
          },
        ),
        (state) => { return $decode.success(state); },
      ),
    ),
    (_use0) => {
      let replica = _use0[0];
      let spec = _use0[1];
      let clock = _use0[2];
      let entries = _use0[3];
      return $result.try$(
        (() => {
          let $ = (clock >= 0) && (clock <= 9_007_199_254_740_991);
          if ($) {
            return new Ok(undefined);
          } else {
            return new Error(
              invalid(
                "safe nonnegative allocation clock",
                $int.to_string(clock),
                toList(["clock"]),
              ),
            );
          }
        })(),
        (_) => {
          return $result.try$(
            spec_from_json_with(spec, decoder),
            (spec) => {
              return $result.try$(
                $list.try_map(
                  entries,
                  (entry) => {
                    let key = entry[0];
                    let generation = entry[1];
                    let membership = entry[2];
                    let value = entry[3];
                    return $bool.guard(
                      $observed.clock(generation) > clock,
                      new Error(
                        invalid(
                          "clock covering all generations",
                          key,
                          toList(["clock"]),
                        ),
                      ),
                      () => {
                        return $result.try$(
                          $or_set.from_json_with(membership, $decode.string),
                          (membership) => {
                            return $bool.guard(
                              (() => {
                                let _pipe = $set.to_list(
                                  $or_set.value(membership),
                                );
                                return $list.any(
                                  _pipe,
                                  (member) => { return member !== key; },
                                );
                              })(),
                              new Error(
                                invalid(
                                  "membership only for entry key",
                                  key,
                                  toList(["entries", key, "membership"]),
                                ),
                              ),
                              () => {
                                return $result.try$(
                                  (() => {
                                    let _pipe = parse_optional(
                                      value,
                                      (_capture) => {
                                        return parse_child(_capture, spec);
                                      },
                                    );
                                    return $result.map_error(
                                      _pipe,
                                      (_capture) => {
                                        return json_at_key(_capture, key);
                                      },
                                    );
                                  })(),
                                  (value) => {
                                    return new Ok(
                                      [
                                        key,
                                        new $observed.Entry(
                                          generation,
                                          membership,
                                          value,
                                        ),
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
                ),
                (entries) => {
                  return $result.try$(
                    unique_pairs(entries),
                    (entries) => {
                      return new Ok(
                        [
                          $replica_id.new$(replica),
                          spec,
                          new $observed.State(clock, entries),
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
}

function dispatch_tag(input) {
  return $json.parse(
    input,
    $decode.field(
      "type",
      $decode.string,
      (kind) => { return $decode.success(kind); },
    ),
  );
}

function parse_checked_child(input, spec, decoder) {
  return $result.try$(
    from_json_with(input, decoder),
    (value) => {
      let $ = matches_spec(value, spec);
      if ($) {
        return new Ok(value);
      } else {
        return new Error(
          invalid(
            "matching recursive child schema",
            type_name(value),
            toList(["value"]),
          ),
        );
      }
    },
  );
}

export function lww_from_json_with(input, decoder) {
  return $result.try$(
    check_envelope(input, "lww_map", toList([3])),
    (_) => {
      let entry_decoder = $decode.field(
        "key",
        $decode.string,
        (key) => {
          return $decode.field(
            "timestamp",
            $decode.int,
            (timestamp) => {
              return $decode.field(
                "provenance",
                provenance_decoder(),
                (provenance) => {
                  return $decode.field(
                    "value",
                    $decode.optional($decode.string),
                    (value) => {
                      return $decode.success(
                        [key, timestamp, provenance, value],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
      return $result.try$(
        $json.parse(
          input,
          $decode.field(
            "state",
            $decode.field(
              "replica_id",
              $decode.string,
              (replica) => {
                return $decode.field(
                  "spec",
                  $decode.string,
                  (spec) => {
                    return $decode.field(
                      "pruned_timestamp",
                      $decode.int,
                      (pruned) => {
                        return $decode.field(
                          "entries",
                          $decode.list(entry_decoder),
                          (entries) => {
                            return $decode.success(
                              [replica, spec, pruned, entries],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            (state) => { return $decode.success(state); },
          ),
        ),
        (_use0) => {
          let replica = _use0[0];
          let spec = _use0[1];
          let pruned = _use0[2];
          let entries = _use0[3];
          return $bool.guard(
            (pruned < 0) || (pruned > 9_007_199_254_740_991),
            new Error(
              invalid(
                "nonnegative prune floor",
                $int.to_string(pruned),
                toList(["pruned_timestamp"]),
              ),
            ),
            () => {
              return $result.try$(
                spec_from_json_with(spec, decoder),
                (spec) => {
                  return $result.try$(
                    $list.try_map(
                      entries,
                      (entry) => {
                        let key = entry[0];
                        let timestamp = entry[1];
                        let provenance = entry[2];
                        let value = entry[3];
                        let _block;
                        if (provenance instanceof $lww.Modern) {
                          _block = true;
                        } else {
                          _block = false;
                        }
                        let modern = _block;
                        return $bool.guard(
                          ((modern && (timestamp <= 0)) || (timestamp > 9_007_199_254_740_991)) || (timestamp < -9_007_199_254_740_991),
                          new Error(
                            invalid(
                              "positive write timestamp",
                              key,
                              toList(["entries", key]),
                            ),
                          ),
                          () => {
                            return $result.try$(
                              (() => {
                                let _pipe = parse_optional(
                                  value,
                                  (_capture) => {
                                    return parse_checked_child(
                                      _capture,
                                      spec,
                                      decoder,
                                    );
                                  },
                                );
                                return $result.map_error(
                                  _pipe,
                                  (_capture) => {
                                    return json_at_key(_capture, key);
                                  },
                                );
                              })(),
                              (value) => {
                                return new Ok(
                                  [
                                    key,
                                    new $lww.Entry(value, timestamp, provenance),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    (entries) => {
                      return $result.try$(
                        unique_pairs(entries),
                        (entries) => {
                          return new Ok(
                            new LWWMap(
                              $replica_id.new$(replica),
                              spec,
                              new $lww.State(entries, pruned),
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
      );
    },
  );
}

export function or_from_json_with(input, decoder) {
  return $result.try$(
    check_envelope(input, "or_map", toList([3])),
    (_) => {
      return $result.try$(
        parse_or_state(
          input,
          decoder,
          (input, spec) => { return parse_checked_child(input, spec, decoder); },
        ),
        (_use0) => {
          let replica = _use0[0];
          let spec = _use0[1];
          let state = _use0[2];
          return $result.try$(
            $list.try_fold(
              $dict.to_list(state.entries),
              undefined,
              (_, pair) => {
                let key = pair[0];
                let entry = pair[1];
                let $ = $observed.active(entry, key);
                let $1 = entry.value;
                if ($ && $1 instanceof None) {
                  return new Error(
                    invalid(
                      "value for active membership",
                      "null",
                      toList(["entries", key, "value"]),
                    ),
                  );
                } else {
                  return new Ok(undefined);
                }
              },
            ),
            (_) => {
              return new Ok(or_bind(new ORMap(replica, spec, state), replica));
            },
          );
        },
      );
    },
  );
}

/**
 * Decode a generic state; bare Sequence envelopes always dispatch as Sequence.
 *
 * Bind the result before editing as another writer. A bare Sequence of Strings
 * is not inferred to be Text; only the explicit Text dispatch wrapper is Text.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new("A"))
 * let encoded = crdt.to_json_with(state, json.int) |> json.to_string
 * let assert Ok(decoded) = crdt.from_json_with(encoded, decode.int)
 * crdt.matches_spec(decoded, crdt.LwwRegisterSpec(42)) // -> True
 * ```
 */
export function from_json_with(input, decoder) {
  return $result.try$(
    dispatch_tag(input),
    (kind) => {
      if (kind === "g_counter") {
        let _pipe = $g_counter.from_json(input);
        return $result.map(_pipe, (var0) => { return new CrdtGCounter(var0); });
      } else if (kind === "pn_counter") {
        let _pipe = $pn_counter.from_json(input);
        return $result.map(_pipe, (var0) => { return new CrdtPnCounter(var0); });
      } else if (kind === "lww_register") {
        let _pipe = $lww_register.from_json_with(input, decoder);
        return $result.map(
          _pipe,
          (var0) => { return new CrdtLwwRegister(var0); },
        );
      } else if (kind === "mv_register") {
        let _pipe = $mv_register.from_json_with(input, decoder);
        return $result.map(
          _pipe,
          (var0) => { return new CrdtMvRegister(var0); },
        );
      } else if (kind === "g_set") {
        let _pipe = $g_set.from_json_with(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtGSet(var0); });
      } else if (kind === "two_p_set") {
        let _pipe = $two_p_set.from_json_with(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtTwoPSet(var0); });
      } else if (kind === "or_set") {
        let _pipe = $or_set.from_json_with(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtOrSet(var0); });
      } else if (kind === "version_vector") {
        let _pipe = $version_vector.from_json(input);
        return $result.map(
          _pipe,
          (var0) => { return new CrdtVersionVector(var0); },
        );
      } else if (kind === "sequence") {
        let _pipe = $sequence.from_json(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtSequence(var0); });
      } else if (kind === "text") {
        return $result.try$(
          check_envelope(input, "text", toList([1])),
          (_) => {
            return $result.try$(
              $json.parse(
                input,
                $decode.field(
                  "state",
                  $decode.string,
                  (payload) => { return $decode.success(payload); },
                ),
              ),
              (payload) => {
                let _pipe = $text.from_json(payload);
                return $result.map(
                  _pipe,
                  (var0) => { return new CrdtText(var0); },
                );
              },
            );
          },
        );
      } else if (kind === "or_map") {
        let _pipe = or_from_json_with(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtOrMap(var0); });
      } else if (kind === "lww_map") {
        let _pipe = lww_from_json_with(input, decoder);
        return $result.map(_pipe, (var0) => { return new CrdtLwwMap(var0); });
      } else {
        return new Error(invalid("known CRDT type", kind, toList(["type"])));
      }
    },
  );
}

function legacy_or_set(input, decoder) {
  return $result.try$(
    $or_set.from_json(input),
    (legacy) => {
      return $or_set.from_json_with(
        (() => {
          let _pipe = $or_set.to_json_with(legacy, $json.string);
          return $json.to_string(_pipe);
        })(),
        decoder,
      );
    },
  );
}

/**
 * Decode String states, including legacy String leaf codecs (not legacy maps).
 *
 * Use the map facades' explicit import adapters for legacy map baselines.
 *
 * ## Examples
 *
 * ```gleam
 * let state = crdt.default_crdt(crdt.LwwRegisterSpec(""), replica_id.new("A"))
 * let encoded = state |> crdt.to_json |> json.to_string
 * crdt.from_json(encoded) // -> Ok(state)
 * ```
 */
export function from_json(input) {
  return $result.try$(
    dispatch_tag(input),
    (kind) => {
      if (kind === "or_set") {
        return $result.try$(
          $json.parse(
            input,
            $decode.field(
              "v",
              $decode.int,
              (version) => { return $decode.success(version); },
            ),
          ),
          (version) => {
            if (version === 1) {
              let _pipe = legacy_or_set(input, $decode.string);
              return $result.map(
                _pipe,
                (var0) => { return new CrdtOrSet(var0); },
              );
            } else if (version === 2) {
              let _pipe = legacy_or_set(input, $decode.string);
              return $result.map(
                _pipe,
                (var0) => { return new CrdtOrSet(var0); },
              );
            } else {
              return from_json_with(input, $decode.string);
            }
          },
        );
      } else {
        return from_json_with(input, $decode.string);
      }
    },
  );
}

export function or_delta_to_json_with(delta, encode) {
  return envelope(
    "or_map_delta",
    2,
    or_state_json(
      delta.replica,
      delta.spec,
      delta.state,
      encode,
      (_capture) => { return delta_to_json_with(_capture, encode); },
    ),
  );
}

/**
 * Encode a typed dispatch delta without expanding nested ORMap changes.
 *
 * ## Examples
 *
 * ```gleam
 * let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
 * let delta = crdt.OrMapChange(or_map.empty_delta(map))
 * let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
 * crdt.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
 * ```
 */
export function delta_to_json_with(delta, encode) {
  let _block;
  if (delta instanceof NoChange) {
    let spec = delta[0];
    _block = ["none", spec_to_json_with(spec, encode)];
  } else if (delta instanceof StateDelta) {
    let value = delta[0];
    _block = ["state", to_json_with(value, encode)];
  } else {
    let value = delta[0];
    _block = ["or_map", or_delta_to_json_with(value, encode)];
  }
  let $ = _block;
  let kind = $[0];
  let payload = $[1];
  return envelope(
    "crdt_delta",
    1,
    $json.object(
      toList([["kind", $json.string(kind)], ["payload", embedded(payload)]]),
    ),
  );
}

/**
 * Encode a String-payload dispatch delta.
 *
 * ## Examples
 *
 * ```gleam
 * let delta = crdt.NoChange(crdt.LwwRegisterSpec(""))
 * let encoded = delta |> crdt.delta_to_json |> json.to_string
 * crdt.delta_from_json(encoded) // -> Ok(delta)
 * ```
 */
export function delta_to_json(delta) {
  return delta_to_json_with(delta, $json.string);
}

export function or_delta_from_json_with(input, decoder) {
  return $result.try$(
    check_envelope(input, "or_map_delta", toList([2])),
    (_) => {
      return $result.try$(
        parse_or_state(
          input,
          decoder,
          (input, spec) => {
            return $result.try$(
              delta_from_json_with(input, decoder),
              (delta) => {
                let $ = matches_delta(delta, spec);
                if ($) {
                  return new Ok(delta);
                } else {
                  return new Error(
                    invalid(
                      "matching recursive delta schema",
                      "mismatch",
                      toList(["value"]),
                    ),
                  );
                }
              },
            );
          },
        ),
        (_use0) => {
          let replica = _use0[0];
          let spec = _use0[1];
          let state = _use0[2];
          return new Ok(new ORMapDelta(replica, spec, state));
        },
      );
    },
  );
}

/**
 * Decode a typed dispatch delta.
 *
 * Apply it with `apply_delta` and the receiver's expected schema. Decoding a
 * change does not establish that it belongs to a particular receiving map.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * let schema = crdt.LwwRegisterSpec(42)
 * let delta = crdt.NoChange(schema)
 * let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
 * let assert Ok(decoded) = crdt.delta_from_json_with(encoded, decode.int)
 * let state = crdt.default_crdt(schema, local)
 * crdt.apply_delta(state, decoded, schema, local) // -> Ok(state)
 * ```
 */
export function delta_from_json_with(input, decoder) {
  return $result.try$(
    check_envelope(input, "crdt_delta", toList([1])),
    (_) => {
      return $result.try$(
        $json.parse(
          input,
          $decode.field(
            "state",
            $decode.field(
              "kind",
              $decode.string,
              (kind) => {
                return $decode.field(
                  "payload",
                  $decode.string,
                  (payload) => { return $decode.success([kind, payload]); },
                );
              },
            ),
            (state) => { return $decode.success(state); },
          ),
        ),
        (_use0) => {
          let kind = _use0[0];
          let payload = _use0[1];
          if (kind === "none") {
            let _pipe = spec_from_json_with(payload, decoder);
            return $result.map(_pipe, (var0) => { return new NoChange(var0); });
          } else if (kind === "state") {
            let _pipe = from_json_with(payload, decoder);
            return $result.map(
              _pipe,
              (var0) => { return new StateDelta(var0); },
            );
          } else if (kind === "or_map") {
            let _pipe = or_delta_from_json_with(payload, decoder);
            return $result.map(
              _pipe,
              (var0) => { return new OrMapChange(var0); },
            );
          } else {
            return new Error(
              invalid("none, state, or or_map delta", kind, toList(["kind"])),
            );
          }
        },
      );
    },
  );
}

/**
 * Decode a String-payload dispatch delta.
 *
 * ## Examples
 *
 * ```gleam
 * let delta = crdt.NoChange(crdt.LwwRegisterSpec(""))
 * let encoded = delta |> crdt.delta_to_json |> json.to_string
 * let assert Ok(decoded) = crdt.delta_from_json(encoded)
 * crdt.is_empty_delta(decoded) // -> True
 * ```
 */
export function delta_from_json(input) {
  return delta_from_json_with(input, $decode.string);
}

export function or_import_legacy(input, spec, decoder, replica) {
  return $result.try$(
    check_envelope(input, "or_map", toList([1, 2])),
    (_) => {
      return $result.try$(
        $json.parse(
          input,
          $decode.field(
            "state",
            $decode.field(
              "crdt_spec",
              $decode.string,
              (spec) => {
                return $decode.field(
                  "key_set",
                  $decode.string,
                  (membership) => {
                    return $decode.field(
                      "values",
                      $decode.list(
                        $decode.field(
                          "key",
                          $decode.string,
                          (key) => {
                            return $decode.field(
                              "crdt",
                              $decode.string,
                              (child) => {
                                return $decode.success([key, child]);
                              },
                            );
                          },
                        ),
                      ),
                      (entries) => {
                        return $decode.optional_field(
                          "remove_bounds",
                          $dict.new$(),
                          $decode.dict(
                            $decode.string,
                            $version_vector.decoder(),
                          ),
                          (bounds) => {
                            return $decode.success(
                              [spec, membership, entries, bounds],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            (state) => { return $decode.success(state); },
          ),
        ),
        (_use0) => {
          let old_spec = _use0[0];
          let membership = _use0[1];
          let entries = _use0[2];
          let bounds = _use0[3];
          return $bool.guard(
            old_spec !== spec_name(spec),
            new Error(invalid(spec_name(spec), old_spec, toList(["crdt_spec"]))),
            () => {
              return $result.try$(
                legacy_or_set(membership, $decode.string),
                (membership) => {
                  return $result.try$(
                    $list.try_map(
                      entries,
                      (pair) => {
                        return $result.try$(
                          dispatch_tag(pair[1]),
                          (kind) => {
                            return $result.try$(
                              (() => {
                                if (kind === "or_set") {
                                  let _pipe = legacy_or_set(pair[1], decoder);
                                  return $result.map(
                                    _pipe,
                                    (var0) => { return new CrdtOrSet(var0); },
                                  );
                                } else {
                                  return from_json_with(pair[1], decoder);
                                }
                              })(),
                              (child) => {
                                return $bool.guard(
                                  !matches_spec(child, spec),
                                  new Error(
                                    invalid(
                                      "matching legacy child schema",
                                      kind,
                                      toList(["values", pair[0]]),
                                    ),
                                  ),
                                  () => { return new Ok([pair[0], child]); },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    (pairs) => {
                      return $result.try$(
                        unique_pairs(pairs),
                        (children) => {
                          let _block;
                          let _pipe = $dict.keys(children);
                          let _pipe$1 = $list.append(
                            _pipe,
                            $set.to_list($or_set.value(membership)),
                          );
                          let _pipe$2 = $list.append(
                            _pipe$1,
                            $dict.keys(bounds),
                          );
                          _block = $list.unique(_pipe$2);
                          let keys = _block;
                          return $result.try$(
                            $list.try_map(
                              keys,
                              (key) => {
                                let _block$1;
                                let $ = $dict.get(children, key);
                                if ($ instanceof Ok) {
                                  let child = $[0];
                                  _block$1 = new Some(child);
                                } else {
                                  _block$1 = Option$None$const;
                                }
                                let child = _block$1;
                                return $bool.guard(
                                  $or_set.contains(membership, key) && (child instanceof None),
                                  new Error(
                                    invalid(
                                      "active legacy child baseline",
                                      key,
                                      toList(["values"]),
                                    ),
                                  ),
                                  () => {
                                    let per_key = $or_set.remove_where(
                                      membership,
                                      (other) => { return other !== key; },
                                    );
                                    return new Ok(
                                      [
                                        key,
                                        new $observed.Entry(
                                          $observed.Generation$Initial$const,
                                          per_key,
                                          child,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                            (entries) => {
                              return new Ok(
                                or_bind(
                                  new ORMap(
                                    replica,
                                    spec,
                                    new $observed.State(
                                      0,
                                      $dict.from_list(entries),
                                    ),
                                  ),
                                  replica,
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
          );
        },
      );
    },
  );
}

export function lww_import_legacy(input, spec, replica) {
  return $result.try$(
    check_envelope(input, "lww_map", toList([1, 2])),
    (_) => {
      return $bool.guard(
        spec_name(spec) !== "lww_register",
        new Error(
          invalid("explicit LwwRegisterSpec", spec_name(spec), toList(["spec"])),
        ),
        () => {
          return $result.try$(
            $json.parse(
              input,
              $decode.field(
                "state",
                $decode.field(
                  "entries",
                  $decode.list(
                    $decode.field(
                      "key",
                      $decode.string,
                      (key) => {
                        return $decode.field(
                          "value",
                          $decode.optional($decode.string),
                          (value) => {
                            return $decode.field(
                              "timestamp",
                              $decode.int,
                              (timestamp) => {
                                return $decode.success([key, value, timestamp]);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  (entries) => {
                    return $decode.optional_field(
                      "pruned_timestamp",
                      0,
                      $decode.int,
                      (pruned) => { return $decode.success([entries, pruned]); },
                    );
                  },
                ),
                (state) => { return $decode.success(state); },
              ),
            ),
            (_use0) => {
              let entries = _use0[0];
              let pruned = _use0[1];
              return $bool.guard(
                (pruned < 0) || (pruned > 9_007_199_254_740_991),
                new Error(
                  invalid(
                    "safe nonnegative prune floor",
                    $int.to_string(pruned),
                    toList(["pruned_timestamp"]),
                  ),
                ),
                () => {
                  return $result.try$(
                    $list.try_map(
                      entries,
                      (entry) => {
                        let key = entry[0];
                        let value = entry[1];
                        let timestamp = entry[2];
                        return $bool.guard(
                          (timestamp > 9_007_199_254_740_991) || (timestamp < -9_007_199_254_740_991),
                          new Error(
                            invalid(
                              "safe write timestamp",
                              $int.to_string(timestamp),
                              toList(["entries", key]),
                            ),
                          ),
                          () => {
                            let _block;
                            if (value instanceof Some) {
                              let value$1 = value[0];
                              _block = [
                                new Some(
                                  new CrdtLwwRegister(
                                    $lww_register.new$(
                                      value$1,
                                      timestamp,
                                      scope(
                                        $replica_id.new$("legacy"),
                                        toList(["lww-import", key, value$1]),
                                      ),
                                    ),
                                  ),
                                ),
                                value$1,
                              ];
                            } else {
                              _block = [Option$None$const, ""];
                            }
                            let $ = _block;
                            let child = $[0];
                            let tie_key = $[1];
                            return new Ok(
                              [
                                key,
                                new $lww.Entry(
                                  child,
                                  timestamp,
                                  new $lww.Legacy(tie_key),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    (entries) => {
                      return $result.try$(
                        unique_pairs(entries),
                        (entries) => {
                          return new Ok(
                            new LWWMap(
                              replica,
                              spec,
                              new $lww.State(entries, pruned),
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
      );
    },
  );
}
