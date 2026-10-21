# SharedTree app-building agent eval

Date: 2026-10-19
Status: Design approved in conversation; written spec awaiting review.

## Goal

Compare an agent's ability to implement a collaborative app using Watershed
SharedTree and Fluid Framework SharedTree. Use Vally to run the agent, capture
its trajectory, and grade the resulting app.

The first eval is API-focused. Provide working UI shells and development
service tooling. Ask the agent to implement the document schema, creation and
opening, edits, observation, and cleanup.

Use idiomatic Gleam/Lustre for Watershed and TypeScript/React for Fluid.
Results describe agent effectiveness with each API ecosystem, including its
language, documentation, and tooling. They do not isolate API syntax from
language familiarity.

## Scope

Implement one task, a collaborative incident-response board, with two starters
and shared acceptance scenarios. Run either starter from Watershed or the Fluid
Framework repository against an explicitly selected SDK revision.

Exclude transactions, undo/redo, schema evolution, presence, character-level
text merging, offline authoring, network-partition recovery, and visual-design
grading. Neither app needs to open the other SDK's documents.

Do not modify either SDK to make a candidate pass. A missing API capability is
a benchmark outcome, not permission to change the SDK during the trial.

## Alternatives considered

1. **One portable benchmark package with two native starters.** Share the task,
   fixtures, scenarios, and result format. Keep the implementation interfaces
   idiomatic to each SDK. This is the chosen approach.
2. **Independent evals in each repository.** Easier to customize, but differences
   in prompts, fixtures, and graders could invalidate the comparison.
3. **A common API wrapper.** Simplifies testing, but measures the wrapper and
   hides the native API decisions that the eval should test.

## App task and public requirements

The document contains an ordered list of incidents. An incident has an
immutable string ID, a title, a status (`open`, `investigating`, or `resolved`),
an optional assignee string, and an ordered list of checklist steps. A step has
an immutable string ID, a label, and a completion flag.

Use valid, nonempty IDs with document-wide uniqueness. The shell supplies ID
generation for local creation so agents do not spend time choosing a UUID
library. Display order and identity are separate.

The agent must implement these user actions:

- Create an incident, edit its title and status, set or remove its assignee,
  and delete it.
- Add, rename, complete, delete, and reorder checklist steps within an incident.
- Reorder incidents without recreating their nodes or changing their IDs.
- Create a document, share its URL with another client, and open that document
  without resetting its existing content.
- Observe local and remote edits without a refresh.
- Unsubscribe and close a session without leaving active app callbacks.

New documents start with an empty incident list. Moving an item identifies the
item and an optional destination sibling by ID: place it before that sibling,
or append when the destination is absent. Moving an item before itself does
nothing. Removing an already-removed item does nothing; an edit targeting a
removed item must not affect another item or resurrect the removed node.
Report other invalid inputs through the starter's error interface.

Each string edit assigns the whole property. Concurrent writes to the same
property may resolve to either submitted value. Both clients must converge;
the eval must not prescribe a winner.

The durable model must use SharedTree object properties and arrays. Storing the
board as one JSON string, replacing unrelated subtrees on each edit, using a
different DDS, or synchronizing independent local state does not satisfy the
task. UI snapshots are allowed; the document remains authoritative.

Publish these requirements to the agent. Hidden tests vary inputs and schedules,
not the requirements.

## Starters and responsibility boundaries

Provide equivalent, completed UI shells with accessible controls and stable
test selectors. The shell renders snapshots, forwards user intent, displays
connection and error state, and exposes a Close action. It contains no board
schema or working SharedTree model.

Provide a documented model interface in each language covering the same
actions and lifecycle. Use typed records, results, and subscriptions in Gleam;
use corresponding TypeScript types and native conventions in Fluid. Define the
exact declarations during implementation and keep their user-visible semantics
identical.

The interface connects the app to the candidate's model. Do not supply
SharedTree helpers that implement schema creation, CRUD, observation, or
document lifecycle on the agent's behalf.

Supply development-only authentication, service configuration, dependency
lockfiles, and commands for build, serve, and public smoke tests. Service
tooling may prepare a local server and credentials, but the candidate must use
the SDK to create/open its document and initialize a new tree.

