# Runtime component palette design

**Date:** 2026-09-02

## Goal

Extend the project-room example so a user can add, move, and remove component
instances while the room is running. Add Checklist and Tally component kinds
to prove that the runtime can start multiple instances of one kind and
replicate their state across clients.

The palette asks for a component kind and title. It does not edit connections
or arbitrary component configuration.

## Current behavior

`workspace_setup.seed` creates six fixed instances and four fixed connections
before the component runtime starts. The workspace API already supports
adding, moving, and deleting instances. The JavaScript runtime observes
workspace changes and reconciles its running instances.

The example does not expose those operations. Its catalog contains six kinds,
and its view selects an adapter by matching each fixed instance ID.

## Scope

This change adds:

- a project-room component palette;
- title-only runtime creation from demo-owned presets;
- move-up, move-down, and remove controls;
- Checklist and Tally component kinds;
- one seeded instance of each new kind;
- one seeded Checklist-to-Tally connection;
- two-client coverage for runtime-created instances.

This change does not add:

- runtime connection editing;
- a generic configuration form schema;
- arbitrary formulas or reactive projections;
- remote component code;
- automatic component migration;
- destructive subtree collection.

## Creation presets

The project-room catalog module defines a `CreationPreset` for each kind that
users can create. A preset contains:

- the stable kind and version;
- a label for the palette;
- a function that builds valid configuration JSON from a title;
- the initializer required by `workspace_js.add_instance_with`.

Creation presets belong to the example, not the watershed catalog API. The
catalog remains responsible for runtime lookup, configuration validation, and
startup. The palette needs one fixed input shape, so a general form-description
API would add unused builder infrastructure.

The first palette can create Checklist and Tally instances. Existing fixed
component kinds can join the preset list when they support meaningful
title-only defaults.

## Instance creation

The host generates an instance ID from the kind slug and
`watershed/id.uuid_v4`. UUID generation needs no shared allocator and makes a
cross-client collision unlikely.

The creation flow is:

1. The user chooses a kind and enters a title.
2. The host rejects a title that becomes empty after trimming whitespace.
3. A Lustre effect calls the preset's configuration function and
   `workspace_js.add_instance_with`.
4. The workspace appends the manifest entry and layout entry.
5. Each client's workspace subscription schedules runtime reconciliation.
6. Each runtime finds the descriptor, resolves the subtree, and starts the new
   instance.

The host does not start the component itself. The existing runtime
reconciliation path remains the only component lifecycle owner.

## Dynamic rendering

The workspace view continues to follow `component_runtime_js.layout`.
`instance_view` selects an adapter from the `catalog.Running` variant instead
of selecting it from the instance ID. This permits any number of Checklist and
Tally instances.

The original components retain their fixed IDs because presence and existing
host actions refer to them. Their adapters can continue to use those
host-specific paths where required.

Each runtime-created panel shows:

- its configured title;
- move-up and move-down controls;
- a remove control;
- lifecycle or operation errors associated with that instance.

Move controls call `workspace_js.move_instance`. Remove calls
`workspace_js.delete_instance`. The host disables a control while its
operation is pending.

## Checklist component

### Configuration

Checklist configuration contains one field:

```text
title: String
```

The component starts with no items. Users add runtime data after creation.

### Collaborative data

Checklist owns:

- an ordered sequence of item records;
- an OR-set of completed item IDs.

Each item record has a UUID, label, and stable encoded version. The sequence
defines display order. The OR-set gives completion add-wins behavior.

Removing an item deletes its sequence record. Concurrent completion tags can
remain in the OR-set. The effective view ignores completion IDs with no item
record, which preserves convergence without adding a cleanup protocol.

### Operations

Checklist supports:

- add item;
- rename item;
- remove item;
- complete item;
- reopen item.

Its collaborative inputs are:

- `AddItem(String)`;
- `CompleteItem(String)`.

The component emits `ItemCompleted(Int)` with payload `1` after a locally
originated completion operation succeeds. Applying a replicated completion
does not emit an output.

