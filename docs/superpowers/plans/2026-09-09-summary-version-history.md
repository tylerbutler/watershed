# Summary Version History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. For this repository owner, execute inline without subagents.

**Goal:** Make Watershed summary history use Routerlicious-style Git commits and a document head, so callers can list and load published checkpoints and a successful `summarize` returns a durable published version ID.

**Architecture:** Floodgate remains the publication authority. A client uploads a summary tree and submits a parent-linked summarize proposal; Floodgate validates the proposal against the current document head, stores and sequences an acknowledgement, advances the authoritative summary pointer, and publishes the document ref. Watershed tracks proposals through `summaryAck` or `summaryNack`, uses commit SHAs as public version IDs, and reads history through Floodgate's existing Historian commit routes.

**Tech Stack:** Gleam on Erlang and JavaScript, Spillway wire types, Floodgate, Silt Git objects and REST shapes, Shelf/DETS persistence, startest, gleeunit, and the existing live integration suites.

**Spec:** `docs/plans/2026-08-09-summary-bootstrap-plan.md`, SB5 as revised on 2026-09-09.

**Status:** Complete on 2026-09-09. Watershed and Floodgate expose commit-backed summary history on JavaScript and BEAM.

**Planning baselines:** Watershed `f4eb13b48e8efbfe3bc13e104f2965308fb35e86`; Floodgate `98a05ccd7650a7cd62e250c08fa329b5a37be4fe`; Silt `7df0c9e60e6d4de94fadb3a351b32cac801cb69b`.

## Execution record

Watershed:

- `5fa1d4a` decodes Floodgate bootstrap summary fields.
- `4012ae2` reads published commit history and loads commit-backed snapshots.
- `910d263` tracks proposals, acknowledgements, rejections, and the published head.
- `e76b482` handles Floodgate's empty bootstrap sentinel.
- `33913bf` waits for JavaScript publication acknowledgements.
- `eca20db` waits for BEAM publication acknowledgements without blocking actor progress.

Floodgate:

- `4526619` through `fe654e8` add parent validation, serialized publication, recovery, document-scoped history, and restart coverage.
- `af88942` accepts Routerlicious tree entries that omit `mode` when it reads a parent summary.

Acceptance coverage proves newest-first history, count limits, historical loads, JavaScript commit IDs, and a competing BEAM summarizer retry from the winning head. The checklist below records the implementation procedure; its unchecked boxes are historical, not remaining work.

## Global Constraints

- Treat Fluid Framework and Routerlicious behavior as canonical. Do not add a Watershed-specific `/versions/:tenant/:document` endpoint.
- Use the existing `GET /repos/:tenant/commits?sha=<document>&count=<count>` route and `refs/heads/<document>` publication ref.
- A public version ID is a published commit SHA. An uploaded tree SHA is staging data and is not a published version.
- Keep the summary blob format at v4. The blob's `sequenceNumber` remains the state capture point.
- Keep the summarize proposal's `referenceSequenceNumber` as the state capture boundary and the proposal's sequenced number as publication metadata. Do not substitute either for the blob's load point.
- A manual `summarize` succeeds only after its `summaryAck` identifies the published commit. Upload plus proposal submission is not success.
- An automatic summary advances the policy checkpoint only after `summaryAck`. A rejected proposal must remain eligible for retry.
- Floodgate must publish one linear first-parent chain per document. A proposal based on a stale parent is rejected and must not advance the pointer or ref.
- Uploaded trees and commits that never publish are allowed to remain unreachable. They must never appear in version history.
- The session summary pointer is authoritative. The document ref is its discoverable projection and must converge to it after restart.
- Preserve tenant and document authorization. A commit ID from another document must not become loadable through a token for the current document.
- Preserve current JavaScript promise APIs and BEAM `Result` APIs, except that summary handles become commit IDs and `SummaryVersion` loses the unsupported sequence-number promise described below.
- Add no dependency and no new test runner.
- Use ASD-STE100 for Gleam comments, docs, and error strings. Use normal prose in Markdown.
- Commit Watershed and Floodgate changes separately in their own repositories. Do not use cross-repository commits or local path dependencies.
- Do not add Co-authored-by trailers.

