import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";
import {
  devtoolsEndpoint, findBrowser, sleep, stopBrowser, withPage,
} from "../../../smoke/cdp.mjs";
import { startChecklistServer } from "../../shared_tree_checklist_lustre/serve.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));
const option = process.argv.slice(2);
assert(option.length <= 1 && option.every((arg) =>
  /^--implementation=(watershed|fluid)$/.test(arg)), "Use --implementation=watershed|fluid");
const implementations = option.length ? [option[0].split("=")[1]] : ["watershed", "fluid"];
const field = (key) => `input[data-field=${JSON.stringify(key)}]`;
const badge = (key) => `[data-selection-for=${JSON.stringify(key)}]`;
const action = (name) => `[data-action=${JSON.stringify(name)}]`;
const row = (id) => `[data-milestone-id=${JSON.stringify(id)}]`;
const consoleErrors = new Map();

// Observe real transport traffic and browser failures without replacing delivery.
const instrumentation = `(() => {
  window.__gate = { errors: [], console: [], packets: [], sockets: [], operations: [], submitted: [] };
  addEventListener("error", e => __gate.errors.push(e.message || "resource: " + e.target?.src), true);
  addEventListener("unhandledrejection", e => __gate.errors.push(String(e.reason)));
  const original = console.error.bind(console);
  console.error = (...args) => { __gate.console.push(args.map(String).join(" ")); original(...args); };
  const Native = WebSocket;
  window.WebSocket = new Proxy(Native, { construct(Target, args) {
    const socket = new Target(...args);
    __gate.sockets.push(socket);
    const send = socket.send.bind(socket);
    socket.send = data => {
      if (typeof data === "string" && data.includes("submitOp")) {
        __gate.submitted.push(data);
        try {
          const frame = JSON.parse(data.startsWith("42") ? data.slice(2) : data);
          if (frame[3] === "submitOp" || frame[0] === "submitOp") {
            const visit = value => {
              if (!value || typeof value !== "object") return;
              if (typeof value.clientSequenceNumber === "number" && "contents" in value) {
                __gate.operations.push(value.clientSequenceNumber);
              } else for (const child of Object.values(value)) visit(child);
            };
            visit(frame);
          }
        } catch {}
      }
      return send(data);
    };
    socket.addEventListener("message", e => {
      let meta, sender;
      try {
        if (typeof e.data !== "string") return;
        const frame = JSON.parse(e.data.startsWith("42") ? e.data.slice(2) : e.data);
        if (frame[3] === "signal") {
          meta = frame[4]?.content?.meta;
          sender = frame[4]?.clientId;
        } else if (frame[0] === "signal") {
          const signal = JSON.parse(frame[1].content);
          meta = signal.contents?.content;
          sender = frame[1].clientId;
        }
      } catch { return; }
      if (meta?.name === "Sam" && meta.selected) {
        __gate.packets.push({ time: Date.now(), meta, sender });
        if (__gate.packets.length > 100) __gate.packets.shift();
      }
    });
    // CDP offline does not reliably partition WebSocket reconnects. Close the
    // actual native sockets, including retries, until this test restores B.
    if (__gate.offline) socket.close();
    return socket;
  }});
})();`;

