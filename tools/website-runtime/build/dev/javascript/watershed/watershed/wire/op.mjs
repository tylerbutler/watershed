/// <reference types="./op.d.mts" />
import * as $json from "../../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $list from "../../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../../lattice_core/lattice_core/version_vector.mjs";
import * as $g_counter from "../../../lattice_counters/lattice_counters/g_counter.mjs";
import * as $pn_counter from "../../../lattice_counters/lattice_counters/pn_counter.mjs";
import * as $crdt from "../../../lattice_maps/lattice_maps/crdt.mjs";
import * as $lww_map from "../../../lattice_maps/lattice_maps/lww_map.mjs";
import * as $or_map from "../../../lattice_maps/lattice_maps/or_map.mjs";
import * as $lww_register from "../../../lattice_registers/lattice_registers/lww_register.mjs";
import * as $mv_register from "../../../lattice_registers/lattice_registers/mv_register.mjs";
import * as $sequence from "../../../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $g_set from "../../../lattice_sets/lattice_sets/g_set.mjs";
import * as $or_set from "../../../lattice_sets/lattice_sets/or_set.mjs";
import * as $two_p_set from "../../../lattice_sets/lattice_sets/two_p_set.mjs";
import * as $text from "../../../lattice_text/lattice_text/text.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../../gleam.mjs";
import * as $channel from "../../watershed/channel.mjs";
import * as $claims_kernel from "../../watershed/claims_kernel.mjs";
import { Claim } from "../../watershed/claims_kernel.mjs";
import * as $counter_kernel from "../../watershed/counter_kernel.mjs";
import { Increment } from "../../watershed/counter_kernel.mjs";
import * as $directory_kernel from "../../watershed/directory_kernel.mjs";
import * as $g_counter_kernel from "../../watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../../watershed/g_set_kernel.mjs";
import * as $json_ot from "../../watershed/json_ot.mjs";
import * as $json_ot_kernel from "../../watershed/json_ot_kernel.mjs";
import { JsonOtWireOperation } from "../../watershed/json_ot_kernel.mjs";
import * as $lww_map_kernel from "../../watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../../watershed/lww_register_kernel.mjs";
import * as $map_kernel from "../../watershed/map_kernel.mjs";
import { Delete, Set, MapOperation$Clear$const } from "../../watershed/map_kernel.mjs";
import * as $mv_register_kernel from "../../watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../../watershed/or_map_kernel.mjs";
import * as $or_map_set_leaf from "../../watershed/or_map_set_leaf.mjs";
import * as $or_set_kernel from "../../watershed/or_set_kernel.mjs";
import * as $ordered_collection_kernel from "../../watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "../../watershed/pact_map_kernel.mjs";
import * as $pn_counter_kernel from "../../watershed/pn_counter_kernel.mjs";
import * as $register_collection_kernel from "../../watershed/register_collection_kernel.mjs";
import { Write } from "../../watershed/register_collection_kernel.mjs";
import * as $rich_text from "../../watershed/rich_text.mjs";
import * as $rich_text_kernel from "../../watershed/rich_text_kernel.mjs";
import { RichTextWireOperation } from "../../watershed/rich_text_kernel.mjs";
import * as $sequence_kernel from "../../watershed/sequence_kernel.mjs";
import * as $task_manager_kernel from "../../watershed/task_manager_kernel.mjs";
import * as $text_kernel from "../../watershed/text_kernel.mjs";
import * as $two_p_set_kernel from "../../watershed/two_p_set_kernel.mjs";
import * as $wire from "../../watershed/wire.mjs";

export class ChannelOperation extends $CustomType {
  constructor(address, contents) {
    super();
    this.address = address;
    this.contents = contents;
  }
}
export const OperationContents$ChannelOperation = (address, contents) =>
  new ChannelOperation(address, contents);
export const OperationContents$isChannelOperation = (value) =>
  value instanceof ChannelOperation;
export const OperationContents$ChannelOperation$address = (value) =>
  value.address;
export const OperationContents$ChannelOperation$0 = (value) => value.address;
export const OperationContents$ChannelOperation$contents = (value) =>
  value.contents;
export const OperationContents$ChannelOperation$1 = (value) => value.contents;

export class AttachOperation extends $CustomType {
  constructor(address, snapshot) {
    super();
    this.address = address;
    this.snapshot = snapshot;
  }
}
export const OperationContents$AttachOperation = (address, snapshot) =>
  new AttachOperation(address, snapshot);
export const OperationContents$isAttachOperation = (value) =>
  value instanceof AttachOperation;
export const OperationContents$AttachOperation$address = (value) =>
  value.address;
export const OperationContents$AttachOperation$0 = (value) => value.address;
export const OperationContents$AttachOperation$snapshot = (value) =>
  value.snapshot;
export const OperationContents$AttachOperation$1 = (value) => value.snapshot;

export const OperationContents$address = (value) => value.address;

function text_delta_json(delta) {
  return $json.string($json.to_string($text.to_json(delta)));
}

/**
 * Encode a `TextOperation` for the wire. Every constructor carries the
 * diagnostic intent fields, which are the indexes, the ranges, and the value,
 * with the authoritative CRDT `delta`. A remote replica applies `delta`. It
 * never applies a diagnostic field.
 */
export function encode_text_operation(operation) {
  if (operation instanceof $text_kernel.Insert) {
    let index = operation.index;
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("textInsert")],
        ["index", $json.int(index)],
        ["value", $json.string(value)],
        ["delta", text_delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $text_kernel.DeleteRange) {
    let start = operation.start;
    let end = operation.end;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("textDeleteRange")],
        ["start", $json.int(start)],
        ["end", $json.int(end)],
        ["delta", text_delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $text_kernel.ReplaceRange) {
    let start = operation.start;
    let end = operation.end;
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("textReplaceRange")],
        ["start", $json.int(start)],
        ["end", $json.int(end)],
        ["value", $json.string(value)],
        ["delta", text_delta_json(delta)],
      ]),
    );
  } else {
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("textAppend")],
        ["value", $json.string(value)],
        ["delta", text_delta_json(delta)],
      ]),
    );
  }
}

/**
 * Encode a rich-text operation envelope. It contains the reference sequence
 * number that the delta was written against, and the canonical Quill Delta
 * JSON array of that delta.
 */
export function encode_rich_text_operation(operation) {
  return $json.object(
    toList([
      ["refSeq", $json.int(operation.reference_sequence_number)],
      ["delta", $rich_text.delta_to_json(operation.delta)],
    ]),
  );
}

function sequence_delta_json(delta) {
  return $json.string(
    $json.to_string($sequence.to_json(delta, (value) => { return value; })),
  );
}

export function encode_sequence_operation(operation) {
  if (operation instanceof $sequence_kernel.Insert) {
    let index = operation.index;
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("sequenceInsert")],
        ["index", $json.int(index)],
        ["value", value],
        ["delta", sequence_delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $sequence_kernel.Delete) {
    let index = operation.index;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("sequenceDelete")],
        ["index", $json.int(index)],
        ["delta", sequence_delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $sequence_kernel.Move) {
    let from_index = operation.from_index;
    let to_index = operation.to_index;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("sequenceMove")],
        ["fromIndex", $json.int(from_index)],
        ["toIndex", $json.int(to_index)],
        ["delta", sequence_delta_json(delta)],
      ]),
    );
  } else {
    let index = operation.index;
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("sequenceReplace")],
        ["index", $json.int(index)],
        ["value", value],
        ["delta", sequence_delta_json(delta)],
      ]),
    );
  }
}