Limit candidate edits to the model/schema area and its own tests. Grade against
trusted copies of the UI, build configuration, dependencies, and harness.
Record forbidden edits as a failed integrity check rather than accepting
modified acceptance code.

Public smoke tests check the model interface and a small create/edit/read
example. They provide debugging feedback without exposing hidden schedules.

## Portable package and workspace preparation

Store the benchmark under `evals/shared-tree-app/`, with shared task assets,
`watershed/` and `fluid/` starters, and grader assets outside the staged starter
directories. Provide two Vally eval variants generated from or checked against
one task definition. SDK names, language-specific paths, commands, and links
may differ; behavioral requirements may not.

Keep the package independent of Watershed's example directories. A maintainer
can copy the benchmark package to the Fluid repository and select the local
Fluid SDK build. Preparation resolves local SDK packages and stages only the
source/build assets required to use them. Do not copy the complete host
repository into the agent workspace.

Run agents in disposable, isolated workspaces, not the developer's active
checkout. Exclude completed app examples, hidden tests, reference solutions,
host Git history, unrelated repository instructions, credentials, and the
other starter. Do not give the agent filesystem or tool access to the host
checkout. Ordinary Vally file staging alone does not establish this isolation;
the runner must enforce the boundary.

Give both variants a task-local agent instruction file with equivalent build,
test, and editing guidance. Do not inject Watershed's skill collection into one
variant but not the other.

Expose the selected SDK's public implementation, API documentation, and
required language/framework reference material. Use an explicit staged
allowlist, excluding finished app examples. Block external network access from
agent-controlled tools; prepare dependencies beforehand. Permit the executor's
model/authentication traffic outside that tool boundary and allow access to the
trial's local services. Keep runtime authentication outside the workspace.
Use the same access policy for both variants and record the supplied
documentation manifests. This controls access policy, not the amount or
quality of each SDK's docs.

The runner starts each trial with fresh document/service state and unique
ports. It owns only the processes and temporary resources it creates.

## Vally integration

Use Vally's built-in Copilot SDK executor initially. Keep the benchmark task and
graders independent of that executor so another agent runtime can use them.

Use `agent_environment` to stage the selected starter and run setup commands.
Use `grading_environment.files` to add grader-only assets after the agent
finishes. Keep grader source outside any directory staged for the agent,
including local SDK source selections.

Use the built-in `run-command` grader to invoke a trusted grading entry point.
The entry point builds the candidate, runs model checks and browser scenarios,
and writes a versioned JSON report. Each check records an ID, pass/fail,
failure classification, timing, and evidence. Logs identify the scenario,
client, action, and last observed state.

Use the command's exit status for the required-check verdict. A partial
capability score belongs in the detailed report; do not mistake Vally's binary
command-grader score for that partial score. Require the final all-required
verdict marker as well as a successful process exit.

Pin the Vally version. Verify its actual workspace, staging, timeout, and result
artifact behavior before connecting paid agent runs. Do not assume Vally's
hidden-file staging prevents an unrestricted agent from reading host files.

## Grading

Use deterministic executable checks, not an LLM judge, for the v1 verdict.
Run these required groups:

| Group | Required evidence |
| --- | --- |
| Integrity and build | Allowed edits only; real pinned SDK; successful native compilation/type checking and app build. |
| Native model | Nested object and array schema, optional assignee absence, property-level edits, and node identity across moves. |
| Local operations | Incident and step CRUD, optional removal, completion, empty lists, moves in both directions, and no-op moves. |
| Identity | Editing an item after a sibling moves or disappears affects the intended item; deleted items do not redirect edits. |
| Live collaboration | Two isolated browser clients open one document, submit edits from each side, and receive remote updates without reload. |
| Concurrency | Concurrent edits to distinct properties both survive; concurrent inserts survive with unique identities; same-property writes converge to a submitted value. |
| Join and reopen | A late client sees existing state; a fresh session reopens the delivered document after the original clients close. |
| Lifecycle and errors | Close unsubscribes and closes the SDK session; closed controls are inert; open/create/service errors remain visible without automatic create retries. |

SDK-specific hidden probes inspect the real schema, node identity, mutation
effects, and subscription disposal. Browser checks use shared selectors and
observable outcomes. Do not grade source-string matches for particular helper
names or require the agent to follow a reference implementation.

