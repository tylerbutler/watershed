# markdown_notes_lustre

Offline-first markdown notes — a minimal Obsidian: a note list beside a
plain-markdown editor, where several people type in the same note at once.

Four CRDT kinds, each present because its merge rule is the honest model for
the feature — and every one has ack-free merge, so the whole data model is
portable to p2p mode unchanged:

| Channel | Kind | Why this kind |
| --- | --- | --- |
| `notes` | OR-map | name → serialized `SharedText` handle; concurrent set beats concurrent remove, so a re-registered note survives a delete and a deleted name can be re-created |
| note bodies | `SharedText` (one per note) | markdown formatting is characters in the document — `**bold**` is five inserts, not an attribute range — so the file round-trips as a plain `.md` string |
| `tags` | OR-set | `"<note>\t<tag>"` pairs; a tag you re-add after someone concurrently removes it sticks |
| `order` | `SharedSequence` | sidebar order: append on create, `sequence_move` on drag |

This is the first example to store a channel handle anywhere other than the
root map: handles are ordinary JSON values, and a `SharedText` handle written
into an OR-map register with `or_map_set_json` resolves on a client that has
never seen the channel.

## Running it

```sh
just integration-up          # floodgate dev server on :4000
pnpm install
pnpm run build               # bundles the app and stamps sw.js
pnpm run serve               # http://localhost:8080
```

Open two tabs on the same URL (keep the `?document=` id) and type in the same
note.

```sh
gleam test                   # unit + convergence tests (in-memory sluice)
pnpm run smoke               # end-to-end against the live dev server
```

## The offline story, stated precisely

"Works offline" means three different things, and this app ships the first
two:

- **App shell (v1):** the app is a PWA — a manifest plus one hand-written
  service worker that caches the built bundle, so a previously visited tab
  reopens the full UI with no network and no relay, installable to the home
  screen. Service workers do not intercept WebSockets, so the collaboration
  path is untouched.
- **Document, session-scoped (v1):** `go_offline` queues every edit locally
  and the UI keeps working; `go_online` resubmits and catches up; nothing is
  lost across any disconnect *while the tab is open*. The "N changes not yet
  saved" indicator is `diagnostics(doc).in_flight_count`, polled.
- **Document, durable (follow-on):** reloading while offline, or cold-starting
  with no relay reachable, reopens the app shell but cannot open a document —
  watershed has no client-side persistence layer, and `connect` requires the
  relay. This shell shows that state honestly ("notes need a connection to
  open — offline documents are coming") instead of a spinner. Closing the gap
  is a watershed runtime feature (`docs/plans/2026-08-19-durable-persistence-plan.md`),
  not something to fake in app code with a localStorage mirror that would fork
  the CRDT history.

To see the shell layer: build, visit the page once, stop the relay, set the
browser offline, reload — the full UI renders with the honest disconnected
state. The convergence test suite pins the session-scoped layer (race 2
below).

## The races, as observed

All six races this demo exists for are pinned in
`test/convergence_test.gleam` over the in-memory sluice. Two are worth
spelling out:

**Toolbar vs. keystrokes in the same word (race 1).** A selects `deadline`
and presses bold while B types `LATE` inside the word. Observed: both clients
converge on `meet the **deadLATEline** now` — the delimiters still enclose
the word *including* B's insertion, because the closing `**` is anchored by
identity next to its neighbouring character, not at a numeric offset.

**Concurrent create, same name (race 3).** Both clients create `shared` at
once. Observed: the registers converge on one handle (register LWW), both
clients resolve the same channel and see the survivor's seed line, and the
loser's channel becomes unreachable garbage — harmless. Neither creator sees
an error beyond their content being the survivor's.

The headline offline claim — both clients offline, divergent edits to
different paragraphs of one note, reconnect, nothing lost — is race 2, pinned
in the convergence suite and asserted end-to-end by the smoke test.

## Deliberate cuts

- No rename: rename is create-new-key plus delete-old-key and reopens the
  create race for no demo payoff. The upgrade path is a copy + delete toolbar
  action once someone asks.
- Toolbar buttons apply formatting; they do not toggle it. Pressing bold on
  bold text nests delimiters, same as typing them.
- No preview pane: rendering is orthogonal to every CRDT behaviour this demo
  exists to show.

## Follow-ons

- **P2p transport:** every kind here is il-capable, so the p2p port
  (`docs/plans/2026-08-12-webrtc-p2p-plan.md`) is a transport swap, not a
  remodel — the root bootstrap slot is the one piece `crdt_js.connect`'s
  explicit root initializer replaces.
- **Durable documents:** `docs/plans/2026-08-19-durable-persistence-plan.md`.
  When both ship, this app's only change is deleting the "notes need a
  connection to open" state.
