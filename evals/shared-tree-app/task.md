# Implement a collaborative incident-response board

Complete the native SharedTree model and schema for the provided app shell.
Use the selected SDK and the commands in the starter's `AGENTS.md`. The shell,
development authentication, ID generator, and build tooling are provided.
Implement the model with the native SharedTree API, without changing the SDK.

## Document

Start a new document with an empty ordered incident list.

Each incident has an immutable, nonempty string ID, a string title, a status
(`open`, `investigating`, or `resolved`), an optional string assignee, and an
ordered list of checklist steps. A new incident has `open` status, no assignee,
and no steps. Each step has an immutable, nonempty string ID, a string label,
and a boolean completion flag, initially false. IDs are unique across the
document; the shell generates them for local creation.

Store incidents and steps as nested SharedTree objects and arrays. Assign
individual properties and use native moves to preserve identity. Do not store
the board in a JSON string, recreate nodes to reorder them, replace unrelated
subtrees on edits, use another DDS, or synchronize independent local state.
You may derive read-only UI snapshots from the tree.

## Actions

Support creating incidents, editing titles and statuses, setting or removing
assignees, and deleting incidents. Setting an assignee to `""` keeps a present
empty string; removal makes the optional property absent.

Support appending checklist steps, editing their labels, setting and clearing
completion, deleting steps, and reordering steps within their incident.
New incidents and steps append to their respective lists.

Reorder incidents and steps by immutable ID. Move an item before a specified
sibling, or append it when no destination sibling is specified. Support moves
in both directions. Moving an item before itself does nothing. A missing
destination sibling is an invalid input, distinct from an omitted destination.

Deleting an already-removed item does nothing. Editing or moving a removed
target must not affect another item or resurrect the removed node. Inserting
into a removed incident must not recreate that incident. Report other invalid
inputs through the shell's error interface without changing the document.
In particular, reject duplicate or empty IDs, invalid statuses, and moves
targeting a sibling from another list.

Every text edit assigns the complete string property. Intermediate strings,
including an empty title or label, are valid. Character-level merging is not
required.

## Collaboration and lifecycle

Create a document once and publish its document ID only after successful
creation/attachment. Share its URL so another client can open it. Opening an
existing document must not initialize or reset its content.

Observe local and remote edits without reload. After a sibling moves or
disappears, edits still target the intended incident or step, not its old
index.

Two clients can submit concurrent edits. Changes to distinct properties of an
existing node must both survive. Concurrent inserts must survive with distinct
identities. Same-property writes must converge to one submitted value; either
winner is acceptable. Conflicting concurrent move ordering is outside scope.

A late client must see existing content. After one client observes the other's
edit and both close, a new session with empty browser storage must reopen the
delivered content from the same running service. Closing does not itself prove
that pending edits reached the service. Service-restart durability, offline
authoring, and network-partition recovery are outside scope.

Close must unsubscribe and close the native SDK session. Disable durable
actions while not ready and after Close. Queued callbacks must not reactivate
a closed session. Show create, open, and service errors. Do not automatically
retry creation or attachment after an uncertain response.

## Boundaries and grading

Change only the starter's model/schema area and your own tests. Preserve the
provided model interface and native-handle inspection accessors. Do not change
the UI, build configuration, dependencies, SDK, or acceptance tooling.

Public smoke checks provide local feedback. Hidden checks use other data and
schedules to test these same requirements, including actual native node
identity and two isolated browser clients. You must pass all required checks;
working CRUD alone cannot compensate for broken collaboration.

Do not implement presence, transactions, undo/redo, schema evolution, custom
visual design, or cross-SDK document interoperability.
