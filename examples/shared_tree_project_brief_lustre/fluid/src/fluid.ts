import { Signaler, type ISignaler } from "@fluid-experimental/data-objects";
import { AzureClient } from "@fluidframework/azure-client";
import { InsecureTokenProvider } from "@fluidframework/test-runtime-utils/internal";
import {
  ConnectionState, SharedTree, Tree,
  type ContainerSchema, type IFluidContainer, type TreeView,
} from "fluid-framework";
import { current, target, type EditableNode } from "./edits.ts";
import { ProjectBrief, initial, treeConfiguration, validateUniqueIds } from "./schema.ts";
import {
  decode, focus, initialPolicy, reconcile, reconcileLocal, startPresence,
  type Field, type Peer, type PresenceSession, type SelectionMetadata,
} from "./selection.ts";

export const containerSchema = {
  initialObjects: { brief: SharedTree, selection: Signaler },
} satisfies ContainerSchema;

export function validateBrief(brief: ProjectBrief): void {
  validateUniqueIds(brief.schedule.milestones);
  for (const item of brief.schedule.milestones) {
    if (!item.id || item.id.includes("/")) throw new Error("Invalid milestone ID");
  }
}

export class BriefSession {
  readonly root: ProjectBrief;
  readonly documentId: string;
  readonly sessionId: string;
  metadata: SelectionMetadata;
  treeChangeCount = 0;
  revision = 0;
  valid = true;
  errors: string[] = [];
  closed = false;
  private readonly container: IFluidContainer;
  private readonly view: TreeView<typeof ProjectBrief>;
  private policy = initialPolicy();
  private roster: Peer[] = [];
  private captures = new Map<string, { token: number; node: EditableNode | undefined }>();
  private localTarget: EditableNode | undefined;
  private presence: PresenceSession | undefined;
  private readonly listeners = new Set<() => void>();
  private readonly cleanup: (() => void)[] = [];

  constructor(
    container: IFluidContainer, view: TreeView<typeof ProjectBrief>, signaler: ISignaler,
    documentId: string, metadata: SelectionMetadata, sessionId = crypto.randomUUID(),
  ) {
    if (!view.compatibility.canView) throw new Error("Incompatible brief schema; no automatic upgrade");
    this.container = container;
    this.view = view;
    this.root = view.root;
    this.documentId = documentId;
    this.sessionId = sessionId;
    this.metadata = decode(metadata);
    const changed = () => {
      if (this.closed) return;
      this.treeChangeCount++;
      this.read();
      this.emit();
    };
    this.cleanup.push(Tree.on(this.root, "treeChanged", changed));
    this.cleanup.push(view.events.on("rootChanged", () => {
      if (this.closed) return;
      this.read();
      this.emit();
    }));
    const connected = () => {
      if (this.closed) return;
      this.read();
      this.emit();
    };
    const disconnected = () => {
      if (this.closed) return;
      this.clearSelection();
      this.roster = [];
      this.reconcileSelections();
      this.emit();
    };
    const disposed = (error?: unknown) => {
      if (this.closed) return;
      if (error) this.errors.push(error instanceof Error ? error.message : String(error));
      this.close();
    };
    container.on("connected", connected);
    container.on("disconnected", disconnected);
    container.on("disposed", disposed);
    this.cleanup.push(() => {
      container.off("connected", connected);
      container.off("disconnected", disconnected);
      container.off("disposed", disposed);
    });
    this.read();
    this.presence = startPresence(signaler, container, this.metadata, (peers) => {
      if (this.closed) return;
      this.roster = peers;
      if (this.valid) this.reconcileSelections();
      this.emit();
    }, (error) => this.report(error));
  }

