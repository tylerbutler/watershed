# Data Component SDK Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the target-independent types and pure functions for typed component ports, versioned catalog registration, deterministic connection graphs, and origin-aware dispatch planning.

**Architecture:** Component authors declare typed input and output ports. Generic catalog descriptors erase each component's configuration type inside a decoder and startup closure while preserving one shell-defined runtime type. The connection graph derives one deterministic acyclic view from collaborative edge data, and the dispatch planner turns local output events into ordered local or collaborative deliveries without executing effects.

**Tech Stack:** Gleam 1.7 or newer, `gleam_stdlib`, `gleam_json`, startest, existing compile-fail harness, both Erlang and JavaScript targets.

**Spec:** `docs/superpowers/specs/2026-09-01-data-component-sdk-design.md`

## Global Constraints

- Keep all modules in this plan target-independent and compilable on Erlang and JavaScript.
- Add no dependencies.
- Preserve invalid persisted edges as diagnostics; derive an effective graph without mutating the stored edge set.
- Treat concurrent graph edits deterministically by sorting edge IDs before cycle filtering.
- Only local intent can create port deliveries.
- A collaborative delivery describes an origin-executed target mutation. It does not claim server-run automation.
- Use ASD-STE100 for Gleam module docs, function docs, comments, and error strings.
- Use normal prose in this plan and other Markdown files.

## Plan series

This is the first of four implementation plans. The approved design spans
several subsystems with separate review and test boundaries:

1. **SDK foundation, this plan:** ports, catalog descriptors, graph validation,
   and dispatch planning.
2. **Workspace persistence and lifecycle:** manifest, layout, graph channels,
   instance child maps, startup states, stop, and explicit deletion semantics.
3. **Runtime component execution:** erased running instances, JS and BEAM
   shells, local input execution, collaborative mutation submission, and
   dispatch reporting.
4. **Catalog and reference app:** five headless components, Lustre adapters,
   project-room composition, presence, and two-client acceptance tests.

Each plan must pass its own target-independent or target-specific test gate
before the next plan starts.

## File structure

### New library modules

- `src/watershed/port.gleam`
  - Typed output and input declarations.
  - Runtime port descriptors.
  - Payload encoding and decoding.
  - Compile-time-safe direct connection declarations.
- `src/watershed/component.gleam`
  - Generic component descriptors.
  - Configuration decoding.
  - Catalog registration and lookup by kind and format version.
- `src/watershed/port_graph.gleam`
  - Persistable connection records.
  - Port and instance validation.
  - Deterministic cycle filtering.
- `src/watershed/dispatch.gleam`
  - Local-intent gate.
  - Dispatch traces and ordered delivery plans.

### New tests

- `test/watershed/port_test.gleam`
- `test/watershed/component_test.gleam`
- `test/watershed/port_graph_test.gleam`
- `test/watershed/dispatch_test.gleam`
- `tools/compile-fail/incompatible_port_connection/gleam.toml`
- `tools/compile-fail/incompatible_port_connection/src/incompatible_port_connection.gleam`

### Modified tooling

- `justfile`
  - Add the incompatible-port compile-fail assertion.

---

### Task 1: Typed port declarations

**Files:**
- Create: `src/watershed/port.gleam`
- Create: `test/watershed/port_test.gleam`
- Create: `tools/compile-fail/incompatible_port_connection/gleam.toml`
- Create: `tools/compile-fail/incompatible_port_connection/src/incompatible_port_connection.gleam`
- Modify: `justfile`

**Interfaces:**
- Consumes: `gleam/dynamic/decode.Decoder`, `gleam/json.Json`.
- Produces:
  - `port.InputClass`
  - `port.Direction`
  - `port.Descriptor`
  - `port.Output(payload)`
  - `port.Input(payload)`
  - `port.ConnectionTemplate`
  - `port.PortError`
  - `port.output`
  - `port.local_input`
  - `port.collaborative_input`
  - `port.output_descriptor`
  - `port.input_descriptor`
  - `port.encode`
  - `port.decode`
  - `port.connect`

- [ ] **Step 1: Write tests for port metadata, codecs, and typed connections**

Create `test/watershed/port_test.gleam` with focused cases:

```gleam
import gleam/dynamic/decode
import gleam/json
import startest/expect
import watershed/port

fn selected() -> port.Output(String) {
  port.output("selected", "watershed/task-id@1", json.string)
}

fn focus_subject() -> port.Input(String) {
  port.local_input("focus-subject", "watershed/task-id@1", decode.string)
}

fn append_activity() -> port.Input(String) {
  port.collaborative_input(
    "append-entry",
    "watershed/activity-text@1",
    decode.string,
    ["sequence:insert"],
  )
}

pub fn output_descriptor_has_stable_metadata_test() -> Nil {
  port.output_descriptor(selected())
  |> expect.to_equal(
    port.Descriptor(
      id: "selected",
      direction: port.OutputPort,
      schema_id: "watershed/task-id@1",
      input_class: None,
    ),
  )
}

pub fn local_input_descriptor_records_class_test() -> Nil {
  port.input_descriptor(focus_subject())
  |> expect.to_equal(
    port.Descriptor(
      id: "focus-subject",
      direction: port.InputPort,
      schema_id: "watershed/task-id@1",
      input_class: Some(port.LocalInput),
    ),
  )
}

pub fn collaborative_input_records_capabilities_test() -> Nil {
  port.input_descriptor(append_activity())
  |> expect.to_equal(
    port.Descriptor(
      id: "append-entry",
      direction: port.InputPort,
      schema_id: "watershed/activity-text@1",
      input_class: Some(
        port.CollaborativeInput(capabilities: ["sequence:insert"]),
      ),
    ),
  )
}

pub fn payload_round_trip_test() -> Nil {
  let encoded = port.encode(selected(), "task-42")
  port.decode(focus_subject(), encoded)
  |> expect.to_equal(Ok("task-42"))
}

pub fn invalid_payload_returns_decode_error_test() -> Nil {
  case port.decode(focus_subject(), json.int(42)) {
    Error(port.InvalidPayload(_)) -> Nil
    other -> panic as { "expected InvalidPayload, got " <> string.inspect(other) }
  }
}

pub fn direct_connection_keeps_port_ids_test() -> Nil {
  port.connect(selected(), focus_subject())
  |> expect.to_equal(
    Ok(
      port.ConnectionTemplate(
        source_port: "selected",
        target_port: "focus-subject",
        schema_id: "watershed/task-id@1",
      ),
    ),
  )
}

pub fn matching_payload_type_with_different_schema_is_rejected_test() -> Nil {
  let other = port.local_input("other", "example/other-string@1", decode.string)
  port.connect(selected(), other)
  |> expect.to_equal(
    Error(
      port.SchemaMismatch(
        source: "watershed/task-id@1",
        target: "example/other-string@1",
      ),
    ),
  )
}
```

Import `gleam/option.{None, Some}` and `gleam/string` in the finished test.

- [ ] **Step 2: Run the port tests and confirm the module is missing**

Run:

```bash
gleam test
```

Expected: FAIL because `src/watershed/port.gleam` does not exist.

- [ ] **Step 3: Implement the typed and erased port types**

Create `src/watershed/port.gleam` with this public surface:

```gleam
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type InputClass {
  LocalInput
  CollaborativeInput(capabilities: List(String))
}

pub type Direction {
  OutputPort
  InputPort
}

pub type Descriptor {
  Descriptor(
    id: String,
    direction: Direction,
    schema_id: String,
    input_class: Option(InputClass),
  )
}

pub opaque type Output(payload) {
  Output(id: String, schema_id: String, encode: fn(payload) -> Json)
}

pub opaque type Input(payload) {
  Input(
    id: String,
    schema_id: String,
    decode: Decoder(payload),
    input_class: InputClass,
  )
}

pub type ConnectionTemplate {
  ConnectionTemplate(
    source_port: String,
    target_port: String,
    schema_id: String,
  )
}

pub type PortError {
  InvalidPayload(reason: json.DecodeError)
  SchemaMismatch(source: String, target: String)
}

pub fn output(
  id: String,
  schema_id: String,
  encode: fn(payload) -> Json,
) -> Output(payload) {
  Output(id: id, schema_id: schema_id, encode: encode)
}

pub fn local_input(
  id: String,
  schema_id: String,
  decoder: Decoder(payload),
) -> Input(payload) {
  Input(
    id: id,
    schema_id: schema_id,
    decode: decoder,
    input_class: LocalInput,
  )
}

pub fn collaborative_input(
  id: String,
  schema_id: String,
  decoder: Decoder(payload),
  capabilities: List(String),
) -> Input(payload) {
  Input(
    id: id,
    schema_id: schema_id,
    decode: decoder,
    input_class: CollaborativeInput(capabilities: capabilities),
  )
}

pub fn output_descriptor(output: Output(payload)) -> Descriptor {
  Descriptor(
    id: output.id,
    direction: OutputPort,
    schema_id: output.schema_id,
    input_class: None,
  )
}

pub fn input_descriptor(input: Input(payload)) -> Descriptor {
  Descriptor(
    id: input.id,
    direction: InputPort,
    schema_id: input.schema_id,
    input_class: Some(input.input_class),
  )
}

pub fn encode(output: Output(payload), payload: payload) -> Json {
  output.encode(payload)
}

pub fn decode(
  input: Input(payload),
  payload: Json,
) -> Result(payload, PortError) {
  case json.parse(json.to_string(payload), input.decode) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(InvalidPayload(reason))
  }
}

pub fn connect(
  output: Output(payload),
  input: Input(payload),
) -> Result(ConnectionTemplate, PortError) {
  case output.schema_id == input.schema_id {
    True ->
      Ok(
        ConnectionTemplate(
          source_port: output.id,
          target_port: input.id,
          schema_id: output.schema_id,
        ),
      )
    False ->
      Error(
        SchemaMismatch(source: output.schema_id, target: input.schema_id),
      )
  }
}
```