export function encode_ordered_operation(operation) {
  if (operation instanceof $ordered_collection_kernel.Add) {
    let value = operation.value;
    return $json.object(
      toList([["type", $json.string("orderedAdd")], ["value", value]]),
    );
  } else if (operation instanceof $ordered_collection_kernel.Acquire) {
    let acquire_id = operation.acquire_id;
    return $json.object(
      toList([
        ["type", $json.string("orderedAcquire")],
        ["acquireId", $json.string(acquire_id)],
      ]),
    );
  } else if (operation instanceof $ordered_collection_kernel.Complete) {
    let acquire_id = operation.acquire_id;
    return $json.object(
      toList([
        ["type", $json.string("orderedComplete")],
        ["acquireId", $json.string(acquire_id)],
      ]),
    );
  } else {
    let acquire_id = operation.acquire_id;
    return $json.object(
      toList([
        ["type", $json.string("orderedRelease")],
        ["acquireId", $json.string(acquire_id)],
      ]),
    );
  }
}

function encode_pact_map_value(value) {
  if (value instanceof Some) {
    let inner = value[0];
    return $json.object(
      toList([["type", $json.string("Plain")], ["value", inner]]),
    );
  } else {
    return $json.object(toList([["type", $json.string("Absent")]]));
  }
}

/**
 * Encode a PactMap operation. The value of a `Set` operation is an
 * `Option(Json)`. `None` is a true tombstone, which is not the same as
 * `Some(null)`, and it gets the `Absent` tag.
 */
export function encode_pact_map_operation(operation) {
  if (operation instanceof $pact_map_kernel.Set) {
    let key = operation.key;
    let value = operation.value;
    let reference_sequence_number = operation.reference_sequence_number;
    return $json.object(
      toList([
        ["type", $json.string("pactMapSet")],
        ["key", $json.string(key)],
        ["value", encode_pact_map_value(value)],
        ["refSeq", $json.int(reference_sequence_number)],
      ]),
    );
  } else {
    let key = operation.key;
    return $json.object(
      toList([
        ["type", $json.string("pactMapAccept")],
        ["key", $json.string(key)],
      ]),
    );
  }
}

/**
 * Encode a SharedDirectory operation. Every variant carries `path`, which is
 * the absolute directory address, and `mid`, which is the `message_id` of the
 * kernel. `mid` is the client-sequence identity of the operation. A remote
 * client needs it for the stale-instance filter and for the sibling order.
 */
export function encode_directory_operation(operation, message_id) {
  if (operation instanceof $directory_kernel.Set) {
    let path = operation.path;
    let key = operation.key;
    let value = operation.value;
    return $json.object(
      toList([
        ["type", $json.string("dirSet")],
        ["path", $json.string(path)],
        ["key", $json.string(key)],
        [
          "value",
          $json.object(
            toList([["type", $json.string("Plain")], ["value", value]]),
          ),
        ],
        ["mid", $json.int(message_id)],
      ]),
    );
  } else if (operation instanceof $directory_kernel.Delete) {
    let path = operation.path;
    let key = operation.key;
    return $json.object(
      toList([
        ["type", $json.string("dirDelete")],
        ["path", $json.string(path)],
        ["key", $json.string(key)],
        ["mid", $json.int(message_id)],
      ]),
    );
  } else if (operation instanceof $directory_kernel.Clear) {
    let path = operation.path;
    return $json.object(
      toList([
        ["type", $json.string("dirClear")],
        ["path", $json.string(path)],
        ["mid", $json.int(message_id)],
      ]),
    );
  } else if (operation instanceof $directory_kernel.CreateSubDirectory) {
    let path = operation.path;
    let name = operation.name;
    return $json.object(
      toList([
        ["type", $json.string("dirCreateSub")],
        ["path", $json.string(path)],
        ["name", $json.string(name)],
        ["mid", $json.int(message_id)],
      ]),
    );
  } else {
    let path = operation.path;
    let name = operation.name;
    return $json.object(
      toList([
        ["type", $json.string("dirDeleteSub")],
        ["path", $json.string(path)],
        ["name", $json.string(name)],
        ["mid", $json.int(message_id)],
      ]),
    );
  }
}

/**
 * Encode a json0 operation envelope. It contains the reference sequence number
 * that the components were written against, and the json0 component array.
 */
export function encode_json_ot_operation(operation) {
  return $json.object(
    toList([
      ["refSeq", $json.int(operation.reference_sequence_number)],
      ["components", $json_ot.operation_to_json(operation.components)],
    ]),
  );
}

export function encode_task_manager_operation(operation) {
  if (operation instanceof $task_manager_kernel.Volunteer) {
    let task_id = operation.task_id;
    return $json.object(
      toList([
        ["type", $json.string("taskVolunteer")],
        ["taskId", $json.string(task_id)],
      ]),
    );
  } else if (operation instanceof $task_manager_kernel.Abandon) {
    let task_id = operation.task_id;
    return $json.object(
      toList([
        ["type", $json.string("taskAbandon")],
        ["taskId", $json.string(task_id)],
      ]),
    );
  } else {
    let task_id = operation.task_id;
    return $json.object(
      toList([
        ["type", $json.string("taskComplete")],
        ["taskId", $json.string(task_id)],
      ]),
    );
  }
}

export function encode_claim_operation(operation) {
  let key = operation.key;
  let value = operation.value;
  let reference_sequence_number = operation.reference_sequence_number;
  return $json.object(
    toList([
      ["type", $json.string("claim")],
      ["key", $json.string(key)],
      [
        "value",
        $json.object(
          toList([["type", $json.string("Plain")], ["value", value]]),
        ),
      ],
      ["refSeq", $json.int(reference_sequence_number)],
    ]),
  );
}

export function encode_register_collection_operation(operation) {
  let key = operation.key;
  let value = operation.value;
  let reference_sequence_number = operation.reference_sequence_number;
  return $json.object(
    toList([
      ["type", $json.string("registerWrite")],
      ["key", $json.string(key)],
      [
        "value",
        $json.object(
          toList([["type", $json.string("Plain")], ["value", value]]),
        ),
      ],
      ["refSeq", $json.int(reference_sequence_number)],
    ]),
  );
}

function two_p_set_delta_json(delta) {
  return $json.string($json.to_string($two_p_set.to_json(delta)));
}

export function encode_two_p_set_operation(operation) {
  if (operation instanceof $two_p_set_kernel.Add) {
    let element = operation.element;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("twoPSetAdd")],
        ["element", $json.string(element)],
        ["delta", two_p_set_delta_json(delta)],
      ]),
    );
  } else {
    let element = operation.element;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("twoPSetRemove")],
        ["element", $json.string(element)],
        ["delta", two_p_set_delta_json(delta)],
      ]),
    );
  }
}

function g_set_delta_json(delta) {
  return $json.string($json.to_string($g_set.to_json(delta)));
}

export function encode_g_set_operation(operation) {
  let element = operation.element;
  let delta = operation.delta;
  return $json.object(
    toList([
      ["type", $json.string("gSetAdd")],
      ["element", $json.string(element)],
      ["delta", g_set_delta_json(delta)],
    ]),
  );
}

function or_set_delta_json(delta) {
  return $json.string($json.to_string($or_set.to_json(delta)));
}

export function encode_or_set_operation(operation) {
  if (operation instanceof $or_set_kernel.Add) {
    let element = operation.element;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orSetAdd")],
        ["element", $json.string(element)],
        ["delta", or_set_delta_json(delta)],
      ]),
    );
  } else {
    let element = operation.element;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orSetRemove")],
        ["element", $json.string(element)],
        ["delta", or_set_delta_json(delta)],
      ]),
    );
  }
}

function delta_json(delta) {
  return $json.string($json.to_string($or_map.delta_to_json(delta)));
}

