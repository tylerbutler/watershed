# SharedTree Browser Checklist Implementation Plan

> **Implementation record:** The browser slice is implemented. The dated status
> below is authoritative; the original task procedure is retained for context.
> Checked artifact steps mean their deliverables exist, not that their historical
> RED/GREEN runs were reconstructed. Unchecked historical test-run and commit
> steps are not missing implementation.

**Goal:** Add a local-development Lustre application that creates a native SharedTree container in the browser and demonstrates convergent checklist editing in two browser contexts.

**Architecture:** Add a schema-neutral `watershed_lustre/tree` effect adapter over the existing JavaScript SharedTree facade. Build a standalone checklist app whose pure domain module decodes tree values and prepares ID-addressed edits, then verify the complete create, open, subscribe, edit, and convergence flow in Chromium against local Floodgate.

**Tech Stack:** Gleam 1.11+, JavaScript target, Lustre 5, Watershed SharedTree, esbuild, pnpm, Node.js CDP smoke helpers, Floodgate

**Spec:** `docs/superpowers/specs/2026-09-29-shared-tree-browser-checklist-design.md`

## Current status (code review: 2026-10-04)

Tasks 1-6 have committed implementations, including the HTTP proxy correction
in `01a90a69`. This review compared source, tests, recipes, and Git history; it
did not rerun the browser or release gates.

| Task | Current implementation and evidence |
| --- | --- |
| 1: Lustre effects | `watershed_lustre/src/watershed_lustre/tree.gleam` exports all seven planned effects. `tree_test.gleam` covers lazy mutation execution, deferred outcomes, mutation errors, and invalid-creation errors. It does not contain dedicated open/read/subscription/unsubscribe tests; root runtime/facade suites cover tree subscriptions but not these effects' scheduling. |
| 2: Schema and domain | `schema.gleam` and `checklist.gleam` implement the object/array schema, strict decoding, duplicate-ID rejection, ID-addressed edits, stale-ID errors, and boundary no-ops. The example's Gleam suite checks these behaviors. |
| 3: Browser lifecycle | The app creates or opens a document, preserves its ID in the URL, connects through `watershed_lustre.connect_dev`, and resolves the tree. `serve.mjs` serves assets and proxies Floodgate HTTP requests; the browser FFI rewrites storage requests to the app origin. Node tests cover URL/FFI behavior and HTTP proxying. |
| 4: Collaborative editing | The app implements every `Action`, renders stable selectors, refreshes after tree events and mutation outcomes, and reports errors explicitly. Its `pending` counter tracks outstanding local effect outcomes, not sequencer acknowledgements. |
| 5: Browser gate | `smoke/browser.mjs` checks two isolated Chromium contexts, add/edit/toggle/delete, move-down, and the edit/reorder race. It compares ordered IDs, text, completion values, local pending counts, and errors. There is no separate move-up action in the smoke; the pure suite checks its edit preparation. |
| 6: Documentation | The example README, root README, and parent roadmap describe the implemented development-only slice without closing M7. |
| 7: Release evidence | Commands remain reproducible below, but this plan has no recorded complete Task 7 handoff proving every command or the three consecutive browser runs. Do not infer that evidence from the implementation commits. |

Effects defer work until effect execution and dispatch callbacks through
microtasks. `perform` executes its mutation thunk when the effect runs; it
does not schedule the mutation itself in a microtask. `unsubscribe` likewise
runs during effect execution and dispatches no callback.

The smoke requires the bundle and Floodgate on port 4000 before checking for
Chromium. With those prerequisites present, missing Chromium is its only
successful skip. `just shared-tree-checklist` builds with `corepack pnpm`.
Neither SharedTree workflow nor `website-browser.yml` invokes this example's
gate; the website workflow covers the separate website browser suite.

Remaining evidence gaps are dedicated adapter lifecycle/scheduling tests,
move-up browser coverage, and a recorded release-validation handoff. Production
authentication, offline authoring, schema upgrades in this example, arbitrary
container layouts, and drag-and-drop remain outside this slice.

## Global Constraints

- Keep the adapter schema-neutral. The example owns its schema and checklist semantics.
- Reuse `watershed_lustre.connect_dev`; do not create a second connection abstraction.
- Defer adapter work until effect execution and dispatch every callback through a microtask. Mutations execute as thunks when the effect runs.
- Use the existing fixed native container layout: alias `root`, datastore `A`, bootstrap map `/A/root`, and SharedTree `/A/_C`.
- Treat browser-minted tokens as local-development behavior only.
- Keep the document ID in the URL after creation so another tab can open the same document.
- Address checklist actions by stable item ID, then resolve the current array index from the latest snapshot.
- Preserve explicit errors. Do not assert on user input, transport state, or remote edits.
- Do not add Fluid SDK or oracle dependencies to production or example code.
- Keep schema upgrades, arbitrary layouts, production authentication, offline authoring, and drag-and-drop out of scope.
- Follow the repository's normal prose style outside `**/*.gleam`; use ASD-STE100 for Gleam comments and error strings.
- Do not add Co-authored-by trailers to commits.

---

## File Structure

### SharedTree Lustre adapter

- Create `watershed_lustre/src/watershed_lustre/tree.gleam`
  - Owns deferred effects for create, development create, fixed-layout open,
    subscription, unsubscribe, root reads, and mutations.
- Create `watershed_lustre/test/watershed_lustre/tree_test.gleam`
  - Proves mutation-effect laziness, outcome deferral, and mutation/creation
    error preservation. Root tests own subscription-token semantics.

### Browser checklist package

- Create `examples/shared_tree_checklist_lustre/gleam.toml`
  - Declares the JavaScript package and local Watershed dependencies.
- Create `examples/shared_tree_checklist_lustre/package.json`
  - Builds the browser bundle with esbuild.
