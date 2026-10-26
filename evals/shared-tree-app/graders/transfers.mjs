import assert from "node:assert/strict";
import { wait } from "../lib/conditions.mjs";
import { createBarrier } from "../lib/barrier.mjs";

const snapshot = page => page.evaluate("globalThis.__incidentEval.snapshot()");
const board = async page => (await snapshot(page)).board;
const apply = (page, action) =>
  page.evaluate(`globalThis.__incidentEval.apply(${JSON.stringify(action)})`);
const row = id => `[data-step-id=${JSON.stringify(id)}]`;
const incidentRow = id => `[data-incident-id=${JSON.stringify(id)}]`;
const steps = (value, id) => value.incidents.find(incident => incident.id === id).steps;
const step = (value, id) => value.incidents.flatMap(incident => incident.steps).find(node => node.id === id);

function transfer(value, source, id, destination, before = null) {
  if (source === destination && before === id) return;
  const from = steps(value, source);
  const [node] = from.splice(from.findIndex(node => node.id === id), 1);
  const to = steps(value, destination);
  to.splice(before === null ? to.length : to.findIndex(node => node.id === before), 0, node);
}

export async function runTransferScenarios({ services, browser, record, signal }) {
  const pages = new Set();
  const check = async (id, run) => {
    signal?.throwIfAborted();
    const started = performance.now();
    try {
      const evidence = await run();
      record({ id, passed: true, durationMs: performance.now() - started,
        evidence: evidence ?? "Assertions passed against native nodes, retained references, and browser state" });
    } catch (error) {
      record({ id, passed: false, durationMs: performance.now() - started,
        evidence: error.stack ?? error.message });
      throw error;
    }
  };
  const open = async url => {
    const page = await (await browser.context()).page();
    pages.add(page);
    await page.goto(url);
    await wait("transfer app readiness", () => page.evaluate(`(() => {
      const errors = [...document.querySelectorAll("[role=alert]")].map(node => node.textContent);
      if (errors.length) throw new Error(errors.join("; "));
      return globalThis.__incidentEval?.snapshot();
    })()`), value => value?.phase === "ready");
    return page;
  };
  const equals = async (page, expected) => {
    await wait("transferred native board", () => board(page),
      value => JSON.stringify(value) === JSON.stringify(expected));
    assert.deepEqual((await page.evaluate("globalThis.__nativeEval.inspect()")).board, expected);
  };
  const close = async page => {
    await page.click('[data-action="close"]');
    await page.waitFor('[data-state="closed"]');
    assert.deepEqual(await page.evaluate("globalThis.__nativeEval.closed()"), {
      documentClosed: true, viewClosed: true,
    });
    assert.equal(await page.evaluate(
      'Array.from(document.querySelectorAll("input,select,button")).every(node => node.disabled)'), true);
    assert.deepEqual(page.errors(), []);
    await page.close();
    pages.delete(page);
  };
  const captured = (page, key) =>
    page.evaluate(`globalThis.__nativeEval.capturedState(${JSON.stringify(key)})`);
  let expected;
  const act = async (page, action, change) => {
    change(expected);
    await apply(page, action);
    await equals(page, expected);
  };
  const transferControls = async (page, id, destination, before = null) => {
    const options = ["", ...steps(await board(page), destination).map(node => node.id)];
    await page.select(`${row(id)} [data-field="transfer-destination"]`, destination);
    await wait("destination sibling controls", () => page.evaluate(`(() => {
      const select = document.querySelector(${JSON.stringify(`${row(id)} [data-field="transfer-before"]`)});
      return select && !select.disabled && JSON.stringify([...select.options].map(node => node.value))
        === ${JSON.stringify(JSON.stringify(options))};
    })()`), Boolean);
    await page.select(`${row(id)} [data-field="transfer-before"]`, before ?? "");
    await page.click(`${row(id)} [data-action="transfer-step"]`);
  };
  const uiMove = async (page, source, id, destination, before = null) => {
    transfer(expected, source, id, destination, before);
    await transferControls(page, id, destination, before);
    await equals(page, expected);
  };
  const move = uiMove;
  const submitConcurrent = async (page, action) => {
    switch (action.type) {
      case "transfer-step":
        return transferControls(page, action.id, action.destination, action.before);
      case "step-label":
        return page.fill(`${row(action.id)} [data-field="step-label"]`, action.value);
      case "step-done":
        return page.click(`${row(action.id)} [data-field="step-done"]`);
      case "remove-step":
        return page.click(`${row(action.id)} [data-action="remove-step"]`);
      default: throw new Error(`Unsupported concurrent transfer action: ${action.type}`);
    }
  };
  try {
    await wait("previous native sessions closed", async () => services.transport.clients().length,
      count => count === 0);
    const a = await open(services.appUrl);
    assert.deepEqual(await board(a), { incidents: [] });
    for (let count = 1; count <= 2; count++) {
      await a.click('[data-action="add-incident"]');
      await wait("transfer incident creation", () => board(a), value => value.incidents.length === count);
    }
    const [first, second] = (await board(a)).incidents.map(node => node.id);
    for (let count = 1; count <= 3; count++) {
      await a.click(`${incidentRow(first)} [data-action="add-step"]`);
      await wait("transfer step creation", () => board(a), value => steps(value, first).length === count);
    }
    expected = await board(a);
    const [one, two, three] = steps(expected, first).map(node => node.id);
    for (const [id, label] of [[one, "Handoff"], [two, "Keep second"], [three, "Keep third"]]) {
      await act(a, { type: "step-label", incident: first, id, value: label },
        value => { step(value, id).label = label; });
    }
    const keys = await a.evaluate("globalThis.__nativeEval.capture()");
    const references = async (page, capturedKeys = keys) => {
      for (const key of capturedKeys) {
        const state = await captured(page, key);
        const current = key.startsWith("step:") ? step(expected, key.slice(5)) : undefined;
        assert.equal(state.attached, !key.startsWith("step:") || current !== undefined, key);
        if (current) assert.deepEqual(state.value, current, key);
        if (key === "root") assert.deepEqual(state.value, expected);
      }
    };
    await check("transfers.local", async () => {
      await uiMove(a, first, one, second);
      await move(a, first, two, second, one);
      await move(a, second, one, first, three);
      await move(a, first, one, second);
      await move(a, second, one, second, one);
      await move(a, second, one, second, two);
    });
    await check("transfers.identity", async () => {
      await references(a);
      step(expected, one).label = "Edited through pre-transfer native reference";
      await a.evaluate(`globalThis.__nativeEval.setCaptured(${JSON.stringify(`step:${one}`)},
        "label", "Edited through pre-transfer native reference")`);
      await equals(a, expected);
      await act(a, { type: "move-step", incident: second, id: two, before: one },
        value => transfer(value, second, two, second, one));
      step(expected, one).label = "Correct current parent and index";
      await a.fill(`${row(one)} [data-field="step-label"]`, step(expected, one).label);
      await equals(a, expected);
      await references(a);
    });
    await check("transfers.invalid-input", async () => {
      for (const destination of ["", "missing-incident", first]) {
        const before = destination === first ? two : null;
        const alerts = await a.evaluate('document.querySelectorAll("[role=alert]").length');
        await apply(a, { type: "transfer-step", incident: second, id: one, destination, before });
        await wait("visible invalid transfer", () => a.evaluate(
          'document.querySelectorAll("[role=alert]").length'), count => count > alerts);
        await equals(a, expected);
      }
      await apply(a, { type: "transfer-step", incident: first, id: one, destination: second, before: null });
      await equals(a, expected);
      await act(a, { type: "add-incident", id: "retired-parent", title: "" },
        value => value.incidents.push({ id: "retired-parent", title: "", status: "open", steps: [] }));
      await act(a, { type: "add-step", incident: "retired-parent", id: "retired-step", label: "Retired" },
        value => steps(value, "retired-parent").push({ id: "retired-step", label: "Retired", done: false }));
      await act(a, { type: "remove-incident", id: "retired-parent" },
        value => { value.incidents = value.incidents.filter(node => node.id !== "retired-parent"); });
      await apply(a, { type: "transfer-step", incident: "retired-parent", id: "retired-step",
        destination: first, before: null });
      await equals(a, expected);
      await references(a);
    });
    const url = new URL(services.appUrl);
    url.searchParams.set("document", (await snapshot(a)).documentId);
    const b = await open(url.href);
    await equals(b, expected);
    const bKeys = await b.evaluate("globalThis.__nativeEval.capture()");
    await check("transfers.remote", async () => {
      await move(a, second, one, first, three);
      await equals(b, expected);
      step(expected, one).label = "Remote edit after transfer";
      await b.fill(`${row(one)} [data-field="step-label"]`, step(expected, one).label);
      await equals(a, expected);
      await equals(b, expected);
      await move(b, first, one, second, two);
      await equals(a, expected);
      await references(a);
      await references(b, bKeys);
    });
    const concurrent = async (left, right, final) => {
      await wait("exactly two transfer clients", async () => services.transport.clients().length,
        count => count === 2);
      const barrier = createBarrier({ transport: services.transport, clients: services.transport.clients() });
      try {
        const localA = structuredClone(expected);
        const localB = structuredClone(expected);
        left.change(localA);
        right.change(localB);
        barrier.hold();
        await submitConcurrent(a, left.action);
        await submitConcurrent(b, right.action);
        await equals(a, localA);
        await equals(b, localB);
        await barrier.waitForSubmissions();
        barrier.release();
        final(expected);
        await equals(a, expected);
        await equals(b, expected);
        const evidence = barrier.evidence();
        assert.equal(evidence.proven, true);
        assert.equal(evidence.submittedClients.length, 2);
        assert.ok(evidence.heldFrames > 0);
        assert.equal(evidence.deliveryViolation, null);
        return evidence;
      } finally { barrier.close(); }
    };
    await check("transfers.concurrent-edit", async () => {
      const label = "Edited concurrently with handoff";
      const moveFirst = value => transfer(value, second, one, first, three);
      const editLabel = value => { step(value, one).label = label; };
      const firstEvidence = await concurrent(
        { action: { type: "transfer-step", incident: second, id: one, destination: first, before: three },
          change: moveFirst },
        { action: { type: "step-label", incident: second, id: one, value: label }, change: editLabel },
        value => { moveFirst(value); editLabel(value); });
      await references(a);
      await references(b, bKeys);
      const editDone = value => { step(value, one).done = true; };
      const moveBack = value => transfer(value, first, one, second, two);
      const secondEvidence = await concurrent(
        { action: { type: "step-done", incident: first, id: one, value: true }, change: editDone },
        { action: { type: "transfer-step", incident: first, id: one, destination: second, before: two },
          change: moveBack },
        value => { editDone(value); moveBack(value); });
      await references(a);
      await references(b, bKeys);
      return JSON.stringify([firstEvidence, secondEvidence]);
    });
    await check("transfers.concurrent-delete", async () => {
      const remove = value => { steps(value, second).splice(
        steps(value, second).findIndex(node => node.id === one), 1); };
      const evidence = await concurrent(
        { action: { type: "remove-step", incident: second, id: one }, change: remove },
        { action: { type: "step-label", incident: second, id: one, value: "Edit removed step" },
          change: value => { step(value, one).label = "Edit removed step"; } },
        remove);
      await references(a);
      await references(b, bKeys);
      for (const action of [
        { type: "step-label", incident: second, id: one, value: "Must stay removed" },
        { type: "transfer-step", incident: second, id: one, destination: first, before: null },
      ]) await apply(a, action);
      await equals(a, expected);
      await equals(b, expected);
      return JSON.stringify(evidence);
    });
    await check("transfers.persistence", async () => {
      await uiMove(b, first, three, second);
      await equals(a, expected);
      await references(a);
      await references(b, bKeys);
      const late = await open(url.href);
      await equals(late, expected);
      await close(late);
      await close(a);
      await close(b);
      await wait("all transferred document sessions closed", async () => services.transport.clients().length,
        count => count === 0);
      const reopened = await open(url.href);
      await equals(reopened, expected);
      await close(reopened);
    });
  } finally {
    for (const page of pages) await page.close();
  }
}
