/// <reference types="./aquamarine.d.mts" />
import * as $json from "../gleam_json/gleam/json.mjs";
import * as $channel from "./aquamarine/channel.mjs";
import * as $codec from "./aquamarine/codec.mjs";
import * as $error from "./aquamarine/error.mjs";

/**
 * Re-export of [`channel.receive`](aquamarine/channel.html#receive).
 */
export function receive(channel) {
  return $channel.receive(channel);
}
