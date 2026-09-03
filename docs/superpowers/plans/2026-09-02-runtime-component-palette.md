# Runtime Component Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let project-room users add, move, and remove Checklist and Tally component instances while the room is running.

**Architecture:** Keep creation metadata in the project-room example as typed presets instead of extending the watershed catalog. Reuse the existing workspace mutation and runtime reconciliation APIs, and render instances from `catalog.Running` variants instead of fixed instance IDs.

**Tech Stack:** Gleam 1.7 or newer, JavaScript target, Lustre, watershed workspace and component runtimes, sluice test transport, gleeunit.

**Spec:** `docs/superpowers/specs/2026-09-02-runtime-component-palette-design.md`

## Global Constraints

- Add no dependencies.
- Keep creation presets local to `examples/project_room_lustre`.
- Ask only for a kind and title when creating an instance.
- Generate IDs with `watershed/id.uuid_v4`.
- Keep runtime connection editing out of scope.
- Keep runtime-created instances unconnected.
- Preserve unknown instances as `Unavailable`.
- Use the existing non-destructive workspace deletion semantics.
- Use ASD-STE100 in Gleam docs, comments, and error strings.
- Use normal prose in Markdown and website copy.
- Do not edit `website/src/generated/snippets.json`.
- The current branch has six pre-existing website snippet drift failures in
  `just test`. Do not treat those failures as regressions from this plan, and
  do not fix them in these tasks.

## File structure

### New component modules

- `examples/project_room_lustre/src/project_room_lustre/checklist.gleam`
  owns Checklist config, item codecs, channels, lifecycle, and commands.
- `examples/project_room_lustre/src/project_room_lustre/tally.gleam`
  owns Tally config, PN-counter and Claims channels, lifecycle, and commands.
- `examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam`
  defines the shared integer-delta output and input ports.

### New tests

- `examples/project_room_lustre/test/checklist_test.gleam`
  tests Checklist bootstrap, resume, commands, convergence, and output rules.
- `examples/project_room_lustre/test/tally_test.gleam`
  tests Tally bootstrap, counter convergence, input handling, and target latch.
- `examples/project_room_lustre/test/catalog_palette_test.gleam`
  tests presets, catalog registration, duplicate kinds, and the seeded edge.

### Modified project-room files

- `examples/project_room_lustre/src/project_room_lustre/catalog.gleam`
  registers both kinds, defines creation presets, and exposes typed downcasts.
- `examples/project_room_lustre/src/project_room_lustre/workspace_setup.gleam`
  seeds one instance of each kind and creates instances from presets.
- `examples/project_room_lustre/src/project_room_lustre/views.gleam`
  renders the palette, instance controls, Checklist, and Tally.
- `examples/project_room_lustre/src/project_room_lustre.gleam`
  owns palette form state, workspace effects, dynamic adapter selection, and
  instance commands.
- `examples/project_room_lustre/index.html`
  styles the palette, controls, Checklist, and Tally.
- `examples/project_room_lustre/test/acceptance_test.gleam`
  extends the deterministic two-client runtime scenario.
- `examples/project_room_lustre/README.md`
  documents runtime creation and the seeded Checklist-to-Tally route.
- `smoke/project_room.mjs`
  drives runtime creation, shared edits, movement, and removal in Chromium.

---

### Task 1: Checklist headless component

**Files:**
- Create: `examples/project_room_lustre/src/project_room_lustre/checklist.gleam`
- Create: `examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam`
- Create: `examples/project_room_lustre/test/checklist_test.gleam`

**Interfaces:**
- Consumes:
  - `watershed.create_sequence`
  - `watershed.create_or_set`
  - `watershed.ensure_sequence`
  - `watershed.ensure_or_set`
  - `watershed.sequence_insert`
  - `watershed.sequence_delete`
  - `watershed.or_set_add`
  - `watershed.or_set_remove`
  - `component.emit`
- Produces:

```gleam
pub type Config {
  Config(title: String)
}

pub type Item {
  Item(id: String, label: String)
}

pub opaque type Running

pub fn config_decoder() -> Decoder(Config)
pub fn encode_config(config: Config) -> Json
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String)
pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil
pub fn config(running: Running) -> Config
pub fn items(running: Running) -> List(Item)
pub fn completed(running: Running, item_id: String) -> Bool
pub fn draft(running: Running) -> String
pub fn set_draft(
  running: Running,
  draft: String,
) -> #(Running, List(component.OutputEvent))
pub fn add(running: Running) ->
  Result(#(Running, List(component.OutputEvent)), String)
pub fn rename(
  running: Running,
  item_id: String,
  label: String,
) -> Result(#(Running, List(component.OutputEvent)), String)
pub fn remove(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String)
pub fn complete(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String)
pub fn reopen(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String)
pub fn stop(running: Running) -> Result(Nil, String)
```

