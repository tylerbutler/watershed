import assert from "node:assert/strict";
import test from "node:test";
import { createSequencer, type SeqClient } from "./sequencer.ts";

type Client = SeqClient & { id: string };

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

test("does not begin an operation that became stale inside the transport", async () => {
  const clients: Record<string, Client> = {
    a: { id: "a", el: {} as HTMLElement, lastArrival: 0 },
    b: { id: "b", el: {} as HTMLElement, lastArrival: 0 },
  };
  const sequenced: string[] = [];
  let stale = false;
  const sequencer = createSequencer({
    clients,
    seqNode: {} as HTMLElement,
    flow: { animateDot() {} },
    controls: {
      animSpeed: 1,
      sampleLatency: () => 0,
      paced: () => 0,
    },
    onChange() {},
  });

  sequencer.send({
    originId: "a",
    guard: () => () => stale,
    onSequence(sequence) {
      sequenced.push(`stale:${sequence}`);
      return undefined;
    },
    onDeliver() {},
  });
  await tick();
  stale = true;
  await tick();

  sequencer.send({
    originId: "a",
    onSequence(sequence) {
      sequenced.push(`current:${sequence}`);
      return undefined;
    },
    onDeliver() {},
  });
  await tick();
  await tick();

  assert.deepEqual(sequenced, ["current:2"]);
});
