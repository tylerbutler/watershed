# Gnome Village Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task in a later session. Execute directly rather than dispatching subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the JavaScript owners' execution and lifecycle contracts, close synchronization startup gaps, and use Room Agreement to improve the component extension workflow.

**Architecture:** Preserve the pure cores, typed ports, opaque component state, persisted workspace composition, and application-owned catalog. Reject nested synchronous commands, make shutdown terminal before cleanup, and contain exceptions at application callback boundaries. Keep rendering application-owned while integrating one more component; introduce no generic plug-in framework.

**Tech Stack:** Gleam `>= 1.7.0`, JavaScript and Erlang targets, existing JavaScript FFI, startest, gleeunit, Lustre, sluice, and Node.

**Spec:** [Gnome Village architecture review](../../research/gnome-village-architecture-review.md), especially sections 3, 4, 6.1, and 7. Also read [the component SDK design](../specs/2026-09-01-data-component-sdk-design.md).

## Status and scope

This document plans implementation; it does not claim that the reported failures have been reproduced or fixed. The research cites `122ccba`. At planning time, HEAD was `6da6d5c`, which added the research document without changing the cited implementation.

The user approved planning these five recommendations: host run-to-completion, synchronization startup, failure and completion contracts, Room Agreement as an extension exercise, and accompanying contract documentation. The implementation choices below are the proposed defaults for that work.

Keep this one handoff document, but ship its three workstreams separately:

| Workstream | Tasks | Dependencies | Deliverable |
|---|---|---|---|
| Component host | 1-3 | In order | Explicit command, shutdown, startup, and callback-failure behavior |
| Synchronization | 4-6 | Task 5 follows 4; task 6 reuses task 3's callback helper | Correct startup and observer behavior without new transports |
| Component integration | 7-9 | After host hardening; task 9 closes the documentation across all workstreams | Working Room Agreement, less adapter repetition, accurate extension documentation |

Stop after any completed task if the session runs out of time. Update its checkboxes and record its commit, remaining failures, and the next task in the execution record at the end.

## Global constraints

- Add no package dependencies or testing frameworks.
- Keep `command` synchronous and keep its `Result(Nil, RuntimeError)` return type.
- Preserve `stop`'s `List(component.ComponentError)` return type.
- Preserve FIFO dispatch, per-trace edge deduplication, generation-bound emitters, and unchanged-instance reuse.
- Preserve the difference between accepting a command and delivering its outputs. Neither promises server acknowledgement or rollback of channel mutations.
- Treat components as trusted application code. This work does not provide a sandbox.
- Keep the explicit `Running` union and typed codecs. Do not replace them with dynamic values or unchecked casts.
- Use existing scheduler and transport injection. Do not add an actor, worker, message bus, generic executor, or command queue.
- Scope exception containment to application hooks. Do not wrap a whole protocol transition in a catch-and-continue block.
- Use ASD-STE100 for Gleam comments, docs, and error strings. Use normal prose in Markdown.
- Read `AGENTS.md` before edits. Do not change apm-managed instructions or generated snippet output.
- Leave website copy alone in this plan. If implementation needs a website correction, first read `.github/instructions/website-copy.instructions.md`.
- Do not import old plans' claims about pre-existing failures. Establish the current state when executing.

## Execution setup

- [x] Read the research, this plan, and `AGENTS.md`; inspect `git status --short` and recent commits.
- [x] Recheck the named functions before editing. File and symbol references below describe the planning baseline, not immutable line numbers.
- [ ] For each task: add its regression, run it to establish the failure, implement the change, rerun the targeted command, review the diff, and commit that task's files. A reproduction that passes is evidence to investigate, not permission to force a change.
- [ ] Keep implementation and unrelated cleanup in separate commits. Do not commit this entire roadmap's changes as one patch.

Root tests use startest. New root test functions must return `Nil` and use `@target(javascript)` for JS-only code. Project Room and `watershed_lustre` use gleeunit. Do not assume startest awaits a returned JavaScript promise.

```bash
# Root selectors used by this plan:
gleam test --target javascript -- component_runtime
gleam test --target javascript -- runtime
gleam test --target javascript -- crdt_sequencer_js
gleam test --target javascript -- sluice/driver_js

# Package-level consumers:
(cd watershed_lustre && gleam test)
(cd examples/project_room_lustre && gleam test && pnpm run build)
```

Use one selector covering related cases rather than rerunning overlapping suites after each assertion. Run Erlang tests for target-independent changes; do not run a repository-wide build for a documentation-only task.

## File map

