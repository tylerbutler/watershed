import { useEffect, useRef, useState } from "react";
import type { Action, Board, Config, Session, State } from "./domain.ts";
import { start } from "./model.ts";

const initial: State = {
  phase: "opening", documentId: null, board: { incidents: [] }, errors: [],
};

function TransferControls({ board, incident, id, disabled, apply }: {
  board: Board; incident: string; id: string; disabled: boolean; apply: (action: Action) => void;
}) {
  const [destination, setDestination] = useState("");
  const [before, setBefore] = useState("");
  const target = board.incidents.find(value => value.id === destination);
  return <>
    <label>Transfer destination<select data-field="transfer-destination" disabled={disabled}
      value={destination} onChange={event => { setDestination(event.target.value); setBefore(""); }}>
      <option value="">Choose incident</option>
      {board.incidents.map(value => <option key={value.id} value={value.id}>{value.title || value.id}</option>)}
    </select></label>
    <label>Transfer before<select data-field="transfer-before" disabled={disabled || !target}
      value={before} onChange={event => setBefore(event.target.value)}>
      <option value="">Append</option>
      {target?.steps.map(step => <option key={step.id} value={step.id}>{step.label || step.id}</option>)}
    </select></label>
    <button type="button" data-action="transfer-step" disabled={disabled || !target}
      onClick={() => apply({ type: "transfer-step", incident, id, destination, before: before || null })}>
      Transfer step
    </button>
  </>;
}

export function App({ config }: { config: Config }) {
  const [state, setState] = useState(initial);
  const [session, setSession] = useState<Session>();
  const [issues, setIssues] = useState<string[]>([]);
  const closing = useRef(false);
  const latestNative = useRef<Session | undefined>(undefined);
  const report = (error: unknown) =>
    setIssues(values => [...values, error instanceof Error ? error.message : String(error)]);

  useEffect(() => {
    closing.current = false;
    latestNative.current = undefined;
    let active = true;
    let current: Session | undefined;
    let unsubscribe: (() => void) | undefined;
    start(config).then(opened => {
      current = opened;
      if (!active) { opened.close(); return; }
      latestNative.current = opened;
      if (closing.current) { opened.close(); return; }
      const read = () => { if (active && !closing.current) setState(opened.read()); };
      unsubscribe = opened.subscribe(read);
      setSession(opened);
      read();
    }).catch(error => {
      if (active) {
        if (!closing.current) setState(value => ({ ...value, phase: "error" }));
        report(error);
      }
    });
    return () => { active = false; unsubscribe?.(); current?.close(); };
  }, [config]);

  useEffect(() => {
    if (state.documentId) {
      const url = new URL(location.href);
      url.searchParams.set("document", state.documentId);
      history.replaceState(null, "", url);
    }
  }, [state.documentId]);

  const disabled = state.phase !== "ready";
  const apply = (action: Action) => {
    if (disabled || !session) return;
    try { session.apply(action); } catch (error) { report(error); }
  };
  const close = () => {
    if (state.phase === "closed") return;
    closing.current = true;
    if (!session) { setState(value => ({ ...value, phase: "closed" })); return; }
    try { session.close(); setState(session.read()); } catch (error) { report(error); }
  };
  useEffect(() => {
    const adapter = {
      snapshot: () => structuredClone(state),
      apply,
      close,
      native: () => latestNative.current,
    };
    Object.assign(globalThis, { __incidentEval: adapter });
    return () => {
      if (Reflect.get(globalThis, "__incidentEval") === adapter) {
        Reflect.deleteProperty(globalThis, "__incidentEval");
      }
    };
  }, [state, session]);
  const button = (action: string, text: string, perform: () => void, inert = disabled) =>
    <button type="button" data-action={action} disabled={inert} onClick={perform}>{text}</button>;

  return <>
    <h1>Incident response board</h1>
    <p data-state={state.phase} role="status">{state.phase}</p>
    {[...state.errors, ...issues].map((error, index) => <p role="alert" key={index}>{error}</p>)}
    {button("add-incident", "Add incident", () => apply({
      type: "add-incident", id: crypto.randomUUID(), title: "",
    }))}
    {state.board.incidents.length === 0 && <p data-empty="incidents">No incidents</p>}
    {state.board.incidents.map((incident, index, incidents) =>
      <section key={incident.id} data-incident-id={incident.id}>
        <label>Title<input data-field="title" disabled={disabled} value={incident.title}
          onChange={event => apply({ type: "title", id: incident.id, value: event.target.value })} /></label>
        <label>Status<select data-field="status" disabled={disabled} value={incident.status}
          onChange={event => {
            const value = event.target.value;
            if (value === "open" || value === "investigating" || value === "resolved") {
              apply({ type: "status", id: incident.id, value });
            } else {
              report(new Error("Invalid status"));
            }
          }}>
          <option value="open">Open</option>
          <option value="investigating">Investigating</option>
          <option value="resolved">Resolved</option>
        </select></label>
        <label>Assignee<input data-field="assignee" disabled={disabled} value={incident.assignee ?? ""}
          onChange={event => apply({ type: "assignee", id: incident.id, value: event.target.value })} /></label>
        <span data-assignee-present={incident.assignee !== undefined}>
          {incident.assignee === undefined ? "Unassigned" : "Assigned"}
        </span>
        {button("assignee-remove", "Remove assignee", () => apply({
          type: "assignee", id: incident.id, value: null,
        }))}
        {button("incident-up", "Move incident up", () => apply({
          type: "move-incident", id: incident.id, before: incidents[index - 1]?.id ?? null,
        }), disabled || index === 0)}
        {button("incident-down", "Move incident down", () => apply({
          type: "move-incident", id: incident.id, before: incidents[index + 2]?.id ?? null,
        }), disabled || index === incidents.length - 1)}
        {button("remove-incident", "Delete incident", () => apply({ type: "remove-incident", id: incident.id }))}
        {button("add-step", "Add step", () => apply({
          type: "add-step", incident: incident.id, id: crypto.randomUUID(), label: "",
        }))}
        {incident.steps.map((step, stepIndex, steps) =>
          <div key={step.id} data-step-id={step.id}>
            <label>Step<input data-field="step-label" disabled={disabled} value={step.label}
              onChange={event => apply({
                type: "step-label", incident: incident.id, id: step.id, value: event.target.value,
              })} /></label>
            <label>Complete<input type="checkbox" data-field="step-done" disabled={disabled} checked={step.done}
              onChange={event => apply({
                type: "step-done", incident: incident.id, id: step.id, value: event.target.checked,
              })} /></label>
            {button("step-up", "Move step up", () => apply({
              type: "move-step", incident: incident.id, id: step.id, before: steps[stepIndex - 1]?.id ?? null,
            }), disabled || stepIndex === 0)}
            {button("step-down", "Move step down", () => apply({
              type: "move-step", incident: incident.id, id: step.id, before: steps[stepIndex + 2]?.id ?? null,
            }), disabled || stepIndex === steps.length - 1)}
            {button("remove-step", "Delete step", () => apply({
              type: "remove-step", incident: incident.id, id: step.id,
            }))}
            <TransferControls board={state.board} incident={incident.id} id={step.id}
              disabled={disabled} apply={apply} />
          </div>)}
      </section>)}
    {button("close", "Close", close, state.phase === "closed")}
  </>;
}
