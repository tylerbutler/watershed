# Shared textarea component plan — componentizing `SharedText` for Lustre

**Date:** 2026-08-03
**Builds on:** `2026-07-06-lustre-integration-plan.md` (LU1–LU3, shipped — this is the first *component* on top of those effects), `examples/text_lustre` (the evidence: a working textarea↔SharedText bridge whose logic is all reusable and none of it packaged).
**Benchmark:** Fluid's `CollaborativeTextArea` React component — the DDS meets the widget, so apps drop in a tag instead of reimplementing the diff/caret/IME bridge.

**Decisions already made (flagged — confirm before TA1):**

1. **Core shape is a nested MVU triple, not a custom element.** A new module `watershed_lustre/textarea` exports `Model` / `Msg` / `init` / `update` / `view`; the parent app holds the child model, routes `Msg` through `element.map`/`effect.map`, and passes the resolved `SharedText` to `init`. This is fully typed — no way to smuggle the opaque `SharedText` across a custom-element property boundary without an unsafe `Json` coercion, because `attribute.property` takes `Json` and the handle closes over the live runtime. A `<watershed-textarea>` custom-element wrapper stays on the ladder (TA5) and wraps this same triple via `lustre.component` once handle-passing is settled; nothing in the core shape blocks it.
2. **`init` takes a resolved `SharedText`, not an `Option`.** The parent already has the `ensure_text` → `EnsuredBody(Ok(text))` moment; constructing the component there means the model never carries a `None` channel and the view never renders a disabled ghost. Before that moment the parent renders whatever placeholder it wants.
3. **The component owns the whole DOM↔CRDT bridge**: snapshot-on-event, grapheme diff → one minimal op per keystroke, caret/selection preservation across remote edits (anchors), and the IME composition guard. The parent owns connection, schema, layout, and styling (via pass-through attributes).
4. **`grapheme_diff` is promoted from `examples/text_lustre` into `watershed_lustre`** (new module `watershed_lustre/grapheme_diff`, unchanged semantics). It is pure, already documented, and the example re-imports it from the package. Same treatment the LU1 effects gave the connect glue.

## Why this rung

`examples/text_lustre` proves the bridge works but every future app must copy four things by hand: the diff-on-input pattern, the "re-read optimistic value on every `TextChanged`" snapshot discipline, error folding for stale-index rejections, and — the one the example *doesn't* do — keeping the user's caret in place when a remote edit rewrites the `<textarea>` value out from under them. That last one is the difference between a demo and a component: without it, a remote keystroke while you're typing teleports your cursor, because the browser keeps the caret at a raw UTF-16 offset into a string that just changed. `TextAnchor` exists precisely to solve this, and the component is where that solution should live once, not per-app.

## Module surface

`watershed_lustre/src/watershed_lustre/textarea.gleam`:

```gleam
pub opaque type Model

pub opaque type Msg

/// Wrap a resolved text channel. Subscribes to it (the returned effect) and
/// takes the first snapshot, so a joiner renders existing text immediately.
pub fn init(channel: SharedText) -> #(Model, Effect(Msg))

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg))

/// A controlled `<textarea>` bound to the channel. Caller attributes
/// (rows, placeholder, class, disabled, …) are appended after the
/// component's own, so callers can override presentation but the value
/// and the event handlers always win.
pub fn view(model: Model, attrs: List(Attribute(Msg))) -> Element(Msg)

// ── Read-only accessors (the outbound surface — no callback plumbing) ──
pub fn value(model: Model) -> String
pub fn length(model: Model) -> Int
pub fn error(model: Model) -> Option(String)          // last rejected op, cleared on next success
pub fn selection(model: Model) -> Option(#(Int, Int)) // current grapheme range, for presence later
```

No `on_change`/`on_error` constructor parameters: the parent already routes every `Msg` through its `update`, so it can inspect the accessors after each `textarea.update` call. This keeps the signature the standard nested-TEA triple and avoids threading a parent-msg type parameter through the component.

### Internal model

```gleam
type Model {
  Model(
    channel: SharedText,
    instance: String,            // random key stamped as data-attr; before_paint finds the element by it
    value: String,               // optimistic snapshot the view renders
    selection: Option(Selection),
    composing: Option(TextAnchor), // Some(anchor at composition start) while IME is active
    frozen: Option(String),      // value frozen during composition (vdom keeps rendering this)
    error: Option(String),
  )
}

type Selection {
  Selection(start: TextAnchor, end: TextAnchor)
}
```

