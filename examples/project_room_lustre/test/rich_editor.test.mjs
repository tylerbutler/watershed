import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";

let element;
let initialLoadError;
let instances;

class FakeQuill {
  constructor(target, options) {
    this.target = target;
    this.options = options;
    this.handlers = new Map();
    this.calls = {
      off: [],
      setContents: [],
      updateContents: [],
    };
    instances.push(this);
  }

  on(name, handler) {
    this.handlers.set(name, handler);
  }

  off(name, handler) {
    this.calls.off.push([name, handler]);
    if (this.handlers.get(name) === handler) this.handlers.delete(name);
  }

  setContents(delta, source) {
    this.calls.setContents.push([delta, source]);
    if (initialLoadError !== null) throw initialLoadError;
  }

  updateContents(delta, source) {
    this.calls.updateContents.push([delta, source]);
    this.handlers.get("text-change")?.(delta, {}, source);
  }

  emit(delta, source) {
    this.handlers.get("text-change")?.(delta, {}, source);
  }
}

beforeEach(() => {
  element = { id: "editor" };
  initialLoadError = null;
  instances = [];
  globalThis.document = {
    getElementById(id) {
      return id === element.id ? element : null;
    },
  };
  globalThis.__projectRoomQuillConstructor = FakeQuill;
});

afterEach(() => {
  delete globalThis.document;
  delete globalThis.__projectRoomQuillConstructor;
});

async function bridge() {
  return import("../src/project_room_lustre/rich_editor_ffi.mjs");
}

function mountEditor(mount, initialDocument, onUserDelta, onError) {
  return new Promise((resolve) => {
    mount("editor", initialDocument, onUserDelta, resolve, onError);
  });
}

test("mount configures user-only history and loads the initial document silently", async () => {
  const { mount } = await bridge();
  const errors = [];

  await mountEditor(
    mount,
    JSON.stringify([{ insert: "Initial\n" }]),
    () => {},
    (error) => errors.push(error),
  );

  assert.equal(errors.length, 0);
  assert.equal(instances.length, 1);
  assert.equal(instances[0].target, element);
  assert.equal(instances[0].options.theme, undefined);
  assert.equal(instances[0].options.modules.history.userOnly, true);
  assert.deepEqual(instances[0].calls.setContents, [
    [[{ insert: "Initial\n" }], "silent"],
  ]);
});

test("mount serializes only user delta operation arrays", async () => {
  const { mount } = await bridge();
  const changes = [];
  await mountEditor(mount, "[]", (change) => changes.push(change), () => {});

  instances[0].emit({ ops: [{ insert: "😀" }] }, "user");
  instances[0].emit({ ops: [{ insert: "api" }] }, "api");
  instances[0].emit({ ops: [{ insert: "silent" }] }, "silent");
  await Promise.resolve();

  assert.deepEqual(changes, [JSON.stringify([{ insert: "😀" }])]);
});

test("applyRemote applies bare operations with API source and does not echo", async () => {
  const { applyRemote, mount } = await bridge();
  const changes = [];
  const editor = await mountEditor(
    mount,
    "[]",
    (change) => changes.push(change),
    () => {},
  );
  const delta = [{ retain: 2 }, { insert: "remote" }];

  applyRemote(editor, JSON.stringify(delta));

  assert.deepEqual(instances[0].calls.updateContents, [[delta, "api"]]);
  assert.deepEqual(changes, []);
});

test("loadDocument replaces the document silently", async () => {
  const { loadDocument, mount } = await bridge();
  const editor = await mountEditor(mount, "[]", () => {}, () => {});
  instances[0].calls.setContents.length = 0;
  const document = [{ insert: "Replacement\n" }];

  loadDocument(editor, JSON.stringify(document));

  assert.deepEqual(instances[0].calls.setContents, [[document, "silent"]]);
});

test("mount reports missing elements through the error callback", async () => {
  const { mount } = await bridge();
  const errors = [];

  mount(
    "missing",
    "[]",
    () => {},
    () => {},
    (error) => errors.push(error),
  );
  await Promise.resolve();

  assert.equal(instances.length, 0);
  assert.deepEqual(errors, ['rich editor element "missing" was not found']);
});

test("mount reports success explicitly and cleans a partial editor on failure", async () => {
  const { mount } = await bridge();
  const mounted = [];
  const errors = [];
  initialLoadError = new Error("initial load failed");

  mount(
    "editor",
    "[]",
    () => {},
    (editor) => mounted.push(editor),
    (error) => errors.push(error),
  );
  await Promise.resolve();

  assert.deepEqual(mounted, []);
  assert.deepEqual(errors, ["initial load failed"]);
  assert.equal(instances[0].calls.off.length, 1);
});

test("callback and editor failures are reported", async () => {
  const { applyRemote, mount } = await bridge();
  const errors = [];
  const editor = await mountEditor(
    mount,
    "[]",
    () => {},
    (error) => errors.push(error),
  );
  const cyclic = {};
  cyclic.self = cyclic;

  instances[0].emit({ ops: [cyclic] }, "user");
  instances[0].updateContents = () => {
    throw new Error("remote failed");
  };
  applyRemote(editor, "[]");
  await Promise.resolve();

  assert.match(errors[0], /circular|cyclic/i);
  assert.equal(errors[1], "remote failed");
});

test("destroy removes the listener once and blocks late work", async () => {
  const { applyRemote, destroy, loadDocument, mount } = await bridge();
  const changes = [];
  const editor = await mountEditor(
    mount,
    "[]",
    (change) => changes.push(change),
    () => {},
  );
  const handler = instances[0].handlers.get("text-change");
  instances[0].calls.setContents.length = 0;

  destroy(editor);
  destroy(editor);
  handler({ ops: [{ insert: "late" }] }, {}, "user");
  applyRemote(editor, "[]");
  loadDocument(editor, "[]");

  assert.equal(instances[0].calls.off.length, 1);
  assert.equal(instances[0].calls.off[0][0], "text-change");
  assert.equal(instances[0].calls.off[0][1], handler);
  assert.equal(editor.editor, null);
  assert.equal(editor.textChange, null);
  assert.deepEqual(changes, []);
  assert.deepEqual(instances[0].calls.updateContents, []);
  assert.deepEqual(instances[0].calls.setContents, []);
});

test("the bridge module can load before a browser document exists", async () => {
  delete globalThis.document;
  delete globalThis.__projectRoomQuillConstructor;

  await import(
    `../src/project_room_lustre/rich_editor_ffi.mjs?headless=${Date.now()}`
  );
});

test("mount and retained editor callbacks leave the current stack first", async () => {
  const { mount } = await bridge();
  const events = [];

  mount(
    "editor",
    "[]",
    () => events.push("change"),
    () => events.push("mounted"),
    () => events.push("error"),
  );

  assert.deepEqual(events, []);
  await Promise.resolve();
  assert.deepEqual(events, ["mounted"]);

  instances[0].emit({ ops: [{ insert: "user" }] }, "user");
  assert.deepEqual(events, ["mounted"]);
  await Promise.resolve();
  assert.deepEqual(events, ["mounted", "change"]);
});
