import {
  Error as GleamError,
  Ok,
  toList,
  type List,
  type Result,
} from "../../../../tools/website-runtime/build/dev/javascript/watershed/gleam.mjs";
import {
  None,
  Some,
  type Option$ as Option,
} from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import * as claimsKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/claims_kernel.mjs";
import * as counterKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/counter_kernel.mjs";
import * as gCounterKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/g_counter_kernel.mjs";
import * as gSetKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/g_set_kernel.mjs";
import * as handle from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/handle.mjs";
import * as jsonOt from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/json_ot.mjs";
import * as lwwMapKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/lww_map_kernel.mjs";
import * as lwwRegisterKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/lww_register_kernel.mjs";
import * as mapKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as mvKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/mv_register_kernel.mjs";
import * as orderedKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/ordered_collection_kernel.mjs";
import * as orMapKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/or_map_kernel.mjs";
import * as orSetKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/or_set_kernel.mjs";
import * as pactKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
import * as pnKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/pn_counter_kernel.mjs";
import * as registerKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/register_collection_kernel.mjs";
import * as richText from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/rich_text.mjs";
import * as runtime from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/runtime.mjs";
import * as sluice from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/sluice_js.mjs";
import * as taskManagerKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/task_manager_kernel.mjs";
import * as twoPSetKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/two_p_set_kernel.mjs";
import * as watershed from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed.mjs";
import * as websiteRuntime from "../../../../tools/website-runtime/build/dev/javascript/website_runtime/website_runtime.mjs";
import * as gdict from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/dict.mjs";
import * as gset from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/set.mjs";
import * as json from "../../../../tools/website-runtime/build/dev/javascript/gleam_json/gleam/json.mjs";
import * as gCounter from "../../../../tools/website-runtime/build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";
import * as pnLattice from "../../../../tools/website-runtime/build/dev/javascript/lattice_counters/lattice_counters/pn_counter.mjs";
import * as replicaId from "../../../../tools/website-runtime/build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as bias from "../../../../tools/website-runtime/build/dev/javascript/lattice_sequence/lattice_sequence/sequence.mjs";
import { register as textareaRegister } from "../../../../tools/website-runtime/build/dev/javascript/watershed_lustre/watershed_lustre/textarea_element.mjs";

export {
  bias,
  claimsKernel,
  counterKernel,
  gCounter,
  gCounterKernel,
  gdict,
  gSetKernel,
  gset,
  handle,
  json,
  jsonOt,
  lwwMapKernel,
  lwwRegisterKernel,
  mapKernel,
  mvKernel,
  orderedKernel,
  orMapKernel,
  orSetKernel,
  pactKernel,
  pnKernel,
  pnLattice,
  registerKernel,
  replicaId,
  richText,
  runtime,
  sluice,
  taskManagerKernel,
  textareaRegister,
  toList,
  twoPSetKernel,
  watershed,
  websiteRuntime,
};
export {
  gdict as dict,
  lwwMapKernel as lwwMap,
  mapKernel as sharedMap,
  mvKernel as mv,
  orMapKernel as orMap,
  pactKernel as pactMap,
  replicaId as replica,
};
export type { List, Option };
export type Option$<T> = Option<T>;

export type ResultValue<R> =
  R extends Result<infer T, infer _E> ? T : never;

export function isOk<T, E>(result: Result<T, E>): result is Ok<T, E> {
  return result instanceof Ok;
}

export function resultValue<T, E>(result: Result<T, E>): T | null {
  return isOk(result) ? result[0] : null;
}

export function resultError<T, E>(result: Result<T, E>): E | null {
  return result instanceof GleamError ? result[0] : null;
}

export function expectOk<T, E>(result: Result<T, E>, detail: string): T {
  if (isOk(result)) return result[0];
  const error = result instanceof GleamError ? result[0] : result;
  throw new Error(`${detail}: ${String(error)}`);
}

export function isSome<T>(option: Option<T>): option is Some<T> {
  return option instanceof Some;
}

export function optionValue<T>(option: Option<T>): T | null {
  return isSome(option) ? option[0] : null;
}

export function some<T>(value: T): Option<T> {
  return new Some(value);
}

export function none<T>(): Option<T> {
  return new None();
}
