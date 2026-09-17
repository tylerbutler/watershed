import * as pactMap from "../../../../build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
import type { Option$ as LustreOption } from "../../../../watershed_lustre/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import * as lustreWatershed from "../../../../watershed_lustre/build/dev/javascript/watershed/watershed.mjs";
import {
  optionValue,
  resultValue,
} from "./gleam-values.ts";

declare const state: pactMap.PactMapState;
declare const setResult: ReturnType<typeof pactMap.set>;
declare const deleteResult: ReturnType<typeof pactMap.delete$>;
declare const lustreResult: ReturnType<typeof lustreWatershed.create_text>;
declare const lustreOption: LustreOption<string>;

const acceptedResult = pactMap.get_with_details(state, "datum-grid");
const pendingResult = pactMap.get_pending(state, "datum-grid");

const accepted: pactMap.Accepted$ | null = resultValue(acceptedResult);
resultValue(pendingResult);
resultValue(setResult);
resultValue(deleteResult);
const lustreText: lustreWatershed.SharedText$ | null =
  resultValue(lustreResult);
const lustreValue: string | null = optionValue(lustreOption);

void accepted;
void lustreText;
void lustreValue;

// @ts-expect-error PactMap reads return Result, not Option.
optionValue(acceptedResult);
// @ts-expect-error PactMap proposals return Result, not Option.
optionValue(setResult);
// @ts-expect-error PactMap deletes return Result, not Option.
optionValue(deleteResult);
