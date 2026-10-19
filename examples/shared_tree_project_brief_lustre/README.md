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
visible peers and cancels local composition without writing its unfinished
text. Reconnect keeps the initialized driver but only displays freshly observed
remote announcements, while retaining invalidated-selection watermarks.

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
The independently authored Fluid counterpart lives under `fluid/`. The two apps
use separate local services and cannot open each other's document URLs.

## Run the Fluid counterpart

Install and build from this example's `fluid/` directory:

```sh
cd fluid
pnpm install
pnpm build
```

In one terminal, run the Fluid local development service on port 7070:

```sh
pnpm service
```

In another terminal, from the same `fluid/` directory, start the static app:

```sh
pnpm serve
```

Open <http://127.0.0.1:8081>. Wait for `?document=...` in the URL, then copy the
full URL to another tab; add `&name=Sam` for a different display name. The service
must remain running. The static server does not start it. This reuses the
existing example server with the Fluid app's root and port, not a second proxy.
The browser connects directly to `http://localhost:7070` through AzureClient
in local mode with compatibility mode `"2.0.0"`.

This is the same compact brief, owner, schedule, milestone, and optional review
form. Native inputs publish whole-property assignments, preserve caret ranges,
and publish completed IME composition once. Rows and captured-node edits stay
with a milestone, not its old array index. Invalid milestone IDs disable the
form instead of rendering ambiguous rows. Disconnect disables edits and cancels
composition; Close disposes the view, container, and selection adapter. Neither
closing nor typing confirms that pending edits reached the service.

Field selection uses the **experimental** exported `Signaler` from
`@fluid-experimental/data-objects` 3.1.0 alongside SharedTree. It is advisory,
supports multiple names per field, and sends no durable tree edits. Heartbeats
run every two seconds with a 6.5-second expiry window. Reconnect starts with
empty remote badges while keeping invalidated-selection token watermarks.
Review replacement invalidates selections on the captured old object even
when no observer saw an intermediate absence.

Fluid uses `InsecureTokenProvider` with development-only local credentials.
Do not deploy these credentials or this authentication flow. A failed or
uncertain create/attach is shown as an error and never automatically retried.
Loaded documents are not initialized again or silently schema-upgraded.

## Checks

```sh
pnpm test
pnpm build
```

The suite covers schema reads, captured-node edits, selection policy, and the
local input/composition policy without a server. App-level runtime regressions
also check driver startup, fresh reconnect awareness and expiry, composition
cleanup and rendered value bindings, and review replacement between captures.
Run `pnpm test` for both suites. Repository `just build` and `just test`
discover the Gleam package through Trellis; no manual workspace list is needed.
Real Chromium/two-service acceptance is not implied by these checks.

For the Fluid schema, edits, input policy, selection, and lifecycle checks:

```sh
cd fluid
pnpm test
pnpm check
pnpm build
```

These tests use real in-memory Fluid trees; connection and signal delivery are
test doubles. They do not replace the separate Chromium/two-service browser gate.