export function encode_or_map_operation(operation) {
  if (operation instanceof $or_map_kernel.Increment) {
    let key = operation.key;
    let amount = operation.amount;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapIncrement")],
        ["key", $json.string(key)],
        ["amount", $json.int(amount)],
        ["delta", delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $or_map_kernel.SetRegister) {
    let key = operation.key;
    let value = operation.value;
    let timestamp = operation.timestamp;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapSet")],
        ["key", $json.string(key)],
        ["value", $json.string(value)],
        ["timestamp", $json.int(timestamp)],
        ["delta", delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $or_map_kernel.SetMvRegister) {
    let key = operation.key;
    let value = operation.value;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapSetMvRegister")],
        ["key", $json.string(key)],
        ["value", $json.string(value)],
        ["delta", delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $or_map_kernel.Remove) {
    let key = operation.key;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapRemove")],
        ["key", $json.string(key)],
        ["delta", delta_json(delta)],
      ]),
    );
  } else if (operation instanceof $or_map_kernel.AddMember) {
    let key = operation.key;
    let member = operation.member;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapAddMember")],
        ["key", $json.string(key)],
        ["member", $json.string(member)],
        ["delta", delta_json(delta)],
      ]),
    );
  } else {
    let key = operation.key;
    let member = operation.member;
    let delta = operation.delta;
    return $json.object(
      toList([
        ["type", $json.string("orMapRemoveMember")],
        ["key", $json.string(key)],
        ["member", $json.string(member)],
        ["delta", delta_json(delta)],
      ]),
    );
  }
}

export function encode_lww_map_operation(operation) {
  let _block;
  if (operation instanceof $lww_map_kernel.Set) {
    let key = operation.key;
    let value = operation.value;
    let timestamp = operation.timestamp;
    let delta = operation.delta;
    _block = [
      "lwwMapSet",
      key,
      timestamp,
      delta,
      toList([["value", $json.string(value)]]),
    ];
  } else {
    let key = operation.key;
    let timestamp = operation.timestamp;
    let delta = operation.delta;
    _block = ["lwwMapRemove", key, timestamp, delta, $List$Empty$const];
  }
  let $ = _block;
  let tag = $[0];
  let key = $[1];
  let timestamp = $[2];
  let delta = $[3];
  let value = $[4];
  return $json.object(
    $list.append(
      toList([
        ["type", $json.string(tag)],
        ["key", $json.string(key)],
        ["timestamp", $json.int(timestamp)],
        [
          "delta",
          $json.string(
            (() => {
              let _pipe = $lww_map.to_json(delta);
              return $json.to_string(_pipe);
            })(),
          ),
        ],
      ]),
      value,
    ),
  );
}

export function encode_lww_register_operation(operation) {
  let value = operation.value;
  let timestamp = operation.timestamp;
  let delta = operation.delta;
  return $json.object(
    toList([
      ["type", $json.string("lwwRegisterSet")],
      ["value", $json.string(value)],
      ["timestamp", $json.int(timestamp)],
      [
        "delta",
        $json.string(
          (() => {
            let _pipe = $lww_register.to_json(delta);
            return $json.to_string(_pipe);
          })(),
        ),
      ],
    ]),
  );
}

export function encode_mv_register_operation(operation) {
  let value = operation.value;
  let delta = operation.delta;
  return $json.object(
    toList([
      ["type", $json.string("mvRegisterSet")],
      ["value", $json.string(value)],
      [
        "delta",
        $json.string(
          (() => {
            let _pipe = $mv_register.to_json(delta);
            return $json.to_string(_pipe);
          })(),
        ),
      ],
    ]),
  );
}

function g_counter_delta_json(delta) {
  return $json.string($json.to_string($g_counter.to_json(delta)));
}

export function encode_g_counter_operation(operation) {
  let amount = operation.amount;
  let delta = operation.delta;
  return $json.object(
    toList([
      ["type", $json.string("gCounterIncrement")],
      ["amount", $json.int(amount)],
      ["delta", g_counter_delta_json(delta)],
    ]),
  );
}

function pn_counter_delta_json(delta) {
  return $json.string($json.to_string($pn_counter.to_json(delta)));
}

export function encode_pn_counter_operation(operation) {
  let amount = operation.amount;
  let delta = operation.delta;
  return $json.object(
    toList([
      ["type", $json.string("pnCounterUpdate")],
      ["amount", $json.int(amount)],
      ["delta", pn_counter_delta_json(delta)],
    ]),
  );
}

export function encode_counter_operation(operation) {
  let increment_amount = operation.increment_amount;
  return $json.object(
    toList([
      ["type", $json.string("increment")],
      ["incrementAmount", $json.int(increment_amount)],
    ]),
  );
}

export function encode_map_operation(operation) {
  if (operation instanceof Set) {
    let key = operation.key;
    let value = operation.value;
    return $json.object(
      toList([
        ["type", $json.string("set")],
        ["key", $json.string(key)],
        [
          "value",
          $json.object(
            toList([["type", $json.string("Plain")], ["value", value]]),
          ),
        ],
      ]),
    );
  } else if (operation instanceof Delete) {
    let key = operation.key;
    return $json.object(
      toList([["type", $json.string("delete")], ["key", $json.string(key)]]),
    );
  } else {
    return $json.object(toList([["type", $json.string("clear")]]));
  }
}

export function encode_channel_operation(operation) {
  if (operation instanceof $channel.MapOperation) {
    let operation$1 = operation[0];
    return encode_map_operation(operation$1);
  } else if (operation instanceof $channel.CounterOperation) {
    let operation$1 = operation[0];
    return encode_counter_operation(operation$1);
  } else if (operation instanceof $channel.PnCounterOperation) {
    let operation$1 = operation[0];
    return encode_pn_counter_operation(operation$1);
  } else if (operation instanceof $channel.GCounterOperation) {
    let operation$1 = operation[0];
    return encode_g_counter_operation(operation$1);
  } else if (operation instanceof $channel.LwwRegisterOperation) {
    let operation$1 = operation[0];
    return encode_lww_register_operation(operation$1);
  } else if (operation instanceof $channel.LwwMapOperation) {
    let operation$1 = operation[0];
    return encode_lww_map_operation(operation$1);
  } else if (operation instanceof $channel.MvRegisterOperation) {
    let operation$1 = operation[0];
    return encode_mv_register_operation(operation$1);
  } else if (operation instanceof $channel.OrMapOperation) {
    let operation$1 = operation[0];
    return encode_or_map_operation(operation$1);
  } else if (operation instanceof $channel.OrSetOperation) {
    let operation$1 = operation[0];
    return encode_or_set_operation(operation$1);
  } else if (operation instanceof $channel.GSetOperation) {
    let operation$1 = operation[0];
    return encode_g_set_operation(operation$1);
  } else if (operation instanceof $channel.TwoPSetOperation) {
    let operation$1 = operation[0];
    return encode_two_p_set_operation(operation$1);
  } else if (operation instanceof $channel.RegisterCollectionOperation) {
    let operation$1 = operation[0];
    return encode_register_collection_operation(operation$1);
  } else if (operation instanceof $channel.ClaimsOperation) {
    let operation$1 = operation[0];
    return encode_claim_operation(operation$1);
  } else if (operation instanceof $channel.TaskManagerOperation) {
    let operation$1 = operation[0];
    return encode_task_manager_operation(operation$1);
  } else if (operation instanceof $channel.PactMapOperation) {
    let operation$1 = operation[0];
    return encode_pact_map_operation(operation$1);
  } else if (operation instanceof $channel.JsonOtOperation) {
    let operation$1 = operation[0];
    return encode_json_ot_operation(operation$1);
  } else if (operation instanceof $channel.DirectoryOperation) {
    let operation$1 = operation.operation;
    let message_id = operation.message_id;
    return encode_directory_operation(operation$1, message_id);
  } else if (operation instanceof $channel.OrderedCollectionOperation) {
    let operation$1 = operation[0];
    return encode_ordered_operation(operation$1);
  } else if (operation instanceof $channel.SequenceOperation) {
    let operation$1 = operation[0];
    return encode_sequence_operation(operation$1);
  } else if (operation instanceof $channel.RichTextOperation) {
    let operation$1 = operation[0];
    return encode_rich_text_operation(operation$1);
  } else {
    let operation$1 = operation[0];
    return encode_text_operation(operation$1);
  }
}

