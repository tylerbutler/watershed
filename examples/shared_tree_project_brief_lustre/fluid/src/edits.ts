import { Tree, TreeStatus } from "fluid-framework";
import { Milestone, Owner, ProjectBrief, Review, Schedule } from "./schema.ts";
import type { Field } from "./selection.ts";

export type EditableNode = ProjectBrief | Owner | Schedule | Review | Milestone;
type Property<T> = Exclude<{
  [K in keyof T]: T[K] extends string | boolean ? K : never
}[keyof T], "id">;

export function current(brief: ProjectBrief, node: EditableNode): boolean {
  const status = Tree.status(node);
  if (status !== TreeStatus.InDocument && status !== TreeStatus.New) return false;
  return node === brief || node === brief.owner || node === brief.schedule ||
    node === brief.review || Array.from(brief.schedule.milestones).some((item) => item === node);
}

function requireCurrent(brief: ProjectBrief, node: EditableNode): void {
  if (!current(brief, node)) throw new Error("Edit target was removed or replaced");
}

export function assign<T extends EditableNode, K extends Property<T>>(
  brief: ProjectBrief, node: T, property: K, value: T[K],
): void {
  requireCurrent(brief, node);
  node[property] = value;
}

export function appendMilestone(brief: ProjectBrief): void {
  brief.schedule.milestones.insertAtEnd({
    id: crypto.randomUUID(), title: "", completed: false,
  });
}

export function removeMilestone(brief: ProjectBrief, node: Milestone): void {
  requireCurrent(brief, node);
  const index = Array.from(brief.schedule.milestones).indexOf(node);
  if (index < 0) throw new Error("Milestone was removed");
  brief.schedule.milestones.removeAt(index);
}

export function removeReview(brief: ProjectBrief, node: Review): void {
  requireCurrent(brief, node);
  brief.review = undefined;
}

export function target(brief: ProjectBrief, field: Field): EditableNode | undefined {
  if (field.kind === "milestone") {
    return Array.from(brief.schedule.milestones).find((item) => item.id === field.id);
  }
  if (field.field.startsWith("review.")) return brief.review;
  if (field.field.startsWith("owner.")) return brief.owner;
  if (field.field.startsWith("schedule.")) return brief.schedule;
  return brief;
}
