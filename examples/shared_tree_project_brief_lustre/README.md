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
The watershed review subtree has an identity-lifetime key: it changes when the
captured review reference is detached, not when its immutable content changes.
Replacement removes the native controls as well as their composition and focus.

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
The harness unit checks cover overwritten concurrent edits and stalled or late
probes. Canceled composition remains canceled across reconnect: a late end and
its final input cannot write. Fresh focus, keyboard/pointer interaction, or a
new composition permits editing again.
Run `pnpm test` for both suites. Repository `just build` and `just test`
discover the Gleam package through Trellis; no manual workspace list is needed.
These checks alone do not imply real Chromium/two-service acceptance.

For the Fluid schema, edits, input policy, selection, and lifecycle checks:

```sh
cd fluid
pnpm test
pnpm check
pnpm build
```

These tests use real in-memory Fluid trees; connection and signal delivery are
test doubles. They do not replace the separate Chromium/two-service browser gate.

With Chromium set as described below, run the focused native-DOM regressions
without either service:

```sh
pnpm --dir examples/shared_tree_project_brief_lustre test:dom
```

This mounts the actual Lustre app against its in-memory runtime and tests review
replacement without an absent render, detached composition events, and stable
controls on ordinary edits. It also mounts the React input to check identity
cancellation, late composition after reconnect, and fresh keyboard editing.

## Two-client browser acceptance

Keep Floodgate on port 4000 (`just integration-up` from the repository root)
and the Fluid local service on port 7070 running:

```sh
corepack pnpm --dir examples/shared_tree_project_brief_lustre/fluid service
```

Reuse already-running services; do not stop someone else's process. Dependencies
must already be installed in the repository and both example packages. Chromium
is required: a missing browser or service fails the gate, never skips it. If
`smoke/cdp.mjs` cannot find your existing Chromium, set its executable explicitly.
For example, with a Playwright browser already installed on macOS:

```sh
export WATERSHED_CHROME="$HOME/Library/Caches/ms-playwright/chromium-1248/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
```

From the repository root:

```sh
# The example-root test includes both pure Gleam and Node app-runtime cases.
corepack pnpm --dir examples/shared_tree_project_brief_lustre test
corepack pnpm --dir examples/shared_tree_project_brief_lustre/fluid test
corepack pnpm --dir examples/shared_tree_project_brief_lustre/fluid check

# Build each app, then run the same real two-client scenarios against each SDK.
just shared-tree-project-brief-comparison

# Or build/run just one implementation.
just shared-tree-project-brief
just shared-tree-project-brief-fluid

# After building both, the harness defaults to both implementations.
node examples/shared_tree_project_brief_lustre/smoke/browser.mjs
```

The harness serves watershed on 8080 and the Fluid directory on 8081. It uses
two isolated Chromium contexts per implementation, actual native typing and
input selections, and real Ripple/Signaler traffic. The checks cover live
on-form updates without blur, advisory same-field contention, DOM identity and
caret preservation, deterministic composition events and duplicate suppression,
optional-review replacement, stable milestone identities, heartbeat/expiry,
disconnect during composition, reconnect, service-backed reload after both
sessions close, and inert Close behavior. Delivery waits are condition-based;
expiry must occur within 8.5 seconds of the last received selection.
Concurrent submissions are checked separately from winner-independent
convergence; neither local string must survive long enough for a snapshot.
Each CDP command and diagnostic has a five-second bound inside the existing
condition deadline. Late results fail, and failures name the active phase.
The native partition records socket creation, close requests, close events, and
ready states. It waits for real socket closure before applying network-offline
mode, and closes native reconnect attempts until recovery. No SDK connection
events or presence messages are fabricated.

Only the composing input is exempt from remote value reconciliation until
composition ends. Composition events are dispatched deterministically; this is
not a test of an operating system's IME candidate window. String edits remain
whole-property assignments, not character-level merges. Selection is advisory
and never saved. Each app shares its URL only with the same implementation:
this gate makes no cross-SDK interoperability claim.

The gate records page errors and unhandled rejections and fails on visible app
errors. It removes its own contexts, browser, profile and static servers even
on failure; it never stops the Floodgate or Fluid service. Credentials are
development-only, and Fluid's exported Signaler remains experimental.
