# Markdown notes demo plan — offline-first notes on `SharedText`

**Date:** 2026-08-19
**Builds on:** `2026-08-03-shared-textarea-component-plan.md` (shipped — the collaborative textarea this app is built around), `2026-08-19-json-workspace-demo-plan.md` (the handle-as-map-value pattern for the note list), `2026-08-09-ensure-channel-seed-needs-a-ready-connection.md` (the bootstrap-arm workaround this must follow), `examples/text_lustre` (single shared textarea, this app's starting point), `2026-08-12-webrtc-p2p-plan.md` (shipped — the p2p mode the follow-on targets and the reason for the CRDT-only constraint).
**Benchmark:** a minimal Obsidian — a note list beside a plain-markdown editor — where several people type in the same note at once.

**Prerequisite work: none** for MN1–MN7. Everything this touches shipped: `SharedText` with `text_insert`/`text_delete_range`/`text_replace_range`, the `textarea` component with grapheme-indexed `selection`, `OR-Map` with `or_map_set_json`/`resolve_text`, `go_offline`/`go_online` effects, and the ensure/subscribe plumbing. The PWA shell (MN6) is plain app code. The two follow-ons — p2p transport and durable document persistence — each need watershed-side work and ship as their own plans; the data-model decisions here are made so neither forces a remodel.

## Decisions already made (flagged — confirm before MN1)

1. **`SharedText`, not `SharedRichText`.** Markdown formatting is characters in the document: `**bold**` is five inserts, not an attribute range. The toolbar therefore writes syntax into the text, the file round-trips as a plain `.md` string with no export step, and every client sees the same bytes. `SharedRichText` stores formatting as Quill attributes out of band, which is the wrong model for markdown and would force a lossy conversion in both directions.
2. **CRDT-only kinds, so the p2p follow-on is a transport swap, not a remodel.** P2p mode (`watershed/crdt_js`, per `2026-08-12-webrtc-p2p-plan.md`) carries only kinds with ack-free merge; it rejects `SharedMap`, OT, and coordination kinds. Every kind in this app's data model is therefore il-capable: `OR-Map` for the note list, `SharedText` for note bodies, nothing else. The one `SharedMap` touch in v1 is the root bootstrap slot that `ensure_or_map` seeds the notes handle into — sequencer-mode plumbing, not app state, and exactly the piece the p2p follow-on replaces with `crdt_js.connect`'s explicit root initializer. Any future feature that wants a server-order-dependent kind (Claims for note locking, say) forfeits p2p and must say so in its own plan.
3. **The note list is one `OR-Map` of note name → `SharedText` handle.** Values are registers: `or_map_set_json(notes, name, text_handle_of(text))` on create, parse the register string back to JSON and `resolve_text` on open. OR-Map's merge rules fit a note list better than `SharedMap`'s anyway: concurrent set beats concurrent remove (a note someone is re-registering survives a delete), and a deleted name can be cleanly re-created. Concurrent create of the same name still converges on one handle — register timestamps pick the winner, the loser's channel becomes unreachable garbage (harmless). Deleting a note removes the key only; a client with that note open keeps its editor behind a "this note was deleted" banner rather than losing work mid-keystroke. No rename in v1 — rename is create-new-key plus delete-old-key and reopens the create race for no demo payoff. `ponytail:` rename is cut; the upgrade path is a `copy + delete` toolbar action once someone actually asks.
4. **The toolbar is selection surgery through the existing facade.** `textarea.selection(model)` already returns a half-open **grapheme** range, which is exactly the unit `text_replace_range` and `text_insert` take, so no offset conversion exists anywhere in this app. Inline buttons (bold `**`, italic `*`, code `` ` ``) wrap the selection: one `text_insert` at the end index, one at the start index, end first so the start index stays valid. Line buttons (H1/H2, bullet) insert a prefix at the start of the line containing the selection, found by scanning `text_value` backwards for `\n`. A collapsed caret gets the delimiters inserted around it. The component re-reads the channel on `KernelEvent`, so toolbar edits render through the same path as remote edits with zero new plumbing.
5. **Toolbar buttons apply formatting; they do not toggle it.** Pressing bold on already-bold text nests delimiters, same as typing them. `ponytail:` toggle-off means detecting delimiters at the range edges and deleting them — small, deferred until the wrap-only version annoys someone in practice.
6. **The offline story is three layers, and v1 ships the first two.** The README states which layer the user is looking at in exactly these terms.
   - **App shell (v1, MN6):** the app is a PWA — a manifest plus one hand-written service worker that caches the built bundle, so a previously visited tab reopens the full UI with no network and no relay, installable to the home screen. Service workers do not intercept WebSockets, so the collaboration path is untouched.
   - **Document, session-scoped (v1, MN5):** `go_offline` queues every edit locally and the UI keeps working; `go_online` resubmits and catches up; nothing is lost across any disconnect *while the tab is open*.
   - **Document, durable (follow-on):** reloading while offline, or cold-starting with no relay reachable, reopens the app shell but cannot open a document — watershed has no client-side persistence layer, and `connect` requires the relay. V1's shell shows that state honestly ("notes need a connection to open — offline documents are coming") instead of a spinner. Closing the gap is a watershed runtime feature sketched in the follow-ons section, not something to fake in app code with a localStorage text mirror that would fork the CRDT history.
7. **No preview pane in v1.** The user-visible claim is collaborative editing plus a toolbar; rendering is orthogonal to every CRDT behaviour this demo exists to show. If a pure-Gleam commonmark package verifiably compiles on the JavaScript target, preview is a cheap follow-on rung; hand-rolling a markdown renderer or adding a bundled JS parser via FFI is not on the table.

## Why this demo

`examples/text_lustre` proves one textarea converges. This app adds the three things every real editor sits on top of, none of which any example currently exercises together:

**Programmatic edits beside keystrokes.** Every existing `SharedText` surface feeds the channel from user typing. The toolbar is the first code path where the app itself computes and submits range edits against a document another client is concurrently typing into — the case where grapheme indexing and identity-anchored inserts either hold or don't, end to end.

**A document-per-item app shape on CRDT-only kinds.** Note list in an `OR-Map`, one text channel per note, open/close/delete while others edit. This is the shape most people actually want `SharedText` for, it retires most of the "offline field notebook" idea from `docs/demo-ideas.md` (`OrMap` + `SharedText` + presence) in a more familiar framing, and — because both kinds have ack-free merge — it is the first example whose whole data model is portable to p2p mode unchanged.

**The offline story, stated precisely.** The PWA shell opens with no network, the offline toggle plus reconnect-convergence test demonstrates the queue-and-resubmit guarantee, and the README draws the exact line between those and durable documents (decision 6), so the project stops being vague about what "works offline" means.

## Data model

```gleam
pub type Notebook

pub const notes: ChannelField(Notebook, schema.OrMapChannel) = ...
```

One root-level channel field: an `OR-Map` whose keys are note names and whose register values are serialized `SharedText` handles (`or_map_set_json(text_handle_of(text))` on create; parse the register string as JSON and `resolve_text` on open). A fresh note is seeded with a `# Title` line matching its name — one `text_append` at create time, nothing clever. The render path treats a `Tally` value or an unparseable register as corrupt rather than guessing.

App state is `OR-Map` + `SharedText` only (decision 2). The `ChannelField` above rides the sequenced root `SharedMap`, and that is the model's entire sequencer dependency.

## The races this demo is for

1. **Toolbar vs. keystrokes in the same word.** Client A selects `deadline` and presses bold while client B is typing inside that word, both online. Expected: both converge, and the delimiters still enclose the word including B's insertion, because the closing `**` insert is anchored by identity next to its neighbouring character, not at a numeric offset. Per the retro-board discipline: **observe this in a convergence test before asserting it in the README** — if identity anchoring places the delimiter differently, document what actually happens.
2. **Divergent offline edits, one note.** Both clients open the same note, both go offline, each edits a different paragraph, both reconnect. Every edit survives on both clients. This is the headline offline claim and the smoke test's headline assertion.
3. **Concurrent create, same name.** Decision 3's register race: converge on one handle, one orphaned channel, neither creator sees an error beyond their content being the survivor's.
4. **Delete-while-editing.** A deletes a note B has open; B's editor stays up behind the banner and B's subsequent keystrokes still apply to the (unreachable but functioning) channel. A concurrent *re-set* of the same key beats the remove (OR-Map's observed-remove rule) — worth one test to pin, since it is the behaviour that distinguishes this from the `SharedMap` version of the same app.

## Rungs

- **MN1 — scaffold + connect.** New `examples/markdown_notes_lustre/` on the `release_checklist_lustre` template (gleam.toml, justfile stanzas, smoke/run.mjs, `doc_schema.gleam` with the `Notebook` tag). `connect_dev`, `ensure_or_map` on `notes`, **bootstrapped from the `Connected(Ok(_))` arm, not `GotHandle`** — the seed-before-handshake defect bites brand-new documents exactly like this one. Gate: two tabs connect and render an empty note list.
- **MN2 — the note list.** Create (decision 3: `create_text` + seed line + `or_map_set_json` the handle), delete, open (parse register + `resolve_text` + bind). Gate: a note created in one tab appears and opens with identical content in the other.
- **MN3 — the editor.** `textarea.init` on the resolved channel at the open callback (never an `Option` channel, per the component's own doc), peers wired for shared cursors since the component already carries them. Gate: two tabs typing in one note converge; each sees the other's cursor.
- **MN4 — the toolbar.** Decision 4's six buttons as pure helpers over `#(String, #(Int, Int))` returning the edit list, applied via `text_insert`/`text_replace_range`. Gate: race 1's convergence test passes and pins where concurrent delimiters land.
- **MN5 — offline.** An offline toggle on `go_offline`/`go_online`, a queued-edits indicator, and race 2 as a convergence test. Gate: the reconnect test passes; the banner from race 4 works.
- **MN6 — PWA shell.** `manifest.webmanifest`, icons, and one hand-written service worker: cache-first for the built app shell under a cache name versioned by build hash, nothing else intercepted. The disconnected state from decision 6's third layer. No workbox, no framework. Gate: stop the relay, set the browser offline, reload a previously visited tab — the full UI renders with the honest "can't open documents offline" state, and the app passes the browser's installability check.
- **MN7 — README + smoke.** README states decision 6's three layers verbatim and documents races 1 and 3 as observed. Smoke test per template; headline assertion is race 2.

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, two in-process clients over `sluice_js`, same harness as `release_checklist_lustre`) for all four races. Each rung gate that mentions concurrency is one of these tests, not a manual two-tab check.
- **Toolbar unit tests:** the helpers from MN4 are pure functions from (text, selection) to edits, so line-start math, collapsed-caret wrapping, and end-before-start insert ordering get plain gleeunit tests with no channel at all.
- **Smoke test** end-to-end against a real relay, per the template. The PWA gate (MN6) stays a scripted manual check unless the smoke harness can drive a service worker cheaply; do not build harness machinery for it.

## Follow-ons (separate plans, enabled by decision 2)

Neither of these blocks v1, and v1's data model was chosen so neither forces a remodel. Together they complete the claim the app's name makes: notes that work with no server and survive a reload.

**P2p transport.** Swap `connect_dev` for `crdt_js.connect` with an OR-Map root initializer (p2p mode has no `SharedMap` root, which is why decision 2 keeps `SharedMap` out of app state), point at the shipped signaling + coturn stack (`just p2p-up`, `?signaling=`/`?ice=` params as in `clap_counter_lustre`), and port the editor binding to the il textarea counterpart in `watershed_lustre/crdt.gleam`. Two things to verify before writing that plan, not assume: that the textarea component (or its il counterpart) binds a `crdt_js` text handle, and that shared cursors have a presence path in p2p mode — if not, the p2p build drops cursors and says so.

**Durable document persistence.** Planned: `2026-08-19-durable-persistence-plan.md`. It ships on the crdt runtime only — `export_snapshot`/`import_snapshot`/`attach` already form the loop, and a disk snapshot is just another replica joining — which confirms the ordering this section implies: the p2p port comes first, persistence lands on top of it, and the sequenced root `SharedMap` question dissolves because in crdt mode the OR-Map is the root. When both ship, this app's only change is deleting MN6's "notes need a connection to open" state.
