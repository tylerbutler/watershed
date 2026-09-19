/// <reference types="./summary_blob.d.mts" />
import * as $json from "../../../gleam_json/gleam/json.mjs";
import * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../../gleam_stdlib/gleam/int.mjs";
import {
  Ok,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../../gleam.mjs";
import * as $channel from "../../watershed/channel.mjs";

export class SummaryBlob extends $CustomType {
  constructor(sequence_number, members, channels) {
    super();
    this.sequence_number = sequence_number;
    this.members = members;
    this.channels = channels;
  }
}
export const SummaryBlob$SummaryBlob = (sequence_number, members, channels) =>
  new SummaryBlob(sequence_number, members, channels);
export const SummaryBlob$isSummaryBlob = (value) =>
  value instanceof SummaryBlob;
export const SummaryBlob$SummaryBlob$sequence_number = (value) =>
  value.sequence_number;
export const SummaryBlob$SummaryBlob$0 = (value) => value.sequence_number;
export const SummaryBlob$SummaryBlob$members = (value) => value.members;
export const SummaryBlob$SummaryBlob$1 = (value) => value.members;
export const SummaryBlob$SummaryBlob$channels = (value) => value.channels;
export const SummaryBlob$SummaryBlob$2 = (value) => value.channels;

export class ChannelSnapshot extends $CustomType {
  constructor(address, snapshot) {
    super();
    this.address = address;
    this.snapshot = snapshot;
  }
}
export const ChannelSnapshot$ChannelSnapshot = (address, snapshot) =>
  new ChannelSnapshot(address, snapshot);
export const ChannelSnapshot$isChannelSnapshot = (value) =>
  value instanceof ChannelSnapshot;
export const ChannelSnapshot$ChannelSnapshot$address = (value) => value.address;
export const ChannelSnapshot$ChannelSnapshot$0 = (value) => value.address;
export const ChannelSnapshot$ChannelSnapshot$snapshot = (value) =>
  value.snapshot;
export const ChannelSnapshot$ChannelSnapshot$1 = (value) => value.snapshot;

/**
 * The current on-disk format version. A loader refuses a version that it does
 * not recognize. It does not read a foreign snapshot incorrectly.
 */
export const version = 4;

export function encode_channels(sequence_number, members, channels) {
  return $json.object(
    toList([
      ["watershedSummaryVersion", $json.int(version)],
      ["sequenceNumber", $json.int(sequence_number)],
      ["members", $json.array(members, $json.int)],
      [
        "channels",
        $json.array(
          channels,
          (entry) => {
            let address = entry[0];
            let snapshot = entry[1];
            return $json.object(
              toList([
                ["address", $json.string(address)],
                [
                  "type",
                  $json.string(
                    $channel.type_to_string($channel.snapshot_type(snapshot)),
                  ),
                ],
                ["data", $channel.encode_snapshot(snapshot)],
              ]),
            );
          },
        ),
      ],
    ]),
  );
}

function channel_snapshot_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (address) => {
      return $decode.field(
        "type",
        $decode.string,
        (channel_type) => {
          let $ = $channel.string_to_type(channel_type);
          if ($ instanceof Ok) {
            let channel_type$1 = $[0];
            return $decode.field(
              "data",
              $channel.snapshot_decoder(channel_type$1),
              (snapshot) => {
                return $decode.success(new ChannelSnapshot(address, snapshot));
              },
            );
          } else {
            return $decode.failure(
              new ChannelSnapshot(
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
}

export function decoder() {
  return $decode.field(
    "watershedSummaryVersion",
    $decode.int,
    (blob_version) => {
      let $ = blob_version === version;
      if ($) {
        return $decode.field(
          "sequenceNumber",
          $decode.int,
          (sequence_number) => {
            return $decode.field(
              "members",
              $decode.list($decode.int),
              (members) => {
                return $decode.field(
                  "channels",
                  $decode.list(channel_snapshot_decoder()),
                  (channels) => {
                    return $decode.success(
                      new SummaryBlob(sequence_number, members, channels),
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new SummaryBlob(0, $List$Empty$const, $List$Empty$const),
          "watershedSummaryVersion " + $int.to_string(version),
        );
      }
    },
  );
}

/**
 * Decode a blob that `encode_channels` produced. Refuse an unknown version
 * and an unknown channel type.
 */
export function decode(raw) {
  return $json.parse(raw, decoder());
}