## Canonical contract

### Staged tree and published version

`git_storage.upload_summary` continues to upload a blob and tree. Its result is a staged tree SHA used in the summarize proposal:

```gleam
pub type UploadedSummary {
  UploadedSummary(tree_id: String)
}
```

The proposal carries the staged tree plus the last published commit as its first parent:

```json
{
  "handle": "<uploaded tree sha>",
  "head": "<current published commit sha>",
  "message": "watershed summary",
  "parents": ["<current published commit sha>"]
}
```

The first summary uses `head: ""` and `parents: []`. Floodgate creates the commit; clients do not post commits or mutate the document ref directly.

### Published version

Replace the current tree-shaped version model with a commit-shaped model:

```gleam
pub type SummaryVersion {
  SummaryVersion(
    id: String,
    tree_id: String,
    message: String,
    created_at: String,
  )
}
```

- `id` is the published commit SHA and is the argument accepted by `load_version`.
- `tree_id` is the commit's root tree SHA and is diagnostic metadata. Callers do not need it to load the version.
- `created_at` comes from `commit.committer.date`.
- Remove `sequence_number`. Silt's commit-history response does not carry it, and Fluid's `IVersion` does not require it. The loaded `SummaryBlob.sequence_number` remains available when a caller needs the snapshot capture point.

`get_versions(document, count)` preserves the server's newest-first first-parent order. Reject `count <= 0` before sending a request.

### Acknowledgement lifecycle

Add pure decoded events for sequenced summary messages:

```gleam
pub type SummaryEvent {
  SummaryProposalSequenced(
    client_id: Option(String),
    client_sequence_number: Int,
    sequence_number: Int,
  )
  SummaryPublished(
    proposal_sequence_number: Int,
    version_id: String,
  )
  SummaryRejected(
    proposal_sequence_number: Int,
    reason: String,
  )
}
```

Extend `runtime_core.Ingested` with `summary_events: List(SummaryEvent)`. The core updates `last_summary_sequence_number` and `summary_head` only for `SummaryPublished`. Target-specific runtimes own promise/reply waiters.

## Repository file map

### Watershed

- `src/watershed/wire/socket.gleam` — decode both canonical Floodgate flat summary fields and the existing nested compatibility field into one `SummaryContext`.
- `src/watershed/wire/summary.gleam` — new pure codecs for summarize, `summaryAck`, and `summaryNack` contents.
- `src/watershed/git_storage.gleam` — commit-history URLs and decoders; commit-to-tree resolution; summary blob loading.
- `src/watershed/runtime_core.gleam` — published head, summary events, policy checkpoint, parent stamping.
- `src/watershed/runtime.gleam` — JavaScript pending summary promises and lifecycle cleanup.
- `src/watershed/runtime_beam.gleam` — BEAM pending summary replies and lifecycle cleanup.
- `src/watershed.gleam`, `src/watershed_beam.gleam` — public version docs and types.
- `test/watershed/wire_test.gleam` — handshake and summary response codecs.
- `test/watershed/runtime_core_test.gleam` — proposal, ack, nack, head, and policy transitions.
- `test/watershed/integration_test.gleam` — published history, load, rejection, restart, and target parity.
- `test/live_js.gleam` — JavaScript promise behavior against Floodgate.

### Floodgate

- `src/floodgate/document_channel.gleam` — validate parent/head, create commits, emit ack/nack, and publish the ref.
- `src/floodgate/session.gleam` — persist the summary operation, response, and authoritative pointer in recoverable order.
- `src/floodgate/doc_state.gleam` — rebuild and repair the summary pointer/ref from durable operations.
- `src/floodgate/git.gleam` — server-owned summary-ref convergence.
- `src/floodgate/store.gleam`, `src/floodgate/memory_store.gleam`, `src/floodgate/shelf_store.gleam` — only if the recovery tests prove the existing pointer API cannot express the required repair.
- `test/phoenix_channel_test.gleam` — summarize protocol, stale-parent rejection, and ack/nack shapes.
- `test/floodgate_test.gleam` — commit lineage and restart recovery.
- `test/store_backend_test.gleam` — backend parity if storage operations change.
- `client/test/conformance/floodgate-routerlicious.test.ts` — canonical Routerlicious history and historical snapshot loading.

