# JSON workspace demo plan — directories of live JSON documents

**Date:** 2026-08-19
**Status:** shipped on main in `examples/json_workspace_lustre/`. JW1–JW7 complete.
**Builds on:** `2026-07-04-shared-directory-kernel-plan.md` (shipped), `2026-07-04-json-ot-kernel-plan.md` (shipped), `2026-08-08-facade-parity-sweep-plan.md` (FP5 shipped the Lustre `ensure_directory`/`subscribe_directory`/`ensure_json_ot`/`subscribe_json_ot` effects), `examples/release_checklist_lustre` (the scaffold template), `2026-08-09-ensure-channel-seed-needs-a-ready-connection.md` (the bootstrap-arm workaround this must follow).
**Benchmark:** the Firebase Realtime Database console — a live JSON tree several people edit at once — crossed with any project-tree sidebar.

**Prerequisite work: none.** FP5 shipped everything this touches. This retires the last "one site only" coverage entry for `SharedDirectory` + `JsonOt` (`docs/demo-ideas.md`, kind-coverage table).

## Decisions already made (flagged — confirm before JW1)

1. **The tree is one `DirectoryChannel`; documents are per-document `JsonOt` channels whose handles are stored as directory *values*.** Creating a document is `create_json_ot` + `directory_set(tree, path, name, json_ot_handle_of(ot))`; opening one is `directory_get` + `resolve_json_ot`. This is the first example to store channel handles anywhere other than the root map, which is its own small claim: handles are ordinary `Json` values and resolve from any slot. The alternative — a flat root map of JSON channels keyed by path strings, with the directory as a mere index — has two sources of truth for one fact and was rejected.
2. **Document creation is last-write-wins on the directory key, and the demo says so.** Two clients concurrently creating `config` in the same folder each create a channel and each set the key; the map merge keeps one handle and the loser's channel becomes unreachable garbage (harmless — channels are cheap and unreferenced ones cost nothing at runtime). No repair, no coordination. A "create is racy, edits are not" contrast is worth a README paragraph; making creation race-free would need `Claims` and would bury the data-structure lesson.
3. **Deleting a folder does not delete the channels inside it.** `delete_subdirectory` removes the tree node; the `JsonOt` channels live on, merely unreachable to new joiners. A client with such a document open keeps its editor open behind a "this folder was deleted" banner rather than losing work mid-keystroke. Say this in the README — it is Fluid's actual model, not a bug.
4. **The editor edits objects and scalar leaves only in v1.** Rendered as an indented tree; string/number/bool/null leaves editable in place, add-key and delete-key on objects, and an increment control on numbers using `number_add` — the one op that shows OT beating last-write-wins arithmetic (two concurrent +1s land on +2, no read-modify-write). Arrays render read-only. `ponytail:` arrays cap out at display-only in v1; `list_insert`/`list_delete`/`list_move` exist in `json_ot.gleam` and wiring them into the tree editor is the upgrade path if the demo needs a list story.
5. **Presence meta is the open path.** The roster shows who is connected; a document row shows chips for peers currently inside it, via the existing `presence.color_for`/`short_name`. Ephemeral only — never in the tree or the documents.
6. **Stay inside json0.** No subtype ops, no text-OT-inside-JSON. If an editor feature seems to need json1 semantics, that is the signal to cut the feature, per `2026-07-04-json1-ot-speclet.md` ("expand only if json0's limits bite" — a demo is not a bite).

## Why this demo

`SharedDirectory` and `JsonOt` are the only kinds with no example under `examples/` — they exist as website pages importing the facade directly. Beyond coverage, each has one behaviour that only a live app makes legible:

**Hierarchical identity.** A directory can be deleted and recreated under the same path, and ops addressed to the dead instance must not apply to the new one. This is the directory kernel's core correctness rule (`is_message_for_current_instance`, D12 — `src/watershed/directory_kernel.gleam:10-16`) and today nothing outside the kernel tests exercises it end-to-end.

**Transformed merge, not overwrite.** Two clients edit different properties of the same JSON document while disconnected, reconnect, and both edits survive — where a register-valued map would keep one whole document and drop the other. `number_add` sharpens the same point on a single field.

## Data model

```gleam
pub type Workspace

pub const tree: ChannelField(Workspace, schema.DirectoryChannel) = ...
```

One root-level channel field. Everything else — folders, documents — lives inside the directory or hangs off it as resolved `JsonOt` channels. A fresh `JsonOt` starts as an empty object (`json_ot_kernel.new` seeds `VObject([])`), so the editor never faces a null root.

Directory layout convention: subdirectories are folders; keys within a directory node are document names whose values are `JsonOt` handles. No other value shapes go in the tree, and the render path treats a non-handle value as corrupt rather than guessing.

## The races this demo is for