| Files | Responsibility |
|---|---|
| `src/watershed/component_runtime_js.gleam` | Host state, command acceptance, lifecycle, dispatch, and reports |
| `src/watershed/component.gleam` | Descriptor and callback contracts; keep it target-independent |
| `test/watershed/component_runtime_js_test.gleam` | Deterministic host regressions using the existing fixtures |
| `src/watershed/callback_js.gleam`, `src/watershed/callback_ffi.mjs` (new in task 3) | Small, typed boundary for invoking an application callback |
| `src/watershed/crdt_js_ffi.mjs` | Existing `guard` implementation; share it without changing CRDT callback policy |
| `src/watershed/runtime.gleam` | Sequenced JS runtime, bootstrap, transport callbacks, observers |
| `src/watershed/crdt_sequencer_js.gleam` | Relay driver handle installation and generation lifetime |
| `src/watershed/transport_js.gleam` | Scheduler contract |
| `test/watershed/runtime_callbacks_test.gleam` (new) | Synchronous adversarial transport and observer tests |
| `test/watershed/runtime_bootstrap_harness.gleam`, `test/watershed/runtime_bootstrap_ffi.mjs`, `smoke/runtime_bootstrap.mjs` (new in task 5) | Awaited bootstrap regressions using the real runtime and controlled HTTP responses |
| `test/watershed/crdt_sequencer_js_test.gleam` | Relay startup regressions |
| `test/watershed/runtime_core_test.gleam`, `test/watershed/sluice/driver_js_test.gleam` | Existing sequencing and convergence coverage |
| `justfile` | Include the awaited bootstrap regression in the existing JS gate |
| `examples/project_room_lustre/src/project_room_lustre/catalog.gleam` | Registration, projections, creation presets, and typed adapters |
| `examples/project_room_lustre/src/project_room_lustre/workspace_setup.gleam` | Idempotent seed and runtime creation |
| `examples/project_room_lustre/src/project_room_lustre.gleam` | Lustre messages, effect routing, component selection |
| `examples/project_room_lustre/src/project_room_lustre/views.gleam` | Room Agreement controls and readout |
| `examples/project_room_lustre/src/project_room_lustre/room_agreement.gleam` | Existing domain implementation; preserve its proposal and event rules |
| `examples/project_room_lustre/test/catalog_palette_test.gleam`, `examples/project_room_lustre/test/acceptance_test.gleam`, `smoke/project_room.mjs` | Registration, multi-client integration, browser behavior |
| `docs/component-runtime-contracts.md` (new), `docs/superpowers/specs/2026-09-01-data-component-sdk-design.md`, `examples/project_room_lustre/README.md` | Contracts and the actual extension workflow |

No change to `runtime_core.Core` opacity, service deployment topology, or production storage belongs in these tasks.

---

## Task 1: Reject nested commands and make shutdown terminal

**Files:** Modify `src/watershed/component_runtime_js.gleam`, `src/watershed/transport_js.gleam`, and `test/watershed/component_runtime_js_test.gleam`.

**Consumes:** `command`, `stop`, `drain`, `dispatch_async_outputs`, `reconcile_now`, `finish_start`, and the existing scheduler.

**Produces:** Add `RuntimeBusy` and `RuntimeStopped` to `RuntimeError`. Keep the public function signatures unchanged. Read-only `running`, `layout`, `graph`, and `lifecycle` calls remain allowed during a command.

The host must hold command exclusion across the action, validation, local commit, output dispatch, and synchronous report callbacks. Merely guarding `action(...)` leaves nested input and report callbacks exposed.

- [x] Add this regression to the existing host test module. It uses its current `started_runtime`, `Running`, and `record` fixtures; the error constructors are the planned additions.

```gleam
@target(javascript)
pub fn nested_commands_are_rejected_before_the_action_runs_test() -> Nil {
  let #(_, _, runtime, _, _, _) = started_runtime("nested-command")
  let nested_results = transport_js.new_cell([])
  let nested_calls = transport_js.new_cell([])

  component_runtime_js.command(runtime, "tasks", fn(running) {
    let nested =
      component_runtime_js.command(runtime, "notes", fn(notes) {
        record(nested_calls, "called")
        Ok(#(notes, []))
      })
    record(nested_results, nested)
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))

  transport_js.get_cell(nested_results)
  |> expect.to_equal([Error(component_runtime_js.RuntimeBusy)])
  transport_js.get_cell(nested_calls) |> expect.to_equal([])

  component_runtime_js.command(runtime, "notes", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))
}
```

- [x] Add variants for a nested command to the same instance, a nested command from an input handler, and a nested command from `on_report`. Assert both the refusal and the outer operation's final state. An ordinary later command must work.
- [x] Add cleanup regressions: a stop handler calls `command`; a stop handler calls `stop` again; an action calls `stop` before returning new state. Record callback counts and assert that no instance or emitter becomes active again.
- [x] Run `gleam test --target javascript -- component_runtime` and identify the expected failure for each behavior.
- [x] Add the command exclusion state and check terminal state before invoking user code. Use this ordering:

```text
command entry:
  stopped -> Error(RuntimeStopped)
  operation active -> Error(RuntimeBusy)
  otherwise -> enter operation; invoke action; validate; commit; dispatch

before committing or continuing a delivery after user code:
  stopped -> do not commit or dispatch; command returns RuntimeStopped

command exit:
  release operation exclusion using CURRENT state, not the entry snapshot
```