---

### Task 1: Decode the current Floodgate bootstrap contract

**Repository:** Watershed

**Files:**
- Modify: `src/watershed/wire/socket.gleam`
- Test: `test/watershed/wire_test.gleam`

**Interfaces:**
- Consumes: Floodgate's flat `summaryHandle` and `summarySequenceNumber` fields.
- Produces: `ConnectedMessage.summary_context: Option(SummaryContext)` for both flat and nested wire shapes.

- [ ] **Step 1: Add a failing flat-field handshake test**

Add a fixture with:

```json
{
  "summaryHandle": "commit-abc",
  "summarySequenceNumber": 40
}
```

Assert that `socket.connected_message_decoder()` produces:

```gleam
Some(SummaryContext(handle: "commit-abc", sequence_number: 40))
```

Keep the existing nested `summaryContext` test.

- [ ] **Step 2: Add conflict and partial-field tests**

Assert these rules:

```text
nested summaryContext present     -> nested value wins
both flat fields present          -> construct SummaryContext
only one flat field present       -> decoding fails
no summary fields present         -> None
```

- [ ] **Step 3: Run the focused test and verify failure**

Run:

```bash
gleam test --target erlang -- wire
```

Expected: the flat-field fixture does not populate `summary_context`.

- [ ] **Step 4: Implement one compatibility decoder**

Decode the nested field and both flat fields, then resolve them with this precedence:

```gleam
case nested, flat_handle, flat_sequence_number {
  Some(context), _, _ -> Ok(Some(context))
  None, Some(handle), Some(sequence_number) ->
    Ok(Some(SummaryContext(handle: handle, sequence_number: sequence_number)))
  None, None, None -> Ok(None)
  _ -> Error(Nil)
}
```

Do not change `spillway/message.ConnectedMessage`.

- [ ] **Step 5: Run the focused suites**

Run:

```bash
gleam test --target erlang -- wire
gleam test --target javascript -- wire
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add src/watershed/wire/socket.gleam test/watershed/wire_test.gleam
git commit -m "fix(summary): decode floodgate checkpoint fields"
```

**Acceptance:** A current Floodgate connection starts from its published summary instead of silently replaying from zero.

---

### Task 2: Make Floodgate publication a linear compare-and-set

**Repository:** Floodgate

**Files:**
- Modify: `src/floodgate/document_channel.gleam`
- Modify: `src/floodgate/session.gleam`
- Test: `test/phoenix_channel_test.gleam`
- Test: `test/floodgate_test.gleam`

**Interfaces:**
- Consumes: `SummarizeContents.parents`, the current `session.summary`, and the staged tree in `handle`/`head`.
- Produces: one accepted first-parent chain; stale proposals receive `summaryNack` and do not change the pointer or ref.

- [ ] **Step 1: Add a failing first-summary test**

Submit a proposal with `parents: []` to a document with no summary. Assert:

```text
summaryAck.contents.handle is a commit SHA
GET /repos/<tenant>/commits?sha=<document>&count=10 returns one commit
that commit has parents: []
```

- [ ] **Step 2: Add a failing child-summary test**

Submit a second proposal whose only parent is the first commit. Assert the history response is `[second, first]` and the document ref points to `second`.

- [ ] **Step 3: Add a failing stale-parent race test**

Upload two trees from the same published parent. Sequence proposal A, then proposal B with the same parent. Assert:

```text
A -> summaryAck
B -> summaryNack with "Summary parent is not the published head"
pointer -> A commit
ref -> A commit
history -> A followed by the original parent
```

No commit created for B may become reachable from the document ref.

- [ ] **Step 4: Run the tests and verify the stale proposal is accepted today**

Run:

```bash
gleam test -- phoenix_channel
gleam test -- floodgate
```

Expected: the stale-parent assertion fails because current code accepts client-supplied sibling parents.

