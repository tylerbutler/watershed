import assert from "node:assert/strict";
import { test } from "node:test";
import {
  Milestone,
  Owner,
  ProjectBrief,
  Review,
  Schedule,
  initial,
  treeConfiguration,
  validateUniqueIds,
} from "./schema.ts";

test("initial construction data retains nested fields and an absent review", () => {
  const data = initial("first", "second");
  assert.deepEqual(data, {
    title: "Release brief",
    owner: { name: "Alex", email: "alex@example.test" },
    schedule: {
      start: "2026-11-02",
      target: "2026-11-16",
      milestones: [
        { id: "first", title: "Agree scope", completed: false },
        { id: "second", title: "Ship preview", completed: false },
      ],
    },
  });
  const brief = new ProjectBrief(data);
  assert.equal(treeConfiguration.schema, ProjectBrief);
  assert.ok(brief.owner instanceof Owner);
  assert.ok(brief.schedule instanceof Schedule);
  assert.ok(brief.schedule.milestones[0] instanceof Milestone);
  assert.equal(brief.review, undefined);
  assert.doesNotThrow(() => validateUniqueIds(brief.schedule.milestones));
});

test("nested properties mutate in place and empty review differs from absence", () => {
  const brief = new ProjectBrief(initial("first", "second"));
  const owner = brief.owner;
  const schedule = brief.schedule;
  const milestone = schedule.milestones[0];
  assert.ok(milestone);
  brief.title = "";
  owner.name = "";
  owner.email = "alex@";
  schedule.start = "2026-";
  schedule.target = "";
  milestone.title = "";
  milestone.completed = true;
  schedule.milestones.insertAtEnd({ id: "third", title: "", completed: false });
  assert.equal(brief.owner, owner);
  assert.equal(brief.schedule, schedule);
  assert.equal(brief.owner.email, "alex@");
  assert.equal(brief.schedule.start, "2026-");
  assert.equal(brief.schedule.milestones[0], milestone);
  assert.equal(brief.schedule.milestones[0].title, "");
  assert.equal(brief.schedule.milestones[0].completed, true);
  assert.equal(brief.schedule.milestones.length, 3);
  brief.review = new Review({ reviewer: "", approved: false });
  assert.ok(brief.review instanceof Review);
  assert.equal(brief.review.reviewer, "");
  assert.equal(brief.review.approved, false);
  brief.review.reviewer = "Alex";
  brief.review.approved = true;
  assert.equal(brief.review.reviewer, "Alex");
  assert.equal(brief.review.approved, true);
  brief.review = undefined;
  assert.equal(brief.review, undefined);
});

test("duplicate milestone IDs are rejected on construction data and tree reads", () => {
  assert.doesNotThrow(() => validateUniqueIds([]));
  const data = initial("same", "same");
  assert.throws(() => validateUniqueIds(data.schedule.milestones), /duplicate/i);
  const brief = new ProjectBrief(initial("first", "second"));
  brief.schedule.milestones.insertAtEnd({
    id: "first",
    title: "Duplicate",
    completed: false,
  });
  assert.throws(() => validateUniqueIds(brief.schedule.milestones), /duplicate/i);
});
