import { Tree, TreeStatus, NodeKind, FieldKind, SchemaFactory } from "fluid-framework";
import { nativeView, nativeContainer } from "./src/model.ts";
import { BoardNode } from "./src/schema.ts";

let view;
let container;
const captured = new Map();
const leaves = new SchemaFactory("eval_native_probe");

function schemaCheck(root) {
  const fields = node => {
    if (node.kind !== NodeKind.Object || !node.fields) throw new Error("Expected a native object schema");
    return node.fields;
  };
  const fieldType = (fields, key, optional = false) => {
    const field = fields.get(key);
    const allowedKind = optional ? FieldKind.Optional : FieldKind.Required;
    if (!field || (field.kind !== allowedKind && !(key === "id" && field.kind === FieldKind.Identifier))) {
      throw new Error(`Expected ${optional ? "optional" : "required"} native field: ${key}`);
    }
    const types = [...field.allowedTypeSet];
    if (types.length !== 1) throw new Error(`Expected one native field type: ${key}`);
    return types[0];
  };
  const arrayElement = array => {
    if (array.kind !== NodeKind.Array) throw new Error("Expected a native array schema");
    const types = [...array.childTypes];
    if (types.length !== 1) throw new Error("Expected one native array element schema");
    return types[0];
  };
  const leaf = (fields, key, expected, optional = false) => {
    const type = fieldType(fields, key, optional);
    if (type.kind !== NodeKind.Leaf || type.identifier !== expected.identifier) {
      throw new Error(`Wrong native leaf schema: ${key}`);
    }
  };
  const board = fields(root);
  const incident = fields(arrayElement(fieldType(board, "incidents")));
  for (const key of ["id", "title", "status"]) leaf(incident, key, leaves.string);
  leaf(incident, "assignee", leaves.string, true);
  const step = fields(arrayElement(fieldType(incident, "steps")));
  leaf(step, "id", leaves.string);
  leaf(step, "label", leaves.string);
  leaf(step, "done", leaves.boolean);
}

function snapshot(root) {
  return { incidents: [...root.incidents].map(incident => ({
    id: incident.id, title: incident.title, status: incident.status,
    ...(incident.assignee === undefined ? {} : { assignee: incident.assignee }),
    steps: [...incident.steps].map(step => ({ id: step.id, label: step.label, done: step.done })),
  })) };
}

export function inspect() {
  const session = globalThis.__incidentEval.native();
  view = nativeView(session);
  container = nativeContainer(session);
  if (!Tree.is(view.root, BoardNode) || Tree.schema(view.root).kind !== NodeKind.Object) {
    throw new Error("Accessor did not return the native board object");
  }
  schemaCheck(Tree.schema(view.root));
  if (Tree.schema(view.root.incidents).kind !== NodeKind.Array) throw new Error("Incidents are not a native array");
  for (const incident of view.root.incidents) {
    if (Tree.schema(incident).kind !== NodeKind.Object || Tree.schema(incident.steps).kind !== NodeKind.Array) {
      throw new Error("Incident/steps are not nested native nodes");
    }
    for (const step of incident.steps) {
      if (Tree.schema(step).kind !== NodeKind.Object) throw new Error("Step is not a native node");
    }
  }
  return { native: true, schema: true, board: snapshot(view.root) };
}

export function capture() {
  inspect();
  captured.clear();
  captured.set("root", view.root);
  captured.set("incidents", view.root.incidents);
  for (const incident of view.root.incidents) {
    captured.set(`incident:${incident.id}`, incident);
    captured.set(`steps:${incident.id}`, incident.steps);
    for (const step of incident.steps) captured.set(`step:${step.id}`, step);
  }
  return [...captured.keys()];
}

export function capturedState(key) {
  const node = captured.get(key);
  if (!node) throw new Error(`No captured native reference ${key}`);
  const attached = Tree.status(node) === TreeStatus.InDocument;
  let value = null;
  if (attached) {
    if (key === "root") value = snapshot(node);
    else if (key.startsWith("incident:")) value = snapshot({ incidents: [node] }).incidents[0];
    else if (key.startsWith("step:")) value = { id: node.id, label: node.label, done: node.done };
    else value = [...node].map(child => child.id);
  }
  return { attached, value };
}

export function setCaptured(key, property, value) {
  const node = captured.get(key);
  if (!node) throw new Error(`No captured native reference ${key}`);
  node[property] = value;
}

export function closed() {
  if (!view || !container) {
    const session = globalThis.__incidentEval.native();
    view = nativeView(session);
    container = nativeContainer(session);
  }
  let viewClosed = false;
  try { void view.root; } catch { viewClosed = true; }
  return { documentClosed: container.disposed, viewClosed };
}

Object.assign(globalThis, { __nativeEval: { inspect, capture, capturedState, setCaptured, closed } });