`tally_payload.gleam` produces:

```gleam
pub const delta_schema = "project-room/tally-delta@1"

pub fn item_completed() -> port.Output(Int) {
  port.output("item_completed", delta_schema, json.int)
}

pub fn add() -> port.Input(Int) {
  port.collaborative_input(
    "add",
    delta_schema,
    decode.int,
    ["pn-counter:update"],
  )
}
```

- [ ] **Step 1: Write failing configuration and bootstrap tests**

Create `test/checklist_test.gleam` with a sluice document helper and these
tests:

```gleam
pub fn config_round_trips_test() -> Nil {
  let config = checklist.Config(title: "Launch")
  json.parse(
    json.to_string(checklist.encode_config(config)),
    checklist.config_decoder(),
  )
  |> should.equal(Ok(config))
}

pub fn bootstrap_twice_adopts_the_same_channels_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-bootstrap")
  let first = start(document, subtree)
  let second = start(document, subtree)
  checklist.items(first) |> should.equal([])
  checklist.items(second) |> should.equal([])
  checklist.stop(first) |> should.equal(Ok(Nil))
  checklist.stop(second) |> should.equal(Ok(Nil))
}
```

Use the `transport_js.Cell(Option(Result(...)))` callback pattern from
`test/components_test.gleam` in the local `start` helper.

- [ ] **Step 2: Run the new test module and verify the red state**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: compilation fails because `project_room_lustre/checklist` does not
exist.

- [ ] **Step 3: Implement config, item codec, channel bootstrap, and cleanup**

Use these channel fields:

```gleam
fn items_field() -> schema.ChannelField(
  ChecklistSchema,
  schema.SequenceChannel,
) {
  schema.channel_field("items")
}

fn completed_field() -> schema.ChannelField(
  ChecklistSchema,
  schema.OrSetChannel,
) {
  schema.channel_field("completed")
}
```

`Running` stores the config, sequence and OR-set in `transport_js.Cell`
values, one subscription cell per channel, the subtree subscription, a local
draft cell, and `invalidate`.

Encode an item as:

```gleam
fn encode_item(item: Item) -> Json {
  json.object([
    #("version", json.int(1)),
    #("id", json.string(item.id)),
    #("label", json.string(item.label)),
  ])
}
```

Decode only version `1`. `items` filters malformed records and duplicate IDs,
keeping the first effective sequence entry. Follow the rebinding and
subscription replacement pattern in `task_collection.gleam`.

- [ ] **Step 4: Run the tests and verify bootstrap passes**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: both Checklist tests pass.

- [ ] **Step 5: Add failing command and output tests**

Add:

```gleam
pub fn commands_change_items_and_completion_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-commands")
  let running = start(document, subtree)
  let #(running, _) = checklist.set_draft(running, "Security review")
  let assert Ok(#(running, [])) = checklist.add(running)
  let assert [item] = checklist.items(running)
  item.label |> should.equal("Security review")

  let assert Ok(#(running, [event])) =
    checklist.complete(running, item.id)
  component.output_id(event) |> should.equal("item_completed")
  component.output_payload(event)
  |> port.decode(tally_payload.item_completed())
  |> should.equal(Ok(1))
  checklist.completed(running, item.id) |> should.be_true

  let assert Ok(#(running, [])) = checklist.reopen(running, item.id)
  checklist.completed(running, item.id) |> should.be_false
  let assert Ok(#(running, [])) =
    checklist.rename(running, item.id, "Threat model")
  checklist.items(running)
  |> should.equal([checklist.Item(item.id, "Threat model")])
  let assert Ok(#(_, [])) = checklist.remove(running, item.id)
  checklist.items(running) |> should.equal([])
}

pub fn complete_rejects_missing_and_duplicate_items_test() -> Nil {
  let #(document, subtree) = new_subtree("checklist-invalid")
  let running = start(document, subtree)
  checklist.complete(running, "missing")
  |> should.equal(Error("checklist item does not exist"))
}
```

Also assert that `add` rejects a trimmed empty draft and `rename` rejects a
trimmed empty label.

- [ ] **Step 6: Implement Checklist commands**