For concurrency, hold transport delivery or use a supported harness barrier
until both clients have submitted edits. Verify both submissions before
releasing delivery. Sequential browser actions without a delivery barrier are
not evidence of concurrency. Do not fabricate SDK operation or connection
events. Check winner-independent convergence after delivery.

Reorder tests cover shared sequential moves and captured-node identity; v1
does not prescribe the order resulting from conflicting concurrent moves.
Test removed-target behavior after observing deletion, without prescribing a
winner for a concurrent edit/delete race.

Use condition-based waits with finite deadlines. Before closing, wait for
another client to observe the edit. Use a fresh browser context without the
original clients' storage for reopen, then assert the expected content from
the service. Closing alone does not prove durability. Keep the same local
service running; service-restart durability is outside v1.

Fail on page errors, unhandled rejections, malformed reports, stalled probes,
and missing checks. Do not skip a browser scenario because Chromium or a
service is unavailable.

## Failure classification and reports

Preflight dependencies, browser availability, service readiness, and SDK
resolution before starting the agent. Run service health probes outside the
candidate code.

Classify build failures, missing implementations, broken candidate lifecycle,
and candidate timeouts as agent failures. Classify a failed infrastructure
preflight as an invalid trial. If infrastructure fails during grading, retain
logs, mark the trial invalid, and report it separately. Do not call a
candidate-induced crash an infrastructure failure merely because it surfaced
as a timeout.

Do not retry agent failures. Any replacement for an invalid infrastructure
trial gets a new run ID, with the original invalid record retained.

For each trial, retain the candidate diff, Vally trajectory, grading report,
browser/service diagnostics, and a manifest containing:

- Eval revision, starter revision, task hash, and documentation manifest.
- SDK source revision and resolved package versions.
- Agent executor, model identity, effective limits, and run order.
- Node, Gleam, browser, and relevant framework/toolchain versions.
- Per-check results and infrastructure classification.
- Agent duration, tool calls, and token counts reported by Vally.

Record cost only when the provider supplies comparable, complete cost data.
Preserve unavailable metrics as unavailable. Keep dependency preparation,
agent working time, and grading duration separate.

Report all-required-checks pass rate, per-group pass rates, and individual
failed scenarios. Include partial check completion for diagnosis without
allowing strong CRUD results to mask failed collaboration. For comparative
runs, show the number of valid and invalid trials per SDK alongside results.

Use identical explicit model settings and resource limits for each matched
run. The operator supplies trial count and an agent working-time limit; record
their resolved values and reject a comparison with mismatched settings.
Do not impose a token budget. Record provider-reported token usage as a metric.
Alternate SDK execution order across repeated trials. Do not infer
comparative performance from a single successful demonstration.

## Validation before benchmark use

Validate the benchmark without paying for agent trials first:

- Confirm Vally accepts both specs and stages agent/hidden assets as intended.
- Build each untouched starter; confirm the unfinished model fails the
  relevant public and hidden behavior checks.
- Run private known-good implementations through the complete grading path
  for each SDK. Keep these validation fixtures out of agent environments.
- Use deliberate broken candidates to prove detection of local-only state,
  serialized-root replacement, stale-index edits, ignored remote updates,
  reset-on-open, leaked subscriptions, and modified acceptance assets.
- Confirm a two-client test cannot pass after making its delivery sequential.
- Confirm missing services, absent browsers, invalid reports, and timeouts
  produce explicit unsuccessful outcomes with the right classification.
- Execute the same benchmark package from both repository contexts without
  accessing Watershed example files or assuming its directory layout.
- Inspect a prepared workspace and the enforced filesystem/network boundary
  for answer leakage before starting an agent.

Only then run a small matched pilot. Review grading failures and infrastructure
reliability before spending on a larger comparison.

## References

- [Vally pipeline](https://microsoft.github.io/vally/concepts/how-it-works/)
- [Writing Vally eval specs](https://microsoft.github.io/vally/guides/writing-eval-specs/)
- [Vally run-command grader](https://microsoft.github.io/vally/reference/graders/run-command/)
- [Watershed typed schema authoring](../../shared-tree-schema-authoring.md)
- [Existing paired project-brief harness](../../../examples/shared_tree_project_brief_lustre/README.md)

The paired project-brief example supplies maintainer-facing harness prior art.
It must not become part of the evaluated agent's starter or documentation set.
