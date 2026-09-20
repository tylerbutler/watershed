import assert from "node:assert/strict";
import test from "node:test";
import { writeSequenceMarker } from "./sluice-runtime.ts";
import {
  createDeliveryEngine,
  createSluiceNetwork,
  drainDeliveries,
  peekDelivery,
  stepDeliveryWave,
  type DeliveryScheduler,
  type DeliveryEngine,
  type SluiceDelivery,
  type SluiceNetwork,
} from "./sluice-transport.ts";

class FakeScheduler implements DeliveryScheduler {
  #now = 0;
  #nextHandle = 1;
  #timers = new Map<
    number,
    { at: number; callback: () => void }
  >();

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

function createNetwork(name: string): SluiceNetwork {
  return createSluiceNetwork({
    tenant: "website",
    document: name,
    clientIds: ["a", "b"],
  });
}

function enqueueOperations(network: SluiceNetwork, count: number): void {
  for (let value = 1; value <= count; value += 1) {
    writeSequenceMarker(network.documents.a, value);
  }
}

function deliverySignature(
  network: SluiceNetwork,
  delivery: SluiceDelivery,
): readonly [string, number, string, boolean] {
  return [
    delivery.event,
    delivery.sequence_number,
    network.sidToId[delivery.to] ?? delivery.to,
    delivery.author === delivery.to,
  ];
}

test("connects peers and drains one sequenced operation as a delivery wave", () => {
  const network = createNetwork("transport-test");
  assert.deepEqual(Object.keys(network.documents), ["a", "b"]);
  assert.deepEqual(Object.values(network.sidToId).sort(), ["a", "b"]);

  writeSequenceMarker(network.documents.a, 1);
  const first = peekDelivery(network);
  assert.ok(first);
  assert.equal(Object.getPrototypeOf(first), Object.prototype);
  assert.deepEqual(Object.keys(first).sort(), [
    "author",
    "event",
    "sequence_number",
    "to",
  ]);

  const before: number[] = [];
  const wave = stepDeliveryWave(network, (delivery) => {
    before.push(delivery.sequence_number);
  });
  assert.ok(wave.length > 0);
  assert.ok(wave.every(
    (delivery) => delivery.sequence_number === wave[0].sequence_number,
  ));
  assert.deepEqual(before, wave.map((delivery) => delivery.sequence_number));
  assert.deepEqual(drainDeliveries(network), []);
});

test("schedule keeps at most one pending delivery timer", () => {
  const network = createNetwork("engine-schedule");
  enqueueOperations(network, 2);
  const scheduler = new FakeScheduler();
  const waves: Array<readonly SluiceDelivery[]> = [];
  const engine = createDeliveryEngine({
    network,
    scheduler,
    onWave: (deliveries) => waves.push(deliveries),
  });

  engine.schedule(5);
  engine.schedule(5);
  assert.equal(engine.pending, true);
  assert.equal(scheduler.pendingCount, 1);

  scheduler.runNext();
  assert.equal(waves.length, 1);
  assert.equal(engine.pending, false);
  assert.equal(scheduler.pendingCount, 0);
  assert.equal(scheduler.now(), 5);
  assert.ok(peekDelivery(network));
});

test("step delivers one complete operation wave", () => {
  const network = createNetwork("engine-step");
  enqueueOperations(network, 2);
  const scheduler = new FakeScheduler();
  const before: SluiceDelivery[] = [];
  const waves: Array<readonly SluiceDelivery[]> = [];
  const engine = createDeliveryEngine({
    network,
    scheduler,
    onBeforeDelivery: (delivery) => before.push(delivery),
    onWave: (deliveries) => waves.push(deliveries),
  });

  const delivered = engine.step();

  assert.ok(delivered.length > 1);
  assert.ok(delivered.every(
    (delivery) => delivery.sequence_number === delivered[0].sequence_number,
  ));
  assert.deepEqual(before, delivered);
  assert.deepEqual(waves, [delivered]);
  const next = peekDelivery(network);
  assert.ok(next);
  assert.notEqual(next.sequence_number, delivered[0].sequence_number);
});

test("settle matches repeated step delivery order", () => {
  const steppedNetwork = createNetwork("engine-settle-stepped");
  const settledNetwork = createNetwork("engine-settle-settled");
  enqueueOperations(steppedNetwork, 3);
  enqueueOperations(settledNetwork, 3);
  let idleCount = 0;
  const steppedEngine = createDeliveryEngine({
    network: steppedNetwork,
    scheduler: new FakeScheduler(),
    onWave: () => {},
  });
  const settledWaves: Array<readonly SluiceDelivery[]> = [];
  const settledEngine = createDeliveryEngine({
    network: settledNetwork,
    scheduler: new FakeScheduler(),
    onWave: (deliveries) => settledWaves.push(deliveries),
    onIdle: () => {
      idleCount += 1;
    },
  });
  const stepped: SluiceDelivery[] = [];

  while (peekDelivery(steppedNetwork) !== null) {
    stepped.push(...steppedEngine.step());
  }
  const settled = settledEngine.settle();

  assert.deepEqual(
    settled.map((delivery) => deliverySignature(settledNetwork, delivery)),
    stepped.map((delivery) => deliverySignature(steppedNetwork, delivery)),
  );
  assert.deepEqual(settledWaves.flat(), settled);
  assert.equal(settledWaves.length, 3);
  assert.ok(settledWaves.every(
    (wave) =>
      wave.length > 1 &&
      wave.every(
        (delivery) => delivery.sequence_number === wave[0]?.sequence_number,
      ),
  ));
  assert.equal(idleCount, 1);
});

test("settle ignores delivery schedules requested by onWave", () => {
  const network = createNetwork("engine-settle-reschedule");
  enqueueOperations(network, 2);
  const scheduler = new FakeScheduler();
  let engine: DeliveryEngine;
  engine = createDeliveryEngine({
    network,
    scheduler,
    onWave: () => engine.schedule(5),
  });

  const delivered = engine.settle();

  assert.ok(delivered.length > 0);
  assert.equal(peekDelivery(network), null);
  assert.equal(engine.pending, false);
  assert.equal(scheduler.pendingCount, 0);
});

test("settle leaves no timer when a delivery callback fails", () => {
  const network = createNetwork("engine-settle-failure");
  enqueueOperations(network, 2);
  const scheduler = new FakeScheduler();
  let engine: DeliveryEngine;
  engine = createDeliveryEngine({
    network,
    scheduler,
    onWave: () => {
      engine.schedule(5);
      throw new Error("wave failed");
    },
  });

  assert.throws(() => engine.settle(), /wave failed/);
  assert.equal(engine.pending, false);
  assert.equal(scheduler.pendingCount, 0);
  assert.ok(peekDelivery(network));
});

test("cancel prevents a scheduled callback from delivering", () => {
  const network = createNetwork("engine-cancel");
  enqueueOperations(network, 1);
  const scheduler = new FakeScheduler();
  const waves: Array<readonly SluiceDelivery[]> = [];
  const engine = createDeliveryEngine({
    network,
    scheduler,
    onWave: (deliveries) => waves.push(deliveries),
  });

  engine.schedule(5);
  engine.cancel();
  engine.cancel();
  scheduler.runAll();

  assert.equal(engine.pending, false);
  assert.equal(scheduler.pendingCount, 0);
  assert.deepEqual(waves, []);
  assert.ok(peekDelivery(network));
});

test("reset cancels the old timer and uses the replacement network", () => {
  const oldNetwork = createNetwork("engine-reset-old");
  const newNetwork = createSluiceNetwork({
    tenant: "website",
    document: "engine-reset-new",
    clientIds: ["c", "d"],
  });
  enqueueOperations(oldNetwork, 1);
  writeSequenceMarker(newNetwork.documents.c, 1);
  const scheduler = new FakeScheduler();
  const waves: Array<readonly SluiceDelivery[]> = [];
  const engine = createDeliveryEngine({
    network: oldNetwork,
    scheduler,
    onWave: (deliveries) => waves.push(deliveries),
  });

  engine.schedule(5);
  engine.reset(newNetwork);
  assert.equal(engine.pending, false);
  assert.equal(scheduler.pendingCount, 0);
  assert.ok(peekDelivery(oldNetwork));

  engine.schedule(5);
  scheduler.runAll();

  assert.deepEqual(
    waves.flatMap((wave) =>
      wave.map((delivery) => newNetwork.sidToId[delivery.to])
    ).sort(),
    ["c", "d"],
  );
  assert.ok(peekDelivery(oldNetwork));
});

test("settle keeps the 20,000-wave delivery guard explicit", () => {
  const network = createSluiceNetwork({
    tenant: "website",
    document: "engine-guard",
    clientIds: ["a"],
  });
  enqueueOperations(network, 20_001);
  const engine = createDeliveryEngine({
    network,
    scheduler: new FakeScheduler(),
    onWave: () => {},
  });

  assert.throws(
    () => engine.settle(),
    /Sluice delivery drain exceeded 20000 waves/,
  );
});
