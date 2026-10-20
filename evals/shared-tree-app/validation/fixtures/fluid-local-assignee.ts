import { SchemaFactory, TreeViewConfiguration } from "fluid-framework";

const schema = new SchemaFactory("incident_eval");
export class StepNode extends schema.object("Step", {
  id: schema.string, label: schema.string, done: schema.boolean,
}) {}
export class IncidentNode extends schema.object("Incident", {
  id: schema.string, title: schema.string, status: schema.string,
  steps: schema.array("Steps", StepNode),
}) {
  assignee?: string;
}
export class BoardNode extends schema.object("Board", {
  incidents: schema.array("Incidents", IncidentNode),
}) {}
export const configuration = new TreeViewConfiguration({ schema: BoardNode });
