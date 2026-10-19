import { SchemaFactory, TreeViewConfiguration } from "fluid-framework";
import type { InsertableTreeNodeFromImplicitAllowedTypes } from "fluid-framework";

const factory = new SchemaFactory("shared_tree_project_brief");

export class Milestone extends factory.object("Milestone", {
  id: factory.string,
  title: factory.string,
  completed: factory.boolean,
}) {}

export class Owner extends factory.object("Owner", {
  name: factory.string,
  email: factory.string,
}) {}

export class Schedule extends factory.object("Schedule", {
  start: factory.string,
  target: factory.string,
  milestones: factory.array("Milestones", Milestone),
}) {}

export class Review extends factory.object("Review", {
  reviewer: factory.string,
  approved: factory.boolean,
}) {}

export class ProjectBrief extends factory.object("ProjectBrief", {
  title: factory.string,
  owner: Owner,
  schedule: Schedule,
  review: factory.optional(Review),
}) {}

export const treeConfiguration = new TreeViewConfiguration({
  schema: ProjectBrief,
});

export function initial(
  firstId: string,
  secondId: string,
): InsertableTreeNodeFromImplicitAllowedTypes<typeof ProjectBrief> {
  return {
    title: "Release brief",
    owner: { name: "Alex", email: "alex@example.test" },
    schedule: {
      start: "2026-11-02",
      target: "2026-11-16",
      milestones: [
        { id: firstId, title: "Agree scope", completed: false },
        { id: secondId, title: "Ship preview", completed: false },
      ],
    },
  };
}

export function validateUniqueIds(items: Iterable<{ readonly id: string }>): void {
  const seen = new Set<string>();
  for (const item of items) {
    if (seen.has(item.id)) {
      throw new Error(`Duplicate milestone ID: ${item.id}`);
    }
    seen.add(item.id);
  }
}
