# Data component SDK design

**Date:** 2026-09-01

## Goal

Build a developer SDK for reusable collaborative data components. Developers
author typed headless components, add optional Lustre views, register them in a
runtime catalog, and compose instances inside one watershed document.

The first release supports code-defined workspaces with runtime-created
instances. Its storage and catalog formats must leave room for a visual builder,
but the release does not include that builder.

The project-room example proves two forms of component communication:

- local connections coordinate presentation on one client;
- collaborative connections let the originating client mutate a target
  component, then watershed replicates the result.

## Design principles

1. A component owns its collaborative data subtree.
2. The workspace shell owns document-wide behavior.
3. Component authors use typed APIs.
4. The runtime catalog validates type-erased data at its boundary.
5. Port metadata states whether a connection changes local or collaborative
   state.
6. Unsupported data remains intact and visible as an error.

## Architecture

A composed app uses one watershed document. The root contains a workspace layer
and a child map for each component instance.

The workspace layer owns three durable structures:

- an instance manifest;
- an ordered layout;
- a connection graph.

Each manifest entry contains:

- a stable instance ID;
- a stable component kind ID;
- a component format version;
- encoded component configuration;
- a handle to the instance's child map.

The layout stores instance IDs instead of component data. Views can interpret
the order as panels, tabs, columns, or another presentation.

The connection graph stores directed edges between output and input port IDs.
The graph belongs in collaborative state from the first release so every client
uses the same composition and a future builder can edit it.

Each component instance has exclusive control over its child map. It can create
plain fields, nested typed maps, and channel fields below that map. Components
must not read or mutate another instance's subtree.

The workspace shell owns:

- document connection and reconnection;
- presence and current-instance context;
- summary policy;
- offline controls and diagnostics;
- manifest, layout, and connection graph subscriptions;
- component startup and shutdown;
- port dispatch.

These rules extend the ownership model used by the existing showcase example:
panels own their channels, while the shell owns document-scoped effects.

## Catalog boundary

The catalog maps a stable component kind and version to a runtime descriptor.
The descriptor uses closures to hide the component's concrete Gleam types from
the heterogeneous catalog.

At startup, the shell performs these steps for each manifest entry:

1. Find the matching descriptor.
2. Decode and validate the configuration.
3. Resolve the instance child map.
4. Bootstrap the headless component.
5. Start its subscriptions.
6. Mount an available view adapter.

Component code stays typed on both sides of the descriptor. Type erasure occurs
only when the shell stores unrelated component definitions together or sends a
payload through the runtime connection graph.

The first release does not load code at runtime. The host application compiles
all supported component definitions and registers them during startup.

## Component package

A component package can contain three layers.

### Headless core

The headless core works without Lustre and exposes:

- metadata with stable kind and version IDs;
- a typed configuration;
- idempotent bootstrap against an instance-owned map;
- a model and lifecycle state;
- messages and subscriptions;
- typed mutation commands;
- typed output events;
- typed local and collaborative inputs;
- cleanup.

Bootstrap uses watershed's existing `ensure_*` operations. Calling bootstrap
more than once must resolve the same logical component structure after the
document settles.

A component definition answers four questions:

1. Which channels does the component own?
2. How does it resume from existing collaborative state?
3. Which commands and inputs does it accept?
4. Which events does it expose?

### Catalog adapter

The catalog adapter provides:

- configuration encoding and decoding;
- output and input port descriptors;
- payload codecs;
- erased startup, dispatch, and cleanup closures.

The adapter verifies the component kind, format version, port ID, payload schema
ID, and decoded payload before it calls typed component code.

Developers who do not need runtime composition can use the headless core
directly and omit the adapter.

### Lustre adapter

An optional Lustre adapter follows the existing nested MVU contract with
`init`, `update`, and `view`. The shell gives it a started headless instance.
The adapter does not connect to the document or create a second set of channel
subscriptions.

This split lets the same headless component run on the BEAM, in a non-Lustre
JavaScript app, or behind several Lustre views.