Add concise STE module and public API documentation. Keep the port IDs and
schema IDs as strings in this first task. The catalog plan can add shared ID
validation after real component IDs establish the naming rules.

- [ ] **Step 4: Run the port tests**

Run:

```bash
gleam test
```

Expected: PASS.

- [ ] **Step 5: Add the compile-fail fixture**

Create `tools/compile-fail/incompatible_port_connection/gleam.toml`:

```toml
name = "incompatible_port_connection"
version = "0.0.0"
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.62.0 and < 2.0.0"
gleam_json = ">= 3.0.0 and < 4.0.0"
watershed = { path = "../../.." }
```

Create
`tools/compile-fail/incompatible_port_connection/src/incompatible_port_connection.gleam`:

```gleam
//// A fixture that must not compile.

import gleam/dynamic/decode
import gleam/json
import watershed/port

pub fn incompatible_connection() {
  let selected = port.output("selected", "task-id@1", json.string)
  let set_filter = port.local_input("set-filter", "status@1", decode.int)
  port.connect(selected, set_filter)
}
```

The call must fail because `Output(String)` cannot unify with `Input(Int)`.

- [ ] **Step 6: Extend the compile-fail recipe**

Append a second explicit assertion to `_test-compile-fail` in `justfile`.
Keep the current `two_root_tags` assertion unchanged.

```bash
out=$(cd tools/compile-fail/incompatible_port_connection && gleam build --target javascript 2>&1)
if [ $? -eq 0 ]; then
  echo "FAIL: incompatible_port_connection compiled. Different payload types now connect."
  exit 1
fi
if ! grep -q 'Input(Int)' <<<"$out"; then
  echo "FAIL: incompatible_port_connection failed, but not with the expected type error:"
  echo "$out"
  exit 1
fi
echo "ok  incompatible port payload types are rejected"
```

Run:

```bash
just _test-compile-fail
```

Expected: both fixtures print `ok` and the recipe exits 0.

- [ ] **Step 7: Format and run both target builds**

Run:

```bash
gleam format src/watershed/port.gleam test/watershed/port_test.gleam tools/compile-fail/incompatible_port_connection/src/incompatible_port_connection.gleam
gleam build --target erlang
gleam build --target javascript
```

Expected: both builds pass.

- [ ] **Step 8: Commit typed ports**

```bash
git add src/watershed/port.gleam test/watershed/port_test.gleam tools/compile-fail/incompatible_port_connection justfile
git commit -m "feat: add typed component ports"
```

---

### Task 2: Generic component catalog

**Files:**
- Create: `src/watershed/component.gleam`
- Create: `test/watershed/component_test.gleam`

**Interfaces:**
- Consumes: `port.Descriptor`.
- Produces:
  - `component.Descriptor(context, running)`
  - `component.Catalog(context, running)`
  - `component.ComponentError`
  - `component.RegistrationError`
  - `component.descriptor`
  - `component.kind`
  - `component.version`
  - `component.ports`
  - `component.validate_config`
  - `component.start`
  - `component.new_catalog`
  - `component.register`
  - `component.find`

- [ ] **Step 1: Write catalog tests with two configuration types**

Create `test/watershed/component_test.gleam`. Use two private config types to
prove that one catalog hides unrelated configuration types:

```gleam
import gleam/dynamic/decode
import gleam/json
import startest/expect
import watershed/component
import watershed/port

type NotesConfig {
  NotesConfig(placeholder: String)
}

type CounterConfig {
  CounterConfig(step: Int)
}

fn notes_decoder() -> decode.Decoder(NotesConfig) {
  use placeholder <- decode.field("placeholder", decode.string)
  decode.success(NotesConfig(placeholder: placeholder))
}

fn counter_decoder() -> decode.Decoder(CounterConfig) {
  use step <- decode.field("step", decode.int)
  decode.success(CounterConfig(step: step))
}

fn notes_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/notes",
    version: 1,
    config_decoder: notes_decoder(),
    start: fn(context, config) {
      Ok(context <> ":" <> config.placeholder)
    },
    ports: [
      port.output_descriptor(
        port.output("selected", "subject@1", json.string),
      ),
    ],
  )
}

fn counter_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/counter",
    version: 1,
    config_decoder: counter_decoder(),
    start: fn(context, config) {
      Ok(context <> ":" <> int.to_string(config.step))
    },
    ports: [],
  )
}

pub fn catalog_holds_different_config_types_test() -> Nil {
  let assert Ok(with_notes) =
    component.register(component.new_catalog(), notes_descriptor())
  let assert Ok(catalog) =
    component.register(with_notes, counter_descriptor())

  component.find(catalog, "watershed/notes", 1)
  |> result.map(component.kind)
  |> expect.to_equal(Ok("watershed/notes"))
}

pub fn start_decodes_config_inside_descriptor_test() -> Nil {
  component.start(
    notes_descriptor(),
    "room",
    json.object([#("placeholder", json.string("Write"))]),
  )
  |> expect.to_equal(Ok("room:Write"))
}

pub fn invalid_config_has_kind_and_version_test() -> Nil {
  case component.start(notes_descriptor(), "room", json.object([])) {
    Error(component.InvalidConfig(kind, version, _)) -> {
      kind |> expect.to_equal("watershed/notes")
      version |> expect.to_equal(1)
    }
    other -> panic as { "expected InvalidConfig, got " <> string.inspect(other) }
  }
}

pub fn duplicate_kind_and_version_is_rejected_test() -> Nil {
  let assert Ok(catalog) =
    component.register(component.new_catalog(), notes_descriptor())

  component.register(catalog, notes_descriptor())
  |> expect.to_equal(
    Error(component.DuplicateRegistration("watershed/notes", 1)),
  )
}

pub fn versions_can_coexist_test() -> Nil {
  let notes_v2 =
    component.descriptor(
      kind: "watershed/notes",
      version: 2,
      config_decoder: notes_decoder(),
      start: fn(_, config) { Ok(config.placeholder) },
      ports: [],
    )
  let assert Ok(with_v1) =
    component.register(component.new_catalog(), notes_descriptor())
  let assert Ok(catalog) =
    component.register(with_v1, notes_v2)

  component.find(catalog, "watershed/notes", 2)
  |> result.map(component.version)
  |> expect.to_equal(Ok(2))
}

pub fn missing_version_is_unavailable_test() -> Nil {
  component.find(component.new_catalog(), "watershed/notes", 7)
  |> expect.to_equal(Error(component.NotRegistered("watershed/notes", 7)))
}
```

Add the imports used by the final test: `gleam/int`, `gleam/result`, and
`gleam/string`.

- [ ] **Step 2: Run the catalog tests and confirm the module is missing**

Run:

```bash
gleam test
```

Expected: FAIL because `src/watershed/component.gleam` does not exist.

- [ ] **Step 3: Implement the generic descriptor**

Create `src/watershed/component.gleam`. Use a generic descriptor whose public
type parameters are the shell context and the shell's common running-instance
type. Hide each component's config type inside `descriptor`:

```gleam
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/result
import watershed/port

pub type ComponentError {
  InvalidConfig(kind: String, version: Int, reason: json.DecodeError)
  StartFailed(kind: String, version: Int, reason: String)
}

pub type RegistrationError {
  DuplicateRegistration(kind: String, version: Int)
}

pub type LookupError {
  NotRegistered(kind: String, version: Int)
}

pub opaque type Descriptor(context, running) {
  Descriptor(
    kind: String,
    version: Int,
    ports: List(port.Descriptor),
    validate_config: fn(Json) -> Result(Nil, ComponentError),
    start: fn(context, Json) -> Result(running, ComponentError),
  )
}

pub opaque type Catalog(context, running) {
  Catalog(entries: Dict(#(String, Int), Descriptor(context, running)))
}

pub fn descriptor(
  kind kind: String,
  version version: Int,
  config_decoder config_decoder: Decoder(config),
  start start_component: fn(context, config) -> Result(running, String),
  ports ports: List(port.Descriptor),
) -> Descriptor(context, running) {
  let decode_config = fn(encoded: Json) {
    case json.parse(json.to_string(encoded), config_decoder) {
      Ok(config) -> Ok(config)
      Error(reason) -> Error(InvalidConfig(kind, version, reason))
    }
  }

  Descriptor(
    kind: kind,
    version: version,
    ports: ports,
    validate_config: fn(encoded) {
      decode_config(encoded)
      |> result.map(fn(_) { Nil })
    },
    start: fn(context, encoded) {
      use config <- result.try(decode_config(encoded))
      start_component(context, config)
      |> result.map_error(fn(reason) { StartFailed(kind, version, reason) })
    },
  )
}
```

