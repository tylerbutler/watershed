import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  arrayServiceStore,
  openSession,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";
import {
  nativeAdapter,
  publishUpstreamSummary,
  success,
  until,
  upstreamAdapter,
} from "./interop-scenarios.mjs";

const runId = randomUUID();
const output = join(import.meta.dirname, ".output/recovery", runId);
const fixture = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/cases/array-schema-content.json",
  import.meta.url,
), "utf8"));
assert.equal(fixture.reference.version, "3.1.0");
const viewSchema = fixture.input.schemas.objectArrays;
assert.equal(typeof viewSchema, "string");

function point(label, x) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m3.Point",
    fields: [
      ["label", { kind: "string", value: label }],
      ["x", { kind: "number", value: x }],
    ],
  };
}

async function cell(config, writer, reader, mode) {
  const acceptedBeforeCrash = mode !== "unsent";
  const interveningReconnect = mode.startsWith("reconnected-");
  const partialAcceptance = mode.endsWith("-prefix");
  const delayedAcceptance = mode.startsWith("reconnected-delayed-");
  const newerThanCheckpoint = mode.endsWith("newer-than-checkpoint");
  const id = `${writer}-${reader}-${mode}`;
  const containers = [];
  let native;
  let resumed;
  try {
    const session = await openSession(config, containers, undefined, false, {
      store: arrayServiceStore,
    });
    const documentId = session.container.resolvedUrl.id;
    const upstream = upstreamAdapter(session);
    await upstream.arrayInsert(["left"], 0, [
      point("first", 1),
      point("second", 2),
    ]);
    await upstream.awaitSynced();
    await publishUpstreamSummary(config, containers, documentId, id, {
      store: arrayServiceStore,
    });
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    const descriptor = {
      runId, documentId, tenant: config.tenantId, viewSchema,
    };
    native = await nativeAdapter(writer, config, descriptor, jwt);
    await native.awaitSynced();
    native.client.gate.hold(
      acceptedBeforeCrash && !interveningReconnect ? "inbound" : "outbound", "op");
    const originalHoldOffset = native.client.gate.evidence().held.length;
    await native.arrayMove(["left"], 0, 1, ["right"], 0);
    if (interveningReconnect) {
      await until(() =>
        native.client.gate.evidence().held.slice(originalHoldOffset)
          .filter(({ direction, kind }) => direction === "outbound" && kind === "op")
          .length === 1,
      `${id} first original submission`);
    }
    await native.set(["right", "0", "label"], "edited");
    if (interveningReconnect) {
      await until(() =>
        native.client.gate.evidence().held.slice(originalHoldOffset)
          .filter(({ direction, kind }) => direction === "outbound" && kind === "op")
          .length === 2,
      `${id} second original submission`);
    }
    const saved = success(await native.client.request({
      command: "pending-checkpoint",
    }), `${id} capture`);
    assert.equal(saved.observation.pendingTreeCount, 2);
    if (interveningReconnect) assert.equal(saved.observation.inFlightCount, 2);
    const file = join(output, `${id}.json`);
    await writeFile(file, JSON.stringify(saved.result), { mode: 0o600 });
    let interveningClientId;
    let resubmissionReferenceNumber;
    let laterPeerSequenceNumber;
    if (interveningReconnect) {
      await native.disconnect();
      await upstream.arrayInsert(["left"], 0, [point("peer-prefix", 6)]);
      await upstream.awaitSynced();
      const offset = native.client.gate.evidence().held.length;
      await native.client.gate.reconnect();
      native.client.gate.hold("outbound", "op");
      if (partialAcceptance) {
        native.client.gate.inject({
          documentId, mutation: "accept-only-first-resubmission",
          expectedStage: "pending-prefix", direction: "outbound", kind: "op",
          transform(payload) {
            const submission = payload[4];
            const messages = submission.messageBatches.flat();
            assert.equal(messages.length, 2);
            submission.messageBatches = [[messages[0]]];
            return payload;
          },
        });
      }
      success(await native.client.request({ command: "reconnect" }), `${id} reconnect`);
      await until(() =>
        native.client.gate.evidence().held.slice(offset)
          .filter(({ direction, kind }) => direction === "outbound" && kind === "op")
          .length === 1,
      `${id} held resubmissions`);
      interveningClientId = (await native.checkpoint()).clientId;
      assert.notEqual(interveningClientId, saved.observation.clientId,
        `${id} reused the original transport identity`);
      if (delayedAcceptance) {
        const occurrence = native.client.gate.evidence().outboundOccurrences.at(-1);
        const messages = occurrence.submissions.flatMap(({ messageBatches }) =>
          messageBatches.flat());
        assert.equal(messages.length, partialAcceptance ? 1 : 2);
        resubmissionReferenceNumber = messages[0].referenceSequenceNumber;
        assert(Number.isInteger(resubmissionReferenceNumber),
          `${id} missing resubmission authoring sequence`);
        assert(messages.every(({ referenceSequenceNumber }) =>
          referenceSequenceNumber === resubmissionReferenceNumber));
        await upstream.arrayInsert(["left"], 0, [point("peer-after-submission", 7)]);
        await upstream.awaitSynced();
        await until(async () =>
          (await native.arrayValues(["left"]))[0]?.fields.some(([name, value]) =>
            name === "label" && value.value === "peer-after-submission"),
        `${id} peer edit after resubmission authoring`);
        laterPeerSequenceNumber = (await native.checkpoint()).sequenceNumber;
        assert(laterPeerSequenceNumber > resubmissionReferenceNumber,
          `${id} did not advance beyond the resubmission authoring sequence`);
      }
      await native.client.gate.release("outbound");
    }
    if (newerThanCheckpoint) {
      await native.arrayInsert(["right"], 1, [point("later", 5)]);
    }
    if (acceptedBeforeCrash) {
      await until(async () =>
        (await upstream.arrayValues(["right"]))[0]?.fields
          .some(([name, value]) =>
            name === "label" && value.value === (partialAcceptance ? "first" : "edited")),
      `${id} server acceptance`);
      if (newerThanCheckpoint) {
        await until(async () =>
          (await upstream.arrayValues(["right"])).length === 2,
        `${id} newer server acceptance`);
      }
    }
    const originalInstance = native.instanceId;
    const transport = native.client.gate.evidence();
    await native.client.crash();
    await native.close();
    native = undefined;

    await upstream.arrayInsert(["narrow"], 0, [point("remote", 3)]);
    await upstream.awaitSynced();
    const checkpoint = JSON.parse(await readFile(file, "utf8"));
    resumed = await nativeAdapter(reader, config, {
      ...descriptor, pendingCheckpoint: checkpoint,
    }, jwt);
    assert.notEqual(resumed.instanceId, originalInstance);
    const recoveredInstance = resumed.instanceId;
    await resumed.awaitSynced();
    const recoveredBeforeContinuation = resumed.client.gate.evidence();
    if (acceptedBeforeCrash && !partialAcceptance) {
      assert.equal(recoveredBeforeContinuation.outboundOccurrences.length, 0,
        `${id} resubmitted work already accepted by the server`);
    } else {
      assert(recoveredBeforeContinuation.outboundOccurrences.length > 0,
        `${id} did not resubmit the saved work`);
      if (partialAcceptance) {
        assert.equal(recoveredBeforeContinuation.outboundOccurrences.length, 1,
          `${id} resubmitted more than the unaccepted suffix`);
      }
    }
    assert.deepEqual(await resumed.arrayValues(["left"]), [
      ...(delayedAcceptance ? [point("peer-after-submission", 7)] : []),
      ...(interveningReconnect ? [point("peer-prefix", 6)] : []),
      point("second", 2),
    ]);
    const expectedRight = [
      point("edited", 1),
      ...(newerThanCheckpoint ? [point("later", 5)] : []),
    ];
    assert.deepEqual(await resumed.arrayValues(["right"]), expectedRight);
    assert.deepEqual(await resumed.arrayValues(["narrow"]), [point("remote", 3)]);
    if (delayedAcceptance) resumed.client.gate.hold("outbound", "op");
    await resumed.arrayInsert(["right"], expectedRight.length, [point("continued", 4)]);
    let continuedCheckpoint;
    if (delayedAcceptance) {
      const savedContinuation = success(await resumed.client.request({
        command: "pending-checkpoint",
      }), `${id} continued capture`);
      assert.equal(savedContinuation.observation.pendingTreeCount, 1);
      assert.equal(savedContinuation.observation.inFlightCount, 1);
      continuedCheckpoint = savedContinuation.result;
      if (!partialAcceptance) {
        assert(continuedCheckpoint.trees.some(({ state }) =>
          state.history.rollbacks.some(({ changes }) =>
            changes.destroys.some((destroys) => destroys.length > 0))),
        `${id} did not retain a rollback destroy for second-crash recovery`);
      }
      await writeFile(join(output, `${id}.continued.json`),
        JSON.stringify(continuedCheckpoint), { mode: 0o600 });
      await resumed.client.gate.release("outbound");
    }
    await resumed.awaitSynced();
    await until(async () =>
      (await upstream.arrayValues(["right"])).length === expectedRight.length + 1,
    `${id} continued allocation`);
    assert.deepEqual(await upstream.arrayValues(["right"]), [
      ...expectedRight,
      point("continued", 4),
    ]);
    let settled = await resumed.checkpoint();
    assert.equal(settled.pendingTreeCount, 0);
    assert.equal(settled.inflightSubmissionCount, 0);
    const recoveredTransport = resumed.client.gate.evidence();
    let continuedRecovery;
    if (delayedAcceptance) {
      await resumed.client.crash();
      await resumed.close();
      resumed = undefined;
      resumed = await nativeAdapter(writer, config, {
        ...descriptor, pendingCheckpoint: continuedCheckpoint,
      }, jwt);
      assert.notEqual(resumed.instanceId, recoveredInstance);
      await resumed.awaitSynced();
      const recoveredBeforeContinuation = resumed.client.gate.evidence();
      assert.equal(recoveredBeforeContinuation.outboundOccurrences.length, 0,
        `${id} repeated the accepted continuation after a second crash`);
      assert.deepEqual(await resumed.arrayValues(["right"]), [
        ...expectedRight, point("continued", 4),
      ]);
      await resumed.arrayInsert(["right"], expectedRight.length + 1,
        [point("continued-again", 8)]);
      await resumed.awaitSynced();
      await until(async () =>
        (await upstream.arrayValues(["right"])).length === expectedRight.length + 2,
      `${id} continued allocation after second crash`);
      assert.deepEqual(await upstream.arrayValues(["right"]), [
        ...expectedRight, point("continued", 4), point("continued-again", 8),
      ]);
      settled = await resumed.checkpoint();
      assert.equal(settled.pendingTreeCount, 0);
      assert.equal(settled.inflightSubmissionCount, 0);
      continuedRecovery = {
        writer: reader, reader: writer, recoveredInstance: resumed.instanceId,
        recoveredBeforeContinuation,
        recoveredTransport: resumed.client.gate.evidence(),
      };
    }
    return {
      id, documentId, writer, reader, acceptedBeforeCrash, newerThanCheckpoint,
      interveningReconnect, partialAcceptance, interveningClientId,
      delayedAcceptance, resubmissionReferenceNumber, laterPeerSequenceNumber,
      originalInstance, recoveredInstance, continuedRecovery,
      sequenceNumber: settled.sequenceNumber,
      pendingTreeCount: settled.pendingTreeCount,
      transport,
      recoveredBeforeContinuation,
      recoveredTransport,
    };
  } catch (error) {
    await writeFile(join(output, `${id}.failure.json`), JSON.stringify({
      id, message: error.message, stack: error.stack,
      transport: native?.client.gate.evidence(),
      recoveredTransport: resumed?.client.gate.evidence(),
    }), { mode: 0o600 }).catch((captureError) => {
      throw new AggregateError([error, captureError], `${id} failure capture failed`);
    });
    throw error;
  } finally {
    try {
      await resumed?.close();
    } finally {
      try {
        await native?.close();
      } finally {
        for (const container of containers.toReversed()) container.close();
      }
    }
  }
}

await mkdir(output, { recursive: true });
const results = await withLocalFloodgate(async (config) => {
  const results = [];
  for (const writer of ["javascript", "erlang"]) {
    for (const reader of ["javascript", "erlang"]) {
      for (const mode of [
        "unsent", "accepted", "newer-than-checkpoint",
        "reconnected-accepted", "reconnected-prefix", "reconnected-newer-than-checkpoint",
        "reconnected-delayed-accepted", "reconnected-delayed-prefix",
      ]) {
        results.push(await cell(config, writer, reader, mode));
      }
    }
  }
  return results;
});
assert.equal(results.length, 32);
await writeFile(join(output, "report.json"), JSON.stringify({
  runId, results,
}), { mode: 0o600 });
console.log(`SharedTree recovery interoperability passed: ${results.length} cells (${runId})`);
