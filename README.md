# watershed

Collaborative data structures for Gleam. A watershed document is a collection
of data stored in those structures; your application decides what the data
means. Many people can edit the same document at once. Watershed applies each
edit locally the moment it happens, sequences it through a server, and
converges every client on the same state — across concurrent edits, dropped
connections, and reloads.

It runs on both Gleam targets from one codebase: an OTP actor on the BEAM, and
the browser via the JavaScript target ([Lustre bindings](watershed_lustre)
included). It speaks the Fluid Framework wire protocol, so it works against any
Fluid-compatible sequencing service — [floodgate](https://floodgate.tylerbutler.com),
[levee](https://github.com/tylerbutler/levee), or Fluid Framework's own
[routerlicious](https://github.com/microsoft/FluidFramework/tree/main/server/routerlicious).

**[Guide](https://watershed.tylerbutler.com/guide)** ·
**[Data structures](https://watershed.tylerbutler.com/structures)** ·
**[Live demos](https://watershed.tylerbutler.com)**

For website builds and Cloudflare Workers deployment, see
[`website/README.md`](website/README.md).

## Install

watershed is not on Hex yet. Add it to your `gleam.toml` as a git dependency,
pinned to a commit — a branch ref is not a pin, and projects that resolve on
different days will land on different revisions:

```toml
[dependencies]
watershed = { git = "https://github.com/tylerbutler/watershed", ref = "<commit-sha>" }
```

[`watershed_lustre`](watershed_lustre) ships from this same repository, so Lustre
apps take it with a `path` into the clone (Gleam 1.18 or newer):

```toml
watershed_lustre = { git = "https://github.com/tylerbutler/watershed", ref = "<commit-sha>", path = "watershed_lustre" }
```

That pulls `watershed` along with it; declare `watershed` yourself only if you
also use it directly. Pin both to the same commit.

## Quick start

```gleam
import gleam/erlang/process
import gleam/json
import watershed/channel.{type ChannelEvent}
import watershed_beam

type Msg {
  MapChanged(ChannelEvent)
}

pub fn main() {
  // Blocks until the op history has replayed locally.
  let assert Ok(document) =
    watershed_beam.connect(
      host: "127.0.0.1",
      port: 4000,
      tenant: "flow-co",
      document: "flowboard",
      token: token,
      user_id: "ada",
    )
  let board = watershed_beam.root(document)
  let events = watershed_beam.subscribe(board)
  let selector =
    process.new_selector()
    |> process.select_map(events, MapChanged)

  // Subscribe first: this local write emits immediately.
  watershed_beam.set(board, "title", json.string("Q3 sprint board"))

  // The same subject also receives remote changes as they are applied.
  let MapChanged(_event) = process.selector_receive_forever(selector)
}
```

The default `watershed` facade is for JavaScript. It takes a
`WatershedConfig` and an
`on_ready` callback instead of blocking, and delivers events to callbacks rather
than a `Subject`. On the BEAM, import `watershed_beam` as shown above.
Everything below the facade is the same code. See the [connect
guide](https://watershed.tylerbutler.com/guide/connect) for both.

## SharedTree runtime (experimental)

Watershed supports fixed objects, dynamic maps, named recursive arrays,
Identifier fields, and explicit schema evolution for the object/map subset on
JavaScript and BEAM.
Interoperability coverage
uses Fluid Framework **3.1.0** and the pinned Floodgate service. The gate
compares upstream, JavaScript, and BEAM authors, reconnects pending edits, and
loads and continues editing across object, map, and schema-evolution summary
matrices. This claim applies to the declared profile, not arbitrary Fluid
documents, services, or package versions.

Identifier fields contain ordinary strings. Omit an Identifier when you insert
a new object and the document compressor generates one; provide a string when
you need an external ID. Reads return that string unchanged. An attached
Identifier field is read-only, so changing an ID requires replacing its parent
object. Duplicate custom strings are allowed and do not make two nodes the same
node: moves, references, and `NodeInDocument` constraints still use node
identity.

Messages can compress known IDs with the author's session and allocation
range. Summaries resolve finalized IDs from their stored compressor state and
have no author session. Loading, reading, moving, and validating nodes never
generate replacement IDs.

The Identifier profile does not add incremental FieldBatch chunks, arbitrary
container layouts, `Tree.shortId`, an identifier index, global uniqueness
checks, a detached JavaScript-style node builder, or UUIDv5 healing.
Transactions are synchronous and limited to one tree. Undo and redo use
application-owned, runtime-local revertible handles; Watershed does not provide
or persist an undo stack.

The [profile manifest](test/fixtures/shared_tree/profile.json) records upstream
commit `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` and Floodgate commit
`0eb493fc46d1bb9baf1151a6ccdde93544e057e7`. Its `oldestSupportedClient: 2.117.0`
field is container metadata, not a claim of tested Fluid 2.x compatibility.
The default layout uses alias `root` -> datastore `A`, a bootstrap map at `/A/root`
with a `"tree"` handle, and a tree at `/A/_C`.

The schema subset includes nested objects, required and optional fields,
dynamic maps, and string, finite number, boolean, and null leaves. The M2
profile uses `MapRoot`, `DynamicMap`, and `MapPoint`. Map values can contain
leaves, fixed objects, and nested `DynamicMap` nodes. Map keys are arbitrary
strings, including empty, Unicode, numeric-looking, and prototype-like keys.
Key and entry reads use canonical UTF-8 key order.

Ordinary connections can load published upstream SharedTree summaries for this
fixed container and schema profile without a caller-supplied seed. The checked
`runtime_core.BootstrapSeed` and `connect_via_seed` remain available for injected
transports. Both targets can also create new containers for this profile with
`create_tree_container`. Use `create_tree_container_with_layout` for declared
additional datastores and channels. Arbitrary Fluid factories remain unsupported.

On either facade, `resolve_root(document)` returns the checked bootstrap
`SharedMap` or an error before readiness. Its handle preserves the full route,
such as `/A/root`. Existing `root(document)` still names the native
`/watershed/root`; use `resolve_root` for routed seeds. Document-only handle
resolution requires an absolute marker. Use
`bind_handle(document, source_handle, value)` to resolve a relative marker in
its source channel's datastore.

After readiness, use `resolve_root(document)`, `get(root, "tree")`, and
`resolve_tree(document, handle, definition)` to reach an existing tree.
`definition` pairs a strict view schema with a hand-authored decoder. The
facades expose one application tree type, `SharedTree(schema, record)`.
The earlier path-and-`TreeValue` read and edit calls were removed; this is a
breaking migration for the experimental API. There is no `TypedTree` wrapper
or raw application escape.

### Typed SharedTree application API

The schema tag, decoded record, and construction input serve different jobs.
The tag prevents a field from one schema being used with another. The record is
an immutable snapshot. The input tells a builder what to insert and can omit an
Identifier that the runtime owns. This declaration reads the generated `id`
but never accepts it in `CardInput`:

```gleam
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed
import watershed/container
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types

const card_type = "example.Card"
const card_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"example.Card\":{\"kind\":{\"object\":{\"deletedAt\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.null\"]},\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"status\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.null\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"example.Card\"]}}"

pub type CardSchema

pub type Card {
  Card(
    id: String,
    title: String,
    note: Option(String),
    status: Nil,
    deleted_at: Option(Nil),
  )
}

pub type CardInput {
  CardInput(title: String, note: Option(String))
}

pub fn title() -> typed.Field(CardSchema, String, typed.Required) {
  typed.required("title", typed.string())
}

pub fn note() -> typed.Field(CardSchema, String, typed.Optional) {
  typed.optional("note", typed.string())
}

pub fn card_builder() -> typed.Builder(CardSchema, CardInput) {
  let assert Ok(value) =
    typed.builder(card_type, fn(input: CardInput) {
      let note = case input.note {
        None -> []
        Some(value) -> [#("note", types.StringValue(value))]
      }
      Ok(types.ObjectValue(card_type, [
        #("title", types.StringValue(input.title)),
        #("status", types.NullValue),
        ..note
      ]))
    })
  value
}

pub fn card_definition() -> typed.Schema(CardSchema, Card) {
  let assert Ok(view) = schema.view_from_string(card_schema)
  let assert Ok(codec) =
    typed.node(card_type, fn(value) {
      let assert types.ObjectValue(_, fields) = value
      use id <- result.try(required(fields, "id", typed.string()))
      use title <- result.try(required(fields, "title", typed.string()))
      use note <- result.try(optional(fields, "note", typed.string()))
      use status <- result.try(required(fields, "status", typed.null()))
      use deleted_at <- result.try(optional(fields, "deletedAt", typed.null()))
      Ok(Card(id:, title:, note:, status:, deleted_at:))
    })
  let assert Ok(value) = typed.schema(view, codec)
  value
}

fn required(
  fields: List(#(String, types.TreeValue)),
  key: String,
  codec: typed.Codec(value),
) -> Result(value, typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> typed.decode(codec, value)
    Error(Nil) -> Error(typed.MissingRequired(key))
  }
}

fn optional(
  fields: List(#(String, types.TreeValue)),
  key: String,
  codec: typed.Codec(value),
) -> Result(Option(value), typed.Error) {
  case list.key_find(fields, key) {
    Ok(value) -> typed.decode(codec, value) |> result.map(Some)
    Error(Nil) -> Ok(None)
  }
}
```

Creation validates the declaration and builder before it allocates a document.
Resolution checks the current stored schema. Reads and edits repeat those
runtime checks because a remote schema change can invalidate a handle even
though its Gleam tags still match:

```gleam
pub fn create(config: container.CreateConfig) {
  watershed.create_tree_container(
    config,
    card_definition(),
    card_builder(),
    Some(CardInput("Draft", None)),
  )
}

pub fn resolve(
  document: watershed.Document(root),
  handle: Json,
) -> Result(watershed.SharedTree(CardSchema, Card), typed.Error) {
  watershed.resolve_tree(document, handle, card_definition())
}

pub fn read_and_rename(
  tree: watershed.SharedTree(CardSchema, Card),
) -> Result(Card, typed.Error) {
  use root <- result.try(watershed.tree_root(tree))
  case root {
    None -> Error(typed.MissingRequired("$root"))
    Some(root) -> {
      use old_title <- result.try(watershed.tree_get(root, title()))
      use _note <- result.try(watershed.tree_get_optional(root, note()))
      use _ <- result.try(
        watershed.tree_set(root, title(), old_title <> " reviewed"),
      )
      watershed.tree_read(root)
    }
  }
}

pub fn watch(
  tree: watershed.SharedTree(CardSchema, Card),
) -> watershed.SubscriptionToken {
  watershed.subscribe_tree(tree, fn(_event) { Nil })
}

pub fn watch_history(
  tree: watershed.SharedTree(CardSchema, Card),
) -> watershed.SubscriptionToken {
  watershed.subscribe_tree_commits(tree, fn(_event) { Nil })
}
```

`tree_read` and `tree_read_root` return record snapshots. `TreeNode`,
`TreeArray`, and `TreeMap` are live handles to native forest identities. A
captured node follows that identity through moves and refuses edits after
removal or replacement; an equal record or repeated application ID does not
retarget it. Index-based array operations use the current sequence when the
call runs. Use node-based remove and move operations when an action must stay
bound to the captured item.

A Fluid handle value names a channel or datastore route. It is data stored in
the tree, not a `TreeNode`, and it retains its source datastore context.
Closing the document invalidates live tree handles. Reload creates a new
runtime, so resolve the tree again and capture fresh nodes; committed data
reloads, but node and revertible handles do not.

Missing optional fields decode as `None`. A present null leaf decodes as
`Nil`, so `Some(Nil)` differs from absence. A missing required field reports
`MissingRequired`. Schema incompatibility, removed nodes, disposed branches,
and closed runtimes return errors without changing visible state.

Subscriptions remain tree-level. This typed API adds no per-field event
promise. Existing change subscriptions, commit subscriptions, settlement
callbacks, transactions, branches, and application-owned history all take the
same `SharedTree(schema, record)`.

To inspect or upgrade an incompatible stored schema, use `open_tree` with the
next typed definition. Reads and edits remain unavailable until compatibility
permits them:

```gleam
pub fn open_or_upgrade(
  document: watershed.Document(root),
  handle: Json,
  next_definition: typed.Schema(schema, record),
) -> Result(watershed.SharedTree(schema, record), typed.Error) {
  use candidate <- result.try(
    watershed.open_tree(document, handle, next_definition),
  )
  use status <- result.try(
    watershed.tree_compatibility(candidate)
    |> result.map_error(typed.AccessFailed),
  )
  use _ <- result.try(case status.can_view {
    True -> Ok(Nil)
    False ->
      watershed.tree_upgrade_schema(candidate)
      |> result.map_error(typed.AccessFailed)
  })
  watershed.resolve_tree(document, handle, next_definition)
}
```

`can_view`, `can_upgrade`, and `is_equivalent` answer different questions.
An ordinary wider view is not readable until its explicit upgrade applies.
An equivalent upgrade is a no-op: it allocates no revision or IDs, submits no
message, and emits no event. Unsupported or invalid local upgrades leave state
unchanged.

Each tree handle keeps the view passed to `open_tree` or `resolve_tree`.
Reads and writes recheck that view against the current visible schema. A handle
that was valid can become unavailable after another client applies an
incompatible upgrade. The document stays usable, and a fresh compatible handle
can continue editing.

`subscribe_tree` reports `SchemaChanged(local)` for a visible schema change and
keeps `TreeChanged(local)` for data changes. If one completed transition changes
both, subscribers receive the schema event first and observe the final state.
Summaries pair the sequenced schema with the sequenced forest, history, and
compressor state, so a pending local upgrade does not leak into a published
snapshot.

Schema upgrades participate in the same sequenced conflict rules as data.
A concurrent data edit can win and reduce the local upgrade to an acknowledged
empty change. Watershed does not merge or retry losing schemas. Inspect
compatibility again and request a new upgrade from the current stored schema.

The supported authoring profile permits additive object/map changes: optional
object fields, wider allowed types for existing object fields and map entries,
required-to-optional field or root changes, wider root types, and definitions
needed by those transitions. Upstream `can_upgrade` describes the schema
relation; Watershed's authoring restrictions can still reject a transition
such as a node-kind replacement. This profile covers initialized documents and
does not broaden creation or initialization.

### SharedTree transactions

Both facades support synchronous transactions on one SharedTree. The callback
uses the ordinary read and edit functions, and its `Result` decides whether the
scope commits or aborts:

```gleam
import gleam/option.{None, Some}
import gleam/result
import watershed
import watershed/tree/typed

pub fn commit_title(
  tree: watershed.SharedTree(schema, record),
  title: typed.Field(schema, String, cardinality),
) -> Result(Nil, watershed.TreeTransactionError(typed.Error)) {
  watershed.tree_transaction(tree, [], fn(transaction_tree) {
    use root <- result.try(watershed.tree_root(transaction_tree))
    case root {
      Some(root) -> watershed.tree_set(root, title, "committed")
      None -> Error(typed.MissingRequired("$root"))
    }
  })
}
```

The callback error stays typed inside `Aborted`. Runtime, setup, constraint,
composition, and transport failures use `TransactionFailed(String)`:

```gleam
import gleam/result
import watershed
import watershed/tree/typed

pub type DraftAbort {
  EditFailed(typed.Error)
  InvalidTitle
}

pub fn abort_draft(
  tree: watershed.SharedTree(schema, record),
  title: typed.Field(schema, String, cardinality),
) -> Result(Nil, watershed.TreeTransactionError(DraftAbort)) {
  watershed.tree_transaction(tree, [], fn(transaction_tree) {
    let assert Ok(Some(root)) = watershed.tree_root(transaction_tree)
    use _ <- result.try(
      watershed.tree_set(root, title, "temporary")
      |> result.map_error(EditFailed),
    )
    Error(InvalidTitle)
  })
}
```

Use `NodeInDocument` when the commit is valid only while a selected node remains
in the document:

```gleam
import watershed
import watershed/tree/typed

pub fn update_while_item_exists(
  tree: watershed.SharedTree(schema, record),
  title: typed.Field(schema, String, cardinality),
) -> Result(Nil, watershed.TreeTransactionError(typed.Error)) {
  watershed.tree_transaction(
    tree,
    [watershed.NodeInDocument(["items", "0"])],
    fn(transaction_tree) {
      let assert Ok(Some(root)) = watershed.tree_root(transaction_tree)
      watershed.tree_set(root, title, "item still exists")
    },
  )
}
```

Nested calls on the same tree use savepoints. Inner success remains part of the
outer scope; inner abort restores its savepoint and lets the outer callback
continue. A successful outer scope with visible edits emits one local
`TreeChanged` event and submits one composed network commit. Intermediate
edits, inner scopes, aborts, and no-op transactions emit no public data event;
an outer abort submits nothing.

`NodeInDocument` checks identity, not the original path. Moving the node keeps
the constraint valid. A missing or detached node fails before the callback
runs. Every client checks the constraint again after sequencing, so a removal
that sequences first suppresses the constrained edits instead of relying on a
local preflight approximation.

Asynchronous and cross-tree transactions, schema upgrades inside transactions,
the alpha `noChange` constraint, transaction metadata, and post-processors are
not supported.

### SharedTree undo and redo

`subscribe_tree_commits` reports local default, undo, and redo commits on both
facades. An eligible local commit supplies a one-shot factory during the
callback. Call that factory before the callback returns, then store the handle
in application state. Remote and schema commits do not supply a factory.

Use `tree_get_revertible(event, on_disposed)` when the application must release
state associated with a revertible. It performs the same one-shot acquisition
and calls `on_disposed` once with the exact acquired handle after disposal is
installed. Disposal includes `tree_revert(handle, True)`, explicit disposal,
disposing or merging away the handle's local branch, and closing the document.
The original zero-argument factory remains available for callers that do not
need a disposal notification.

Use `tree_revertible_revision(handle)` on either facade to read the commit's
stable identity. You can still read it after disposal or document close;
the accessor does not send an actor request.

The following pattern uses one subscription. The application routes
`UndoMessage` values through its existing state owner, such as an actor or an
application update loop. The state owner holds the mutable undo and redo
stacks; Watershed only creates and reverts handles.
Queue dispatched messages so a commit callback does not reenter `update_undo`
during a revert.

```gleam
import gleam/list
import gleam/option.{None, Some}
import watershed
import watershed/tree/types

pub type UndoState {
  UndoState(
    undo: List(watershed.TreeRevertible),
    redo: List(watershed.TreeRevertible),
  )
}

pub type UndoMessage {
  Captured(types.TreeCommitKind, watershed.TreeRevertible)
  Settled(types.TreeCommitOutcome)
  UndoRequested
  RedoRequested
}

pub fn new_undo_state() -> UndoState {
  UndoState(undo: [], redo: [])
}

pub fn subscribe_undo(
  tree: watershed.SharedTree(schema, record),
  dispatch: fn(UndoMessage) -> Nil,
  report_error: fn(String) -> Nil,
) -> watershed.SubscriptionToken {
  watershed.subscribe_tree_commits(tree, fn(event) {
    let watershed.TreeCommitEvent(kind, local, factory, settlement) = event

    case local, factory, settlement {
      True, Some(acquire), Some(register) ->
        case acquire() {
          Error(error) ->
            report_error("Could not acquire revertible: " <> error)
          Ok(handle) ->
            case register(fn(outcome) { dispatch(Settled(outcome)) }) {
              Ok(Nil) -> dispatch(Captured(kind, handle))
              Error(error) -> {
                report_error("Could not register settlement: " <> error)
                case watershed.tree_dispose_revertible(handle) {
                  Ok(Nil) -> Nil
                  Error(dispose_error) ->
                    report_error(
                      "Could not dispose unregistered revertible: "
                      <> dispose_error,
                    )
                }
              }
            }
        }
      False, _, _ | _, None, _ | _, _, None -> Nil
    }
  })
}

fn dispose_all(
  handles: List(watershed.TreeRevertible),
  report_error: fn(String) -> Nil,
) -> Nil {
  list.each(handles, fn(handle) {
    case watershed.tree_dispose_revertible(handle) {
      Ok(Nil) -> Nil
      Error(error) -> report_error("Could not dispose redo handle: " <> error)
    }
  })
}

pub fn update_undo(
  state: UndoState,
  message: UndoMessage,
  report_error: fn(String) -> Nil,
  report_settlement: fn(types.TreeCommitOutcome) -> Nil,
) -> UndoState {
  case message {
    Captured(types.DefaultCommit, handle) -> {
      dispose_all(state.redo, report_error)
      UndoState(undo: [handle, ..state.undo], redo: [])
    }
    Captured(types.UndoCommit, handle) ->
      UndoState(..state, redo: [handle, ..state.redo])
    Captured(types.RedoCommit, handle) ->
      UndoState(..state, undo: [handle, ..state.undo])
    Settled(outcome) -> {
      report_settlement(outcome)
      state
    }
    UndoRequested ->
      case state.undo {
        [] -> state
        [handle, ..rest] ->
          case watershed.tree_revert(handle, True) {
            Ok(Nil) -> UndoState(..state, undo: rest)
            Error(error) -> {
              report_error("Could not undo commit: " <> error)
              state
            }
          }
      }
    RedoRequested ->
      case state.redo {
        [] -> state
        [handle, ..rest] ->
          case watershed.tree_revert(handle, True) {
            Ok(Nil) -> UndoState(..state, redo: rest)
            Error(error) -> {
              report_error("Could not redo commit: " <> error)
              state
            }
          }
      }
  }
}
```

A new default commit disposes and clears the redo stack. Reverting a default
or redo handle emits an undo commit, whose acquired handle goes onto the redo
stack. Reverting an undo handle emits a redo commit, whose handle goes onto the
undo stack. The example consumes each popped handle with
`tree_revert(handle, True)`. `tree_revert(handle, False)` keeps a handle valid,
and the pinned contract permits repeated reversion of that same target.

Handles belong to one runtime, document, and tree address. They survive
disconnect and reconnect in that runtime because reconnect keeps the in-memory
registry and retained history. Closing the runtime disposes them. Summary
reload preserves the committed undo or redo state but creates a new runtime,
so old handles and application stacks do not reload. Dispose unused handles to
release retained history; a second disposal returns an error.

One outer transaction commit can supply one revertible after the transaction
finishes. `tree_revert` during an active transaction is unsupported. Persisted
stacks, schema undo, remote-commit undo, cross-tree atomic undo, public
branches, `noChange`, custom revert metadata, clone-to-view, and `revertTo`
remain outside the profile. The Lustre history/checklist adapter uses this
lifecycle; additional UI bindings are separate consumer work.

### SharedTree local branches

`tree_fork` creates an in-memory checkout of the same runtime, document, and
tree. Read and edit that checkout with the existing tree, map, array, move,
Identifier, transaction, subscription, and revertible APIs. A fork does not
submit tree operations until it is merged.

```gleam
import gleam/option.{None, Some}
import gleam/result
import watershed
import watershed/tree/typed

pub type DraftError {
  TreeError(typed.Error)
  BranchError(String)
}

fn draft_root(
  tree: watershed.SharedTree(schema, record),
) -> Result(watershed.TreeNode(schema, record), DraftError) {
  use root <- result.try(
    watershed.tree_root(tree)
    |> result.map_error(TreeError),
  )
  case root {
    Some(root) -> Ok(root)
    None -> Error(TreeError(typed.MissingRequired("$root")))
  }
}

pub fn publish_draft(
  main: watershed.SharedTree(schema, record),
  title: typed.Field(schema, String, cardinality),
) -> Result(Nil, DraftError) {
  use draft <- result.try(
    watershed.tree_fork(main)
    |> result.map_error(BranchError),
  )
  let outcome = {
    use root <- result.try(draft_root(draft))
    use _ <- result.try(
      watershed.tree_set(root, title, "reviewed draft")
      |> result.map_error(TreeError),
    )
    use _ <- result.try(
      watershed.tree_rebase_onto(draft, main)
      |> result.map_error(BranchError),
    )
    watershed.tree_merge(main, draft, True)
    |> result.map_error(BranchError)
  }
  case outcome {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let _ = watershed.tree_dispose_branch(draft)
      Error(error)
    }
  }
}
```

Pass `True` to dispose the source after merge. Pass `False` when a workflow
must keep the source checkout for more edits or another merge:

```gleam
pub fn publish_in_stages(
  main: watershed.SharedTree(schema, record),
  title: typed.Field(schema, String, cardinality),
) -> Result(Nil, DraftError) {
  use draft <- result.try(
    watershed.tree_fork(main)
    |> result.map_error(BranchError),
  )
  let outcome = {
    use root <- result.try(draft_root(draft))
    use _ <- result.try(
      watershed.tree_set(root, title, "night")
      |> result.map_error(TreeError),
    )
    use _ <- result.try(
      watershed.tree_merge(main, draft, False)
      |> result.map_error(BranchError),
    )
    use _ <- result.try(
      watershed.tree_set(root, title, "compact")
      |> result.map_error(TreeError),
    )
    use _ <- result.try(
      watershed.tree_rebase_onto(draft, main)
      |> result.map_error(BranchError),
    )
    watershed.tree_merge(main, draft, True)
    |> result.map_error(BranchError)
  }
  case outcome {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let _ = watershed.tree_dispose_branch(draft)
      Error(error)
    }
  }
}
```

Undo and redo remain application-owned. Subscribe to commits on the branch,
acquire its one-shot revertible factory during the callback, and queue the
result through the same `UndoMessage` dispatch pattern above. Do not call the
application update loop directly from a commit callback. A branch registration
does not settle merely because the local forest changed. If its commit is
merged, the target commit can settle after sequencing; an accepted source
registration remains independent of the subscription that created it, but
disposing that source cancels its outstanding registrations.

Local checkouts pin ancestry and repair data in memory. Revertibles add their
own pins. Dispose unused handles and branches; descendants retain their own
pins and remain usable. Authoring and publication still require the ready
phase. Disconnect and reconnect in the same runtime preserve branches, pending
main origins, and live handles. Runtime close or a fresh summary load loses all
local branches, subscriptions, handles, and application stacks. Only merged
document state reloads and continues editing.

Branch schema authoring is unsupported. A schema change on main can make a
branch incompatible; an unsupported reconciliation fails atomically rather
than silently changing either checkout. Shared or persisted branches, branch
wire APIs, cross-runtime or cross-tree merge, historical checkouts, portable
handles, async transactions, offline authoring, automatic disk journaling, managed undo stacks,
clone-to-view, `revertTo`, and preview diffs remain outside this profile.

Use `tree_map_get`, `tree_map_set`, `tree_map_delete`, `tree_map_keys`, and
`tree_map_entries` on either facade. Each operation takes a path to the map;
single-entry operations take the key as a separate argument. Per-key edits,
recursive map values, reconnect, and full-summary reload are part of the M2
profile.

Unsupported versions, incompatible schemas, and corrupt input return explicit
errors. Failed bootstrap does not expose a writable partial document. Invalid
local edits leave the tree, pending edits, allocations, events, and outgoing
messages unchanged.

Manual `summarize` publishes a complete tree document when it is synchronized
and has its original routing and protocol metadata. Automatic summary policy
still skips tree documents. New tree edits require the ready phase: disconnected,
bootstrapping, and catching-up clients reject them without changing visible
state. Accepted local edits remain visible across a transport loss. Reconnect
keeps their core and compressor, replays the sequenced tail, waits for the old
submitting session's sequenced leave and the new join, and resubmits only edits
that the server has not accepted. Missing history or failed repair retains the
pending state with an explicit error; it does not report a synchronized tree.
Repeated recovery keeps earlier unacknowledged ID ranges ahead of newly
generated rollback ranges, before the edits that use them.
Authorization refusal stops reconnect with the pending tree still readable;
recoverable connection failures have a bounded, delayed retry and report
their cause through `connection_observation`. A replay error also suspends
recovery without discarding accepted local edits.
This reconnect path keeps state in memory. Explicit pending checkpoints also
support restart recovery as described below; neither path enables offline
authoring.
The combined service gate includes the six focused reconnect schedules on
each native target, the three-client editing matrix, and fresh summary readers.
SharedTree has no P2P mode; P2P tree creation and snapshot import return an
unsupported-channel error. A compatible service transport alone does not
establish SharedTree operation or persistence compatibility.

### Recover pending tree edits

Both native facades expose `pending_checkpoint(document)`. It flushes queued
submissions and returns a versioned JSON checkpoint for a persisted SharedTree
document, including pending array moves and subsequent edits. The checkpoint
retains the original compressor session, native node identities, authoring
history, submission identities, and the sequenced document base. It contains no
connection token.

Your application owns storage. Serialize the returned JSON and durably replace
the previous checkpoint in your chosen store. Local edits that the server has
not accepted must appear in the last successfully stored checkpoint to survive
a crash. Recovery also replays later server-accepted edits. This API does not
journal each edit automatically. Stop the old runtime before restoring, and
never run two copies of the same checkpoint concurrently.

Pass the parsed checkpoint to `connect_resuming` with fresh connection
credentials. The JavaScript facade takes the usual `WatershedConfig`, the
`checkpoint:` argument, and `on_ready:`; it returns
`Result(Document(root), String)`. The BEAM facade takes the usual labeled
connection arguments plus `checkpoint:` and waits before returning that same
result shape. Invalid, unsupported, or wrong-document checkpoints fail before
a transport opens. Recovery replays missing operations, waits for the old
session's leave and the new join, and resubmits only work not already accepted
by the server. A move accepted before the crash is acknowledged, not repeated.

A stored checkpoint can span a later reconnect of the original runtime.
Recovery recognizes accepted resubmissions by their logical batch identity and
complete contents, including peer rebases at the submission's authoring
sequence. It removes accepted prefixes and resubmits only the saved suffix.
After replay acknowledges all saved work, the runtime switches to a fresh
allocation session that includes later server-accepted IDs.

Reacquire typed tree and node handles after restart. Subscriptions, revertible
handles, and application undo stacks are not restored. Capture rejects active
transactions, unmerged local branches, detached graphs, pending attachments or
aliases, pending ordinary DDS edits, and incomplete replay rather than losing
that state. Settle or dispose those before capturing. The checkpoint is a
local recovery format, not a Fluid summary or a portable branch format.

`just shared-tree-recovery-interop` exercises disk capture, process kill, and
fresh-process restoration through pinned Floodgate for all JavaScript/BEAM
writer-reader pairs. Its 32 cells cover unsent moves, accepted-before-crash
moves, accepted edits newer than the checkpoint, and full or partial acceptance
after an intervening reconnect. Peer edits before resubmission and between
authoring and acceptance exercise historical rebase context. Each restored
writer continues editing and drains its pending queue. The eight delayed
cases also store another pending checkpoint and recover from a second crash.

### Build a graph in an open document

A ready, writable service document can grow beyond its bootstrap layout.
`create_data_store(document)` creates a detached datastore, and
`data_store_root(store)` returns its entry-point map. Use
`create_map_in(document, store)` and
`create_tree_in(document, store, definition, builder, initial_input)` to add
detached channels there. `create_tree` adds a detached tree to the bootstrap
datastore. The JavaScript and BEAM facades expose the same calls with matching
`Result` return types. Both also expose
`resolve_tree(document, value, definition)` and
`open_tree(document, value, definition)`,
`tree_handle_of(tree)`, and the immutable
`tree_revertible_revision(revertible)` accessor.

Detached creation is local. It sends no transport message, but tree
initialization still emits the ordinary local commit, schema, tree, and
settlement events. You can edit the new channels, subscribe to them, and use
revertibles before publication.

Publication is implicit. Store a handle to any detached channel in an attached
map, and Watershed attaches that channel and every detached datastore or
channel reachable from it before the referencing map operation. A handle keeps
its source route, so relative handles resolve in the source channel's datastore
rather than the map that happens to carry them.

The runtime validates the complete attachment graph before it commits local
state or submits any message. Completed single-tree transactions can publish a
new graph; an active transaction on the target tree is refused. Local branches
do not publish bindings until merge, and dropping a branch leaves its detached
targets local. Undo can restore an earlier handle while preserving independent
edits to the target. `tree_revertible_revision(handle)` continues to report the
immutable revision captured by a revertible, including after disposal or
document close.

Published summaries retain routes to referenced channels and datastores.
Removing a reference updates GC routes without discarding the retained repair
data needed by undo; a fresh reader can load the published graph and continue
editing it. Reconnect resubmits the existing allocation, attach, and reference
history rather than assigning replacement identities.

Datastores belong to the runtime that created them. The APIs reject a datastore
from another document, a closed document, an incompatible tree view, or an
invalid schema or root without installing a partial graph or advancing
submission and compressor state. Creation is unavailable while the document is
disconnected, reconnecting, read-only, or still replaying history.

This is the supported native SharedTree profile, not arbitrary Fluid dynamic
object authoring. It does not add custom datastore factories, caller-selected
channel IDs, detached graph persistence across runtime close, offline
publication, blob or cross-container handles, GC sweep,
production token handling, cross-runtime handles, or broader DDS and schema
support.

### Publish a datastore alias

`try_set_alias(store, "public")` publishes the datastore's complete attachment
graph and requests a container-wide name. It takes the runtime-owned `DataStore`,
not a document and a separate datastore ID. JavaScript returns
`Promise(Result(container.AliasResult, String))`; BEAM waits and returns
`Result(container.AliasResult, String)`.

The result is `AliasSuccess`, `AliasConflict`, or `AlreadyAliased`. The first
sequenced claim wins; an alias cannot hide an existing datastore identity.
Conflicts leave the document usable and the newly published graph attached,
so the caller can retry another name. Concurrent calls for the same datastore
and name share one submission and receive its exact outcome. After this
runtime has successfully claimed a name, another name for that datastore
returns `AlreadyAliased`.

Completion comes from the claim's own acknowledgement, not from an optimistic
local lookup. Reconnect preserves submission identity, waits for the old session
to close, and resubmits only an unaccepted claim. This also works for an
already-published datastore and a retry after conflict. Reaching the reconnect
deadline returns an interruption error rather than leaving callers waiting.
BEAM's runtime-call timeout is ten seconds; a timeout or interruption does not
cancel a claim that the server may already have accepted.

Published summaries retain successful alias targets as root datastores so
upstream and native readers can resolve them after reload. Pending alias claims
are not part of pending-tree checkpoints: settle them before capture.

### Limits

Native writers produce full summaries, not incremental summaries. Memory use
depends on attached and retained detached content, pending edits, and the
collaboration window. History can trim as the minimum sequence advances, but
there is no published capacity, throughput, or bounded-memory guarantee.

Map-wide clear, array schema evolution, staged upgrades,
unknown-field adapters, data migration, shared or persisted branching,
persisted undo stacks, and incremental summaries remain deferred. Transaction,
undo/redo, handle-valued leaves, and runtime-local branch support are limited as
described above.
The compatibility claim also excludes additional upstream package versions.
Default and declared-layout creation and the live attachment graph are available.
Arbitrary container layouts, automatic application history management, and
automatic disk journaling remain outside the profile. Explicit restart
checkpoints cover the pending-tree boundary described above.

Recreate documents written with earlier Watershed development encodings.
There is no legacy reader or migration path. This format change does not
remove the regression requirement for existing DDS APIs and behavior.

### Create a SharedTree container

`watershed.create_tree_container` returns a
`Promise(Result(String, typed.Error))`;
`watershed_beam.create_tree_container` returns
`Result(String, typed.Error)`. Pass a
`container.CreateConfig(base_url, tenant, token)`, a checked
`typed.Schema(schema, record)`, its matching `typed.Builder(schema, input)`,
and an optional input. Use `None` only with an optional root schema. The
builder encodes construction data; callers do not pass `TreeValue` through the
application facade.

Creation sends one authenticated POST to the pinned Floodgate service and
returns its assigned document ID. It does not start a WebSocket connection or
document runtime. Obtain
a document-scoped token for that ID, call the existing `connect`, then follow
`resolve_root` -> `get(root, "tree")` ->
`resolve_tree(document, handle, definition)`. Keep the returned ID if token
acquisition or opening fails; retry opening that document, not creation.
If the creation response is lost or invalid, the service may have created a
document. Watershed reports that uncertainty and does not retry the POST.

The initial layout uses alias `root` -> datastore `A`, a bootstrap map at
`/A/root`, and a tree at `/A/_C`. The logical code package is
`watershed-shared-tree`; an upstream reader must provide a matching application
loader and view schema. The library has no Fluid SDK runtime dependency.
Use `create_tree_container_with_layout` to include declared stores and channels
in that first POST. The open-document APIs above add runtime-owned detached
datastores and channels after connecting.

The [standalone CLI example](examples/shared_tree_cli) creates a document on
JavaScript, edits it on BEAM, and reopens it without an SDK seed. Local token
minting in that example is for development; applications supply service-issued
tokens. Run `just shared-tree-create-test` for the native and HTTP checks, or
`just shared-tree-create-interop` for the pinned-service creation matrix.

The [browser checklist example](examples/shared_tree_checklist_lustre) creates
the same fixed-layout container from a Lustre application, then edits an
object-and-array schema in two browser contexts. It mints development tokens
in the browser for the local Floodgate stack; production applications must
obtain tenant-write and document tokens from a backend. The application owns
native revertible handles for local undo and redo, groups **Complete all** in
one transaction and undo step, clears invalidated history, and releases its
subscriptions and handles on close. Reload restores committed data but not the
page-local history stacks.

### Declare an initial container layout

Start with `container.layout()` and declare additions to the standard bootstrap.
Store declarations create a SharedMap entry point named `root`. Map bindings
can point forward or form cycles; creation checks the complete graph before
sending the POST.

```gleam
import gleam/json
import gleam/option.{Some}
import watershed/container

pub fn initial_layout() -> container.Layout {
  container.layout()
  |> container.with_data_store("catalog", Some("public"))
  |> container.with_map("catalog", "settings", [
    #("theme", json.string("dark")),
  ])
  |> container.with_binding("A", "root", "catalog", "catalog", "root")
  |> container.with_binding("catalog", "root", "settings", "catalog", "settings")
}
```

Both facades expose
`with_initial_tree(layout, store, channel, definition, builder, input)`.
It returns `Result(container.Layout, typed.Error)` and supports a different
schema for each additional tree, including channels in datastore `A`.
Pass the completed layout as the last argument to
`create_tree_container_with_layout(config, definition, builder, input, layout)`.
Its return type and creation uncertainty match `create_tree_container`.
All initial trees share one document ID compressor.

Names must be canonical, unescaped path components without a leading dot.
Store IDs, aliases, channel IDs within a store, and map keys must be unique.
An alias cannot shadow a store ID. Creation rejects undeclared handle targets,
non-map binding sources, and bindings that replace an existing map key,
including the primary `"tree"` binding. The standard `A/root`, `A/_C`, and
`root` alias remain reserved. Initial aliases publish their stores as summary
roots; unaliased stores can be reached through declared bindings.

This API uses the registered bootstrap and map-root graph factories with code
package `watershed-shared-tree`. Supply both factories to an upstream loader.
It does not install executable factories or enable blob or cross-container
handles. `just shared-tree-layout-interop` checks both creators, three fresh
readers before and after a native summary, cyclic bindings, alias lookup, and
continued secondary-tree array moves without changing the primary tree.

### SharedTree checks

The `SharedTree native` CI job runs on pull requests and pushes to `main`. The
long-running `SharedTree interoperability` workflow runs only by manual
dispatch. The native job prepares and verifies the pinned source, builds and
tests both native targets, then runs the source/generator/gate validator
selection. It does not run the live service suite. The manual workflow performs
the same source and native preparation, captures the genuine pinned source
artifact, then runs the complete serialized Node inventory. It owns isolated
pinned Floodgate runs for the legacy matrices, native creation, declared
layouts, handle lifecycle, checkpoint recovery, and aliases.

| Command | Checks |
| --- | --- |
| `just shared-tree-test` | Both native suites, storage/facade coverage, and HTTP/bootstrap/creation smokes. |
| `npm --prefix tools/shared-tree-oracle test` | The unrestricted Oracle, report-validator, recipe, and real-service inventory, serialized because service files share one owned Erlang shipment. |
| `just shared-tree-oracle-check` | Pinned upstream regeneration against committed fixtures. |
| `just shared-tree-interop` | The existing object/map/array/schema/Identifier service profile and its 300 seeded schedules. |
| `just shared-tree-create-interop` | Object, array, and Identifier creation by JavaScript and BEAM, each loaded by fresh JavaScript, BEAM, and upstream readers: eighteen cells. |
| `just shared-tree-layout-interop` | Declared initial graphs: twelve creator/checkpoint/reader cells with continued array moves. |
| `just shared-tree-lifecycle-interop` | Seven handle-lifecycle sections, 27 writer/checkpoint/reader reload cells, and 300 handle schedules at seed 42. |
| `just shared-tree-recovery-interop` | Thirty-two crash/restart cells, including partial acceptance and a second crash after continued editing. |
| `just shared-tree-alias-interop` | Sixteen alias publication, conflict, retry, and reconnect cells. |
| `just shared-tree-interop-deep` | Manual 7,500-schedule run through the same coordinator. |

See the [oracle README](tools/shared-tree-oracle/README.md#run) for prerequisites,
evidence artifacts, and failure replay. These checks prove the declared profile;
they do not expand the compatibility claim.

## Data structures

Every structure rides the same sequenced stream and can be mixed freely in one
document. Pick by how you want concurrent edits to merge — the
[field guide](https://watershed.tylerbutler.com/structures) covers each one's
merge rule, optimistic behaviour, and what it is best for.

| Family | Structures | Use it for |
| --- | --- | --- |
| Maps & cells | `SharedMap`, `LWWMap`, `OR-Map`, `SharedDirectory`, `LWWRegister`, `MvRegister` | key/value state, nested folders, or a cell with one winner or concurrent alternatives |
| Counters | `SharedCounter`, `G-Counter`, `PN Counter` | numbers many people add to at once |
| Sets | `OR-Set`, `G-Set`, `2P-Set` | membership: re-addable, add-only, or permanent removal |
| Sequences | `SharedSequence`, `SharedText` | ordered lists with `move`, and plain text many people type into |
| Transforms | `JSON OT`, `SharedRichText` | one JSON document, or Quill-style rich text with formatting |
| Coordination | `Claims`, `TaskManager`, `Ordered collection`, `Register collection`, `Pact map` | ownership, work queues, and quorum agreement |

Each has matching `create_*`, `ensure_*`, mutation, read, and `subscribe_*`
functions on both the Erlang (`watershed_beam`) and JavaScript (`watershed`)
facades. For example:

```gleam
let assert Ok(items) = watershed.create_sequence(document)
let assert Ok(Nil) = watershed.sequence_insert(items, 0, json.string("first"))
let assert Ok(Nil) = watershed.sequence_insert(items, 1, json.string("second"))
let assert Ok(Nil) = watershed.sequence_move(items, 0, 1)
watershed.sequence_values(items)
// [json.string("second"), json.string("first")]
```

Indexing rules differ by structure and are enforced, not clamped:
`SharedSequence` and `SharedText` index by **Unicode grapheme cluster**, while
`SharedRichText` uses **UTF-16 code units** to match Quill and JavaScript string
indexing exactly.

`G-Counter` only goes up, which is what you want for hit counts, votes, and
anything else where a decrement would be a bug rather than a feature. Every
replica keeps its own tally and the visible value is their sum, so concurrent
increments never fight. A negative amount is refused and nothing is sent:

```gleam
let assert Ok(hits) = watershed.create_g_counter(document)
let assert Ok(Nil) = watershed.g_counter_increment(hits, 3)
let assert Error(_) = watershed.g_counter_increment(hits, -1)
watershed.g_counter_value(hits)
// Ok(3)
```

Use `create_g_counter`, `ensure_g_counter`, `g_counter_increment`,
`g_counter_value`, and `subscribe_g_counter` on either sequenced facade; typed
fields use `schema.GCounterChannel`, and peer-to-peer documents get
`p2p.g_counter_root()`.

An `OR-Map` chooses one value mode at creation: signed tallies (`TallyMode`),
string registers (`RegisterMode`), sets of strings (`OrSetMode`), or concurrent
string alternatives (`MvRegisterMode`). Set mode fits things like tags per
document: two people can add different tags to the same document without
replacing each other's collection.

```gleam
let assert Ok(labels) =
  watershed.create_or_map(document, or_map_kernel.OrSetMode)
let assert Ok(Nil) =
  watershed.or_map_add_member(labels, "inspection-brief", "reviewed")
watershed.or_map_value(labels, "inspection-brief")
// Ok(or_map_kernel.SetMembers(["reviewed"]))

let assert Ok(Nil) =
  watershed.or_map_remove_member(labels, "inspection-brief", "reviewed")
watershed.or_map_value(labels, "inspection-brief")
// Ok(or_map_kernel.SetMembers([]))

let assert Ok(Nil) = watershed.or_map_remove_key(labels, "inspection-brief")
watershed.or_map_value(labels, "inspection-brief")
// Error(Nil)
```

Removing a member and removing its key are different edits. Removing the last
member leaves a present, empty set; removing an absent member does nothing and
does not create a key. Key removal clears the members its author observed.
A concurrent, unseen member addition can keep the key alive, but a later
re-add does not bring removed members back.

| | SharedMap | OR-map in `OrSetMode` |
| --- | --- | --- |
| Values | JSON, including arrays | Sets of strings |
| Concurrent edits to one key | The later server-sequenced write replaces the whole value | Member edits merge; unseen additions survive observed removals |
| Reads | Insertion-order keys | Keys and members sorted in UTF-8 order |
| Saved state | Visible values | Member tags, tombstones, removal history, and counter floors |

Both sequenced facades expose `or_map_add_member`, `or_map_remove_member`, and
`or_map_remove_key` as `Result(Nil, String)` operations. The last is a
result-returning companion to the existing `or_map_remove`; legacy methods
keep their signatures. Publish the handle with `set_or_map_field`, or use
`ensure_or_map` with `OrSetMode` after synchronization. Typed fields use the
existing `schema.OrMapChannel`.

`or_map_entries` returns `SetMembers` values, and `subscribe_or_map` delivers
`SetMembersUpdated(key, members)` or `KeyRemoved(key)`. Adding an already
visible member still creates a fresh causal tag, so it can survive a
concurrent removal, but it emits no duplicate visible-value event.

For JS CRDT documents, configure `root: p2p.or_map_root(or_map_kernel.OrSetMode)`.
The same three mutations return `Result(Nil, p2p.P2pError)` through `crdt_js`.
Its `or_map_value` has an outer result for document/channel errors:
`Ok(Error(Nil))` means a missing key, while `Ok(Ok(SetMembers([])))` means a
present empty key. Lustre uses the existing `ensure_or_map`, subscriptions,
and deferred `perform` effects; no separate set-map handle is needed.

Set mode accepts empty strings as keys or members. It has no whole-set setter,
clear, pruning, mixed value types, or nested-map support. Counter floors
survive rollback and reload without restoring pending members. The
[maps field guide](https://watershed.tylerbutler.com/structures/maps) includes
the set-mode races beside the other maps.

`LWWRegister` holds one string, initially `""`. Values are string-only in this
release. Each write gets `max(wall_clock_ms, last_seen + 1)` from the runtime
and kernel, so its logical clock advances even when the wall clock repeats or
moves backward. Callers supply only the value. The greatest timestamp wins;
the lexicographically greatest replica ID breaks a timestamp tie.

```gleam
let assert Ok(status) = watershed.create_lww_register(document)
let assert Ok(Nil) = watershed.lww_register_set(status, "ready")
watershed.lww_register_value(status)
// Ok("ready")
```

Store the new register's handle in an attached map to replicate it. Typed fields
use `schema.LwwRegisterChannel`, inferred here from `set_lww_register_field`:

```gleam
let root = watershed.typed(watershed.root(document))
let status_field = schema.channel_field("status")
watershed.set_lww_register_field(root, status_field, status)
watershed.resolve_lww_register_field(document, root, status_field)
// Ok(Some(status))
```

Use `ensure_lww_register` to adopt or create the field after synchronization:
JavaScript takes a result callback, while `watershed_beam` waits and returns the
result. Both sequenced facades expose the create, handle, resolve, set, read, and
typed field operations above. `subscribe_lww_register` delivers
`Changed(previous_value, value)` to a callback on JavaScript or a subject on the
BEAM. Writing the current string still replicates newer metadata (timestamp and
winning author), but emits no visible-value event. Writes return `Result` so
callers can handle channel and clock errors.

For a browser p2p document, use `root: p2p.lww_register_root()` in
`crdt_js.config`, create it with `crdt_js.new_document`, and call `crdt_js.attach`
to connect it to peers. Read and write its root through the CRDT API:

```gleam
let status = crdt_js.root(document)
let assert Ok(Nil) = crdt_js.lww_register_set(status, "ready")
crdt_js.lww_register_value(status)
// Ok("ready")
```

Use `crdt_js.subscribe_lww_register` for visible changes; CRDT reads and writes
return `Result(_, p2p.P2pError)`. Snapshots retain the winning timestamp and
author, including metadata-only writes. `LWWRegister` is a single-value CRDT:
the consensus register collection provides sequenced coordination across named
registers, while an `LWWMap` selects a winner per key.

### LWWMap or SharedMap?

`LWWMap` stores strings under string keys. It uses a logical clock per key:
each edit gets `max(wall_clock_ms, last_seen_for_key + 1)`. The highest
timestamp wins, even if that edit arrives first. At equal timestamps, a
tombstone beats a string. Two active writes resolve by writer ID in UTF-8
byte order, independent of arrival order. Only v3 summaries are accepted.

```gleam
let assert Ok(settings) = watershed.create_lww_map(document)
let root = watershed.typed(watershed.root(document))
let settings_field = schema.channel_field("settings")
watershed.set_lww_map_field(root, settings_field, settings)

let assert Ok(Nil) = watershed.lww_map_set(settings, "gate", "open")
watershed.lww_map_get(settings, "gate")
// Ok("open")
let assert Ok(Nil) = watershed.lww_map_remove(settings, "gate")
watershed.lww_map_get(settings, "gate")
// Error(Nil)
let assert Ok(Nil) = watershed.lww_map_set(settings, "gate", "closed")
```

Both sequenced facades expose these functions, plus `ensure_lww_map`,
`resolve_lww_map`, sorted `lww_map_entries`/`lww_map_keys`, and
`subscribe_lww_map`. Typed fields use `schema.LwwMapChannel`. In a browser
CRDT document, use `p2p.lww_map_root()` and the matching `crdt_js` functions.
Its `lww_map_get` returns `Ok(Error(Nil))` for a missing key, while an outer
`Error(P2pError)` means the read failed.

| | SharedMap | LWWMap |
|---|---|---|
| Winner per key | Later server sequence number | Greater timestamp, then tombstone or writer-ID tie |
| Values | JSON, including supported encoded handles | Strings |
| Edits | Set, delete, clear | Set, remove |
| Iteration | Insertion order | Sorted keys |
| Summary | Confirmed entries and insertion order | Values, timestamps, and retained tombstones |
| Runtime | Server-sequenced | Sequenced or JS CRDT mesh/relay |

Choose SharedMap for server-ordered JSON state. Choose LWWMap for shared
string settings that must merge without a server deciding the winner.
Both discard the losing value at a conflicting key; neither merges fields
inside a value or preserves the alternatives for a person to resolve.
Clock skew can favor an ahead-of-time writer, so "last" is not a guarantee
about which human edited most recently.

A remove retains a timestamped tombstone, even for an absent key. Older
writes cannot bring that key back, but a later write that observes the
tombstone can restore it. This differs from OR-map's observed-remove
add-wins rule: an LWWMap edit only beats a removal with a higher timestamp.
There is no clear or pruning API. Reloads retain tombstones and restore
per-key clocks; same-value writes and absent-key removals still replicate
metadata without emitting a visible-change event. The
[maps demo](https://watershed.tylerbutler.com/structures/maps#lww-map)
shows timestamp order winning against server order.

### OR-map modes

An `OR-Map` has two merge layers. At the key layer, observed-remove is
add-wins: a remove hides the key additions it has seen, but a concurrent
addition keeps the key present. At the value layer, each key contains the
same kind of leaf CRDT selected when the map is created.

| Mode | Leaf at each key | Sequenced operations | Browser p2p |
| --- | --- | --- | --- |
| `TallyMode` | PN-counter | `watershed.or_map_increment`, `watershed.or_map_value` | `p2p.or_map_root(or_map_kernel.TallyMode)`, `crdt_js.or_map_increment` |
| `RegisterMode` | LWW-register | `watershed.or_map_set`, `watershed.or_map_value` | `p2p.or_map_root(or_map_kernel.RegisterMode)`, `crdt_js.or_map_set` |
| `OrSetMode` | OR-set of strings | `watershed.or_map_add_member`, `watershed.or_map_remove_member`, `watershed.or_map_remove_key`, `watershed.or_map_value` | `p2p.or_map_root(or_map_kernel.OrSetMode)`, matching `crdt_js` member and key operations |
| `MvRegisterMode` | MV-register | `watershed.or_map_set_mv_register`, `watershed.or_map_values` | `p2p.or_map_root(or_map_kernel.MvRegisterMode)`, `crdt_js.or_map_set_mv_register`, `crdt_js.or_map_values` |

**One OR-map instance is homogeneous.** It cannot mix PN-counter,
LWW-register, OR-set, and MV-register leaves by key. Create separate OR-map channels
when a document needs different leaf types. All four modes are available
through the sequenced `watershed` and `watershed_beam` facades. Browser p2p
uses `p2p.or_map_root(mode)` with the matching `crdt_js` functions; p2p is a
JavaScript-target API, not a BEAM API.

For an MV-register OR-map, `or_map_set_mv_register` writes one string and
`or_map_values` reads the sorted concurrent alternatives:

```gleam
import watershed/or_map_kernel

let assert Ok(map) =
  watershed.create_or_map(document, or_map_kernel.MvRegisterMode)

watershed.or_map_set_mv_register(map, "gate-mode", "raise crest")

let assert Ok(values) = watershed.or_map_values(map, "gate-mode")
// ["raise crest"]
```

Concurrent writes to the same key remain separate values. A later ordinary
write replaces only the alternatives that writer has observed, so a client can
resolve the values it has seen without deleting a write that arrived
concurrently. This value-level behaviour is independent of the OR-map's
key-level add-wins rule. `or_map_values` returns `Error(Nil)` for an absent key
or for a map created in another mode. On p2p, `crdt_js.or_map_values` adds its
outer `P2pError` result.

### Concurrent alternatives

`MvRegister` holds strings and returns a sorted list of alternatives, preservingduplicate text from independent concurrent writes. Use `create_mv_register`,
`ensure_mv_register`, `mv_register_set`, `mv_register_values`, and
`subscribe_mv_register` on either sequenced facade; typed fields use
`schema.MvRegisterChannel`. A new write replaces only the history its author has
observed. Writing `""` stores an empty string; it does not delete the value.

The peer-to-peer facade uses `p2p.mv_register_root()` with
`crdt_js.mv_register_set`, `mv_register_values`, and `subscribe_mv_register`.
Snapshots retain causal history even when the visible alternatives don't change.
The [revision slate](https://watershed.tylerbutler.com/mv-register) demonstrates
concurrent writes, ordinary-write resolution, and stale-delta replay.

## Targets

The core (kernels, wire codecs, and the runtime state machine) is
target-agnostic; only the transport and the runtime shell differ. Erlang-only
modules are gated with `@target(erlang)`, so `gleam build --target javascript`
compiles the core plus the JS runtime and nothing else.

| Layer | BEAM (`watershed_beam`) | Browser (`watershed`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime_beam` (OTP actor) | `runtime` (callbacks + mutable cell) |
| Core | kernels · `wire` · `runtime_core` | ← identical, shared |

For Lustre apps, [`watershed_lustre`](watershed_lustre) binds the JS facade to
Lustre as effects — `connect`, per-kind subscriptions, `ensure_*` bootstrap, and
presence — so an app declares its wiring instead of hand-bridging callbacks into
`dispatch`. Every Lustre example here is built on it.

## Durability boundary

`watershed_beam` / `watershed` are the **sequenced** line: once an op is accepted
by Floodgate (or another compatible service), durability lives there, and
summaries shorten the replay for later joins.

`watershed/crdt_js` is the **peer-to-peer** line. `merge_snapshot` joins an
exported snapshot into a live document without dropping local channels or local
edits; `import_snapshot` rebuilds a detached document, and `attach` brings it
online later. `watershed/persist_js` stores those snapshots in IndexedDB,
joining the latest stored value before every save and surfacing — never
deleting — corrupt bytes, import failures, and storage errors.
`watershed/persist_controller_js` is the save driver: debounce after local
edits, periodic digest sweep for remote merges, and one final `pagehide` save
attempt.

That browser durability is local to one profile. Cross-device recovery still
needs another live peer or a relay (`SequencedOnly`, or `Auto` once relay
primary). Signaling alone is never storage.

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read and write through it. Typing is a *decode
boundary*, not a closed schema — remote peers (or old summaries) can still write
any JSON, so typed reads return `Result`.

Each slot is a field: a plain value, a nested typed map (`ChildField`), or a
handle to any other channel kind (`ChannelField`).

```gleam
pub type Document

pub fn title() -> Field(Document, String) {
  schema.field("title", json.string, decode.string)
}
pub fn items() -> ChannelField(Document, SequenceChannel) {
  schema.channel_field("items")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, replacing the
create / race / retry bootstrap apps otherwise write by hand:

```gleam
let root = watershed.typed(watershed.root(document))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(sequence) = watershed.ensure_sequence(document, root, items())
```

Channel `ensure_*` calls wait for synchronization before reading or seeding a
field, so they can start before the handshake completes. They report a timeout
if the document or a newly seeded field does not synchronize within the retry
budget. A timeout does not undo an already submitted seed. `ensure_field`
remains synchronous set-if-absent.

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift. Events narrow per field or per channel via `subscribe_field`,
`subscribe_counter`, `subscribe_sequence`, and `subscribe_typed`.
[`examples/sudoku_lustre`](examples/sudoku_lustre) shows the pattern end to end;
[`examples/scoreboard_cli`](examples/scoreboard_cli) shows the record builders.

## Summaries

Automatic summaries are enabled by default on JavaScript and BEAM, including
Lustre connections. A settled client schedules a checkpoint after **500
sequenced messages** since the last known summary, with attempts spread across
a **3-second jitter window**. Messages can contain multiple edits. Each client
checks again before uploading, so a peer's summary can make its attempt
unnecessary. This reduces replay work; it does not guarantee a fixed replay
limit.

Tune `summary_policy.policy()` with `with_threshold` and
`with_jitter_milliseconds`, then apply it with `auto_summarize(document, policy)`.
`stop_auto_summarize(document)` opts that client out; `auto_summarize` re-enables
it. Manual `summarize(document)` remains available, and
`operations_since_summary` reports the message count. Tree documents require
manual synchronized publication; automatic scheduling remains disabled for
them. Uploads need floodgate
summary storage and a token with `summary:write`, which `connect` includes by
default. The call completes only after Floodgate publishes the checkpoint and
returns its Git commit ID. `get_versions(document, count:)` lists those commits
newest first. Pass an ID to `load_version(document, handle:)` to read that
historical snapshot without changing the live document.
This `load_version` result is a snapshot inspection projection, not a complete
restoration object; ordinary connections load the full published hierarchy.

A checkpoint captures confirmed channel state and membership at the blob's
own sequence number. A later client loads it and replays subsequent messages,
including those sequenced during upload. Pending local edits are not in the
checkpoint; reconnect preserves and resubmits unaccepted pending operations,
including fixed-profile tree edits after the old-session closure barrier. See
[reconnect and summaries](https://watershed.tylerbutler.com/runtime/reconnect)
for the boundary and retry behavior.

## Testing your app

`watershed/sluice` (Erlang) and `watershed/sluice_js` (JavaScript) are an
in-memory server: a deterministic, single-process stand-in so you can write
multi-client convergence tests with no infrastructure. It runs the *real*
runtime — same codecs, pending queues, resubmit, reconnect catch-up — over an
injected transport, and the *real* server sequencing, so a passing sluice test
exercises production code paths end to end.

Delivery is explicit: ops sequence when submitted but arrive only when you call
`settle` (deliver until quiescent) or `step` (deliver one frame). That makes
races scriptable — "both clients claim the cell, deliver B first" is a sequence
of calls, not a timing accident.

```gleam
import watershed/sluice_js
import watershed

pub fn two_clients_converge_test() {
  let sluice = sluice_js.start(tenant: "default", document: "demo")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)                       // complete both handshakes

  watershed.set(watershed.root(document_a), "k", json.int(1))
  sluice_js.settle(sluice)                       // deliver the edit everywhere

  watershed.get(watershed.root(document_b), "k")  // Some(json.int(1))
}
```

Other controls: `pause`/`resume` (Erlang — hold a client's frames to script
delivery order) and `advance(ms)`, which moves the sluice's logical clock and
fires the timers that fall due with it, so heartbeat- and TTL-driven logic such
as presence is stepped rather than waited out. The sluice also speaks
`presence_v1`, so server-backed presence is testable in-repo.

The sluice models a real server; it is not one. Keep a live-server test for
anything whose correctness depends on the server's actual behaviour.
[`examples/sudoku_lustre/test/convergence_test.gleam`](examples/sudoku_lustre/test/convergence_test.gleam)
is a real app test.

## Compatibility

- SharedMap ops are byte-identical to the TypeScript `@fluidframework/map`
  format (`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
  SharedCounter ops match `@fluidframework/counter`
  (`{type: "increment", incrementAmount}`).
- `SharedRichText` documents and deltas are JSON arrays of Quill Delta ops, the
  same wire format Quill itself emits and consumes.
- `SharedText` is **not** Fluid's `SharedString`: it uses watershed's own delta
  format over an identity CRDT, so it does not interoperate with Fluid's
  interval merge-tree format. Use it when watershed is on both ends.

Upstream license notices for ported packages are in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Examples

[`examples/`](examples) holds runnable apps, each with its own README:
a [dice roller](examples/dice_lustre) (Lustre) and its
[CLI counterpart](examples/dice_cli), a
[collaborative text editor](examples/text_lustre), a
[reorderable playlist](examples/playlist_lustre) on `SharedSequence`, a
[shared pixel canvas](examples/pixel_canvas_lustre), a
[Sudoku board](examples/sudoku_lustre) on the typed layer, a
[drum machine](examples/drum_machine_lustre) with quorum-agreed tempo, a
[release checklist](examples/release_checklist_lustre) with a first-writer-wins
captain seat and a quorum-agreed release target, and a
[showcase](examples/showcase_lustre) composing several into one document.
Several are available at [watershed.tylerbutler.com](https://watershed.tylerbutler.com).

## Development

```sh
gleam deps download
gleam test                      # BEAM: unit + property + corpus tests
gleam build --target erlang     # BEAM: OTP runtime
gleam build --target javascript # browser: core + JS runtime
gleam format
```

Or use the root justfile:

```sh
just deps
just test
just build
just format
just lint
just integration-up             # local floodgate server on :4000
```

For source navigation, `code-map --root . overview` lists repository areas,
`code-map --root . find connect --path src` finds declarations, and
`code-map --root . file src/watershed/p2p.gleam` shows a file outline. Add
`--json` for agent-readable results. Queries refresh an ignored cache from
current source; they do not require an application or website build.
