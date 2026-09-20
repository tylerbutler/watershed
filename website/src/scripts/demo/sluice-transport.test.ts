import assert from "node:assert/strict";
import test from "node:test";
import {
  json,
  watershed,
} from "./generated-runtime.ts";
import {
  createSluiceNetwork,
  drainDeliveries,
  peekDelivery,
  stepDeliveryWave,
} from "./sluice-transport.ts";

test("connects peers and drains one sequenced operation as a delivery wave", () => {
  const network = createSluiceNetwork({
    tenant: "website",
    document: "transport-test",
    clientIds: ["a", "b"],
  });
  assert.deepEqual(Object.keys(network.documents), ["a", "b"]);
  assert.deepEqual(Object.values(network.sidToId).sort(), ["a", "b"]);

  watershed.set(
    watershed.root(network.documents.a),
    "marker",
    json.int(1),
  );
  const first = peekDelivery(network);
  assert.ok(first);

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
