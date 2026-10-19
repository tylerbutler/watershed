# SharedTree project brief comparison

## Purpose

Add a second Fluid/watershed comparison that demonstrates an object-shaped
SharedTree through a live collaborative form. The item counter remains the
small array example. This example answers a different question: what happens
when two people edit different parts of the same structured document?

The user approved a matched pair of runnable apps, a website source comparison,
and a project brief with nested owner and schedule objects and an optional
review object. They specifically requested remote changes on the editing
surface while another field is being edited, plus field-selection awareness
through signals/ripples. Selection is advisory; simultaneous same-field editing
is allowed.

During planning, the user also approved an array of milestone objects nested
under schedule. Arrays support the object-centered demonstration rather than
replacing it with another top-level list.

## Deliverables and boundaries

- A Gleam/Lustre app under `examples/shared_tree_project_brief_lustre/`.
- An independently runnable TypeScript/React Fluid counterpart under that
  example's `fluid/` directory. This is locally authored comparison code, not
  a pinned official Fluid example or an upstream source snapshot.
- A source comparison at `/sharedtree/project-brief`, linked from the existing
  SharedTree pages and the example catalog.
- Documented run commands and focused automated checks for both apps.

The Fluid app uses a supported local Fluid service configuration, following
the existing reference's AzureClient local connection to Tinylicious. The
watershed app uses the existing local Floodgate workflow. Each app shares its
own document URL with another instance of that app. Neither app claims to open
the other's documents. Use explicit package versions for the Fluid app and
verify the selected versions' public tree and signal APIs before implementation.

Do not expand this into a generic form framework, a new presence library, a
production authentication flow, or a SharedTree SDK change unless a concrete
blocker requires a separately reviewed change.

## Data model

```text
ProjectBrief
  title: string
  owner: Owner
    name: string
    email: string
  schedule: Schedule
    start: string
    target: string
    milestones: Milestone[]
      id: string
      title: string
      completed: boolean
  review?: Review
    reviewer: string
    approved: boolean
```

Declare equivalent named object types and field optionality in both SDKs.
Watershed uses ordinary Gleam records, `Option(Review)`, and the existing typed
schema builder. Fluid uses its public object-schema APIs. Milestones are the
only array in the schema.

Provide the same initial brief in both apps, with meaningful populated owner
and schedule fields and no review. Dates are plain string properties, not a
date-validation demonstration. Text fields must accept intermediate values
while typing; do not use native email/date validation to block publication.
Start with two named, incomplete milestones. Each inserted milestone receives
a fresh UUID in its immutable application `id` field. Validate uniqueness on
construction/read and never reuse IDs. Adding review inserts an object with
an empty reviewer and `approved = false`.
Removing review clears the optional property.

Property edits must target the existing object's property. Do not encode and
replace the whole brief, owner, or schedule to update one leaf. Review
creation/removal deliberately demonstrates changing tree structure.

The milestone array supports append, remove, live title edits, and completion
toggles. Do not add reordering controls. Use node references for edits/removal
and stable milestone IDs for keyed rendering and presence. Never capture an
array index as the identity of a later action. An edit to one milestone and
an insertion/removal of a different milestone must both survive.

## Surface and editing behavior

Both apps present the same compact form, grouped as brief, owner, schedule,
and optional review. Use text inputs for string properties and a checkbox for
approval and milestone completion. Include Add milestone, per-milestone Remove,
Add review, Remove review, connection state, local session
identity, and a visible error area. Do not add Apply or Save buttons.

Publish each ordinary input change to its corresponding tree property.
Subscribe to document changes and render received values directly in their
fields, even while the local user edits another field. A JSON inspector or
event log is not a substitute for updating the form.

Keep field elements stable across ordinary data and presence updates. Updating
another field must preserve the focused element, its text, caret, and selection
range. Avoid writing an input's DOM value when it already matches the value
to render.

