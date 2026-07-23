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
optimistic value* by [`src/grapheme_diff.gleam`](src/grapheme_diff.gleam),
which finds the longest common grapheme prefix and suffix (via
`string.to_graphemes`, Unicode extended grapheme clusters) and emits the one
minimal edit the keystroke implies. Never a whole-document replace when a
narrower op exists; never a code-unit offset as a CRDT index.

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

## Bootstrapping — one channel, many tabs

The root map is typed ([`src/doc_schema.gleam`](src/doc_schema.gleam)) with one
plain field and one channel field:

```text
root ─┬─ "title" = "watershed shared document"
      └─ "body"  = handle ──▶ SharedText
```

Every tab calls `watershed_lustre.ensure_text` unconditionally on connect; it
creates and attaches a text channel only when the slot is empty, so tabs
converge on the *same* `body` instead of seeding rivals. Each tab subscribes
and snapshots immediately, so a joiner renders the existing text without
waiting for an edit.

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
