//// Lustre effects for the JavaScript component runtime.
////
//// The runtime remains independent of Lustre. This module starts it during an
//// effect and moves every callback to a microtask before it reaches the
//// application's update function.

import lustre/effect.{type Effect}
import watershed.{type Document, type SharedMap, type TypedMap}
import watershed/component
import watershed/component_runtime_js
import watershed/schema.{type ChildField}
import watershed/transport_js
import watershed/workspace
import watershed/workspace_js

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

/// Ensure a workspace when Lustre performs this effect.
pub fn ensure_workspace(
  document document: Document(root),
  root root: TypedMap(root),
  field field: ChildField(root, workspace.WorkspaceSchema),
  opened opened: fn(
    Result(workspace_js.Workspace(root), workspace_js.WorkspaceError),
  ) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  workspace_js.ensure(document, root, field, fn(result) {
    queue_microtask(fn() { dispatch(opened(result)) })
  })
}

/// Run one synchronous workspace operation during the effect phase.
pub fn perform(
  operation operation: fn() -> result,
  outcome outcome: fn(result) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let result = operation()
  queue_microtask(fn() { dispatch(outcome(result)) })
}

/// Start one component runtime when Lustre performs this effect.
pub fn start(
  document document: Document(root),
  root root: TypedMap(root),
  field field: ChildField(root, workspace.WorkspaceSchema),
  store store: workspace_js.Workspace(root),
  catalog catalog: component.Catalog(context, running),
  context_for context_for: fn(
    workspace.ManifestEntry,
    SharedMap,
    fn() -> Nil,
    component.OutputEmitter,
  ) -> context,
  started started: fn(component_runtime_js.Runtime(root, context, running)) ->
    msg,
  changed changed: msg,
  report report: fn(component_runtime_js.DispatchReport) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let runtime =
    component_runtime_js.start(
      document: document,
      root: root,
      field: field,
      store: store,
      catalog: catalog,
      context_for: context_for,
      scheduler: transport_js.real_scheduler(),
      on_change: fn() { queue_microtask(fn() { dispatch(changed) }) },
      on_report: fn(update) {
        queue_microtask(fn() { dispatch(report(update)) })
      },
    )
  queue_microtask(fn() { dispatch(started(runtime)) })
}

/// Apply one typed component action when Lustre performs this effect.
pub fn command(
  runtime: component_runtime_js.Runtime(root, context, running),
  instance_id: String,
  action: fn(running) -> Result(#(running, List(component.OutputEvent)), String),
  outcome outcome: fn(Result(Nil, component_runtime_js.RuntimeError)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let result = component_runtime_js.command(runtime, instance_id, action)
  queue_microtask(fn() { dispatch(outcome(result)) })
}

/// Stop one component runtime when Lustre performs this effect.
pub fn stop(
  runtime: component_runtime_js.Runtime(root, context, running),
  stopped stopped: fn(List(component.ComponentError)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let errors = component_runtime_js.stop(runtime)
  queue_microtask(fn() { dispatch(stopped(errors)) })
}
