import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs, promisify } from "node:util";
import { startClient } from "./client-driver.mjs";
import {
  openSession, serviceConfig, tokenProvider, withLocalFloodgate,
} from "./service.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const execute = promisify(execFile);
const profile = "fluid-3.1.0-fixed-object";
export const caseIds = [
  "facade-and-summary-continuation",
  "accepted-before-ack",
  "never-submitted",
  "interleaved-pending",
  "detached-repair",
  "repeated-reconnect",
];
const targets = ["javascript", "erlang"];

export function validateResults(results, runId) {
  const expected = targets.flatMap((target) =>
    caseIds.map((caseId) => `${target}:${caseId}`)).sort();
  assert(Array.isArray(results) && results.length === 12,
    "Client interoperability requires exactly twelve results");
  const expectedRunId = runId ?? results[0].runId;
  assert(typeof expectedRunId === "string" && expectedRunId.length > 0,
    "Missing current run identity");
  const actual = [];
  for (const item of results) {
    assert(targets.includes(item.target) && caseIds.includes(item.caseId),
      "Unknown target or case ID");
    assert.equal(item.runId, expectedRunId, "Result belongs to another run");
    assert.equal(item.profile, profile, "Unsupported tree profile");
    assert.equal(item.passed, true, "Failed interoperability case");
    assert.equal(item.skipped, false, "Skipped interoperability case");
    assert(Number.isSafeInteger(item.evidence?.sequenceNumber)
      && typeof item.evidence.clientId === "string"
      && Number.isSafeInteger(item.evidence.pendingTreeCount)
      && item.evidence.pendingTreeCount === 0
      && Array.isArray(item.evidence.checkpoints)
      && item.evidence.checkpoints.length >= 2
      && item.evidence.checkpoints.every((checkpoint) =>
        Number.isSafeInteger(checkpoint.sequenceNumber)
        && typeof checkpoint.clientId === "string"
        && Number.isSafeInteger(checkpoint.pendingTreeCount)
        && checkpoint.values && typeof checkpoint.values === "object"
        && Array.isArray(checkpoint.events))
      && Array.isArray(item.evidence.submissions)
      && item.evidence.submissions.length > 0
      && item.evidence.submissions.every((submission) =>
        Number.isSafeInteger(submission.sequenceNumber)
        && typeof submission.batchId === "string"
        && Number.isSafeInteger(submission.revision)
        && typeof submission.originatorId === "string")
      && (item.caseId !== "detached-repair"
        || (Array.isArray(item.evidence.repairValues)
          && item.evidence.repairValues.length === 2
          && item.evidence.repairValues.every((values) =>
            Array.isArray(values) && values.length === 2
            && values.every(Number.isFinite)))),
    "Result lacks measured native connection evidence");
    actual.push(`${item.target}:${item.caseId}`);
  }
  assert.deepEqual(actual.sort(), expected, "Missing or duplicated case");
  return results;
}

async function until(predicate, stage, milliseconds = 30_000) {
  const deadline = Date.now() + milliseconds;
  while (!await predicate()) {
    assert(Date.now() < deadline, `Timed out: ${stage}`);
    await delay(25);
  }
}

function success(reply, label) {
  assert.equal(reply.ok, true, `${label}: ${JSON.stringify(reply.error ?? reply)}`);
  return reply;
}

function field(reply, name) {
  return success(reply, "checkpoint").result.values[name];
}

function text(value) { return { kind: "string", value }; }

async function synced(client, sequence = 0) {
  return success(await client.request({
    command: "await-synced", minimumSequenceNumber: sequence,
  }), "await-synced");
}

async function checkpoint(client) {
  return success(await client.request({ command: "checkpoint" }), "checkpoint");
}

async function reconnect(client) {
  await client.gate.disconnect();
  await client.request({ command: "disconnect" });
  await client.gate.reconnect();
  await success(await client.request({ command: "reconnect" }), "reconnect");
  await synced(client);
}

async function schemaBytes() {
  const fixture = JSON.parse(await readFile(join(repository,
    "test/fixtures/shared_tree/cases/schema-profile.json"), "utf8"));
  assert.equal(fixture.reference.version, "3.1.0", "Pinned schema version changed");
  const stored = fixture.input.summary.tree.indexes.tree.Schema.tree.SchemaString.content;
  assert.equal(JSON.parse(stored).root.kind, "Value", "Fixture is not the fixed root profile");
  return stored;
}