- [x] Make `stop` terminal before unsubscribe or component cleanup. Detach the instance/pending collections from live state, retain a local cleanup snapshot, disable emitters, then release resources. Reentrant `stop` returns `[]`. A stop called from an action is an allowed terminal interruption; do not defer it behind a synchronous API that cannot return its eventual cleanup errors.
- [x] Apply the ownership rule to asynchronous output batches and reconciliation as well. Keep legitimate inline `start` completions working through the owner's internal lifecycle path. If an external lifecycle callback arrives while another operation owns state, defer that callback through the existing scheduler and recheck its generation when it runs. Do not queue public commands.
- [x] Document that `Scheduler.schedule` invokes work after the scheduling call returns, including delay zero. Do not make the host work with an inline scheduler by adding recursive rescheduling.
- [x] Cover typed `Error` exits and missing-instance exits so they release exclusion. Task 3 adds exception exits; do not introduce blanket exception swallowing in this task.
- [x] Rerun the host selector and the `watershed_lustre` tests. Confirm existing late-start, stale-emitter, invalid-output, trace-order, and unchanged-instance cases remain intact.
- [x] Commit: `fix: guard component runtime execution`.

**Acceptance:** Nested user work cannot change state during an owned operation. Stopping prevents subsequent commits and deliveries, including those from the interrupted outer stack.

## Task 2: Enforce one-shot start completion

**Files:** Modify `src/watershed/component_runtime_js.gleam`, `src/watershed/component.gleam`, and `test/watershed/component_runtime_js_test.gleam`.

**Consumes:** Task 1's terminal and operation rules; `finish_start` and `PendingStart`.

**Produces:** Add `DuplicateStartCompletion(instance_id: String)` to `RuntimeError`; report it through `RuntimeFailed`. Retain generation-based late-success cleanup.

- [x] Extend the deferred callback fixture in `a_late_start_is_stopped_after_its_instance_is_deleted_test`. Complete an active start with the same `Running` value twice. Assert one ready instance, zero stop calls before runtime shutdown, and one duplicate-completion report.
- [x] Give the fixture an output port and publish after the duplicate completion. Assert delivery succeeds: the accepted generation's emitter must remain enabled.
- [x] Cover first-error/second-success, first-success/second-error, duplicate completion after removal, and first late success after removal. The first late success still needs one cleanup; repeating that completion must not clean up the same value again.
- [x] Run the host selector to establish the failures.
- [x] Allocate a completion flag per invocation of `component.start`, not per instance ID. Consume it before `finish_start` invokes any user code:

```text
completion callback:
  already consumed -> report DuplicateStartCompletion; do not touch its value
  first completion -> mark consumed; run the existing generation check

first completion for an obsolete generation:
  Ok(running) -> disable that generation's emitter; stop running once
  Error(_) -> disable that generation's emitter
```

- [x] Document ownership: a component transfers one successful running value to the host through the first completion. On a duplicate callback, the host cannot know whether it received the live value again or a separately allocated resource. It reports the violation and leaves extra-resource cleanup to the violating starter. Do not use structural equality to guess resource identity.
- [x] Keep incomplete starts pending until topology removal or host shutdown. Document this limit; do not add timeout configuration in this task.
- [x] Rerun the host selector and commit: `fix: accept component startup once`.

**Acceptance:** A duplicate callback cannot disable or stop the accepted instance. A first late success still releases its resources.

## Task 3: Contain component hook failures without pretending to roll back

**Files:** Create `src/watershed/callback_js.gleam` and `src/watershed/callback_ffi.mjs`. Modify `src/watershed/crdt_js_ffi.mjs`, `src/watershed/component_runtime_js.gleam`, and `test/watershed/component_runtime_js_test.gleam`.

**Consumes:** Tasks 1-2; the existing `guard`/`describe` implementation in `crdt_js_ffi.mjs`.

**Produces:** Shared internal-use functions `callback_js.capture(work: fn() -> value) -> Result(value, String)` and `callback_js.report(reason: String) -> Nil`. Add `HookThrew(instance_id: String, hook: String, reason: String)` to `RuntimeError`. Do not change the CRDT facade's existing reporting policy.

- [x] Add throwing action, input, start, stop, `on_change`, and `on_report` fixtures. Use the existing Gleam test convention of an intentional `panic` for a throwing callback; scope the expectation to that callback.
- [x] Assert this failure policy:

| Callback | Required behavior |
|---|---|
| Action, input, context creation, or start throws | Mark the host terminal, stop further dispatch, disable outputs, and attempt cleanup of owned resources; report `HookThrew` |
| Stop throws | Record `component.StopFailed` with kind/version/reason; continue the other cleanup calls |
| `on_change` throws | Surface the observer failure without invalidating otherwise valid component state |
| `on_report` throws | Surface the failure through the platform error reporter; do not recursively invoke `on_report` |
| Protocol/internal host code throws | Do not convert it into an observer failure and continue |

- [x] Run the host selector to establish the interrupted-dispatch and interrupted-cleanup failures.
- [x] Extract the existing callback error description and guard into the shared FFI file. Re-export `guard` from `crdt_js_ffi.mjs` so its current Gleam binding still works. Add the value-returning boundary:

```javascript
export function capture(work, onSuccess, onError) {
  let value;
  try {
    value = work();
  } catch (error) {
    return onError(describe(error));
  }
  return onSuccess(value);
}
```

Keep `onSuccess` outside the `try`: a failure in processing the result is not a failure of the supplied hook. Bind it in `callback_js.gleam` using typed success and error constructors:

```gleam
@target(javascript)
@external(javascript, "./callback_ffi.mjs", "capture")
fn capture_ffi(
  work: fn() -> value,
  on_success: fn(value) -> Result(value, String),
  on_error: fn(String) -> Result(value, String),
) -> Result(value, String)

@target(javascript)
pub fn capture(work: fn() -> value) -> Result(value, String) {
  capture_ffi(work, Ok, Error)
}
```

- [x] Put the non-recursive platform reporting function in the same FFI file. Use `globalThis.reportError(new Error(detail))` where available and `console.error` otherwise. Cover the reporting path with a test spy; restore globals after the test. Do not copy the CRDT facade's silent containment fallback into these new contracts.
- [x] Capture only application hook invocations. On a mutating hook exception, make the owner terminal before reporting or cleaning up; preserve the original fault and report cleanup faults separately. `command` returns `Error(HookThrew(...))` if its action throws. A later delivery fault goes through `RuntimeFailed` and does not retroactively claim the accepted source command was rolled back.
- [x] Keep exception-exit exclusion cleanup consistent with task 1. A terminal host remains terminal after the enclosing operation exits.
- [x] Document the resource limit: a starter that allocates resources and throws before transferring them through `done` must release those resources itself. The host can clean up only resources it owns.
- [x] Rerun `gleam test --target javascript -- component_runtime` and `gleam test --target javascript -- crdt_js`, plus the Lustre adapter package. Review that the extracted CRDT guard retains its previous behavior.
- [x] Commit: `fix: contain component callback failures`.

**Acceptance:** Required cleanup gets a chance to run; observer exceptions do not interrupt valid work; a failed mutating hook cannot leave a host accepting commands against uncertain state.

## Task 4: Install transport handles before processing callbacks

**Files:** Create `test/watershed/runtime_callbacks_test.gleam`. Modify `src/watershed/runtime.gleam`, `src/watershed/crdt_sequencer_js.gleam`, and `test/watershed/crdt_sequencer_js_test.gleam`.

**Consumes:** `runtime.Transport`, `TransportCallbacks`, `TransportHandle`, `start_with_transport`; relay `Driver`, `Handlers`, and `Connection`.

**Produces:** Unchanged public transport signatures, with a documented guarantee that callbacks raised during connection construction run only after the runtime installs the returned handle.

`sluice_js.connect` deliberately fires `on_join` after `connect_via` returns. It cannot expose this bug by itself. Build an adversarial test-local transport rather than weakening the shared sluice fixture.

- [ ] Add an inline-join transport using the current constructor shape:

```gleam
let pushes = transport_js.new_cell([])
let transport =
  runtime.Transport(connect: fn(callbacks) {
    callbacks.on_join()
    runtime.TransportHandle(
      push: fn(event, _) {
        transport_js.set_cell(
          pushes,
          [event, ..transport_js.get_cell(pushes)],
        )
      },
      close: fn() { Nil },
      drop: fn() { Nil },
      hold: fn() { Nil },
      resume: fn() { Nil },
    )
  })
```

Pass it to `watershed.connect_via` with the same arguments as `sluice_js.connect`. Assert that `pushes` contains exactly one `"connect_document"` after connect returns. Add a variant whose `push` synchronously responds through `on_event` using `watershed/sluice/frame` encoders.

- [ ] Add relay cases: a compatible greeting from inside `Driver.open`; `on_ready` immediately sends through the relay; close before `open` returns; a callback followed by `Error(detail)`; callbacks from a retired generation.
- [ ] Run the new `runtime_callbacks` selector and `crdt_sequencer_js` selector to establish failures.
- [ ] Buffer construction-time callbacks in arrival order until the handle is installed. Use a small local event union/list for each existing owner. Keep the buffer active while draining so a synchronous response to a send cannot overtake an earlier buffered callback:

```text
construct -> record callbacks
successful return -> install handle -> drain FIFO -> switch to direct delivery
failed return -> discard unusable conversation -> existing failure/retry path
retired generation -> close returned handle; do not revive the generation
```

- [ ] Preserve relay `start`/`connect` separation, close semantics, and backoff. Recheck generation and terminal state between buffered callbacks. Do not force ordinary callbacks through a new timer or change readiness into a scheduled event.
- [ ] Do not generalize this into a permanent mailbox for all traffic. Fix any additional inline response within this handshake path that the adversarial fixture exposes by committing owner state before the outbound call.
- [ ] Run the two targeted selectors and `gleam test --target javascript -- sluice/driver_js`.
- [ ] Commit: `fix: buffer transport startup callbacks`.

**Acceptance:** Inline and deferred transports produce the same handshake and readiness outcome. No callback observes a ready connection whose outbound handle is still absent.

## Task 5: Retain operations throughout asynchronous bootstrap

**Files:** Modify `src/watershed/runtime.gleam` and `justfile`. Create `test/watershed/runtime_bootstrap_harness.gleam`, `test/watershed/runtime_bootstrap_ffi.mjs`, and `smoke/runtime_bootstrap.mjs`.

