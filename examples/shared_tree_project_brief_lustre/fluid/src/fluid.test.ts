import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { test } from "node:test";
import { AzureClient } from "@fluidframework/azure-client";
import type { ISignaler } from "@fluid-experimental/data-objects";
import { ConnectionState, Tree, type IFluidContainer } from "fluid-framework";
import { createIndependentTreeView } from "fluid-framework/beta";
import { BriefSession, containerSchema, openSession } from "./fluid.ts";
import { Review, initial, treeConfiguration } from "./schema.ts";
import { assign } from "./edits.ts";

class FakeSignaler extends EventEmitter implements ISignaler {
  sends = 0;
  submitSignal: ISignaler["submitSignal"] = () => { this.sends++; };
  onSignal: ISignaler["onSignal"] = (name, listener) => { this.on(name, listener); return this; };
  offSignal: ISignaler["offSignal"] = (name, listener) => { this.off(name, listener); return this; };
}

function fixture() {
  const view = createIndependentTreeView(treeConfiguration);
  view.initialize(initial("first", "second"));
  const events = new EventEmitter();
  const signals = new FakeSignaler();
  let disposed = 0;
  const container = Object.assign(events, {
    connectionState: ConnectionState.Connected,
    disposed: false,
    dispose() { disposed++; this.disposed = true; events.emit("disposed"); },
  });
  const session = new BriefSession(
    container as unknown as IFluidContainer, view, signals, "document",
    { name: "Alex", color: "blue", token: 0, selected: null },
  );
  return {
    session, view, container,
    get sends() { return signals.sends; },
    get disposed() { return disposed; },
    peer(token: number) {
      signals.emit("project-brief-selection", "peer", false, {
        name: "Sam", color: "green", token,
        selected: { kind: "fixed", field: "review.reviewer" },
      });
    },
  };
}

test("nested mutations count only tree callbacks; disconnect and close guard all edits", () => {
  const f = fixture();
  const root = f.view.root;
  let notifications = 0;
  const unsubscribe = f.session.subscribe(() => notifications++);
  try {
    const count = f.session.treeChangeCount;
    f.session.edit(() => assign(root, root.owner, "name", "Updated"));
    assert.equal(root.owner.name, "Updated");
    assert.equal(f.session.treeChangeCount, count + 1);
    const afterEdit = f.session.treeChangeCount;
    f.session.select({ kind: "fixed", field: "owner.name" }, root.owner);
    assert.equal(f.session.treeChangeCount, afterEdit);
    f.container.connectionState = ConnectionState.Disconnected;
    f.container.emit("disconnected");
    f.session.edit(() => assign(root, root.owner, "name", "Offline"));
    assert.equal(root.owner.name, "Updated");
    assert.equal(f.session.status, "disconnected");
    assert.equal(f.session.metadata.selected, null);
    assert.match(f.session.errors.join(), /connected/i);
    f.session.close();
    const afterClose = notifications;
    let lateEdits = 0;
    f.container.emit("connected");
    f.session.edit(() => { lateEdits++; });
    f.session.select({ kind: "fixed", field: "title" }, root);
    assert.equal(notifications, afterClose);
    assert.equal(lateEdits, 0);
    assert.equal(f.session.status, "closed");
    assert.equal(f.disposed, 1);
    assert.equal(f.container.listenerCount("connected"), 0);
    assert.equal(f.container.listenerCount("disconnected"), 0);
    f.session.close();
    assert.equal(f.disposed, 1);
  } finally { unsubscribe(); f.session.close(); }
});

test("review identity invalidates selection even when replacement occurs between callbacks", () => {
  const f = fixture();
  try {
    const root = f.view.root;
    root.review = new Review({ reviewer: "Old", approved: false });
    const old = root.review;
    f.session.select({ kind: "fixed", field: "review.reviewer" }, old);
    f.peer(1);
    assert.deepEqual(f.session.peers.map((p) => p.metadata.selected),
      [{ kind: "fixed", field: "review.reviewer" }]);
    Tree.runTransaction(root, () => {
      root.review = undefined;
      root.review = new Review({ reviewer: "Replacement", approved: false });
    });
    assert.equal(f.session.metadata.selected, null);
    assert.equal(f.session.peers[0].metadata.selected, null);
    f.container.connectionState = ConnectionState.Disconnected;
    f.container.emit("disconnected");
    f.container.connectionState = ConnectionState.Connected;
    f.container.emit("connected");
    f.peer(1);
    assert.equal(f.session.peers[0].metadata.selected, null);
    f.peer(2);
    assert.deepEqual(f.session.peers.map((p) => p.metadata.selected),
      [{ kind: "fixed", field: "review.reviewer" }]);
  } finally { f.session.close(); }
});

