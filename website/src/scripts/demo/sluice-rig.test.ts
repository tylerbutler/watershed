import assert from "node:assert/strict";
import test from "node:test";
import { createSluiceRig, type Rig, type RigConfig } from "./sluice-rig.ts";
import { writeSequenceMarker } from "./sluice-runtime.ts";
import type { DeliveryScheduler } from "./sluice-transport.ts";

class FakeScheduler implements DeliveryScheduler {
  #now = 0;
  #nextHandle = 1;
  #timers = new Map<number, { at: number; callback: () => void }>();

  get pendingCount(): number {
    return this.#timers.size;
  }

  now(): number {
    return this.#now;
  }

  set(delayMs: number, callback: () => void): unknown {
    const handle = this.#nextHandle;
    this.#nextHandle += 1;
    this.#timers.set(handle, { at: this.#now + delayMs, callback });
    return handle;
  }

  clear(handle: unknown): void {
    if (typeof handle === "number") this.#timers.delete(handle);
  }

  runNext(): void {
    const next = [...this.#timers.entries()].sort(
      ([leftHandle, left], [rightHandle, right]) =>
        left.at - right.at || leftHandle - rightHandle,
    )[0];
    assert.ok(next, "expected a pending timer");
    const [handle, timer] = next;
    this.#timers.delete(handle);
    this.#now = timer.at;
    timer.callback();
  }

  runAll(): void {
    while (this.#timers.size > 0) this.runNext();
  }
}

class FakeClassList {
  add(): void {}
  remove(): void {}
}

class FakeElement {
  children: FakeElement[] = [];
  className = "";
  classList = new FakeClassList();
  disabled = false;
  innerHTML = "";
  scrollHeight = 0;
  scrollTop = 0;
  textContent = "";
  #queries = new Map<string, FakeElement>();

  addEventListener(): void {}

  animate(): { onfinish: (() => void) | null } {
    return { onfinish: null };
  }

  append(...children: FakeElement[]): void {
    this.children.push(...children);
  }

  appendChild(child: FakeElement): FakeElement {
    this.children.push(child);
    return child;
  }

  getBoundingClientRect() {
    return { height: 0, left: 0, top: 0, width: 0 };
  }

  get lastChild(): FakeElement | null {
    return this.children.at(-1) ?? null;
  }

  get offsetWidth(): number {
    return 0;
  }

  prepend(child: FakeElement): void {
    this.children.unshift(child);
  }

  querySelector(selector: string): FakeElement | null {
    return this.#queries.get(selector) ?? null;
  }

  querySelectorAll(): FakeElement[] {
    return [];
  }

  remove(): void {}

  replaceChildren(...children: FakeElement[]): void {
    this.children = children;
  }