- [ ] **Step 5: Add parent validation before commit creation**

Use this rule in the document actor's serialized summary path:

```gleam
case current_summary_handle, contents.parents {
  "", [] -> Ok(Nil)
  current, [parent] if parent == current -> Ok(Nil)
  _, _ -> Error("Summary parent is not the published head")
}
```

Reject multiple parents. Check `contents.handle == contents.head`. Verify the staged tree exists before creating the commit.

The current head read and pointer update must occur inside the same document actor transition. Do not read the head in the channel process and update it later.

- [ ] **Step 6: Keep rejection sequenced and observable**

A stale parent produces the existing paired summarize proposal plus `summaryNack`. It does not call `store.put_summary` or `git.publish_summary_ref`.

- [ ] **Step 7: Run focused and canonical suites**

Run:

```bash
gleam test -- phoenix_channel
gleam test -- floodgate
just test-routerlicious
```

Expected: all pass.

- [ ] **Step 8: Commit in Floodgate**

```bash
git add src/floodgate/document_channel.gleam src/floodgate/session.gleam test/phoenix_channel_test.gleam test/floodgate_test.gleam
git commit -m "fix(summary): linearize published history"
```

**Acceptance:** Two concurrent proposals cannot create two published children of one head.

---

### Task 3: Repair every acknowledged publication after restart

**Repository:** Floodgate

**Files:**
- Modify: `src/floodgate/doc_state.gleam`
- Modify: `src/floodgate/git.gleam`
- Modify if required: `src/floodgate/store.gleam`
- Modify if required: `src/floodgate/memory_store.gleam`
- Modify if required: `src/floodgate/shelf_store.gleam`
- Test: `test/floodgate_test.gleam`
- Test if required: `test/store_backend_test.gleam`

**Interfaces:**
- Consumes: durable summarize and `summaryAck` operations, `store.get_summary`, and `refs/heads/<document>`.
- Produces: one recovered authoritative pointer and a ref equal to that pointer.

- [ ] **Step 1: Add crash-prefix fixtures**

Construct backend states for each write prefix:

```text
objects only
objects + summarize op
objects + summarize op + summaryAck
objects + ops + pointer
objects + ops + pointer + ref
```

Use real encoded summarize and acknowledgement messages, not sentinel strings.

- [ ] **Step 2: State the recovery expectations in tests**

```text
objects only                         -> no published summary
summarize without ack                -> no published summary
summaryAck with valid commit         -> repair pointer and ref to commit
pointer without ref                  -> repair ref to pointer
lagging ref behind newer pointer     -> advance ref to pointer
ref ahead of pointer                 -> reset ref to pointer
```

The dedicated summary ref is server-owned. Remove the old assumption that an external client may intentionally move it.

- [ ] **Step 3: Run the focused tests and verify failures**

Run:

```bash
gleam test -- floodgate
```

Expected: ack-only recovery and lagging-ref convergence fail.

- [ ] **Step 4: Derive the latest acknowledged commit from the durable log**

Add a pure fold in `doc_state.gleam` that recognizes `summaryAck` messages, decodes `contents.handle`, verifies the referenced commit exists, and selects the ack with the greatest sequence number.

Use the recovered acknowledgement only when it is newer than or repairs the stored pointer. Ignore malformed messages and missing commits; they are not publishable versions.

- [ ] **Step 5: Make the summary ref converge to the authoritative pointer**

Replace missing-only repair with:

```gleam
pub fn reconcile_summary_ref(
  storage: store.Backend,
  tenant: String,
  document_id: String,
  commit_id: String,
) -> Result(Nil, Nil)
```

If the ref differs from the pointer, write the pointer value. This ref is not a user branch.

- [ ] **Step 6: Run memory and Shelf backend tests**

Run:

```bash
gleam test -- floodgate
gleam test -- store_backend
```

Expected: all crash-prefix cases pass on both backends.

- [ ] **Step 7: Commit in Floodgate**

```bash
git add src/floodgate/doc_state.gleam src/floodgate/git.gleam src/floodgate/store.gleam src/floodgate/memory_store.gleam src/floodgate/shelf_store.gleam test/floodgate_test.gleam test/store_backend_test.gleam
git commit -m "fix(summary): recover published head"
```