test("invalid milestone reads disable editing instead of exposing ambiguous rows", () => {
  const f = fixture();
  try {
    const root = f.view.root;
    root.schedule.milestones.insertAtEnd({ id: "first", title: "Duplicate", completed: false });
    assert.equal(f.session.valid, false);
    assert.match(f.session.errors.join(), /duplicate/i);
    f.session.edit(() => { root.title = "Forbidden"; });
    assert.equal(root.title, "Release brief");
    root.schedule.milestones.removeAt(2);
    assert.equal(f.session.valid, true);
    root.schedule.milestones.insertAtEnd({ id: "", title: "Invalid", completed: false });
    assert.equal(f.session.valid, false);
  } finally { f.session.close(); }
});

test("external disposal reports errors only after making the editor inert", () => {
  const f = fixture();
  const states: string[] = [];
  f.session.subscribe(() => states.push(f.session.status));
  f.container.disposed = true;
  f.container.emit("disposed", new Error("Connection closed unexpectedly"));
  assert.deepEqual(states, ["closed"]);
  assert.match(f.session.errors.join(), /unexpectedly/);
  assert.equal(f.container.listenerCount("disposed"), 0);
  assert.equal(f.disposed, 0);
});

test("creation initializes before its single attach and records the returned document URL", async (t) => {
  const view = createIndependentTreeView(treeConfiguration);
  const signals = new FakeSignaler();
  let attaches = 0;
  let disposed = 0;
  const container = Object.assign(new EventEmitter(), {
    connectionState: ConnectionState.Connected,
    disposed: false,
    initialObjects: {
      brief: { viewWith: () => view },
      selection: signals,
    },
    async attach() {
      attaches++;
      assert.equal(view.root.title, "Release brief");
      assert.notEqual(view.root.schedule.milestones[0].id, view.root.schedule.milestones[1].id);
      return "new-document";
    },
    dispose() { this.disposed = true; disposed++; },
  });
  t.mock.method(AzureClient.prototype, "createContainer", async (schema: unknown, mode: unknown) => {
    assert.equal(schema, containerSchema);
    assert.equal(mode, "2.0.0");
    return { container };
  });
  const oldHistory = Object.getOwnPropertyDescriptor(globalThis, "history");
  const urls: string[] = [];
  Object.defineProperty(globalThis, "history", {
    configurable: true, value: { replaceState(_data: unknown, _unused: string, url: URL) {
      urls.push(String(url));
    } },
  });
  t.after(() => {
    if (oldHistory) Object.defineProperty(globalThis, "history", oldHistory);
    else Reflect.deleteProperty(globalThis, "history");
  });
  const session = await openSession(new URL("http://127.0.0.1:8081/?name=Sam"), new AbortController().signal);
  try {
    assert.equal(session.documentId, "new-document");
    assert.equal(session.metadata.name, "Sam");
    assert.equal(attaches, 1);
    assert.deepEqual(urls, ["http://127.0.0.1:8081/?name=Sam&document=new-document"]);
  } finally { session.close(); }
  assert.equal(disposed, 1);
});

test("loading retains existing content and never initializes or attaches", async (t) => {
  const loadedView = createIndependentTreeView(treeConfiguration);
  loadedView.initialize({
    ...initial("loaded-first", "loaded-second"), title: "Existing document",
  });
  const container = Object.assign(new EventEmitter(), {
    connectionState: ConnectionState.Connected,
    disposed: false,
    initialObjects: { brief: { viewWith: () => loadedView }, selection: new FakeSignaler() },
    attach() { throw new Error("Loaded documents must not attach"); },
    dispose() { this.disposed = true; },
  });
  t.mock.method(AzureClient.prototype, "getContainer", async (id: unknown, schema: unknown, mode: unknown) => {
    assert.equal(id, "existing");
    assert.equal(schema, containerSchema);
    assert.equal(mode, "2.0.0");
    return { container };
  });
  const session = await openSession(new URL("http://127.0.0.1:8081/?document=existing"),
    new AbortController().signal);
  try {
    assert.equal(session.root.title, "Existing document");
    assert.equal(session.root.schedule.milestones[0].id, "loaded-first");
  } finally { session.close(); }
});

test("a creation result arriving after close is disposed without attaching", async (t) => {
  const controller = new AbortController();
  let disposed = 0;
  let attaches = 0;
  const container = {
    disposed: false,
    dispose() { this.disposed = true; disposed++; },
    async attach() { attaches++; return "must-not-attach"; },
  };
  t.mock.method(AzureClient.prototype, "createContainer", async () => {
    controller.abort();
    return { container };
  });
  await assert.rejects(openSession(new URL("http://127.0.0.1:8081/"), controller.signal),
    { name: "AbortError" });
  assert.equal(disposed, 1);
  assert.equal(attaches, 0);
});
