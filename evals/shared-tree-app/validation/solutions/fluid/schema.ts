import { SchemaFactory, TreeViewConfiguration } from "fluid-framework";

const schema = new SchemaFactory("incident_eval");
export class StepNode extends schema.object("Step", {
  id: schema.string, label: schema.string, done: schema.boolean,
}) {}
export class IncidentNode extends schema.object("Incident", {
  id: schema.string,
  title: schema.string,
  status: schema.string,
  assignee: schema.optional(schema.string),
  steps: schema.array("Steps", StepNode),
}) {}
export class BoardNode extends schema.object("Board", {
  // mutation:start board-schema
  incidents: schema.array("Incidents", IncidentNode),
  // mutation:end board-schema
}) {}
export const configuration = new TreeViewConfiguration({ schema: BoardNode });
