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

It also keeps your caret where you left it when a peer edits around you, and
keeps an IME composition alive through the same interruption — see
[Caret preservation](#caret-preservation) and [IME composition](#ime-composition)
below.

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
makes shared cursors possible; broadcasting them is what the presence wiring
below does.

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

## IME composition

Typing 拼音 or かな runs a *composition session*: the browser puts provisional
text in the element and only settles it when you pick a candidate. None of those
intermediates is an edit the document should see, and — the part that bites —
writing to the element's `value` mid-session cancels the session outright.

That last point is sharper in Lustre than it looks. A `<textarea>` that has
dispatched events is *controlled*, meaning its `value` property is re-applied on
every diff whether or not the string changed. So holding the rendered value
still is not enough; any re-render at all during a session would clobber the
provisional text. The component instead renders the textarea with **no value
binding at all** for the duration, leaving the vdom nothing to re-apply, and
remembers the string the element held when the session opened.

Committing then means reading the element's final value against that remembered
base — which is in the coordinates of a document that peers may have edited
since. Two questions come apart there. *What did the user type?* is answered by
the base: whatever now sits in the region the session opened over. *Where does
it go, and what does it replace?* is answered by anchors on **both ends** of
that region, resolved at commit. A peer inserting inside the composed-over
region moves its tail without moving its head, so a single offset cannot say
where it went — and a commit that assumed otherwise would replace an extent
nobody chose. The two answers meet as one op.

### Manual checklist

With two tabs and an IME active in tab B (macOS Pinyin, Windows Microsoft IME,
or `ibus`/`fcitx` on Linux):

| In tab B                              | In tab A                      | Expected in B                                        |
| ------------------------------------- | ----------------------------- | ---------------------------------------------------- |
| compose a word, don't commit           | nothing                       | grapheme count does **not** move while composing      |
| compose a word, commit                 | nothing                       | committed text lands once, as one op                  |
| compose a word, don't commit           | insert **before** the site    | your composition survives untouched                   |
| …then commit it                        | —                             | composed text lands **after** A's insert, not at the old offset |
| compose over a selection, commit       | nothing                       | the selection is replaced, not appended to            |
| compose at the end, don't commit       | **delete** text before it     | commit still lands at the end                         |
| compose over a selection, don't commit | **insert inside** it          | —                                                     |
| …then commit it                        | —                             | the whole selection is replaced, A's insert with it   |
| compose over a selection, don't commit | **delete inside** it          | —                                                     |
| …then commit it                        | —                             | the replace stops where the selection now stops       |
| compose over a selection, **escape** it | **insert inside** it         | nothing is sent; A's insert survives                  |

The third and fourth rows are the ones worth the trouble: they are the whole
reason the session is anchored rather than just frozen. The rows after them are
why it is anchored as a *span* — the region's two ends stop moving together the
moment a peer edits between them. If you have no IME to hand, the same sequences
can be driven with synthetic `CompositionEvent`s from the devtools console —
dispatch `compositionstart`, assign `textarea.value`, then dispatch
`compositionend`.

Composing over a selection replaces that selection *as it now stands*, so a
peer's concurrent edit inside it goes with the rest — the same thing typing over
a selection does. Escaping the session sends nothing at all, which is what keeps
that from becoming a delete-and-reinstate of text the peer had changed.

## Shared cursors

Open two tabs and you see the other's caret and selection, labelled and
coloured, moving as they move and shifting as either of you edits.

What travels is a pair of **anchors**, not a pair of offsets. An offset is
meaningless to a peer: by the time it arrives their replica has applied edits
yours had not, and the number points somewhere else. Anchors bind to content, so
the receiver resolves them against their own copy and lands where the sender
meant — the same property that keeps your own caret still under a remote edit.
The component hands its selection over as `textarea.Cursor` and takes peers'
back through `textarea.set_peers`; this app owns everything in between:

```gleam
// what rides on presence
type Editing {
  Editing(cursor: Option(textarea.Cursor))
}

// the roster arrives -> hand it to the component, with names and colours
PresenceEvent(event) -> {
  // `State` and `Changed` both carry the whole roster; the caret is keyed by
  // session id, so two tabs of one person draw two carets.
  let cursors = list.filter_map(entries, ...textarea.peer(id:, label:, colour:, cursor:))
  let #(editor, fx) = textarea.set_peers(editor, cursors)
  ...
}
```

Announcing is deliberately conditional on the cursor having *moved*. Anchors
compare by value, and re-anchoring after a remote edit yields the same anchors
whenever the caret tracked the same content — so a peer typing does not make
every client re-broadcast.

Drawing is the component's job, because a `<textarea>` will not do it: it
renders only its own text, and it will not even say where that text is — the
glyphs live in shadow DOM, with no API from offset to pixel. So `textarea.view`
returns a wrapper holding the textarea, an overlay, and a hidden **mirror**: the
same string in an ordinary element with the same typography, where a DOM `Range`
gives the answer and `getClientRects` splits a wrapped selection into one
rectangle per line for free.

> **`view` returns a wrapper, not the textarea.** Caller attributes still land
> on the `<textarea>`, so `class("editor")` styles what you expect. But a
> sibling selector reaching *out* of the editor now has to account for the extra
> element.

### Manual checklist

| In tab B                       | Expected in tab A                                  |
| ------------------------------ | -------------------------------------------------- |
| place a caret                  | thin coloured bar with B's name, at the same spot   |
| select a few words             | translucent band over exactly those words           |
| select across a line wrap      | one band per line, not one box over both            |
| put the caret on the first line | the name tag flips below it rather than being clipped |
| type before A's cursor          | A's own caret keeps its neighbours (see above)      |
| **in A**, type before B's caret | B's drawn cursor stays on the same text             |
| close tab B                    | B's cursor disappears at once against a server with presence, or within the ripple TTL (~6.5s) without one |

## The custom element host

[`element.html`](element.html) is the same editor with **no Lustre app behind
it**. It renders `<watershed-textarea>` — the component wrapped as a custom
element by
[`watershed_lustre/textarea_element`](../../watershed_lustre/src/watershed_lustre/textarea_element.gleam)
— and [`element_host.mjs`](element_host.mjs) is plain JavaScript: register the
element, connect with the `watershed_js` facade, and hand over the channel as
one property assignment.

```js
register();                       // once, before any <watershed-textarea>
editor.channel = text;            // the live SharedText handle
```

Everything the triple exposes as accessors comes back out as `CustomEvent`s —
`change` (`{value, length}`), `error` (`{message | null}`), and `cursor` (this
user's selection as anchors, ready to broadcast). Peer cursors go back in as
plain data on the `peers` property; this host rides the same presence driver
and wire shape as the Lustre app, so a tab of each interoperates — same
document, shared cursors across host kinds. Styling reaches the inner textarea
through `watershed-textarea::part(textarea)`.

The channel property is the one untyped seam in the whole stack: a live handle
cannot serialize, so it crosses as an opaque property value, shape-checked on
the component side before the single contained coercion. A Lustre host never
sees the seam — `textarea_element.element(channel:, attrs:)` is typed.

```sh
pnpm run build:element
pnpm run serve      # then open http://localhost:8080/element.html twice
```

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

Start a floodgate dev server from the repository root:

```sh
just integration-up   # seeds tenant "dev-tenant", listens on :4000
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
running `just integration-up` server, racing an emoji insert at the head of one client against
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
