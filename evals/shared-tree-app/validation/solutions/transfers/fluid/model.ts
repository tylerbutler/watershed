import { AzureClient } from "@fluidframework/azure-client";
import { InsecureTokenProvider } from "@fluidframework/test-runtime-utils/internal";
import {
  ConnectionState, SharedTree, Tree, type IFluidContainer, type TreeView,
} from "fluid-framework";
import type { Action, Board, Config, Session, State, Status } from "./domain.ts";
import { BoardNode, configuration, IncidentNode } from "./schema.ts";
// mutation:start imports
// mutation:end imports

const containerSchema = { initialObjects: { board: SharedTree } };
const message = (error: unknown) => error instanceof Error ? error.message : String(error);

interface NativeArray<T extends { readonly id: string }> extends Iterable<T> {
  readonly length: number;
  moveToEnd(index: number): void;
  moveToIndex(destination: number, source: number): void;
  removeAt(index: number): void;
}

function move<T extends { readonly id: string }>(array: NativeArray<T>, id: string, before: string | null) {
  const values = [...array];
  const source = values.findIndex(node => node.id === id);
  if (source < 0) return;
  if (before === null) { array.moveToEnd(source); return; }
  const destination = values.findIndex(node => node.id === before);
  if (destination < 0) throw new Error("Destination is not a sibling");
  if (source !== destination) array.moveToIndex(destination, source);
}

class BoardSession implements Session {
  readonly container: IFluidContainer;
  readonly view: TreeView<typeof BoardNode>;
  private closed = false;
  private errors: string[] = [];
  private board: Board = { incidents: [] };
  private readonly listeners = new Set<() => void>();
  private readonly cleanup: (() => void)[] = [];
  // mutation:start root
  private get root() { return this.view.root; }
  // mutation:end root

  // mutation:start constructor
  constructor(container: IFluidContainer, view: TreeView<typeof BoardNode>, readonly documentId: string) {
  // mutation:end constructor
    this.container = container;
    this.view = view;
    const changed = () => { if (!this.closed) this.emit(); };
    const disconnected = () => {
      if (this.closed) return;
      this.errors.push("Service connection is unavailable");
      this.emit();
    };
    const disposed = (error?: unknown) => {
      if (this.closed) return;
      this.errors.push(error ? message(error) : "Service container was disposed");
      this.emit();
    };
    // mutation:start observation
    this.cleanup.push(Tree.on(view.root, "treeChanged", changed));
    this.cleanup.push(view.events.on("rootChanged", changed));
    // mutation:end observation
    container.on("connected", changed);
    container.on("disconnected", disconnected);
    container.on("disposed", disposed);
    this.cleanup.push(() => {
      container.off("connected", changed);
      container.off("disconnected", disconnected);
      container.off("disposed", disposed);
    });
    this.read();
  }

  private emit() {
    for (const listener of this.listeners) listener();
  }