Add the accessors and catalog functions named in **Interfaces**. Store entries
in `Dict(#(String, Int), Descriptor(context, running))`. `new_catalog` returns
an empty catalog value, not a `Result`.

Use these signatures:

```gleam
pub fn new_catalog() -> Catalog(context, running)

pub fn register(
  catalog: Catalog(context, running),
  descriptor: Descriptor(context, running),
) -> Result(Catalog(context, running), RegistrationError)

pub fn find(
  catalog: Catalog(context, running),
  kind: String,
  version: Int,
) -> Result(Descriptor(context, running), LookupError)
```

Do not add lifecycle states here. `Loading`, `Ready`, `Unavailable`, and
`Failed` belong to the workspace lifecycle plan, where an instance ID and
subtree exist.

- [ ] **Step 4: Run the catalog tests on both targets**

Run:

```bash
gleam test
gleam test --target javascript
```

Expected: both commands pass.

- [ ] **Step 5: Add a failed-start test**

Add a descriptor whose start closure returns `Error("cannot subscribe")`.
Assert:

```gleam
Error(
  component.StartFailed(
    "watershed/failing",
    1,
    "cannot subscribe",
  ),
)
```

Run:

```bash
gleam test
```

Expected: PASS.

- [ ] **Step 6: Format and build**

Run:

```bash
gleam format src/watershed/component.gleam test/watershed/component_test.gleam
gleam build --target erlang
gleam build --target javascript
```

Expected: both builds pass.

- [ ] **Step 7: Commit the catalog boundary**

```bash
git add src/watershed/component.gleam test/watershed/component_test.gleam
git commit -m "feat: add component catalog boundary"
```

---

### Task 3: Deterministic connection graph

**Files:**
- Create: `src/watershed/port_graph.gleam`
- Create: `test/watershed/port_graph_test.gleam`

**Interfaces:**
- Consumes: `port.Descriptor`, `port.Direction`, `port.InputClass`.
- Produces:
  - `port_graph.PortRef`
  - `port_graph.Connection`
  - `port_graph.GraphError`
  - `port_graph.EffectiveGraph`
  - `port_graph.connection`
  - `port_graph.effective`
  - `port_graph.connections`
  - `port_graph.errors`
  - `port_graph.outgoing`

- [ ] **Step 1: Write graph validation and ordering tests**

Create `test/watershed/port_graph_test.gleam` with helpers for one source port
and one target port per instance:

```gleam
import gleam/option.{None, Some}
import startest/expect
import watershed/port
import watershed/port_graph

fn output(id: String, schema_id: String) -> port.Descriptor {
  port.Descriptor(id, port.OutputPort, schema_id, None)
}

fn local_input(id: String, schema_id: String) -> port.Descriptor {
  port.Descriptor(id, port.InputPort, schema_id, Some(port.LocalInput))
}

fn ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" -> Ok([output("completed", "task@1"), local_input("open", "task@1")])
    "activity" ->
      Ok([output("selected", "task@1"), local_input("append", "task@1")])
    "notes" -> Ok([local_input("focus", "task@1")])
    _ -> Error(Nil)
  }
}

fn edge(
  id: String,
  source_instance: String,
  source_port: String,
  target_instance: String,
  target_port: String,
) -> port_graph.Connection {
  port_graph.connection(
    id,
    port_graph.PortRef(source_instance, source_port),
    port_graph.PortRef(target_instance, target_port),
  )
}

pub fn valid_edges_are_sorted_by_id_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("b", "activity", "selected", "notes", "focus"),
        edge("a", "tasks", "completed", "activity", "append"),
      ],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["a", "b"])
}

pub fn unknown_instance_is_reported_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("a", "missing", "completed", "activity", "append")],
      ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.UnknownInstance("a", "missing")])
}

pub fn wrong_direction_is_reported_test() -> Nil {
  let graph =
    port_graph.effective(
      [edge("a", "tasks", "open", "activity", "append")],
      ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([
    port_graph.WrongDirection(
      "a",
      port_graph.PortRef("tasks", "open"),
      port.OutputPort,
    ),
  ])
}

pub fn schema_mismatch_is_reported_test() -> Nil {
  let mismatched_ports = fn(instance_id) {
    case instance_id {
      "tasks" -> Ok([output("completed", "task@1")])
      "activity" -> Ok([local_input("append", "activity@1")])
      _ -> Error(Nil)
    }
  }
  let graph =
    port_graph.effective(
      [edge("a", "tasks", "completed", "activity", "append")],
      mismatched_ports,
    )

  port_graph.errors(graph)
  |> expect.to_equal([
    port_graph.SchemaMismatch("a", "task@1", "activity@1"),
  ])
}
```

