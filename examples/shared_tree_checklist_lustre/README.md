# SharedTree browser checklist

This Lustre app creates a native SharedTree document, opens it in the browser,
and keeps a checklist in sync across tabs. The checklist supports add, edit,
toggle, delete, move up, and move down.

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

The root is a `shared_tree_checklist.Checklist` object with a string `title`
and a `shared_tree_checklist.Items` array. Each
`shared_tree_checklist.Item` has a required string `id`, string `text`, and
boolean `completed` field.

UI actions carry the stable item ID. The app resolves that ID against the
latest SharedTree snapshot before it prepares an array or field edit. A stale
rendered index cannot target a different item after a concurrent reorder.

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
subscriptions, every checklist operation, and an edit/reorder race. It skips
only when it cannot find a Chromium-based browser.

## Limits

This example does not provide production authentication, offline authoring,
schema upgrades, arbitrary container layouts, or drag-and-drop reordering.