/**
 * The `{address, contents}` document envelope around a kernel operation.
 */
export function encode_channel_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_channel_operation(operation)],
    ]),
  );
}

/**
 * Wrap a kernel operation in the document envelope as an outbound `"op"`
 * message.
 */
export function outbound_channel_operation(
  address,
  client_sequence_number,
  reference_sequence_number,
  operation
) {
  return new $wire.OutboundOperation(
    client_sequence_number,
    reference_sequence_number,
    "op",
    encode_channel_envelope(address, operation),
    Option$None$const,
  );
}

/**
 * An attach envelope carries the full channel snapshot as
 * `{type:"attach", address, channelType, snapshot}`. The channel type sets the
 * shape of the `snapshot` payload.
 */
export function encode_attach(address, snapshot) {
  return $json.object(
    toList([
      ["type", $json.string("attach")],
      ["address", $json.string(address)],
      [
        "channelType",
        $json.string($channel.type_to_string($channel.snapshot_type(snapshot))),
      ],
      ["snapshot", $channel.encode_snapshot(snapshot)],
    ]),
  );
}

export function outbound_attach_operation(
  address,
  client_sequence_number,
  reference_sequence_number,
  snapshot
) {
  return new $wire.OutboundOperation(
    client_sequence_number,
    reference_sequence_number,
    "op",
    encode_attach(address, snapshot),
    Option$None$const,
  );
}

/**
 * A `"summarize"` operation that announces a stored snapshot. The contents
 * carry the fields that the server needs. `handle` is the staged tree SHA.
 * `head` is the current published commit SHA, or an empty string for the first
 * summary. `parents` is empty for the first summary and otherwise contains
 * only `head`.
 */
export function outbound_summarize_operation(
  client_sequence_number,
  reference_sequence_number,
  handle,
  message,
  parents,
  head
) {
  return new $wire.OutboundOperation(
    client_sequence_number,
    reference_sequence_number,
    "summarize",
    $json.object(
      toList([
        ["handle", $json.string(handle)],
        ["message", $json.string(message)],
        ["parents", $json.array(parents, $json.string)],
        ["head", $json.string(head)],
      ]),
    ),
    Option$None$const,
  );
}

function default_text_delta() {
  return $text.new$($replica_id.new$(""));
}

function sequence_delta_shape_decoder() {
  return $decode.then$(
    $decode.at(toList(["state", "frontier"]), $version_vector.decoder()),
    (frontier) => {
      return $decode.then$(
        $decode.at(
          toList(["state", "forwardings"]),
          $decode.list($decode.dynamic),
        ),
        (forwardings) => {
          return $decode.then$(
            $decode.at(
              toList(["state", "segments"]),
              $decode.list(
                $decode.field(
                  "kind",
                  $decode.string,
                  (kind) => { return $decode.success(kind); },
                ),
              ),
            ),
            (segment_kinds) => {
              let $ = ($version_vector.is_empty(frontier) && $list.is_empty(
                forwardings,
              )) && $list.all(
                segment_kinds,
                (kind) => { return kind === "item"; },
              );
              if ($) {
                return $decode.success(undefined);
              } else {
                return $decode.failure(undefined, "SequenceDelta");
              }
            },
          );
        },
      );
    },
  );
}

function text_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $json.parse(encoded, sequence_delta_shape_decoder());
      if ($ instanceof Ok) {
        let $1 = $text.from_json(encoded);
        if ($1 instanceof Ok) {
          let delta = $1[0];
          return $decode.success(delta);
        } else {
          return $decode.failure(default_text_delta(), "TextDelta");
        }
      } else {
        return $decode.failure(default_text_delta(), "TextDelta");
      }
    },
  );
}

/**
 * Decode the wire tag of a `TextOperation`. The diagnostic intent fields,
 * which are the indexes, the ranges, and the value, travel with the
 * authoritative CRDT `delta`. A `delta` that is malformed or absent fails this
 * decoder, and thus fails stage two of the decode, before the operation
 * reaches the kernel.
 */