**Read before editing:** `runtime.load_summary_then_bootstrap`, `finish_bootstrap`, `continue_bootstrap`, `on_operation`, `on_close`, and `fail`; `git_storage.fetch_summary`/`fetch_deltas`; `runtime_core.bootstrap`/`resume_bootstrap`; the summary and truncated-history cases in `test/watershed/runtime_core_test.gleam`.

**Consumes:** Task 4's installed-handle callback ordering. Use the existing core operation application, deduplication, and catch-up logic.

**Produces:** A bootstrap-session generation and a bounded buffer for validated operations received after a successful handshake but before bootstrap finishes. No new public storage API.

- [ ] Build an awaited regression harness around the real runtime. Expose `run() -> Promise(Nil)` from the new Gleam harness and await it from `smoke/runtime_bootstrap.mjs`:

```javascript
const { run } = await import(
  "../build/dev/javascript/watershed/watershed/runtime_bootstrap_harness.mjs"
);
await run();
```

- [ ] In the test-only FFI, intercept HTTP through `globalThis.fetch`, retain a release callback for each deferred response, and restore fetch in `finally`. Use no public service and no wall-clock sleep. An unexpected request must reject the test. Reuse `sluice/frame` for handshake and operation encoding, and `summary_blob.encode_channels` for summary content rather than inventing a parallel wire format.

The real summary reader expects these response shapes:

```javascript
const tree = { tree: [{ path: "header", sha: "blob-1" }] };
const blobResponse = (summaryJson) => ({
  content: Buffer.from(summaryJson, "utf8").toString("base64"),
});
const deltasResponse = (messages) => ({ value: messages });
```

Use a dummy token scoped to the fixture. Never contact the URL it names. Each test must close its runtime/transport and leave no real timers running.

- [ ] Implement these scripts as separate assertions within the awaited harness:

| Scenario | Required observation |
|---|---|
| Summary through sequence N; handshake complete through N; deliver N+1 while blob fetch waits; release blob; send nothing else | N+1 is applied, readiness fires once, final sequence is N+1 |
| Deliver N+2 while fetch waits; release; answer catch-up request with N+1 | Runtime requests the gap without another live operation; readiness waits for contiguous state |
| Deliver an operation already included in fetched history | One application, no duplicate notification |
| Pause a later `MissingPrefix` HTTP page; deliver live operations | Preserve them across all prefix pages, not only the first summary fetch |
| Close/rejoin while an old HTTP request waits; release old response last | Old completion cannot overwrite the new session or report readiness |
| HTTP failure or buffer overflow | One explicit failure, no readiness success, buffer released |
| No summary and no async prefix | Existing synchronous bootstrap behavior remains |

- [ ] Run `gleam build --target javascript && node smoke/runtime_bootstrap.mjs` and establish the no-later-traffic failure.
- [ ] Start buffering after accepting the handshake for the current session, not for arbitrary pre-handshake traffic. Tag every summary/prefix completion with the session generation and invalidate it on close, failure, or a newer handshake.
- [ ] Bound the new buffer at 10,000 operations and 16 MiB of UTF-8 payload bytes, whichever comes first. Check byte size before JSON decoding and count decoded operations, not envelopes. Overflow fails the connection with an explicit reason; do not drop the oldest operations or add public tuning options in this change. Test both limits using generated input.
- [ ] Replay buffered operations through the same core application path used for normal traffic. Keep the owner in bootstrap/catch-up until it has applied the contiguous received history; issue existing gap requests when needed. Preserve acknowledgements, released outbound operations, and readiness/presence ordering. Do not replay by calling a ready-only handler that would drop the messages again.
- [ ] Drain batches until no buffered work remains, then publish readiness. Release retained payloads on completion or failure. Keep duplicate handling in the core rather than maintaining another deduplication set.
- [ ] Remove the current comment claiming that future traffic repairs dropped startup operations. Document the new buffer and generation rules.
- [ ] Add `node smoke/runtime_bootstrap.mjs` after the existing compilation/test command in `justfile`'s `_test-js` recipe so `just test` runs the awaited regression.
- [ ] Run the awaited harness and `gleam test --target javascript -- runtime`, then the sluice driver selector. If changes to `runtime_core.gleam` prove necessary, run `gleam test --target erlang -- runtime_core` too.
- [ ] Commit: `fix: retain operations during bootstrap`.

**Acceptance:** Startup converges with no later live traffic, and a stale HTTP completion cannot change a newer session.

## Task 6: Keep observer exceptions out of sequenced protocol work

**Files:** Modify `src/watershed/runtime.gleam` and `test/watershed/runtime_callbacks_test.gleam`; reuse `src/watershed/callback_js.gleam` from task 3.

**Consumes:** `fan_out`, `fire_ready`, `notify_presence`, ripple subscribers, outcome callbacks, and the shared callback boundary.

**Produces:** Observer exceptions surface through the platform error reporter while protocol processing and remaining observers continue. Public subscription and connection signatures stay unchanged.

- [ ] Add two subscribers to one channel, with the first one throwing. Assert that the second observes the committed value and that the outbound/catch-up work still runs.
- [ ] Add a gap-producing inbound operation with a throwing subscriber. Assert that the transport records `"requestOps"` despite the throw. Also cover an operation that releases outbound consensus work so the test checks more than notification counts.
- [ ] Cover a throwing `on_ready`, presence listener, and ripple listener. An `on_ready` throw must not suppress presence session notification or fire readiness again.
- [ ] Run `gleam test --target javascript -- runtime_callbacks` to establish the failure.
- [ ] Wrap the observer invocation, not `on_operation` or `apply_operations`:

