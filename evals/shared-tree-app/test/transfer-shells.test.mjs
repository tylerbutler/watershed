import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const moduleUrl = source => `data:text/javascript,${encodeURIComponent(source)}`;

test("transfers Watershed adapter forwards destination and optional sibling and ignores edits after Close", async () => {
  const source = await readFile(new URL(
    "../tracks/transfers/watershed/src/incident_eval_ffi.mjs", import.meta.url,
  ), "utf8");
  const domainUrl = moduleUrl(`
    export const phase_name = value => value;
    export class TransferStep {
      constructor(incident, id, destination, before) {
        Object.assign(this, { incident, id, destination, before });
      }
    }
  `);
  const optionUrl = moduleUrl(`
    export class None {}
    export class Some { constructor(value) { this[0] = value; } }
  `);
  const { Some, None } = await import(optionUrl);
  const adapterModule = await import(moduleUrl(source
    .replace('"./incident_eval/domain.mjs"', JSON.stringify(domainUrl))
    .replace('"../gleam_stdlib/gleam/option.mjs"', JSON.stringify(optionUrl))));
  const actions = [];
  const errors = [];
  const ready = { phase: "ready" };
  const previous = globalThis.__incidentEval;
  try {
    adapterModule.install({}, ready, value => actions.push(value), () => {}, value => errors.push(value));
    globalThis.__incidentEval.apply({
      type: "transfer-step", incident: "source", id: "step", destination: "target", before: "sibling",
    });
    assert.deepEqual(errors, []);
    assert.equal(actions.length, 1);
    assert.deepEqual({ ...actions[0], before: actions[0].before[0] }, {
      incident: "source", id: "step", destination: "target", before: "sibling",
    });
    assert.ok(actions[0].before instanceof Some);
    globalThis.__incidentEval.apply({
      type: "transfer-step", incident: "source", id: "step", destination: "", before: null,
    });
    assert.equal(actions[1].destination, "");
    assert.ok(actions[1].before instanceof None);
    for (const phase of ["opening", "disconnected", "error", "closed"]) {
      adapterModule.publish({}, { phase });
      globalThis.__incidentEval.apply({
        type: "transfer-step", incident: "source", id: "step", destination: "target", before: null,
      });
    }
    assert.equal(actions.length, 2);
  } finally {
    if (previous === undefined) delete globalThis.__incidentEval;
    else globalThis.__incidentEval = previous;
  }
});
