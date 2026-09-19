/// <reference types="./summary.d.mts" />
import * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import { Error, toList, CustomType as $CustomType } from "../../gleam.mjs";

export class Ack extends $CustomType {
  constructor(proposal_sequence_number, version_id) {
    super();
    this.proposal_sequence_number = proposal_sequence_number;
    this.version_id = version_id;
  }
}
export const SummaryResponse$Ack = (proposal_sequence_number, version_id) =>
  new Ack(proposal_sequence_number, version_id);
export const SummaryResponse$isAck = (value) => value instanceof Ack;
export const SummaryResponse$Ack$proposal_sequence_number = (value) =>
  value.proposal_sequence_number;
export const SummaryResponse$Ack$0 = (value) => value.proposal_sequence_number;
export const SummaryResponse$Ack$version_id = (value) => value.version_id;
export const SummaryResponse$Ack$1 = (value) => value.version_id;

export class Nack extends $CustomType {
  constructor(proposal_sequence_number, reason) {
    super();
    this.proposal_sequence_number = proposal_sequence_number;
    this.reason = reason;
  }
}
export const SummaryResponse$Nack = (proposal_sequence_number, reason) =>
  new Nack(proposal_sequence_number, reason);
export const SummaryResponse$isNack = (value) => value instanceof Nack;
export const SummaryResponse$Nack$proposal_sequence_number = (value) =>
  value.proposal_sequence_number;
export const SummaryResponse$Nack$0 = (value) => value.proposal_sequence_number;
export const SummaryResponse$Nack$reason = (value) => value.reason;
export const SummaryResponse$Nack$1 = (value) => value.reason;

export const SummaryResponse$proposal_sequence_number = (value) =>
  value.proposal_sequence_number;

function nack_decoder() {
  return $decode.subfield(
    toList(["summaryProposal", "summarySequenceNumber"]),
    $decode.int,
    (proposal_sequence_number) => {
      return $decode.field(
        "message",
        $decode.string,
        (reason) => {
          return $decode.success(new Nack(proposal_sequence_number, reason));
        },
      );
    },
  );
}

function ack_decoder() {
  return $decode.field(
    "handle",
    $decode.string,
    (version_id) => {
      return $decode.subfield(
        toList(["summaryProposal", "summarySequenceNumber"]),
        $decode.int,
        (proposal_sequence_number) => {
          return $decode.success(new Ack(proposal_sequence_number, version_id));
        },
      );
    },
  );
}

export function decode_message(message_type, contents) {
  if (message_type === "summaryAck") {
    let _pipe = $decode.run(contents, ack_decoder());
    return $result.replace_error(_pipe, undefined);
  } else if (message_type === "summaryNack") {
    let _pipe = $decode.run(contents, nack_decoder());
    return $result.replace_error(_pipe, undefined);
  } else {
    return new Error(undefined);
  }
}