Anchor biases: **selection start `Before`, selection end `After`** — the selection hugs the selected *content*: a remote insert at either edge lands outside the range, and interior edits grow/shrink it naturally. **Collapsed caret: both anchors `After`** (attached to the preceding grapheme), so a remote insert exactly at the caret leaves the caret before the inserted text — the user's typing position stays where they left it. This matches ProseMirror/Yjs association conventions; it's a judgment call, noted here so it isn't relitigated per bug report.

### Messages and flows

```gleam
type Msg {
  KernelEvent(text_kernel.TextEvent)
  UserInput(value: String, sel_start: Int, sel_end: Int)  // UTF-16 offsets, read off event.target
  UserSelect(sel_start: Int, sel_end: Int)
  CompositionStarted
  CompositionEnded
}
```

**Selection reads need no FFI.** The `input` handler is a custom `event.on("input", decoder)` whose decoder pulls `target.value`, `target.selectionStart`, `target.selectionEnd` in one pass. Caret-only moves are caught by the same decoder on `select`, `keyup`, `mouseup`, and `focus`. (Element-level `selectionchange` is attractive but its bubbling behavior vs. Lustre's delegated root listener is unverified — the four-event set is the conservative spec; revisit if it proves noisy.) Re-anchor only when the raw offsets actually changed since the last read.

**Local input** (`UserInput`):
1. Diff `watershed_js.text_value(channel)` against the new value with `grapheme_diff` → exactly one `text_insert` / `text_delete_range` / `text_replace_range`, or nothing.
2. On `Error(reason)` (stale index — a peer edited between render and keystroke), record it and re-snapshot: the next render snaps the textarea back to optimistic truth.
3. Convert the UTF-16 offsets to grapheme indices and re-anchor the selection.
4. Snapshot. The kernel's own `TextChanged` arrives next microtask via the subscription and re-snapshots to the same string — the vdom write is a no-op, so the browser-managed caret is untouched. This is why local typing needs no caret restoration at all.

**Remote edit** (`KernelEvent(TextChanged)`, or any event where the snapshot differs from the rendered value):
1. Re-read the optimistic value into the model.
2. Resolve both selection anchors (`text_resolve_anchor`) → grapheme indices → clamp to the new length. An `UnknownAnchorTarget` (the anchored grapheme was deleted remotely) collapses the selection to the nearest resolvable edge, or drops it.
3. Return `effect.before_paint(fn(_, root) { restore_selection(root, instance, start_u16, end_u16) })`. `before_paint` runs after the vdom has patched `textarea.value` but before the browser paints — the caret never visibly jumps. The FFI restores only if the element is the active (focused) element; stealing focus to place a caret is worse than losing the position.

**UTF-16 ↔ grapheme conversion** — the browser speaks code units, the CRDT speaks graphemes; the component converts at the boundary, both directions, via a pure Gleam fold over `string.to_graphemes` plus one FFI one-liner `utf16_length = (s) => s.length`. This is the bug class the example's module docs warn about (emoji, combining marks); the conversion lives in `watershed_lustre/textarea` (private) or alongside `grapheme_diff` if the diff wants it too.

**IME composition** (`CompositionStarted` / `CompositionEnded`):
- On start: pin an anchor at the caret, freeze the rendered value (`frozen: Some(model.value)`), and stop diffing intermediate `input` events — composition intermediates are not edits, and re-rendering the value mid-composition cancels the IME session in most browsers.
- Remote events during composition still update the CRDT and the model's `value`, but the view keeps rendering `frozen` — the composition session survives.
- On end: read the textarea's final value, diff it against `frozen` to extract the composed edit, re-map its index through the pinned anchor (remote edits may have shifted it), apply as one op, unfreeze, snapshot, restore caret.
- Documented limitation, v1: a remote edit *inside* the composed-over region during an active composition can interleave oddly; convergence is still guaranteed by the CRDT, only the local caret/visual during that window is best-effort. This matches what mature collaborative editors ship.

### FFI

One small file, `watershed_lustre/src/watershed_lustre/textarea_ffi.mjs`:

- `utf16_length(s)` — `s.length`.
- `restore_selection(root, instance_key, start, end)` — `querySelector` by the instance data-attribute (searching from the app/component root that `before_paint` hands over, so multiple instances and future shadow roots both work), check `document.activeElement`, `setSelectionRange`.

Nothing else — event data is read declaratively by decoders, and microtask/timer scheduling already lives in `watershed_lustre_ffi.mjs`.

### Parent wiring (the whole integration)

```gleam
type Msg {
  // …
  EnsuredBody(Result(SharedText, String))
  Editor(textarea.Msg)
}

// update:
EnsuredBody(Ok(channel)) -> {
  let #(editor, fx) = textarea.init(channel)
  #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
}
Editor(inner) ->
  case model.editor {
    Some(editor) -> {
      let #(editor, fx) = textarea.update(editor, inner)
      #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
    }
    None -> #(model, effect.none())
  }

// view:
case model.editor {
  Some(editor) ->
    textarea.view(editor, [rows(10), class("editor"), placeholder("…")])
    |> element.map(Editor)
  None -> html.p([], [html.text("connecting…")])
}
```

## Rungs

**TA1 — promote the pure parts. ✅ done 2026-08-03.** Move `grapheme_diff` into `watershed_lustre/grapheme_diff`; add the UTF-16↔grapheme conversion helpers. Both are pure → gleeunit tests first (TDD is natural here: emoji, combining marks, prefix==suffix overlap, empty strings, conversion round-trips). `examples/text_lustre` re-imports the package module and deletes its copy. Exit gate: tests pass, example builds, net-negative example diff.

**TA2 — the triple, at example parity. ✅ done 2026-08-03.** `watershed_lustre/textarea` with `init`/`update`/`view` + accessors, covering snapshot discipline, diff-on-input, and error folding — everything the example does today, no caret work yet. Proof, LU1-style: rewrite `examples/text_lustre` on the component; its `InputChanged` arm, `snapshot`, `record`, and `editor_view` all delete, `smoke.gleam` still passes, two-tab `just server` script unchanged.

**TA3 — caret and selection preservation. ✅ done 2026-08-03.** Anchored selection tracking, `before_paint` restoration, UTF-16 conversion at the boundary, `UnknownAnchorTarget` fallback. Exit gate: two-tab manual script — type mid-document in tab A while tab B holds a caret before/at/after the edit point; B's caret must not jump. This is the rung that earns the word *component*.

**TA4 — IME composition guard. ✅ done 2026-08-03.** Freeze/diff/re-map per the design above. Exit gate: manual test with a CJK IME (macOS Pinyin or JS `compositionstart` simulation in `smoke.gleam`) plus a concurrent remote edit during composition.

**TA5 (deferred) — wrappers and cursors.** (a) `<watershed-textarea>` custom element via `lustre.component` over the same triple, once a story exists for passing the handle (likely `Document`-by-unsafe-property + `text_handle_of` Json, or a registry keyed by string); valuable because it opens non-Lustre hosts. (b) Shared cursors: `selection(model)` already exposes the grapheme range and anchors serialize via `anchor_to_json` — broadcast over presence/ripples and render peer selections with a mirror-div overlay (a `<textarea>` cannot render highlights). Both are additive; neither shapes the core.

## As-built notes (TA1–TA2)

Deviations from the plan above, and why:

- **`grapheme_offset`, not a private helper in `textarea`.** The conversion is
  its own module (`to_utf16` / `from_utf16`) so TA1 could test it. It reuses
  `watershed/rich_text/utf16.length` rather than adding the planned
  `utf16_length` FFI one-liner — that function already exists in the root
  package. TA3's `textarea_ffi.mjs` is therefore just `restore_selection`.
  An offset landing *inside* a cluster snaps backwards to that cluster's start.
- **gleeunit, and the package now declares `gleam >= 1.11`.** `watershed_lustre`
  had no test suite at all; startest (the root package's harness) pins
  `gleam_stdlib < 1.0` transitively and cannot be shared here. Tests use the
  built-in `assert`, hence the version floor. `just test` now runs both suites.
- **`watershed_lustre/manifest.toml` pinned `spillway` at an older commit than
  the root package**, so the package and both Lustre examples failed to compile
  against `watershed`'s current source (`types.User` vs `token.User`). Synced to
  the root's commit; this was broken on `main` before any of this work.
- **The example bootstrapped too early.** `ensure_text` fired from `GotHandle`,
  before the handshake, and `create_text` requires a ready connection — so the
  browser app failed at startup with the textarea permanently disabled, also
  before any of this work. Moved to the `Connected(Ok)` arm. This was blocking
  TA2's exit gate, not caused by it.
- **The example keeps `record` and a second `subscribe_text`.** Append and the
  pinned anchor are app-owned mutations that still need error folding and an
  anchor refresh; a channel fans out to every subscriber, so the app's
  subscription coexists with the component's. `editor_view` survives as ~12
  lines of pure presentation plus the `Some`/`None` branch — the *bridge* left,
  not the markup.
- **`channel(model)` accessor added**, not in the plan's surface: the parent
  needs the handle back for exactly those app-owned mutations. `selection` is
  deliberately absent until TA3 rather than shipped returning `None`.

Verified: 26 new unit tests plus the existing 864; example builds and bundles;
`smoke.gleam` passes against a live levee container; two browser tabs against
`docker compose up` converge through the component (grapheme-counted emoji,
joiner renders existing text on `init`, append and anchor work through
`textarea.channel`, anchor tracked 17 → 20 under a remote insert before it).

## As-built notes (TA3)

Deviations from the plan above, and why:

- **No `composing`/`frozen` fields yet.** They belong to TA4 and would sit
  unused; the model grew only `instance` and `selection`. `Selection` carries
  more than the plan's two anchors: the resolved grapheme `range` (what the
  `selection` accessor returns) and the `raw` UTF-16 pair (what gets written
  back on restore, and what an incoming selection event is compared against to
  skip the redundant re-anchor when `select`, `keyup`, and `mouseup` all fire
  for one interaction).
- **Every write goes through one `pin`.** The plan described local input,
  remote edit, and caret-only moves as three flows; they converge on "clamp a
  grapheme range, create both anchors, record it in both coordinate systems."
  `resolve` (anchors → range) and `anchor` (reported offsets → range) are the
  two ways in. This is why the `UnknownAnchorTarget` fallback is three lines:
  collapse onto the surviving edge and pin that.
- **Restoration is decided by string comparison, not by message kind.** A
  `KernelEvent` whose snapshot equals the rendered value is the local echo, so
  it restores nothing; a `UserInput` whose snapshot *differs* from the event's
  value is a rejected op, so it does. That covers the rejection path the plan
  didn't assign a caret story to, and makes "restore only when the value
  actually moved under the element" a single invariant rather than a rule per
  arm.
- **The caret decoders are deliberately total.** Lustre drops an event whose
  decoder fails, so a browser reporting `selectionStart` as `null` would cost
  the user a keystroke rather than an anchor refresh. `caret` falls back to a
  `-1` sentinel that `anchor` reads as "keep the anchors you have".
- **`utf16_length` FFI still not needed** (TA1 note stands), so
  `textarea_ffi.mjs` is only `restore_selection` — as the plan predicted.
- **`selectionchange` stayed off the list**, as specced. The four-event set
  (`select`/`keyup`/`mouseup`/`focus`) is what shipped; Lustre attaches
  listeners to the node rather than delegating from the root, so non-bubbling
  `focus` works without special handling.

Verified in two browser tabs against `docker compose up` (the loop in the
tooling note), with `🌊🌊ABCDE(ZZZ)FGHIJ`: a remote insert **before** B's caret
moved it to the same neighbours (`ABCDE|FGHIJ` → `🌊🌊ABCDE|FGHIJ`, offset 5 →
9, so the UTF-16 conversion is load-bearing); an insert **at** it left the caret
before the inserted text; inserts at **both edges** of a selected `ZZZ` left the
selection exactly `ZZZ`; deleting `ZZZ` remotely collapsed B's selection to a
caret where it had been; a remote edit while focus sat in another field did not
pull focus back. Grapheme-cluster integrity holds across the boundary (a ZWJ
family emoji, 8 code units, crosses correctly). 26 unit tests and the 864 root
tests still pass, and `smoke.gleam` still passes against a live levee container.

Known gap, documented rather than fixed: a blurred element keeps the offsets the
browser last gave it, so a remote edit that lands while the user is elsewhere
leaves the *browser's* caret stale until they next place it. The anchors keep
tracking; only the un-restorable DOM state drifts. Restoring it would mean
writing a selection into an unfocused element, which the plan ruled out.

Known pre-existing breakage left alone: `pnpm run build` in the examples fails
with "packages field missing or empty" — each example's `pnpm-workspace.yaml`
lacks a `packages:` key, which the installed pnpm requires. `pnpm install
--ignore-workspace` plus a direct `esbuild` call works around it. This breaks
`just deps` and `just build`; fixing it is a repo-wide tooling call.

## As-built notes (TA4)

Deviations from the plan above, and why:

- **Freezing the rendered value does not work, and the reason matters.** The
  plan assumed an unchanging value means no vdom patch. It doesn't: Lustre
  classes a `<textarea>` that has dispatched events as *controlled*
  (`is_controlled` in `lustre/vdom/diff`), and `diff_attributes` then emits the
  `value` property on **every** diff — `controlled || !property_value_equal(…)`
  — which the reconciler applies as a bare `node[name] = value`. So any
  re-render during a session overwrites the IME's provisional text whatever
  string the component picks. Verified in the browser: the first remote edit
  wiped a live composition even with the freeze in place.
  What ships instead: mid-composition the component renders the textarea with
  **no value binding at all** (`element.element("textarea", …)` rather than
  `html.textarea`, which prepends the property). There is then nothing for the
  vdom to re-apply. Removal is safe — `value` is a property, so the reconciler's
  removal path calls `removeAttribute(node, "value")`, which a textarea does not
  use, and `SYNCED_ATTRIBUTES.value` has no `removed` hook. The frozen string is
  still kept, as the diff base at commit and as the child text node (constant,
  so it produces no patch either).
- **`grapheme_diff.shift` is public, not a private helper.** The re-mapping is
  the one pure part of TA4, so it went where TDD could reach it — seven tests
  covering both directions, the clamp at zero, and range-order preservation.
  Upper-bound clamping was deliberately left out: an index past the end is a
  rejection the runtime should report, not one to quietly relocate.
- **Drift is measured once, before the op lands.** Applying the composition can
  move or delete the grapheme the site anchors to, so resolving the anchor again
  afterwards answers a different question. The first draft resolved it twice and
  would have mis-placed the caret whenever the composed edit overwrote its own
  site.
- **A `committed` field, not in the plan.** Browsers disagree on whether `input`
  fires before or after `compositionend`; the ones that fire it after report the
  same value again, and diffing it would re-apply the composition against a
  channel that has moved on — undoing any peer edit made during the session.
  Recording the committed value and suppressing exactly one echo covers it. Safe
  because any real keystroke produces a different value. This also makes the
  ordering browser-agnostic without decoding `isComposing`: the state machine
  (`composing` set by start, cleared by end) already distinguishes intermediates
  from the commit, and a genuinely stale `compositionend` value self-heals,
  because the following `input` diffs the remainder.
- **`UserSelect` is ignored during a session**, which the plan didn't specify.
  The IME fires `keyup` as it walks its own provisional text, and those offsets
  index a string the document has never seen.
- **`CompositionEnded` with no session in flight falls through to the ordinary
  input path** rather than being dropped, so a composition whose
  `compositionstart` never decoded still commits its text.

Verified in two browser tabs against `docker compose up`, driving real
`CompositionEvent`s (no CJK IME is available on this machine, which is the
simulation route the plan allowed). Tab B composes `pin` → 拼 at the end of
`ABCDEFGHIJ` while tab A inserts `🌊🌊` at the head: B's element keeps the
provisional text untouched through the remote edit, and the commit lands at
grapheme 12, not 10 — `🌊🌊ABCDEFGHIJ拼`, with B's caret at UTF-16 offset 15
(4 + 10 + 1), so both the op shift and the caret shift are load-bearing. The
Firefox-order trailing `input` was suppressed rather than undoing A's insert.
Also covered: a plain composition with no peer activity; composing over a
selection (the `Replace` path, 5 graphemes → 1); and a **negative** shift — a
peer deleting 5 graphemes before the site while B composes at the end, which
committed at the new end with the caret at offset 8. Both tabs converged every
time and the error banner stayed empty. TA3's caret preservation still holds
(caret 7 → 9 under a remote head insert, same neighbours). 33 unit tests, the
864 root tests, and `smoke.gleam` against a live levee container all pass.

Known gap, unchanged from the plan's v1 scope: if the *anchored* grapheme at the
composition site is itself deleted remotely, the anchor stops resolving and
drift falls back to zero, so the composed text lands where it was typed rather
than where the site moved. The CRDT still converges. Fixing it would mean
anchoring a span rather than a point.

## Testing strategy

- TA1 modules are pure — unit tests, TDD.
- `update` logic runs against a live runtime handle, so component-level behavior is proven the way every other watershed Lustre surface is: the rewritten example + `smoke.gleam` against `just server`, two-tab convergence scripts per rung above.
- Caret behavior is inherently manual/browser: keep a short checklist in the example README (type-while-remote-edits at the three caret positions; select-while-remote-insert at each edge; IME compose + remote edit).
