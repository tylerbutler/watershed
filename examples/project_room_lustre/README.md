# project_room_lustre

A fixed project room that runs three components from one persisted watershed
workspace:

- Tasks sends selection to Notes as a local input.
- Tasks sends completion to Activity as a collaborative input.
- The component runtime starts, observes, dispatches, and stops each instance.

## Run it

```sh
just integration-up
pnpm --dir examples/project_room_lustre install
pnpm --dir examples/project_room_lustre run build
pnpm --dir examples/project_room_lustre run serve
```

Open `http://localhost:8080` in two tabs with the same URL. Select a task in one
tab: only that tab changes the Notes context. Complete it: both tabs show the
completion and exactly one matching Activity row.

## Test it

```sh
cd examples/project_room_lustre
gleam test
```

The package tests use `sluice_js`; they need no server or browser. The
repository's `project-room-smoke` recipe drives the rendered two-tab scenario
through Chromium while floodgate is running.