Add a duplicate-ID test. The first sorted occurrence wins and the other entry
produces `DuplicateConnection(id)`.

- [ ] **Step 2: Write the concurrent-cycle normalization test**

Two clients can each add an edge that is acyclic in their local graph while the
merged edge set contains a cycle. Pin deterministic handling:

```gleam
pub fn merged_cycle_keeps_lexically_first_acyclic_edges_test() -> Nil {
  let graph =
    port_graph.effective(
      [
        edge("02-activity-tasks", "activity", "selected", "tasks", "open"),
        edge("01-tasks-activity", "tasks", "completed", "activity", "append"),
      ],
      ports,
    )

  port_graph.connections(graph)
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["01-tasks-activity"])

  port_graph.errors(graph)
  |> expect.to_equal([port_graph.Cycle("02-activity-tasks")])
}
```

Also test a self-edge and a three-instance cycle. The effective graph must stay
acyclic and return one `Cycle(edge_id)` for each skipped edge.

- [ ] **Step 3: Run the graph tests and confirm the module is missing**

Run:

```bash
gleam test
```

Expected: FAIL because `src/watershed/port_graph.gleam` does not exist.

- [ ] **Step 4: Implement persisted connection records and diagnostics**

Create `src/watershed/port_graph.gleam`:

```gleam
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import watershed/port

pub type PortRef {
  PortRef(instance_id: String, port_id: String)
}

pub type Connection {
  Connection(id: String, source: PortRef, target: PortRef)
}

pub type GraphError {
  DuplicateConnection(connection_id: String)
  UnknownInstance(connection_id: String, instance_id: String)
  UnknownPort(connection_id: String, port: PortRef)
  WrongDirection(
    connection_id: String,
    port: PortRef,
    expected: port.Direction,
  )
  SchemaMismatch(connection_id: String, source: String, target: String)
  Cycle(connection_id: String)
}

pub opaque type EffectiveGraph {
  EffectiveGraph(
    connections: List(Connection),
    errors: List(GraphError),
  )
}

pub fn connection(
  id: String,
  source: PortRef,
  target: PortRef,
) -> Connection {
  Connection(id: id, source: source, target: target)
}
```

Implement `effective` with this signature:

```gleam
pub fn effective(
  stored: List(Connection),
  ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> EffectiveGraph
```

Its algorithm is:

1. Sort by `Connection.id` with `string.compare`.
2. Detect repeated IDs before port validation.
3. Resolve each instance's descriptors through `ports_for`.
4. Require `OutputPort` at the source and `InputPort` at the target.
5. Require equal schema IDs.
6. Test whether adding the instance-to-instance edge creates a path from the
   target instance back to the source instance.
7. Keep valid edges and append one diagnostic for each skipped edge.

Implement the path search with a `Set(String)` of visited instance IDs. A
self-edge creates a cycle. Port-level edges between the same pair of component
instances share the same graph arc for cycle detection.

Expose accessors:

```gleam
pub fn connections(graph: EffectiveGraph) -> List(Connection)
pub fn errors(graph: EffectiveGraph) -> List(GraphError)
pub fn outgoing(graph: EffectiveGraph, source: PortRef) -> List(Connection)
```

`outgoing` preserves effective graph order.

- [ ] **Step 5: Run the graph tests on both targets**

Run:

```bash
gleam test
gleam test --target javascript
```

Expected: both commands pass.

- [ ] **Step 6: Add a permutation property test**

Use a small fixed edge set and `list.permutations`. For each permutation,
assert that `effective` returns the same connection IDs and diagnostics. Include
the two-edge concurrent cycle in the set.