export function text_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "textInsert") {
        return $decode.field(
          "index",
          $decode.int,
          (index) => {
            return $decode.field(
              "value",
              $decode.string,
              (value) => {
                return $decode.field(
                  "delta",
                  text_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $text_kernel.Insert(index, value, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "textDeleteRange") {
        return $decode.field(
          "start",
          $decode.int,
          (start) => {
            return $decode.field(
              "end",
              $decode.int,
              (end) => {
                return $decode.field(
                  "delta",
                  text_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $text_kernel.DeleteRange(start, end, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "textReplaceRange") {
        return $decode.field(
          "start",
          $decode.int,
          (start) => {
            return $decode.field(
              "end",
              $decode.int,
              (end) => {
                return $decode.field(
                  "value",
                  $decode.string,
                  (value) => {
                    return $decode.field(
                      "delta",
                      text_delta_decoder(),
                      (delta) => {
                        return $decode.success(
                          new $text_kernel.ReplaceRange(
                            start,
                            end,
                            value,
                            delta,
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
      } else if (operation_type === "textAppend") {
        return $decode.field(
          "value",
          $decode.string,
          (value) => {
            return $decode.field(
              "delta",
              text_delta_decoder(),
              (delta) => {
                return $decode.success(new $text_kernel.Append(value, delta));
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $text_kernel.DeleteRange(0, 0, default_text_delta()),
          "TextOp",
        );
      }
    },
  );
}

function rich_text_delta_decoder() {
  return $decode.then$(
    $json_ot.decoder(),
    (raw) => {
      let $ = $rich_text.delta_from_json(raw);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure($rich_text.empty_delta(), "RichTextDelta");
      }
    },
  );
}

/**
 * A strict decoder for a rich-text operation envelope. The `delta` field must
 * decode as a correct Quill Delta, which is an array of insert, delete, and
 * retain operations. A malformed delta fails the whole decode. The decoder
 * does not drop the operation.
 */
export function rich_text_operation_decoder() {
  return $decode.field(
    "refSeq",
    $decode.int,
    (reference_sequence_number) => {
      return $decode.field(
        "delta",
        rich_text_delta_decoder(),
        (delta) => {
          return $decode.success(
            new RichTextWireOperation(reference_sequence_number, delta),
          );
        },
      );
    },
  );
}

function default_sequence_delta() {
  return $sequence.new$($replica_id.new$(""));
}

function sequence_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $json.parse(encoded, sequence_delta_shape_decoder());
      if ($ instanceof Ok) {
        let $1 = $sequence.from_json(encoded, $wire.json_value_decoder());
        if ($1 instanceof Ok) {
          let delta = $1[0];
          return $decode.success(delta);
        } else {
          return $decode.failure(default_sequence_delta(), "SequenceDelta");
        }
      } else {
        return $decode.failure(default_sequence_delta(), "SequenceDelta");
      }
    },
  );
}

export function sequence_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "sequenceInsert") {
        return $decode.field(
          "index",
          $decode.int,
          (index) => {
            return $decode.field(
              "value",
              $wire.json_value_decoder(),
              (value) => {
                return $decode.field(
                  "delta",
                  sequence_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $sequence_kernel.Insert(index, value, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "sequenceDelete") {
        return $decode.field(
          "index",
          $decode.int,
          (index) => {
            return $decode.field(
              "delta",
              sequence_delta_decoder(),
              (delta) => {
                return $decode.success(
                  new $sequence_kernel.Delete(index, delta),
                );
              },
            );
          },
        );
      } else if (operation_type === "sequenceMove") {
        return $decode.field(
          "fromIndex",
          $decode.int,
          (from_index) => {
            return $decode.field(
              "toIndex",
              $decode.int,
              (to_index) => {
                return $decode.field(
                  "delta",
                  sequence_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $sequence_kernel.Move(from_index, to_index, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "sequenceReplace") {
        return $decode.field(
          "index",
          $decode.int,
          (index) => {
            return $decode.field(
              "value",
              $wire.json_value_decoder(),
              (value) => {
                return $decode.field(
                  "delta",
                  sequence_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $sequence_kernel.Replace(index, value, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $sequence_kernel.Delete(0, default_sequence_delta()),
          "SequenceOp",
        );
      }
    },
  );
}

export function ordered_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "orderedAdd") {
        return $decode.field(
          "value",
          $wire.json_value_decoder(),
          (value) => {
            return $decode.success(new $ordered_collection_kernel.Add(value));
          },
        );
      } else if (operation_type === "orderedAcquire") {
        return $decode.field(
          "acquireId",
          $decode.string,
          (acquire_id) => {
            return $decode.success(
              new $ordered_collection_kernel.Acquire(acquire_id),
            );
          },
        );
      } else if (operation_type === "orderedComplete") {
        return $decode.field(
          "acquireId",
          $decode.string,
          (acquire_id) => {
            return $decode.success(
              new $ordered_collection_kernel.Complete(acquire_id),
            );
          },
        );
      } else if (operation_type === "orderedRelease") {
        return $decode.field(
          "acquireId",
          $decode.string,
          (acquire_id) => {
            return $decode.success(
              new $ordered_collection_kernel.Release(acquire_id),
            );
          },
        );
      } else {
        return $decode.failure(
          new $ordered_collection_kernel.Acquire(""),
          "OrderedOp",
        );
      }
    },
  );
}

function pact_map_value_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (value_type) => {
      if (value_type === "Plain") {
        return $decode.field(
          "value",
          $wire.json_value_decoder(),
          (inner) => { return $decode.success(new Some(inner)); },
        );
      } else if (value_type === "Absent") {
        return $decode.success(Option$None$const);
      } else {
        return $decode.failure(Option$None$const, "PactMapValue");
      }
    },
  );
}

export function pact_map_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "pactMapSet") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              pact_map_value_decoder(),
              (value) => {
                return $decode.field(
                  "refSeq",
                  $decode.int,
                  (reference_sequence_number) => {
                    return $decode.success(
                      new $pact_map_kernel.Set(
                        key,
                        value,
                        reference_sequence_number,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "pactMapAccept") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => { return $decode.success(new $pact_map_kernel.Accept(key)); },
        );
      } else {
        return $decode.failure(new $pact_map_kernel.Accept(""), "PactMapOp");
      }
    },
  );
}

/**
 * A `Plain` value carries an opaque kernel `Json` payload. This decoder does
 * not interpret a handle marker, for example `{"type":"Shared", ...}`. The
 * full runtime must materialize such a marker. This decoder accepts a `Plain`
 * marker only.
 * 
 * @ignore
 */
function plain_value_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (value_type) => {
      if (value_type === "Plain") {
        return $decode.field(
          "value",
          $wire.json_value_decoder(),
          $decode.success,
        );
      } else {
        return $decode.failure($json.null$(), "PlainValue");
      }
    },
  );
}

function directory_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      return $decode.field(
        "path",
        $decode.string,
        (path) => {
          return $decode.field(
            "mid",
            $decode.int,
            (message_id) => {
              if (operation_type === "dirSet") {
                return $decode.field(
                  "key",
                  $decode.string,
                  (key) => {
                    return $decode.field(
                      "value",
                      plain_value_decoder(),
                      (value) => {
                        return $decode.success(
                          new $channel.DirectoryOperation(
                            new $directory_kernel.Set(path, key, value),
                            message_id,
                          ),
                        );
                      },
                    );
                  },
                );
              } else if (operation_type === "dirDelete") {
                return $decode.field(
                  "key",
                  $decode.string,
                  (key) => {
                    return $decode.success(
                      new $channel.DirectoryOperation(
                        new $directory_kernel.Delete(path, key),
                        message_id,
                      ),
                    );
                  },
                );
              } else if (operation_type === "dirClear") {
                return $decode.success(
                  new $channel.DirectoryOperation(
                    new $directory_kernel.Clear(path),
                    message_id,
                  ),
                );
              } else if (operation_type === "dirCreateSub") {
                return $decode.field(
                  "name",
                  $decode.string,
                  (name) => {
                    return $decode.success(
                      new $channel.DirectoryOperation(
                        new $directory_kernel.CreateSubDirectory(path, name),
                        message_id,
                      ),
                    );
                  },
                );
              } else if (operation_type === "dirDeleteSub") {
                return $decode.field(
                  "name",
                  $decode.string,
                  (name) => {
                    return $decode.success(
                      new $channel.DirectoryOperation(
                        new $directory_kernel.DeleteSubDirectory(path, name),
                        message_id,
                      ),
                    );
                  },
                );
              } else {
                return $decode.failure(
                  new $channel.DirectoryOperation(
                    new $directory_kernel.Clear(path),
                    message_id,
                  ),
                  "DirectoryOp",
                );
              }
            },
          );
        },
      );
    },
  );
}

export function json_ot_operation_decoder() {
  return $decode.field(
    "refSeq",
    $decode.int,
    (reference_sequence_number) => {
      return $decode.field(
        "components",
        $json_ot.operation_decoder(),
        (components) => {
          return $decode.success(
            new JsonOtWireOperation(reference_sequence_number, components),
          );
        },
      );
    },
  );
}

export function task_manager_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "taskVolunteer") {
        return $decode.field(
          "taskId",
          $decode.string,
          (task_id) => {
            return $decode.success(new $task_manager_kernel.Volunteer(task_id));
          },
        );
      } else if (operation_type === "taskAbandon") {
        return $decode.field(
          "taskId",
          $decode.string,
          (task_id) => {
            return $decode.success(new $task_manager_kernel.Abandon(task_id));
          },
        );
      } else if (operation_type === "taskComplete") {
        return $decode.field(
          "taskId",
          $decode.string,
          (task_id) => {
            return $decode.success(new $task_manager_kernel.Complete(task_id));
          },
        );
      } else {
        return $decode.failure(
          new $task_manager_kernel.Volunteer(""),
          "TaskManagerOp",
        );
      }
    },
  );
}

export function claim_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "claim") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              plain_value_decoder(),
              (value) => {
                return $decode.field(
                  "refSeq",
                  $decode.int,
                  (reference_sequence_number) => {
                    return $decode.success(
                      new Claim(key, value, reference_sequence_number),
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(new Claim("", $json.null$(), 0), "ClaimOp");
      }
    },
  );
}

export function register_collection_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "registerWrite") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              plain_value_decoder(),
              (value) => {
                return $decode.field(
                  "refSeq",
                  $decode.int,
                  (reference_sequence_number) => {
                    return $decode.success(
                      new Write(key, value, reference_sequence_number),
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new Write("", $json.null$(), 0),
          "RegisterCollectionOp",
        );
      }
    },
  );
}

function default_two_p_set_delta() {
  return $two_p_set.new$();
}

function two_p_set_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $two_p_set.from_json(encoded);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_two_p_set_delta(), "TwoPSetDelta");
      }
    },
  );
}

export function two_p_set_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "twoPSetAdd") {
        return $decode.field(
          "element",
          $decode.string,
          (element) => {
            return $decode.field(
              "delta",
              two_p_set_delta_decoder(),
              (delta) => {
                let operation = new $two_p_set_kernel.Add(element, delta);
                return $decode.success(operation);
              },
            );
          },
        );
      } else if (operation_type === "twoPSetRemove") {
        return $decode.field(
          "element",
          $decode.string,
          (element) => {
            return $decode.field(
              "delta",
              two_p_set_delta_decoder(),
              (delta) => {
                let operation = new $two_p_set_kernel.Remove(element, delta);
                return $decode.success(operation);
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $two_p_set_kernel.Add("", default_two_p_set_delta()),
          "TwoPSetOp",
        );
      }
    },
  );
}

function default_g_set_delta() {
  return $g_set.new$();
}

function g_set_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $g_set.from_json(encoded);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_g_set_delta(), "GSetDelta");
      }
    },
  );
}