- Create `examples/shared_tree_checklist_lustre/pnpm-workspace.yaml`
  - Allows the esbuild postinstall.
- Create `examples/shared_tree_checklist_lustre/.gitignore`
  - Ignores build output and dependencies.
- Create `examples/shared_tree_checklist_lustre/index.html`
  - Hosts the application and supplies stable smoke-test selectors.
- Create `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/schema.gleam`
  - Owns stored schema, view schema, and initial root.
- Create `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/checklist.gleam`
  - Owns decoded checklist values, stable-ID lookup, and edit preparation.
- Create `examples/shared_tree_checklist_lustre/test/shared_tree_checklist_lustre_test.gleam`
  - Entry point and pure schema/domain tests.
- Create `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre_ffi.mjs`
  - Reads query parameters, replaces the document ID, and rewrites Floodgate
    HTTP requests to the app origin.
- Create `examples/shared_tree_checklist_lustre/serve.mjs`
  - Serves assets and proxies HTTP requests to local Floodgate.
- Create `examples/shared_tree_checklist_lustre/test/browser_ffi.test.mjs`
  - Checks URL preservation and app-origin HTTP rewriting.
- Create `examples/shared_tree_checklist_lustre/test/serve.test.mjs`
  - Checks document-creation and storage HTTP proxying.
- Create `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre.gleam`
  - Owns the Lustre model, lifecycle, update loop, and view.
- Create `examples/shared_tree_checklist_lustre/smoke/browser.mjs`
  - Runs the two-context create and convergence gate.
- Create `examples/shared_tree_checklist_lustre/README.md`
  - Documents local setup, behavior, limits, and authentication warnings.
- Generated by package managers:
  - `examples/shared_tree_checklist_lustre/manifest.toml`
  - `examples/shared_tree_checklist_lustre/pnpm-lock.yaml`

### Repository integration

- Modify `justfile`
  - Adds the `shared-tree-checklist` browser gate.
- Modify `README.md`
  - Links the new browser example from SharedTree creation documentation.
- Modify `docs/superpowers/plans/2026-09-21-shared-tree.md`
  - Records the thin Lustre adapter and browser demo as a pulled-forward M7
    slice without closing M7.

---

### Task 1: Add Deferred SharedTree Lustre Effects

**Files:**
- Create: `watershed_lustre/src/watershed_lustre/tree.gleam`
- Create: `watershed_lustre/test/watershed_lustre/tree_test.gleam`

**Interfaces:**
- Consumes:
  - `watershed.create_tree_container(container.CreateConfig, StoredSchema, Option(TreeValue)) -> Promise(Result(String, String))`
  - `watershed.dev_token(secret:, tenant:, document:, user_id:) -> Promise(String)`
  - `watershed.resolve_root(Document(root)) -> Result(SharedMap, String)`
  - `watershed.get(SharedMap, String) -> Result(Json, Nil)`
  - `watershed.resolve_tree(Document(root), Json, ViewSchema) -> Result(SharedTree, String)`
  - `watershed.subscribe_tree(SharedTree, fn(TreeEvent) -> Nil) -> SubscriptionToken`
  - `watershed.tree_get(SharedTree, FieldPath) -> Result(Option(TreeValue), String)`
  - `watershed.unsubscribe(SubscriptionToken) -> Nil`
- Produces:
  - `tree.create`
  - `tree.create_dev`
  - `tree.open`
  - `tree.subscribe`
  - `tree.unsubscribe`
  - `tree.read_root`
  - `tree.perform`

- [x] **Step 1: Write failing effect tests**

Create `watershed_lustre/test/watershed_lustre/tree_test.gleam` with a concrete
message type, an effect runner, a minimal valid schema, and tests for deferred
mutation outcomes and deferred invalid-creation errors:

```gleam
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None}
import lustre/effect.{type Effect}
import watershed/container
import watershed/transport_js
import watershed/tree/schema
import watershed_lustre/tree

type Msg {
  Performed(Result(Nil, String))
  Created(Result(String, String))
}

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

pub fn perform_runs_lazily_and_defers_the_outcome_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  let calls = transport_js.new_cell(0)
  let operation = fn() {
    transport_js.set_cell(calls, transport_js.get_cell(calls) + 1)
    Ok(Nil)
  }
  let effect = tree.perform(operation, Performed)
  let assert 0 = transport_js.get_cell(calls)
  run(effect, sink)
  let assert 1 = transport_js.get_cell(calls)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Ok(Nil))] = messages(sink)
  promise.resolve(Nil)
}

pub fn create_preserves_invalid_configuration_and_defers_dispatch_test() -> Promise(
  Nil,
) {
  let assert Ok(stored) = schema.stored_from_string(definition)
  let sink = transport_js.new_cell([])
  run(
    tree.create(
      container.CreateConfig("ftp://invalid", "dev-tenant", "token"),
      stored,
      None,
      Created,
    ),
    sink,
  )
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Created(Error(detail))] = messages(sink)
  let assert True = detail != ""
  promise.resolve(Nil)
}

fn run(effect_to_run: Effect(Msg), sink: transport_js.Cell(List(Msg))) -> Nil {
  effect.perform(
    effect_to_run,
    fn(message) {
      transport_js.set_cell(sink, [message, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

fn messages(sink: transport_js.Cell(List(Msg))) -> List(Msg) {
  transport_js.get_cell(sink) |> list.reverse
}
```

- [ ] **Step 2: Run the tests and confirm the adapter is missing**

Run:

```sh
cd watershed_lustre
gleam test
```

Expected: compilation fails because `watershed_lustre/tree` does not exist.

- [x] **Step 3: Implement the adapter module**

Create `watershed_lustre/src/watershed_lustre/tree.gleam`. Use the existing
FFI microtask helper and these public functions:

```gleam
import gleam/javascript/promise
import gleam/option.{type Option}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/container
import watershed/tree/schema as tree_schema
import watershed/tree/types as tree_types
import watershed/tree_kernel

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

pub fn create(
  config: container.CreateConfig,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use outcome <- promise.map(
      watershed.create_tree_container(config, stored, initial_root),
    )
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn create_dev(
  base_url: String,
  tenant: String,
  secret: String,
  stored: tree_schema.StoredSchema,
  initial_root: Option(tree_types.TreeValue),
  created: fn(Result(String, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use token <- promise.map(watershed.dev_token(
      secret: secret,
      tenant: tenant,
      document: "",
      user_id: "shared-tree-checklist",
    ))
    use outcome <- promise.map(watershed.create_tree_container(
      container.CreateConfig(base_url, tenant, token),
      stored,
      initial_root,
    ))
    queue_microtask(fn() { dispatch(created(outcome)) })
  }
  Nil
}

pub fn open(
  document: watershed.Document(root),
  view: tree_schema.ViewSchema,
  opened: fn(Result(watershed.SharedTree, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  queue_microtask(fn() {
    let outcome = {
      use root <- result.try(watershed.resolve_root(document))
      use handle <- result.try(
        watershed.get(root, "tree")
        |> result.replace_error("tree handle is absent"),
      )
      watershed.resolve_tree(document, handle, view)
    }
    dispatch(opened(outcome))
  })
}

pub fn subscribe(
  tree: watershed.SharedTree,
  subscribed: fn(watershed.SubscriptionToken) -> msg,
  changed: fn(tree_kernel.TreeEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      queue_microtask(fn() { dispatch(changed(event)) })
    })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

pub fn unsubscribe(
  subscription: watershed.SubscriptionToken,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.unsubscribe(subscription)
}

pub fn read_root(
  tree: watershed.SharedTree,
  read: fn(Result(Option(tree_types.TreeValue), String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  queue_microtask(fn() {
    dispatch(read(watershed.tree_get(tree, [])))
  })
}

pub fn perform(
  operation: fn() -> Result(Nil, String),
  completed: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let outcome = operation()
  queue_microtask(fn() { dispatch(completed(outcome)) })
}
```

Use the same `../watershed_lustre_ffi.mjs` path as
`watershed_lustre/crdt.gleam`. Do not add a second microtask implementation.

- [x] **Step 4: Add error-preservation coverage**

Extend `tree_test.gleam` with:

```gleam
pub fn perform_preserves_errors_test() -> Promise(Nil) {
  let sink = transport_js.new_cell([])
  run(tree.perform(fn() { Error("refused") }, Performed), sink)
  let assert [] = messages(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Performed(Error("refused"))] = messages(sink)
  promise.resolve(Nil)
}
```

The root `shared_tree` and `facade_parity` suites continue to own subscription
token semantics. This package test owns Lustre effect scheduling.

- [ ] **Step 5: Run the adapter tests**

Run:

```sh
cd watershed_lustre
gleam test
```

Expected: all `watershed_lustre` tests pass.

- [ ] **Step 6: Commit the adapter**

```sh
git add watershed_lustre/src/watershed_lustre/tree.gleam \
  watershed_lustre/test/watershed_lustre/tree_test.gleam
git commit -m "feat(tree): add Lustre SharedTree effects"
```

---

### Task 2: Define the Checklist Schema and Pure Edit Model

**Files:**
- Create: `examples/shared_tree_checklist_lustre/gleam.toml`
- Create: `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/schema.gleam`
- Create: `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/checklist.gleam`
- Create: `examples/shared_tree_checklist_lustre/test/shared_tree_checklist_lustre_test.gleam`
- Generate: `examples/shared_tree_checklist_lustre/manifest.toml`

**Interfaces:**
- Produces:
  - `schema.stored() -> StoredSchema`
  - `schema.view() -> ViewSchema`
  - `schema.initial() -> TreeValue`
  - `schema.checklist_value(List(#(String, String, Bool))) -> TreeValue`
  - `schema.item_value(String, String, Bool) -> TreeValue`
  - `checklist.Item`
  - `checklist.Checklist`
  - `checklist.decode(TreeValue) -> Result(Checklist, String)`
  - `checklist.add(Checklist, String, String) -> Result(Edit, String)`
  - `checklist.edit(Checklist, String, String) -> Result(Edit, String)`
  - `checklist.toggle(Checklist, String) -> Result(Edit, String)`
  - `checklist.delete(Checklist, String) -> Result(Edit, String)`
  - `checklist.move_up(Checklist, String) -> Result(Option(Edit), String)`
  - `checklist.move_down(Checklist, String) -> Result(Option(Edit), String)`

- [x] **Step 1: Create the package manifest**

Create `examples/shared_tree_checklist_lustre/gleam.toml`:

```toml
name = "shared_tree_checklist_lustre"
version = "1.0.0"
description = "Native SharedTree collaborative checklist browser demo"
licences = ["MIT"]
gleam = ">= 1.11.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.62.0 and < 2.0.0"
gleam_javascript = ">= 1.0.0 and < 2.0.0"
lustre = ">= 5.0.0 and < 6.0.0"
watershed = { path = "../.." }
watershed_lustre = { path = "../../watershed_lustre" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

- [x] **Step 2: Write failing schema and domain tests**

Create `test/shared_tree_checklist_lustre_test.gleam` with `gleeunit.main()` and
tests that assert:

```gleam
pub fn initial_tree_matches_the_stored_schema_test() {
  let assert Ok(Nil) =
    schema.validate_root(document_schema.stored(), document_schema.initial())
}

