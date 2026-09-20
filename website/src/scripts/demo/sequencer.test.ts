import assert from "node:assert/strict";
import test from "node:test";
import { createSequencer, type SeqClient } from "./sequencer.ts";
import type { DeliveryScheduler } from "./sluice-transport.ts";

type Client = SeqClient & { id: string };

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

function createClients(): Record<string, Client> {
  return {
    a: { id: "a", el: {} as HTMLElement, lastArrival: 0 },
    b: { id: "b", el: {} as HTMLElement, lastArrival: 0 },
  };
}

function createTestSequencer(
  scheduler: FakeScheduler,
  options: {
    clients?: Record<string, Client>;
    isLinkUp?: (client: Client) => boolean;
    onHold?: (client: Client, deliver: () => void) => void;
  } = {},
) {
  return createSequencer(
    {
      clients: options.clients ?? createClients(),
      seqNode: {} as HTMLElement,
      flow: { animateDot() {} },
      controls: {
        animSpeed: 1,
        sampleLatency: () => 0,
        paced: (duration) => duration,
      },
      onChange() {},
      isLinkUp: options.isLinkUp,
      onHold: options.onHold,
    },
    scheduler,
  );
}

test("does not begin an operation that became stale inside the transport", () => {
  const scheduler = new FakeScheduler();
  const sequenced: string[] = [];
  let stale = false;
  const sequencer = createTestSequencer(scheduler);

  sequencer.send({
    originId: "a",
    guard: () => () => stale,
    onSequence(sequence) {
      sequenced.push(`stale:${sequence}`);
      return undefined;
    },
    onDeliver() {},
  });
  scheduler.runNext();
  stale = true;
  scheduler.runAll();

  sequencer.send({
    originId: "a",
    onSequence(sequence) {
      sequenced.push(`current:${sequence}`);
      return undefined;
    },
    onDeliver() {},
  });
  scheduler.runAll();

  assert.deepEqual(sequenced, ["current:2"]);
});

test("reset cancels queued delivery and restarts logical sequence numbers", () => {
  const scheduler = new FakeScheduler();
  const sequencer = createTestSequencer(scheduler);
  const sequenced: number[] = [];
  const delivered: number[] = [];

  sequencer.send({
    originId: "a",
    onSequence(sequence) {
      sequenced.push(sequence);
      return sequence;
    },
    onDeliver(_target, { extra }) {
      delivered.push(extra);
    },
  });
  scheduler.runNext();
  assert.equal(scheduler.pendingCount, 1);

  sequencer.reset();
  assert.equal(scheduler.pendingCount, 0);

  sequencer.send({
    originId: "a",
    onSequence(sequence) {
      sequenced.push(sequence);
      return sequence;
    },
    onDeliver(_target, { extra }) {
      delivered.push(extra);
    },
  });
  scheduler.runAll();

  assert.deepEqual(sequenced, [1]);
  assert.deepEqual(delivered, [1, 1]);
  assert.equal(sequencer.sn, 1);
});

test("one operation reaches every connected client in one wave", () => {
  const scheduler = new FakeScheduler();
  const sequencer = createTestSequencer(scheduler);
  const delivered: string[] = [];

  sequencer.send({
    originId: "a",
    onSequence: (sequence) => sequence,
    onDeliver(target, { seq }) {
      delivered.push(`${target.id}:${seq}`);
    },
  });

  scheduler.runNext();
  scheduler.runNext();
  assert.equal(delivered.length, 0);
  assert.equal(scheduler.pendingCount, 2);

  scheduler.runAll();
  assert.deepEqual(delivered.sort(), ["a:1", "b:1"]);
});

test("held links do not deliver until their supplied callback runs", () => {
  const scheduler = new FakeScheduler();
  const held: Array<{ id: string; deliver: () => void }> = [];
  const delivered: string[] = [];
  const sequencer = createTestSequencer(scheduler, {
    isLinkUp: () => false,
    onHold: (client, deliver) => held.push({ id: client.id, deliver }),
  });

  sequencer.send({
    originId: "a",
    onSequence: (sequence) => sequence,
    onDeliver(target) {
      delivered.push(target.id);
    },
  });
  scheduler.runAll();

  assert.deepEqual(delivered, []);
  assert.deepEqual(held.map(({ id }) => id).sort(), ["a", "b"]);

  for (const hop of held) hop.deliver();
  assert.deepEqual(delivered.sort(), ["a", "b"]);
});