1. **Recreate-while-held.** Client B goes offline holding `/specs` and sets a key in a document-less folder op (`directory_set` on `/specs` itself, or creates a doc there). Client A deletes `/specs` and recreates it. B reconnects. B's ops were addressed to the dead instance and must be dropped, not grafted onto the new `/specs`. Gate on the observed behaviour — per the retro-board discipline, **do not assert a behaviour in the README before observing it in a test**.
2. **Divergent edits, one document.** Both clients open `/specs/api`, go offline (`go_offline`/`go_online` effects exist on `watershed_lustre`), one edits `title`, the other edits `version`, reconnect. Both edits present on both clients. Same-path concurrent `obj_replace` is also worth a test: transform keeps exactly one, deterministically, and the doc never forks.
3. **Concurrent create, same name.** Decision 2's LWW race: converge on one handle, one orphaned channel, no error surfaced to either creator beyond their doc's content being the survivor's.

## Rungs

- **JW1 — scaffold + connect.** New `examples/json_workspace_lustre/` on the `release_checklist_lustre` template (gleam.toml, justfile stanzas, smoke/run.mjs, doc_schema.gleam with the `Workspace` tag). `connect_dev`, `ensure_directory` on `tree`, **bootstrapped from the `Connected(Ok(_))` arm, not `GotHandle`** — the seed-before-handshake defect (`2026-08-09-ensure-channel-seed-needs-a-ready-connection.md`) bites brand-new documents exactly like this one. Gate: two tabs connect and render an empty tree. ✅ shipped: `bootstrap_effect` is called only from `Connected(Ok(_))`.
- **JW2 — folders.** Tree render from `directory_subdirectories`/`directory_entries`, create/delete folder via `directory_create_subdirectory`/`directory_delete_subdirectory`, `subscribe_directory` re-render. Gate: a folder created in one tab appears in the other; nested creation works. ✅ shipped: `tree_view`/`breadcrumbs_view`, nested navigation via `NavigateTo`, pinned indirectly through the convergence tests' folder create/delete assertions.
- **JW3 — documents.** Create (decision 1), open (resolve + `subscribe_json_ot`), raw read-only JSON view of `json_ot_view`. Gate: a document created in one tab opens with identical content in the other. ✅ shipped: `CreateDocClicked`/`OpenDocClicked`, `editor_view`; pinned by `divergent_edits_on_different_keys_converge_across_reconnect_test` and the live smoke test. Shipping this rung exposed and fixed a runtime gap: `directory_set` now attaches channel-handle dependencies before it submits the directory value, matching `watershed.set`.
- **JW4 — the editor.** Decision 4's tree editor: scalar leaf edits (`obj_replace`), add/delete key (`obj_insert`/`obj_delete`), number increment (`number_add`). Gate: two tabs editing different keys of the same document concurrently both keep their edits; two concurrent increments land on the sum. ✅ shipped: `render_node`/`render_object`/`render_readonly`, `concurrent_increments_land_on_the_sum_test`, and `concurrent_same_path_replacements_converge_test`. This rung also fixed reconnect convergence in the shared JSON OT and rich-text client kernels by deriving transform side from sequence order rather than reconnect-unstable client identity.
- **JW5 — presence.** Open-path meta, roster, per-document chips. Gate: opening a doc in one tab lights its chip in the other; closing the tab clears it. ✅ shipped: `WorkspacePresence { color, name, open_path }`, `roster_view`, `peers_at` chips on tree rows.
- **JW6 — the deleted-folder banner and the recreate race.** Decision 3's banner; then the recreate-while-held scenario as a convergence test, observed first, then documented. Gate: the test pins the instance-filtering behaviour and the README describes what it pinned. ✅ shipped: `mark_deleted_if_covered` raises the banner; `a_stale_write_queued_before_a_delete_and_recreate_is_dropped_test` (facade + sluice) and `directory_invariants_test.gleam` (pure kernel, with `check_invariants`) both pin the instance filter, observed before the README described it.
- **JW7 — README + smoke test.** README carries decisions 2 and 3 verbatim (the racy-create contrast, the orphaned-channel model). Smoke test on the `release_checklist_lustre` pattern; headline smoke assertion is race 2 (divergent edits converge across a reconnect). ✅ shipped: `examples/json_workspace_lustre/README.md`; `src/smoke.gleam` ran green against a live floodgate server (`just integration-up`).

## Testing strategy

- **Convergence tests** (`test/convergence_test.gleam`, two in-process clients over `sluice`, same harness as `release_checklist_lustre`) for the three races above plus same-path `obj_replace`. These are the demo's claims; each rung gate that mentions concurrency is one of these tests, not a manual two-tab check.
- **Directory invariants:** the facade does not expose a live channel's internal `DirectoryState`, so `check_invariants` cannot run against the convergence tests' clients directly. `test/directory_invariants_test.gleam` instead pins the same recreate-while-held scenario one layer down, directly against `directory_kernel`, and runs `check_invariants` there.
- **Render-rule unit test:** feed the tree renderer a directory containing a non-handle value and a handle to a since-deleted folder's document; assert it renders the corrupt-value marker and the banner respectively, never crashes.
- **Smoke test** end-to-end against a real relay, per the template.