pub fn decode_and_prepare_every_required_operation_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", True),
      #("c", "third", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(types.ArrayInsert(
    ["items"],
    3,
    [document_schema.item_value("d", "fourth", False)],
  )) = checklist.add(value, "d", "fourth")
  let assert Ok(types.SetField(
    ["items", "1", "text"],
    types.StringValue("renamed"),
  )) = checklist.edit(value, "b", "renamed")
  let assert Ok(types.SetField(
    ["items", "1", "completed"],
    types.BooleanValue(False),
  )) = checklist.toggle(value, "b")
  let assert Ok(types.ArrayRemove(["items"], 1, 2)) =
    checklist.delete(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 0))) =
    checklist.move_up(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 3))) =
    checklist.move_down(value, "b")
}

pub fn boundary_moves_and_stale_ids_do_not_submit_edits_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(None) = checklist.move_up(value, "a")
  let assert Ok(None) = checklist.move_down(value, "b")
  let assert Error("checklist item missing is no longer present") =
    checklist.delete(value, "missing")
}
```

- [ ] **Step 3: Run the tests and confirm the modules are missing**

Run:

```sh
cd examples/shared_tree_checklist_lustre
gleam test
```

Expected: compilation fails because the schema and checklist modules do not
exist.

- [x] **Step 4: Implement the stored schema and value constructors**

Create `schema.gleam` with these identifiers and exact schema shape:

```gleam
import watershed/tree/schema
import watershed/tree/types

const checklist_type = "shared_tree_checklist.Checklist"
const items_type = "shared_tree_checklist.Items"
const item_type = "shared_tree_checklist.Item"

const definition = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.boolean\":{\"kind\":{\"leaf\":2}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_checklist.Checklist\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Item\":{\"kind\":{\"object\":{\"completed\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.boolean\"]},\"id\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"text\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"shared_tree_checklist.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"shared_tree_checklist.Item\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_checklist.Checklist\"]}}"

pub fn stored() -> schema.StoredSchema {
  let assert Ok(value) = schema.stored_from_string(definition)
  value
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(value) = schema.view_from_string(definition)
  value
}

pub fn initial() -> types.TreeValue {
  checklist_value([])
}

pub fn checklist_value(
  items: List(#(String, String, Bool)),
) -> types.TreeValue {
  types.ObjectValue(checklist_type, [
    #("title", types.StringValue("SharedTree checklist")),
    #(
      "items",
      types.ArrayValue(
        items_type,
        list.map(items, fn(item) {
          item_value(item.0, item.1, item.2)
        }),
      ),
    ),
  ])
}

pub fn item_value(
  id: String,
  text: String,
  completed: Bool,
) -> types.TreeValue {
  types.ObjectValue(item_type, [
    #("id", types.StringValue(id)),
    #("text", types.StringValue(text)),
    #("completed", types.BooleanValue(completed)),
  ])
}
```

- [x] **Step 5: Implement strict decoding and edit preparation**

Create `checklist.gleam` with these public types:

```gleam
pub type Item {
  Item(id: String, text: String, completed: Bool)
}

pub type Checklist {
  Checklist(title: String, items: List(Item))
}
```

Decode only the declared object and array schema IDs. Require exactly one
string `id`, one string `text`, and one boolean `completed` field per item.
Reject duplicate item IDs with:

```text
duplicate checklist item id <id>
```

Prepare edits with these formulas:

```gleam
pub fn add(
  checklist: Checklist,
  id: String,
  text: String,
) -> Result(types.Edit, String) {
  let Checklist(items:, ..) = checklist
  case string.trim(text) {
    "" -> Error("checklist item text is empty")
    text ->
      Ok(types.ArrayInsert(
        ["items"],
        list.length(items),
        [document_schema.item_value(id, text, False)],
      ))
  }
}

pub fn edit(
  checklist: Checklist,
  id: String,
  text: String,
) -> Result(types.Edit, String) {
  use index <- result.try(index_of(checklist, id))
  case string.trim(text) {
    "" -> Error("checklist item text is empty")
    text ->
      Ok(types.SetField(
        ["items", int.to_string(index), "text"],
        types.StringValue(text),
      ))
  }
}

pub fn toggle(
  checklist: Checklist,
  id: String,
) -> Result(types.Edit, String) {
  use #(index, item) <- result.try(item_at(checklist, id))
  Ok(types.SetField(
    ["items", int.to_string(index), "completed"],
    types.BooleanValue(!item.completed),
  ))
}

pub fn delete(
  checklist: Checklist,
  id: String,
) -> Result(types.Edit, String) {
  use index <- result.try(index_of(checklist, id))
  Ok(types.ArrayRemove(["items"], index, index + 1))
}

pub fn move_up(
  checklist: Checklist,
  id: String,
) -> Result(Option(types.Edit), String) {
  use index <- result.try(index_of(checklist, id))
  case index {
    0 -> Ok(None)
    _ ->
      Ok(Some(types.ArrayMove(
        ["items"],
        index,
        index + 1,
        ["items"],
        index - 1,
      )))
  }
}

pub fn move_down(
  checklist: Checklist,
  id: String,
) -> Result(Option(types.Edit), String) {
  let Checklist(items:, ..) = checklist
  use index <- result.try(index_of(checklist, id))
  case index == list.length(items) - 1 {
    True -> Ok(None)
    False ->
      Ok(Some(types.ArrayMove(
        ["items"],
        index,
        index + 1,
        ["items"],
        index + 2,
      )))
  }
}
```

Keep `index_of` and `item_at` private. Both return
`Error("checklist item " <> id <> " is no longer present")` when no item
matches.

- [ ] **Step 6: Run the pure tests**

Run:

```sh
cd examples/shared_tree_checklist_lustre
gleam test
```

Expected: all schema, decode, stable-ID, edit, boundary, and stale-action tests
pass.

- [ ] **Step 7: Commit the package domain**

```sh
git add examples/shared_tree_checklist_lustre/gleam.toml \
  examples/shared_tree_checklist_lustre/manifest.toml \
  examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/schema.gleam \
  examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre/checklist.gleam \
  examples/shared_tree_checklist_lustre/test/shared_tree_checklist_lustre_test.gleam