Multiple users can edit the same field. Show all remote selectors and render
the SDK's resolved property value live, including in a focused field. Preserve
the local selection range when programmatically changing that field, clamped
to the new string length. Do not invent a last-writer algorithm in application
code or promise character-level merging: each edit assigns a string property.

IME composition is the one rendering exception. During local composition,
leave the composing input under browser control and defer remote value writes
to that input only. Publish the completed composed value at composition end,
then resume rendering resolved tree values. Other fields and presence continue
updating throughout. Do not publish partial composition strings or submit the
completed string twice through composition-end and input handlers.

When review disappears, remove its controls and clear local focus/selection
state targeting it. Retained references to the removed object must not edit a
replacement review. Adding another review does not restore focus or selection
automatically. Report a stale edit explicitly rather than redirecting it to the
new object.

## Two collaboration channels

SharedTree carries the durable brief. Fluid signals and watershed ripples carry
ephemeral field selection. Sending awareness must not edit the tree, produce a
tree commit, or become part of a saved summary.

Use watershed's existing `presence_js` driver with `presence.Ripple` explicitly
selected. It already supports immediate metadata updates, heartbeats, and
peer expiry. Use a small Fluid adapter over the selected SDK's public signal
API with equivalent behavior, not a durable DDS for presence.

Each session advertises a display name, color, and optional field selection.
Use an enumerated set of field identifiers such as `owner.name` and
`schedule.target`; reject unrecognized fields. A session is a tab, not a user:
two tabs belonging to one user must remain independently visible.

Milestone targets contain the milestone ID and either `title` or `completed`.
They do not contain an array index. Removing a milestone clears its local and
remote selections; no badge can move to a surviving neighbor. Ignore presence
for milestone IDs not present in the current document.

Focus announces selection immediately. Moving focus announces the new field;
leaving the form announces no selection. Apply the same rule to the approval
checkbox. A peer's selection decorates the field with an outline and a name
badge. Names, not color alone, identify selectors. Multiple selectors get
multiple names rather than hiding one another. These decorations do not
disable editing or claim ownership.

Use the existing driver's default two-second heartbeat and 6.5-second expiry
window in both apps. A late joiner sees current selections by the next
heartbeat. Refreshing metadata must refresh liveness, including an unchanged
selection. Heartbeats must not move focus or cause new tree edits.

When the local client disconnects, clear its view of remote badges and show
that awareness is unavailable. A peer that silently disappears expires
from other clients after the liveness window. On reconnect, announce the
current local selection with the active session identity and rebuild remote
awareness from fresh messages, not a persisted roster.

While review is absent, never display presence for its fields. On review
removal, clear cached selections targeting that object and invalidate the
local selection. A heartbeat must not restore a selection on a replacement
review merely because its field path matches. The adapter must distinguish
repeated announcements of an invalidated selection from a fresh focus event;
use a per-session selection token that changes on focus transitions and is
preserved by heartbeats. Suppress invalidated tokens until the session makes a
new selection. This token is ephemeral metadata, not another stored property.

Stop presence timers and subscriptions when closing or disposing the view.
Peers may retain a departed ripple session until expiry; do not promise
instant departure detection. A graceful blur can announce no selection, but
correctness must not depend on browser unload events.

## Implementation responsibilities

Keep each app's schema and document operations separate from its view and
awareness adapter. Use existing lifecycle, configuration, error-reporting,
development-authentication, and browser-test patterns where they fit.
Do not extract a cross-framework UI or a generic protocol package.

Watershed reads typed snapshots for rendering and uses typed node references
and property descriptors for edits. Fluid renders from its subscribed live
tree view. Both implementations must distinguish content updates from presence
updates and preserve the input behavior described above.

Subscribe and read the initial state without losing an intervening update.
Clean up tree observation, presence, and document resources. A late callback
after close must not revive the editor. Expose creation, connection, schema,
read, edit, and presence errors; do not turn failed reads into blank fields or
retry uncertain document creation.

