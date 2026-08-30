# watershed JSON workspace — a tree of folders holding live JSON documents

A collaborative file tree as a [Lustre](https://lustre.build) single-page
app: create folders, drop JSON documents into them, and edit those documents
— objects, scalars, and numbers — with everyone in the room watching the
same tree and the same document update live. Open two or three tabs, build
a folder or two, create a document, and edit it from more than one tab at
once.

`SharedDirectory` and `JsonOt` are the only two kinds in this repository
with no example under `examples/` before this one — everywhere else they
only show up as website pages that call the facade directly. This app is
the first to put them together: **the tree is one `SharedDirectory`
channel, and every document inside it is a separate `JsonOt` channel whose
handle is stored as an ordinary directory *value*.** Creating a document is

```gleam
let assert Ok(json_document) = watershed.create_json_ot(document)
watershed.directory_set(
  tree,
  path,
  name,
  watershed.json_ot_handle_of(json_document),
)
```

and opening one is `directory_get` followed by `resolve_json_ot`. Every
other example in this repository stores a channel handle only on the root
map; this one stores handles anywhere in a tree, and the point worth seeing
is that a handle is an ordinary `Json` value that resolves the same way
from any slot, not a special case the root map alone gets.

## What it demonstrates

| Concern | Structure | Encoding |
| --- | --- | --- |
| Folders and document names | `SharedDirectory` | subdirectories are folders; a key's value is a `JsonOt` handle |
| A document's content | `JsonOt` (json0) | objects, scalar leaves, and read-only arrays |
| Who has which document open | ephemeral presence | `{ color, name, open_path }`, never written to the tree or a document |

### Document creation is last-write-wins, and that is on purpose

Creating a document is two steps — create a channel, then set its handle at
a directory key — and the *key* is an ordinary last-write-wins map slot.
Two clients concurrently creating `config` in the same folder each create
their own channel and each set the same key; the directory's merge keeps
exactly one handle, and the other client's channel becomes unreachable.
That is not an error, and neither creator sees one: the loser's channel
still works, it is just pointed at by nothing in the tree any more.
Channels are cheap, so an orphaned one costs nothing at runtime — there is
no repair pass and no coordination protocol, because none is needed.
`test/convergence_test.gleam`'s
`concurrent_same_name_document_creation_converges_on_one_handle_test` pins
this: both clients agree on the surviving handle, and the loser's own
handle still reads whatever it wrote.

Editing an existing document is a different story. `JsonOt` is a real OT
document, not a register: two clients editing *different* keys of the same
document while offline both keep their edits after reconnecting — a
register-valued map would have kept one whole document and dropped the
other. `number_add` sharpens the same point on one field: two concurrent
`+1`s land on `+2`, with no read-modify-write race to lose.

Two clients that replace the same value concurrently also converge. The
replacement that sequences first survives everywhere; reconnecting does not
change the tie-break because it comes from sequence order, not client identity.

### Deleting a folder does not delete the documents inside it

`directory_delete_subdirectory` removes a tree node — nothing more. The
`JsonOt` channels that lived under it keep running; they only stop being
*reachable* from the tree. A client with one of those documents already
open keeps its editor open, behind a banner that says the folder is gone,
rather than losing the document or the client's place in it mid-keystroke.
This is watershed's actual data model, not a bug this demo works around,
and `deleting_a_folder_does_not_break_an_already_open_document_test` pins
it: the channel keeps accepting edits, and both clients still see them,
even though `directory_has_subdirectory` now reports `False`.

### A directory instance is its creation, not only its path

Delete a folder and recreate it under the same path, and the recreated
folder is a *different instance* — not the same object come back. An edit
a client queued against the old instance while it was offline must not
land on the new one just because the path string matches. This is the
directory kernel's hierarchical-identity rule
(`src/watershed/directory_kernel.gleam`'s `is_message_for_current_instance`),
and `a_stale_write_queued_before_a_delete_and_recreate_is_dropped_test`
exercises it end to end: client B goes offline holding `/specs`, queues a
write to it; client A deletes and recreates `/specs` while B is gone; B
reconnects, and its stale write does not appear anywhere. Because the
public facade does not expose a live channel's internal `DirectoryState`
for a test to call `check_invariants` on, `test/directory_invariants_test.gleam`
pins the same rule one layer down, directly against `directory_kernel`, the
same seam the kernel's own test suite uses for the identical claim.

## The editor

The tree editor works on objects and scalar leaves only:

- A string, number, boolean, or null leaf is editable in place. A null leaf
  can only become a string from the UI — there is no type picker — which is
  enough to show the shape without building a full JSON authoring tool.
- An object gets an "add key" form (string or number) and a delete button
  on every member.
- A number additionally gets `+1`/`−1` buttons wired to `number_add`, the
  one op in this editor that beats last-write-wins arithmetic outright.
- **Arrays render read-only, all the way down** — an object nested inside
  an array does not get add/delete controls just because it is, itself, an
  object. `json_ot.gleam` already has `list_insert`/`list_delete`/`list_move`;
  wiring them into this editor is the natural upgrade path if this demo
  ever needs a list story, and it is deliberately left undone here.

A non-handle value written into the directory (from a bug, or a peer
running different code) renders as a corrupt row rather than crashing the
tree — `test/tree_test.gleam` pins that rendering rule against plain data,
no live channel required.

## Presence

Presence carries one fact: the path of the document a client currently has
open, alongside its colour and short name. The roster shows every
connected client; a document row in the tree shows a chip for every peer
who currently has that document open. Presence never touches the tree or a
document's content — it is exactly as ephemeral as every other example's
presence in this repository.

## Tests

```sh
gleam test            # convergence + directory invariants + pure render rules, no server and no browser
pnpm run smoke         # the divergent-edits-across-reconnect claim against a live floodgate server
```

- `test/tree_test.gleam` — the pure helpers in `tree.gleam` in isolation:
  path joining, breadcrumbs, deterministic folder-then-document row
  ordering, the corrupt-value marker, and the deleted-folder-covers-a-path
  predicate. No `Document`, no `SharedDirectory`, no `sluice`.
- `test/convergence_test.gleam` — two clients over the in-memory `sluice`:
  divergent edits on different keys of one document surviving a reconnect,
  same-path replacements choosing one sequenced winner, concurrent numeric
  increments landing on the sum, concurrent same-name document creation
  converging on one handle (with the loser's channel still readable), a folder
  delete leaving an already-open document alone, and a stale write queued
  before a delete-and-recreate being dropped.
- `test/directory_invariants_test.gleam` — the stale-write-after-recreate
  rule and a general nested folder/document scenario, pinned directly
  against `directory_kernel.check_invariants`, the seam the facade does not
  expose.
- `dev/json_workspace_lustre/smoke.gleam` drives two real `watershed` clients
  against a live floodgate server end to end: seeds the tree, creates a folder
  and a
  document, has both clients edit different keys while offline, and
  asserts both edits present on both clients after they reconnect.

## Run it

Start a floodgate dev server from the repository root:

```sh
just integration-up   # seeds tenant "dev-tenant", listens on :4000
```

Then, in this directory:

```sh
pnpm install          # phoenix + esbuild
pnpm run build        # gleam build --target javascript, then esbuild bundle
pnpm run serve        # serves index.html on http://localhost:8080
```

Open two or three browser tabs on <http://localhost:8080> — all against the
same document, either by leaving the URL as-is or by sharing a
`?document=...` query string across tabs. Create a folder in one tab and
watch it appear in the others; create a document, open it from a second
tab, and edit different keys from each side. Delete a folder that has a
document open in another tab and watch that tab keep working behind the
banner. Use the offline toggle to hold a tab's edits locally, then bring it
back and watch them land.

> The demo mints an HS256 dev JWT in the browser using the server's dev
> secret. This is for local dev only; a real deployment issues tokens from
> a backend and never ships the tenant secret to the client.