Omit unchanged storage files from the commit.

**Acceptance:** A crash cannot make an acknowledged version disappear from the document's first-parent history.

---

### Task 4: Read commit history and load commit-backed snapshots

**Repository:** Watershed

**Files:**
- Modify: `src/watershed/git_storage.gleam`
- Test: `test/watershed/integration_test.gleam`
- Create: `test/watershed/git_storage_test.gleam` if no focused storage decoder test file exists

**Interfaces:**
- Consumes: Silt commit-history JSON and commit/tree/blob REST routes.
- Produces: the new `SummaryVersion` type, `fetch_versions`, and commit-aware `fetch_summary` on both targets.

- [ ] **Step 1: Add pure decoder tests for Silt's response**

Decode this shape:

```json
[{
  "sha": "commit-2",
  "commit": {
    "message": "watershed summary",
    "committer": {"date": "1720000000"},
    "tree": {"sha": "tree-2"}
  },
  "parents": [{"sha": "commit-1"}]
}]
```

Assert:

```gleam
[
  SummaryVersion(
    id: "commit-2",
    tree_id: "tree-2",
    message: "watershed summary",
    created_at: "1720000000",
  ),
]
```

- [ ] **Step 2: Add request-construction tests**

Pin this URL:

```text
/repos/<tenant>/commits?sha=<document>&count=<count>
```

Assert `count <= 0` returns a typed local error and makes no request.

- [ ] **Step 3: Add commit-to-tree load tests**

For `load_version(document, "commit-2")`, assert the client requests:

```text
GET /repos/<tenant>/git/commits/commit-2
GET /repos/<tenant>/git/trees/tree-2
GET /repos/<tenant>/git/blobs/<header sha>
```

The returned `SummaryBlob.sequence_number` comes from the blob.

- [ ] **Step 4: Add the narrow legacy-tree fallback**

When the commit request returns 404, try the supplied ID as a tree SHA. Do not fall back after 401, 403, 500, a malformed commit, or a commit whose tree is malformed.

This keeps old stored summary handles loadable without treating every storage failure as an old-format handle.

- [ ] **Step 5: Run the focused tests and verify failure**

Run:

```bash
gleam test --target erlang -- git_storage
gleam test --target javascript -- git_storage
```

Expected: current code requests `/versions` and treats the supplied ID as a tree.

- [ ] **Step 6: Implement the new model and decoders**

Replace:

```gleam
SummaryVersion(handle, sequence_number, message, created_at)
```

with the canonical type in this plan. Decode the top-level history as a list, not `{value: ...}`.

- [ ] **Step 7: Run target suites**

Run:

```bash
gleam test --target erlang -- git_storage
gleam test --target javascript -- git_storage
gleam format --check src test
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add src/watershed/git_storage.gleam test/watershed/git_storage_test.gleam test/watershed/integration_test.gleam
git commit -m "feat(summary): read commit-backed versions"
```

Use only the test files that changed.

**Acceptance:** Watershed lists Floodgate's first-parent history and loads any listed commit without a custom versions endpoint.

---

### Task 5: Model summary publication in the pure runtime core

**Repository:** Watershed

**Files:**
- Create: `src/watershed/wire/summary.gleam`
- Modify: `src/watershed/runtime_core.gleam`
- Modify: `src/watershed/wire/op.gleam`
- Test: `test/watershed/wire_test.gleam`
- Test: `test/watershed/runtime_core_test.gleam`

**Interfaces:**
- Consumes: sequenced `summarize`, `summaryAck`, and `summaryNack` messages.
- Produces: `SummaryEvent`, `Core.summary_head`, correct policy checkpoints, and parent-linked outbound proposals.

- [ ] **Step 1: Add summary response codec tests**

Pin the Floodgate shapes:

```gleam
SummaryAck(
  proposal_sequence_number: 41,
  version_id: "commit-abc",
)

SummaryNack(
  proposal_sequence_number: 41,
  reason: "Summary parent is not the published head",
)
```