If disconnected, disable durable edits and show the connection state rather
than promising offline authoring. Do not claim pending edits were saved on
close. Development credentials remain clearly labeled and must not be
presented as production authentication.

## Website comparison

Follow the existing side-by-side comparison structure, with sections for:

- Nested object schema and the optional review.
- The milestone array inside schedule, including stable node-targeted edits.
- Creation, opening, and resource lifetime.
- Live observation: Fluid's live view versus watershed's typed snapshots.
- Property edits through object identity rather than parent replacement.
- Field selection over signals/ripples, separate from durable content.

Explain the expected two-client interaction beside the source. State the
same-field string-assignment limitation and the absence of cross-SDK document
interoperability claims.

All real source excerpts must use marker pairs, `website/snippets.json`,
generated `sourceSnippet` lookups, and `SnippetBlock`. Link both sides to the
locally authored example source; do not label the Fluid app as official
upstream code or reuse the item counter's upstream provenance metadata.
Keep the existing item counter comparison intact.

Use the website's house style for copy and literal accessible labels for
inputs, status, and field selectors. Do not announce every remote keystroke
through an assertive live region.

## Acceptance

Run the following scenarios independently against each implementation with
two isolated browser clients, without relying on interoperability between them.
Use event/state conditions and bounded waits, not sleeps that assume delivery.

1. Create a brief, open its shared URL in a second client, and verify the same
   initialized nested object values.
2. Focus `owner.name` in A and `schedule.target` in B. Both clients show the
   other session's field and name. Type in both fields and verify that remote
   text appears in the corresponding input before either client blurs.
3. While A keeps an input focused with a nontrivial selection range, let B edit
   another field and change field selection. Verify A's element identity,
   focus, text, and selection range remain unchanged.
4. Focus the same string field in both clients. Show both sessions' awareness,
   permit both to edit, and verify eventual resolved-value agreement without
   asserting character-level merge or a predetermined winning author.
5. Exercise composition events while a remote edit arrives. Verify the
   composing input is not overwritten, other fields still update, and the
   completed local composition publishes once. Cover shortened remote values
   when checking selection-range clamping.
6. Add review remotely and see its controls appear. Change reviewer and
   approval from separate clients. Remove it while the other client selects
   a review field; verify controls and badges disappear and a retained stale
   action cannot edit a new review added afterward.
7. Join while another client already selects a field and observe its selection
   within one heartbeat plus delivery allowance. Blur and see it clear. Drop
   a client without a graceful leave and verify expiry using the specified
   liveness window. Reconnect and verify fresh session awareness.
8. Verify selection-only activity creates no tree edits. Reload after durable
   edits are confirmed delivered and recover content, not old presence.
9. Verify visible connection/error states and close behavior, including no
   editing after close and no late callback reopening the view.
10. Focus a milestone title in A, then remove a preceding milestone in B.
    Verify A's field, caret, and remote selection badge remain attached to the
    same milestone ID. Append a milestone while another client edits an
    existing milestone; verify both changes survive. Remove the selected
    milestone and verify its controls and badges disappear and a retained
    stale action cannot edit another item.

Use focused pure tests for selection-state transitions, invalid messages,
expiry, stale review selections, and any extracted input-reconciliation logic.
Browser gates must exercise actual SDKs and their local services, not only
mock transports. Require Chromium for acceptance and report missing service
or browser prerequisites as blocked, not passed.

Validate the website's generated snippets, comparison data, links, and build
with the repository's existing tooling. Document exact build, run, and check
commands in the example README and wire the new example into the existing
example/test entry points.

## Non-goals

No array reordering, rich text, character cursors, locking, undo/redo, schema
evolution, offline authoring, persistent presence, production authentication,
or arbitrary form generation. The example demonstrates nested object edits
and live awareness; it is not a promise of application-level validation or
conflict-free simultaneous typing within one string.
