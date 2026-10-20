import * as model from "./build/dev/javascript/incident_eval/incident_eval/model.mjs";
import * as tree from "./build/dev/javascript/watershed/watershed/tree.mjs";
import * as protocol from "./build/dev/javascript/watershed/watershed/tree/live_types.mjs";
import * as schema from "./build/dev/javascript/watershed/watershed/tree/schema.mjs";
import * as types from "./build/dev/javascript/watershed/watershed/tree/types.mjs";
import * as errors from "./build/dev/javascript/watershed/watershed/tree/error.mjs";
import * as watershed from "./build/dev/javascript/watershed/watershed.mjs";
import * as dict from "./build/dev/javascript/gleam_stdlib/gleam/dict.mjs";
import { Some } from "./build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { Ok } from "./build/dev/javascript/prelude.mjs";

const captured = new Map();
let handle;
let document;

function unwrap(result) {
  if (!(result instanceof Ok)) throw new Error(errors.to_string(result[0]));
  return result[0];
}

function required(optional) {
  if (!(optional instanceof Some)) throw new Error("Native handle or node is absent");
  return optional[0];
}

function value(raw) {
  if (raw instanceof types.ObjectValue) {
    return Object.fromEntries([...raw.fields].map(([key, child]) => [key, value(child)]));
  }
  if (raw instanceof types.ArrayValue) return [...raw.elements].map(value);
  if (raw instanceof types.StringValue || raw instanceof types.BooleanValue) return raw[0];
  throw new Error("Unexpected native node kind");
}

function request(operation) { return unwrap(handle.backend.request(operation)); }
function read(ref) { return value(required(request(new protocol.Read(ref.anchor))[0])); }
function definition(id) { return unwrap(dict.get(handle.compiled.stored.repository.nodes, id)); }
function field(ref, key) {
  const node = definition(ref.identifier);
  if (!(node instanceof schema.Object)) throw new Error(`Not a native object: ${key}`);
  const result = new Map(node.fields).get(key);
  if (!result) throw new Error(`Missing native schema field: ${key}`);
  return new protocol.FieldProof(key, result);
}
function acquire(operation) { return required(request(operation)[0]); }
function child(ref, key) { return acquire(new protocol.ChildAcquire(ref.anchor, field(ref, key))); }
function nodes(array) {
  return read(array).map((_, index) => acquire(new protocol.ArrayAcquire(array.anchor, index)));
}

function schemaCheck() {
  const stored = handle.compiled.stored.repository;
  const nodeFor = field => {
    if (!field) throw new Error("Missing declared native field");
    const allowed = [...field.allowed_types];
    if (allowed.length !== 1) throw new Error("Expected one declared native node type");
    return definition(allowed[0]);
  };
  const objectFields = node => {
    if (!(node instanceof schema.Object)) throw new Error("Expected a native object schema");
    return new Map(node.fields);
  };
  const arrayElement = field => {
    const array = nodeFor(field);
    if (!(array instanceof schema.Array)) throw new Error("Expected a native array schema");
    return nodeFor(array.elements);
  };
  const leaf = (fields, key, kind) => {
    const field = fields.get(key);
    if (!field) throw new Error(`Missing schema field ${key}`);
    const node = nodeFor(field);
    if (!(node instanceof schema.Leaf) || !(node.kind instanceof kind)) {
      throw new Error(`Wrong native schema for ${key}`);
    }
  };
  const requiredField = (fields, key) => {
    const field = fields.get(key);
    if (!field || (!(field.cardinality instanceof schema.Required)
      && !(key === "id" && field.cardinality instanceof schema.Identifier))) {
      throw new Error(`Expected a required native field: ${key}`);
    }
    return field;
  };
  const board = objectFields(nodeFor(stored.root));
  const incident = objectFields(arrayElement(requiredField(board, "incidents")));
  for (const key of ["id", "title", "status"]) requiredField(incident, key);
  for (const key of ["id", "title", "status", "assignee"]) leaf(incident, key, schema.StringLeaf);
  if (!(incident.get("assignee").cardinality instanceof schema.Optional)) {
    throw new Error("Assignee is not an optional native field");
  }
  const step = objectFields(arrayElement(requiredField(incident, "steps")));
  for (const key of ["id", "label", "done"]) requiredField(step, key);
  leaf(step, "id", schema.StringLeaf);
  leaf(step, "label", schema.StringLeaf);
  leaf(step, "done", schema.BooleanLeaf);
}

export function inspect() {
  const current = globalThis.__incidentEval.native();
  handle = required(model.native_tree(current));
  document = required(model.native_document(current));
  if (!(handle.backend instanceof tree.Backend)) throw new Error("Accessor did not return an SDK tree backend");
  schemaCheck();
  const board = value(required(request(new protocol.RootRead(handle.token))[0]));
  return { native: true, schema: true, board, phase: watershed.diagnostics(document).phase };
}

export function capture() {
  inspect();
  captured.clear();
  const root = acquire(new protocol.RootAcquire(handle.token, new schema.Required()));
  captured.set("root", root);
  const incidents = child(root, "incidents");
  captured.set("incidents", incidents);
  for (const incident of nodes(incidents)) {
    const data = read(incident);
    captured.set(`incident:${data.id}`, incident);
    const steps = child(incident, "steps");
    captured.set(`steps:${data.id}`, steps);
    for (const step of nodes(steps)) captured.set(`step:${read(step).id}`, step);
  }
  return [...captured.keys()];
}

export function capturedState(key) {
  const ref = captured.get(key);
  if (!ref) throw new Error(`No captured native reference ${key}`);
  const status = request(new protocol.Status(ref.anchor))[0];
  return {
    attached: status instanceof errors.Attached,
    value: status instanceof errors.Attached ? read(ref) : null,
  };
}

export function setCaptured(key, property, input) {
  const ref = captured.get(key);
  if (!ref) throw new Error(`No captured native reference ${key}`);
  const encoded = typeof input === "boolean" ? new types.BooleanValue(input) : new types.StringValue(input);
  request(new protocol.PropertySet(ref.anchor, field(ref, property), new Some(encoded)));
}

export function closed() {
  if (!handle || !document) throw new Error("No inspected native session");
  return {
    documentClosed: watershed.diagnostics(document).phase === "failed: runtime closed",
    viewClosed: !(tree.read_root(handle) instanceof Ok),
  };
}

Object.assign(globalThis, { __nativeEval: { inspect, capture, capturedState, setCaptured, closed } });
