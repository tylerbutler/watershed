// Focused unit tests for the Quill-compatible SharedRichText adapter, using
// a fake Quill-like editor and Node's built-in test runner. No test
// framework or Quill dependency required: `node --test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRichTextAdapter } from "./rich-text-adapter.js";

/** Minimal structural stand-in for a Quill instance. */
function createFakeEditor() {
  const listeners = new Map();
  return {
    calls: {
      updateContents: /** @type {Array<[unknown, string]>} */ ([]),
      setContents: /** @type {Array<[unknown, string]>} */ ([]),
    },
    on(event, handler) {
      if (!listeners.has(event)) listeners.set(event, new Set());
      listeners.get(event).add(handler);
    },
    off(event, handler) {
      listeners.get(event)?.delete(handler);
    },
    listenerCount(event) {
      return listeners.get(event)?.size ?? 0;
    },
    emitTextChange(delta, oldDelta, source) {
      for (const handler of listeners.get("text-change") ?? []) {
        handler(delta, oldDelta, source);
      }
    },
    emitSelectionChange(range, oldRange, source) {
      for (const handler of listeners.get("selection-change") ?? []) {
        handler(range, oldRange, source);
      }
    },
    updateContents(delta, source) {
      this.calls.updateContents.push([delta, source]);
    },
    setContents(delta, source) {
      this.calls.setContents.push([delta, source]);
    },
  };
}

/** Identity-ish fake transform: shifts index by delta.shift, marks calls. */
function createFakeTransform() {
  const calls = [];
  const fn = (selection, delta, isOwnOperation) => {
    calls.push({ selection, delta, isOwnOperation });
    const shift = typeof delta?.shift === "number" ? delta.shift : 0;
    return { index: selection.index + shift, length: selection.length };
  };
  fn.calls = calls;
  return fn;
}

function makeConfig(overrides = {}) {
  const editor = overrides.editor ?? createFakeEditor();
  const submitted = [];
  const localSelections = [];
  const peerRenders = [];
  const transformSelection = overrides.transformSelection ?? createFakeTransform();
  const adapter = createRichTextAdapter({
    editor,
    submitChange: (delta) => submitted.push(delta),
    onLocalSelection: (selection) => localSelections.push(selection),
    onPeerSelections: (peers) => peerRenders.push(peers),
    transformSelection,
    ...overrides.config,
  });
  return { editor, submitted, localSelections, peerRenders, transformSelection, adapter };
}

test("only source 'user' submits a change", () => {
  const { editor, submitted } = makeConfig();
  editor.emitTextChange({ ops: [{ insert: "a" }] }, {}, "user");
  editor.emitTextChange({ ops: [{ insert: "b" }] }, {}, "api");
  editor.emitTextChange({ ops: [{ insert: "c" }] }, {}, "silent");
  assert.equal(submitted.length, 1);
  assert.deepEqual(submitted[0], { ops: [{ insert: "a" }] });
});

test("applying a remote change does not resubmit", () => {
  const { editor, submitted, adapter } = makeConfig();
  adapter.applyChange({ delta: { ops: [{ insert: "x" }] }, local: false });
  assert.equal(submitted.length, 0);
  // The editor.updateContents call fires a synthetic text-change in real
  // Quill; simulate that and confirm it still doesn't resubmit.
  editor.emitTextChange({ ops: [{ insert: "x" }] }, {}, "api");
  assert.equal(submitted.length, 0);
});

test("remote apply uses editor.updateContents with source exactly 'api'", () => {
  const { editor, adapter } = makeConfig();
  const delta = { ops: [{ insert: "remote" }] };
  adapter.applyChange({ delta, local: false });
  assert.equal(editor.calls.updateContents.length, 1);
  const [appliedDelta, source] = editor.calls.updateContents[0];
  assert.equal(source, "api");
  assert.equal(appliedDelta, delta);
});