git commit -m "feat(tree): define checklist schema and edits"
```

---

### Task 3: Scaffold the Browser Package and Creation Lifecycle

**Files:**
- Create: `examples/shared_tree_checklist_lustre/package.json`
- Create: `examples/shared_tree_checklist_lustre/pnpm-workspace.yaml`
- Create: `examples/shared_tree_checklist_lustre/.gitignore`
- Create: `examples/shared_tree_checklist_lustre/index.html`
- Create: `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre_ffi.mjs`
- Create: `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre.gleam`
- Create: `examples/shared_tree_checklist_lustre/serve.mjs`
- Create: `examples/shared_tree_checklist_lustre/test/browser_ffi.test.mjs`
- Create: `examples/shared_tree_checklist_lustre/test/serve.test.mjs`
- Generate: `examples/shared_tree_checklist_lustre/pnpm-lock.yaml`

**Interfaces:**
- Consumes:
  - Task 1 `watershed_lustre/tree` effects
  - Task 2 schema and checklist modules
  - Existing `watershed_lustre.connect_dev`
- Produces:
  - Browser-native create-or-open lifecycle
  - Stable DOM status selectors
  - Document URL replacement

- [x] **Step 1: Add package-manager and bundle files**

Create `package.json`:

```json
{
  "name": "shared_tree_checklist_lustre",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "description": "Native SharedTree collaborative checklist browser demo",
  "scripts": {
    "build": "gleam build --target javascript && esbuild build/dev/javascript/shared_tree_checklist_lustre/shared_tree_checklist_lustre.mjs --bundle --format=esm --outfile=dist/shared_tree_checklist_lustre.mjs",
    "serve": "node serve.mjs"
  },
  "dependencies": {
    "esbuild": "^0.28.1",
    "phoenix": "^1.8.8"
  },
  "allowScripts": {
    "esbuild@0.28.1": true
  },
  "packageManager": "pnpm@11.13.1"
}
```

Create `pnpm-workspace.yaml`:

```yaml
allowBuilds:
  esbuild: true
```

Create `.gitignore`:

```gitignore
*.beam
*.ez
build
erl_crash.dump
node_modules
dist
```

- [x] **Step 2: Add browser routing FFI tests through Node**

Create `src/shared_tree_checklist_lustre_ffi.mjs` with exports:

```js
export function queryParameter(name, fallback) {
  return new URL(globalThis.location.href).searchParams.get(name) ?? fallback;
}

