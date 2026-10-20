import type { Action, Config, Session, State } from "../../fluid/src/domain.ts";

export async function start(_config: Config): Promise<Session> {
  let state: State = {
    phase: "ready", documentId: null, errors: [],
    board: { incidents: [
      { id: "incident-a", title: "First", status: "open", assignee: "Alex", steps: [
        { id: "step-a", label: "One", done: false },
        { id: "step-b", label: "Two", done: false },
      ] },
      { id: "incident-b", title: "Second", status: "open", steps: [] },
    ] },
  };
  if (new URL(location.href).searchParams.has("empty")) state.board.incidents = [];
  const listeners = new Set<() => void>();
  const actions: Action[] = [];
  Object.assign(globalThis, { __actions: actions });
  return {
    read: () => state,
    apply: action => {
      actions.push(action);
      if (action.type === "add-incident") {
        state = { ...state, board: { incidents: [
          ...state.board.incidents,
          { id: action.id, title: action.title, status: "open", steps: [] },
        ] } };
      } else if (action.type === "title") {
        state = { ...state, board: { incidents: state.board.incidents.map(incident =>
          incident.id === action.id ? { ...incident, title: action.value } : incident) } };
        if (new URL(location.href).searchParams.has("fail-edit")) state.errors = ["Service rejected the edit"];
      }
      for (const listener of listeners) listener();
    },
    subscribe: listener => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    close: () => {
      state = { ...state, phase: "closed" };
      for (const listener of listeners) listener();
    },
  };
}
