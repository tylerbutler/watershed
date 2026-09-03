# project_room_lustre

A fixed project room that runs six components from one persisted watershed
workspace:

- Tasks sends selection to Task Inspector as a local input.
- Tasks sends completion to Activity as a collaborative input.
- Decision Poll stores approval ballots in an OR-set. Its first threshold
  crossing flows to Activity through a Claims latch.
- Ownership Slots resolves first-writer-wins claims. Accepted claims, releases,
  and handoffs flow to Activity.
- Notes shares text and publishes anchored cursors through presence.
- The component runtime starts, observes, dispatches, and stops each instance.

The persisted graph has four edges:

- `tasks.selected -> inspector.inspect_task`
- `tasks.completed -> activity.append_entry`
- `poll.threshold_reached -> activity.append_poll_threshold`
- `ownership.ownership_changed -> activity.append_ownership_change`

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

## Test it

```sh
cd examples/project_room_lustre
gleam test
```

The package tests use `sluice_js`; they need no server or browser. The
repository's `project-room-smoke` recipe drives the rendered two-tab scenario
through Chromium while floodgate is running.