## Lifecycle

The shell tracks four instance states:

- `Loading`;
- `Ready`;
- `Unavailable`;
- `Failed`.

`Unavailable` means the local catalog lacks the component kind or version.
`Failed` means the shell found a descriptor but could not decode the config,
resolve the subtree, bootstrap the component, or maintain a required
subscription.

Stopping an instance releases subscriptions and view resources. It does not
delete the component's collaborative data.

Deleting data requires a separate workspace operation. The operation removes
the manifest entry, its layout references, its graph edges, and the instance
subtree according to an explicit deletion policy.

The first release supports several component versions side by side. It does not
perform automatic migrations. A host can add an explicit migration later or
keep the older adapter registered.

## Ports

Ports connect typed output events to typed inputs. They do not expose reactive
values in the first release.

Every port descriptor contains:

- a stable port ID;
- a direction;
- a stable payload schema ID;
- a payload codec;
- an input class when the port is an input.

The shell validates source and target instances, port IDs, directions, schema
IDs, and input classes before it stores an edge. It decodes the payload again
before target dispatch because persisted graph data and runtime envelopes can
be invalid.

### Local inputs

A `LocalInput` changes presentation or local controller state. Examples include
selecting, focusing, filtering, opening, and highlighting.

Local inputs cannot mutate collaborative channels.

### Collaborative inputs

A `CollaborativeInput` invokes a target-owned mutation on the client that
originated the source event. The target component writes only its own channels.
Watershed then sequences and replicates the result.

Examples include:

- task completion appending one shared activity entry;
- a poll threshold appending one shared decision entry;
- an assignment event requesting a claim on a named role.

Collaborative inputs provide the same delivery class as a direct user action.
They do not provide durable automation. If the origin client disappears before
it submits the target mutation, no server completes the reaction.

Each collaborative input declares capability metadata for the channel
mutations it can perform. A host or future builder can show the difference
between local wiring and shared-state effects before it creates a connection.

### Future automation inputs

A future `AutomationInput` can run on trusted infrastructure. It will require
durable execution records, idempotency keys, retry rules, and an authorization
model.

The first release must not describe a collaborative input as an automation
guarantee. Adding server execution later creates a new input class instead of
changing the behavior of existing connections.

## Dispatch

Only local intent emits an output event. A channel subscription that applies a
remote operation does not emit the corresponding port event. This rule prevents
each observer from repeating one target mutation.

The shell processes output events after the source update completes:

1. Assign a dispatch trace ID.
2. Encode the typed output through its registered codec.
3. Read outgoing edges from the local graph snapshot.
4. Validate and decode the payload for each target.
5. Queue each target input.
6. Run local inputs against local state.
7. Submit collaborative inputs through the target component.
8. Report target results to the originating shell.

The shell runs each edge at most once in one dispatch trace. The first release
rejects graph edits that would create a cycle. Fan-out follows the graph's
stable edge order.

Collaborative graph edits still follow watershed's convergence rules. Two
clients can briefly hold different graph snapshots during concurrent edits.
Each local action uses the origin's current graph snapshot.

## Initial component catalog

The first catalog contains five headless components.

| Component | Owned data | Output examples | Input examples |
| --- | --- | --- | --- |
| Task collection | Sequence order and OR-map task records | selected, created, completed, assignee changed | local select/filter; collaborative create/update/assign |
| Collaborative notes | Shared text, optionally keyed by subject | selection changed, mention activated | local focus subject; collaborative append section |
| Activity stream | Append-oriented sequence | entry selected | local filter; collaborative append entry |
| Decision poll | OR-set choices plus voter set or counters | vote cast, threshold reached | local show result; collaborative open/close |
| Ownership slots | Claims channel | claim attempted, claim resolved | local reveal owner; collaborative claim/release/handoff |

These components model different concurrency rules. They are not tied to one
widget. A task collection can use a kanban, table, or compact-list adapter
without changing its channels or port contract.