  read(): State {
    let phase: State["phase"] = this.closed ? "closed"
      : this.container.disposed ? "error"
      : this.container.connectionState === ConnectionState.Connected ? "ready" : "disconnected";
    if (!this.closed && !this.container.disposed) {
      try {
        if (!this.view.compatibility.canView) throw new Error("Incompatible board schema");
        // mutation:start read
        // mutation:end read
        const ids = new Set<string>();
        const id = (value: string) => {
          if (!value || ids.has(value)) throw new Error("ID must be nonempty and unique");
          ids.add(value);
          return value;
        };
        this.board = { incidents: [...this.root.incidents].map(incident => {
          const status = incident.status;
          if (status !== "open" && status !== "investigating" && status !== "resolved") {
            throw new Error("Invalid status");
          }
          return {
            id: id(incident.id), title: incident.title, status,
            ...(incident.assignee === undefined ? {} : { assignee: incident.assignee }),
            steps: [...incident.steps].map(step => ({
              id: id(step.id), label: step.label, done: step.done,
            })),
          };
        }) };
      } catch (error) {
        phase = "error";
        const detail = message(error);
        if (this.errors.at(-1) !== detail) this.errors.push(detail);
      }
    }
    return { phase, documentId: this.documentId, board: this.board, errors: [...this.errors] };
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  private unique(id: string) {
    if (typeof id !== "string" || !id) throw new Error("ID must be nonempty and unique");
    for (const incident of this.root.incidents) {
      if (incident.id === id || [...incident.steps].some(step => step.id === id)) {
        throw new Error("ID must be nonempty and unique");
      }
    }
  }

  private incident(id: string): IncidentNode | undefined {
    // mutation:start lookup
    return [...this.root.incidents].find(node => node.id === id);
    // mutation:end lookup
  }

  // mutation:start apply
  apply(action: Action) {
  // mutation:end apply
    if (this.closed) return;
    if (this.read().phase !== "ready") throw new Error("Edits require a ready document");
    if (action.type === "add-incident") {
      this.unique(action.id);
      this.root.incidents.insertAtEnd({
        id: action.id, title: action.title, status: "open", steps: [],
      });
      return;
    }
    // mutation:start target
    const incident = this.incident("incident" in action ? action.incident : action.id);
    // mutation:end target
    if (!incident) return;
    switch (action.type) {
      // mutation:start title
      case "title": incident.title = action.value; break;
      // mutation:end title
      case "status":
        if (!(["open", "investigating", "resolved"] satisfies Status[]).includes(action.value)) {
          throw new Error("Invalid status");
        }
        incident.status = action.value;
        break;
      case "assignee": incident.assignee = action.value === null ? undefined : action.value; break;
      case "remove-incident":
        this.root.incidents.removeAt([...this.root.incidents].indexOf(incident));
        break;
      case "move-incident": move(this.root.incidents, incident.id, action.before); break;
      case "add-step":
        this.unique(action.id);
        incident.steps.insertAtEnd({ id: action.id, label: action.label, done: false });
        break;
      default: {
        const step = [...incident.steps].find(node => node.id === action.id);
        if (!step) return;
        switch (action.type) {
          case "step-label": step.label = action.value; break;
          case "step-done": step.done = action.value; break;
          case "remove-step": incident.steps.removeAt([...incident.steps].indexOf(step)); break;
          case "move-step": move(incident.steps, step.id, action.before); break;
          case "transfer-step": {
            // mutation:start transfer-target
            const destination = this.incident(action.destination);
            if (!action.destination || !destination) throw new Error("Destination incident does not exist");
            // mutation:end transfer-target
            if (destination === incident) {
              move(incident.steps, step.id, action.before);
              break;
            }
            // mutation:start transfer-lookup
            const sourceIndex = [...incident.steps].indexOf(step);
            // mutation:end transfer-lookup
            // mutation:start transfer-move
            if (action.before === null) {
              destination.steps.moveToEnd(sourceIndex, incident.steps);
            } else {
              const gap = [...destination.steps].findIndex(node => node.id === action.before);
              if (gap < 0) throw new Error("Destination is not a sibling");
              destination.steps.moveToIndex(gap, sourceIndex, incident.steps);
            }
            // mutation:end transfer-move
            break;
          }
        }
      }
    }
  }

  close() {
    if (this.closed) return;
    this.read();
    this.closed = true;
    // mutation:start cleanup
    for (const stop of this.cleanup.splice(0)) {
      try { stop(); } catch (error) { this.errors.push(`Unsubscribe failed: ${message(error)}`); }
    }
    try { this.view.dispose(); } catch (error) { this.errors.push(`View close failed: ${message(error)}`); }
    try { if (!this.container.disposed) this.container.dispose(); }
    catch (error) { this.errors.push(`Container close failed: ${message(error)}`); }
    // mutation:end cleanup
    this.emit();
    this.listeners.clear();
  }
}

export async function start(config: Config): Promise<Session> {
  const client = new AzureClient({ connection: {
    type: "local", endpoint: config.endpoint,
    tokenProvider: new InsecureTokenProvider("local-development-only", { id: config.clientId, name: "Incident editor" }),
  } });
  const documentId = config.documentId;
  const creating = documentId === null;
  const { container } = creating
    ? await client.createContainer(containerSchema, "2.0.0")
    : await client.getContainer(documentId, containerSchema, "2.0.0");
  let view: TreeView<typeof BoardNode> | undefined;
  try {
    view = container.initialObjects.board.viewWith(configuration);
    if (creating) view.initialize(new BoardNode({ incidents: [] }));
    // mutation:start open
    // mutation:end open
    const id = creating ? await container.attach() : documentId;
    if (!view.compatibility.canView) throw new Error("Incompatible board schema");
    // mutation:start session
    return new BoardSession(container, view, id);
    // mutation:end session
  } catch (error) {
    try { view?.dispose(); } finally { if (!container.disposed) container.dispose(); }
    throw error;
  }
}

export function nativeView(session: Session): TreeView<typeof BoardNode> {
  if (!(session instanceof BoardSession)) throw new Error("Unknown native session");
  return session.view;
}

export function nativeContainer(session: Session): IFluidContainer {
  if (!(session instanceof BoardSession)) throw new Error("Unknown native session");
  return session.container;
}