Run:

```bash
gleam test
```

Expected: PASS.

- [ ] **Step 7: Format and build**

Run:

```bash
gleam format src/watershed/port_graph.gleam test/watershed/port_graph_test.gleam
gleam build --target erlang
gleam build --target javascript
```

Expected: both builds pass.

- [ ] **Step 8: Commit deterministic graph handling**

```bash
git add src/watershed/port_graph.gleam test/watershed/port_graph_test.gleam
git commit -m "feat: validate component port graphs"
```

---

### Task 4: Origin-aware dispatch planning

**Files:**
- Create: `src/watershed/dispatch.gleam`
- Create: `test/watershed/dispatch_test.gleam`

**Interfaces:**
- Consumes:
  - `port.Descriptor`
  - `port.InputClass`
  - `port_graph.EffectiveGraph`
  - `port_graph.PortRef`
- Produces:
  - `dispatch.Origin`
  - `dispatch.Trace`
  - `dispatch.Delivery`
  - `dispatch.DispatchError`
  - `dispatch.Plan`
  - `dispatch.plan`
  - `dispatch.deliveries`
  - `dispatch.errors`

- [ ] **Step 1: Write local-intent and remote-echo tests**

Create `test/watershed/dispatch_test.gleam`:

```gleam
import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/dispatch
import watershed/port
import watershed/port_graph

fn ports(instance_id: String) -> Result(List(port.Descriptor), Nil) {
  case instance_id {
    "tasks" ->
      Ok([
        port.Descriptor("completed", port.OutputPort, "task@1", None),
      ])
    "activity" ->
      Ok([
        port.Descriptor(
          "append",
          port.InputPort,
          "task@1",
          Some(
            port.CollaborativeInput(
              capabilities: ["sequence:insert"],
            ),
          ),
        ),
      ])
    "notes" ->
      Ok([
        port.Descriptor(
          "focus",
          port.InputPort,
          "task@1",
          Some(port.LocalInput),
        ),
      ])
    _ -> Error(Nil)
  }
}

fn graph() -> port_graph.EffectiveGraph {
  port_graph.effective(
    [
      port_graph.connection(
        "activity",
        port_graph.PortRef("tasks", "completed"),
        port_graph.PortRef("activity", "append"),
      ),
      port_graph.connection(
        "notes",
        port_graph.PortRef("tasks", "completed"),
        port_graph.PortRef("notes", "focus"),
      ),
    ],
    ports,
  )
}

pub fn local_intent_fans_out_in_edge_order_test() -> Nil {
  let planned =
    dispatch.plan(
      trace_id: "trace-1",
      origin: dispatch.LocalIntent,
      source: port_graph.PortRef("tasks", "completed"),
      payload: json.string("task-42"),
      graph: graph(),
      ports_for: ports,
    )

  dispatch.deliveries(planned)
  |> list.map(fn(delivery) { delivery.edge_id })
  |> expect.to_equal(["activity", "notes"])
}

pub fn replicated_change_produces_no_deliveries_test() -> Nil {
  dispatch.plan(
    trace_id: "trace-2",
    origin: dispatch.ReplicatedChange,
    source: port_graph.PortRef("tasks", "completed"),
    payload: json.string("task-42"),
    graph: graph(),
    ports_for: ports,
  )
  |> dispatch.deliveries
  |> expect.to_equal([])
}

pub fn delivery_keeps_target_class_and_capabilities_test() -> Nil {
  let assert [delivery, ..] =
    dispatch.plan(
      "trace-3",
      dispatch.LocalIntent,
      port_graph.PortRef("tasks", "completed"),
      json.string("task-42"),
      graph(),
      ports,
    )
    |> dispatch.deliveries

  delivery.input_class
  |> expect.to_equal(
    port.CollaborativeInput(capabilities: ["sequence:insert"]),
  )
}
```

Add the final imports for `gleam/list`.

- [ ] **Step 2: Write duplicate-edge and stale-descriptor tests**

Although `EffectiveGraph` removes duplicate edge IDs, dispatch must still avoid
repeating an edge in one trace if a future graph source supplies duplicates.
Keep `EffectiveGraph` opaque, so test the public guarantee by asserting unique
delivery edge IDs from the effective graph.

Add a stale-descriptor test where `ports_for` no longer returns the target port
that existed during graph normalization. Assert
`TargetUnavailable(edge_id, target_ref)` and no delivery for that edge. This
models a host catalog change between graph construction and dispatch.

- [ ] **Step 3: Run the dispatch tests and confirm the module is missing**