export function g_set_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "gSetAdd") {
        return $decode.field(
          "element",
          $decode.string,
          (element) => {
            return $decode.field(
              "delta",
              g_set_delta_decoder(),
              (delta) => {
                let operation = new $g_set_kernel.Add(element, delta);
                return $decode.success(operation);
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $g_set_kernel.Add("", default_g_set_delta()),
          "GSetOp",
        );
      }
    },
  );
}

function default_or_set_delta() {
  return $or_set.new$($replica_id.new$(""));
}

function or_set_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $or_set.from_json(encoded);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_or_set_delta(), "ORSetDelta");
      }
    },
  );
}

export function or_set_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "orSetAdd") {
        return $decode.field(
          "element",
          $decode.string,
          (element) => {
            return $decode.field(
              "delta",
              or_set_delta_decoder(),
              (delta) => {
                let operation = new $or_set_kernel.Add(element, delta);
                return $decode.success(operation);
              },
            );
          },
        );
      } else if (operation_type === "orSetRemove") {
        return $decode.field(
          "element",
          $decode.string,
          (element) => {
            return $decode.field(
              "delta",
              or_set_delta_decoder(),
              (delta) => {
                let operation = new $or_set_kernel.Remove(element, delta);
                return $decode.success(operation);
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $or_set_kernel.Remove("", default_or_set_delta()),
          "OrSetOp",
        );
      }
    },
  );
}

function default_or_map_delta() {
  let _pipe = $or_map.new$(
    $replica_id.new$(""),
    $crdt.CrdtSpec$PnCounterSpec$const,
  );
  return $or_map.empty_delta(_pipe);
}

function validated_set_operation(operation) {
  let $ = $or_map_kernel.validate_operation(
    $or_map_kernel.OrMapMode$OrSetMode$const,
    operation,
  );
  if ($ instanceof Ok) {
    return $decode.success(operation);
  } else {
    return $decode.failure(operation, "ORMap set operation intent");
  }
}

function or_map_spec_name(encoded) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(
        encoded,
        $decode.at(toList(["state", "spec"]), $decode.string),
      );
      return $result.map_error(_pipe, (_) => { return undefined; });
    })(),
    (spec) => {
      let _pipe = $json.parse(
        spec,
        $decode.field(
          "type",
          $decode.string,
          (name) => { return $decode.success(name); },
        ),
      );
      return $result.map_error(_pipe, (_) => { return undefined; });
    },
  );
}

function checked_or_map_operation(operation, delta) {
  let $ = or_map_spec_name(
    (() => {
      let _pipe = $or_map.delta_to_json(delta);
      return $json.to_string(_pipe);
    })(),
  );
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 === "or_set") {
      return validated_set_operation(operation);
    } else {
      return $decode.success(operation);
    }
  } else {
    return $decode.success(operation);
  }
}

function or_map_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let _block;
      let $ = or_map_spec_name(encoded);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 === "or_set") {
          let _pipe = $or_map_set_leaf.decode_delta(encoded);
          _block = $result.map_error(_pipe, (_) => { return undefined; });
        } else {
          let _pipe = $or_map.delta_from_json(encoded);
          _block = $result.map_error(_pipe, (_) => { return undefined; });
        }
      } else {
        _block = new Error(undefined);
      }
      let decoded = _block;
      if (decoded instanceof Ok) {
        let delta = decoded[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_or_map_delta(), "ORMapDelta");
      }
    },
  );
}

function or_map_intent_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "orMapIncrement") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "amount",
              $decode.int,
              (amount) => {
                return $decode.field(
                  "delta",
                  or_map_delta_decoder(),
                  (delta) => {
                    return checked_or_map_operation(
                      new $or_map_kernel.Increment(key, amount, delta),
                      delta,
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "orMapSet") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              $decode.string,
              (value) => {
                return $decode.field(
                  "timestamp",
                  $decode.int,
                  (timestamp) => {
                    return $decode.field(
                      "delta",
                      or_map_delta_decoder(),
                      (delta) => {
                        return checked_or_map_operation(
                          new $or_map_kernel.SetRegister(
                            key,
                            value,
                            timestamp,
                            delta,
                          ),
                          delta,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "orMapSetMvRegister") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              $decode.string,
              (value) => {
                return $decode.field(
                  "delta",
                  or_map_delta_decoder(),
                  (delta) => {
                    return $decode.success(
                      new $or_map_kernel.SetMvRegister(key, value, delta),
                    );
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "orMapRemove") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "delta",
              or_map_delta_decoder(),
              (delta) => {
                return checked_or_map_operation(
                  new $or_map_kernel.Remove(key, delta),
                  delta,
                );
              },
            );
          },
        );
      } else if (operation_type === "orMapAddMember") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "member",
              $decode.string,
              (member) => {
                return $decode.field(
                  "delta",
                  $decode.string,
                  (encoded) => {
                    let $ = $or_map_set_leaf.decode_delta(encoded);
                    if ($ instanceof Ok) {
                      let delta = $[0];
                      let _block;
                      if (operation_type === "orMapAddMember") {
                        _block = new $or_map_kernel.AddMember(
                          key,
                          member,
                          delta,
                        );
                      } else {
                        _block = new $or_map_kernel.RemoveMember(
                          key,
                          member,
                          delta,
                        );
                      }
                      let operation = _block;
                      return validated_set_operation(operation);
                    } else {
                      return $decode.failure(
                        new $or_map_kernel.Remove("", default_or_map_delta()),
                        "ORMap set delta",
                      );
                    }
                  },
                );
              },
            );
          },
        );
      } else if (operation_type === "orMapRemoveMember") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "member",
              $decode.string,
              (member) => {
                return $decode.field(
                  "delta",
                  $decode.string,
                  (encoded) => {
                    let $ = $or_map_set_leaf.decode_delta(encoded);
                    if ($ instanceof Ok) {
                      let delta = $[0];
                      let _block;
                      if (operation_type === "orMapAddMember") {
                        _block = new $or_map_kernel.AddMember(
                          key,
                          member,
                          delta,
                        );
                      } else {
                        _block = new $or_map_kernel.RemoveMember(
                          key,
                          member,
                          delta,
                        );
                      }
                      let operation = _block;
                      return validated_set_operation(operation);
                    } else {
                      return $decode.failure(
                        new $or_map_kernel.Remove("", default_or_map_delta()),
                        "ORMap set delta",
                      );
                    }
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $or_map_kernel.Remove("", default_or_map_delta()),
          "OrMapOp",
        );
      }
    },
  );
}

export function or_map_operation_decoder() {
  return $decode.then$(
    or_map_intent_decoder(),
    (operation) => {
      let $ = $or_map_kernel.validate_operation_intent(operation);
      if ($ instanceof Ok) {
        return $decode.success(operation);
      } else {
        return $decode.failure(operation, "OR-map intent matching its delta");
      }
    },
  );
}

