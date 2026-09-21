import assert from "node:assert/strict";
import test from "node:test";
import {
  cleanupEphemeralService,
  startEphemeralService,
} from "@fluidframework/local-driver/alpha";
import { initialRoot, rootStore } from "./schema.mjs";

test("two upstream clients merge edits to the declared object schema", {
  timeout: 30_000,
}, async () => {
  const service = startEphemeralService();
  try {
    const client = service.defaultClient;
    const first = await client.createAttachedContainer(rootStore);
    const second = await client.loadContainer(first.id, rootStore);

    first.data.root.title = "upstream";
    second.data.root.point.x = 7;
    await service.synchronize();

    for (const container of [first, second]) {
      assert.equal(container.data.root.title, "upstream");
      assert.equal(container.data.root.point.x, 7);
      assert.equal(container.data.root.point.y, 0);
      assert.equal(container.data.root.enabled, false);
      assert.equal(container.data.root.rating, 0);
      assert.equal(container.data.root.marker, null);
      assert.equal(container.data.root.note, undefined);
    }
  } finally {
    await cleanupEphemeralService();
  }
});

test("initializers do not reuse mutable tree nodes between documents", () => {
  const first = initialRoot();
  const second = initialRoot();
  first.point.x = 11;
  assert.equal(second.point.x, 0);
});