  setQuery(selector: string, element: FakeElement): void {
    this.#queries.set(selector, element);
  }
}

let documentNumber = 0;

function installFakeDom() {
  const rig = new FakeElement();
  const status = new FakeElement();
  const section = new FakeElement();
  rig.setQuery("[data-flow-layer]", new FakeElement());
  rig.setQuery("[data-seq-node]", new FakeElement());
  rig.setQuery("[data-seq-counter]", new FakeElement());
  rig.setQuery("[data-op-log]", new FakeElement());
  rig.setQuery('[data-client="a"]', new FakeElement());
  rig.setQuery('[data-client="b"]', new FakeElement());

  const document = {
    createElement: () => new FakeElement(),
    querySelector(selector: string) {
      if (selector === "[data-test-rig]") return rig;
      if (selector === "[data-test-status]") return status;
      if (selector === "#test-demo") return section;
      return null;
    },
  };
  const globals = {
    document: globalThis.document,
    Element: globalThis.Element,
    HTMLElement: globalThis.HTMLElement,
    HTMLButtonElement: globalThis.HTMLButtonElement,
    HTMLInputElement: globalThis.HTMLInputElement,
    HTMLOListElement: globalThis.HTMLOListElement,
    window: globalThis.window,
  };
  Object.assign(globalThis, {
    document,
    Element: FakeElement,
    HTMLElement: FakeElement,
    HTMLButtonElement: FakeElement,
    HTMLInputElement: FakeElement,
    HTMLOListElement: FakeElement,
    window: { matchMedia: () => ({ matches: true }) },
  });

  return {
    status,
    restore() {
      Object.assign(globalThis, globals);
    },
  };
}

function createTestRig(
  scheduler: FakeScheduler,
  overrides: Partial<RigConfig> = {},
): { rig: Rig; status: FakeElement; restore: () => void } {
  const dom = installFakeDom();
  documentNumber += 1;
  const rig = createSluiceRig(
    {
      rig: "[data-test-rig]",
      status: "[data-test-status]",
      section: "#test-demo",
      control: "test",
      document: `test-${documentNumber}`,
      clientIds: ["a", "b"],
      clientLabel: { a: "Client A", b: "Client B" },
      setup() {},
      render() {},
      canonical: () => "same",
      ...overrides,
    },
    scheduler,
  );
  assert.ok(rig);
  return { rig, status: dom.status, restore: dom.restore };
}

function submitMarker(rig: Rig, marker: string, value: number): void {
  rig.submit(
    rig.clients.a,
    marker,
    () => writeSequenceMarker(rig.clients.a.doc, value),
    marker,
  );
}

test("step and settleNow clear the same pending marker", () => {
  const scheduler = new FakeScheduler();
  const { rig, restore } = createTestRig(scheduler);
  try {
    submitMarker(rig, "first", 1);
    rig.step();
    scheduler.runAll();
    assert.deepEqual(rig.clients.a.pending, []);

    submitMarker(rig, "second", 2);
    rig.settleNow();
    assert.deepEqual(rig.clients.a.pending, []);
  } finally {
    rig.reset();
    restore();
  }
});

test("reset cancels old deliveries and boots fresh documents", () => {
  const scheduler = new FakeScheduler();
  const beforeDeliveries: number[] = [];
  const { rig, restore } = createTestRig(scheduler, {
    onBeforeDeliver: (delivery) => {
      beforeDeliveries.push(delivery.sequence_number);
    },
  });
  try {
    const oldDocuments = Object.values(rig.clients).map((client) => client.doc);
    submitMarker(rig, "old", 1);
    assert.equal(scheduler.pendingCount, 1);

    rig.reset();
    scheduler.runAll();

    assert.equal(scheduler.pendingCount, 0);
    assert.deepEqual(beforeDeliveries, []);
    assert.deepEqual(rig.clients.a.pending, []);
    assert.ok(
      Object.values(rig.clients).every(
        (client, index) => client.doc !== oldDocuments[index],
      ),
    );
  } finally {
    rig.reset();
    restore();
  }
});

test("settleNow invokes onBeforeDeliver for every landed frame", () => {
  const scheduler = new FakeScheduler();
  const beforeRecipients: string[] = [];
  const { rig, restore } = createTestRig(scheduler, {
    onBeforeDeliver: (_delivery, _author, to) => {
      beforeRecipients.push(to.id);
    },
  });
  try {
    submitMarker(rig, "settle", 1);
    rig.settleNow();

    assert.deepEqual(beforeRecipients.sort(), ["a", "b"]);
    assert.deepEqual(rig.clients.a.pending, []);
  } finally {
    rig.reset();
    restore();
  }
});

test("status becomes converged only after queue, animation, and markers are empty", () => {
  const scheduler = new FakeScheduler();
  const { rig, status, restore } = createTestRig(scheduler);
  try {
    assert.match(status.innerHTML, /Converged/);

    submitMarker(rig, "pending", 1);
    assert.match(status.innerHTML, /Revising/);

    scheduler.runNext();
    assert.equal(rig.serverPending(), false);
    assert.deepEqual(rig.clients.a.pending, ["pending"]);
    assert.match(status.innerHTML, /Revising/);

    scheduler.runAll();
    assert.deepEqual(rig.clients.a.pending, []);
    assert.match(status.innerHTML, /Converged/);
  } finally {
    rig.reset();
    restore();
  }
});
