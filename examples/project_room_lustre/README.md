# project_room_lustre

A project room that starts nine seeded components from one persisted watershed
workspace:

- Tasks sends selection to Task Inspector as a local input and completion to
  Activity as a collaborative input.
- Task Inspector keeps each client's selected task local.
- Decision Poll stores approval ballots in an OR-set. Its first threshold
  crossing flows to Activity through a Claims latch.
- Ownership Slots resolves first-writer-wins claims. Accepted claims, releases,
  and handoffs flow to Activity.
- Notes shares text and publishes anchored cursors through presence.
- Activity records the collaborative events routed to it.
- Checklist keeps ordered items and shared completion state.
- Tally merges increments and decrements from every client.
- Room Agreement proposes shared text through a PactMap. The proposing client
  routes an accepted agreement to Activity once.

The persisted graph has six edges:

- `tasks.selected -> inspector.inspect_task`
- `tasks.completed -> activity.append_entry`
- `poll.threshold_reached -> activity.append_poll_threshold`
- `ownership.ownership_changed -> activity.append_ownership_change`
- `checklist.item_completed -> tally.add`
- `agreement.component_event -> activity.append_component_event`

The component palette asks only for a title, then creates a Checklist, Tally,
or Room Agreement from its catalog preset. New instances join the shared layout
and start on all connected clients. They begin without graph connections, so
seeded routes do not include runtime-created components.

Move controls update the shared layout for every client. Remove takes an
instance out of the layout, graph, and manifest without destroying its detached
child map.

## Run it

```sh
just integration-up
pnpm --dir examples/project_room_lustre install
pnpm --dir examples/project_room_lustre run build
pnpm --dir examples/project_room_lustre run serve
```

Open `http://localhost:8080` in two tabs with the same URL. Select a different
task in each tab. Each Task Inspector keeps its own selection, while colored
presence markers show which task the other tab is viewing. Complete a task:
both tabs show the completion and exactly one matching Activity row.

Approve Customer research in both tabs. The ballots converge at two approvals,
the threshold latches once, and Activity gets one poll entry. Show results in
one tab to confirm that result visibility stays local.

Claim Facilitator in the first tab, then hand it to the second tab's presence
identity. Both tabs converge on the new owner and Activity records each
accepted ownership change. Reveal owner details in one tab to confirm that the
durable identity and last local outcome stay local.

Move the caret or select text in Notes: the other tab shows the live cursor
with its presence color and name. Close a tab and its presence disappears.

Write a proposal in Room Agreement and select Propose. The PactMap protocol
handles signoffs; both tabs show the accepted text and one Activity entry.
Each tab keeps its draft local. Reloading a tab restores the accepted agreement
without replaying its event.

## Add a component

Follow the [runtime contracts](../../docs/component-runtime-contracts.md) and
use Room Agreement as an example of the application integration:

1. Implement the headless lifecycle and domain commands. Bootstrap must reopen
   existing data; stop must release subscriptions. Keep local drafts separate
   from collaborative state.
2. Add a `Running` variant, a typed projection, and a descriptor in
   `catalog.descriptors()`. Its start adapter forwards only the context values
   the headless starter consumes. Give input and stop adapters explicit
   wrong-variant errors.
3. Define typed ports beside their shared codec. Room Agreement emits
   `component_event.emitted()` and has no input ports. Activity already accepts
   that payload through `component_event.append()`.
4. Add a creation preset and, if the room needs a seeded instance, an idempotent
   seed entry and graph edge. Preserve stored IDs and existing data.
5. Add instance-ID messages and effect-performed actions in the shell. Room
   Agreement marks an adapter flag on invalidation and clears it inside the
   refresh action, before calling the headless function. Refreshing from a view
   or on every host notification would create repeated work.
6. Add the view and route its events to that instance ID. The shell owns UI
   selection; registering the descriptor does not mount a view.
7. Add deterministic two-client coverage for convergence, origin-only events,
   independent drafts, removal, and reopening. Include an idle settle check
   for a component that schedules refresh commands.

The Room Agreement integration touched five production files: catalog,
workspace setup, shell, views, and a headless config getter. Before the catalog
refactor, adding its variant required changing 29 exhaustive negative matches.
The refactor removed those lists and changed 21 input/stop matches to use typed
projections. Registration now folds over the descriptor list: one registration
call instead of nine. Each of the nine projections matches its own variant,
so another kind needs no edits to unrelated handlers' negative cases. These
counts measure code coupling, not development time.

## Test it

```sh
cd examples/project_room_lustre
gleam test
```

The package tests use `sluice_js`; they need no server or browser. The
repository's `project-room-smoke` recipe drives the rendered two-tab scenario
through Chromium while floodgate is running.