export function lww_map_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "key",
        $decode.string,
        (key) => {
          return $decode.field(
            "timestamp",
            $decode.int,
            (timestamp) => {
              return $decode.field(
                "delta",
                $decode.string,
                (encoded) => {
                  let $ = $json.parse(encoded, $lww_map_kernel.decoder());
                  if ($ instanceof Ok) {
                    let delta = $[0];
                    return $decode.then$(
                      (() => {
                        if (tag === "lwwMapSet") {
                          return $decode.field(
                            "value",
                            $decode.string,
                            (value) => {
                              return $decode.success(
                                new $lww_map_kernel.Set(
                                  key,
                                  value,
                                  timestamp,
                                  delta,
                                ),
                              );
                            },
                          );
                        } else if (tag === "lwwMapRemove") {
                          return $decode.success(
                            new $lww_map_kernel.Remove(key, timestamp, delta),
                          );
                        } else {
                          return $decode.failure(
                            new $lww_map_kernel.Remove(key, timestamp, delta),
                            "lwwMapSet or lwwMapRemove",
                          );
                        }
                      })(),
                      (operation) => {
                        let $1 = $lww_map_kernel.validate_operation(operation);
                        if ($1 instanceof Ok) {
                          return $decode.success(operation);
                        } else {
                          return $decode.failure(
                            operation,
                            "matching single-key LWW map fragment",
                          );
                        }
                      },
                    );
                  } else {
                    return $decode.failure(
                      new $lww_map_kernel.Remove(
                        key,
                        timestamp,
                        $lww_map.new$(
                          $replica_id.new$(""),
                          new $crdt.LwwRegisterSpec(""),
                        ),
                      ),
                      "LwwMapDelta",
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
}

export function lww_register_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "value",
        $decode.string,
        (value) => {
          return $decode.field(
            "timestamp",
            $decode.int,
            (timestamp) => {
              return $decode.field(
                "delta",
                $decode.string,
                (encoded) => {
                  let $ = $json.parse(encoded, $channel.lww_register_decoder());
                  if ($ instanceof Ok) {
                    let delta = $[0];
                    let operation = new $lww_register_kernel.Set(
                      value,
                      timestamp,
                      delta,
                    );
                    let metadata = $decode.then$(
                      $decode.at(toList(["state", "timestamp"]), $decode.int),
                      (stamp) => {
                        return $decode.then$(
                          $decode.at(
                            toList(["state", "replica_id"]),
                            $decode.string,
                          ),
                          (author) => {
                            return $decode.success([stamp, author]);
                          },
                        );
                      },
                    );
                    let $1 = $json.parse(encoded, metadata);
                    if ($1 instanceof Ok) {
                      let stamp = $1[0][0];
                      let author = $1[0][1];
                      if (
                        ((tag === "lwwRegisterSet") && (author !== "")) && (timestamp === stamp)
                      ) {
                        let $2 = $lww_register.value(delta) === value;
                        if ($2) {
                          return $decode.success(operation);
                        } else {
                          return $decode.failure(
                            operation,
                            "matching LWW register value",
                          );
                        }
                      } else {
                        return $decode.failure(
                          operation,
                          "matching LWW register timestamp and author",
                        );
                      }
                    } else {
                      return $decode.failure(
                        operation,
                        "matching LWW register timestamp and author",
                      );
                    }
                  } else {
                    return $decode.failure(
                      new $lww_register_kernel.Set(
                        value,
                        timestamp,
                        $lww_register.new$("", 0, $replica_id.new$("")),
                      ),
                      "LwwRegisterDelta",
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
}

export function mv_register_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "value",
        $decode.string,
        (value) => {
          return $decode.field(
            "delta",
            $decode.string,
            (encoded) => {
              let $ = $mv_register_kernel.decode_crdt(encoded);
              if ($ instanceof Ok) {
                let delta = $[0];
                let $1 = (tag === "mvRegisterSet") && (isEqual(
                  $mv_register.value(delta),
                  toList([value])
                ));
                if ($1) {
                  return $decode.success(
                    new $mv_register_kernel.Set(value, delta),
                  );
                } else {
                  return $decode.failure(
                    new $mv_register_kernel.Set(value, delta),
                    "one matching MV-register write",
                  );
                }
              } else {
                return $decode.failure(
                  new $mv_register_kernel.Set(
                    value,
                    $mv_register.new$($replica_id.new$("")),
                  ),
                  "MvRegisterDelta",
                );
              }
            },
          );
        },
      );
    },
  );
}

function default_g_counter_delta() {
  return $g_counter.new$($replica_id.new$(""));
}

function g_counter_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $g_counter.from_json(encoded);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_g_counter_delta(), "GCounterDelta");
      }
    },
  );
}

function non_negative_int_decoder() {
  return $decode.then$(
    $decode.int,
    (value) => {
      let $ = value >= 0;
      if ($) {
        return $decode.success(value);
      } else {
        return $decode.failure(0, "a non-negative integer");
      }
    },
  );
}

/**
 * The grow-only counter accepts one operation type. The decoder rejects a
 * negative intent amount, because the public API cannot produce one, and a
 * fragment whose per-replica counts do not decode. It does not require the
 * count of the fragment to equal the intent amount: the fragment is
 * cumulative, and it thus carries the total of that replica.
 */
export function g_counter_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "gCounterIncrement") {
        return $decode.field(
          "amount",
          non_negative_int_decoder(),
          (amount) => {
            return $decode.field(
              "delta",
              g_counter_delta_decoder(),
              (delta) => {
                return $decode.success(
                  new $g_counter_kernel.Increment(amount, delta),
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $g_counter_kernel.Increment(0, default_g_counter_delta()),
          "GCounterOp",
        );
      }
    },
  );
}

function default_pn_counter_delta() {
  return $pn_counter.new$($replica_id.new$(""));
}

function pn_counter_delta_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $pn_counter.from_json(encoded);
      if ($ instanceof Ok) {
        let delta = $[0];
        return $decode.success(delta);
      } else {
        return $decode.failure(default_pn_counter_delta(), "PNCounterDelta");
      }
    },
  );
}

export function pn_counter_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "pnCounterUpdate") {
        return $decode.field(
          "amount",
          $decode.int,
          (amount) => {
            return $decode.field(
              "delta",
              pn_counter_delta_decoder(),
              (delta) => {
                return $decode.success(
                  new $pn_counter_kernel.Update(amount, delta),
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new $pn_counter_kernel.Update(0, default_pn_counter_delta()),
          "PnCounterOp",
        );
      }
    },
  );
}

export function counter_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "increment") {
        return $decode.field(
          "incrementAmount",
          $decode.int,
          (increment_amount) => {
            return $decode.success(new Increment(increment_amount));
          },
        );
      } else {
        return $decode.failure(new Increment(0), "CounterOp");
      }
    },
  );
}

export function map_operation_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (operation_type) => {
      if (operation_type === "set") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => {
            return $decode.field(
              "value",
              plain_value_decoder(),
              (value) => { return $decode.success(new Set(key, value)); },
            );
          },
        );
      } else if (operation_type === "delete") {
        return $decode.field(
          "key",
          $decode.string,
          (key) => { return $decode.success(new Delete(key)); },
        );
      } else if (operation_type === "clear") {
        return $decode.success(MapOperation$Clear$const);
      } else {
        return $decode.failure(MapOperation$Clear$const, "MapOp");
      }
    },
  );
}

/**
 * The decoder for the `contents` payload of a channel operation. The
 * registered type of the channel selects it. This is stage two of
 * `decode_operation_contents`.
 */
