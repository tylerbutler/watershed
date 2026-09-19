import * as pactMap from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
import type { Option$ } from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import * as watershed from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed.mjs";
import {
  optionValue,
  resultValue,
} from "./gleam-values.ts";

declare const state: pactMap.PactMapState;
declare const setResult: ReturnType<typeof pactMap.set>;
declare const deleteResult: ReturnType<typeof pactMap.delete$>;
declare const textResult: ReturnType<typeof watershed.create_text>;
declare const option: Option$<string>;

const acceptedResult = pactMap.get_with_details(state, "datum-grid");
const pendingResult = pactMap.get_pending(state, "datum-grid");

const accepted: pactMap.Accepted$ | null = resultValue(acceptedResult);
resultValue(pendingResult);
resultValue(setResult);
resultValue(deleteResult);
const text: watershed.SharedText$ | null = resultValue(textResult);
const value: string | null = optionValue(option);

void accepted;
void text;
void value;

// @ts-expect-error PactMap reads return Result, not Option.
optionValue(acceptedResult);
// @ts-expect-error PactMap proposals return Result, not Option.
optionValue(setResult);
// @ts-expect-error PactMap deletes return Result, not Option.
optionValue(deleteResult);
