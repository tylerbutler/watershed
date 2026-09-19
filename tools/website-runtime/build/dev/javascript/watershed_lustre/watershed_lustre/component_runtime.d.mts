import type * as $effect from "../../lustre/lustre/effect.d.mts";
import type * as $watershed from "../../watershed/watershed.d.mts";
import type * as $component from "../../watershed/watershed/component.d.mts";
import type * as $component_runtime_js from "../../watershed/watershed/component_runtime_js.d.mts";
import type * as $schema from "../../watershed/watershed/schema.d.mts";
import type * as $workspace from "../../watershed/watershed/workspace.d.mts";
import type * as $workspace_js from "../../watershed/watershed/workspace_js.d.mts";
import type * as _ from "../gleam.d.mts";

export function ensure_workspace<CCGQ, CCGY>(
  document: $watershed.Document$<CCGQ>,
  root: $watershed.TypedMap$<CCGQ>,
  field: $schema.ChildField$<CCGQ, $workspace.WorkspaceSchema$>,
  opened: (
    x0: _.Result<$workspace_js.Workspace$<CCGQ>, $workspace_js.WorkspaceError$>
  ) => CCGY
): $effect.Effect$<CCGY>;

export function perform<CCHA, CCHB>(
  operation: () => CCHA,
  outcome: (x0: CCHA) => CCHB
): $effect.Effect$<CCHB>;

export function start<CCHD, CCHJ, CCHK, CCHQ>(
  document: $watershed.Document$<CCHD>,
  root: $watershed.TypedMap$<CCHD>,
  field: $schema.ChildField$<CCHD, $workspace.WorkspaceSchema$>,
  store: $workspace_js.Workspace$<CCHD>,
  catalog: $component.Catalog$<CCHJ, CCHK>,
  context_for: (
    x0: $workspace.ManifestEntry$,
    x1: $watershed.SharedMap$,
    x2: () => undefined,
    x3: $component.OutputEmitter$
  ) => CCHJ,
  started: (x0: $component_runtime_js.Runtime$<CCHD, CCHJ, CCHK>) => CCHQ,
  changed: CCHQ,
  report: (x0: $component_runtime_js.DispatchReport$) => CCHQ
): $effect.Effect$<CCHQ>;

export function command<CCHU, CCID>(
  runtime: $component_runtime_js.Runtime$<any, any, CCHU>,
  instance_id: string,
  action: (x0: CCHU) => _.Result<
    [CCHU, _.List<$component.OutputEvent$>],
    string
  >,
  outcome: (x0: _.Result<undefined, $component_runtime_js.RuntimeError$>) => CCID
): $effect.Effect$<CCID>;

export function stop<CCIM>(
  runtime: $component_runtime_js.Runtime$<any, any, any>,
  stopped: (x0: _.List<$component.ComponentError$>) => CCIM
): $effect.Effect$<CCIM>;