## Tally component

### Configuration

Tally configuration contains:

```text
title: String
target: Int
```

The title-only creation preset sets `target` to `10`.

### Collaborative data

Tally owns:

- one PN-counter;
- one Claims key that latches the first target crossing.

The PN-counter merges concurrent increments and decrements. Tally has no reset
operation. A reset would need an epoch so an old counter state could not merge
back into the reset value.

### Operations and ports

Users can increment or decrement the tally. Its collaborative input is
`Add(Int)`. The component emits `TargetReached(Int)` after its Claims latch
accepts the first crossing.

Only the client that submits the accepted latch emits `TargetReached`.
Replicated counter or Claims events update the view without emitting another
semantic event.

## Seeded composition

`workspace_setup.seed` adds one Checklist and one Tally after the existing six
instances. It also adds this connection:

```text
checklist.item_completed -> tally.add
```

Both ports use one stable integer-delta schema. The seeded Tally title is
`Completion events`.

The tally counts locally originated completion events delivered through the
graph. It does not represent the current number of completed checklist items.
Two clients can complete the same item concurrently and each origin can emit
one event while the OR-set presents one completed item. The title and nearby
copy state this event-counting behavior.

Instances created from the palette start without connections. Connection
authoring remains code-defined until a separate design specifies a visual
composition tool.

## Removal and preservation

Removing an instance uses the existing workspace deletion sequence:

1. remove layout references;
2. remove graph edges that name the instance;
3. remove the manifest entry.

Runtime reconciliation stops the instance and releases its subscriptions. The
operation unlinks the child map but does not clear its channels. Watershed has
no channel-level garbage collector, so a retained handle can still inspect the
data.

## Error handling

The palette reports:

- invalid titles before a workspace write;
- workspace mutation errors in the host error area;
- configuration, bootstrap, and subscription failures on the affected panel;
- unsupported kinds or versions as `Unavailable`.

A client with an older catalog preserves unknown manifest entries and their
subtrees. It does not remove data that it cannot run.

One failed instance does not stop the runtime or other instances. A failed
move or removal leaves the latest observed workspace state visible.

## Testing

### Component tests

Checklist tests cover:

- idempotent bootstrap and resume;
- configuration and port codecs;
- add, rename, remove, complete, and reopen operations;
- completion output from local intent;
- no output from replicated completion;
- dangling completion IDs after concurrent removal.

Tally tests cover:

- idempotent bootstrap and resume;
- configuration and integer-delta codecs;
- concurrent increment and decrement convergence;
- collaborative `Add`;
- one accepted target latch;
- no repeated output from replicated events.

### Catalog and workspace tests

Tests cover:

- registration of both descriptors and creation presets;
- validation of the seeded integer-delta edge;
- two instances of the same kind with distinct IDs and subtrees;
- move and deletion planning;
- edge removal during deletion;
- preservation of an unsupported manifest entry.

### Runtime and acceptance tests

The JavaScript runtime tests add two instances after startup and assert that
both reach `Ready`. They then move one instance, delete the other, and assert
that reconciliation updates layout and lifecycle state.

The deterministic two-client project-room test performs this scenario:

1. Client A creates a Checklist.
2. Both clients observe the manifest entry and start the instance.
3. Client A adds an item.
4. Both clients show the item.
5. Client B completes it.
6. Both clients show the completion.
7. Client A removes the instance.
8. Both runtimes stop it and remove it from effective layout.

The existing project-room acceptance scenario continues to cover the fixed
connections, local controller state, presence, governance components, and
origin-only dispatch.

## Delivery boundary

The work is complete when:

- users can add multiple Checklist and Tally instances without reconnecting;
- all connected clients start and render each new instance;
- move and removal operations converge;
- the seeded Checklist completion dispatch reaches the seeded Tally once per
  origin event;
- unknown kinds remain preserved and visible as unavailable;
- repository tests and the project-room smoke scenario pass.
