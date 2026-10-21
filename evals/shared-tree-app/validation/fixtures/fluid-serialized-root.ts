import { AzureClient } from "@fluidframework/azure-client";
import { InsecureTokenProvider } from "@fluidframework/test-runtime-utils/internal";
import { ConnectionState, Tree, type IFluidContainer, type TreeView, SharedTree } from "fluid-framework";
import { BoardNode, configuration } from "./schema.ts";
import type { Action, Board, Config, Session, State } from "./domain.ts";

class SerializedSession implements Session {
  private closed = false;
  private readonly listeners = new Set<() => void>();
  private readonly stop: () => void;
  private readonly changed = () => {
    for (const listener of this.listeners) listener();
  };
  constructor(readonly container: IFluidContainer, readonly view: TreeView<typeof BoardNode>,
    readonly documentId: string) {
    this.stop = Tree.on(view.root, "treeChanged", this.changed);
    container.on("connected", this.changed);
    container.on("disconnected", this.changed);
  }
  read(): State {
    return { phase: this.closed ? "closed"
      : this.container.connectionState === ConnectionState.Connected ? "ready" : "disconnected",
    documentId: this.documentId, board: JSON.parse(this.view.root.serialized) as Board, errors: [] };
  }
  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }
  apply(action: Action) {
    if (this.closed) return;
    const board = this.read().board;
    const move = <T extends { id: string }>(items: T[], id: string, before: string | null) => {
      const index = items.findIndex(item => item.id === id);
      if (index < 0 || id === before) return;
      const [item] = items.splice(index, 1);
      const destination = before === null ? items.length : items.findIndex(item => item.id === before);
      if (destination < 0) throw new Error("Destination is not a sibling");
      items.splice(destination, 0, item);
    };
    if (action.type === "add-incident") {
      board.incidents.push({ id: action.id, title: action.title, status: "open", steps: [] });
    } else {
      const incident = board.incidents.find(node =>
        node.id === ("incident" in action ? action.incident : action.id));
      if (!incident) return;
      switch (action.type) {
        case "title": incident.title = action.value; break;
        case "status": incident.status = action.value; break;
        case "assignee":
          if (action.value === null) delete incident.assignee;
          else incident.assignee = action.value;
          break;
        case "remove-incident": board.incidents.splice(board.incidents.indexOf(incident), 1); break;
        case "move-incident": move(board.incidents, action.id, action.before); break;
        case "add-step": incident.steps.push({ id: action.id, label: action.label, done: false }); break;
        default: {
          const step = incident.steps.find(node => node.id === action.id);
          if (!step) return;
          switch (action.type) {
            case "step-label": step.label = action.value; break;
            case "step-done": step.done = action.value; break;
            case "remove-step": incident.steps.splice(incident.steps.indexOf(step), 1); break;
            case "move-step": move(incident.steps, action.id, action.before); break;
          }
        }
      }
    }
    this.view.root.serialized = JSON.stringify(board);
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    this.stop();
    this.container.off("connected", this.changed);
    this.container.off("disconnected", this.changed);
    this.view.dispose();
    this.container.dispose();
    this.listeners.clear();
  }
}

export async function start(config: Config): Promise<Session> {
  const client = new AzureClient({ connection: { type: "local", endpoint: config.endpoint,
    tokenProvider: new InsecureTokenProvider("local-development-only", {
      id: config.clientId, name: "Incident editor",
    }) } });
  const schema = { initialObjects: { board: SharedTree } };
  const creating = config.documentId === null;
  const { container } = creating ? await client.createContainer(schema, "2.0.0")
    : await client.getContainer(config.documentId!, schema, "2.0.0");
  const view = container.initialObjects.board.viewWith(configuration);
  if (creating) view.initialize(new BoardNode({ serialized: '{"incidents":[]}' }));
  const id = creating ? await container.attach() : config.documentId!;
  return new SerializedSession(container, view, id);
}

export function nativeView(session: Session) { return (session as SerializedSession).view; }
export function nativeContainer(session: Session) { return (session as SerializedSession).container; }
