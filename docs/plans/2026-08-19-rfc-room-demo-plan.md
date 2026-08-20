# RFC publishing room demo plan — `SharedRichText` + `PactMap` + presence

**Date:** 2026-08-19
**Builds on:** `2026-07-03-pact-map-kernel-plan.md` (shipped), `2026-08-08-facade-parity-sweep-plan.md` (FP2 shipped `SharedRichText` on the JS facade; FP5 shipped the Lustre `ensure_rich_text`/`subscribe_rich_text` and `ensure_pact_map`/`subscribe_pact_map` effects), `website/src/scripts/rich-text-demo.ts` (the Quill bridge this extracts), `examples/release_checklist_lustre` (the scaffold template *and* the prior art for every PactMap discipline below), `2026-08-09-ensure-channel-seed-needs-a-ready-connection.md` (the bootstrap-arm workaround this must follow).
**Benchmark:** a Google Doc crossed with an RFC tracker's published-revision slot — everyone types at once, but "the published revision" is a single fact the room settles on.

**Prerequisite work: none.** FP2 and FP5 shipped everything this touches. This retires the `SharedRichText` entry in the "one site only" coverage row (`docs/demo-ideas.md`, kind-coverage table) — the last kind whose only demo imports the facade from a website page.

## Decisions already made (flagged — confirm before RR1)

1. **Two root channel fields: `draft: RichTextChannel`, `published: PactMapChannel`.** The draft is one `SharedRichText` everyone edits without coordination. Publishing snapshots the draft — `rich_text_view` → `rich_text.document_to_json` — and calls `pact_map_set(published, "current", value)` on one fixed key. The value is `{label, content}` where `label` is a short revision name typed at publish time and `content` is the encoded document. No revision history channel in v1. `ponytail:` history caps out at "the one accepted value" — if a revision log is ever wanted, the upgrade path is a `SharedSequence` of the same snapshot values, appended on `WentAccepted`.
2. **The Quill bridge lives in the example, not in `watershed_lustre`.** The textarea component earned a home in the library because it wraps a native platform element; Quill is a heavy npm dependency the library must not carry. Extract `website/src/scripts/rich-text-demo.ts` (~540 lines, working) into the example as a Lustre element + FFI, keeping its three disciplines intact: submit only user-sourced Quill deltas (decoded via the generated `rich_text` codec), apply remote changes from kernel events rather than echoing local ones, and keep Quill's undo history scoped to user edits.
3. **Acknowledgement, not approval — enforced in the vocabulary.** `channel.gleam:726` auto-submits `OweAccept`; no client ever chooses to agree (the drum-machine correction, restated here because this UI is the one most tempted to violate it — "publish" reads like a workflow word). No "approve", "vote", "sign off" controls anywhere. The pending banner reads "sequenced, waiting on N connected clients", with N from `list.length(pending.expected_signoffs)` via `pact_map_pending`. **Count, never names.** The quorum roster could name the laggards, but names read as "who hasn't approved yet"; a count reads as what it is — protocol lag.
4. **Publish is disabled while a publication is pending** — the `release_readiness.gleam` discipline verbatim: a second `pact_map_set` while one is in flight is ambiguous to the user, and the disable is a UI kindness, not a security boundary (nothing stops another client from setting the key; say so in a comment, as the release checklist does).
5. **The publication is a snapshot, decoupled from the draft.** Draft ops after publish do not touch the pending or accepted value — separate channels, separate stories. The UI shows a "draft has changed since this revision" note by comparing the draft's `document_to_json` against the accepted `content`. String equality on canonical encodings is enough; no diffing.
6. **Peer cursors are a stretch goal, not v1.** The website bridge already prototypes quill-cursors over ripples, so RR8 is mostly a port — but presence v1 is the roster plus an is-editing chip (`update_presence` on editor focus/blur), because cursors add a second npm dependency and a selection-transform path that would dominate review of an otherwise small example.

## Why this demo

`SharedRichText` is fully public on both facades since FP2/FP5 and exercised by nothing in `examples/`. Beyond coverage, this pairing puts watershed's **two consistency models on one screen**: the left pane merges every keystroke optimistically through delta transform; the right pane holds a value that is *sequenced but not yet settled* until the frozen signoff list drains. No other example makes that contrast visible side by side — the release checklist has the PactMap half but its "document" is a version string.

Two behaviours only a live app makes legible:

**Formatted transform, not plain-text transform.** Concurrent bold-vs-italic on overlapping ranges, and insert-vs-format races, go through the quill-delta algebra (`rich_text.transform`). The textarea examples can't show attribute merges at all.