Use `id.uuid_v4()` when `add` creates an item. Clear the draft only after
`sequence_insert` returns `Ok`.

`rename` finds the effective sequence index, deletes that index, and inserts
the updated record at the same index. `remove` deletes every raw sequence
index with the item ID, highest index first. It does not remove a dangling
completion tag.

`complete` performs this transition:

```gleam
case find_item(running, item_id), completed(running, item_id) {
  Error(Nil), _ -> Error("checklist item does not exist")
  Ok(_), True -> Ok(#(running, []))
  Ok(_), False -> {
    watershed.or_set_add(completed_set(running), item_id)
    Ok(#(running, [
      component.emit(tally_payload.item_completed(), 1),
    ]))
  }
}
```

`reopen` removes the ID from the OR-set and emits no output.

- [ ] **Step 7: Add and pass convergence and resume tests**

Create two sluice clients, attach both to one initialized subtree, and verify:

```gleam
checklist.complete(running_a, item.id)
checklist.remove(running_b, item.id)
sluice_js.settle(sluice)
checklist.items(running_a) |> should.equal([])
checklist.items(running_b) |> should.equal([])
checklist.completed(running_a, item.id) |> should.be_true
checklist.completed(running_b, item.id) |> should.be_true
```

Stop and restart one running value against the same subtree. Assert that items
and completion state remain present while the local draft returns to `""`.

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: all project-room tests pass.

- [ ] **Step 8: Format and commit Checklist**

Run:

```bash
gleam format \
  examples/project_room_lustre/src/project_room_lustre/checklist.gleam \
  examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam \
  examples/project_room_lustre/test/checklist_test.gleam
cd examples/project_room_lustre && gleam test --target javascript
git add \
  examples/project_room_lustre/src/project_room_lustre/checklist.gleam \
  examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam \
  examples/project_room_lustre/test/checklist_test.gleam
git commit -m "feat: add checklist component"
```

---

### Task 2: Tally headless component

**Files:**
- Create: `examples/project_room_lustre/src/project_room_lustre/tally.gleam`
- Create: `examples/project_room_lustre/test/tally_test.gleam`

**Interfaces:**
- Consumes:
  - `tally_payload.add`
  - `watershed.create_pn_counter`
  - `watershed.create_claims`
  - `watershed.pn_counter_update`
  - `watershed.pn_counter_value`
  - `watershed.claim_once`
  - `claim_outcome_js.observe`
- Produces:

```gleam
pub type Config {
  Config(title: String, target: Int)
}

pub opaque type Running

pub fn config_decoder() -> Decoder(Config)
pub fn encode_config(config: Config) -> Json
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String)
pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  emitter: component.OutputEmitter,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil
pub fn config(running: Running) -> Config
pub fn value(running: Running) -> Int
pub fn target_reached(running: Running) -> Bool
pub fn pending_target(running: Running) -> Bool
pub fn add(
  running: Running,
  amount: Int,
) -> Result(#(Running, List(component.OutputEvent)), String)
pub fn stop(running: Running) -> Result(Nil, String)
```

- [ ] **Step 1: Write failing config and counter tests**

Create `test/tally_test.gleam`:

```gleam
pub fn config_requires_a_positive_target_test() -> Nil {
  let invalid =
    tally.Config(title: "Completions", target: 0)
    |> tally.encode_config
  json.parse(json.to_string(invalid), tally.config_decoder())
  |> result.is_error
  |> should.be_true
}

pub fn add_updates_the_counter_test() -> Nil {
  let #(document, subtree) = new_subtree("tally-add")
  let running = start(document, subtree, component.output_emitter(fn(_) { Nil }))
  let assert Ok(#(running, [])) = tally.add(running, 3)
  tally.value(running) |> should.equal(3)
  let assert Ok(#(running, [])) = tally.add(running, -1)
  tally.value(running) |> should.equal(2)
}
```

- [ ] **Step 2: Run the test and verify the red state**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: compilation fails because `project_room_lustre/tally` does not
exist.

- [ ] **Step 3: Implement config, channels, rebinding, and add**

Use:

```gleam
fn counter_field() -> schema.ChannelField(
  TallySchema,
  schema.PnCounterChannel,
) {
  schema.channel_field("counter")
}

fn target_field() -> schema.ChannelField(
  TallySchema,
  schema.ClaimsChannel,
) {
  schema.channel_field("target")
}

const target_key = "reached"
```

