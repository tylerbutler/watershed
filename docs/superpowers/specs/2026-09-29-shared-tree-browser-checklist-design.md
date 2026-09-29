# SharedTree Browser Checklist Design

## Goal

Build a local-development Lustre application that creates a native SharedTree
container in the browser and demonstrates collaborative checklist editing in two
tabs. The work pulls forward a small, reusable part of M7: SharedTree effects
for Lustre applications.

## Scope

The first demo supports:

- native SharedTree container creation from the browser;
- opening the created document from its URL;
- two independent browser contexts connected through Floodgate;
- adding, editing, completing, deleting, and reordering checklist items;
- visible connection, synchronization, and mutation errors; and
- a real-browser convergence gate.

The demo uses browser-minted development tokens and the fixed container layout
that native SharedTree creation already supports. It is a local development
example. It is not a production authentication pattern.

The first demo does not include drag-and-drop, offline authoring, schema
upgrades, arbitrary container layouts, production token issuance, or new
summary policies.

## Architecture

### Lustre adapter

Add `watershed_lustre/tree.gleam` as a JavaScript-only effect adapter over the
public `watershed` SharedTree facade. The adapter owns callback scheduling and
delivers each callback through a microtask, matching the existing
`watershed_lustre` bindings.

The adapter exposes effects for:

- creating a native tree container;
- resolving the fixed-layout SharedTree after the existing Lustre connection
  effect reports readiness;
- subscribing to tree events;
- refreshing the application snapshot; and
- running set, clear, array insert, array remove, and array move operations.

The adapter remains schema-neutral. Applications supply `StoredSchema`,
`ViewSchema`, and `TreeValue` values from `watershed/tree/schema` and
`watershed/tree/types`. The adapter does not introduce typed path generation,
schema builders, migrations, or schema-upgrade effects.

### Demo package

Add `examples/shared_tree_checklist_lustre/` as a standalone Lustre package. It
follows the existing browser-example structure:

- `gleam.toml` declares the JavaScript target and local Watershed packages;
- `package.json` builds an ES module bundle with esbuild;
- `index.html` hosts the application;
- `src/shared_tree_checklist_lustre.gleam` owns the Lustre model, update, and
  view;
- `src/shared_tree_checklist_lustre_ffi.mjs` reads optional query parameters
  and replaces the current URL after native creation;
- `src/shared_tree_checklist_lustre/schema.gleam` owns the stored/view schema
  and initial tree;
- `src/shared_tree_checklist_lustre/checklist.gleam` decodes snapshots and
  calculates mutations by stable item ID;
- `test/` covers schema and checklist logic; and
- `smoke/browser.mjs` drives the two-tab browser scenario.

The repository's Trellis discovery includes the package in `just build` and
`just test`. Add a dedicated `just shared-tree-checklist` recipe for the live
Floodgate and Chromium gate.

## Stored Schema

The document root is a required `shared_tree_checklist.Checklist` object:

```text
Checklist
├── title: required string
└── items: required ChecklistItems array
    └── ChecklistItem
        ├── id: required string
        ├── text: required string
        └── completed: required boolean
```

The initial tree uses the title `SharedTree checklist` and an empty array.

Each item receives an application ID before insertion. The ID remains part of
the item object through edits and moves. UI actions carry the ID rather than a
rendered array index.

## Public Adapter Interfaces

The adapter uses the existing public facade types. It adds these Lustre effect
functions:

```gleam
pub fn create(
  config: container.CreateConfig,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
) -> Effect(msg)

pub fn create_dev(
  base_url: String,
  tenant: String,
  secret: String,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
) -> Effect(msg)

pub fn open(
  document: watershed.Document(root),
  view: tree_schema.ViewSchema,
  opened: fn(Result(watershed.SharedTree, String)) -> msg,
) -> Effect(msg)

pub fn subscribe(
  tree: watershed.SharedTree,
  subscribed: fn(watershed.SubscriptionToken) -> msg,
  changed: fn(tree_kernel.TreeEvent) -> msg,
) -> Effect(msg)

pub fn unsubscribe(
  subscription: watershed.SubscriptionToken,
) -> Effect(msg)

pub fn read_root(
  tree: watershed.SharedTree,
  read: fn(Result(Option(tree_types.TreeValue), String)) -> msg,
) -> Effect(msg)

pub fn perform(
  operation: fn() -> Result(Nil, String),
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg)
```

The application reuses `watershed_lustre.connect_dev` for its local-development
connection. After readiness, `open` resolves the bootstrap root, reads its
`"tree"` handle, and calls `watershed.resolve_tree` with the supplied view
schema.

`create_dev` mints a tenant-write development token with an empty document ID,
then delegates to `create`. Production applications call `create` with a token
issued by their backend.

`create`, `create_dev`, `open`, `subscribe`, `read_root`, and `perform` defer
their results. A mutation does not dispatch a success message from inside the
Lustre update call stack.

The adapter returns the existing facade errors as strings. It does not replace
specific failures with generic messages.

## Application Flow

### First load

The application reads these query parameters:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `document` | absent | Existing document ID. |
| `host` | `127.0.0.1` | Floodgate host. |
| `port` | `4000` | Floodgate HTTP and Phoenix port. |
| `tenant` | `dev-tenant` | Development tenant. |
| `secret` | `levee-dev-secret-change-in-production` | Development JWT signing secret. |

When `document` is absent:

1. Call the adapter's `create_dev` effect with the checklist schema and initial
   root. The effect mints a tenant-write development token with an empty
   document ID.
3. Call the example's browser FFI to replace the current URL with the returned
   document ID while preserving the other query parameters.