async function serverHistory(session, sequence) {
  const service =
    await session.documentServiceFactory.createDocumentService(session.container.resolvedUrl);
  try {
    const storage = await service.connectToDeltaStorage();
    const messages = storage.fetchMessages(1, sequence + 1, AbortSignal.timeout(15_000), false);
    const history = [];
    for (;;) {
      const chunk = await messages.read();
      if (chunk.done) break;
      history.push(...chunk.value);
    }
    assert(history.every((message, index) => message.sequenceNumber === index + 1),
      "Server history has a missing or repeated sequence number");
    return history;
  } finally {
    service.dispose();
  }
}

function treeSubmission(message) {
  const outer = typeof message.contents === "string"
    ? JSON.parse(message.contents) : message.contents;
  if (message.type !== "op" || outer?.type !== "groupedBatch") return null;
  const items = outer.contents;
  if (!Array.isArray(items)) return null;
  const tree = items.find((item) => item.contents?.type === "component")
    ?.contents?.contents?.contents?.content?.contents;
  if (!tree || !Array.isArray(tree.changeset)) return null;
  const allocation = items.find((item) => item.contents?.type === "idAllocation");
  const batchId = allocation?.metadata?.batchId;
  if (typeof batchId !== "string" || batchId.length === 0) return null;
  assert(Number.isSafeInteger(tree.revision)
    && typeof tree.originatorId === "string" && tree.originatorId.length > 0,
  "Tree submission has no stable revision or originator");
  return {
    sequenceNumber: message.sequenceNumber,
    clientId: message.clientId,
    batchId,
    revision: tree.revision,
    originatorId: tree.originatorId,
    contents: JSON.stringify(outer),
  };
}

function withheldSubmissions(gate, allowIncomplete = false) {
  return gate.withheldOutboundPayloads({ allowIncomplete }).flatMap((payload) => {
    const frame = JSON.parse(payload);
    if (frame[3] !== "submitOp") return [];
    return frame[4].messageBatches.flat()
      .map((message) => treeSubmission({
        ...message, clientId: frame[4].clientId, sequenceNumber: 0,
      }))
      .filter(Boolean);
  });
}

function refresherValues(submission) {
  const outer = JSON.parse(submission.contents);
  const tree = outer.contents.find((item) => item.contents?.type === "component")
    ?.contents?.contents?.contents?.content?.contents;
  const repair = tree?.changeset?.[0]?.data?.refreshers;
  assert.equal(repair?.builds?.length, 1, "Missing per-commit detached root");
  const point = repair.trees.data?.[0]?.[1];
  assert.equal(point?.[1], "org.watershed.shared-tree.m1.Point");
  const fields = point?.[3];
  assert.deepEqual([fields?.[0], fields?.[2]], ["x", "y"]);
  assert.equal(fields[1]?.[1], "com.fluidframework.leaf.number");
  assert.equal(fields[3]?.[1], "com.fluidframework.leaf.number");
  return [fields[1][3], fields[3][3]];
}

async function upstreamRepairValues() {
  const fixture = JSON.parse(await readFile(join(repository,
    "test/fixtures/shared_tree/cases/history-reconciliation.json"), "utf8"));
  const commits = fixture.expected.observations
    .find(({ label }) => label === "resubmit-detached-repair")
    ?.checkpoints.at(-1).resubmitted;
  assert.equal(commits?.length, 2, "Pinned upstream two-commit repair is missing");
  const values = commits.map((commit) => commit.change.refreshers[0].trees[0]
    .fields.map(([, field]) => field.value));
  assert.deepEqual(values, [[1, 2], [42, 2]],
    "Pinned upstream repair profile changed");
  return values;
}