`Running` stores config, counter and Claims cells, subscription cells, subtree
subscription, pending flag, generation, stopped flag, emitter, and invalidate.
Return `0` if `watershed.pn_counter_value` returns `Error(Nil)`.

`add` rejects `0` with `"tally delta must not be zero"`, calls
`watershed.pn_counter_update`, invokes `check_target`, and returns no direct
outputs.

- [ ] **Step 4: Run the tests and verify counter behavior passes**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: config and add tests pass.

- [ ] **Step 5: Write failing target-latch and convergence tests**

Add:

```gleam
pub fn target_emits_once_test() -> Nil {
  let #(sluice, document, subtree) = new_sluice_subtree("tally-target")
  let published = transport_js.new_cell([])
  let emitter = component.output_emitter(fn(events) {
    transport_js.set_cell(published, [
      events,
      ..transport_js.get_cell(published)
    ])
  })
  let running = start(document, subtree, emitter)
  let assert Ok(#(running, [])) = tally.add(running, 10)
  settle_runtime(sluice)
  tally.target_reached(running) |> should.be_true
  transport_js.get_cell(published) |> list.flatten |> list.length
  |> should.equal(1)
  let assert Ok(#(_, [])) = tally.add(running, 1)
  settle_runtime(sluice)
  transport_js.get_cell(published) |> list.flatten |> list.length
  |> should.equal(1)
}
```

The two-client test pauses replication, applies `+7` on A and `+5` on B,
resumes both clients, settles sluice, and asserts both values equal `12` and
only one accepted target output exists across both emitters.

- [ ] **Step 6: Implement the Claims target latch**

Follow `decision_poll.check_thresholds` and `claim_threshold`:

```gleam
fn check_target(running: Running) -> Nil {
  case
    transport_js.get_cell(running.stopped),
    value(running) >= running.config.target,
    target_reached(running),
    transport_js.get_cell(running.pending)
  {
    False, True, False, False -> claim_target(running)
    _, _, _, _ -> Nil
  }
}
```

`claim_target` records the generation, sets pending, and submits:

```gleam
watershed.claim_once(
  claims(running),
  target_key,
  json.int(value(running)),
)
```

On `claims_kernel.Accepted(_)`, publish one `TargetReached` output. Define that
output in `tally_payload.gleam` with schema
`"project-room/tally-value@1"`. On `Lost`, publish nothing. On `Aborted`, clear
pending and retain the current value. Ignore callbacks after stop or a channel
rebind changes the generation.

Counter subscriptions call `check_target`, then `invalidate`. Claims
subscriptions call `invalidate`.

- [ ] **Step 7: Run component tests and format**

Run:

```bash
gleam format \
  examples/project_room_lustre/src/project_room_lustre/tally.gleam \
  examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam \
  examples/project_room_lustre/test/tally_test.gleam
cd examples/project_room_lustre && gleam test --target javascript
```

Expected: all project-room tests pass.

- [ ] **Step 8: Commit Tally**

Run:

```bash
git add \
  examples/project_room_lustre/src/project_room_lustre/tally.gleam \
  examples/project_room_lustre/src/project_room_lustre/tally_payload.gleam \
  examples/project_room_lustre/test/tally_test.gleam
git commit -m "feat: add tally component"
```

---

### Task 3: Catalog presets and seeded composition

**Files:**
- Modify: `examples/project_room_lustre/src/project_room_lustre/catalog.gleam`
- Modify: `examples/project_room_lustre/src/project_room_lustre/workspace_setup.gleam`
- Create: `examples/project_room_lustre/test/catalog_palette_test.gleam`
- Modify: `examples/project_room_lustre/test/acceptance_test.gleam`

**Interfaces:**
- Consumes:
  - `checklist.Config`
  - `tally.Config`
  - `tally_payload.item_completed`
  - `tally_payload.add`
- Produces:

```gleam
pub type CreationPreset(root) {
  CreationPreset(
    label: String,
    kind: String,
    version: Int,
    config: fn(String) -> Json,
    initialize: fn(
      watershed.Document(root),
      watershed.SharedMap,
    ) -> Result(Nil, String),
  )
}

pub fn creation_presets() -> List(CreationPreset(root))
pub fn find_creation_preset(
  kind: String,
) -> Result(CreationPreset(root), Nil)
pub type CreateError {
  InvalidTitle
  WorkspaceMutation(workspace_js.WorkspaceError)
}
pub fn as_checklist(running: Running) -> Result(checklist.Running, Nil)
pub fn as_tally(running: Running) -> Result(tally.Running, Nil)
pub fn create_from_preset(
  store: workspace_js.Workspace(root),
  room_catalog: component.Catalog(catalog.Context(root), catalog.Running),
  preset: catalog.CreationPreset(root),
  instance_id: String,
  title: String,
) -> Result(Nil, CreateError)
```