```gleam
case callback_js.capture(fn() { subscriber.handler(event) }) {
  Ok(Nil) -> Nil
  Error(reason) -> callback_js.report(reason)
}
```

Use task 3's `callback_js.report`. Include subscriber/channel or callback-kind context in the reported string at the call site.

- [ ] Keep commit-before-notification and subscription-snapshot semantics. Audit adjacent callbacks that resolve claim/acquire outcomes: remove/commit waiters before invoking caller code so a callback cannot resurrect a waiter through an older state snapshot.
- [ ] Commit failure state before `fire_ready(Error(...))` or session-loss callbacks. Use current state after callbacks rather than restoring a snapshot from before they ran.
- [ ] Do not quarantine ordinary observers or add subscription settings. A bad observer may report another error on its next invocation, but cannot interrupt protocol work.
- [ ] Run `runtime_callbacks`, the awaited bootstrap harness, and the sluice driver selector; commit: `fix: isolate sequenced runtime observers`.

**Acceptance:** A throwing observer cannot skip recovery, acknowledgements, other observers, or session notification. Failures remain visible without turning a valid document into a failed one.

## Task 7: Integrate Room Agreement through the existing catalog

**Files:** Modify the Project Room `catalog.gleam`, `workspace_setup.gleam`, `project_room_lustre.gleam`, `views.gleam`, `test/catalog_palette_test.gleam`, `test/acceptance_test.gleam`, and `smoke/project_room.mjs`. Update `index.html` only if existing control styles cannot render the new view.

**Read:** `room_agreement.gleam`, `test/room_agreement_test.gleam`, `component_event.gleam`, the Activity descriptor, and Checklist/Tally's instance-ID-based shell routing.

**Consumes:** Existing `room_agreement.initialize`, `start`, `set_draft`, `propose`, `refresh`, and `stop`. `component_event.emitted()` and `component_event.append()` already provide the output schema and Activity input.

**Produces:** `catalog.RoomAgreement(running: room_agreement.Running, refresh_pending: transport_js.Cell(Bool))`, kind `"project-room/room-agreement"`, version `1`, seeded instance ID `"agreement"`, and a creation preset titled `"Room Agreement"`. The flag belongs to the application adapter, not to the headless component. Add a seeded edge `"agreement-accepted-to-activity"` from `component_event` to Activity's `append_component_event`.

- [ ] Before refactoring, record the files and exhaustive matches touched by this integration in the execution record. This is the extension-cost measurement for task 8.
- [ ] Add a catalog test using existing public APIs:

```gleam
pub fn room_agreement_preset_builds_valid_config_test() -> Nil {
  let assert Ok(preset) =
    catalog.find_creation_preset("project-room/room-agreement")
  let catalog.CreationPreset(kind:, version:, config:, ..) = preset
  let assert Ok(descriptor) = component.find(catalog.catalog(), kind, version)
  component.validate_config(descriptor, config("Working agreement"))
  |> should.equal(Ok(Nil))
}
```

- [ ] Extend the deterministic runtime acceptance scenario: start two clients; seed one agreement; propose from A; settle the protocol; refresh both components through runtime commands. Assert accepted text on both clients, one Activity entry, and an output dispatch only from the proposing client.
- [ ] Add runtime-created instances with distinct IDs. Assert independent local drafts, correct rendering/action targeting, movement/removal, and non-destructive reopening. Keep runtime-created instances unconnected, matching the palette's current policy.
- [ ] Run `(cd examples/project_room_lustre && gleam test)` to establish the integration failures.
- [ ] Register the descriptor with no input ports and `component_event.emitted()` as its output. Forward only the arguments `room_agreement.start` consumes: document, subtree, instance ID, invalidation, config, completion. It does not need the common context's participant label or emitter; it derives participant identity from the document. Allocate `refresh_pending` with initial value `True`. Its invalidation closure sets that flag and then calls the host's invalidation callback.
- [ ] Add catalog projections and shell messages keyed by instance ID: draft change, propose, and refresh. Route operations through `watershed_lustre/component_runtime` effects. Wrap the existing return shapes without changing domain behavior:

```gleam
// Action bodies after matching RoomAgreement(inner, refresh_pending):
Ok(#(
  catalog.RoomAgreement(
    room_agreement.set_draft(inner, text),
    refresh_pending,
  ),
  [],
))

// Proposal action:
room_agreement.propose(inner)
|> result.map(fn(next) {
  #(catalog.RoomAgreement(next, refresh_pending), [])
})

// Refresh action:
transport_js.set_cell(refresh_pending, False)
let #(next, outputs) = room_agreement.refresh(inner)
Ok(#(catalog.RoomAgreement(next, refresh_pending), outputs))
```

