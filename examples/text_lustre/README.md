# watershed text — SharedText demo

A collaborative, plain-text editor as a Lustre single-page app. Where
[`playlist_lustre`](../playlist_lustre) exercises a `SharedSequence`'s
convergent `move`, this example exercises the one DDS addressed by **grapheme
index into a live string**: `SharedText`.

## The whole-document-replace trap

A `<textarea>` only ever reports its *entire* new value on each `input` event.
The tempting bridge — write that whole string back to the CRDT as one
replace-the-document op — is correct in isolation and catastrophic under
collaboration: it clobbers every concurrent remote keystroke and makes the
sequence do maximum work for a single-character change. It also invites you to
address the CRDT by the browser's `selectionStart`, which is a UTF-16
code-unit offset, **not** a grapheme index — one emoji or combining mark and
the two disagree, so the op lands in the wrong place.

Instead, every `input` event is diffed against the channel's *current
optimistic value* by
[`watershed_lustre/grapheme_diff`](../../watershed_lustre/src/watershed_lustre/grapheme_diff.gleam),
which finds the longest common grapheme prefix and suffix (via
`string.to_graphemes`, Unicode extended grapheme clusters) and emits the one
minimal edit the keystroke implies. Never a whole-document replace when a
narrower op exists; never a code-unit offset as a CRDT index.

## The bridge is a component

Snapshot, diff, one minimal op, error folding — none of that lives in this app
any more. It is
[`watershed_lustre/textarea`](../../watershed_lustre/src/watershed_lustre/textarea.gleam),
a nested MVU triple: `init` takes the resolved channel, and the parent holds
the child model and routes its messages.

```gleam
EnsuredBody(Ok(channel)) -> {
  let #(editor, fx) = textarea.init(channel)
  #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
}
Editor(inner) -> {
  let #(editor, fx) = textarea.update(editor, inner)
  #(Model(..model, editor: Some(editor)), effect.map(fx, Editor))
}

// view
textarea.view(editor, [class("editor"), rows(10)]) |> element.map(Editor)
```

What remains here is what an app actually owns: connecting, the schema, layout,
diagnostics, and the two mutations the component does not perform — **Append**
and the pinned anchor, both reaching the channel through `textarea.channel`.
Editing the channel behind the component's back is safe: the channel fans out
to every subscriber, so the component re-snapshots itself a microtask later.