- [ ] **Step 1: Write failing catalog and edge tests**

Create `test/catalog_palette_test.gleam`:

```gleam
pub fn creation_presets_build_valid_configs_test() -> Nil {
  catalog.creation_presets()
  |> list.each(fn(preset) {
    let catalog.CreationPreset(kind:, version:, config:, ..) = preset
    let assert Ok(descriptor) = component.find(catalog.catalog(), kind, version)
    component.validate_config(descriptor, config("Runtime title"))
    |> should.equal(Ok(Nil))
  })
}

pub fn seeded_completion_edge_is_valid_test() -> Nil {
  let #(sluice, document) = document("palette-edge")
  let store = ensure_workspace(document)
  workspace_setup.seed(store) |> should.equal(Ok(Nil))
  sluice_js.settle(sluice)
  let snapshot = workspace_js.read(store, catalog.catalog())
  workspace.graph(snapshot)
  |> port_graph.connections
  |> list.map(fn(edge) { edge.id })
  |> list.contains(catalog.checklist_tally_connection_id)
  |> should.be_true
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: compilation fails because creation presets and the new connection do
not exist.

- [ ] **Step 3: Register Checklist and Tally**

Add constants:

```gleam
pub const checklist_kind = "project-room/checklist"
pub const checklist_version = 1
pub const checklist_instance_id = "checklist"
pub const tally_kind = "project-room/tally"
pub const tally_version = 1
pub const tally_instance_id = "tally"
pub const checklist_tally_connection_id =
  "checklist-completed-to-tally-add"
