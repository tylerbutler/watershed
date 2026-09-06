# Component runtime contracts

These rules describe the JavaScript component host and sequenced document
runtime. The [Project Room example](../examples/project_room_lustre/README.md)
shows how an application connects them to Lustre. Descriptors, typed ports,
and catalog validation remain target-independent.

## Execution owner

The component host owns one operation at a time: a command, output dispatch,
or lifecycle transition. A nested `component_runtime_js.command` returns
`Error(RuntimeBusy)` without running its action. Public commands are not queued.
Reads remain available inside callbacks.

`stop` can interrupt an action. It makes the host terminal before cleanup,
so the interrupted action cannot commit its returned state. Later commands
return `Error(RuntimeStopped)`. Cleanup and notification callbacks cannot
restart that host; start a new host to reopen the workspace.

## Acceptance and delivery

`command` returning `Ok(Nil)` means the host accepted the source's returned
state and validated its output batch. It does not guarantee successful target
delivery. Inspect `DispatchReport` for each dispatch:

| Report | Meaning |
|---|---|
| `Triggered` | The origin dispatched an output |
| `LocalDelivered` | A local target accepted the input |
| `MutationSubmitted` | A collaborative target accepted the input on the origin |
| `DispatchFailed` | Planning, source validation, or a target delivery failed |
| `RuntimeFailed` | A runtime or application-hook failure occurred |

`MutationSubmitted` is not a sequencing acknowledgement. A target may mutate a
channel before the server accepts that operation. Remote clients observe the
replicated state; they do not replay the source event through the graph.

A throwing input hook stops the host and reports `RuntimeFailed`. The source
command still returns `Ok(Nil)` if the host already accepted its state and
outputs. A throwing action returns `Error(HookThrew(...))`.

## Effects and rollback

Returned-state validation is local. It cannot undo a mutation that component
code already submitted through a channel handle. For example, Checklist adds
to its completion OR-set before returning an `item_completed` output. Rejecting
that output does not remove the OR-set mutation.

An error therefore does not prove that no effects occurred. Check inputs before
mutating channels, use typed failures for expected rejection, and design
retries around the component's domain rules. The host provides no transaction
or cross-component rollback.

## Startup and shutdown

Call a starter's `done` callback exactly once. The first completion consumes
that invocation; an `Ok` first completion transfers ownership of the running
value to the host. If the instance has since been removed or replaced, the
host stops that first late success instead of installing it.

Later completions report `DuplicateStartCompletion(instance_id)` and transfer
no ownership. The starter must release any distinct resources supplied in a
duplicate result without stopping or disabling the accepted instance. This
rule also applies to success after an initial error.

There is no startup timeout. An incomplete start remains pending until
removal, replacement, or shutdown. Emitters belong to one instance generation;
old emitters cannot publish through a replacement instance.

Shutdown detaches the live instances and subscriptions before calling cleanup.
Reentrant shutdown cannot stop an instance twice. Cleanup continues after a
stop hook rejects or throws, and `stop` returns the collected component errors.
Stopping a host does not delete collaborative data.

## Failures

A component can reject an action or input with a typed `Result` error. That
rejection does not terminate the host. An exception in an action, input,
context factory, or starter does: the host stops all owned instances and
reports `HookThrew(instance_id, hook, reason)`. Host-wide hooks use an empty
instance ID. A throwing stop hook becomes `StopFailed`.

The exception boundary surrounds only application work. It does not catch
the runtime's continuation and relabel an internal error as an application
failure. A starter that throws before transferring resources must clean them
up itself; the host cannot discover resources it never received.

Component `on_change` and `on_report` observers cannot interrupt valid host
work by throwing. A failed `on_change` produces a runtime report. A failed
report callback goes straight to the platform reporter, without calling that
callback again. Reporting uses `globalThis.reportError`, with `console.error`
as the fallback.

The sequenced runtime commits state before notifying channel, ripple, presence,
readiness, or outcome observers. It removes resolved or aborted waiters before
calling them. Observer exceptions go to the same platform reporter; later
observers, gap requests, and outbound protocol work continue. Closing the
document inside a callback remains an explicit request to stop further work.
Ordinary observers stay subscribed after throwing.

## Scheduling and transport

A `transport_js.Scheduler` must defer work until the scheduling call returns,
including delay zero. The component host uses that scheduler for lifecycle
work, notifications, and asynchronous output publication.

The sequenced transport and relay client accept callbacks during connection
construction. They install the returned handle before draining those callbacks
in arrival order. Synchronous responses during the drain join the same queue;
ordinary traffic then uses direct callbacks. Failed relay construction discards
its buffered callbacks. A retired relay generation cannot install a handle.

After an accepted handshake, the sequenced runtime retains live operations
while loading a summary and operation prefix. It drains through the ordinary
operation path, preserving duplicates, acknowledgements, gaps, and released
outbound work. Readiness waits for contiguous state; diagnostics report
`catching-up` in the meantime.

Each bootstrap allows at most 10,000 decoded live operations and 16 MiB of raw
UTF-8 operation payloads. These counters include catch-up traffic received
during bootstrap and do not reset between drain batches. Overflow fails the
connection. Close, failure, and rejoin invalidate pending HTTP completions
through a generation check.

## Payload schemas

The codec module owns the namespaced schema ID. For example,
[`component_event`](../examples/project_room_lustre/src/project_room_lustre/component_event.gleam)
owns `project-room/component-event@1`. Reuse its encoder, decoder, and typed
ports when producing or consuming that payload. Give an incompatible format a
new schema version.

Matching schema strings do not prove that two independently written codecs
agree. Typed connections check Gleam payload types; persisted connections
check metadata; delivery decodes the actual payload. Test both accepted and
rejected JSON at the codec boundary.

This example uses the same codec as the Project Room
[round-trip and unknown-action tests](../examples/project_room_lustre/test/components_test.gleam):

```gleam
let event = component_event.Event(
  source_instance_id: "agreement",
  source_kind: "project-room/room-agreement",
  source_title: "Room Agreement",
  action: component_event.AgreementAccepted,
  detail: "Accepted agreement: Review together",
)
let assert Ok(decoded) =
  json.parse(
    json.to_string(component_event.encode(event)),
    component_event.decoder(),
  )
let assert True = decoded == event
let assert Error(_) =
  json.parse(
    "{\"sourceInstanceId\":\"agreement\",\"sourceKind\":\"project-room/room-agreement\",\"sourceTitle\":\"Room Agreement\",\"action\":\"unknown\",\"detail\":\"Rejected\"}",
    component_event.decoder(),
  )
```

## Trust and capabilities

Capability strings such as `sequence:insert` describe intended use. They are
not authorization checks. The application supplies a trusted context; a
component with a document or mutable channel handle can use its mutation APIs.
An opaque handle is not a read-only handle. This host does not isolate
untrusted plugins or enforce a security boundary between components.

## Rendering

The application owns message routing and view selection. Registering a
headless descriptor does not mount a UI. Project Room adds a typed `Running`
variant, projection, instance-ID messages, runtime effects, and a view for each
new interactive kind.

Room Agreement also needs an adapter-owned refresh flag. Channel invalidation
sets it; a refresh command clears it before calling the headless refresh
function. A new invalidation during that command survives. Command completion
alone does not set the flag, so an idle component stops scheduling refreshes.
Only the proposing client's local attempt can emit the acceptance event.

The [extension checklist](../examples/project_room_lustre/README.md#add-a-component)
lists the application work. Optional nested MVU adapters remain a design
direction; the current SDK has no automatic heterogeneous mounting contract.