## Project-room reference app

The reference app creates the five component types through code and registers
these connections:

- `tasks.TaskSelected` to `notes.FocusSubject` as a local input;
- `tasks.TaskCompleted` to `activity.AppendEntry` as a collaborative input;
- `tasks.AssigneeChanged` to `ownership.ClaimRole` as a collaborative input;
- `poll.ThresholdReached` to `activity.AppendEntry` as a collaborative input.

The shell publishes presence context that identifies the component instance
each peer uses. Components receive filtered presence data from the shell. They
do not start independent document-wide presence drivers.

The same catalog can support:

- an incident room with action tasks, command roles, and a timeline;
- a planning workspace with notes, polls, and tasks;
- a lightweight CRM with task collections and activity streams per account.

## Error handling

The SDK defines separate errors for:

- catalog lookup;
- unsupported versions;
- configuration decoding;
- instance subtree resolution;
- bootstrap;
- connection validation;
- port payload decoding;
- local input handling;
- collaborative mutation submission;
- subscription loss;
- cleanup.

The shell associates each error with an instance ID, edge ID, or dispatch trace
ID. One component failure does not stop unrelated instances.

The shell keeps unknown kinds, unsupported versions, and invalid configurations
in the manifest. It renders an unavailable or failed instance and preserves its
configuration and subtree.

A collaborative dispatch reports two stages:

- `Triggered`;
- `MutationSubmitted`.

The shell reports submission failures to the originating UI. The target keeps
its previous state. The first release does not retry failed collaborative
inputs because repeating append and increment operations can duplicate their
effects. A component can expose an idempotent command when its data model
supports one.

## Testing

### Typed component tests

Each headless component test must:

- bootstrap twice;
- mutate each owned channel;
- receive local and remote subscription events;
- stop without deleting data;
- restart from existing state.

### Catalog adapter tests

Each adapter test must:

- round-trip configuration;
- round-trip every port payload;
- reject the wrong kind, version, port, and schema ID;
- preserve unsupported manifest entries.

### Workspace tests

Workspace tests must:

- add, remove, and reorder runtime instances;
- validate compatible connections;
- reject incompatible schemas and graph cycles;
- clean graph and layout references during explicit deletion;
- prove that stopping an instance preserves its subtree.

### Two-client composition tests

Two-client tests must prove:

- each component converges in isolation;
- all components converge when nested in one workspace;
- a local input changes only the origin client's controller state;
- one origin-emitted collaborative input produces one target mutation;
- remote application of that mutation does not re-emit the source event.

### Partition tests

Partition tests must distinguish accepted mutations from triggers whose target
submission failed:

- an accepted target mutation converges after reconnect;
- a failed submission reports an origin-side error;
- reconnect does not invent a target mutation that no client submitted.

### Compile-fail tests

Direct typed API tests must reject incompatible ports and commands at compile
time. Runtime graph mismatches must return connection validation or payload
decoding errors.

## Acceptance scenario

Open the same project room in two clients.

1. Client A selects a task.
2. Only client A's notes component focuses that task.
3. Client A completes the task.
4. Both clients show the completed task.
5. Both clients show exactly one new shared activity entry.
6. Neither client emits another completion event while applying the remote
   channel update.

This scenario proves local component coordination, collaborative component
communication, origin-only dispatch, and normal watershed convergence.

## Out of scope

The first release excludes:

- a visual builder;
- arbitrary formulas or reactive dataflow;
- a component marketplace;
- remote code loading;
- automatic schema migration;
- a permissions system;
- server-run automation;
- hot replacement of component code;
- a general drag-and-drop layout editor.

## Implementation sequence

The implementation plan should separate the work into these milestones:

1. workspace schemas and runtime instance lifecycle;
2. typed headless component and catalog adapter contracts;
3. local port graph and dispatch;
4. collaborative inputs and dispatch reporting;
5. initial reusable components;
6. optional Lustre adapters;
7. project-room reference app and two-client acceptance tests.
