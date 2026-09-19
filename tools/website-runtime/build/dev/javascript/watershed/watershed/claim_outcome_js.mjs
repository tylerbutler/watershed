/// <reference types="./claim_outcome_js.d.mts" />
import * as $promise from "../../gleam_javascript/gleam/javascript/promise.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $claims_kernel from "../watershed/claims_kernel.mjs";
import * as $runtime from "../watershed/runtime.mjs";

/**
 * Observe the outcome of one claim submission.
 *
 * Pending replies resolve from their promise. Immediate replies call
 * `resolved` before this function returns.
 */
export function observe(reply, resolved) {
  if (reply instanceof $runtime.Pending) {
    let outcome = reply.outcome;
    let $ = $promise.map(outcome, resolved);
    
    return undefined;
  } else if (reply instanceof $runtime.AlreadyClaimed) {
    let current_value = reply.current_value;
    return resolved(new $claims_kernel.Lost(new Some(current_value)));
  } else if (reply instanceof $runtime.AlreadyPendingLocally) {
    return resolved($claims_kernel.ClaimOutcome$Aborted$const);
  } else {
    return resolved($claims_kernel.ClaimOutcome$Aborted$const);
  }
}
