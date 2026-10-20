import { SchemaFactory } from "fluid-framework";

const factory = new SchemaFactory("incident_eval");
export class BoardNode extends factory.object("Board", {}) {}
