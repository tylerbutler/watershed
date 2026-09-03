# project_room_lustre

A fixed project room that runs four components from one persisted watershed
workspace:

- Tasks sends selection to Task Inspector as a local input.
- Tasks sends completion to Activity as a collaborative input.
- Notes shares text and publishes anchored cursors through presence.
- The component runtime starts, observes, dispatches, and stops each instance.

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
both tabs show the completion and exactly one matching Activity row. Move the
caret or select text in Notes: the other tab shows the live cursor with its
presence color and name. Close a tab and its presence disappears.

## Test it

```sh
cd examples/project_room_lustre
gleam test
```

The package tests use `sluice_js`; they need no server or browser. The
repository's `project-room-smoke` recipe drives the rendered two-tab scenario
through Chromium while floodgate is running.
