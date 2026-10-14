# SharedTree browser checklist

This Lustre app creates a native SharedTree document, opens it in the browser,
and keeps a checklist in sync across tabs. The checklist supports add, edit,
toggle, delete, move up, move down, bulk completion, local undo, and local redo.

## Run it

Start Floodgate from the repository root:

```sh
just integration-up
```

Then build and serve the app:

```sh
cd examples/shared_tree_checklist_lustre
pnpm install
pnpm run build
pnpm run serve
```

Open <http://localhost:8080>. Wait for the URL to gain a `document` parameter,
then copy the full URL into a second tab.

The local server serves the bundle and proxies Floodgate HTTP requests through
the app origin. This avoids browser CORS restrictions on document creation and
summary storage. The Phoenix socket still connects to Floodgate on port 4000.

## Schema and edits

`typed_schema.gleam` declares one
`SharedTree(typed_schema.Checklist, checklist.Checklist)`. Its builder accepts
`ChecklistInput` and `ItemInput`; reads return the application's
`checklist.Checklist` and `checklist.Item` records. The root has a required
string `title` and a required `Items` array. Each item has required `id`,
`text`, and `completed` fields.

Decoded records are snapshots. The app also keeps live `TreeNode` handles for
rendered items. Rename, toggle, delete, and move actions capture the native node
identity, so an intervening reorder does not redirect an action to the item now
at the old index. Removing an item invalidates its captured node. Inserting a
new item with the same application `id` does not make the old handle valid.
Position-based insertion still uses the current array when the effect runs.

The app owns its undo and redo stacks. It subscribes to local SharedTree
commits, retains the native revertible handles, and disposes handles when a new
edit invalidates redo or the user clears history. **Complete all** reads the
latest snapshot inside one native transaction, so every incomplete item changes
in one commit and one undo step. An all-complete checklist creates no commit.

Undo and redo are local to the current page lifetime. Remote commits update the
checklist but do not enter that page's stacks. **Close** unsubscribes, disposes
retained revertibles, closes the document, and disables editing. Closing also
invalidates tree and node handles. Reloading the same URL resolves a fresh
typed tree and captures fresh nodes; it recovers committed checklist data with
empty local history.

The app uses the fixed native container layout: alias `root`, datastore `A`,
bootstrap map `/A/root`, and SharedTree `/A/_C`.

## Development authentication

This example mints tenant and document tokens in the browser with a tenant
secret. Use it only with a local development service. A production app must
obtain its tenant-write creation token and document token from a backend.

## Browser gate

With Floodgate running:

```sh
just shared-tree-checklist
```

The gate opens two isolated Chromium contexts and checks creation,
subscriptions, every captured action after a reorder, refusal of every captured
action after same-ID replacement, bulk completion as one undo step, redo,
preservation of a peer text edit during undo, redo invalidation, history
clearing, close, and reload with empty stacks. Acceptance requires a real
Chromium-based browser; a skipped run is not acceptance.

## Limits

This example does not provide production authentication, offline authoring,
persisted undo stacks, crash recovery for pending local actions, schema
upgrades, arbitrary container layouts, or drag-and-drop reordering.