async function caseRun(config, viewSchema, runId, target, caseId) {
  const containers = [];
  let native;
  const checkpoints = [];
  let pending;
  let prefix;
  let originalDetached;
  let repairValues;
  try {
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    const peer = await openSession(config, containers, documentId);
    if (caseId === "detached-repair") {
      peer.data.view.root.point = { x: 1, y: 2 };
      await until(() => !peer.container.isDirty, "oracle repair starting point");
    }
    const summarizer = await openSession(config, containers, documentId, true);
    assert(summarizer.data.ISummarizer, "Missing upstream summarizer");
    const summary = summarizer.data.ISummarizer.summarizeOnDemand({
      reason: `SharedTree native bootstrap ${caseId}`, fullTree: true,
    });
    const submitted = await summary.summarySubmitted;
    assert(submitted.success, `Bootstrap summary submission failed: ${submitted.error}`);
    const broadcast = await summary.summaryOpBroadcasted;
    assert(broadcast.success, `Bootstrap summary broadcast failed: ${broadcast.error}`);
    const ack = await summary.receivedSummaryAckOrNack;
    assert(ack.success, `Bootstrap summary acknowledgement failed: ${ack.error}`);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId);
    native = await startClient(target, {
      runId, documentId, tenant: config.tenantId, viewSchema,
    }, { socketUrl: config.socketUrl, token: jwt });
    async function capture(label) {
      const snapshot = await checkpoint(native);
      checkpoints.push({
        label,
        sequenceNumber: snapshot.sequenceNumber,
        clientId: snapshot.observation.clientId,
        pendingTreeCount: snapshot.observation.pendingTreeCount,
        values: snapshot.result.values,
        events: snapshot.result.events,
      });
      return snapshot;
    }
    const initial = await capture("initial");
    assert.equal(field(initial, "title").value.value, "");
    await success(await native.request({ command: "subscribe" }), "subscribe");
    const title = `${target}-${caseId}-${randomUUID()}`;
    if (caseId === "facade-and-summary-continuation") {
      await success(await native.request({
        command: "set", path: ["title"], value: text(title),
      }), "set title");
      await success(await native.request({
        command: "set", path: ["note"], value: text("temporary"),
      }), "set optional");
      await success(await native.request({
        command: "set", path: ["point"],
        value: {
          kind: "object", schemaId: "org.watershed.shared-tree.m1.Point",
          fields: [
            ["x", { kind: "number", value: 6 }],
            ["y", { kind: "number", value: 8 }],
          ],
        },
      }), "replace nested point");
      await success(await native.request({
        command: "clear", path: ["note"],
      }), "clear optional");
      const required = await native.request({ command: "clear", path: ["title"] });
      assert.equal(required.ok, false, "Required field was cleared");
      assert.equal(required.error.code, "facade-error");
      const rejected = await native.request({
        command: "set", path: ["title"], value: { kind: "number", value: 7 },
      });
      assert.equal(rejected.ok, false, "Invalid edit was accepted");
      assert.equal(rejected.error.code, "facade-error");
      await until(() => peer.data.view.root.title === title
        && peer.data.view.root.point.x === 6
        && peer.data.view.root.point.y === 8,
      "upstream peer observation");
      assert.equal(peer.data.view.root.point.x, 6);
      assert.equal(peer.data.view.root.point.y, 8);
      await synced(native);
      const changed = await capture("after-native-edits");
      assert.equal(field(changed, "title").value.value, title);
      assert.equal(field(changed, "note").present, false);
      assert.equal(field(changed, "x").value.value, 6);
      assert.equal(field(changed, "y").value.value, 8);
      assert(changed.result.events.some((event) => event.local),
        "No local tree notification");
      const published = success(await native.request({ command: "summarize" }), "summarize");
      assert.equal(typeof published.result, "string");
      const fresh = await openSession(config, containers, documentId);
      assert.equal(fresh.data.view.root.title, title);
      fresh.data.view.root.title = `${title}-continued`;
      await until(() => peer.data.view.root.title === `${title}-continued`,
        "published upstream continuation");
      await until(async () => {
        const read = success(await native.request({
          command: "read", path: ["title"],
        }), "read upstream continuation");
        return read.result.value.value === `${title}-continued`;
      }, "native observation after upstream continuation");
      const continued = await capture("upstream-continuation");
      assert(continued.result.events.some((event) => event.local === false),
        "No remote tree notification");
    } else if (caseId === "accepted-before-ack") {
      native.gate.pauseInbound();
      await success(await native.request({
        command: "set", path: ["title"], value: text(title),
      }), "set before ack");
      await until(() => peer.data.view.root.title === title,
        "server acceptance before native ack");
      pending = await capture("server-accepted-before-ack");
      assert(pending.observation.pendingTreeCount > 0, "Missing unacknowledged native edit");
      await reconnect(native);
      assert.equal(field(await capture("reconciled"), "title").value.value, title);
    } else if (caseId === "never-submitted") {
      native.gate.pauseOutbound();
      await success(await native.request({
        command: "set", path: ["title"], value: text(title),
      }), "queue unsent title");
      pending = await capture("withheld-outbound");
      assert(pending.observation.pendingTreeCount > 0, "Unsent tree edit was lost");
      assert.equal(peer.data.view.root.title, "", "Unsent edit reached the peer");
      assert.equal(
        (await serverHistory(creator, pending.sequenceNumber))
          .filter((message) => JSON.stringify(message.contents).includes(title)).length,
        0,
        "An outbound-gated edit appeared in server history",
      );
      await reconnect(native);
      await until(() => peer.data.view.root.title === title, "resubmitted title");
    } else if (caseId === "interleaved-pending") {
      native.gate.pauseInbound();
      await success(await native.request({
        command: "set", path: ["title"], value: text(title),
      }), "accepted prefix");
      await until(() => peer.data.view.root.title === title, "accepted prefix observation");
      prefix = await capture("accepted-prefix-withheld-ack");
      native.gate.pauseOutbound();
      await success(await native.request({
        command: "set", path: ["note"], value: text("local-suffix"),
      }), "unsent suffix");
      pending = await capture("withheld-suffix");
      assert(pending.observation.pendingTreeCount >= 2, "Interleaved pending prefix/suffix missing");
      peer.data.view.root.rating = 42;
      await until(() => !peer.container.isDirty, "remote interleaving acknowledgement");
      await reconnect(native);
      await until(() => peer.data.view.root.note === "local-suffix",
        "interleaved suffix delivery");
      assert.equal(field(await capture("reconciled"), "rating").value.value, 42);
    } else if (caseId === "detached-repair") {
      native.gate.pauseOutbound();
      await success(await native.request({
        command: "set", path: ["point", "x"], value: { kind: "number", value: 42 },
      }), "first pending child edit");
      await success(await native.request({
        command: "set", path: ["point", "y"], value: { kind: "number", value: 7 },
      }), "second pending child edit");
      pending = await capture("two-detached-children-pending");
      assert.equal(pending.observation.pendingTreeCount, 2,
        "Detached repair must cover two separate child commits");
      await until(() => withheldSubmissions(native.gate, true).length === 2,
        "capture both original unsubmitted child commits");
      originalDetached = withheldSubmissions(native.gate);
      assert(originalDetached.every((entry) =>
        entry.clientId === pending.observation.clientId));
      assert.notEqual(originalDetached[0].batchId, originalDetached[1].batchId);
      peer.data.view.root.point = { x: 3, y: 4 };
      await until(() => !peer.container.isDirty, "remote parent replacement");
      await reconnect(native);
      const after = await capture("repaired-forest");
      assert.equal(field(after, "x").value.value, 3,
        "A detached child edit replaced the new visible parent");
      assert.equal(field(after, "y").value.value, 4);
      assert.equal(peer.data.view.root.point.x, 3,
        "Native and upstream views diverged after detached repair");
      const published = success(await native.request({ command: "summarize" }),
        "publish repaired detached state");
      assert.equal(typeof published.result, "string");
      const fresh = await openSession(config, containers, documentId);
      assert.equal(fresh.data.view.root.point.x, 3);
      assert.equal(fresh.data.view.root.point.y, 4);
      fresh.data.view.root.point.x = 5;
      await until(() => peer.data.view.root.point.x === 5,
        "post-repair upstream continuation");
    } else if (caseId === "repeated-reconnect") {
      native.gate.pauseOutbound();
      await success(await native.request({
        command: "set", path: ["title"], value: text(title),
      }), "first pending edit");
      pending = await capture("first-pending");
      await native.gate.disconnect();
      await native.request({ command: "disconnect" });
      const rejected = await native.request({
        command: "set", path: ["title"], value: text("must-not-commit"),
      });
      assert.equal(rejected.ok, false, "Tree edit succeeded during reconnect");
      peer.data.view.root.rating = 17;
      await until(() => !peer.container.isDirty, "sequenced catch-up tail");
      await native.gate.reconnect({ pauseAfterConnectSuccess: true });
      await success(await native.request({ command: "reconnect" }),
        "start first reconnect");
      await until(async () => {
        const observation = (await checkpoint(native)).observation;
        return native.gate.connectSuccesses === 1
          && observation.clientId !== pending.observation.clientId
          && observation.phase === "catching-up"
          && observation.pendingTreeCount === 1;
      }, "new identity entered catch-up before interruption");
      const interrupted = await capture("interrupted-recovery");
      assert.equal(interrupted.observation.phase, "catching-up",
        "Gate did not interrupt actual catch-up");
      await native.gate.disconnect();
      await native.request({ command: "disconnect" });
      await native.gate.reconnect();
      await success(await native.request({ command: "reconnect" }),
        "resume interrupted recovery");
      await synced(native);
      await capture("first-reconnect");
      assert.equal(field(await checkpoint(native), "rating").value.value, 17,
        "Interrupted recovery missed a remote tail edit");
      native.gate.pauseOutbound();
      await success(await native.request({
        command: "set", path: ["note"], value: text("second-pending"),
      }), "second pending edit");
      await capture("second-pending");
      await reconnect(native);
      await until(() => peer.data.view.root.title === title,
        "repeated recovery delivery");
      await until(() => peer.data.view.root.note === "second-pending",
        "second recovery delivery");
    }
    const final = await capture("final");
    assert.equal(final.observation.pendingTreeCount, 0,
      "Native tree edits remained pending");
    assert.equal(final.observation.inFlightCount, 0,
      "Native submissions remained in flight");
    assert(final.observation.synced, "Native connection has not synchronized");
    assert.equal(typeof final.observation.clientId, "string");
    assert(Number.isSafeInteger(final.sequenceNumber));
    const history = await serverHistory(creator, final.sequenceNumber);
    const allSubmissions = history.map(treeSubmission).filter(Boolean);
    const nativeClients = new Set(checkpoints.map((entry) => entry.clientId));
    const submissions = allSubmissions.filter((entry) =>
      nativeClients.has(entry.clientId) && (entry.contents.includes(title)
        || caseId === "detached-repair"));
    if (caseId === "accepted-before-ack" || caseId === "never-submitted") {
      assert.equal(submissions.length, 1,
        `${caseId} duplicated or lost the native revision`);
      assert.equal(submissions[0].clientId,
        caseId === "accepted-before-ack"
          ? pending.observation.clientId
          : final.observation.clientId,
        "Accepted submission used the wrong transport identity");
    }
    if (caseId === "interleaved-pending") {
      const accepted = submissions.find((entry) => entry.contents.includes(title));
      const suffix = allSubmissions.find((entry) => entry.contents.includes("local-suffix"));
      assert(accepted && suffix, "Interleaved tree batches were not both sequenced");
      assert(accepted.sequenceNumber < suffix.sequenceNumber,
        "Interleaved submissions lost their order");
      assert.equal(accepted.clientId, prefix.observation.clientId);
      assert.equal(suffix.clientId, final.observation.clientId);
      const remote = history.find((message) => message.clientId === peer.container.clientId
        && message.type === "op"
        && message.sequenceNumber > accepted.sequenceNumber
        && message.sequenceNumber < suffix.sequenceNumber);
      assert(remote, "No remote operation was sequenced between pending batches");
    }
    if (caseId === "detached-repair") {
      assert.equal(submissions.length, 2,
        "Both repaired detached edits must be submitted exactly once");
      for (let index = 0; index < 2; index++) {
        assert.equal(submissions[index].clientId, final.observation.clientId);
        assert.equal(submissions[index].batchId, originalDetached[index].batchId);
        assert.equal(submissions[index].revision, originalDetached[index].revision);
        assert.equal(submissions[index].originatorId, originalDetached[index].originatorId);
      }
      repairValues = submissions.map(refresherValues);
      assert.deepEqual(repairValues, await upstreamRepairValues(),
        "Each emitted refresher must match its pinned upstream predecessor state");
    }
    if (caseId === "repeated-reconnect") {
      assert.equal(submissions.length, 1,
        "First reconnect duplicated or lost the title edit");
      assert.equal(allSubmissions.filter((entry) =>
        entry.contents.includes("second-pending")).length, 1,
      "Second reconnect duplicated or lost the note edit");
    }
    if (pending) {
      assert.notEqual(pending.observation.clientId, final.observation.clientId,
        "Reconnect did not assign a new transport identity");
    }
    return {
      runId, target, caseId, profile, passed: true, skipped: false,
      evidence: {
        sequenceNumber: final.sequenceNumber,
        clientId: final.observation.clientId,
        pendingTreeCount: final.observation.pendingTreeCount,
        checkpoints,
        ...(repairValues ? { repairValues } : {}),
        submissions: submissions.map(({ contents: _, ...identity }) => identity),
      },
    };
  } finally {
    if (native) await native.close();
    for (const container of containers) container.dispose();
  }
}

async function runService(config) {
  const runId = randomUUID();
  const viewSchema = await schemaBytes();
  for (const target of targets) {
    await execute("gleam", ["build", "--target", target], {
      cwd: repository, timeout: 120_000,
    });
  }
  const results = [];
  for (const target of targets) {
    for (const caseId of caseIds) {
      const result = await caseRun(config, viewSchema, runId, target, caseId);
      results.push(result);
      console.log(JSON.stringify(result));
    }
  }
  validateResults(results, runId);
  return { runId, results };
}

async function main() {
  const { values } = parseArgs({
    options: { "local-floodgate": { type: "boolean", default: false } },
  });
  const output = values["local-floodgate"]
    ? await withLocalFloodgate(runService)
    : await runService(serviceConfig());
  console.log(JSON.stringify({ runId: output.runId, passed: output.results.length }));
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
