# Field notes — the demo annotation system

"Field notes" is the opt-in annotation layer on the live DDS demos. Switch it
on and the demo calls out the trip an operation takes: a local edit appears in
magenta, the sluice stamps it, and the replicas settle into ink.

The implementation is native Lustre now. There is no shared DOM-diffing module
to register with and no Astro component to patch:

- `website_lustre/src/watershed_site/structure_demo/model.gleam` owns the shared
  demo state.
- `website_lustre/src/watershed_site/structure_demo/runtime.gleam` owns edits,
  sequencing, delivery, and the field-notes toggle.
- `website_lustre/src/watershed_site/structure_demo/view.gleam` renders the
  annotation copy and the pending or sequenced state already present in the
  model.
- `website_lustre/src/watershed_site/sequence/runtime.gleam` and
  `website_lustre/src/watershed_site/sequence/view.gleam` own the sequence
  demo's timed station and log annotations.

The browser entry points under `website_lustre/src/watershed_site/client/`
mount those Lustre apps. Keep behavior in the typed runtime and view modules;
the entry points should stay thin.

## The central idea

Field notes should feel like an inspector marking up a precise printed survey
sheet—not like another layer of application chrome. Use them to expose the
merge rule at the moment it matters. If the ordinary pending and sequenced
states already tell the story, a short caption is enough.

## Color grammar

The annotations use the same two-color language as the live values:

| Token | Meaning | Use for |
| --- | --- | --- |
| `--ink` | sequenced, converged fact | state the replicas have accepted |
| `--overprint` | pending, optimistic fact | a local edit the sluice has not stamped |

Pending work is magenta. Sequenced work is ink. Reuse the existing state
classes and tokens; do not hardcode colors or invent a third status.

## Shared structure demos

The shared structure rig carries `field_notes` in its `Model`.
`runtime.SetFieldNotes` changes that value, and
`structure_demo/view.gleam` renders the `field-notes-on` class and the
"Local edit → sequencer → replicas" note.

When you add another structure to this rig:

1. Put its state and operations in `structure_demo/model.gleam`.
2. Handle local edits, sequencing, and delivery in
   `structure_demo/runtime.gleam`.
3. Render values from the typed model in `structure_demo/view.gleam`.
4. Reuse the existing pending and sequenced classes so field notes describe
   real runtime state rather than a second DOM-only state machine.

The rule is simple: update the model first, then let Lustre render the
annotation. Do not snapshot nodes, mutate text in place for a diffing helper,
or add a JavaScript registry of selectors.

## Timed annotations on the sequence demo

The sequence demo has the richer version because position changes are the
lesson. Its runtime stores typed `Annotation` values with a target and tone:

- `StationTarget` marks a waypoint whose visible position changed.
- `LogTarget` boxes the newest sequenced operation.
- `LocalNote` and `SequencedNote` choose magenta or ink.

`annotate_routes` compares the before and after routes when an operation
changes visible positions. `annotate_log` records the sequenced moment. The
view turns those values into `note-local`, `note-sequenced`, and `note-newest`
classes, while the runtime clears each annotation after its playback-scaled
TTL.

To add another timed target, extend those typed targets, create the annotation
in the transition that owns the state change, and render the matching class in
`sequence/view.gleam`. Keep the timing in `sequence/runtime.gleam`; do not bolt
timers or `MutationObserver` callbacks onto the rendered DOM.

## Dedicated demos

The directory, Sudoku, and JSON OT pages own their behavior in the matching
native modules:

- `website_lustre/src/watershed_site/directory/`
- `website_lustre/src/watershed_site/sudoku/`
- `website_lustre/src/watershed_site/json_ot/`

They already render optimistic state, pending counts, flow dots, and sequenced
logs from their models. If one of them earns an opt-in field-notes layer, follow
the sequence pattern: typed annotation state in the runtime, classes in the
view, and a focused runtime/view test. Do not revive the deleted rig-side
TypeScript API.

## Check the work

Build the production site:

```sh
just website-lustre
```

Serve that generated artifact locally:

```sh
just website-lustre-serve
```

For a field-notes change, run the focused Gleam tests for the demo you touched,
then run `just _test-website-lustre`. In a browser, verify the note can be
switched off, pending edits still read as magenta, sequenced state reads as
ink, reduced motion remains usable, and no annotation survives a reset.