4. Mint a document token for that ID.
5. Connect and resolve the SharedTree.

The application does not retry creation after an uncertain HTTP result. It
shows the error and tells the user that the service might have created a
document whose ID the browser did not receive.

### Existing document

When `document` is present:

1. Call `watershed_lustre.connect_dev`, which mints a development token scoped
   to the document and connects to Floodgate.
2. After readiness, call the tree adapter's `open` effect to resolve `root`,
   read its `"tree"` handle, and open the SharedTree with the checklist view
   schema.
3. Subscribe to `TreeChanged` and `SchemaChanged`.
4. Read and decode the complete root value.

The application treats `SchemaChanged` as a refresh trigger even though the
demo does not author schema upgrades. An incompatible schema produces the
facade's explicit resolution or compatibility error.

### Mutations

The application implements these actions:

| Action | SharedTree operation |
| --- | --- |
| Add item | `tree_array_insert` at the current array length. |
| Edit text | `tree_set` at `["items", int.to_string(index), "text"]`. |
| Toggle completion | `tree_set` at `["items", int.to_string(index), "completed"]`. |
| Delete item | `tree_array_remove` for `[index, index + 1)`. |
| Move up/down | `tree_array_move` for the item range and destination gap. |

Before each index-based mutation, `checklist.gleam` finds the item ID in the
latest decoded snapshot. If the item no longer exists, the operation returns a
visible stale-action error and performs no SharedTree mutation.

After any mutation result, the application reads the current root. Tree events
also trigger a read. The model uses the latest successful read, so local and
remote events follow one rendering path.

## Model and Error States

The application model uses these phases:

```gleam
pub type Phase {
  Creating
  Connecting
  Ready
  Failed(String)
}
```

The model stores the document ID, optional document and tree handles, decoded
checklist, optional subscription token, pending mutation count, and a list of
visible errors.

The UI disables mutations until the phase is `Ready`. It keeps the last
successfully decoded checklist visible during reconnect or mutation failure.
It reports:

- creation uncertainty;
- connection and tree-resolution failures;
- schema or snapshot decode failures;
- stale item actions;
- invalid SharedTree operations; and
- synchronization status from the document.

The demo must not assert on user-triggered or transport-dependent failures.

## Testing

### Adapter tests

Add JavaScript-target tests in `watershed_lustre/test/watershed_lustre/tree_test.gleam`.
Use injected operations and callbacks to prove:

- `perform` does not dispatch during the caller's update stack;
- `perform` delivers one success or failure message;
- the shared callback-delivery helper dispatches one message; and
- `unsubscribe` defers the existing `watershed.unsubscribe` call.

Connection and creation remain covered by Watershed's SharedTree creation,
bootstrap, subscription, and facade tests. The adapter tests cover effect
scheduling rather than duplicating the transport suite.

### Application logic tests

Add JavaScript-target tests for:

- stored schema acceptance of the initial checklist;
- snapshot decoding with multiple items;
- rejection of malformed item objects;
- stable-ID lookup after reordering;
- add, edit, toggle, delete, move-up, and move-down operation preparation;
- boundary moves that perform no mutation; and
- stale actions whose item ID is absent.

Keep mutation preparation pure. Tests assert the exact path, range, value, and
destination gap that the application submits.

### Browser smoke

`examples/shared_tree_checklist_lustre/smoke/browser.mjs` uses the repository's
CDP helpers and a local Floodgate process. It must:

1. Build and serve the application.
2. Open the first browser context without a document ID.
3. Wait for browser-native creation and capture the resulting URL.
4. Open the URL in a second isolated browser context.
5. Add an item in the first context and observe it in the second.
6. Edit and toggle the item in the second context and observe both changes in
   the first.
7. Add two more items.
8. Race a reorder in one context with a text edit in the other.
9. Require both contexts to converge on the same IDs, order, text, and
   completion values.
10. Delete one item and require both contexts to converge again.

The script fails when Floodgate, creation, a browser context, or an expected
observation is missing. It follows the repository convention and exits with an
explicit skip only when no Chromium browser is available.

## Documentation

The example README explains:

- how to start the pinned local Floodgate service;
- how to build and serve the application;
- how to open a second tab with the generated document URL;
- which SharedTree subset the demo exercises;
- why stable item IDs protect actions from stale indexes;
- that the browser contains a development tenant secret; and
- that a production deployment needs a server-issued tenant-write token and
  document-scoped tokens.

Update the root README's SharedTree creation section to link to both the CLI
example and the browser checklist.

Update the parent SharedTree roadmap to record this browser demo and thin
Lustre adapter as another pulled-forward M7 slice. Do not mark the remaining
M7 work complete.

## Acceptance

The work is complete when:

- `just build` builds the adapter and demo bundle;
- `just test` runs the adapter and pure application tests;
- `just shared-tree-test` retains its existing results;
- `just shared-tree-checklist` passes the real-browser two-context scenario;
- the browser creates a native SharedTree without a Fluid SDK seed;
- both contexts converge after every required operation and the edit/reorder
  race;
- no production module depends on the Fluid npm SDK or oracle code;
- the demo labels browser token minting as development-only; and
- the roadmap records only the completed M7 slice.

## Deferred Work

This design leaves these capabilities for later M7 or later milestones:

- production token-service integration;
- generated typed schema and path APIs;
- arbitrary container layouts and live channel attachment;
- Fluid handles in tree values;
- schema-upgrade UI;
- offline authoring and disk recovery of pending edits;
- drag-and-drop interaction;
- automatic or incremental summary policy changes; and
- deployable hosting configuration.
