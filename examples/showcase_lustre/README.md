# showcase_lustre — four collaborative apps in one document

The examples galleries this borrows from — Liveblocks', PartyKit's — are *lists
of separate apps*: each demo gets its own document, its own connection, its own
roster. This is one document whose panels are separate apps.

That difference is the whole demo:

- **One connection, one handshake, four collaborative apps.** Switching panels
  is instant because nothing reconnects.
- **One presence roster across all of them.** "Dana is in the sudoku panel" is a
  sentence you can only say once presence is document-wide, and it is the most
  legible payoff here.
- **The document is a tree, and the tree is typed.** The root is a map of
  handles to sub-documents, each with its own schema and its own decode
  boundary.

## Running it

```sh
just server                       # floodgate on :4000
pnpm --dir examples/showcase_lustre install
pnpm --dir examples/showcase_lustre run build
pnpm --dir examples/showcase_lustre run serve   # then open http://localhost:8080
```

Open two tabs. Put them on *different* panels and watch the roster name both
panels; put them on the same one and watch it converge.

Each panel is also still its own app — `text_lustre`, `playlist_lustre`,
`sudoku_lustre`, `pixel_canvas_lustre` all run standalone exactly as before.
That is the property the composition is built around, not a leftover.

## How composition works

`showcase_lustre/doc_schema` declares one `ChildField` per panel. A child field
is a key whose value is a handle to a nested typed map carrying a *different*
phantom tag, so each panel's existing `doc_schema` works unchanged against its
own map — those fields were always scoped to the panel's tag rather than to
"the root".

Each panel is a nested MVU triple in its own package:

```gleam
let #(panel, fx) = text_component.init(doc, text_map)   // in the shell's update
let #(panel, fx) = text_component.update(panel, inner)
text_component.view(panel) |> element.map(TextMsg)      // in the shell's view
```

A panel's `init` takes a `TypedMap(Tag)` and never a root. Standalone, that map
happens to *be* the document's root; composed, it is a child of the showcase
root — and nothing in the panel can tell the difference. Each standalone `main`
is the showcase with one panel and no switcher.

## Two rules, both load-bearing

**1. Only the showcase schema touches the root map.** A panel that reaches for
`root_typed` shares one key namespace with three others, silently: the text
panel's `title` and the sudoku panel's `title` would be the same key.
`Document(Showcase)` makes the tag checkable, and `composition_test` asserts
root purity directly for what the types cannot catch.

**2. Document-scoped effects belong to the shell.** Anything whose API takes a
`Document` rather than a channel is document-wide no matter which panel calls
it. Three of them show up here:

- `presence` — one driver, always. Every driver broadcasts under the same
  ripple kind, so two panels each starting one would receive each other's
  envelopes; the `kind` check passes and only the payload decoder rejects them,
  *silently*. The shell runs one driver with a `Where` variant per panel and
  hands each panel its filtered peers.
- `go_offline` — it disconnects the document, so it stops all four panels at
  once. It cannot be scoped down to one panel (the connection is per-document),
  so it lives in the chrome, labelled as what it is.
- `auto_summarize` — one policy per document, stored in a slot rather than a
  list. A panel installing its own would set the threshold for the whole
  showcase, and with panels initialised lazily, *which* policy won would depend
  on the order someone clicked.

## Three things worth knowing

**The offline toggle partitions everything at once.** One click
partitions a text buffer, a sequence, a claims grid, and an OR-map; coming back
converges all four in one reconnect. `offline_partitions_every_panel_test`
asserts exactly that.

**The cold-document race runs four times.** `ensure_child` checks for a key and,
if absent, creates and sets — so two clients opening a *brand-new* document both
create a child map and last-write-wins settles one handle, orphaning the other.
This race predates the showcase; what is new is running it once per panel. It
converges, and the loss window is sub-second and before anyone has interacted,
so the design accepts it rather than inventing a bootstrap protocol.
`racing_clients_agree_on_one_set_of_children_test` pins the convergence.

**The canvas sets the log's pace for everyone.** Painting emits ops by the
thousand, into the same log as the text buffer and the playlist — so a client
who only wants to read the playlist still replays painting history to get there.
That is what the shell's `auto_summarize` threshold is for, and why it is not
decorative.

## What this does not do

No cross-panel *data* sharing. The panels share a connection, a roster, and a
document tree — not state. A cell in sudoku does not affect the playlist, and
pretending otherwise would need a story about cross-channel transactions that
watershed does not have. The claim here is composition of independent
collaborative apps, which is sufficient on its own.

## Tests

```sh
cd examples/showcase_lustre && gleam test
```

`composition_test` covers the structure — root purity, the cold-document race,
per-panel convergence from inside a child map, and the document-wide partition.
`roster_test` covers the presence payload, including the negative case: a
foreign envelope must not decode into a phantom peer.

Two things are deliberately not asserted, because they are not assertable from a
test. The pixel buffer is FFI-owned and the canvas element is drawn to rather
than diffed, so "the picture is right" is a manual check — what the tests assert
is the OR-map behind it. And the roster's panel labels are checked at the codec
rather than in a rendered DOM.
