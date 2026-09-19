/// <reference types="./website_runtime_test.d.mts" />
import * as $gleeunit from "../gleeunit/gleeunit.mjs";
import { Ok, Error, toList, makeError } from "./gleam.mjs";
import * as $website_runtime from "./website_runtime.mjs";

const FILEPATH = "test/website_runtime_test.gleam";

export function main() {
  return $gleeunit.main();
}

export function starts_and_resolves_clients_test() {
  let $ = $website_runtime.start(
    "website",
    "runtime-test",
    toList(["a", "b", "c"]),
  );
  let runtime;
  if ($ instanceof Ok) {
    runtime = $[0];
  } else {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      9,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $, start: 137, end: 231, pattern_start: 148, pattern_end: 159 }
    )
  }
  $website_runtime.settle(runtime);
  let $1 = $website_runtime.client(runtime, "a");
  if (!($1 instanceof Ok)) {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      13,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $1, start: 269, end: 324, pattern_start: 280, pattern_end: 285 }
    )
  }
  let $2 = $website_runtime.client(runtime, "b");
  if (!($2 instanceof Ok)) {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      14,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $2, start: 327, end: 382, pattern_start: 338, pattern_end: 343 }
    )
  }
  let $3 = $website_runtime.client(runtime, "c");
  if (!($3 instanceof Ok)) {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      15,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $3, start: 385, end: 440, pattern_start: 396, pattern_end: 401 }
    )
  }
  let $4 = $website_runtime.client(runtime, "missing");
  if ($4 instanceof Error) {
    let $5 = $4[0];
    if (!($5 === "unknown client: missing")) {
      throw makeError(
        "let_assert",
        FILEPATH,
        "website_runtime_test",
        16,
        "starts_and_resolves_clients_test",
        "Pattern match failed, no pattern matched the value.",
        { value: $4, start: 443, end: 535, pattern_start: 454, pattern_end: 486 }
      )
    }
  } else {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      16,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $4, start: 443, end: 535, pattern_start: 454, pattern_end: 486 }
    )
  }
  let $6 = $website_runtime.pending(runtime);
  if (!(!$6)) {
    throw makeError(
      "let_assert",
      FILEPATH,
      "website_runtime_test",
      18,
      "starts_and_resolves_clients_test",
      "Pattern match failed, no pattern matched the value.",
      { value: $6, start: 538, end: 589, pattern_start: 549, pattern_end: 554 }
    )
  }
  return undefined;
}
