
## Transfers track: native checklist handoffs

This track includes every core requirement above and adds cross-incident step
transfers. The core exclusion of conflicting concurrent moves still applies;
transferring a step while another client edits it is now explicitly in scope.
Do not implement transactions, undo, offline authoring, or schema evolution.

Implement the supplied `transfer-step` action and UI. It names the source
`incident`, the step `id`, the `destination` incident, and an optional `before`
step ID in the destination (`null` means append). The Gleam action is
`TransferStep(incident, id, destination, before)`. Use the SDK's native cross-array
move operation. Removing and reinserting an equivalent value is not a transfer:
the actual step node, its native identity, and references acquired before the
transfer must survive.

Transfers must work to empty and populated incident checklists, in both
directions, before a destination sibling and at the end. A same-incident
transfer is a reorder; moving before oneself is inert. Preserve all step values
and the identities of both parent incidents and their checklist arrays.
Subsequent edits and reorders address the step under its current incident, even
after other nodes shift its index.

An empty or missing destination or a `before` ID outside that destination's
checklist must produce a visible error without changing the document. An action
whose source incident or step was removed must not recreate anything. Transfers
must obey the same readiness and Close rules as the core actions.

Two clients must support these schedules with actual concurrent native edits:

- One transfers a step while the other edits that same step's label or done
  field in the source checklist. After delivery, both clients see exactly one
  step in its destination with the concurrent edit intact. References acquired
  before the move still address that step.
- One removes a step while the other edits that same step. After delivery,
  clients agree, the removed step stays absent, and no unrelated step changes.
  A stale action must not resurrect it.

The grader controls operation delivery and requires both clients to submit
native operations before delivery resumes. Sequential edits or a local shadow
board do not satisfy these requirements. A late joiner and a fresh session
opened after all existing sessions close must see the transferred state.