Reject missing handles, missing proposal numbers, and missing nack messages.

- [ ] **Step 2: Add core transition tests**

Cover these cases:

```text
bootstrap with summary context       -> summary_head is context.handle
build first proposal                 -> parents is []
build later proposal                 -> parents is [summary_head]
proposal sequences without ack       -> policy checkpoint does not advance
summaryAck sequences                 -> head and checkpoint advance; event emitted
summaryNack sequences                -> head/checkpoint unchanged; rejection emitted
foreign summaryAck                   -> every client adopts the published head
older replayed summaryAck            -> cannot move head/checkpoint backward
```

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
gleam test --target erlang -- runtime_core
gleam test --target javascript -- runtime_core
```

Expected: current core advances on `summarize`, ignores ack/nack, and always writes `parents: []`.

- [ ] **Step 4: Add the pure wire types and decoder**

Create `watershed/wire/summary.gleam` with:

```gleam
pub type SummaryResponse {
  Ack(proposal_sequence_number: Int, version_id: String)
  Nack(proposal_sequence_number: Int, reason: String)
}

pub fn decode_message(
  message_type: String,
  contents: Dynamic,
) -> Result(SummaryResponse, Nil)
```

Return `Error(Nil)` for non-summary-response message types.

- [ ] **Step 5: Extend core state and ingestion**

Add:

```gleam
summary_head: Option(String)
```

to `Core`, and:

```gleam
summary_events: List(SummaryEvent)
```

to `Ingested`. Seed the head from `ConnectedMessage.summary_context`. Set `last_summary_sequence_number` from the context's publication sequence number while retaining the blob's sequence number as `last_seen_sequence_number`.

- [ ] **Step 6: Stamp proposals from the published head**

Change `build_summarize` to pass:

```gleam
parents: option.to_list(core.summary_head)
```

Remove its eager update of `last_summary_sequence_number`.

- [ ] **Step 7: Apply ack/nack transitions**

On `summaryAck`, use `int.max` for the policy checkpoint and emit `SummaryPublished`. Update `summary_head` only when the ack is not older than the current checkpoint. On `summaryNack`, emit `SummaryRejected` without moving state.

- [ ] **Step 8: Run focused suites**

Run:

```bash
gleam test --target erlang -- runtime_core
gleam test --target javascript -- runtime_core
gleam test --target erlang -- wire
gleam test --target javascript -- wire
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add src/watershed/wire/summary.gleam src/watershed/wire/op.gleam src/watershed/runtime_core.gleam test/watershed/wire_test.gleam test/watershed/runtime_core_test.gleam
git commit -m "feat(summary): track published commit head"
```

**Acceptance:** The pure core distinguishes proposed, published, and rejected summaries and never builds a stale parent intentionally.

---

### Task 6: Resolve JavaScript summarize promises on publication

**Repository:** Watershed

**Files:**
- Modify: `src/watershed/runtime.gleam`
- Modify if required: `src/watershed/runtime_ffi.mjs`
- Test: `test/live_js.gleam`
- Test: `test/watershed/runtime_core_test.gleam`

**Interfaces:**
- Consumes: `Ingested.summary_events` from Task 5.
- Produces: `summarize` promises that resolve with a published commit ID or reject with a summary nack/lifecycle error.

- [ ] **Step 1: Add a deferred-success test**

Use the existing injected transport pattern. Assert:

```text
construct summarize promise          -> no result yet
upload completes and proposal sends  -> no result yet
proposal echoes                      -> no result yet
summaryAck arrives                   -> Ok("commit-abc")
```

The returned value must differ from the staged tree SHA.

- [ ] **Step 2: Add rejection and lifecycle tests**

Assert:

```text
summaryNack                          -> Error(server message)
disconnect before ack                -> Error("summary publication was interrupted")
close before ack                     -> same error
late ack after failure               -> ignored
second simultaneous summarize call   -> Error("a summary publication is already pending")
```

Keep one pending manual summary per runtime. Automatic summaries use the same proposal state but no external promise.

- [ ] **Step 3: Run the JavaScript tests and verify failure**

Run:

```bash
gleam test --target javascript -- live_js
```

Expected: current `summarize` resolves immediately with the tree SHA.

- [ ] **Step 4: Add pending summary state**

Add a target-specific record that retains:

```gleam
PendingSummary(
  tree_id: String,
  client_sequence_number: Int,
  proposal_sequence_number: Option(Int),
  resolve: fn(Result(String, String)) -> Nil,
)
```

Use the existing promise construction pattern used by other deferred runtime outcomes. Do not put callbacks in `runtime_core`.

- [ ] **Step 5: Reconcile `summary_events` after every ingested batch**

- Match the local proposal echo by `client_sequence_number` and store its server sequence number.
- Match ack/nack by proposal sequence number.
- Resolve exactly once and clear the pending record before invoking the callback.
- Let foreign acknowledgements update the core head without touching the local waiter.

- [ ] **Step 6: Make auto-summary failures retryable**

An upload error or nack leaves the policy checkpoint unchanged. Clear `summary_armed`; the next sequenced message may arm another attempt. Report the failure through the existing callback error reporter, not an unhandled promise rejection.

- [ ] **Step 7: Run the focused JavaScript suites**

Run:

```bash
gleam test --target javascript -- live_js
gleam test --target javascript -- runtime
node smoke/runtime_bootstrap.mjs
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add src/watershed/runtime.gleam src/watershed/runtime_ffi.mjs test/live_js.gleam test/watershed/runtime_core_test.gleam
git commit -m "feat(summary): await published version on javascript"
```

Omit the FFI and core test files if unchanged.

**Acceptance:** JavaScript callers cannot mistake an uploaded tree or rejected proposal for a published version.

---

### Task 7: Resolve BEAM summarize calls without blocking the actor

**Repository:** Watershed

**Files:**
- Modify: `src/watershed/runtime_beam.gleam`
- Test: `test/watershed/integration_test.gleam`

**Interfaces:**
- Consumes: `Ingested.summary_events` from Task 5.
- Produces: synchronous public `Result` semantics backed by an actor-held pending reply.

- [ ] **Step 1: Add an actor-progress regression**

Start `summarize` from another process, hold the ack, and deliver an ordinary sequenced operation. Assert the runtime applies the operation before the summarize call returns.

This proves the actor stores the caller's reply subject and continues; it must not wait inside the actor handler.

- [ ] **Step 2: Add success, nack, timeout, and disconnect tests**

Pin these results:

```text
summaryAck            -> Ok(commit id)
summaryNack           -> Error(server message)
disconnect            -> Error("summary publication was interrupted")
call timeout           -> caller times out; later ack is safe and clears state
```

- [ ] **Step 3: Run the focused Erlang tests and verify failure**

Run:

```bash
gleam test --target erlang -- integration
```

Expected: current call returns the staged tree before an ack exists.

- [ ] **Step 4: Store the reply subject in actor state**

Change `handle_summarize` to upload, submit, retain the reply subject, and call `actor.continue`. Resolve it only while processing summary events. Reject a second manual call while one is pending.

- [ ] **Step 5: Apply the same cleanup rules as JavaScript**

Disconnect, close, reconnect replacement, and terminal failure resolve the pending reply once with an interruption error. Late acks update the core head but do not send a second reply.

- [ ] **Step 6: Run Erlang suites**

Run:

```bash
gleam test --target erlang -- integration
gleam test --target erlang -- runtime
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add src/watershed/runtime_beam.gleam test/watershed/integration_test.gleam
git commit -m "feat(summary): await published version on beam"
```

**Acceptance:** The BEAM API remains synchronous to its caller while the runtime actor continues processing protocol messages needed to complete that call.

---

### Task 8: Update public APIs and replace the obsolete live test

**Repository:** Watershed

**Files:**
- Modify: `src/watershed.gleam`
- Modify: `src/watershed_beam.gleam`
- Modify: `test/watershed/integration_test.gleam`
- Modify: `test/live_js.gleam`
- Modify: `README.md`
- Modify: `watershed_lustre/README.md` only if it mentions summary handles
- Modify: `docs/plans/2026-08-09-summary-bootstrap-plan.md`
- Modify: `docs/demo-ideas.md`

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: accurate public documentation and cross-target acceptance coverage.

- [ ] **Step 1: Rewrite `summary_versions_test` around published commits**

The test must prove:

```text
no summary                         -> []
first summarize returns commit 1  -> history [commit 1]
second summarize returns commit 2 -> history [commit 2, commit 1]
count 1                            -> [commit 2]
load commit 1                      -> first snapshot
load commit 2                      -> second snapshot
live document                      -> unchanged by historical reads
```

Assert `version.id` equals the summarize result and `version.tree_id` does not equal the commit ID.

- [ ] **Step 2: Add a concurrent summarizer acceptance test**

Two clients upload from one head. One publishes; the other receives a stale-parent nack. Retry the loser after it observes the winning ack. Assert the final history is one linear chain containing both successfully published retries, with no sibling in the listed history.

- [ ] **Step 3: Add restart acceptance**

Publish two versions, restart Floodgate without deleting its persistent store, reconnect, list both versions, and load the older one. This is the end-to-end gate for Task 3.

- [ ] **Step 4: Correct public API documentation**

State:

```text
summarize -> published commit ID after summaryAck
get_versions -> published commits, newest first
load_version -> snapshot captured by a published commit ID
SummaryBlob.sequence_number -> capture point
```

Remove claims that each call stores a version before acknowledgement or that handles are tree SHAs.

- [ ] **Step 5: Update plan and backlog status**

Mark SB5 complete only after both repositories pass their final gates. Link this execution record from the August plan and `docs/demo-ideas.md`. Until then, keep this plan's status as in progress and record each repository commit separately.

- [ ] **Step 6: Run Floodgate final gates**

From the Floodgate checkout:

```bash
just test
just lint
just test-routerlicious
just test-dual-mode
```

Expected: all pass.

- [ ] **Step 7: Run Watershed final gates**

With the tested Floodgate build running:

```bash
WATERSHED_INTEGRATION=1 gleam test --target erlang -- integration
gleam test --target javascript -- live_js
just test
just build
just lint
```

Expected: all pass. Confirm the live suite is connected to Floodgate, not Levee or a stale process.

- [ ] **Step 8: Commit Watershed documentation and acceptance changes**

```bash
git add src/watershed.gleam src/watershed_beam.gleam test/watershed/integration_test.gleam test/live_js.gleam README.md watershed_lustre/README.md docs/plans/2026-08-09-summary-bootstrap-plan.md docs/demo-ideas.md docs/superpowers/plans/2026-09-09-summary-version-history.md
git commit -m "docs(summary): record published version history"
```

Stage only files that changed.

**Acceptance:** Both targets expose the same published-version semantics, Floodgate passes its Routerlicious gates, and SB5 has no gated 404 or unsupported API claim left.

## Review checkpoints and execution record

Review each task before its commit. Tasks 2 and 3 are Floodgate correctness gates; Task 5 is the pure protocol gate; Tasks 6 and 7 are lifecycle gates; Task 8 is the cross-repository acceptance gate.

| Task | Repository | Status | Commit / outcome |
|---|---|---|---|
| 1. Bootstrap contract | Watershed | Not started | — |
| 2. Linear publication | Floodgate | Not started | — |
| 3. Restart recovery | Floodgate | Not started | — |
| 4. Commit history storage client | Watershed | Not started | — |
| 5. Pure summary lifecycle | Watershed | Not started | — |
| 6. JavaScript publication wait | Watershed | Not started | — |
| 7. BEAM publication wait | Watershed | Not started | — |
| 8. Public API and final gates | Both | Not started | — |

## Out of scope

- A custom `/versions` endpoint.
- Branching or merge commits in the public document history.
- User-created refs under the server-owned document summary ref.
- Summary deletion, retention limits, object garbage collection, or operation-log pruning.
- Migration of every orphan tree or sibling commit created before this plan.
- Server-side summary generation or summarizer election.
- A new summary blob version.
- Changes to channel snapshot formats.
