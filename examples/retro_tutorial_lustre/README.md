# retro_tutorial_lustre

A small collaborative retro board for the watershed tutorial track. It keeps
three columns of notes in a RegisterMode OR-map, tracks tallies in a TallyMode
OR-map, and uses presence to show who is reading which note.

This example is intentionally smaller than `retro_board_lustre`. There are no
sequences, drag-and-drop interactions, edit/delete flows, cross-column moves, or
vote budgets. The whole board is meant to stay understandable as a standalone
copyable tutorial project.

## Run it

From the repository root, start the development server:

```sh
just integration-up
```

Then build and serve the example:

```sh
cd examples/retro_tutorial_lustre
pnpm install
pnpm build
pnpm serve
```

Open <http://localhost:8080> in two tabs on the same `?document=` URL. Add
notes from both tabs, vote on them, and click **Focus** to watch the presence
roster and card highlights update across clients.