- [ ] Add `catalog.as_room_agreement(running: Running) -> Result(room_agreement.Running, Nil)` for reads and `catalog.room_agreement_needs_refresh(running: Running) -> Bool` for the shell. The latter returns the flag for an agreement and `False` for other variants. On `RuntimeChanged`, schedule a refresh command only for an agreement whose flag is set. Clear the flag inside the effect-performed action before refreshing, so a new invalidation during refresh survives.
- [ ] Keep refresh out of `view` and Lustre `update`. Command completion triggers a host notification but does not set the adapter's invalidation flag; that distinction prevents an endless refresh-command-notification loop. Add a deterministic settle-count assertion for an idle agreement and a case where invalidation arrives during refresh.
- [ ] Render accepted text, pending proposal, pending signoff count, local draft, and the propose action using existing view conventions. Do not add a manual signoff button: the existing PactMap protocol handles signoffs.
- [ ] Extend `seed` idempotently and append the seeded edge. Preserve existing stored IDs and connections; update exact layout/preset expectations in tests. Older rooms receive only the missing seeded instance/edge through the existing seed flow.
- [ ] Extend the two-tab smoke for accepted text and one Activity entry. Do not route refreshed state from remote clients back into new acceptance events.
- [ ] Run `(cd examples/project_room_lustre && gleam test && pnpm run build)`. Run `just project-room-smoke` only with its documented Chromium and floodgate prerequisites available; record a missing prerequisite instead of calling the browser check passed.
- [ ] Commit: `feat: integrate room agreement component`.

**Acceptance:** Room Agreement works as a seeded and runtime-created component without copying its domain rules into the shell.

## Task 8: Remove measured catalog repetition

**Files:** Modify `examples/project_room_lustre/src/project_room_lustre/catalog.gleam` and `examples/project_room_lustre/test/catalog_palette_test.gleam`. Keep changes to the application shell limited to using the same adapter functions.

**Consumes:** Task 7's change inventory and existing `as_checklist`, `as_tally`, and other projections.

**Produces:** One descriptor list used for registration and enumeration, plus projection-based adapter code. No new public SDK abstraction.

- [ ] Add assertions that each descriptor returned by `catalog.descriptors()` resolves through `component.find(catalog.catalog(), ...)` with the same kind/version. Cover wrong-variant inputs and cleanup returning explicit errors.
- [ ] Replace the separate registration chain with a fold over `descriptors()`:

```gleam
pub fn catalog() -> component.Catalog(Context(root), Running) {
  let assert Ok(catalog) =
    list.try_fold(descriptors(), component.new_catalog(), fn(catalog, descriptor) {
      component.register(catalog, descriptor)
    })
  catalog
}
```

The existing catalog already asserts that its fixed registrations are valid; this preserves that behavior while removing a second list to update.

- [ ] Use each existing typed projection once per adapter instead of repeating the full negative `Running` match in every input and stop closure. Keep an explicit error for a wrong variant:

```gleam
fn stop_checklist(running: Running) -> Result(Nil, String) {
  use inner <- result.try(
    as_checklist(running)
    |> result.map_error(fn(_) {
      "checklist stop reached the wrong component"
    }),
  )
  checklist.stop(inner)
}
```

- [ ] Add a shared adapter helper only if the integration inventory shows repeated identical mapping that projections do not remove. Keep it private to `catalog.gleam`; do not create a generic registry or lift it into the library as part of this task.
- [ ] Audit start arguments against headless signatures. Retain document/channel access where required and avoid passing participant/publication capabilities to components that do not consume them. The common catalog context remains a trusted application context, not a security boundary.
- [ ] Record before/after registration sites and repeated negative-match counts. Do not set an arbitrary line-count target or rewrite working components to improve the metric.
- [ ] Run `(cd examples/project_room_lustre && gleam test && pnpm run build)` and commit: `refactor: simplify project room adapters`.

**Acceptance:** Adding the next kind requires one descriptor-list entry and one projection per type, without adding that kind to unrelated handlers' negative matches.

## Task 9: Publish the contracts and reconcile the rendering promise

**Files:** Create `docs/component-runtime-contracts.md`. Modify `docs/superpowers/specs/2026-09-01-data-component-sdk-design.md` and `examples/project_room_lustre/README.md`. Update doc comments in `src/watershed/component.gleam`, `component_runtime_js.gleam`, `port.gleam`, `runtime.gleam`, and `transport_js.gleam` where their public APIs expose these rules.

**Consumes:** The implemented behavior from tasks 1-8. Do not describe a planned guarantee as shipped.

**Produces:** A contract reference and an extension checklist that match the working example.

- [ ] Write `docs/component-runtime-contracts.md` with these sections and explicit statements:

| Section | Required content |
|---|---|
| Execution owner | Nested commands return `RuntimeBusy`; terminal hosts return `RuntimeStopped`; reads remain permitted; stop may interrupt an action and prevents a later commit |
| Acceptance and delivery | `Ok(Nil)` accepts source state/output validation; reports describe delivery; collaborative submission is not sequencing acknowledgement |
| Effects and rollback | Local returned-state validation does not undo earlier channel mutations; example: Checklist mutates its OR-set before returning an event |
| Startup and shutdown | Exactly one completion per start; first late success cleanup; duplicate ownership rule; no startup timeout; terminal-before-cleanup ordering |
| Failures | Typed component rejection versus hook exception; terminal host policy; observer containment and non-recursive error reporting; resource-transfer limit |
| Scheduling and transport | Scheduler deferral; construction-time callback buffering; generation checks; bounded bootstrap retention and overflow failure |
| Payload schemas | Namespaced ID owned by the codec module, for example `project-room/component-event@1`; incompatible changes get a new version; matching strings do not prove codecs agree |
| Trust and capabilities | Capability strings document intended use; they are not authorization; opaque handles are not read-only handles |
| Rendering | The current shell owns message routing and view selection; a headless descriptor alone does not mount a UI |

