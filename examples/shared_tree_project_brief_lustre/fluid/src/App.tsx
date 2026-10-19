import { useLayoutEffect, useRef, useSyncExternalStore } from "react";
import { BriefInput } from "./BriefInput.tsx";
import { appendMilestone, assign, removeMilestone, removeReview, type EditableNode } from "./edits.ts";
import type { BriefSession } from "./fluid.ts";
import { Review } from "./schema.ts";
import { fieldKey, type Field } from "./selection.ts";

function Selectors({ session, field }: { session: BriefSession; field: Field }) {
  const key = fieldKey(field);
  return <span data-selection-for={key} className="selectors">
    {session.peers.filter((peer) => peer.metadata.selected &&
      fieldKey(peer.metadata.selected) === key).map((peer) =>
      <span key={peer.sessionId} className={`badge ${peer.metadata.color}`}>{peer.metadata.name}</span>)}
  </span>;
}

interface FieldProps {
  session: BriefSession;
  field: Field;
  node: EditableNode;
  label: string;
}

function TextField({ session, field, node, label, value, edit }: FieldProps & {
  value: string; edit(value: string): void;
}) {
  return <label className="field">{label}
    <BriefInput field={fieldKey(field)} value={value} node={node} disabled={!session.editable}
      onValue={(next) => session.edit(() => edit(next))}
      onFocus={() => session.select(field, node)} onBlur={() => session.select(null)} />
    <Selectors session={session} field={field} />
  </label>;
}

function Checkbox({ session, field, node, label, checked, edit }: FieldProps & {
  checked: boolean; edit(value: boolean): void;
}) {
  const ref = useRef<HTMLInputElement>(null);
  const previousNode = useRef(node);
  useLayoutEffect(() => {
    if (previousNode.current !== node) {
      previousNode.current = node;
      ref.current?.blur();
    }
  });
  return <label className="field checkbox">
    <input ref={ref} type="checkbox" data-field={fieldKey(field)} checked={checked}
      disabled={!session.editable} onChange={(event) => {
        const next = event.currentTarget.checked;
        session.edit(() => edit(next));
      }}
      onFocus={() => session.select(field, node)} onBlur={() => session.select(null)} />
    {label}<Selectors session={session} field={field} />
  </label>;
}

function Form({ session }: { session: BriefSession }) {
  const root = session.root;
  const owner = root.owner;
  const schedule = root.schedule;
  const review = root.review;
  const fixed = (field: Extract<Field, { kind: "fixed" }>["field"]): Field => ({ kind: "fixed", field });
  const text = (label: string, field: Field, node: EditableNode, value: string,
    edit: (value: string) => void) =>
    <TextField {...{ label, field, node, value, edit, session }} />;
  const action = (name: string, label: string, edit: () => void) =>
    <button type="button" data-action={name} disabled={!session.editable}
      onClick={() => session.edit(edit)}>{label}</button>;
  return <div className="brief">
    <fieldset><legend>Brief</legend>
      {text("Title", fixed("title"), root, root.title, (value) => assign(root, root, "title", value))}
    </fieldset>
    <fieldset><legend>Owner</legend>
      {text("Name", fixed("owner.name"), owner, owner.name, (value) => assign(root, owner, "name", value))}
      {text("Email", fixed("owner.email"), owner, owner.email, (value) => assign(root, owner, "email", value))}
    </fieldset>
    <fieldset><legend>Schedule</legend>
      {text("Start", fixed("schedule.start"), schedule, schedule.start,
        (value) => assign(root, schedule, "start", value))}
      {text("Target", fixed("schedule.target"), schedule, schedule.target,
        (value) => assign(root, schedule, "target", value))}
      <div className="milestones">{Array.from(schedule.milestones).map((node) => {
        const title: Field = { kind: "milestone", id: node.id, field: "title" };
        const completed: Field = { kind: "milestone", id: node.id, field: "completed" };
        return <div key={node.id} data-milestone-id={node.id} className="milestone">
          {text("Milestone title", title, node, node.title, (value) => assign(root, node, "title", value))}
          <Checkbox session={session} field={completed} node={node} label="Completed"
            checked={node.completed} edit={(value) => assign(root, node, "completed", value)} />
          {action("remove-milestone", "Remove milestone", () => removeMilestone(root, node))}
        </div>;
      })}</div>
      {action("add-milestone", "Add milestone", () => appendMilestone(root))}
    </fieldset>
    <fieldset><legend>Review</legend>
      {review ? <>
        {text("Reviewer", fixed("review.reviewer"), review, review.reviewer,
          (value) => assign(root, review, "reviewer", value))}
        <Checkbox session={session} field={fixed("review.approved")} node={review} label="Approved"
          checked={review.approved} edit={(value) => assign(root, review, "approved", value)} />
        {action("remove-review", "Remove review", () => removeReview(root, review))}
      </> : action("add-review", "Add review", () => {
        if (root.review) throw new Error("Review was already added");
        root.review = new Review({ reviewer: "", approved: false });
      })}
    </fieldset>
  </div>;
}

export function App({ session }: { session: BriefSession }) {
  useSyncExternalStore(session.subscribe, session.snapshot);
  return <main data-tree-change-count={session.treeChangeCount}>
    <h1>SharedTree project brief</h1>
    <p>Copy this URL into another tab. Each edit assigns one property; simultaneous typing is not character-level merging.</p>
    <p role="status" data-runtime-status={session.status}>{session.status}</p>
    <p data-document-id={session.documentId}>Document: {session.documentId}</p>
    <p>{session.metadata.name} · tab session: {session.sessionId}</p>
    <p>{session.editable ? "Field selection is advisory. Everyone can edit."
      : "Awareness unavailable. Durable edits require a ready connection."}</p>
    {!session.closed && session.valid && <Form session={session} />}
    <button type="button" data-action="close" disabled={session.closed}
      onClick={() => session.close()}>Close</button>
    <div role="alert">{session.errors.map((error, index) =>
      <p key={index} data-error="">{error}</p>)}</div>
    <p>Development authentication only. These credentials are not for production.
      This app opens Fluid documents, not watershed documents.
      Closing does not confirm pending edits were saved. Selection uses the experimental Fluid Signaler.</p>
  </main>;
}