async function evaluate(send, expression) {
  const result = await send("Runtime.evaluate", {
    expression, returnByValue: true, awaitPromise: true,
  });
  assert(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}

function call(send, fn, ...args) {
  return evaluate(send, `(${fn})(...${JSON.stringify(args)})`);
}

async function snapshot(send) {
  const value = await call(send, () => ({
    time: Date.now(),
    status: document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus,
    id: document.querySelector("[data-document-id]")?.dataset.documentId,
    count: Number(document.querySelector("[data-tree-change-count]")?.dataset.treeChangeCount),
    values: Object.fromEntries([...document.querySelectorAll("input[data-field]")].map(e =>
      [e.dataset.field, e.type === "checkbox" ? e.checked : e.value])),
    badges: Object.fromEntries([...document.querySelectorAll("[data-selection-for]")].map(e =>
      [e.dataset.selectionFor, e.textContent.trim()])),
    ids: [...document.querySelectorAll("[data-milestone-id]")].map(e => e.dataset.milestoneId),
    active: document.activeElement?.dataset.field,
    start: document.activeElement?.selectionStart,
    end: document.activeElement?.selectionEnd,
    errors: [...document.querySelectorAll("[data-error]")].map(e => e.textContent),
    browserErrors: window.__gate?.errors ?? [],
    console: window.__gate?.console ?? [],
    packets: window.__gate?.packets ?? [],
    operations: window.__gate?.operations ?? [],
    url: location.href,
  }));
  if (!consoleErrors.has(send)) consoleErrors.set(send, new Set());
  for (const error of value.console) consoleErrors.get(send).add(error);
  assert.deepEqual(value.errors, [], `visible errors: ${JSON.stringify(value)}`);
  assert.deepEqual(value.browserErrors, [], `browser errors: ${JSON.stringify(value)}`);
  return value;
}

async function wait(label, probe, predicate, timeout = 20_000) {
  const deadline = Date.now() + timeout;
  let last;
  while (true) {
    last = await probe();
    if (predicate(last)) return last;
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    await sleep(Math.min(50, remaining));
  }
  throw new Error(`${label} timed out (deadline ${deadline}): ${JSON.stringify(last)}`);
}

const state = (send, label, predicate, timeout) =>
  wait(label, () => snapshot(send), predicate, timeout);
const ready = (send) => state(send, "ready document", s => s.status === "ready" && !!s.id);
const disconnected = async (send) => {
  try {
    return await state(send, "visible disconnect", s =>
      ["disconnected", "reconnecting"].includes(s.status));
  } catch (error) {
    console.error("disconnect transport diagnostics", await call(send, () => ({
      offline: __gate.offline,
      sockets: __gate.sockets.map(s => ({ url: s.url, readyState: s.readyState })),
    })));
    throw error;
  }
};
const value = (send, key, expected) =>
  state(send, `native ${key}=${expected}`, s => s.values[key] === expected);
const awareness = (send, key, name) =>
  state(send, `${name} selects ${key}`, s => s.badges[key]?.includes(name));

async function focus(send, key, start, end = start) {
  await call(send, (selector, start, end) => {
    const input = document.querySelector(selector);
    if (!input || input.disabled) throw new Error("Missing or disabled input " + selector);
    input.focus();
    if (start !== null) {
      input.setSelectionRange(start, end);
      input.dispatchEvent(new Event("select", { bubbles: true }));
    }
  }, field(key), start ?? null, end ?? null);
  await state(send, `focus ${key}`, s => s.active === key);
}

async function type(send, key, text) {
  await focus(send, key, 0, 10000);
  await send("Input.insertText", { text });
  await value(send, key, text);
}

async function click(send, selector) {
  await call(send, selector => {
    const button = document.querySelector(selector);
    if (!button || button.disabled) throw new Error("Missing or disabled control " + selector);
    button.click();
  }, selector);
}

async function prepare(send, url) {
  await send("Runtime.enable");
  await send("Page.enable");
  await send("Network.enable");
  await send("Page.addScriptToEvaluateOnNewDocument", { source: instrumentation });
  await send("Page.navigate", { url });
  return ready(send);
}

async function mark(send, key, start = 1, end = 4) {
  await focus(send, key, start, end);
  await call(send, (f, b) => {
    window.__retained = {
      input: document.querySelector(f), badge: document.querySelector(b),
      text: document.querySelector(f).value,
    };
  }, field(key), badge(key));
}

async function unchanged(send, key, start = 1, end = 4, text) {
  await state(send, `identity/focus/native range of ${key}`, s =>
    s.active === key && s.start === start && s.end === end &&
    (text === undefined || s.values[key] === text));
  assert.equal(await call(send, (f, b) =>
    __retained.input === document.querySelector(f) &&
    __retained.badge === document.querySelector(b) &&
    (document.querySelector(f).value === __retained.text),
  field(key), badge(key)), true, `retained input and badge identity: ${key}`);
}

async function composition(send, key, event, text, isComposing = false) {
  await call(send, (selector, event, text, isComposing) => {
    const input = document.querySelector(selector);
    if (text != null) input.value = text;
    input.dispatchEvent(event === "input"
      ? new InputEvent("input", { bubbles: true, data: text, inputType: "insertCompositionText", isComposing })
      : new CompositionEvent(event, { bubbles: true, data: text ?? "" }));
  }, field(key), event, text, isComposing);
}

async function offline(send, enabled) {
  await call(send, enabled => { __gate.offline = enabled; }, enabled);
  await send("Network.emulateNetworkConditions", {
    offline: enabled, latency: 0, downloadThroughput: -1, uploadThroughput: -1,
  });
  if (enabled) await call(send, () => {
    for (const socket of __gate.sockets) if (socket.readyState < 2) socket.close();
  });
}

async function scenarios(a, b, sharedUrl) {
  const pass = (number, detail) => console.log(`  PASS ${number}: ${detail}`);
  const initialA = await snapshot(a);
  const initialB = await snapshot(b);
  assert.deepEqual(initialA.values, initialB.values);
  assert.equal(initialA.values.title, "Release brief");
  assert.equal(initialA.values["owner.name"], "Alex");
  assert.equal(initialA.values["owner.email"], "alex@example.test");
  assert.equal(initialA.values["schedule.start"], "2026-11-02");
  assert.equal(initialA.values["schedule.target"], "2026-11-16");
  assert.equal(initialA.ids.length, 2);
  assert.equal(initialA.values[`milestone/${initialA.ids[0]}/title`], "Agree scope");
  assert.equal(initialA.values[`milestone/${initialA.ids[1]}/title`], "Ship preview");
  for (const id of initialA.ids) assert.equal(initialA.values[`milestone/${id}/completed`], false);
  assert.equal(initialA.values["review.reviewer"], undefined);
  pass(1, `created and loaded ${initialA.id}; identical nested sample`);

  await type(a, "owner.name", "Morgan");
  await type(b, "schedule.target", "2026-11-23");
  await value(b, "owner.name", "Morgan");
  await value(a, "schedule.target", "2026-11-23");
  await awareness(a, "schedule.target", "Sam");
  await awareness(b, "owner.name", "Morgan");
  assert.equal((await snapshot(a)).active, "owner.name");
  assert.equal((await snapshot(b)).active, "schedule.target");
  pass(2, "native remote values and reciprocal awareness before blur");

  await mark(a, "owner.name");
  await type(b, "schedule.start", "2026-11-03");
  await value(a, "schedule.start", "2026-11-03");
  await awareness(a, "schedule.start", "Sam");
  await unchanged(a, "owner.name", 1, 4, "Morgan");
  pass(3, "input/badge identities, focus, text and non-collapsed selection retained");

  await focus(b, "owner.name");
  await awareness(a, "owner.name", "Sam");
  await awareness(b, "owner.name", "Morgan");
  await Promise.all([type(a, "owner.name", "Morgan concurrent"), type(b, "owner.name", "Sam concurrent")]);
  await wait("same-field resolved agreement", async () =>
    Promise.all([snapshot(a), snapshot(b)]), ([x, y]) =>
    x.values["owner.name"] === y.values["owner.name"] &&
    ["Morgan concurrent", "Sam concurrent"].includes(x.values["owner.name"]));
  pass(4, "advisory same-field contention; agreement without a chosen winner");

  await focus(a, "owner.name");
  const operationsBeforeIME = (await snapshot(a)).operations.length;
  await composition(a, "owner.name", "compositionstart");
  await composition(a, "owner.name", "input", "編集中", true);
  await type(b, "owner.name", "Remote during IME");
  await type(b, "schedule.target", "2026-11-24");
  await value(a, "schedule.target", "2026-11-24");
  await value(a, "owner.name", "編集中");
  const composing = await snapshot(a);
  // B's later delivered field edit fences the earlier partial composing input.
  assert.equal(composing.operations.length, operationsBeforeIME,
    "partial composition must not submit a durable operation");
  // Remote edits legitimately added callbacks while A was composing.
  const beforeIME = composing.count;
  await composition(a, "owner.name", "compositionend", "完成");
  await value(b, "owner.name", "完成");
  await state(a, "one composition tree callback", s => s.count === beforeIME + 1);
  await composition(a, "owner.name", "input", "完成");
  // A later real remote operation provides a delivery fence for duplicate suppression.
  await type(b, "schedule.start", "2026-11-04");
  await value(a, "schedule.start", "2026-11-04");
  assert.equal((await snapshot(a)).count, beforeIME + 2);
  const operationsAfterIME = (await snapshot(a)).operations.length;
  assert.equal(operationsAfterIME, operationsBeforeIME + 1,
    `composition and duplicate must submit exactly one durable operation; ${await call(a, () => JSON.stringify(__gate.submitted.slice(-2)))}`);
  await type(b, "owner.name", "Long selection text");
  await value(a, "owner.name", "Long selection text");
  await focus(a, "owner.name", 5, 12);
  await type(b, "owner.name", "Hi");
  await value(a, "owner.name", "Hi");
  await state(a, "shortened value clamps native range", s =>
    s.active === "owner.name" && s.start === 2 && s.end === 2);
  pass(5, "IME isolation, other-field delivery, one publish plus duplicate suppression, clamping");

  await click(b, action("add-review"));
  await value(a, "review.reviewer", "");
  await type(a, "review.reviewer", "Taylor");
  await click(b, field("review.approved"));
  await value(b, "review.reviewer", "Taylor");
  await value(a, "review.approved", true);
  await focus(a, "review.reviewer");
  await awareness(b, "review.reviewer", "Morgan");
  await call(a, selector => { window.__staleReview = document.querySelector(selector); }, field("review.reviewer"));
  await click(b, action("remove-review"));
  await state(a, "review controls and badges removed", s =>
    !("review.reviewer" in s.values) && !s.badges["review.reviewer"]);
  await click(b, action("add-review"));
  await value(a, "review.reviewer", "");
  const reviewCount = (await snapshot(a)).count;
  await call(a, () => {
    if (__staleReview.isConnected) throw new Error("Removed review input is still connected");
    __staleReview.value = "stale review";
    __staleReview.dispatchEvent(new InputEvent("input", { bubbles: true }));
  });
  await type(b, "review.reviewer", "Replacement");
  await value(a, "review.reviewer", "Replacement");
  assert.equal((await snapshot(a)).count, reviewCount + 1, "stale review input cannot write");
  assert(!((await snapshot(b)).badges["review.reviewer"] ?? "").includes("Morgan"));
  pass(6, "review appears, separate edits, removal, recreation and retained stale input isolation");

  const [preceding, selected] = initialA.ids;
  const key = `milestone/${selected}/title`;
  await mark(a, key);
  await awareness(b, key, "Morgan");
  await call(b, selector => { window.__selectedBadge = document.querySelector(selector); }, badge(key));
  await click(b, `${row(preceding)} ${action("remove-milestone")}`);
  await state(a, "preceding milestone removed", s => !s.ids.includes(preceding));
  await unchanged(a, key, 1, 4, "Ship preview");
  await awareness(b, key, "Morgan");
  assert.equal(await call(b, selector =>
    __selectedBadge === document.querySelector(selector), badge(key)), true);
  await Promise.all([type(a, key, "Existing survives append"), click(b, action("add-milestone"))]);
  await value(b, key, "Existing survives append");
  const appended = await state(a, "fresh append delivered", s => s.ids.length === 2);
  assert.notEqual(appended.ids[1], preceding);
  assert.notEqual(appended.ids[1], selected);
  await call(a, selector => { window.__staleMilestone = document.querySelector(selector); }, field(key));
  await awareness(b, key, "Morgan");
  await click(b, `${row(selected)} ${action("remove-milestone")}`);
  await state(a, "selected milestone controls/badges gone", s =>
    !(key in s.values) && !(key in s.badges));
  const milestoneCount = (await snapshot(a)).count;
  await call(a, () => {
    if (__staleMilestone.isConnected) throw new Error("Removed milestone input is still connected");
    __staleMilestone.value = "stale milestone";
    __staleMilestone.dispatchEvent(new InputEvent("input", { bubbles: true }));
  });
  const surviving = `milestone/${appended.ids[1]}/title`;
  await type(b, surviving, "Surviving milestone");
  await value(a, surviving, "Surviving milestone");
  assert.equal((await snapshot(a)).count, milestoneCount + 1, "stale milestone input cannot write");
  pass(10, "stable ID/input/badge after preceding removal, concurrent append/edit, selected removal");

  // Reopen B while A already selects: awareness must come from the live heartbeat.
  await focus(a, "owner.email");
  await call(b, () => document.activeElement.blur());
  await state(a, "blur clears remote selection", s => Object.values(s.badges).every(x => !x.includes("Sam")));
  await snapshot(b);
  await b("Page.reload");
  await ready(b);
  await state(b, "late join observes selection within heartbeat allowance", s =>
    s.badges["owner.email"]?.includes("Morgan"), 4500);
  await focus(b, "schedule.target");
  await awareness(a, "schedule.target", "Sam");
  const presenceBaseline = await Promise.all([snapshot(a), snapshot(b)]);
  const counters = s => [s.count, s.operations.length];
  const counts = presenceBaseline.map(counters);
  await focus(a, "title");
  await focus(b, "schedule.start");
  await awareness(a, "schedule.start", "Sam");
  await awareness(b, "title", "Morgan");
  const selectedPacket = (await snapshot(a)).packets.at(-1);
  assert.equal(selectedPacket?.meta.selected.field, "schedule.start");
  await state(a, "real selection heartbeat traffic", s => s.packets.some(p =>
    p.time > selectedPacket.time && p.meta.token === selectedPacket.meta.token &&
    p.meta.selected.field === "schedule.start"), 4500);
  assert.deepEqual((await Promise.all([snapshot(a), snapshot(b)])).map(counters), counts);
  pass(8, "focus changes and real heartbeat produce no tree callbacks in either client");

  await call(a, () => {
    window.__expiry = null;
    window.__expiryObserver = new MutationObserver(() => {
      if (![...document.querySelectorAll("[data-selection-for]")].some(e => e.textContent.includes("Sam"))) {
        window.__expiry = Date.now();
        __expiryObserver.disconnect();
      }
    });
    __expiryObserver.observe(document.body, { subtree: true, childList: true, characterData: true });
  });
  await offline(b, true);
  await disconnected(b);
  const lastPacket = (await snapshot(a)).packets.at(-1);
  assert(lastPacket, "received a real remote selection packet");
  console.log(`  last received selection: ${JSON.stringify(lastPacket)}`);
  await wait("ungraceful selection expiry", async () => ({
    state: await snapshot(a), disappeared: await call(a, () => __expiry),
  }), s => s.state.status === "ready" && s.disappeared !== null &&
    Object.values(s.state.badges).every(x => !x.includes("Sam")),
  Math.max(1, 8500 - (Date.now() - lastPacket.time)));
  const elapsed = await call(a, () => __expiry) - lastPacket.time;
  assert(elapsed >= 6500 && elapsed <= 8500, `expiry outside TTL/sweep window: ${elapsed}ms`);
  console.log(`  expiry observed ${elapsed}ms after last received selection`);
  await offline(b, false);
  await ready(b);
  await focus(b, "schedule.target");
  await awareness(a, "schedule.target", "Sam");
  pass(7, "late join heartbeat, blur, abrupt disconnect expiry and fresh reconnect awareness");

  await focus(b, "owner.name");
  const durable = (await snapshot(a)).values["owner.name"];
  await composition(b, "owner.name", "compositionstart");
  await composition(b, "owner.name", "input", "CANCELED OFFLINE", true);
  await offline(b, true);
  await disconnected(b);
  await composition(b, "owner.name", "compositionend", "CANCELED OFFLINE");
  await composition(b, "owner.name", "input", "CANCELED OFFLINE");
  await offline(b, false);
  await ready(b);
  await type(a, "schedule.target", "2026-11-25");
  await value(b, "schedule.target", "2026-11-25");
  await value(a, "owner.name", durable);
  await value(b, "owner.name", durable);

  await call(a, () => document.activeElement.blur());
  await call(b, () => document.activeElement.blur());
  await state(a, "presence cleared before persistence check", s => Object.values(s.badges).every(x => !x));
  await state(b, "peer presence cleared", s => Object.values(s.badges).every(x => !x));
  const saved = (await snapshot(a)).values;
  assert.deepEqual((await snapshot(b)).values, saved);
  await call(b, selector => { window.__closedInput = document.querySelector(selector); }, field("owner.name"));
  // Close both sessions before reload so the service, not a live peer, supplies content.
  await click(a, action("close"));
  await click(b, action("close"));
  await state(a, "closed A", s => s.status === "closed");
  await state(b, "closed B", s => s.status === "closed");
  assert.equal(await call(b, () =>
    [...document.querySelectorAll("input,button[data-action]:not([data-action=close])")]
      .every(e => e.disabled)), true, "closed controls are absent or disabled");
  const closedCount = (await snapshot(b)).count;
  await call(b, () => {
    for (const input of document.querySelectorAll("input")) {
      input.value = "AFTER CLOSE";
      input.dispatchEvent(new InputEvent("input", { bubbles: true }));
    }
    __closedInput.value = "AFTER CLOSE";
    __closedInput.dispatchEvent(new InputEvent("input", { bubbles: true }));
    window.__staleReview?.dispatchEvent(new InputEvent("input", { bubbles: true }));
    window.__staleMilestone?.dispatchEvent(new InputEvent("input", { bubbles: true }));
  });
  await a("Page.reload");
  await ready(a);
  const recovered = await snapshot(a);
  assert.equal(new URL(recovered.url).searchParams.get("document"), new URL(sharedUrl).searchParams.get("document"));
  assert.deepEqual(recovered.values, saved, "service recovery after both sessions closed");
  assert(Object.values(recovered.badges).every(x => !x), "no awareness after clean close");
  assert.equal((await snapshot(b)).status, "closed", "late callbacks cannot reopen B");
  assert.equal((await snapshot(b)).count, closedCount);
  await click(a, action("close"));
  pass(8, "same-URL reload recovers real service content after clean close");
  pass(9, "visible disconnect/ready/closed, canceled offline composition, inert close and no late reopen");
  for (const [name, send] of [["A", a], ["B", b]]) {
    const final = await snapshot(send);
    console.log(`  ${name} browser errors=${final.browserErrors.length}; console errors=${JSON.stringify([...consoleErrors.get(send)])}`);
  }

  await a("Page.navigate", { url: sharedUrl });
  await ready(a);
  const peerUrl = new URL(sharedUrl);
  peerUrl.searchParams.set("name", "Sam");
  await b("Page.navigate", { url: peerUrl.href });
  await ready(b);
  await focus(b, "owner.email", 1, 4);
  await type(a, "title", "Recovery with live selection");
  await value(b, "title", "Recovery with live selection");
  await awareness(a, "owner.email", "Sam");
  await awareness(b, "title", "Morgan");
  await state(b, "non-collapsed selection retained through delivered content", s =>
    s.active === "owner.email" && s.start === 1 && s.end === 4);
  const savedWithAwareness = (await snapshot(a)).values;
  assert.deepEqual((await snapshot(b)).values, savedWithAwareness);
  // Cut transport before unloading, so no blur/close can deliver an empty selection.
  // The delivered title assignment above establishes real saved content while
  // both clients still have nonempty awareness, without mocking persistence.
  await offline(b, true);
  await offline(a, true);
  for (const send of [b, a]) {
    await send("Page.navigate", { url: "about:blank" });
    await wait("old document unloaded", () => call(send, () => location.href),
      url => url === "about:blank");
  }
  await offline(a, false);
  await a("Page.navigate", { url: sharedUrl });
  await ready(a);
  const isolated = await snapshot(a);
  assert.equal(new URL(isolated.url).searchParams.get("document"), new URL(sharedUrl).searchParams.get("document"));
  assert.deepEqual(isolated.values, savedWithAwareness, "service recovery after abrupt unload with live awareness");
  assert(Object.values(isolated.badges).every(x => !x), "isolated recovery must not restore saved awareness");
  assert.equal(await call(b, () => location.href), "about:blank", "no live peer can supply recovery");
  await click(a, action("close"));
  pass(8, "live selections survive until transport cut; isolated service recovery restores content, not awareness");

  await offline(b, false);
  const missing = new URL(sharedUrl);
  missing.searchParams.set("document", crypto.randomUUID());
  await b("Page.navigate", { url: missing.href });
  const failure = await wait("visible missing-document failure", () => call(b, () => ({
    status: document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus,
    errors: [...document.querySelectorAll("[data-error]")].map(e => e.textContent),
    browserErrors: window.__gate?.errors ?? [],
    console: window.__gate?.console ?? [],
    enabled: [...document.querySelectorAll("input")].some(e => !e.disabled),
    url: location.href,
  })), s => ["failed", "error"].includes(s.status) && s.errors.some(Boolean));
  assert.deepEqual(failure.browserErrors, []);
  assert.equal(failure.enabled, false);
  assert.equal(new URL(failure.url).searchParams.get("document"), missing.searchParams.get("document"));
  console.log(`  PASS 9: missing document shows ${failure.status}: ${JSON.stringify(failure.errors)}; console=${JSON.stringify(failure.console)}`);
  await click(b, action("close"));
  await wait("failed session can close", () => call(b, () =>
    document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus), s => s === "closed");
  assert.deepEqual(await call(b, () => __gate.errors), []);
}

async function command(endpoint, method, params = {}) {
  return withPage(endpoint, 30_000, `${method} timeout`, send => send(method, params));
}

async function targetEndpoint(endpoint, id) {
  return wait("CDP target", async () => {
    const response = await fetch(`http://${new URL(endpoint).host}/json/list`);
    return (await response.json()).find(t => t.id === id)?.webSocketDebuggerUrl;
  }, Boolean);
}

function configuration(implementation) {
  const fluid = implementation === "fluid";
  const appRoot = fluid ? resolve(root, "fluid") : root;
  const bundle = fluid ? "dist/index.js" : "dist/shared_tree_project_brief_lustre.mjs";
  return { appRoot, bundle, port: fluid ? 8081 : 8080,
    service: fluid ? "http://localhost:7070/" : "http://127.0.0.1:4000/health" };
}

async function preflight(implementation) {
  const { appRoot, bundle, service } = configuration(implementation);
  assert(existsSync(resolve(appRoot, bundle)), `Missing ${implementation} bundle; run pnpm build in ${appRoot}`);
  const response = await fetch(service, { signal: AbortSignal.timeout(5000) });
  assert(response.ok, `Required service ${service}: ${response.status}`);
  console.log(`${implementation}: service ${service} ${response.status}`);
}

async function run(implementation, browser) {
  const { appRoot, bundle, port } = configuration(implementation);
  console.log(`${implementation}: Chromium ${browser}`);
  let server, chrome, endpoint;
  const contexts = [];
  const profile = resolve(root, `build/task-6-browser-${implementation}-${process.pid}`);
  mkdirSync(profile, { recursive: true });
  try {
    const origin = `http://127.0.0.1:${port}/`;
    let existing;
    try {
      existing = await fetch(origin, { signal: AbortSignal.timeout(1500) });
    } catch (error) {
      if (error.cause?.code !== "ECONNREFUSED") throw error;
    }
    if (existing) {
      assert(existing.ok, `Existing static server ${origin}: ${existing.status}`);
      console.log(`${implementation}: reuse existing static server ${origin}`);
    } else {
      server = await startChecklistServer({ appRoot, port });
    }
    const html = await (existing ?? await fetch(origin)).text();
    assert(html.includes("./" + bundle),
      "static server must serve the selected implementation");
    const servedBundle = await fetch(origin + bundle);
    assert(servedBundle.ok);
    assert.equal((await servedBundle.text()) === readFileSync(resolve(appRoot, bundle), "utf8"), true,
      "static server must serve the current build, not an old or different app");
    chrome = spawn(browser, [
      "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
      "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0",
      "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
      "--user-data-dir=" + profile, "about:blank",
    ], { stdio: ["ignore", "pipe", "pipe"] });
    chrome.stdout.resume();
    endpoint = await devtoolsEndpoint(chrome);
    async function page() {
      const { browserContextId } = await command(endpoint, "Target.createBrowserContext");
      contexts.push(browserContextId);
      const { targetId } = await command(endpoint, "Target.createTarget", {
        url: "about:blank", browserContextId,
      });
      return targetEndpoint(endpoint, targetId);
    }
    const [aEndpoint, bEndpoint] = await Promise.all([page(), page()]);
    await withPage(aEndpoint, 240_000, "A acceptance timeout", async a => {
      const created = await prepare(a, origin + "?name=Morgan");
      const url = new URL(created.url);
      url.searchParams.set("name", "Sam");
      await withPage(bEndpoint, 240_000, "B acceptance timeout", async b => {
        await prepare(b, url.href);
        await scenarios(a, b, created.url);
      });
    });
    console.log(`${implementation}: all ten acceptance cases PASS`);
  } finally {
    if (endpoint) for (const browserContextId of contexts) {
      await command(endpoint, "Target.disposeBrowserContext", { browserContextId }).catch(() => {});
    }
    if (chrome) await stopBrowser(chrome);
    if (server) await new Promise(done => server.close().once("close", done));
    rmSync(profile, { recursive: true, force: true });
    console.log(`${implementation}: owned contexts/browser/profile cleaned; ${server ? "owned static server closed" : "existing static server untouched"}`);
  }
}

try {
  const browser = findBrowser();
  assert(browser, "Chromium REQUIRED. Set WATERSHED_CHROME to an existing executable; skipping is not acceptance.");
  for (const implementation of implementations) await preflight(implementation);
  for (const implementation of implementations) await run(implementation, browser);
} catch (error) {
  console.error(error.stack ?? error);
  process.exitCode = 1;
}
