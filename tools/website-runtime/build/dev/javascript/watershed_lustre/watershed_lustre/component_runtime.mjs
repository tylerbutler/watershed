/// <reference types="./component_runtime.d.mts" />
import * as $effect from "../../lustre/lustre/effect.mjs";
import * as $watershed from "../../watershed/watershed.mjs";
import * as $component from "../../watershed/watershed/component.mjs";
import * as $component_runtime_js from "../../watershed/watershed/component_runtime_js.mjs";
import * as $schema from "../../watershed/watershed/schema.mjs";
import * as $transport_js from "../../watershed/watershed/transport_js.mjs";
import * as $workspace from "../../watershed/watershed/workspace.mjs";
import * as $workspace_js from "../../watershed/watershed/workspace_js.mjs";
import { queue_microtask } from "../watershed_lustre_ffi.mjs";

/**
 * Ensure a workspace when Lustre performs this effect.
 */
export function ensure_workspace(document, root, field, opened) {
  return $effect.from(
    (dispatch) => {
      return $workspace_js.ensure(
        document,
        root,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(opened(result)); });
        },
      );
    },
  );
}

/**
 * Run one synchronous workspace operation during the effect phase.
 */
export function perform(operation, outcome) {
  return $effect.from(
    (dispatch) => {
      let result = operation();
      return queue_microtask(() => { return dispatch(outcome(result)); });
    },
  );
}

/**
 * Start one component runtime when Lustre performs this effect.
 */
export function start(
  document,
  root,
  field,
  store,
  catalog,
  context_for,
  started,
  changed,
  report
) {
  return $effect.from(
    (dispatch) => {
      let runtime = $component_runtime_js.start(
        document,
        root,
        field,
        store,
        catalog,
        context_for,
        $transport_js.real_scheduler(),
        () => { return queue_microtask(() => { return dispatch(changed); }); },
        (update) => {
          return queue_microtask(() => { return dispatch(report(update)); });
        },
      );
      return queue_microtask(() => { return dispatch(started(runtime)); });
    },
  );
}

/**
 * Apply one typed component action when Lustre performs this effect.
 */
export function command(runtime, instance_id, action, outcome) {
  return $effect.from(
    (dispatch) => {
      let result = $component_runtime_js.command(runtime, instance_id, action);
      return queue_microtask(() => { return dispatch(outcome(result)); });
    },
  );
}

/**
 * Stop one component runtime when Lustre performs this effect.
 */
export function stop(runtime, stopped) {
  return $effect.from(
    (dispatch) => {
      let errors = $component_runtime_js.stop(runtime);
      return queue_microtask(() => { return dispatch(stopped(errors)); });
    },
  );
}