It also keeps your caret where you left it when a peer edits around you — see
[Caret preservation](#caret-preservation) below.

## Op coverage

All four text mutation families, against a single channel:

| UI                    | Call                              | Note                                                        |
| --------------------- | --------------------------------- | ----------------------------------------------------------- |
| **typing a char**     | `text_insert(text, i, v)`         | the diff yields an insert at grapheme `i`                   |
| **backspace / cut**   | `text_delete_range(text, s, e)`   | the diff yields a delete of `[s, e)`                        |
| **type over selection** | `text_replace_range(text, s, e, v)` | the diff yields one replace, not a delete + insert pair   |
| **Append**            | `text_append(text, v)`            | an explicit action in its own right, distinct from the diff |

Plus `subscribe_text`, which delivers a `TextChanged` carrying the full
post-edit optimistic string for local and remote edits alike — a state-shaped
event, so a peer's stale author index is never mistaken for the final position.

### Edits return `Result`, and that matters

Every text mutation returns `Result(Nil, String)`. A grapheme index can go
stale — a peer may edit between render and keystroke — and an explicit
out-of-bounds index is refused rather than clamped. The app renders the
runtime's own error message in a banner instead of asserting; it never uses
`let assert` on an edit.

## Pinned anchor

`text_anchor_at` pins a stable position that survives concurrent edits and
merges. The **Pin anchor at end** button anchors the current tail; as remote
edits insert or delete text *before* it, `text_resolve_anchor` reports its
shifted grapheme index, which the panel shows live. This is the primitive that
makes shared cursors possible — broadcasting them (presence) is deliberately
out of scope here.

## Caret preservation

The same primitive is what keeps the editor usable under collaboration. When a
peer's keystroke arrives, the component rewrites the `<textarea>`'s value — and
the browser leaves your caret at a raw UTF-16 offset into a string that just
changed, so it teleports. The component instead holds your selection as a pair
of anchors, resolves them after each remote edit, converts back to code units,
and writes the caret back from `effect.before_paint` — after the DOM is patched,
before the browser paints, so there is no visible jump. Restoration is skipped
when the element isn't focused: stealing focus to place a caret is worse than
losing the position.

Two association conventions are baked in, matching ProseMirror and Yjs. A
**collapsed caret** hangs off the preceding grapheme, so a remote insert exactly
at it leaves your typing position *before* the inserted text. A **range** hugs
its content, so an insert at either edge lands outside the selection while an
interior edit grows or shrinks it.

### Manual checklist

Caret behaviour is a browser property, so it is checked by hand. With two tabs
on the same document and text like `🌊🌊ABCDE(ZZZ)FGHIJ`:

| In tab B                | In tab A                     | Expected in B                             |
| ----------------------- | ---------------------------- | ----------------------------------------- |
| caret mid-document       | insert **before** it          | caret keeps the same neighbours, not the same offset |
| caret mid-document       | insert **at** it              | caret stays *before* the inserted text     |
| caret mid-document       | insert **after** it           | caret does not move                        |
| select `ZZZ`             | insert at the **head** edge   | selection is still exactly `ZZZ`           |
| select `ZZZ`             | insert at the **tail** edge   | selection is still exactly `ZZZ`           |
| select `ZZZ`             | **delete** `ZZZ`              | selection collapses to a caret where it was |
| focus elsewhere on the page | any edit                   | focus is **not** pulled back to the textarea |

Use an emoji or a combining mark for at least one insert — that is where a
code-unit offset and a grapheme index disagree, and where a bridge that skipped
the conversion silently lands the caret in the wrong place.

## Bootstrapping — one channel, many tabs

The root map is typed ([`src/doc_schema.gleam`](src/doc_schema.gleam)) with one
plain field and one channel field:

```text
root ─┬─ "title" = "watershed shared document"
      └─ "body"  = handle ──▶ SharedText
```

Every tab calls `watershed_lustre.ensure_text` unconditionally once the
handshake completes; it creates and attaches a text channel only when the slot
is empty, so tabs converge on the *same* `body` instead of seeding rivals.
Attaching a channel needs a ready connection — the document handle arrives
first, and is good for reads and optimistic edits, but not yet for creating a
channel — so this waits for `Connected` rather than firing at `GotHandle`.
`textarea.init` subscribes and snapshots immediately, so a joiner renders the
existing text without waiting for an edit.

## Prerequisites

Start a levee dev server from the `levee` repo:

```sh
just server   # registers tenant "dev-tenant", listens on :4000
```

## Run it

```sh
cd examples/text_lustre
pnpm install
pnpm run build
pnpm run serve      # http://localhost:8080
```

Open two browser tabs. Type in one and watch the characters appear in the
other; type at the same spot from both at once and watch the edits reconcile
grapheme-for-grapheme. Each tab joins as a distinct `web-XXXX` user, so they
are genuinely separate connections.

The **Force reconnect** button drops the socket mid-session — type during the
reconnect and nothing is lost.

## Headless smoke test

[`src/smoke.gleam`](src/smoke.gleam) drives two clients from Node against a
running `just server`, racing an emoji insert at the head of one client against
a combining-mark insert at the tail of the other:

```sh
cd examples/text_lustre
pnpm run smoke
# → SMOKE PASS: concurrent grapheme edits converged
```

`pnpm run smoke` bundles `dist/smoke.mjs` and runs `node smoke/run.mjs` (which
supplies a `WebSocket` global for phoenix.js). It asserts:

- **convergence** — both clients land on the same string;
- **grapheme integrity** — the emoji (🌊) and combining sequence (é) each
  survive intact, never split;
- **append survival** — an append survives the concurrent race;
- **bounds rejection** — an out-of-bounds insert is refused, not clamped;
- **anchor movement** — an anchor pinned at grapheme 5 moves right after text
  is inserted before it.

## Build check

```sh
gleam build --target javascript   # from this directory
```