export function replaceDocument(documentId) {
  const url = new URL(globalThis.location.href);
  url.searchParams.set("document", documentId);
  globalThis.history.replaceState(null, "", url);
}
```

Add `test/browser_ffi.test.mjs` that installs fake `location` and `history`
objects, imports the module, and asserts that `replaceDocument("doc-1")`
preserves `tenant` and `secret` while replacing only `document`. The committed
test also checks `currentOrigin` and `proxyFloodgateHttp`. `test/serve.test.mjs`
checks the server-side proxy. A static-only Python server is insufficient for
this app's cross-origin creation and storage requests.

- [ ] **Step 3: Run the FFI test**

Run:

```sh
node --test examples/shared_tree_checklist_lustre/test/*.test.mjs
```

Expected: the test passes.

- [x] **Step 4: Add the initial HTML host**

Create `index.html` with:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>watershed · SharedTree checklist</title>
  </head>
  <body>
    <main id="app"></main>
    <script type="module">
      import { main } from "./dist/shared_tree_checklist_lustre.mjs";
      main();
    </script>
  </body>
</html>
```

Add this style block inside `<head>`:

```html
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: system-ui, sans-serif;
    margin: 0;
    min-height: 100vh;
    display: grid;
    place-items: start center;
  }
  #app { width: min(42rem, calc(100% - 2rem)); padding: 2rem 0; }
  form, [data-item-id] { display: flex; gap: 0.5rem; align-items: center; }
  form { margin: 1.5rem 0; }
  input[type="text"] { flex: 1; min-width: 0; }
  [data-item-id] { padding: 0.5rem 0; }
  [data-item-completed="true"] input[type="text"] {
    text-decoration: line-through;
    opacity: 0.65;
  }
  [data-error] { color: #b42318; }
  [data-development-auth] { font-size: 0.875rem; opacity: 0.75; }
  button:disabled, input:disabled { opacity: 0.45; }
</style>
```

Keep smoke selectors in Gleam data attributes rather than CSS class names.

- [x] **Step 5: Implement configuration and URL replacement externals**

In the Gleam main module, declare:

```gleam
@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "currentOrigin")
fn current_origin() -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "proxyFloodgateHttp")
fn proxy_floodgate_http(upstream: String) -> Nil

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "replaceDocument")
fn replace_document(document_id: String) -> Nil
```

Use these constants:

```gleam
const default_host = "127.0.0.1"
const default_port = "4000"
const default_tenant = "dev-tenant"
const default_secret = "levee-dev-secret-change-in-production"
```

Define a `Config` with `base_url`, `socket_url`, `tenant`, and `secret`.
The implemented HTTP base defaults to `current_origin()` and can be overridden
with `base`; the socket uses the default Floodgate host and port. The app reads
`tenant`, `secret`, and `document`, not host/port overrides. Initialization calls
`proxy_floodgate_http` for the default Floodgate HTTP origin.

- [x] **Step 6: Implement the create-or-open model**

Use these core types:

```gleam
type Phase {
  Creating
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(watershed.SharedTree),
    subscription: Option(watershed.SubscriptionToken),
    checklist: checklist.Checklist,
    draft: String,
    pending: Int,
    errors: List(String),
  )
}

type Msg {
  Created(Result(String, String))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(watershed.SharedTree, String))
  Subscribed(watershed.SubscriptionToken)
  TreeChanged(tree_kernel.TreeEvent)
  Read(Result(Option(types.TreeValue), String))
  DraftChanged(String)
}
```

Use `Nil` as the document root phantom because this app resolves the bootstrap
map dynamically.

When the URL has no `document` parameter, initialize with `Creating` and run:

```gleam
tree.create_dev(
  base_url: config.base_url,
  tenant: config.tenant,
  secret: config.secret,
  stored: document_schema.stored(),
  initial_root: Some(document_schema.initial()),
  created: Created,
)
```

On `Created(Ok(id))`, call `replace_document(id)`, switch to `Connecting`, and
run `connect(config, id)`. On `Created(Error(detail))`, use:

```text
Creation failed. The service might have created a document whose ID this browser did not receive: <detail>
```

Do not retry.

For an existing document ID, start in `Connecting` and call:

```gleam
watershed_lustre.connect_dev(
  url: config.socket_url,
  tenant: config.tenant,
  secret: config.secret,
  document: document_id,
  user_id: "checklist-" <> id.uuid_v4(),
  got_document: GotDocument,
  connected: Connected,
)
```

Store `GotDocument`. On `Connected(Ok(Nil))`, require that document handle and
call the following; a missing handle is an explicit lifecycle error:

```gleam
tree.open(document, document_schema.view(), Opened)
```

On `Opened(Ok(shared_tree))`, batch:

```gleam
effect.batch([
  tree.subscribe(shared_tree, Subscribed, TreeChanged),
  tree.read_root(shared_tree, Read),
])
```

- [x] **Step 7: Decode reads and expose stable status selectors**

Handle `Read` as follows:

```gleam
case result {
  Ok(Some(value)) ->
    case checklist.decode(value) {
      Ok(checklist) -> #(Model(..model, phase: Ready, checklist: checklist), effect.none())
      Error(detail) -> fail(model, "Invalid checklist snapshot: " <> detail)
    }
  Ok(None) -> fail(model, "The SharedTree root is absent")
  Error(detail) -> fail(model, detail)
}
```

Render one of:

```html
<p data-runtime-status="creating">creating</p>
<p data-runtime-status="connecting">connecting</p>
<p data-runtime-status="ready">ready</p>
<p data-runtime-status="failed">failed</p>
```

Render the current document ID with `data-document-id="<id>"`.

- [ ] **Step 8: Install, build, and inspect the bundle**

Run:

```sh
pnpm --dir examples/shared_tree_checklist_lustre install
pnpm --dir examples/shared_tree_checklist_lustre run build
```

Expected: `dist/shared_tree_checklist_lustre.mjs` exists and the build has no
Fluid SDK dependency.

- [ ] **Step 9: Commit the create-and-open shell**

```sh
git add examples/shared_tree_checklist_lustre
git commit -m "feat(tree): create browser checklist documents"
```

---

### Task 4: Add Checklist Mutations and Collaborative Refresh

**Files:**
- Modify: `examples/shared_tree_checklist_lustre/src/shared_tree_checklist_lustre.gleam`
- Modify: `examples/shared_tree_checklist_lustre/index.html`
- Modify: `examples/shared_tree_checklist_lustre/test/shared_tree_checklist_lustre_test.gleam`

**Interfaces:**
- Consumes Task 2 `types.Edit` preparation.
- Produces complete add, edit, toggle, delete, move-up, and move-down UI.

- [x] **Step 1: Add failing update-helper tests**

Use this mutation helper in the application module:

```gleam
fn operation(
  tree: watershed.SharedTree,
  edit: types.Edit,
) -> Result(Nil, String)
```

Add tests around the pure action-preparation helper:

```gleam
pub type Action {
  Add(id: String, text: String)
  Edit(id: String, text: String)
  Toggle(id: String)
  Delete(id: String)
  MoveUp(id: String)
  MoveDown(id: String)
}

pub fn prepare(
  checklist: checklist.Checklist,
  action: Action,
) -> Result(Option(types.Edit), String)
```

Assert that every `Action` delegates to the exact Task 2 edit and that boundary
moves return `Ok(None)`.

- [ ] **Step 2: Run the focused package tests**

Run:

```sh
cd examples/shared_tree_checklist_lustre
gleam test
```

Expected: compilation fails because `Action` and `prepare` do not exist.

- [x] **Step 3: Implement action preparation and edit dispatch**

Add messages:

```gleam
DraftChanged(String)
AddClicked
EditCommitted(id: String, text: String)
ToggleClicked(id: String)
DeleteClicked(id: String)
MoveUpClicked(id: String)
MoveDownClicked(id: String)
MutationFinished(Result(Nil, String))
```

Implement `prepare` with a case over `Action`. Generate add IDs with
`watershed/id.uuid_v4()` in the `AddClicked` update branch, not inside the pure
helper.

Implement `operation`:

```gleam
fn operation(
  tree: watershed.SharedTree,
  edit: types.Edit,
) -> Result(Nil, String) {
  case edit {
    types.SetField(path, value) -> watershed.tree_set(tree, path, value)
    types.ClearField(path) -> watershed.tree_clear(tree, path)
    types.ArrayInsert(path, index, values) ->
      watershed.tree_array_insert(tree, path, index, values)
    types.ArrayRemove(path, start, end) ->
      watershed.tree_array_remove(tree, path, start, end)
    types.ArrayMove(source, start, end, destination, gap) ->
      watershed.tree_array_move(
        tree,
        source,
        start,
        end,
        destination,
        gap,
      )
    types.MapSet(_, _, _) -> Error("checklist does not use map edits")
    types.MapDelete(_, _) -> Error("checklist does not use map edits")
  }
}
```

Use one `mutate(model, action)` helper:

```gleam
fn mutate(model: Model, action: Action) -> #(Model, Effect(Msg)) {
  case model.tree {
    None -> #(append_error(model, "SharedTree is not ready"), effect.none())
    Some(shared_tree) ->
      case prepare(model.checklist, action) {
        Error(detail) -> #(append_error(model, detail), effect.none())
        Ok(None) -> #(model, effect.none())
        Ok(Some(edit)) -> #(
          Model(..model, pending: model.pending + 1),
          tree.perform(fn() { operation(shared_tree, edit) }, MutationFinished),
        )
      }
  }
}
```

On every `MutationFinished`, decrement `pending`, append any error, and run
`tree.read_root` when the tree handle exists.

- [x] **Step 4: Refresh on every tree event**

Handle every event variant through the same read path, including the later
`SchemaChanged` variant:

```gleam
TreeChanged(_) ->
  case model.tree {
    Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
    None -> #(model, effect.none())
  }
```

Do not infer the new visible value from event locality or the submitted edit.
The latest successful SharedTree read is the rendered state.

- [x] **Step 5: Build the checklist UI**

Render:

- a title;
- connection status and document ID;
- an add form with `data-new-item`;
- a list with one `data-item-id` per item;
- a checkbox with `data-action="toggle"`;
- a text input with `data-action="edit"`;
- buttons with `data-action="move-up"`, `move-down`, and `delete`;
- a pending count with `data-pending`;
- errors with `data-error`; and
- a local-development warning with `data-development-auth`.

Disable all mutations unless `phase == Ready`. Disable move-up on the first
item and move-down on the last item.

Use `event.on_input` for draft and text edits. Submit text edits on `change` or
blur rather than each keystroke so the first demo does not create one
SharedTree operation per character.

- [ ] **Step 6: Run tests and build**

Run:

```sh
cd examples/shared_tree_checklist_lustre
gleam test
pnpm run build
```

Expected: all pure tests pass and the browser bundle builds.

- [ ] **Step 7: Commit collaborative editing**

```sh
git add examples/shared_tree_checklist_lustre/src \
  examples/shared_tree_checklist_lustre/test \
  examples/shared_tree_checklist_lustre/index.html
git commit -m "feat(tree): edit shared checklist in browser"
```

---

### Task 5: Add the Real-Browser Convergence Gate

**Files:**
- Create: `examples/shared_tree_checklist_lustre/smoke/browser.mjs`
- Modify: `justfile`

**Interfaces:**
- Consumes stable selectors from Tasks 3 and 4.
- Produces `just shared-tree-checklist`.

- [x] **Step 1: Write the failing browser smoke**

Create `smoke/browser.mjs` from the repository's CDP helpers. Require:

```js
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { connect } from "node:net";
import { join, resolve } from "node:path";
import {
  devtoolsEndpoint,
  findBrowser,
  stopBrowser,
  withPage,
} from "../../../smoke/cdp.mjs";
import { startChecklistServer } from "../serve.mjs";
```

The script must:

1. Fail when the bundle is missing.
2. Fail with `Start it with: just integration-up` when port 4000 is closed.
3. After those prerequisites, exit zero with an explicit skip only when Chromium is unavailable.
4. Start `startChecklistServer` to serve `index.html` and proxy Floodgate HTTP.
5. Open the first page without `document`.
6. Wait for `data-runtime-status="ready"` and capture its changed URL.
7. Open that URL in a separate browser context.
8. Execute all required mutations and require matching snapshots.

Expose one DOM snapshot expression:

```js
const snapshot = `(() => ({
  status: document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus,
  document: document.querySelector("[data-document-id]")?.dataset.documentId,
  pending: Number(document.querySelector("[data-pending]")?.dataset.pending ?? -1),
  items: Array.from(document.querySelectorAll("[data-item-id]")).map((row) => ({
    id: row.dataset.itemId,
    text: row.querySelector('[data-action="edit"]').value,
    completed: row.querySelector('[data-action="toggle"]').checked,
  })),
  errors: Array.from(document.querySelectorAll("[data-error]")).map((node) =>
    node.textContent
  ),
}))()`;
```

Use helper functions that click by `data-action`, set input values through
`input` and `change` events, and poll until both snapshots match.

- [x] **Step 2: Add the just recipe before making the smoke pass**

Add:

```make
# Native SharedTree browser demo: browser creation plus two-context checklist
# convergence. Requires local Floodgate and skips only when Chromium is absent.
shared-tree-checklist:
    cd examples/shared_tree_checklist_lustre && corepack pnpm run build
    node examples/shared_tree_checklist_lustre/smoke/browser.mjs
```

- [ ] **Step 3: Run the gate and confirm the first concrete failure**

Run:

```sh
just integration-up
just shared-tree-checklist
```

Expected: the smoke fails at the first missing or incorrect selector,
lifecycle transition, or operation. Keep Floodgate running for the next steps.

- [x] **Step 4: Make create and second-context opening pass**

Fix only the creation, URL replacement, connection, and opening path until the
smoke reaches the first add operation.

Run:

```sh
just shared-tree-checklist
```

Expected: both contexts report `ready`, have the same nonempty document ID,
have zero errors, and show an empty checklist.

- [x] **Step 5: Make add, edit, toggle, and delete pass**

Drive these exact observations:

1. First context adds `write plan`.
2. Second context observes the same item ID and text.
3. Second context changes text to `review plan`.
4. Second context checks the item.
5. First context observes `review plan` and `completed: true`.
6. Add `ship demo` and `watch convergence`.
7. Delete `ship demo`.
8. Both contexts converge with two surviving IDs.

Run the gate after each operation family.

- [x] **Step 6: Add the edit-and-reorder race**

With three items present:

1. First context clicks move-down for the first item.
2. Without waiting for convergence, second context edits the last item's text.
3. Wait until both contexts have the same ordered IDs and the edited text.
4. Assert that every original ID appears exactly once.
5. Assert both pending counts return to zero.
6. Assert both error lists remain empty.

The smoke must compare IDs, order, text, and completion values. Visible text
alone is not sufficient.

- [ ] **Step 7: Run the gate three times**

Run:

```sh
just shared-tree-checklist
just shared-tree-checklist
just shared-tree-checklist
```

Expected: all three runs pass without retries or timing-dependent failures.

- [ ] **Step 8: Stop Floodgate and commit the gate**

```sh
just integration-down
git add examples/shared_tree_checklist_lustre/smoke/browser.mjs justfile
git commit -m "test(tree): gate browser checklist convergence"
```

---

### Task 6: Document the Demo and M7 Slice

**Files:**
- Create: `examples/shared_tree_checklist_lustre/README.md`
- Modify: the root README's SharedTree creation section.
- Modify: the parent plan's later-plans and M7 browser-slice sections.

**Interfaces:**
- Consumes the final commands and limits proven by Tasks 1-5.
- Produces user-facing run instructions and an accurate roadmap record.

- [x] **Step 1: Write the example README**

Document these exact commands:

```sh
just integration-up
cd examples/shared_tree_checklist_lustre
pnpm install
pnpm run build
pnpm run serve
```

Tell the reader to open `http://localhost:8080`, wait for the URL to gain a
`document` parameter, and copy that URL into a second tab.

Include sections for:

- schema shape;
- add/edit/toggle/delete/reorder coverage;
- stable item IDs and stale index protection;
- fixed native container layout;
- local-development token warning;
- browser gate command;
- unsupported production authentication, offline authoring, schema upgrades,
  arbitrary layouts, and drag-and-drop.

- [x] **Step 2: Update the root SharedTree creation section**

After the CLI example paragraph, add:

```markdown
The [browser checklist example](examples/shared_tree_checklist_lustre) creates
the same fixed-layout container from a Lustre application, then edits an
object-and-array schema in two browser contexts. It mints development tokens
in the browser for the local Floodgate stack; production applications must
obtain tenant-write and document tokens from a backend.
```

- [x] **Step 3: Update the parent roadmap**

In the M7 section, record:

```markdown
**Pulled-forward M7 browser slice:** The thin `watershed_lustre/tree` adapter
and `shared_tree_checklist_lustre` example cover browser-native creation,
fixed-layout resolution, subscriptions, object/array edits, and a two-context
Chromium gate. They do not close M7. Production token services, arbitrary
layouts, live attachment, handle-valued leaves, richer typed APIs, and pending
state recovery remain open.
```

In the exclusions paragraph that currently lists `SharedTree Lustre bindings`
as wholly deferred, replace that phrase with `richer SharedTree Lustre bindings`
so the document distinguishes the completed thin adapter from the remaining
typed API work.

- [ ] **Step 4: Check documentation links and formatting**

Run:

```sh
git diff --check
rg -n "shared_tree_checklist_lustre|Pulled-forward M7 browser slice" \
  README.md examples/shared_tree_checklist_lustre/README.md \
  docs/superpowers/plans/2026-09-21-shared-tree.md
```

Expected: all links point to committed paths and the roadmap does not mark M7
complete.

- [ ] **Step 5: Commit documentation**

```sh
git add README.md \
  examples/shared_tree_checklist_lustre/README.md \
  docs/superpowers/plans/2026-09-21-shared-tree.md
git commit -m "docs(tree): publish browser checklist demo"
```

---

### Task 7: Run Release Validation and Record the Slice

**Files:**
- Modify only files required by failures caused by Tasks 1-6.

**Interfaces:**
- Produces the final acceptance evidence for the pulled-forward M7 slice.

- [ ] **Step 1: Format all Gleam packages**

Run:

```sh
just format
```

Expected: formatter completes successfully.

- [ ] **Step 2: Run focused adapter and example tests**

Run:

```sh
cd watershed_lustre && gleam test
cd ../examples/shared_tree_checklist_lustre && gleam test
node --test test/*.test.mjs
```

Expected: all focused tests pass.

- [ ] **Step 3: Run SharedTree regressions**

Run from the repository root:

```sh
just shared-tree-test
```

Expected: both native targets and the storage, bootstrap, and creation smokes
pass.

- [ ] **Step 4: Run repository build, tests, and lint**

Run:

```sh
just build
just test
just lint
```

Expected: the new package is auto-discovered by Trellis, its bundle builds, its
tests run, and all tracked Gleam files pass format checking. Investigate any
failure before attributing it to a historical baseline.

- [ ] **Step 5: Run the browser gate with local Floodgate**

Run:

```sh
just integration-up
just shared-tree-checklist
status=$?
just integration-down
exit $status
```

Expected: browser-native creation succeeds and both isolated contexts converge
after add, edit, toggle, delete, reorder, and the edit/reorder race.

- [ ] **Step 6: Check the final diff**

Run:

```sh
git diff --check
git status --short
git diff --stat HEAD~7..HEAD
```

Confirm:

- no `.code-map/` files changed;
- no build or browser-profile output is tracked;
- the package lockfiles belong only to the new example;
- no production dependency imports the Fluid SDK or oracle;
- the documentation calls browser token minting development-only; and
- M7 remains open outside this slice.

- [ ] **Step 7: Resolve validation failures in their owning task**

When a command fails because of this change, return to the task that owns the
failing file, apply the smallest correction there, rerun that task's focused
command, and use that task's explicit `git add` list. Do not create a catch-all
validation commit or an empty commit.

- [ ] **Step 8: Record final commands in the implementation handoff**

Record the exact passing commands and the Chromium/Floodgate environment in the
task handoff or pull request. Do not add validation details to a pull request
description unless the user asks for them.
