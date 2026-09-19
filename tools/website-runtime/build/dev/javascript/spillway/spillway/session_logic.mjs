/// <reference types="./session_logic.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";

export class SequencedOpParams extends $CustomType {
  constructor(client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, op_type, contents, metadata, timestamp) {
    super();
    this.client_id = client_id;
    this.sequence_number = sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
    this.client_sequence_number = client_sequence_number;
    this.reference_sequence_number = reference_sequence_number;
    this.op_type = op_type;
    this.contents = contents;
    this.metadata = metadata;
    this.timestamp = timestamp;
  }
}
export const SequencedOpParams$SequencedOpParams = (client_id, sequence_number, minimum_sequence_number, client_sequence_number, reference_sequence_number, op_type, contents, metadata, timestamp) =>
  new SequencedOpParams(client_id,
  sequence_number,
  minimum_sequence_number,
  client_sequence_number,
  reference_sequence_number,
  op_type,
  contents,
  metadata,
  timestamp);
export const SequencedOpParams$isSequencedOpParams = (value) =>
  value instanceof SequencedOpParams;
export const SequencedOpParams$SequencedOpParams$client_id = (value) =>
  value.client_id;
export const SequencedOpParams$SequencedOpParams$0 = (value) => value.client_id;
export const SequencedOpParams$SequencedOpParams$sequence_number = (value) =>
  value.sequence_number;
export const SequencedOpParams$SequencedOpParams$1 = (value) =>
  value.sequence_number;
export const SequencedOpParams$SequencedOpParams$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const SequencedOpParams$SequencedOpParams$2 = (value) =>
  value.minimum_sequence_number;
export const SequencedOpParams$SequencedOpParams$client_sequence_number = (value) =>
  value.client_sequence_number;
export const SequencedOpParams$SequencedOpParams$3 = (value) =>
  value.client_sequence_number;
export const SequencedOpParams$SequencedOpParams$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SequencedOpParams$SequencedOpParams$4 = (value) =>
  value.reference_sequence_number;
export const SequencedOpParams$SequencedOpParams$op_type = (value) =>
  value.op_type;
export const SequencedOpParams$SequencedOpParams$5 = (value) => value.op_type;
export const SequencedOpParams$SequencedOpParams$contents = (value) =>
  value.contents;
export const SequencedOpParams$SequencedOpParams$6 = (value) => value.contents;
export const SequencedOpParams$SequencedOpParams$metadata = (value) =>
  value.metadata;
export const SequencedOpParams$SequencedOpParams$7 = (value) => value.metadata;
export const SequencedOpParams$SequencedOpParams$timestamp = (value) =>
  value.timestamp;
export const SequencedOpParams$SequencedOpParams$8 = (value) => value.timestamp;

/**
 * Negotiate features between server and client capabilities.
 * Returns a map of features that both sides agree on.
 *
 * Rules:
 * - Server supports (true), client supports (true) -> true
 * - Server supports (true), client doesn't specify -> true (advertise)
 * - Server supports (true), client declines (false) -> false
 * - Otherwise -> server value
 */
export function negotiate_features(server_features, client_features) {
  return $dict.map_values(
    server_features,
    (feature, server_value) => {
      let $ = $dict.get(client_features, feature);
      if (server_value) {
        if ($ instanceof Ok) {
          let $1 = $[0];
          if ($1) {
            return server_value;
          } else {
            return false;
          }
        } else {
          return server_value;
        }
      } else {
        return server_value;
      }
    },
  );
}

/**
 * Negotiate protocol version based on client's supported version ranges.
 * Returns the first server version that matches any client version range.
 * Falls back to "0.1.0" if no match found.
 */
export function negotiate_version(supported_versions, client_versions) {
  let $ = $list.find(
    supported_versions,
    (sv) => { return $list.contains(client_versions, sv); },
  );
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 === "^0.1.0") {
      return "0.1.0";
    } else if ($1 === "^1.0.0") {
      return "1.0.0";
    } else {
      let v = $1;
      return v;
    }
  } else {
    return "0.1.0";
  }
}

/**
 * Validate that summarize operation contents have all required fields.
 * Returns Ok(Nil) if valid, Error with missing field names if not.
 */
export function validate_summarize_contents(contents) {
  let required = toList(["handle", "message", "parents", "head"]);
  let missing = $list.filter(
    required,
    (field) => {
      let $ = $dict.get(contents, field);
      if ($ instanceof Ok) {
        return false;
      } else {
        return true;
      }
    },
  );
  if (missing instanceof $Empty) {
    return new Ok(undefined);
  } else {
    return new Error("missing fields: " + $string.join(missing, ", "));
  }
}

/**
 * Determine which clients should receive a signal based on targeting rules.
 *
 * Priority: targeted_clients > ignored_clients > single target > broadcast
 *
 * - targeted_clients: send only to specified clients (excluding sender)
 * - ignored_clients: send to all except ignored and sender
 * - single_target: send only to the target (if in all_clients and not sender)
 * - broadcast: send to all except sender
 */
export function determine_signal_recipients(
  sender_client_id,
  targeted_clients,
  ignored_clients,
  single_target,
  all_client_ids
) {
  if (targeted_clients instanceof Some) {
    let targets = targeted_clients[0];
    let _pipe = targets;
    let _pipe$1 = $list.filter(_pipe, (c) => { return c !== sender_client_id; });
    return $list.filter(
      _pipe$1,
      (c) => { return $list.contains(all_client_ids, c); },
    );
  } else if (ignored_clients instanceof Some) {
    let ignored = ignored_clients[0];
    let _pipe = all_client_ids;
    return $list.filter(
      _pipe,
      (c) => { return (c !== sender_client_id) && !$list.contains(ignored, c); },
    );
  } else if (single_target instanceof Some) {
    let target = single_target[0];
    let $ = (target !== sender_client_id) && $list.contains(
      all_client_ids,
      target,
    );
    if ($) {
      return toList([target]);
    } else {
      return $List$Empty$const;
    }
  } else {
    return $list.filter(
      all_client_ids,
      (c) => { return c !== sender_client_id; },
    );
  }
}

/**
 * Add an operation to the history (newest first) and trim to max size.
 */
export function add_to_history(op, history, max_size) {
  let _pipe = listPrepend(op, history);
  return $list.take(_pipe, max_size);
}