- [ ] Add a codec compatibility example based on `component_event.encode`/`decoder`, showing a valid round trip and a malformed payload rejection. Reference the existing tests rather than creating a runtime schema registry.
- [ ] Correct the SDK design's Lustre adapter section: distinguish its optional nested-MVU direction from today's implemented shell integration. State that this plan does not implement an automatic mounting contract. Preserve the headless/adapter separation as a design direction.
- [ ] Add the Room Agreement extension checklist to the example README: headless lifecycle; descriptor and projection; preset/seed; typed ports; instance-ID messages/effects; view; deterministic acceptance case. Link the new contract reference.
- [ ] Record the task 7/8 extension-cost findings as measured counts, without claiming development-time savings.
- [ ] Check links and the implementation against each contract statement. If an implementation differs from this plan, explain that difference in the execution record and document the behavior that actually shipped.
- [ ] Commit: `docs: define runtime and extension contracts`.

**Acceptance:** A caller can find execution, lifecycle, schema, and extension rules without inferring them from callback timing or reading the research report.

## Final integration checkpoint

- [ ] Confirm all acceptance scenarios above have durable coverage and all new harnesses run through an existing gate.
- [ ] Confirm new runtime error variants compile through the Lustre adapter and example consumers.
- [ ] Run the smallest combined root selector covering the changed runtime modules, the awaited bootstrap harness, and both consumer packages. Run the relay lifecycle selector if relay callback ordering changed its facade behavior.
- [ ] Run Erlang coverage for target-independent edits. Run the existing port compile-fail gate if typed port APIs changed; this plan does not require changing them.
- [ ] Preserve source snippet markers. If a marked source block changed, run `just snippets`; do not commit `website/src/generated/snippets.json`.
- [ ] Review for accidental scope growth: no component actors, plugin registry, new transport protocol, startup timeout system, service repartitioning, or unrelated prose rewrite.

## Deferred work and its trigger

| Deferred change | Reconsider only when |
|---|---|
| Queued public commands | A caller requires asynchronous acceptance/completion and accepts an API change |
| Generic nested-MVU mounting | A concrete second integration demonstrates a reusable contract that the application-owned shell cannot meet cleanly |
| Startup deadlines | A real starter can hang and the product has a defined timeout/retry experience |
| Untrusted component isolation | The product accepts third-party code with enforced capability or failure boundaries |
| Per-room service processes/storage workers | Measured latency, overload, or recovery requirements justify partitioning |
| Opaque sequenced `Core` | A separate compatibility review identifies consumers and migration cost |

## Execution record

### Task 1: execution ownership and terminal shutdown

Commit: `181e176` (`fix: guard component runtime execution`).
Baseline: 15 host/core tests passed. The new regressions reproduced five
failures: nested actions, nested input/report actions, action-stop resurrection,
delivery after stop, and repeated cleanup. After implementation,
`gleam test --target javascript -- component_runtime` passed 24 tests;
`(cd watershed_lustre && gleam test)` passed 60.

Additional cases cover external completion during an action, generation
rechecking after shutdown, and shutdown from reconciliation cleanup. Missing
instances and typed rejections release ownership. Reviewed the diff directly,
as requested; no subagents. Existing unrelated compiler warnings remain.
No unmet task-1 criterion. Next: task 2.

### Task 2: one-shot startup

Commit: `eb5175b` (`fix: accept component startup once`).
Three regression tests reproduced duplicate cleanup and missing violation
reports. They cover both result orderings and both removal timings. The host
selector passed 27 tests after the change. `just snippets` regenerated the
ignored manifest because the descriptor documentation is source-backed.
No unmet task-2 criterion. Next: task 3.

### Task 3: application hook failures

Commit: `fix: contain component callback failures` (hash recorded with task 4).
Five tests reproduced uncontained action, context, input, observer, and cleanup
exceptions. Coverage also includes startup throwing after `done`, both platform
reporting paths with globals restored in `finally`, terminal subsequent commands,
and separate original/cleanup fault reports. Host tests: 32 passed. CRDT facade:
64 passed. Lustre adapter: 60 passed. Source snippets regenerated.

Inline startup completions are processed after the starter returns, still inside
the lifecycle operation, so host transitions are outside the starter's exception
boundary. If the starter throws after `done`, the transferred value is cleaned up
as a late success. Host-wide `on_change` faults use an empty instance ID.
No unmet task-3 criterion. Next: task 4.

For each completed task, append its task number, commit, commands and outcomes, any unmet acceptance criterion, and the next task. For tasks 7-8, include the integration-file and adapter-repetition measurements. Keep temporary logs out of the repository.
