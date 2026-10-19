# SharedTree project brief

A live nested-object form in Gleam and Lustre, backed by watershed SharedTree.
Owner and schedule fields are properties of existing objects. Milestones live
in the schedule's only array; their immutable UUIDs keep rows and field-selection
badges attached to the right item when another item disappears.

## Run

From the repository root, start the local development service:

```sh
just integration-up
```

Then build and serve the watershed app:

```sh
cd examples/shared_tree_project_brief_lustre
pnpm install
pnpm build
pnpm serve
```

Open <http://127.0.0.1:8080>. Wait for the URL to include `document`, then copy
the full URL into another tab. Use `&name=Sam` to change a tab's visible name.
Type directly into the form; there is no save step. Add or remove milestones
and the optional review from either tab. Dates and email are ordinary text,
so intermediate edits remain valid input.

Each edit assigns a complete string property. Different fields can change
independently; simultaneous typing in one field is **not character-level
merging**. A remote resolved value appears in the field even while it is
focused. Native UTF-16 selection ranges are retained and clamped to that value.
During IME composition only the composing input stays under browser control;
the completed composition publishes once.

Field selection is advisory, not a lock. Names beside fields identify all
remote selectors, including checkbox selectors. Awareness uses the existing
Ripple presence driver, with its two-second heartbeat and 6.5-second expiry
window; it never changes the durable tree. A late joiner sees existing
selections on a heartbeat. Disconnect disables durable edits and clears
visible peers; reconnect rebuilds awareness with a fresh driver while retaining
invalidated-selection watermarks.

**Close** stops presence, unsubscribes, and closes the document. Reload to
reopen its URL. Closing does not confirm that pending edits reached the
service. Reload after another tab receives an edit to check delivered content.
Errors remain visible. Creation is never retried automatically: a lost response
can leave a document whose ID was not received.

The host reuses `startChecklistServer` and its HTTP proxy. HTTP configuration
uses the existing `base`, `tenant`, and `secret` query parameters; the Phoenix
WebSocket connects to Floodgate on port 4000.

## Development authentication only

The browser mints local development tokens using a tenant secret. Do not deploy
this authentication flow; production tokens must come from a backend. This
app shares URLs with other watershed instances, not with Fluid documents.
The independently authored Fluid counterpart lives under `fluid/`; its runnable
UI and the real two-client browser gate are separate tasks.

## Checks

```sh
gleam test --target javascript
pnpm build
```

The suite covers schema reads, captured-node edits, selection policy, and the
local input/composition policy without a server. Repository `just build` and
`just test` discover this package through Trellis; no manual workspace list is
needed. Real Chromium/two-service acceptance is not implied by these checks.