test("local RichTextChanged events are ignored for editor application", () => {
  const { editor, adapter } = makeConfig();
  adapter.applyChange({ delta: { ops: [{ insert: "echo" }] }, local: true });
  assert.equal(editor.calls.updateContents.length, 0);
  assert.equal(editor.calls.setContents.length, 0);
});

test("loadDocument uses a setup/reconnect path and does not submit", () => {
  const { editor, submitted, adapter } = makeConfig();
  const documentDelta = { ops: [{ insert: "whole doc" }] };
  adapter.loadDocument(documentDelta);
  assert.equal(editor.calls.setContents.length, 1);
  const [appliedDelta, source] = editor.calls.setContents[0];
  assert.equal(appliedDelta, documentDelta);
  assert.notEqual(source, "user");
  assert.equal(editor.calls.updateContents.length, 0);
  assert.equal(submitted.length, 0);
});

test("local user deltas transform all peer selections as remote", () => {
  const { editor, adapter, peerRenders, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  peerRenders.length = 0; // ignore the replace-triggered render for this assertion
  editor.emitTextChange({ ops: [{ insert: "z" }], shift: 1 }, {}, "user");
  assert.equal(transformSelection.calls.length, 2);
  for (const call of transformSelection.calls) {
    assert.equal(call.isOwnOperation, false);
  }
  const latest = peerRenders.at(-1);
  const alice = latest.find((p) => p.id === "alice");
  const bob = latest.find((p) => p.id === "bob");
  assert.deepEqual(alice.selection, { index: 3, length: 0 });
  assert.deepEqual(bob.selection, { index: 6, length: 1 });
});

test("remote delta with known author uses own=true only for that peer", () => {
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }] },
    local: false,
    author: "alice",
  });
  const aliceCall = transformSelection.calls.find((c) => c.selection.index === 2);
  const bobCall = transformSelection.calls.find((c) => c.selection.index === 5);
  assert.equal(aliceCall.isOwnOperation, true);
  assert.equal(bobCall.isOwnOperation, false);
});

test("numeric peer id matches string author id for own-operation identity", () => {
  const { adapter, transformSelection } = makeConfig();
  // Peer cached under a numeric id...
  adapter.replacePeerSelections([
    { id: 1, selection: { index: 2, length: 0 } },
    { id: 2, selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  // ...but the remote event reports the author as a string.
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }] },
    local: false,
    author: "1",
  });
  const peerOneCall = transformSelection.calls.find((c) => c.selection.index === 2);
  const peerTwoCall = transformSelection.calls.find((c) => c.selection.index === 5);
  assert.equal(peerOneCall.isOwnOperation, true);
  assert.equal(peerTwoCall.isOwnOperation, false);
  // The original numeric id is preserved for display on the cached entry.
  const snapshot = adapter.getPeerSelections();
  const peerOne = snapshot.find((p) => p.id === 1);
  assert.equal(typeof peerOne.id, "number");
  assert.equal(peerOne.selection.index, 2);
});

test("authorSelectionAlreadyApplied skips only the author's cached entry", () => {
  // Simulates a presence/roster path that has already delivered the
  // author's post-edit selection (e.g. a synchronous, zero-latency
  // broadcast racing ahead of a latency-modelled op delivery): the cached
  // "alice" entry is already her position *after* this delta, so
  // transforming it again would double-shift it. Bob's cache still needs
  // the ordinary transform.
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }], shift: 3 },
    local: false,
    author: "alice",
    authorSelectionAlreadyApplied: true,
  });
  // Only bob's cached selection was transformed; alice's was left alone.
  assert.equal(transformSelection.calls.length, 1);
  assert.equal(transformSelection.calls[0].selection.index, 5);
  assert.equal(transformSelection.calls[0].isOwnOperation, false);

  const snapshot = adapter.getPeerSelections();
  const alice = snapshot.find((p) => p.id === "alice");
  const bob = snapshot.find((p) => p.id === "bob");
  assert.deepEqual(alice.selection, { index: 2, length: 0 }); // untouched
  assert.deepEqual(bob.selection, { index: 8, length: 1 }); // shifted by 3
});