**A pending value is not a draft.** The published slot goes pending the moment the set sequences, is identical on every client, and yet is not accepted — and one backgrounded tab holds it there. `sluice_js.pause` makes that deterministic in tests; a real backgrounded tab makes it visceral in the browser.

## Data model

```gleam
pub type RfcRoom

pub const draft: ChannelField(RfcRoom, schema.RichTextChannel) = ...
pub const published: ChannelField(RfcRoom, schema.PactMapChannel) = ...
```

Presence meta: `#(name, editing)` — display name plus whether the editor has focus. Ephemeral only. The published pane renders the accepted value in a read-only Quill instance (cheapest correct renderer for a quill-delta document; no HTML serializer to write or audit).

## The races this demo is for

1. **Publication held by a paused client.** Three clients; pause C's frames (`sluice_js.pause`, the `quorum_test.gleam` pattern). A publishes. Assert pending on A and B with one expected signoff outstanding; resume C; assert `WentAccepted` and identical accepted values everywhere.
2. **Signoff drains by leave, not accept.** Same setup, but C disconnects instead of resuming. The kernel's other drain path — membership leave — must settle the publication without C ever acknowledging. This path has kernel tests but no example-level exercise.
3. **Divergent formatted edits.** Both clients offline (`go_offline`/`go_online`), one bolds a range and inserts text, the other italicises an overlapping range and inserts at the same position; reconnect; both clients' `document_to_json` are byte-identical and contain all four edits.
4. **Publish races the draft.** A publishes, then both clients keep typing while the publication is pending. Accepted `content` equals the snapshot at set time, not the current draft — decision 5, observed.
5. **Concurrent publish.** Two clients `pact_map_set` the same key in the same window. Per the retro-board discipline, **observe the kernel's behaviour in a test before writing a word about it in the README** — do not assume last-set-wins or first-set-wins.

## Rungs

- **RR1 — scaffold + connect.** New `examples/rfc_room_lustre/` on the `release_checklist_lustre` template (gleam.toml, justfile stanzas, smoke/run.mjs, doc_schema.gleam with the `RfcRoom` tag). `connect_dev`, then `ensure_rich_text` + `ensure_pact_map` **from the `Connected(Ok(_))` arm, not `GotHandle`** — the seed-before-handshake defect bites brand-new documents exactly like this one. Gate: two tabs connect and render an empty editor shell.
- **RR2 — the Quill bridge.** Decision 2's extraction: editable draft pane, user deltas submitted via `submit_rich_text`, remote events applied from `subscribe_rich_text`. Gate: text typed bold in one tab arrives bold in the other; concurrent typing in both tabs converges.
- **RR3 — publish → accepted.** Publish button snapshots the draft (decision 1), `pact_map_set`; published pane renders the accepted value read-only from `pact_map_get`. Gate: publishing in one tab updates the published pane in both.
- **RR4 — pending is visible.** `pact_map_is_pending` / `pact_map_pending` drive the "sequenced, waiting on N connected clients" banner (decision 3's vocabulary), publish disabled while pending (decision 4), "draft has changed since this revision" note (decision 5). Gate: with a third tab backgrounded, publishing shows the waiting count until that tab resumes.
- **RR5 — presence.** Roster with `presence.color_for`/`short_name`, is-editing chips from focus/blur meta. Gate: focusing the editor in one tab lights the chip in the other; closing the tab clears the roster entry.
- **RR6 — the five races as tests.** All of "The races this demo is for", in the harness below. Race 5's outcome gets written into the README only after the test pins it. Gate: tests green and the README's PactMap paragraphs cite them.
- **RR7 — README + smoke.** README carries decisions 3–5 verbatim (the not-a-vote model, the disable-is-not-a-boundary caveat, the snapshot decoupling). Smoke test on the template pattern; headline smoke assertion is race 1 end-to-end against a real relay — publish held pending by a paused client, then accepted on resume.
- **RR8 (stretch) — peer cursors.** Port the quill-cursors + selection-ripple half of the website bridge. Only after RR1–RR7 ship; skip freely.

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, in-process clients over `sluice`, same harness as `release_checklist_lustre`) for races 3–5. Rich-text convergence asserts equality of `rich_text.document_to_json` across clients, not structural spot checks.
- **Quorum tests** (`test/quorum_test.gleam` pattern, `sluice_js.pause`) for races 1–2 — hold, then resume for race 1, disconnect for race 2.
- **Bridge unit test:** feed the delta codec a remote event stream containing an attribute-only delta and an insert-at-same-position pair; assert the editor document matches `rich_text.apply` done by hand. This is the one non-trivial pure seam the extraction introduces.
- **Smoke test** end-to-end against a real relay, per the template.