Run:

```bash
gleam test
```

Expected: FAIL because `src/watershed/dispatch.gleam` does not exist.

- [ ] **Step 4: Implement pure dispatch planning**

Create `src/watershed/dispatch.gleam`:

```gleam
import gleam/json.{type Json}
import watershed/port
import watershed/port_graph

pub type Origin {
  LocalIntent
  ReplicatedChange
}

pub type Trace {
  Trace(id: String)
}

pub type Delivery {
  Delivery(
    trace: Trace,
    edge_id: String,
    target: port_graph.PortRef,
    input_class: port.InputClass,
    payload: Json,
  )
}

pub type DispatchError {
  SourceUnavailable(source: port_graph.PortRef)
  TargetUnavailable(
    edge_id: String,
    target: port_graph.PortRef,
  )
}

pub opaque type Plan {
  Plan(
    deliveries: List(Delivery),
    errors: List(DispatchError),
  )
}
```

Implement:

```gleam
pub fn plan(
  trace_id trace_id: String,
  origin origin: Origin,
  source source: port_graph.PortRef,
  payload payload: Json,
  graph graph: port_graph.EffectiveGraph,
  ports_for ports_for: fn(String) -> Result(List(port.Descriptor), Nil),
) -> Plan
```

For `ReplicatedChange`, return an empty plan without reading the graph. For
`LocalIntent`:

1. Verify that the source descriptor still exists and is `OutputPort`.
2. Read `port_graph.outgoing(graph, source)`.
3. Resolve each target descriptor again.
4. Read the target's `Some(input_class)`.
5. Copy the encoded payload into a `Delivery`.
6. Preserve edge order.
7. Record `TargetUnavailable` when the target instance or input is absent.

Do not decode the payload in this module. The runtime execution plan will use
the typed input decoder immediately before it calls component code. This module
does not have access to the typed `Input(payload)` hidden behind the catalog
adapter.

Expose:

```gleam
pub fn deliveries(plan: Plan) -> List(Delivery)
pub fn errors(plan: Plan) -> List(DispatchError)
```

- [ ] **Step 5: Run dispatch tests on both targets**

Run:

```bash
gleam test
gleam test --target javascript
```

Expected: both commands pass.

- [ ] **Step 6: Add the project-room acceptance unit**

Add one pure test containing the two project-room edges from the design:

- `TaskSelected` to `FocusSubject` with `LocalInput`;
- `TaskCompleted` to `AppendEntry` with `CollaborativeInput`.

Assert the first delivery class is local, the second is collaborative, and
running the same plans with `ReplicatedChange` returns no deliveries.

Run:

```bash
gleam test
```

Expected: PASS.

- [ ] **Step 7: Format and build**

Run:

```bash
gleam format src/watershed/dispatch.gleam test/watershed/dispatch_test.gleam
gleam build --target erlang
gleam build --target javascript
```

Expected: both builds pass.

- [ ] **Step 8: Commit dispatch planning**

```bash
git add src/watershed/dispatch.gleam test/watershed/dispatch_test.gleam
git commit -m "feat: plan component port dispatch"
```

---

### Task 5: Foundation integration gate

**Files:**
- Verify: `src/watershed/port.gleam`
- Verify: `src/watershed/component.gleam`
- Verify: `src/watershed/port_graph.gleam`
- Verify: `src/watershed/dispatch.gleam`
- Verify: their matching tests and `justfile`

**Interfaces:**
- Consumes: all interfaces from Tasks 1 through 4.
- Produces: one target-independent foundation ready for the workspace
  persistence plan.

- [ ] **Step 1: Run targeted foundation tests together**

Run:

```bash
gleam test
gleam test --target javascript
```

Expected: both target suites pass.

- [ ] **Step 2: Run the compile-fail gate**

Run:

```bash
just _test-compile-fail
```

Expected: both compile-fail fixtures print `ok`.

- [ ] **Step 3: Run repository formatting and lint checks**

Run:

```bash
just format
just lint
```

Expected: both commands pass with no uncommitted formatting changes outside
the files in this plan.

- [ ] **Step 4: Run the full repository test and build gates**

Run:

```bash
just test
just build
```

Expected: both commands pass.

- [ ] **Step 5: Check the complete foundation diff**

Run:

```bash
git --no-pager diff HEAD~4 --check
git --no-pager diff HEAD~4 --stat
```

Expected: no whitespace errors. The diff contains the four modules, four test
modules, one compile-fail package, and the `justfile` assertion.

The next plan may start after this gate passes.