test("authorSelectionAlreadyApplied has no effect when author is unknown", () => {
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }] },
    local: false,
    // No author, so no cached entry is identified as "the author's" —
    // the flag can't skip anything and every peer transforms as usual.
    authorSelectionAlreadyApplied: true,
  });
  assert.equal(transformSelection.calls.length, 2);
  for (const call of transformSelection.calls) {
    assert.equal(call.isOwnOperation, false);
  }
});

test("default contract (authorSelectionAlreadyApplied omitted) still transforms the known author's cache — Task 7 behavior intact", () => {
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }], shift: 3 },
    local: false,
    author: "alice",
    // authorSelectionAlreadyApplied omitted entirely.
  });
  assert.equal(transformSelection.calls.length, 2);
  const aliceCall = transformSelection.calls.find((c) => c.selection.index === 2);
  const bobCall = transformSelection.calls.find((c) => c.selection.index === 5);
  assert.equal(aliceCall.isOwnOperation, true);
  assert.equal(bobCall.isOwnOperation, false);
  const snapshot = adapter.getPeerSelections();
  assert.deepEqual(snapshot.find((p) => p.id === "alice").selection, {
    index: 5,
    length: 0,
  });
});

test("authorSelectionAlreadyApplied: false is equivalent to omitting it", () => {
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({
    delta: { ops: [{ insert: "y" }], shift: 3 },
    local: false,
    author: "alice",
    authorSelectionAlreadyApplied: false,
  });
  assert.equal(transformSelection.calls.length, 1);
  assert.equal(transformSelection.calls[0].isOwnOperation, true);
});

test("remote delta with unknown author uses own=false for all peers", () => {
  const { adapter, transformSelection } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  transformSelection.calls.length = 0;
  adapter.applyChange({ delta: { ops: [{ insert: "y" }] }, local: false });
  assert.equal(transformSelection.calls.length, 2);
  for (const call of transformSelection.calls) {
    assert.equal(call.isOwnOperation, false);
  }
});

test("heartbeat roster replacement corrects cached values", () => {
  const { adapter, peerRenders } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
  ]);
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 40, length: 0 } },
    { id: "carol", selection: { index: 1, length: 3 } },
  ]);
  const latest = peerRenders.at(-1);
  assert.equal(latest.length, 2);
  const alice = latest.find((p) => p.id === "alice");
  assert.deepEqual(alice.selection, { index: 40, length: 0 });
  const snapshot = adapter.getPeerSelections();
  assert.equal(snapshot.find((p) => p.id === "carol").selection.index, 1);
});

test("peer renderer receives immutable snapshots in stable order", () => {
  const { adapter, peerRenders } = makeConfig();
  adapter.replacePeerSelections([
    { id: "alice", selection: { index: 2, length: 0 } },
    { id: "bob", selection: { index: 5, length: 1 } },
  ]);
  const firstSnapshot = peerRenders.at(-1);
  assert.deepEqual(
    firstSnapshot.map((p) => p.id),
    ["alice", "bob"],
  );
  // Mutating a returned snapshot must not affect the adapter's own cache.
  firstSnapshot[0].selection.index = 999;
  const freshSnapshot = adapter.getPeerSelections();
  assert.equal(freshSnapshot[0].selection.index, 2);
});

test("local selection publish normalizes ranges and handles null focus", () => {
  const { editor, localSelections } = makeConfig();
  editor.emitSelectionChange({ index: 3, length: 2 }, null, "user");
  editor.emitSelectionChange(null, { index: 3, length: 2 }, "user");
  assert.deepEqual(localSelections[0], { index: 3, length: 2 });
  assert.equal(localSelections[1], null);
});

