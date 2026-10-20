import assert from "node:assert/strict";
import { wait } from "../lib/conditions.mjs";
import { createBarrier } from "../lib/barrier.mjs";

const snapshot = page => page.evaluate("globalThis.__incidentEval.snapshot()");
const board = async page => (await snapshot(page)).board;
const native = page => page.evaluate("globalThis.__nativeEval.inspect()");
const incidentSelector = id => `[data-incident-id=${JSON.stringify(id)}]`;
const stepSelector = id => `[data-step-id=${JSON.stringify(id)}]`;
const field = (selector, name) => `${selector} [data-field="${name}"]`;
const action = (selector, name) => `${selector} [data-action="${name}"]`;
const frame = page => page.evaluate("new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))");
const apply = (page, value) => page.evaluate(`globalThis.__incidentEval.apply(${JSON.stringify(value)})`);

async function ready(page, url) {
  await page.goto(url);
  await wait("native app readiness", () => page.evaluate(`(() => {
    const errors = [...document.querySelectorAll("[role=alert]")].map(el => el.textContent);
    if (errors.length) throw new Error(errors.join("; "));
    return globalThis.__incidentEval?.snapshot();
  })()`), state => state?.phase === "ready");
}

export async function runScenarios({ sdk, services, browser, record }) {
  const pages = [];
  const open = async url => {
    const page = await (await browser.context()).page();
    pages.push(page);
    await ready(page, url);
    return page;
  };
  const check = async (ids, run) => {
    const started = performance.now();
    try {
      const evidence = await run();
      for (const id of [ids].flat()) record({ id, passed: true,
        durationMs: performance.now() - started,
        evidence: evidence ?? "Assertions passed against browser state and actual native SDK objects" });
    } catch (error) {
      for (const id of [ids].flat()) record({ id, passed: false,
        durationMs: performance.now() - started, evidence: error.stack ?? error.message });
      throw new Error(`${[ids].flat().join(", ")} failed: ${error.message}`, { cause: error });
    }
  };
  const equals = async (page, expected) => {
    await wait("expected native-backed board", () => board(page),
      value => JSON.stringify(value) === JSON.stringify(expected));
    assert.deepEqual((await native(page)).board, expected);
  };
  const changed = async (page, predicate) => {
    await wait("expected user edit", () => board(page), predicate);
    const value = await board(page);
    assert.deepEqual((await native(page)).board, value);
    return value;
  };
  const a = await open(services.appUrl);
  await check("native.schema", async () => {
    const value = await native(a);
    assert.equal(value.schema, true);
    assert.equal(value.native, true);
    assert.deepEqual(value.board, { incidents: [] });
  });
  let first;
  let second;
  let firstStep;
  let secondStep;
  await check("local.incident-create", async () => {
    await a.click('[data-action="add-incident"]');
    let value = await changed(a, value => value.incidents.length === 1);
    first = value.incidents[0].id;
    assert.equal(typeof first, "string");
    assert.ok(first.length);
    assert.deepEqual(value.incidents[0], { id: first, title: "", status: "open", steps: [] });
    await a.click('[data-action="add-incident"]');
    value = await changed(a, value => value.incidents.length === 2);
    second = value.incidents[1].id;
    assert.notEqual(second, first);
    assert.ok(second.length);
  });
  const firstRow = incidentSelector(first);
  const secondRow = incidentSelector(second);
  await check("local.step-create", async () => {
    for (let count = 1; count <= 2; count++) {
      await a.click(action(firstRow, "add-step"));
      await changed(a, value => value.incidents[0].steps.length === count);
    }
    const steps = (await board(a)).incidents[0].steps;
    [firstStep, secondStep] = steps.map(step => step.id);
    assert.equal(new Set([first, second, firstStep, secondStep]).size, 4);
    assert.ok(firstStep.length && secondStep.length);
    assert.deepEqual(steps, [
      { id: firstStep, label: "", done: false },
      { id: secondStep, label: "", done: false },
    ]);
  });
  const captured = await a.evaluate("globalThis.__nativeEval.capture()");
  const assertCaptured = async () => {
    for (const key of captured) {
      assert.equal((await a.evaluate(
        `globalThis.__nativeEval.capturedState(${JSON.stringify(key)})`)).attached, true, key);
    }
  };
  await check("local.incident-title", async () => {
    for (const title of ["Database outage", "Whole string: \u00e9 \ud83c\udf0a", ""]) {
      await a.fill(field(firstRow, "title"), title);
      await changed(a, value => value.incidents[0].title === title);
    }
  });
  await check("local.incident-status", async () => {
    for (const status of ["investigating", "resolved", "open"]) {
      await a.select(field(firstRow, "status"), status);
      await changed(a, value => value.incidents[0].status === status);
    }
  });
  await check("local.step-label", async () => {
    for (const label of ["Check replica", ""]) {
      await a.fill(field(stepSelector(firstStep), "step-label"), label);
      await changed(a, value => value.incidents[0].steps[0].label === label);
    }
  });
  await check("local.step-complete", async () => {
    for (const done of [true, false]) {
      await a.click(field(stepSelector(firstStep), "step-done"));
      await changed(a, value => value.incidents[0].steps[0].done === done);
    }
  });
  await check("local.assignee-set", async () => {
    for (const assignee of ["Alex", ""]) {
      await a.fill(field(firstRow, "assignee"), assignee);
      await changed(a, value => value.incidents[0].assignee === assignee);
    }
  });
  await check(["local.assignee-remove", "native.optional"], async () => {
    await a.click(action(firstRow, "assignee-remove"));
    await changed(a, value => !Object.hasOwn(value.incidents[0], "assignee"));
    assert.equal(Object.hasOwn((await native(a)).board.incidents[0], "assignee"), false);
  });
  await check("native.property-edits", async () => {
    await assertCaptured();
    const key = JSON.stringify(`incident:${first}`);
    await a.evaluate(`globalThis.__nativeEval.setCaptured(${key}, "title", "Captured incident")`);
    await changed(a, value => value.incidents[0].title === "Captured incident");
    await a.evaluate(`globalThis.__nativeEval.setCaptured(${JSON.stringify(`step:${firstStep}`)}, "label", "Captured step")`);
    await changed(a, value => value.incidents[0].steps[0].label === "Captured step");
  });
  await check("local.incident-move", async () => {
    await a.click(action(firstRow, "incident-down"));
    await changed(a, value => value.incidents.map(node => node.id).join() === [second, first].join());
    await a.click(action(firstRow, "incident-up"));
    await changed(a, value => value.incidents.map(node => node.id).join() === [first, second].join());
  });
  await check("local.step-move", async () => {
    await a.click(action(stepSelector(firstStep), "step-down"));
    await changed(a, value => value.incidents[0].steps.map(node => node.id).join() === [secondStep, firstStep].join());
    await a.click(action(stepSelector(firstStep), "step-up"));
    await changed(a, value => value.incidents[0].steps.map(node => node.id).join() === [firstStep, secondStep].join());
  });
  await check("identity.move", async () => {
    await assertCaptured();
    assert.equal((await a.evaluate(
      `globalThis.__nativeEval.capturedState(${JSON.stringify(`incident:${first}`)})`)).value.id, first);
    assert.equal((await a.evaluate(
      `globalThis.__nativeEval.capturedState(${JSON.stringify(`step:${firstStep}`)})`)).value.id, firstStep);
  });
  await check("local.noop-move", async () => {
    const expected = await board(a);
    await apply(a, { type: "move-incident", id: first, before: first });
    await apply(a, { type: "move-step", incident: first, id: firstStep, before: firstStep });
    await frame(a);
    await equals(a, expected);
    await assertCaptured();
  });
  const documentUrl = await a.evaluate("location.href");
  const b = await open(documentUrl);
  await equals(b, await board(a));
  await check("collaboration.remote", async () => {
    await a.fill(field(secondRow, "title"), "Written by A");
    await changed(b, value => value.incidents[1].title === "Written by A");
    await b.fill(field(firstRow, "assignee"), "Written by B");
    await changed(a, value => value.incidents[0].assignee === "Written by B");
    await equals(b, await board(a));
  });
  await check(["collaboration.moves", "identity.target"], async () => {
    await b.click(action(secondRow, "incident-up"));
    await changed(a, value => value.incidents[0].id === second);
    await a.fill(field(firstRow, "title"), "Target after move");
    await changed(b, value => value.incidents[1].title === "Target after move");
    await b.click(action(stepSelector(secondStep), "step-up"));
    await changed(a, value => value.incidents[1].steps[0].id === secondStep);
    await a.fill(field(stepSelector(firstStep), "step-label"), "Target step after move");
    await changed(b, value => value.incidents[1].steps[1].label === "Target step after move");
    await equals(b, await board(a));
    await assertCaptured();
  });
  await check("local.step-delete", async () => {
    await a.click(action(stepSelector(firstStep), "remove-step"));
    await changed(b, value => value.incidents[1].steps.length === 1);
    const expected = await board(b);
    await apply(a, { type: "remove-step", incident: first, id: firstStep });
    await frame(a);
    await equals(a, expected);
    assert.equal((await a.evaluate(
      `globalThis.__nativeEval.capturedState(${JSON.stringify(`step:${firstStep}`)})`)).attached, false);
  });
  let removed;
  await check("local.incident-delete", async () => {
    await a.click('[data-action="add-incident"]');
    const value = await changed(b, value => value.incidents.length === 3);
    removed = value.incidents[2].id;
    await a.click(action(incidentSelector(removed), "remove-incident"));
    await changed(b, value => value.incidents.length === 2);
    const expected = await board(b);
    await apply(a, { type: "remove-incident", id: removed });
    await frame(a);
    await equals(a, expected);
  });
  await check("identity.removed", async () => {
    const expected = await board(b);
    for (const value of [
      { type: "title", id: removed, value: "Must not appear" },
      { type: "move-incident", id: removed, before: first },
      { type: "add-step", incident: removed, id: "must-not-exist", label: "Missing parent" },
      { type: "step-label", incident: first, id: firstStep, value: "Must not redirect" },
      { type: "move-step", incident: first, id: firstStep, before: secondStep },
    ]) await apply(a, value);
    await a.fill(field(secondRow, "title"), "After stale actions");
    expected.incidents[0].title = "After stale actions";
    await equals(b, expected);
    await equals(a, expected);
  });
  const barriers = [];
  const concurrent = async (id, submit, converged) => {
    await check(id, async () => {
      const barrier = createBarrier({ transport: services.transport, clients: services.transport.clients() });
      try {
        barrier.hold();
        await submit();
        await barrier.waitForSubmissions();
        barriers.push(barrier.evidence());
        barrier.release();
        await wait("concurrent convergence", async () => Promise.all([board(a), board(b)]),
          values => JSON.stringify(values[0]) === JSON.stringify(values[1]) && converged(values[0]));
        await equals(a, await board(b));
        return JSON.stringify(barrier.evidence());
      } finally { barrier.close(); }
    });
  };
  await concurrent("concurrency.distinct-fields", async () => {
    await a.fill(field(firstRow, "title"), "Concurrent title");
    await b.fill(field(firstRow, "assignee"), "Concurrent assignee");
  }, value => {
    const node = value.incidents.find(node => node.id === first);
    return node.title === "Concurrent title" && node.assignee === "Concurrent assignee";
  });
  const priorIds = new Set((await board(a)).incidents.map(node => node.id));
  let inserted;
  await concurrent("concurrency.inserts", async () => {
    await a.click('[data-action="add-incident"]');
    await changed(a, value => value.incidents.length === priorIds.size + 1);
    await b.click('[data-action="add-incident"]');
    await changed(b, value => value.incidents.length === priorIds.size + 1);
    const local = await Promise.all([board(a), board(b)]);
    inserted = local.map(value => value.incidents.find(node => !priorIds.has(node.id)).id);
    assert.equal(new Set(inserted).size, 2);
  }, value => value.incidents.length === priorIds.size + 2
    && inserted.every(id => value.incidents.some(node => node.id === id)));
  await concurrent("concurrency.same-field", async () => {
    await a.fill(field(firstRow, "title"), "First contender");
    await b.fill(field(firstRow, "title"), "Second contender");
  }, value => ["First contender", "Second contender"].includes(
    value.incidents.find(node => node.id === first).title));
  await check("concurrency.barrier", async () => {
    assert.equal(barriers.length, 3);
    for (const evidence of barriers) {
      assert.equal(evidence.proven, true);
      assert.equal(evidence.submittedClients.length, 2);
      assert.ok(evidence.heldFrames > 0);
      assert.equal(evidence.deliveryViolation, null);
    }
    return JSON.stringify(barriers);
  });
  const delivered = await board(b);
  let late;
  await check(["persistence.late-join", "lifecycle.no-reset"], async () => {
    late = await open(documentUrl);
    await equals(late, delivered);
    await equals(a, delivered);
    await equals(b, delivered);
    await late.click('[data-action="close"]');
    await late.waitFor('[data-state="closed"]');
  });
  await check("local.invalid-input", async () => {
    for (const value of [
      { type: "add-incident", id: "", title: "Invalid ID" },
      { type: "add-incident", id: secondStep, title: "Duplicate step ID" },
      { type: "add-step", incident: first, id: second, label: "Duplicate incident ID" },
      { type: "move-incident", id: first, before: "missing-destination" },
      { type: "move-step", incident: first, id: secondStep, before: second },
      { type: "status", id: first, value: "invalid" },
    ]) {
      const count = await a.evaluate('document.querySelectorAll("[role=alert]").length');
      await apply(a, value);
      await wait("visible invalid input", () => a.evaluate(
        'document.querySelectorAll("[role=alert]").length'), value => value > count);
      await equals(a, delivered);
    }
    await equals(b, delivered);
  });
  await check(["lifecycle.close", "lifecycle.late-callback"], async () => {
    await a.evaluate(`(() => {
      queueMicrotask(() => globalThis.__incidentEval.close());
      globalThis.__nativeEval.setCaptured(${JSON.stringify(`incident:${first}`)}, "title", "Queued before close");
    })()`);
    await a.waitFor('[data-state="closed"]');
    await frame(a);
    assert.equal((await snapshot(a)).phase, "closed");
    assert.deepEqual(await a.evaluate("globalThis.__nativeEval.closed()"), {
      viewClosed: true, documentClosed: true,
    });
    const expected = await snapshot(a);
    await apply(a, { type: "title", id: first, value: "Must remain closed" });
    await frame(a);
    assert.deepEqual(await snapshot(a), expected);
    assert.equal(await a.evaluate(
      'Array.from(document.querySelectorAll("input,select,button")).every(el => el.disabled)'), true);

    const priorClients = new Set(services.transport.clients());
    const completed = services.diagnostics().completedWrites;
    services.holdHttpWrites(true);
    const early = await (await browser.context()).page();
    pages.push(early);
    try {
      await early.goto(services.appUrl);
      await wait("initialization held before Close", async () => services.diagnostics().pendingWrites,
        count => count === 1);
      await early.click('[data-action="close"]');
      await early.waitFor('[data-state="closed"]');
      services.holdHttpWrites(false);
      await wait("late initialization response", async () => services.diagnostics().completedWrites,
        count => count > completed);
      if (sdk === "fluid") {
        await wait("late native session", () => early.evaluate(
          "globalThis.__incidentEval.native() !== undefined"), Boolean);
      }
      await frame(early);
      assert.equal((await snapshot(early)).phase, "closed");
      assert.deepEqual(await early.evaluate("globalThis.__nativeEval.closed()"), {
        viewClosed: true, documentClosed: true,
      });
      await wait("late initialization leaves no new live transport",
        async () => services.transport.clients().filter(id => !priorClients.has(id)), ids => ids.length === 0);
    } finally { services.holdHttpWrites(false); }
  });
  await check("persistence.reopen", async () => {
    const witness = await open(documentUrl);
    await b.fill(field(firstRow, "title"), "Confirmed before reopen");
    await changed(witness, value =>
      value.incidents.find(node => node.id === first).title === "Confirmed before reopen");
    const persisted = await board(witness);
    await equals(b, persisted);
    await b.click('[data-action="close"]');
    await b.waitFor('[data-state="closed"]');
    await witness.click('[data-action="close"]');
    await witness.waitFor('[data-state="closed"]');
    const reopened = await open(documentUrl);
    await equals(reopened, persisted);
    await reopened.click('[data-action="close"]');
    await reopened.waitFor('[data-state="closed"]');
  });
  await check("lifecycle.errors", async () => {
    const creationAttempts = () => services.diagnostics().rejectedRequests.filter(request =>
      request.method === "POST" && /^\/(?:api\/)?documents\/[^/]+$/.test(request.path)).length;
    for (const failure of ["create", "open"]) {
      const url = new URL(services.appUrl);
      const before = creationAttempts();
      services.rejectHttpWrites(true);
      if (failure === "open") url.searchParams.set("document", "missing-document");
      const page = await (await browser.context()).page();
      const expected = before + (failure === "create" ? 1 : 0);
      const stable = async (closed, duration) => {
        const deadline = performance.now() + duration;
        await wait(`persistent ${failure} failure without retries`, async () => {
          const state = await snapshot(page);
          if (closed) assert.equal(state.phase, "closed");
          else {
            assert.notEqual(state.phase, "ready");
            assert.ok(await page.evaluate('document.querySelector("[role=alert]")?.textContent'));
          }
          if (failure === "create") assert.equal(state.documentId, null);
          assert.equal(creationAttempts(), expected,
            `${failure} must not retry creation or create a replacement document`);
          return performance.now() >= deadline;
        }, Boolean, duration + 5000);
      };
      try {
        await page.goto(url.href);
        await wait(`visible ${failure} error`, () => page.evaluate(
          'document.querySelector("[role=alert]")?.textContent'), Boolean, 30_000);
        assert.equal(await page.evaluate('document.querySelector("[data-state=ready]") !== null'), false);
        await stable(false, 1000);
        await page.click('[data-action="close"]');
        await page.waitFor('[data-state="closed"]');
        await stable(true, 500);
        assert.deepEqual(page.errors(), []);
      } finally {
        try { await page.close(); }
        finally { services.rejectHttpWrites(false); }
      }
    }
    const disconnected = await open(documentUrl);
    services.failConnections(true);
    try {
      await wait("visible service disconnection", () => disconnected.evaluate(
        'document.querySelector("[role=alert]")?.textContent'), Boolean);
      assert.notEqual((await snapshot(disconnected)).phase, "ready");
      await disconnected.click('[data-action="close"]');
      await disconnected.waitFor('[data-state="closed"]');
    } finally { services.failConnections(false); }
    for (const page of pages) assert.deepEqual(page.errors(), []);
  });
}
