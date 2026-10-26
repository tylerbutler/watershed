import * as domain from "./incident_eval/domain.mjs";
import { None, Some } from "../gleam_stdlib/gleam/option.mjs";

let currentModel;
let currentState;

function snapshot() {
  return {
    phase: domain.phase_name(currentState.phase),
    documentId: currentState.document_id instanceof Some ? currentState.document_id[0] : null,
    errors: [...currentState.errors],
    board: { incidents: [...currentState.board.incidents].map(incident => ({
      id: incident.id, title: incident.title, status: domain.status_name(incident.status),
      ...(incident.assignee instanceof Some ? { assignee: incident.assignee[0] } : {}),
      steps: [...incident.steps].map(step => ({ id: step.id, label: step.label, done: step.done })),
    })) },
  };
}

function action(value) {
  const optional = value => value == null ? new None() : new Some(value);
  switch (value.type) {
    case "add-incident": return new domain.AddIncident(value.id, value.title);
    case "title": return new domain.Title(value.id, value.value);
    case "status": {
      const statuses = { open: domain.Open, investigating: domain.Investigating, resolved: domain.Resolved };
      if (!Object.hasOwn(statuses, value.value)) throw new Error("Invalid status");
      return new domain.Status(value.id, new statuses[value.value]());
    }
    case "assignee": return new domain.Assignee(value.id, optional(value.value));
    case "remove-incident": return new domain.RemoveIncident(value.id);
    case "move-incident": return new domain.MoveIncident(value.id, optional(value.before));
    case "add-step": return new domain.AddStep(value.incident, value.id, value.label);
    case "step-label": return new domain.StepLabel(value.incident, value.id, value.value);
    case "step-done": return new domain.StepDone(value.incident, value.id, value.value);
    case "remove-step": return new domain.RemoveStep(value.incident, value.id);
    case "move-step": return new domain.MoveStep(value.incident, value.id, optional(value.before));
    case "transfer-step": return new domain.TransferStep(value.incident, value.id, value.destination, optional(value.before));
    default: throw new Error(`Unknown action: ${value.type}`);
  }
}

export function publish(model, state) {
  currentModel = model;
  currentState = state;
}

export function install(model, state, apply, close, report) {
  publish(model, state);
  globalThis.__incidentEval = {
    snapshot,
    apply(value) {
      if (domain.phase_name(currentState.phase) !== "ready") return;
      try { apply(action(value)); } catch (error) { report(error.message); }
    },
    close,
    native: () => currentModel,
  };
}

export function query(name, fallback) {
  return new URL(location.href).searchParams.get(name) ?? fallback;
}

export function origin() {
  return location.origin;
}

export function uuid() {
  return crypto.randomUUID();
}

export function replaceDocument(documentId) {
  const url = new URL(location.href);
  url.searchParams.set("document", documentId);
  history.replaceState(null, "", url);
}