test("destroy unregisters listeners and prevents later submissions/publications", () => {
  const { editor, submitted, localSelections, peerRenders, adapter } = makeConfig();
  adapter.destroy();
  assert.equal(editor.listenerCount("text-change"), 0);
  assert.equal(editor.listenerCount("selection-change"), 0);

  // Even if something still calls the old handlers directly (defensive
  // guard against double-invocation), nothing should be published.
  editor.emitTextChange({ ops: [{ insert: "late" }] }, {}, "user");
  editor.emitSelectionChange({ index: 0, length: 0 }, null, "user");
  assert.equal(submitted.length, 0);
  assert.equal(localSelections.length, 0);

  const rendersBefore = peerRenders.length;
  adapter.replacePeerSelections([{ id: "alice", selection: { index: 1, length: 0 } }]);
  adapter.applyChange({ delta: { ops: [{ insert: "x" }] }, local: false });
  adapter.loadDocument({ ops: [{ insert: "doc" }] });
  assert.equal(peerRenders.length, rendersBefore);
  assert.equal(editor.calls.updateContents.length, 0);
  assert.equal(editor.calls.setContents.length, 0);
});

test("caller-owned inputs are not mutated", () => {
  const { adapter } = makeConfig();
  const peerEntry = { id: "alice", selection: { index: 2, length: 0 } };
  const peerList = [peerEntry];
  adapter.replacePeerSelections(peerList);

  const delta = { ops: [{ insert: "hi" }], shift: 1 };
  const frozenDeltaOps = JSON.stringify(delta);
  const remoteEvent = { delta, local: false, author: "bob" };
  adapter.applyChange(remoteEvent);

  assert.equal(JSON.stringify(delta), frozenDeltaOps);
  assert.deepEqual(peerEntry.selection, { index: 2, length: 0 });
  assert.equal(remoteEvent.delta, delta);
});

test("transformSelection contract: wrapper reorders args and unwraps a generated-style Result", () => {
  // Stand-in for the generated `rich_text.transform_selection(delta,
  // selection, is_own_op) -> Result(Selection, Error)` FFI export: Gleam's
  // argument order (delta first), returning a tagged Ok/Error rather than a
  // plain Selection.
  function fakeGeneratedTransformSelection(delta, selection, isOwnOp) {
    if (delta?.malformed) {
      return { isOk: false, error: "Malformed" };
    }
    const shift = typeof delta?.shift === "number" ? delta.shift : 0;
    return {
      isOk: true,
      value: { index: selection.index + shift, length: selection.length },
    };
  }

  // The integration wrapper callers must supply per the TransformSelection
  // JSDoc contract: reorder to (selection, delta, isOwnOperation) and
  // unwrap the Result, falling back to the untransformed selection on Error.
  function wrapGeneratedTransformSelection(selection, delta, isOwnOperation) {
    const result = fakeGeneratedTransformSelection(delta, selection, isOwnOperation);
    if (!result.isOk) {
      return selection; // explicit fallback on Error
    }
    return result.value;
  }

  const { editor, adapter } = makeConfig({
    transformSelection: wrapGeneratedTransformSelection,
  });
  adapter.replacePeerSelections([{ id: "alice", selection: { index: 2, length: 0 } }]);

  // Successful transform: the wrapper's unwrapped value is used.
  editor.emitTextChange({ ops: [{ insert: "z" }], shift: 3 }, {}, "user");
  let alice = adapter.getPeerSelections().find((p) => p.id === "alice");
  assert.deepEqual(alice.selection, { index: 5, length: 0 });

  // Error case: the wrapper falls back to the untransformed selection
  // instead of leaking the Result wrapper into the cache.
  editor.emitTextChange({ ops: [], malformed: true }, {}, "user");
  alice = adapter.getPeerSelections().find((p) => p.id === "alice");
  assert.deepEqual(alice.selection, { index: 5, length: 0 });
});