export function channel_operation_decoder(channel_type) {
  if (channel_type instanceof $channel.MapChannel) {
    let _pipe = map_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.MapOperation(var0); },
    );
  } else if (channel_type instanceof $channel.CounterChannel) {
    let _pipe = counter_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.CounterOperation(var0); },
    );
  } else if (channel_type instanceof $channel.PnCounterChannel) {
    let _pipe = pn_counter_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.PnCounterOperation(var0); },
    );
  } else if (channel_type instanceof $channel.GCounterChannel) {
    let _pipe = g_counter_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.GCounterOperation(var0); },
    );
  } else if (channel_type instanceof $channel.LwwRegisterChannel) {
    let _pipe = lww_register_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.LwwRegisterOperation(var0); },
    );
  } else if (channel_type instanceof $channel.LwwMapChannel) {
    let _pipe = lww_map_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.LwwMapOperation(var0); },
    );
  } else if (channel_type instanceof $channel.MvRegisterChannel) {
    let _pipe = mv_register_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.MvRegisterOperation(var0); },
    );
  } else if (channel_type instanceof $channel.OrMapChannel) {
    let _pipe = or_map_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.OrMapOperation(var0); },
    );
  } else if (channel_type instanceof $channel.OrSetChannel) {
    let _pipe = or_set_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.OrSetOperation(var0); },
    );
  } else if (channel_type instanceof $channel.GSetChannel) {
    let _pipe = g_set_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.GSetOperation(var0); },
    );
  } else if (channel_type instanceof $channel.TwoPSetChannel) {
    let _pipe = two_p_set_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.TwoPSetOperation(var0); },
    );
  } else if (channel_type instanceof $channel.RegisterCollectionChannel) {
    let _pipe = register_collection_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.RegisterCollectionOperation(var0); },
    );
  } else if (channel_type instanceof $channel.ClaimsChannel) {
    let _pipe = claim_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.ClaimsOperation(var0); },
    );
  } else if (channel_type instanceof $channel.TaskManagerChannel) {
    let _pipe = task_manager_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.TaskManagerOperation(var0); },
    );
  } else if (channel_type instanceof $channel.PactMapChannel) {
    let _pipe = pact_map_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.PactMapOperation(var0); },
    );
  } else if (channel_type instanceof $channel.JsonOtChannel) {
    let _pipe = json_ot_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.JsonOtOperation(var0); },
    );
  } else if (channel_type instanceof $channel.DirectoryChannel) {
    return directory_operation_decoder();
  } else if (channel_type instanceof $channel.OrderedCollectionChannel) {
    let _pipe = ordered_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.OrderedCollectionOperation(var0); },
    );
  } else if (channel_type instanceof $channel.SequenceChannel) {
    let _pipe = sequence_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.SequenceOperation(var0); },
    );
  } else if (channel_type instanceof $channel.RichTextChannel) {
    let _pipe = rich_text_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.RichTextOperation(var0); },
    );
  } else {
    let _pipe = text_operation_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new $channel.TextOperation(var0); },
    );
  }
}

/**
 * The `{address, contents}` document envelope around a map operation.
 */
export function encode_map_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_map_operation(operation)],
    ]),
  );
}

/**
 * The `{address, contents}` document envelope around a SharedCounter
 * operation.
 */
export function encode_counter_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_counter_operation(operation)],
    ]),
  );
}

/**
 * The `{address, contents}` document envelope around a PnCounter operation.
 */
export function encode_pn_counter_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_pn_counter_operation(operation)],
    ]),
  );
}

/**
 * The `{address, contents}` document envelope around a GCounter operation.
 */
export function encode_g_counter_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_g_counter_operation(operation)],
    ]),
  );
}

export function encode_lww_register_envelope(address, operation) {
  return encode_channel_envelope(
    address,
    new $channel.LwwRegisterOperation(operation),
  );
}

export function encode_lww_map_envelope(address, operation) {
  return encode_channel_envelope(
    address,
    new $channel.LwwMapOperation(operation),
  );
}

export function lww_map_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        lww_map_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

export function decode_lww_map_envelope(contents) {
  return $decode.run(contents, lww_map_envelope_decoder());
}

export function lww_register_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        lww_register_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

export function decode_lww_register_envelope(contents) {
  return $decode.run(contents, lww_register_envelope_decoder());
}

export function encode_mv_register_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_mv_register_operation(operation)],
    ]),
  );
}

export function mv_register_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        mv_register_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

export function decode_mv_register_envelope(contents) {
  return $decode.run(contents, mv_register_envelope_decoder());
}

/**
 * The `{address, contents}` document envelope around an OrMap operation.
 */
export function encode_or_map_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_or_map_operation(operation)],
    ]),
  );
}

export function encode_or_set_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_or_set_operation(operation)],
    ]),
  );
}

export function encode_g_set_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_g_set_operation(operation)],
    ]),
  );
}

export function encode_two_p_set_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_two_p_set_operation(operation)],
    ]),
  );
}

export function encode_register_collection_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_register_collection_operation(operation)],
    ]),
  );
}

export function encode_claim_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_claim_operation(operation)],
    ]),
  );
}

export function encode_task_manager_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_task_manager_operation(operation)],
    ]),
  );
}

/**
 * The `{address, contents}` document envelope around a PactMap operation.
 */
export function encode_pact_map_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_pact_map_operation(operation)],
    ]),
  );
}

export function pact_map_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        pact_map_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

export function decode_pact_map_envelope(contents) {
  return $decode.run(contents, pact_map_envelope_decoder());
}

/**
 * The `{address, contents}` document envelope around an ordered-collection
 * operation.
 */
export function encode_ordered_envelope(address, operation) {
  return $json.object(
    toList([
      ["address", $json.string(address)],
      ["contents", encode_ordered_operation(operation)],
    ]),
  );
}

export function ordered_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        ordered_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

export function decode_ordered_envelope(contents) {
  return $decode.run(contents, ordered_envelope_decoder());
}

export function map_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        map_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

/**
 * Decode the `contents` of a sequenced `"op"` message into
 * `#(address, MapOperation)`.
 */
export function decode_map_envelope(contents) {
  return $decode.run(contents, map_envelope_decoder());
}

export function counter_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        counter_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

/**
 * Decode the `contents` of a sequenced `"op"` message into
 * `#(address, CounterOperation)`.
 */
export function decode_counter_envelope(contents) {
  return $decode.run(contents, counter_envelope_decoder());
}

export function pn_counter_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        pn_counter_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

/**
 * Decode the `contents` of a sequenced `"op"` message into
 * `#(address, PnCounterOperation)`.
 */
export function decode_pn_counter_envelope(contents) {
  return $decode.run(contents, pn_counter_envelope_decoder());
}

export function g_counter_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        g_counter_operation_decoder(),
        (operation) => { return $decode.success([address, operation]); },
      );
    },
  );
}

/**
 * Decode the `contents` of a sequenced `"op"` message into
 * `#(address, GCounterOperation)`.
 */
export function decode_g_counter_envelope(contents) {
  return $decode.run(contents, g_counter_envelope_decoder());
}

export function attach_envelope_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (t) => {
      if (t === "attach") {
        return $decode.field(
          "address",
          $decode.string,
          (address) => {
            return $decode.field(
              "channelType",
              $decode.string,
              (channel_type) => {
                let $ = $channel.string_to_type(channel_type);
                if ($ instanceof Ok) {
                  let channel_type$1 = $[0];
                  return $decode.field(
                    "snapshot",
                    $channel.snapshot_decoder(channel_type$1),
                    (snapshot) => {
                      return $decode.success(
                        new AttachOperation(address, snapshot),
                      );
                    },
                  );
                } else {
                  return $decode.failure(
                    new AttachOperation(
                      "",
                      new $channel.MapSnapshot($List$Empty$const),
                    ),
                    "ChannelType",
                  );
                }
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new AttachOperation("", new $channel.MapSnapshot($List$Empty$const)),
          "AttachEnvelope",
        );
      }
    },
  );
}

function channel_envelope_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "contents",
        $decode.dynamic,
        (contents) => {
          return $decode.success(new ChannelOperation(address, contents));
        },
      );
    },
  );
}

export function decode_operation_contents(contents) {
  let $ = $decode.run(contents, $decode.at(toList(["type"]), $decode.string));
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 === "attach") {
      return $decode.run(contents, attach_envelope_decoder());
    } else {
      return $decode.run(contents, channel_envelope_decoder());
    }
  } else {
    return $decode.run(contents, channel_envelope_decoder());
  }
}