  get status(): string {
    if (this.closed) return "closed";
    if (!this.valid) return "error";
    return this.container.connectionState === ConnectionState.Connected ? "ready" : "disconnected";
  }
  get editable(): boolean { return this.status === "ready"; }
  get peers(): Peer[] { return this.policy.peers; }
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };
  snapshot = (): number => this.revision;
  private emit(): void {
    this.revision++;
    for (const listener of this.listeners) listener();
  }
  report(error: unknown): void {
    if (this.closed) return;
    this.errors.push(error instanceof Error ? error.message : String(error));
    this.emit();
  }

  private clearSelection(): void {
    this.metadata = focus(this.metadata, null);
    this.localTarget = undefined;
    this.presence?.update(this.metadata);
  }

  private read(): void {
    try {
      if (!this.view.compatibility.canView || this.view.root !== this.root) {
        throw new Error("Brief root or schema changed; reopen this document");
      }
      validateBrief(this.root);
      this.valid = true;
      this.reconcileSelections();
    } catch (error) {
      this.valid = false;
      this.clearSelection();
      this.policy = { ...this.policy, peers: [] };
      // Keep watermarks: invalid content must not revive stale field selections.
      for (const [id, metadata] of this.policy.latest) {
        this.policy.invalid.set(id, metadata.token);
      }
      this.report(error);
    }
  }

  private reconcileSelections(): void {
    if (!this.valid) return;
    if (this.metadata.selected && (!this.localTarget ||
        !current(this.root, this.localTarget) ||
        target(this.root, this.metadata.selected) !== this.localTarget)) {
      this.clearSelection();
    }
    const next = reconcileLocal(this.metadata, this.root);
    if (next !== this.metadata) {
      this.metadata = next;
      this.localTarget = undefined;
      this.presence?.update(next);
    }
    // Availability alone misses remove/recreate inside one observed transaction.
    for (const [id, captured] of this.captures) {
      const metadata = this.policy.latest.get(id);
      if (metadata?.selected && metadata.token === captured.token &&
          (!captured.node || !current(this.root, captured.node) ||
          target(this.root, metadata.selected) !== captured.node)) {
        this.policy.invalid.set(id, metadata.token);
      }
    }
    this.policy = reconcile(this.policy, this.roster, this.root);
    for (const [id, metadata] of this.policy.latest) {
      if (this.captures.get(id)?.token !== metadata.token) {
        this.captures.set(id, {
          token: metadata.token,
          node: metadata.selected ? target(this.root, metadata.selected) : undefined,
        });
      }
    }
  }

  select(field: Field | null, node?: EditableNode): void {
    if (this.closed) return;
    if (field && (!this.editable || !node || !current(this.root, node) ||
        target(this.root, field) !== node)) {
      this.report(new Error("Selection target is unavailable"));
      return;
    }
    this.metadata = focus(this.metadata, field);
    this.localTarget = field ? node : undefined;
    this.presence?.update(this.metadata);
    this.emit();
  }

  edit(action: () => void): void {
    if (this.closed) return;
    if (!this.editable) {
      this.report(new Error("Edits require a connected, valid document"));
      return;
    }
    try { action(); } catch (error) { this.report(error); }
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.clearSelection();
    this.presence?.stop();
    for (const stop of this.cleanup.splice(0)) stop();
    this.policy = { ...this.policy, peers: [] };
    this.view.dispose();
    if (!this.container.disposed) this.container.dispose();
    this.emit();
  }
}

/** Called once by the entry point, never by a React mount effect. */
export async function openSession(url: URL, signal: AbortSignal): Promise<BriefSession> {
  const name = Array.from(url.searchParams.get("name") || "Alex").slice(0, 80).join("");
  const sessionId = crypto.randomUUID();
  const client = new AzureClient({
    connection: {
      type: "local", endpoint: "http://localhost:7070",
      tokenProvider: new InsecureTokenProvider("fooBar", { id: sessionId, name }),
    },
  });
  let documentId = url.searchParams.get("document") || "";
  const creating = documentId === "";
  const { container } = creating
    ? await client.createContainer(containerSchema, "2.0.0")
    : await client.getContainer(documentId, containerSchema, "2.0.0");
  let view: TreeView<typeof ProjectBrief> | undefined;
  const abort = () => { if (!container.disposed) container.dispose(); };
  signal.addEventListener("abort", abort, { once: true });
  try {
    signal.throwIfAborted();
    view = container.initialObjects.brief.viewWith(treeConfiguration);
    if (creating) {
      const data = initial(crypto.randomUUID(), crypto.randomUUID());
      validateUniqueIds(data.schedule.milestones);
      view.initialize(data);
      validateBrief(view.root);
      // An uncertain attach is never retried. The URL changes only on success.
      documentId = await container.attach();
      signal.throwIfAborted();
      url.searchParams.set("document", documentId);
      history.replaceState(null, "", url);
    }
    signal.throwIfAborted();
    return new BriefSession(container, view, container.initialObjects.selection, documentId,
      { name, color: "blue", token: 0, selected: null }, sessionId);
  } catch (error) {
    view?.dispose();
    abort();
    throw error;
  } finally { signal.removeEventListener("abort", abort); }
}
