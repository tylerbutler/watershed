# Task 7 report: preserved schema context

## Result

SharedTree message and summary codecs now carry schema context through ordered
outer changes. Data runs use the schema active at their authoring point.
Schema changes advance that context for later data in the same commit. The
normal encoder rejects inverse schema changes without adding a new wire field.

Summary history now rewinds from the summarized schema to the initial retained
schema, decodes trunk commits forward, and starts each peer branch from its base
revision. Initialization history can therefore move from `EmptySchema` to a
fixed schema before decoding later data. Duplicate retained revisions use the
latest trunk occurrence, matching history reconciliation.

## Retained history and replay

Summary export now writes the current semantic outer history payload instead
of patching one modular change into retained wire data. It keeps retained custom
metadata, but retained content cannot override a rebased semantic change.

Restored history receipts now retain the original semantic commit. A later
duplicate can authenticate its contents after summary restore and append its
new sequence point without applying the change twice.

The schema-evolution history corpus now compares its full observation shape.
The previous exclusions for accepted messages, replay, continuation, and
historical decode are removed.

## Interoperability

The codec producer emits a distinct native `summary-schema-initial` artifact.
The pinned upstream consumer loads it, observes its retained history, and
continues editing it for both Erlang and JavaScript outputs.

The summary artifact coordinator also requires schema context in every native
summary. It accepts either the current Schema index or retained schema changes
in EditManager history and fails closed when both are absent.

## Verification

- Erlang focused codec and summary tests: 49 passed.
- JavaScript focused codec and summary tests: 49 passed.
- Erlang schema-evolution history tests: 41 passed.
- Codec and summary interop coordinator tests: 23 passed.
- Native summary artifact interop: four scenarios per target loaded; six
  retained-history continuation checks passed.
- `just shared-tree-codec-interop`: two targets, 18 items each passed upstream
  consumption.
- `git diff --check`: passed.

## Concerns

Restored receipts retain semantic commit content, but summaries still do not
retain the original transport reference and minimum sequence numbers. A replay
at a later sequence point can authenticate its contents; transport-field
authentication that requires those omitted fields remains unavailable.
