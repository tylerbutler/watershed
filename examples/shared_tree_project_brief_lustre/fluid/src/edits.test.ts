import assert from "node:assert/strict";
import { test } from "node:test";
import { Tree, TreeStatus } from "fluid-framework";
import { createIndependentTreeView } from "fluid-framework/beta";
import { ProjectBrief, Review, initial, treeConfiguration } from "./schema.ts";
import { appendMilestone, assign, removeMilestone, removeReview } from "./edits.ts";

test("captured milestone survives a neighbor removal without shifting edit targets", () => {
  const brief = new ProjectBrief(initial("first", "second"));
  const captured = brief.schedule.milestones[1];
  removeMilestone(brief, brief.schedule.milestones[0]);
  assign(brief, captured, "title", "Captured");
  assert.equal(brief.schedule.milestones[0], captured);
  assert.equal(captured.id, "second");
  assert.equal(captured.title, "Captured");
  removeMilestone(brief, captured);
  appendMilestone(brief);
  appendMilestone(brief);
  const [a, b] = brief.schedule.milestones;
  assert.notEqual(a.id, b.id);
  assert.match(a.id, /^[0-9a-f-]{36}$/);
  assert.throws(() => assign(brief, captured, "title", "Stale"), /removed/i);
  assert.throws(() => removeMilestone(brief, captured), /removed/i);
  assert.equal(a.title, "");
});

test("captured review cannot edit or remove its replacement, even on detached nodes", () => {
  const brief = new ProjectBrief(initial("first", "second"));
  brief.review = new Review({ reviewer: "Old", approved: false });
  const old = brief.review;
  removeReview(brief, old);
  brief.review = new Review({ reviewer: "New", approved: false });
  assert.throws(() => assign(brief, old, "reviewer", "Stale"), /removed/i);
  assert.throws(() => removeReview(brief, old), /removed/i);
  assert.equal(brief.review.reviewer, "New");
});

function realView() {
  const view = createIndependentTreeView(treeConfiguration);
  view.initialize(initial("first", "second"));
  return view;
}

test("hydrated removed nodes are rejected using the public Tree status API", () => {
  const view = realView();
  try {
    const brief = view.root;
    const old = brief.schedule.milestones[0];
    assert.equal(Tree.status(old), TreeStatus.InDocument);
    removeMilestone(brief, old);
    assert.notEqual(Tree.status(old), TreeStatus.InDocument);
    assert.throws(() => assign(brief, old, "completed", true), /removed/i);
    brief.review = new Review({ reviewer: "Old", approved: false });
    const review = brief.review;
    removeReview(brief, review);
    brief.review = new Review({ reviewer: "New", approved: false });
    assert.notEqual(Tree.status(review), TreeStatus.InDocument);
    assert.throws(() => assign(brief, review, "approved", true), /removed/i);
    assert.equal(brief.review.approved, false);
  } finally { view.dispose(); }
});