```

Extend `Running` with `Checklist(checklist.Running)` and
`Tally(tally.Running)`. Add both descriptors to `catalog` and `descriptors`,
update every exhaustive downcast and descriptor callback, and add
`as_checklist` and `as_tally`.

The Checklist descriptor registers `item_completed` as an output. The Tally
descriptor registers `add` as a collaborative input:

```gleam
component.input_handler(tally_payload.add(), fn(running, amount) {
  case running {
    Tally(inner) ->
      tally.add(inner, amount)
      |> result.map(fn(next) { #(Tally(next.0), next.1) })
    _ -> Error("tally input reached the wrong component")
  }
})
```

Pass `emitter(context)` to `tally.start`.

- [ ] **Step 4: Add creation presets and workspace creation**

Return two presets:

```gleam
pub fn creation_presets() -> List(CreationPreset(root)) {
  [
    CreationPreset(
      label: "Checklist",
      kind: checklist_kind,
      version: checklist_version,
      config: fn(title) {
        checklist.encode_config(checklist.Config(title: title))
      },
      initialize: checklist.initialize,
    ),
    CreationPreset(
      label: "Tally",
      kind: tally_kind,
      version: tally_version,
      config: fn(title) {
        tally.encode_config(tally.Config(title: title, target: 10))
      },
      initialize: tally.initialize,
    ),
  ]
}
```

`find_creation_preset` uses `list.find`. `create_from_preset` trims the title
and returns `InvalidTitle` before it creates a child map when the result is
empty. It maps every `workspace_js.add_instance_with` error to
`WorkspaceMutation`. Keep UI-level empty-title validation in Task 4 as the
normal path.

- [ ] **Step 5: Seed both instances and the fixed edge**

Add both `ensure_instance` calls after Activity. Append this connection to
`persisted_connections`:

```gleam
pub fn checklist_tally_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(tally_payload.item_completed(), tally_payload.add())
  port_graph.connection(
    checklist_tally_connection_id,
    port_graph.PortRef(checklist_instance_id, template.source_port),
    port_graph.PortRef(tally_instance_id, template.target_port),
  )
}
```

Use titles `"Checklist"` and `"Completion events"`; set the seeded Tally target
to `10`.

- [ ] **Step 6: Update fixed-layout acceptance expectations**

Change the expected layout in `acceptance_test.gleam` to:

```gleam
[
  catalog.task_collection_instance_id,
  catalog.inspector_instance_id,
  catalog.decision_poll_instance_id,
  catalog.ownership_slots_instance_id,
  catalog.notes_instance_id,
  catalog.activity_instance_id,
  catalog.checklist_instance_id,
  catalog.tally_instance_id,
]
```

Start the seeded Checklist, add and complete one item through a runtime
command, settle sluice, and assert both clients report Tally value `1`.

- [ ] **Step 7: Run tests and format**

Run:

```bash
gleam format \
  examples/project_room_lustre/src/project_room_lustre/catalog.gleam \
  examples/project_room_lustre/src/project_room_lustre/workspace_setup.gleam \
  examples/project_room_lustre/test/catalog_palette_test.gleam \
  examples/project_room_lustre/test/acceptance_test.gleam
cd examples/project_room_lustre && gleam test --target javascript
```

Expected: all project-room tests pass.

- [ ] **Step 8: Commit catalog and seeding**

Run:

```bash
git add \
  examples/project_room_lustre/src/project_room_lustre/catalog.gleam \
  examples/project_room_lustre/src/project_room_lustre/workspace_setup.gleam \
  examples/project_room_lustre/test/catalog_palette_test.gleam \
  examples/project_room_lustre/test/acceptance_test.gleam
git commit -m "feat: register runtime component presets"
```

---

### Task 4: Runtime palette and dynamic views

**Files:**
- Modify: `examples/project_room_lustre/src/project_room_lustre.gleam`
- Modify: `examples/project_room_lustre/src/project_room_lustre/views.gleam`
- Modify: `examples/project_room_lustre/index.html`
- Modify: `examples/project_room_lustre/test/project_room_lustre_test.gleam`

**Interfaces:**
- Consumes:
  - `catalog.creation_presets`
  - `catalog.find_creation_preset`
  - `workspace_setup.create_from_preset`
  - `workspace_js.move_instance`
  - `workspace_js.delete_instance`
  - `component_runtime_js.layout`
  - `catalog.as_checklist`
  - `catalog.as_tally`
- Produces these messages:

```gleam
PaletteTitleChanged(String)
AddComponent(String)
WorkspaceOperationFinished(String, Result(Nil, workspace_setup.CreateError))
MoveComponent(String, Int)
RemoveComponent(String)
ChecklistDraftChanged(String, String)
ChecklistAdd(String)
ChecklistRename(String, String, String)
ChecklistRemove(String, String)
ChecklistComplete(String, String)
ChecklistReopen(String, String)
TallyAdd(String, Int)
```

- [ ] **Step 1: Write failing view-construction tests**

In `project_room_lustre_test.gleam`, construct the palette and both new
component views with inert messages:

```gleam
pub fn palette_and_dynamic_views_construct_test() -> Nil {
  let _palette =
    views.palette(
      "",
      catalog.creation_presets(),
      False,
      fn(_) { Nil },
      fn(_) { Nil },
    )
  let #(document, checklist_tree, tally_tree) = component_trees()
  let checklist = start_checklist(document, checklist_tree)
  let tally = start_tally(document, tally_tree)
  let _checklist_view =
    views.checklist(
      "checklist-test",
      checklist,
      fn(_) { Nil },
      Nil,
      fn(_, _) { Nil },
      fn(_) { Nil },
      fn(_) { Nil },
      fn(_) { Nil },
    )
  let _tally_view = views.tally("tally-test", tally, fn(_) { Nil })
  Nil
}
```

Reuse the synchronous callback helpers from `components_test.gleam` to build
the running values. This test fixes the intended public view signatures before
the host wiring begins.

- [ ] **Step 2: Run the package tests and verify the red state**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: compilation fails because palette state and messages do not exist.

- [ ] **Step 3: Add palette and workspace-operation state**

Extend `Model` with:

```gleam
palette_title: String,
workspace_operation: Option(String),
```

Initialize them to `""` and `None`.

`AddComponent(kind)` validates `string.trim(model.palette_title)`. On success,
find the preset, generate:

```gleam
let instance_id =
  kind
  |> string.replace("project-room/", "")
  |> fn(slug) { slug <> "-" <> id.uuid_v4() }
```

Run `workspace_setup.create_from_preset` through
`runtime_effect.perform`. Set `workspace_operation` to `Some(instance_id)`.
On success, clear `palette_title`; on failure, retain it and show the
workspace error.

Move and remove use the same effect and pending field. Derive the target move
index from the current runtime layout before starting the effect.

- [ ] **Step 4: Render the palette and instance controls**

Add:

```gleam
pub fn palette(
  title: String,
  presets: List(catalog.CreationPreset(root)),
  disabled: Bool,
  title_changed: fn(String) -> msg,
  add: fn(String) -> msg,
) -> Element(msg)
```

Use one text input and one button per preset. Add stable selectors:

```text
data-palette-title
data-action="add-component"
data-component-kind="<kind>"
```

Add:

```gleam
pub fn instance_controls(
  instance_id: String,
  index: Int,
  count: Int,
  disabled: Bool,
  move: fn(Int) -> msg,
  remove: msg,
) -> Element(msg)
```

Disable move-up at index `0`, move-down at `count - 1`, and all controls for
the pending instance.

Do not show controls for these fixed host instances:

```gleam
[
  "tasks", "inspector", "poll", "ownership", "notes", "activity",
  "checklist", "tally",
]
```

- [ ] **Step 5: Render Checklist and Tally by running variant**

Add view signatures:

```gleam
pub fn checklist(
  instance_id: String,
  running: checklist.Running,
  draft_changed: fn(String) -> msg,
  add: msg,
  rename: fn(String, String) -> msg,
  remove: fn(String) -> msg,
  complete: fn(String) -> msg,
  reopen: fn(String) -> msg,
) -> Element(msg)

pub fn tally(
  instance_id: String,
  running: tally.Running,
  add: fn(Int) -> msg,
) -> Element(msg)
```

Use `data-component-kind="checklist"` or `"tally"` and
`data-instance-id="<id>"`. Checklist item controls use `data-item-id`; Tally
renders `data-tally-value` and `data-tally-target`.

Refactor `instance_view` so it reads `component_runtime_js.running` first and
then matches the `catalog.Running` variant. Keep fixed-ID handling only for
Notes editor state and Task Inspector presence context.

- [ ] **Step 6: Route dynamic component commands**

Each Checklist or Tally message calls `runtime_effect.command` with the
message's instance ID. Downcast with `catalog.as_checklist` or
`catalog.as_tally`, invoke the component function, wrap the returned running
value in the matching `catalog.Running` constructor, and report through
`RuntimeCommandFinished`.

For example:

```gleam
fn run_tally_action(
  model: Model,
  instance_id: String,
  amount: Int,
) -> #(Model, Effect(Msg)) {
  run_component_action(model, instance_id, fn(running) {
    use tally <- result.try(
      catalog.as_tally(running)
      |> result.map_error(fn(_) { "tally action reached the wrong component" }),
    )
    tally.add(tally, amount)
    |> result.map(fn(next) { #(catalog.Tally(next.0), next.1) })
  })
}
```

Extract `run_component_action` from the repeated Task, Poll, and Ownership
runtime-effect wiring without changing their behavior.

- [ ] **Step 7: Add styles and run the browser build**

Add styles for `.component-palette`, `.instance-controls`,
`.checklist-items`, and `.tally-value`. Preserve the existing three-column,
two-column, and one-column responsive workspace breakpoints.

Run:

```bash
pnpm --dir examples/project_room_lustre run build
```

Expected: the Gleam and esbuild bundle completes.

- [ ] **Step 8: Run tests, format, and commit the palette**

Run:

```bash
gleam format \
  examples/project_room_lustre/src/project_room_lustre.gleam \
  examples/project_room_lustre/src/project_room_lustre/views.gleam \
  examples/project_room_lustre/test/project_room_lustre_test.gleam
cd examples/project_room_lustre && gleam test --target javascript
pnpm run build
cd ../..
git add \
  examples/project_room_lustre/src/project_room_lustre.gleam \
  examples/project_room_lustre/src/project_room_lustre/views.gleam \
  examples/project_room_lustre/index.html \
  examples/project_room_lustre/test/project_room_lustre_test.gleam
git commit -m "feat: add runtime component palette"
```

---

### Task 5: Two-client acceptance and documentation

**Files:**
- Modify: `examples/project_room_lustre/test/acceptance_test.gleam`
- Modify: `smoke/project_room.mjs`
- Modify: `examples/project_room_lustre/README.md`

**Interfaces:**
- Consumes all interfaces from Tasks 1 through 4.
- Produces the final deterministic and rendered acceptance coverage.

- [ ] **Step 1: Add a failing runtime-creation acceptance test**

Add a separate test in `acceptance_test.gleam`:

```gleam
pub fn runtime_created_checklist_converges_and_stops_test() -> Nil {
  let #(sluice, document_a, document_b, store_a, store_b) =
    two_client_workspace("project-room-runtime-create")
  let runtime_a = start_test_runtime(sluice, document_a, store_a, "user-a")
  let runtime_b = start_test_runtime(sluice, document_b, store_b, "user-b")
  settle_runtime(sluice)

  let assert Ok(preset) =
    catalog.find_creation_preset(catalog.checklist_kind)
  let instance_id = "checklist-runtime-test"
  workspace_setup.create_from_preset(
    store_a,
    catalog.catalog(),
    preset,
    instance_id,
    "Sprint checklist",
  )
  |> should.equal(Ok(Nil))
  settle_runtime(sluice)

  component_runtime_js.running(runtime_a, instance_id)
  |> result_then(catalog.as_checklist)
  |> result.is_ok
  |> should.be_true
  component_runtime_js.running(runtime_b, instance_id)
  |> result_then(catalog.as_checklist)
  |> result.is_ok
  |> should.be_true
}
```

Continue the test by adding an item on A, completing it on B, moving the
instance to index `0`, and deleting it on A. Assert both clients see the item
and completion, both layouts move it to index `0`, and both runtimes return
`Error(Nil)` from `running` after deletion.

- [ ] **Step 2: Run the acceptance test and verify it fails**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: the new test fails at the first missing or incorrect runtime
creation behavior.

- [ ] **Step 3: Fix only integration defects exposed by the test**

Adjust catalog, workspace setup, or runtime host code only where the
two-client test exposes a mismatch with the approved spec. Do not add graph
editing, generic forms, or subtree collection.

Run the package test after each fix:

```bash
cd examples/project_room_lustre
gleam test --target javascript
```

Expected: the full project-room package passes.

- [ ] **Step 4: Extend the Chromium smoke scenario**

In `smoke/project_room.mjs`, add steps that:

1. type `Sprint checklist` into `[data-palette-title]`;
2. click the Checklist add button;
3. read the generated `data-instance-id`;
4. wait for the same ID in the second tab;
5. add an item in the first tab;
6. complete it in the second tab;
7. verify completion in both tabs;
8. move the component up and verify both DOM orders;
9. remove it and verify both tabs remove the panel.

Retain the existing local Inspector, poll, ownership, Notes, and Activity
checks.

- [ ] **Step 5: Update the project-room README**

Document:

- the eight seeded components;
- the Checklist completion-to-Tally route;
- the title-only palette;
- that new instances start on all clients;
- that runtime-created instances begin without graph connections;
- move and non-destructive removal behavior.

Keep the existing run and test commands unchanged.

- [ ] **Step 6: Run targeted validation**

Run:

```bash
cd examples/project_room_lustre
gleam test --target javascript
pnpm run build
cd ../..
just format
just lint
git --no-pager diff --check
```

Expected: project-room tests and build pass; format, lint, and diff checks pass.

- [ ] **Step 7: Run the rendered smoke scenario**

Start the existing integration services, then run:

```bash
just integration-up
just project-room-smoke
```

Expected: the smoke script reports that fixed component behavior and
runtime-created Checklist behavior converge across both tabs.

Stop services with the repository's existing integration-down recipe if
`just --list` provides one. Otherwise stop only the exact process IDs started
by `just integration-up`.

- [ ] **Step 8: Run the repository gate and record the known baseline**

Run:

```bash
just test
just build
```

Expected component-model result: all Gleam, JavaScript, compile-fail, and
project-room suites pass. `just test` can still report the six pre-existing
website snippet drift failures listed in Global Constraints. If it does,
record that exact baseline in the handoff and do not claim the full repository
gate passes.

- [ ] **Step 9: Commit acceptance and docs**

Run:

```bash
git add \
  examples/project_room_lustre/test/acceptance_test.gleam \
  examples/project_room_lustre/README.md \
  smoke/project_room.mjs
git commit -m "test: cover runtime component creation"
```

## Final review checklist

- [ ] Every palette preset produces config accepted by its registered
  descriptor.
- [ ] Two instances of one kind receive distinct UUID-backed IDs and child
  maps.
- [ ] Views dispatch by `catalog.Running` variant instead of dynamic instance
  IDs.
- [ ] Fixed Notes and Inspector host integration still uses their stable IDs.
- [ ] Runtime-created instances have no implicit graph edges.
- [ ] Checklist emits only for locally originated completion commands.
- [ ] Tally publishes one accepted target event.
- [ ] Delete removes layout and graph references before the manifest entry.
- [ ] Unknown kinds remain visible as `Unavailable`.
- [ ] No task adds a generic config schema or graph editor.
- [ ] The project-room package tests and browser bundle pass.
- [ ] The Chromium smoke scenario passes.
