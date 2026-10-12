import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import {
  runLifecycleInterop,
  synchronize,
  validateLifecycleReport,
  validateLifecycleSection,
} from "./lifecycle-interop.mjs";
import { nativeAdapter } from "./interop-scenarios.mjs";
import { openSession, withLocalFloodgate } from "./service.mjs";

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
}

function replaceNested(value, before, after) {
  if (typeof value === "string") {
    return value.includes(before) ? value.replaceAll(before, after) : value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => replaceNested(item, before, after));
  }
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) =>
    [key, replaceNested(item, before, after)]));
}

function changeFirstRevision(value) {
  if (!value || typeof value !== "object") return false;
  if (Number.isSafeInteger(value.revision)) {
    value.revision += 1;
    return true;
  }
  for (const [key, item] of Object.entries(value)) {
    if (typeof item === "string" && /^[\[{]/.test(item.trim())) {
      try {
        const decoded = JSON.parse(item);
        if (changeFirstRevision(decoded)) {
          value[key] = JSON.stringify(decoded);
          return true;
        }
      } catch {
        // A source value can resemble JSON without containing encoded data.
      }
    } else if (changeFirstRevision(item)) {
      return true;
    }
  }
  return false;
}

function snapshotNode(snapshot, absolutePath) {
  const parts = absolutePath.split("/").filter(Boolean);
  let node = snapshot.tree.trees[".channels"].trees[parts[0]];
  for (const part of parts.slice(1)) node = node.trees[".channels"].trees[part];
  return node;
}

function replaceSnapshotBlob(artifact, row, id, bytes) {
  artifact.snapshot.blobs[id] = bytes.toString("base64");
  row.snapshot.blobs[id] = hash(bytes);
}

function rehashTransport(raw) {
  for (const occurrence of raw.submitted) {
    occurrence.hash = hash(JSON.stringify(occurrence.submissions));
  }
  for (const message of raw.sequenced) {
    message.contentsSha256 = hash(
      typeof message.contents === "string"
        ? message.contents
        : JSON.stringify(message.contents),
    );
  }
}

function submittedMessages(occurrence) {
  return occurrence.submissions.flatMap(({ clientId, messageBatches }) =>
    messageBatches.flat().map((message) => ({ clientId, message })));
}

function rehashUpstreamReconnectOccurrence(window, occurrence) {
  const submission = occurrence.submissions[0];
  const bytes = Buffer.from(
    `42${JSON.stringify([
      "submitOp",
      submission.clientId,
      submission.messageBatches,
    ])}`,
  );
  occurrence.hash = hash(bytes);
  occurrence.byteLength = bytes.length;
  for (const collection of [
    window.raw.gate.held,
    window.raw.gate.delivered,
    window.raw.gate.outboundOccurrences,
    window.raw.gateBeforeDisconnect.held,
    window.raw.gateBeforeDisconnect.delivered,
    window.raw.gateBeforeDisconnect.outboundOccurrences,
  ]) {
    const copy = collection.find(({ id }) => id === occurrence.id);
    if (!copy) continue;
    copy.hash = occurrence.hash;
    copy.byteLength = occurrence.byteLength;
    copy.submissions = structuredClone(occurrence.submissions);
  }
}

function rehashUpstreamGateSubmission(receipt) {
  const submission = receipt.submissions[0];
  const bytes = Buffer.from(
    `42${JSON.stringify([
      "submitOp",
      submission.clientId,
      submission.messageBatches,
    ])}`,
  );
  receipt.hash = hash(bytes);
  receipt.byteLength = bytes.length;
}

function syncReconnectGateOccurrence(window, occurrence) {
  for (const collection of [
    window.raw.gate.held,
    window.raw.gate.delivered,
    window.raw.gate.outboundOccurrences,
    window.raw.gateBeforeDisconnect.held,
    window.raw.gateBeforeDisconnect.delivered,
    window.raw.gateBeforeDisconnect.outboundOccurrences,
  ]) {
    const copy = collection.find(({ id }) => id === occurrence.id);
    if (!copy) continue;
    copy.hash = occurrence.hash;
    copy.byteLength = occurrence.byteLength;
    copy.submissions = structuredClone(occurrence.submissions);
  }
}

function reconnectAttach(window, occurrence) {
  const [{ message }] = submittedMessages(occurrence);
  const contents = typeof message.contents === "string"
    ? JSON.parse(message.contents)
    : message.contents;
  let found;
  const visit = (value) => {
    if (!value || typeof value !== "object" || found) return;
    if (value.type === "attach") {
      found = value.content ?? value.contents;
      return;
    }
    for (const child of Object.values(value)) visit(child);
  };
  visit(contents);
  assert(found, "Reconnect occurrence lacks an attachment");
  return { attachment: found, contents, message };
}

function rewriteMessageContents(message, contents) {
  message.contents = typeof message.contents === "string"
    ? JSON.stringify(contents)
    : contents;
}

function duplicateTargetAttachment(raw) {
  let inserted;
  const duplicate = (message) => mutateContents(message, (contents) => {
    if (inserted !== undefined
      || contents?.type !== "groupedBatch"
      || !Array.isArray(contents.contents)) return;
    const index = contents.contents.findIndex((item) => hasAttach(item));
    if (index < 0) return;
    contents.contents.splice(
      index + 1,
      0,
      structuredClone(contents.contents[index]),
    );
    inserted = {
      sequenceNumber: message.sequenceNumber,
      clientSequenceNumber: message.clientSequenceNumber,
      innerIndex: index,
    };
  });
  for (const occurrence of raw.submitted.slice(-1)) {
    for (const submission of occurrence.submissions) {
      for (const message of submission.messageBatches.flat()) duplicate(message);
    }
  }
  inserted = undefined;
  for (const message of raw.sequenced) duplicate(message);
  assert(inserted, "Reconnect row lacks a target attachment");
  const sameOperation = (item) =>
    item.sequenceNumber === inserted.sequenceNumber
      && item.clientSequenceNumber === inserted.clientSequenceNumber;
  for (const target of raw.dependencies.targets) {
    for (const occurrence of target.occurrences) {
      if (sameOperation(occurrence) && occurrence.innerIndex > inserted.innerIndex) {
        occurrence.innerIndex += 1;
      }
    }
    const attachment = target.occurrences.find((occurrence) =>
      sameOperation(occurrence)
        && occurrence.innerIndex === inserted.innerIndex
        && occurrence.kind === "attach");
    if (attachment) {
      target.occurrences.push({
        ...structuredClone(attachment),
        innerIndex: inserted.innerIndex + 1,
      });
      target.occurrences.sort((left, right) =>
        left.sequenceNumber - right.sequenceNumber
          || left.innerIndex - right.innerIndex);
    }
  }
  for (const commit of raw.dependencies.commits) {
    if (sameOperation(commit) && commit.innerIndex > inserted.innerIndex) {
      commit.innerIndex += 1;
    }
  }
  rehashTransport(raw);
}

function hasAttach(value, id) {
  if (!value || typeof value !== "object") return false;
  if (value.type === "attach"
    && (id === undefined || (value.content ?? value.contents)?.id === id)) return true;
  return Object.values(value).some((child) => hasAttach(child, id));
}

function changeAttachParent(value) {
  if (!value || typeof value !== "object") return;
  if (value.type === "component"
    && value.contents?.address === "A"
    && hasAttach(value.contents.contents)) {
    value.contents.address = "WRONG";
  }
  for (const child of Object.values(value)) changeAttachParent(child);
}

function mutateContents(message, mutate) {
  const parsed = typeof message.contents === "string"
    ? JSON.parse(message.contents)
    : message.contents;
  mutate(parsed);
  message.contents = typeof message.contents === "string"
    ? JSON.stringify(parsed)
    : parsed;
}

function moveAllocationAfterDependentUse(raw, attachmentOnly = false, attachedId) {
  let moved;
  const move = (message) => mutateContents(message, (contents) => {
    if (moved !== undefined
      || contents?.type !== "groupedBatch"
      || !Array.isArray(contents.contents)
      || (attachedId !== undefined && !hasAttach(contents, attachedId))) {
      return;
    }
    const index = contents.contents.findIndex(
      (item) => item.contents?.type === "idAllocation",
    );
    if (index < 0 || index === contents.contents.length - 1) return;
    const destination = attachmentOnly
      ? contents.contents.findLastIndex((item) => hasAttach(item, attachedId))
      : contents.contents.length - 1;
    assert(destination > index, "Row lacks an attachment after allocation");
    const [allocation] = contents.contents.splice(index, 1);
    contents.contents.splice(destination, 0, allocation);
    moved = {
      sequenceNumber: message.sequenceNumber,
      clientSequenceNumber: message.clientSequenceNumber,
      before: index,
      after: destination,
    };
  });
  for (const occurrence of raw.submitted) {
    for (const submission of occurrence.submissions) {
      for (const message of submission.messageBatches.flat()) move(message);
    }
  }
  moved = undefined;
  for (const message of raw.sequenced) move(message);
  assert(moved, "Row lacks an allocation before a dependent use");
  const sameOperation = (item) =>
    item.sequenceNumber === moved.sequenceNumber
      && item.clientSequenceNumber === moved.clientSequenceNumber;
  const shift = (item) => {
    if (sameOperation(item)
      && item.innerIndex > moved.before && item.innerIndex <= moved.after) {
      item.innerIndex -= 1;
    }
  };
  for (const allocation of raw.dependencies.allocations) {
    if (sameOperation(allocation) && allocation.innerIndex === moved.before) {
      allocation.innerIndex = moved.after;
    }
  }
  for (const target of raw.dependencies.targets) {
    for (const occurrence of target.occurrences) shift(occurrence);
  }
  for (const commit of raw.dependencies.commits) shift(commit);
  rehashTransport(raw);
}

async function rejectArtifactMutation(
  name,
  result,
  mutate,
  pattern,
  writer,
) {
  const section = structuredClone(result.report.sections[name]);
  const artifacts = structuredClone(result.artifacts);
  const row = writer === undefined
    ? section.rows[0]
    : section.rows.find((item) => item.writer === writer);
  assert(row, `${name} lacks writer ${writer}`);
  const descriptor = row.artifacts[0];
  const path = join(artifacts.root, descriptor.path);
  const original = await readFile(path);
  const artifact = JSON.parse(original);
  mutate(artifact, row);
  const bytes = Buffer.from(`${JSON.stringify(artifact)}\n`);
  const digest = hash(bytes);
  descriptor.sha256 = digest;
  artifacts.files[descriptor.path].sha256 = digest;
  await writeFile(path, bytes, { mode: 0o600 });
  try {
    await assert.rejects(
      () => validateLifecycleSection(
        name,
        section,
        artifacts,
        result.validationContext,
      ),
      pattern,
    );
  } finally {
    await writeFile(path, original, { mode: 0o600 });
  }
}

async function rejectRoundOneCounterexamples(t, result) {
  const channel = result.report.sections.channelAttachment;
  const javascript = channel.rows.find(({ writer }) => writer === "javascript");
  const firstAttach = javascript.raw.submitted.findIndex(({ submissions }) =>
    hasAttach(submissions));
  assert(firstAttach >= 0, "Saved JavaScript row lacks an outbound attach");

  await t.test("dropped outbound attachment occurrence", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      const index = row.raw.submitted.findIndex(({ submissions }) =>
        hasAttach(submissions));
      row.raw.submitted.splice(index, 1);
      artifact.raw.submitted.splice(index, 1);
    },
    /complete|ordered|outbound|correspondence/i,
    "javascript",
  ));
  await t.test("changed outbound reference sequence", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      for (const raw of [row.raw, artifact.raw]) {
        const operation = raw.submitted
          .flatMap(({ submissions }) => submissions)
          .flatMap(({ messageBatches }) => messageBatches.flat())
          .find(({ type }) => type === "op");
        operation.referenceSequenceNumber = 0;
        rehashTransport(raw);
      }
    },
    /reference sequence|correspondence/i,
    "javascript",
  ));
  await t.test("changed full attachment parent route", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      for (const raw of [row.raw, artifact.raw]) {
        for (const occurrence of raw.submitted) {
          for (const submission of occurrence.submissions) {
            for (const message of submission.messageBatches.flat()) {
              mutateContents(message, changeAttachParent);
            }
          }
        }
        for (const message of raw.sequenced) {
          mutateContents(message, changeAttachParent);
        }
        rehashTransport(raw);
      }
    },
    /attachment route|target path|address|dependency order/i,
    "javascript",
  ));
  await t.test("truncated compressor state", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      const id = artifact.snapshot.tree.blobs[".idCompressor"];
      const encoded = JSON.parse(
        Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
      );
      const state = Buffer.from(encoded, "base64").subarray(0, 8);
      const bytes = Buffer.from(JSON.stringify(state.toString("base64")));
      replaceSnapshotBlob(artifact, row, id, bytes);
      row.snapshot.evidence.compressor = {
        ...row.snapshot.evidence.compressor,
        sha256: hash(bytes),
        stateSha256: hash(state),
        byteLength: state.length,
      };
    },
    /compressor.*(deserialize|layout|state|allocation)/i,
    "javascript",
  ));
  await t.test("changed handle-values stored map value", () =>
    rejectArtifactMutation(
    "handleValues",
    result,
    (artifact, row) => {
      const node = snapshotNode(artifact.snapshot, row.targets.map.path);
      const id = node.blobs.header;
      const header = JSON.parse(
        Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
      );
      header.content.value.value = "wrong-stored-value";
      const bytes = Buffer.from(JSON.stringify(header));
      replaceSnapshotBlob(artifact, row, id, bytes);
      row.snapshot.evidence.targets.map.graph.value = "wrong-stored-value";
    },
    /persisted map value/i,
    "javascript",
  ));
  await t.test("changed primary datastore metadata", () =>
    rejectArtifactMutation(
    "handleValues",
    result,
    (artifact, row) => {
      const primary = artifact.snapshot.tree.trees[".channels"].trees.A;
      const id = primary.blobs[".component"];
      const component = JSON.parse(
        Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
      );
      component.pkg = "[\"wrong.factory\"]";
      component.isRootDataStore = false;
      replaceSnapshotBlob(
        artifact,
        row,
        id,
        Buffer.from(JSON.stringify(component)),
      );
    },
    /primary.*(factory|metadata|root)/i,
    "javascript",
  ));
  await t.test("changed upstream summary proposal", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      for (const raw of [row.raw, artifact.raw]) {
        raw.publication.response.contents.summaryProposal
          .summarySequenceNumber = 6;
        const acknowledgement = raw.sequenced.find(
          ({ sequenceNumber }) =>
            sequenceNumber === raw.publication.acknowledgementSequenceNumber,
        );
        acknowledgement.contents.summaryProposal.summarySequenceNumber = 6;
        rehashTransport(raw);
      }
    },
    /summarize proposal|summarize operation|acknowledgement.*proposal/i,
    "upstream",
  ));
  await t.test("self-declared native peer removal", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      delete row.peer.observations.erlang;
      row.peer.expectedImplementations = ["upstream"];
      delete artifact.peers.erlang;
    },
    /peer implementation (coverage|policy)/i,
    "javascript",
  ));
  await t.test("changed persisted runtime metadata pins", () =>
    rejectArtifactMutation(
    "channelAttachment",
    result,
    (artifact, row) => {
      const id = artifact.snapshot.tree.blobs[".metadata"];
      const metadata = JSON.parse(
        Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
      );
      metadata.documentSchema.info.minVersionForCollab = "9.9.9";
      metadata.createContainerRuntimeVersion = "9.9.9";
      replaceSnapshotBlob(
        artifact,
        row,
        id,
        Buffer.from(JSON.stringify(metadata)),
      );
    },
    /persisted.*(version|metadata|minimum)/i,
    "javascript",
  ));
}

test("full lifecycle validation refuses a bounded report", async () => {
  await assert.rejects(
    () => validateLifecycleReport({
      formatVersion: 1,
      runId: "bounded",
      contract: {},
      sections: {},
    }, { runId: "bounded" }),
    /pins|seven|required section|handleValues/i,
  );
});

test("default lifecycle producer refuses a partial report", async () => {
  await assert.rejects(
    () => runLifecycleInterop({ config: {} }),
    /full seven-section.*not implemented/i,
  );
});

test("one real reconnect writer validates both acceptance windows", {
  timeout: 300_000,
}, async () => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-reconnect-${randomUUID()}`,
  );
  try {
    const result = await withLocalFloodgate((config) =>
      runLifecycleInterop({
        config,
        scenario: "handleReconnect:upstream",
        output,
      }));
    const section = result.report.sections.handleReconnect;
    assert.deepEqual(section.expectedWriters, ["upstream"]);
    assert.equal(section.rows.length, 1);
    assert.deepEqual(
      section.rows[0].reconnect.windows.map(({ id }) => id),
      ["before-service-acceptance", "accepted-before-local-ack"],
    );
    await validateLifecycleSection(
      "handleReconnect",
      section,
      result.artifacts,
      result.validationContext,
    );
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("all reconnect writers reject semantic counterexamples", {
  timeout: 900_000,
}, async (t) => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-reconnect-all-${randomUUID()}`,
  );
  try {
    const results = {};
    await withLocalFloodgate(async (config) => {
      for (const writer of ["upstream", "javascript", "erlang"]) {
        results[writer] = await runLifecycleInterop({
          config,
          scenario: `handleReconnect:${writer}`,
          output: join(output, writer),
        });
      }
    });
    const mutateWindow = (artifact, row, id, mutate) => {
      const rowWindow = row.reconnect.windows.find((window) => window.id === id);
      const artifactWindow = artifact.reconnect.windows.find(
        (window) => window.id === id,
      );
      mutate(rowWindow);
      mutate(artifactWindow);
    };
    for (const [writer, result] of Object.entries(results)) {
      await t.test(`${writer} false service acceptance`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "before-service-acceptance",
            (window) => {
              window.raw.acceptedBeforeDisconnect =
                structuredClone(window.raw.sequenced);
            },
          ),
          /falsely claims no service acceptance/i,
          writer,
        ));
      await t.test(`${writer} missing accepted delta`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "accepted-before-local-ack",
            (window) => {
              window.raw.acceptedBeforeDisconnect = [];
            },
          ),
          /accepted-before-disconnect delta is missing|predisconnect acceptance differs/i,
          writer,
        ));
      await t.test(`${writer} unrelated noop replaces predisconnect acceptance`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             const accepted = window.raw.acceptedBeforeDisconnect[0];
             window.raw.acceptedBeforeDisconnect = [{
               ...structuredClone(accepted),
               clientId: "unrelated-client",
               type: "noop",
               contents: null,
               contentsSha256: hash(JSON.stringify(null)),
             }];
           },
         ),
         /predisconnect acceptance.*accepted service|accepted.*identity/i,
         writer,
        ));
      await t.test(`${writer} dropped inbound echo also claims delivery`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             const accepted = window.logical.accepted[0].outerSequenceNumber;
             const held = window.raw.gateBeforeDisconnect.held.find(
               ({ direction, sequenceNumbers }) =>
                 direction === "inbound"
                   && sequenceNumbers.includes(accepted),
             );
             assert(held, "Reconnect row lacks the held accepted echo");
             const delivered = { ...structuredClone(held), duplicate: false };
             window.raw.gateBeforeDisconnect.delivered.push(
               structuredClone(delivered),
             );
             window.raw.gate.delivered.push(delivered);
           },
         ),
         /held.*echo.*delivered|dropped.*acknowledgement.*delivered/i,
         writer,
        ));
      await t.test(`${writer} changed resubmitted identity`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "before-service-acceptance",
            (window) => {
              const submitted = window.raw.submitted.findLast((occurrence) => {
                const copy = structuredClone(occurrence.submissions);
                return changeFirstRevision(copy);
              });
              assert(submitted, "Reconnect row lacks a submitted revision");
              assert(changeFirstRevision(submitted.submissions),
                "Reconnect row lacks a submitted revision");
              submitted.hash = hash(JSON.stringify(
                submitted.submissions,
              ));
              if (writer === "upstream") {
                rehashUpstreamReconnectOccurrence(
                  window,
                  submitted,
                );
              } else {
                syncReconnectGateOccurrence(
                  window,
                  submitted,
                );
              }
            },
          ),
          /resubmitted logical identity differs|accepted logical projection|exact upstream wire/i,
          writer,
        ));
      await t.test(`${writer} duplicate target attachment`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "accepted-before-local-ack",
            (window) => duplicateTargetAttachment(window.raw),
          ),
          /target attachment is missing or duplicated|accepted logical projection/i,
          writer,
        ));
      await t.test(`${writer} falsified pending drain`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "accepted-before-local-ack",
            (window) => {
              window.final.pendingTreeCount = 1;
            },
          ),
          /pending tree work did not drain/i,
          writer,
        ));
      await t.test(`${writer} retained final pending history`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             window.final.history.pending =
               structuredClone(window.pending.history.pending);
           },
         ),
         /final.*pending history|pending history.*drain/i,
         writer,
        ));
      if (writer !== "upstream") {
        await t.test(`${writer} disconnected final native observation`, () =>
         rejectArtifactMutation(
           "handleReconnect",
           result,
           (artifact, row) => mutateWindow(
             artifact,
             row,
             "accepted-before-local-ack",
             (window) => {
               window.final.connection.phase = "disconnected";
               window.final.connection.synced = false;
             },
           ),
           /final.*native connection|native.*finalization/i,
           writer,
         ));
      }
      await t.test(`${writer} changed peer data`, () =>
        rejectArtifactMutation(
          "handleReconnect",
          result,
          (artifact, row) => mutateWindow(
            artifact,
            row,
            "accepted-before-local-ack",
            (window) => {
              const implementation = Object.keys(
                window.peer.observations,
              )[0];
              window.peer.observations[implementation].value = "wrong";
            },
          ),
          /accepted attachment content|observed another target value/i,
          writer,
        ));
      await t.test(`${writer} arbitrary noop contents`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "before-service-acceptance",
           (window) => {
             const source = window.raw.submitted.at(-1);
             const occurrence = structuredClone(source);
             occurrence.id = Math.max(
               ...window.raw.gate.outboundOccurrences.map(({ id }) => id),
             ) + 1;
             const [{ message }] = submittedMessages(occurrence);
             message.type = "noop";
             message.contents = { type: "component" };
             delete message.metadata;
             occurrence.hash = hash(JSON.stringify(occurrence.submissions));
             window.raw.submitted.push(occurrence);
             const receipt = {
               ...structuredClone(occurrence),
               direction: "outbound",
               kind: "op",
               duplicate: false,
             };
             window.raw.gate.outboundOccurrences.push(
               structuredClone(receipt),
             );
             window.raw.gate.delivered.push(receipt);
           },
         ),
         /SDK noop.*operation contents|transport occurrence classification/i,
         writer,
        ));
      await t.test(`${writer} coordinated fabricated attachment value`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             window.label = "fabricated-value";
             window.local.value = "fabricated-value";
             for (const peer of Object.values(window.peer.observations)) {
               peer.value = "fabricated-value";
             }
           },
         ),
         /accepted.*attachment.*value|attachment.*content/i,
         writer,
        ));
      await t.test(`${writer} removed accepted delivery receipt`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             const accepted = window.logical.accepted[0].outerSequenceNumber;
             window.raw.gate.held = window.raw.gate.held.filter(
               ({ sequenceNumbers }) => !sequenceNumbers.includes(accepted),
             );
             window.raw.gateBeforeDisconnect.held =
               window.raw.gateBeforeDisconnect.held.filter(
                 ({ sequenceNumbers }) => !sequenceNumbers.includes(accepted),
               );
           },
         ),
         /accepted acknowledgement.*held|delivery.*receipt/i,
         writer,
        ));
      await t.test(`${writer} removed reconnect connection and handshake`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "before-service-acceptance",
           (window) => {
             const acceptedOccurrence = window.raw.submitted.find(
               (occurrence) => submittedMessages(occurrence)
                 .some(({ message }) => message.type === "op"
                   && message.clientSequenceNumber
                     === window.logical.accepted[0].clientSequenceNumber
                   && occurrence.connectionId
                     !== window.raw.submitted[0].connectionId),
             );
             assert(acceptedOccurrence,
               "Reconnect row lacks its accepted retry occurrence");
             window.raw.gate.connections = window.raw.gate.connections.filter(
               ({ connectionId }) =>
                 connectionId !== acceptedOccurrence.connectionId,
             );
             window.raw.gate.handshakes = [];
           },
         ),
         /accepted.*connection|reconnect.*handshake/i,
         writer,
        ));
      await t.test(`${writer} acknowledged before dropped inbound echo`, () =>
        rejectArtifactMutation(
         "handleReconnect",
         result,
         (artifact, row) => mutateWindow(
           artifact,
           row,
           "accepted-before-local-ack",
           (window) => {
             window.pending.sequenceNumber =
               window.logical.accepted[0].outerSequenceNumber;
             window.pending.history.pending = [];
           },
         ),
         /local acknowledgement.*before.*drop|pending.*before.*disconnect/i,
         writer,
        ));
    }
    await t.test("upstream altered original attachment snapshot", () =>
      rejectArtifactMutation(
        "handleReconnect",
        results.upstream,
        (artifact, row) => mutateWindow(
         artifact,
         row,
         "before-service-acceptance",
         (window) => {
           const original = window.raw.submitted[0];
           const { attachment, contents, message } =
             reconnectAttach(window, original);
           const header = attachment.snapshot.entries.find(
             ({ path }) => path === "header",
           );
           const decoded = JSON.parse(header.value.contents);
           decoded.content.value.value = "fabricated-original";
           header.value.contents = JSON.stringify(decoded);
           rewriteMessageContents(message, contents);
           rehashUpstreamReconnectOccurrence(window, original);
         },
        ),
        /original.*attachment|resubmitted.*batch/i,
        "upstream",
      ));
    await t.test("upstream altered original compressor allocation", () =>
      rejectArtifactMutation(
        "handleReconnect",
        results.upstream,
        (artifact, row) => mutateWindow(
         artifact,
         row,
         "before-service-acceptance",
         (window) => {
           const original = window.raw.submitted[0];
           const [{ message }] = submittedMessages(original);
           const contents = typeof message.contents === "string"
             ? JSON.parse(message.contents)
             : message.contents;
           const allocation = contents.contents.find(
             (item) => item.contents?.type === "idAllocation",
           ).contents.contents.ids;
           allocation.count += 1;
           allocation.localIdRanges[0][1] += 1;
           rewriteMessageContents(message, contents);
           rehashUpstreamReconnectOccurrence(window, original);
         },
        ),
        /original.*allocation|resubmitted.*batch/i,
        "upstream",
      ));
    await t.test("upstream gate submission differs from projected payload", () =>
      rejectArtifactMutation(
        "handleReconnect",
        results.upstream,
        (artifact, row) => mutateWindow(
          artifact,
          row,
          "accepted-before-local-ack",
          (window) => {
            const occurrence = window.raw.submitted[0];
            let mutated = 0;
            for (const collection of [
              window.raw.gate.outboundOccurrences,
              window.raw.gate.delivered,
              window.raw.gateBeforeDisconnect.delivered,
            ]) {
              const receipt = collection.find(({ direction, submissions }) =>
                direction !== "inbound"
                  && submissions?.[0]?.clientId
                    === occurrence.submissions[0].clientId
                  && submissions[0].messageBatches.flat()[0]
                    .clientSequenceNumber
                    === occurrence.submissions[0].messageBatches.flat()[0]
                      .clientSequenceNumber);
              if (!receipt) continue;
              const message = receipt.submissions[0].messageBatches.flat()[0];
              message.contents = "{}";
              rehashUpstreamGateSubmission(receipt);
              occurrence.hash = receipt.hash;
              occurrence.byteLength = receipt.byteLength;
              mutated += 1;
            }
            assert(mutated > 0, "Reconnect row lacks gate submission copies");
          },
        ),
        /gate submission.*projected payload|exact upstream wire/i,
        "upstream",
      ));
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("one real retention writer validates fresh runtime evidence", {
  timeout: 300_000,
}, async () => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-retention-${randomUUID()}`,
  );
  try {
    const result = await withLocalFloodgate((config) =>
      runLifecycleInterop({
        config,
        scenario: "handleRetention:upstream",
        output,
      }));
    const section = result.report.sections.handleRetention;
    assert.deepEqual(section.expectedWriters, ["upstream"]);
    assert.equal(section.rows.length, 1);
    assert.deepEqual(
      section.rows[0].retention.checkpoints.map(({ id }) => id),
      [
        "before-removal",
        "after-removal",
        "after-undo",
        "retained-repair",
        "branch-disposal",
        "revertible-disposal",
        "unreferenced-datastore",
        "fresh-load",
      ],
    );
    await validateLifecycleSection(
      "handleRetention",
      section,
      result.artifacts,
      result.validationContext,
    );
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("one real transaction branch writer validates fresh runtime evidence", {
  timeout: 300_000,
}, async () => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-transaction-${randomUUID()}`,
  );
  try {
    const result = await withLocalFloodgate((config) =>
      runLifecycleInterop({
        config,
        scenario: "handleTransactionBranch:upstream",
        output,
      }));
    const section = result.report.sections.handleTransactionBranch;
    assert.deepEqual(section.expectedWriters, ["upstream"]);
    assert.equal(section.rows.length, 1);
    assert.deepEqual(
      section.rows[0].history.steps.map(({ id }) => id),
      [
        "successful-transaction",
        "aborted-transaction",
        "nested-transaction",
        "active-target",
        "branch-before-merge",
        "branch-after-merge",
        "branch-dropped",
        "branch-disposal",
        "handle-undo-peer-edit",
      ],
    );
    await validateLifecycleSection(
      "handleTransactionBranch",
      section,
      result.artifacts,
      result.validationContext,
    );
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("all retention writers reject semantic counterexamples", {
  timeout: 900_000,
}, async (t) => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-retention-all-${randomUUID()}`,
  );
  try {
    const results = await withLocalFloodgate(async (config) => {
      const captured = {};
      for (const writer of ["upstream", "javascript", "erlang"]) {
        captured[writer] = await runLifecycleInterop({
          config,
          scenario: `handleRetention:${writer}`,
          output: join(output, writer),
        });
      }
      return captured;
    });
    for (const [writer, result] of Object.entries(results)) {
      const section = result.report.sections.handleRetention;
      assert.equal(section.skipped, false);
      assert.deepEqual(section.expectedWriters, [writer]);
      assert.equal(section.rows.length, 1);
      await validateLifecycleSection(
        "handleRetention",
        section,
        result.artifacts,
        result.validationContext,
      );
    }
    const javascript = results.javascript;
    const mutateCheckpoint = (artifact, row, id, mutate) => {
      const reportCheckpoint = row.retention.checkpoints.find(
        (checkpoint) => checkpoint.id === id,
      );
      const artifactCheckpoint = artifact.retention.checkpoints.find(
        (checkpoint) => checkpoint.id === id,
      );
      assert(reportCheckpoint && artifactCheckpoint, `Missing checkpoint ${id}`);
      mutate(artifactCheckpoint, reportCheckpoint);
    };
    for (const [label, mutate, pattern] of [
      ["wrong GC timestamp", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "unreferenced-datastore",
          (captured, report) => {
            const id = captured.rawSnapshot.tree.trees.gc.blobs.__gc_root;
            const gc = JSON.parse(Buffer.from(
              captured.rawSnapshot.blobs[id],
              "base64",
            ).toString("utf8"));
            const secondaryId = row.targets.secondary.path.split("/")[1];
            gc.gcNodes[`/${secondaryId}`].unreferencedTimestampMs = 0;
            gc.gcNodes[row.targets.secondary.path].unreferencedTimestampMs = 0;
            const bytes = Buffer.from(JSON.stringify(gc));
            captured.rawSnapshot.blobs[id] = bytes.toString("base64");
            captured.snapshot.blobs[id] = hash(bytes);
            report.snapshot.blobs[id] = hash(bytes);
            captured.snapshot.evidence.gc = structuredClone(gc);
            report.snapshot.evidence.gc = structuredClone(gc);
          },
        ), /(?:unreferenced datastore|unreachable GC node).*timestamp/i],
      ["retained history target removed", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "retained-repair",
          (captured, report) => {
            const retained = captured.snapshot.evidence.retainedHandles.find(
              ({ path, markers }) =>
                /(Repair|EditManager|Detached)/i.test(path)
                  && markers.some(({ url }) => url === row.targets.target.path),
            );
            assert(retained, "Captured row lacks retained history target bytes");
            const bytes = Buffer.from(
              captured.rawSnapshot.blobs[retained.blobId],
              "base64",
            );
            const changed = Buffer.from(
              bytes.toString("utf8").replaceAll(
                row.targets.target.path,
                "/wrong-retained-target",
              ),
            );
            const changedHistory = JSON.parse(changed.toString("utf8")).trunk;
            captured.rawSnapshot.blobs[retained.blobId] =
              changed.toString("base64");
            captured.snapshot.blobs[retained.blobId] = hash(changed);
            report.snapshot.blobs[retained.blobId] = hash(changed);
            for (const evidence of [
              captured.snapshot.evidence.retainedHandles,
              report.snapshot.evidence.retainedHandles,
            ]) {
              const item = evidence.find(({ blobId }) =>
                blobId === retained.blobId);
              item.sha256 = hash(changed);
              item.history = item.history.map((commit, index) => ({
                ...commit,
                changeSha256: hash(JSON.stringify(changedHistory[index].change)),
              }));
              item.targetPresent = false;
              item.markers = item.markers.map((marker) => ({
                ...marker,
                url: marker.url === row.targets.target.path
                  ? "/wrong-retained-target"
                  : marker.url,
              }));
            }
          },
        ), /retained history lost the target handle/i],
      ["inverse lifetime shortened", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "branch-disposal",
          (captured, report) => {
            captured.lifetime.revertible = "Disposed";
            report.lifetime.revertible = "Disposed";
          },
        ), /branch disposal also disposed the inverse/i],
      ["metadata pin changed", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "fresh-load",
          (captured, report) => {
            const id = captured.rawSnapshot.tree.blobs[".metadata"];
            const metadata = JSON.parse(Buffer.from(
              captured.rawSnapshot.blobs[id],
              "base64",
            ).toString("utf8"));
            metadata.createContainerRuntimeVersion = "9.9.9";
            metadata.documentSchema.info.minVersionForCollab = "9.9.9";
            const bytes = Buffer.from(JSON.stringify(metadata));
            captured.rawSnapshot.blobs[id] = bytes.toString("base64");
            captured.snapshot.blobs[id] = hash(bytes);
            report.snapshot.blobs[id] = hash(bytes);
          },
        ), /persisted (runtime metadata version|minimum client)/i],
      ["compressor replaced with earlier state", (artifact, row) => {
        const source = artifact.retention.checkpoints[0];
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          const id = captured.rawSnapshot.tree.blobs[".idCompressor"];
          const sourceId = source.rawSnapshot.tree.blobs[".idCompressor"];
          const encoded = source.rawSnapshot.blobs[sourceId];
          const bytes = Buffer.from(encoded, "base64");
          captured.rawSnapshot.blobs[id] = encoded;
          captured.snapshot.blobs[id] = hash(bytes);
          report.snapshot.blobs[id] = hash(bytes);
          const compressor = {
            ...source.snapshot.evidence.compressor,
            blobId: id,
          };
          captured.snapshot.evidence.compressor = structuredClone(compressor);
          report.snapshot.evidence.compressor = structuredClone(compressor);
        });
      }, /compressor|allocation|identity context/i],
      ["fresh load target changed", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          captured.continuation.before.target = row.targets.secondary.path;
          report.continuation.before.target = row.targets.secondary.path;
        }), /fresh load resolved another target/i],
      ["unreferenced datastore made root-reachable", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "unreferenced-datastore",
          (captured, report) => {
            const id = captured.rawSnapshot.tree.trees.gc.blobs.__gc_root;
            const gc = JSON.parse(Buffer.from(
              captured.rawSnapshot.blobs[id],
              "base64",
            ).toString("utf8"));
            const secondaryId = row.targets.secondary.path.split("/")[1];
            gc.gcNodes["/"].outboundRoutes.push(`/${secondaryId}`);
            const bytes = Buffer.from(JSON.stringify(gc));
            captured.rawSnapshot.blobs[id] = bytes.toString("base64");
            captured.snapshot.blobs[id] = hash(bytes);
            report.snapshot.blobs[id] = hash(bytes);
            captured.snapshot.evidence.gc = structuredClone(gc);
            report.snapshot.evidence.gc = structuredClone(gc);
          },
        ), /GC|reachable|route/i],
      ["native lifetime receipts removed", (artifact, row) => {
        artifact.raw.nativeReplies = [];
        row.raw.nativeReplies = [];
        for (const captured of artifact.retention.checkpoints) {
          delete captured.lifetime.checkpoint;
        }
        for (const report of row.retention.checkpoints) {
          delete report.lifetime.checkpoint;
        }
      }, /lifetime|receipt|checkpoint/i],
      ["retained URL is not a handle marker", (artifact, row) =>
        mutateCheckpoint(
          artifact,
          row,
          "retained-repair",
          (captured, report) => {
            const retained = captured.snapshot.evidence.retainedHandles.find(
              ({ path }) => /EditManager\/String$/i.test(path),
            );
            assert(retained, "Captured row lacks retained history bytes");
            const bytes = Buffer.from(JSON.stringify({
              type: "not_a_handle",
              url: row.targets.target.path,
            }));
            captured.rawSnapshot.blobs[retained.blobId] =
              bytes.toString("base64");
            captured.snapshot.blobs[retained.blobId] = hash(bytes);
            report.snapshot.blobs[retained.blobId] = hash(bytes);
            for (const evidence of [
              captured.snapshot.evidence.retainedHandles,
              report.snapshot.evidence.retainedHandles,
            ]) {
              const item = evidence.find(({ blobId }) =>
                blobId === retained.blobId);
              item.sha256 = hash(bytes);
              item.targetPresent = true;
            }
          },
        ), /retained|handle marker|history/i],
      ["fresh loader receipts and continuation transport removed", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          delete captured.continuation.loader;
          delete report.continuation.loader;
          delete captured.continuation.transport;
          delete report.continuation.transport;
        }), /loader|storage|continuation transport|fresh load/i],
      ["fresh target attributes changed", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          const target = snapshotNode(captured.rawSnapshot, row.targets.target.path);
          const id = target.blobs[".attributes"];
          const stored = JSON.parse(Buffer.from(
            captured.rawSnapshot.blobs[id],
            "base64",
          ).toString("utf8"));
          stored.type = "not-a-shared-map";
          stored.packageVersion = "9.9.9";
          const bytes = Buffer.from(JSON.stringify(stored));
          captured.rawSnapshot.blobs[id] = bytes.toString("base64");
          captured.snapshot.blobs[id] = hash(bytes);
          report.snapshot.blobs[id] = hash(bytes);
          captured.snapshot.evidence.attributes.target =
            structuredClone(stored);
          report.snapshot.evidence.attributes.target = structuredClone(stored);
          captured.target.attachment.attributes = structuredClone(stored);
          report.target.attachment.attributes = structuredClone(stored);
        }), /attributes|shared map|package version/i],
      ["retained repair compressor replaced with sequence eight", (artifact, row) => {
        const source = artifact.retention.checkpoints[0];
        mutateCheckpoint(artifact, row, "retained-repair", (captured, report) => {
          const id = captured.rawSnapshot.tree.blobs[".idCompressor"];
          const sourceId = source.rawSnapshot.tree.blobs[".idCompressor"];
          const encoded = source.rawSnapshot.blobs[sourceId];
          const bytes = Buffer.from(encoded, "base64");
          captured.rawSnapshot.blobs[id] = encoded;
          captured.snapshot.blobs[id] = hash(bytes);
          report.snapshot.blobs[id] = hash(bytes);
          const compressor = {
            ...source.snapshot.evidence.compressor,
            blobId: id,
          };
          captured.snapshot.evidence.compressor = structuredClone(compressor);
          report.snapshot.evidence.compressor = structuredClone(compressor);
        });
      }, /compressor|allocation|identity context/i],
      ["positive GC timestamp reset at one checkpoint", (artifact, row) =>
        mutateCheckpoint(artifact, row, "unreferenced-datastore", (captured, report) => {
          const id = captured.rawSnapshot.tree.trees.gc.blobs.__gc_root;
          const gc = JSON.parse(Buffer.from(captured.rawSnapshot.blobs[id], "base64"));
          const store = `/${row.targets.secondary.path.split("/")[1]}`;
          for (const path of [store, row.targets.secondary.path]) {
            gc.gcNodes[path].unreferencedTimestampMs += 60_000;
          }
          const bytes = Buffer.from(JSON.stringify(gc));
          captured.rawSnapshot.blobs[id] = bytes.toString("base64");
          captured.snapshot.blobs[id] = report.snapshot.blobs[id] = hash(bytes);
          captured.snapshot.evidence.gc = structuredClone(gc);
          report.snapshot.evidence.gc = structuredClone(gc);
        }), /timestamp|unreference/i],
      ...["retention-redo", "retention-final"].map((name) => [
        `${name} acquisition receipt removed`,
        (artifact, row) => {
          const replies = artifact.raw.nativeReplies.filter(({ request }) =>
            !(request.op === "retainLastLocalCommit" && request.name === name));
          artifact.raw.nativeReplies = replies;
          row.raw.nativeReplies = structuredClone(replies);
        },
        /acquisition|lifetime|receipt/i,
      ]),
      ["branch lifetime receipt names another tree", (artifact, row) => {
        for (const raw of [artifact.raw, row.raw]) {
          for (const { request } of raw.nativeReplies) {
            if (["fork", "disposeBranch"].includes(request.op)) {
              request.tree = "another-tree";
            }
          }
        }
      }, /branch|owner|receipt/i],
      ["retained commit session changed", (artifact, row) =>
        mutateCheckpoint(artifact, row, "retained-repair", (captured, report) => {
          const retained = captured.snapshot.evidence.retainedHandles.find(
            ({ kind }) => kind === "history",
          );
          const decoded = JSON.parse(Buffer.from(
            captured.rawSnapshot.blobs[retained.blobId], "base64",
          ));
          decoded.trunk[0].sessionId = "00000000-0000-4000-8000-000000000000";
          const bytes = Buffer.from(JSON.stringify(decoded));
          captured.rawSnapshot.blobs[retained.blobId] = bytes.toString("base64");
          captured.snapshot.blobs[retained.blobId] =
            report.snapshot.blobs[retained.blobId] = hash(bytes);
          for (const checkpoint of [captured, report]) {
            const item = checkpoint.snapshot.evidence.retainedHandles.find(
              ({ blobId }) => blobId === retained.blobId,
            );
            item.sha256 = hash(bytes);
            if (Object.hasOwn(item.history[0], "sessionId")) {
              item.history[0].sessionId = decoded.trunk[0].sessionId;
            }
          }
        }), /retained.*(identity|session|commit)|history.*(identity|session)/i],
      ["valid-looking retained marker in an unrelated property", (artifact, row) =>
        mutateCheckpoint(artifact, row, "retained-repair", (captured, report) => {
          const retained = captured.snapshot.evidence.retainedHandles.find(
            ({ kind }) => kind === "history",
          );
          const decoded = JSON.parse(Buffer.from(
            captured.rawSnapshot.blobs[retained.blobId], "base64",
          ));
          const changed = replaceNested(decoded, "__fluid_handle__", "not_a_handle");
          changed.unrelated = structuredClone(retained.markers);
          const bytes = Buffer.from(JSON.stringify(changed));
          captured.rawSnapshot.blobs[retained.blobId] = bytes.toString("base64");
          captured.snapshot.blobs[retained.blobId] =
            report.snapshot.blobs[retained.blobId] = hash(bytes);
          for (const checkpoint of [captured, report]) {
            checkpoint.snapshot.evidence.retainedHandles.find(
              ({ blobId }) => blobId === retained.blobId,
            ).sha256 = hash(bytes);
          }
        }), /retained|handle|history/i],
      ["fresh loader receipt internals removed", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          for (const checkpoint of [captured, report]) {
            checkpoint.continuation.loader.versionReceipt = {};
            checkpoint.continuation.loader.treeReceipt = {};
          }
        }), /loader|receipt|storage/i],
      ["fresh continuation outbound targets another map", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          for (const checkpoint of [captured, report]) {
            const outbound = checkpoint.continuation.transport.outboundOccurrences[0];
            outbound.submissions = replaceNested(
              outbound.submissions,
              row.targets.target.path.split("/").at(-1),
              "another-target",
            );
            if (outbound.hash !== undefined) {
              outbound.hash = hash(JSON.stringify(outbound.submissions));
            }
          }
        }), /continuation.*(target|correspondence|submission)|outbound.*correspondence/i],
      ["fresh branch and inverse observations omitted", (artifact, row) =>
        mutateCheckpoint(artifact, row, "fresh-load", (captured, report) => {
          delete captured.continuation.localStacks.probes;
          delete report.continuation.localStacks.probes;
        }), /fresh.*(lifetime|branch|inverse)|probe/i],
      ["channel type expectations and stored attributes changed together", (artifact, row) => {
        const wrong = { ...row.targets.target.attributes, type: "wrong-map", packageVersion: "9.9.9" };
        artifact.targets.target.attributes = structuredClone(wrong);
        row.targets.target.attributes = structuredClone(wrong);
        for (const id of row.retention.checkpoints.map(({ id }) => id)) {
          mutateCheckpoint(artifact, row, id, (captured, report) => {
            const node = snapshotNode(captured.rawSnapshot, row.targets.target.path);
            const blob = node.blobs[".attributes"];
            const bytes = Buffer.from(JSON.stringify(wrong));
            captured.rawSnapshot.blobs[blob] = bytes.toString("base64");
            captured.snapshot.blobs[blob] = report.snapshot.blobs[blob] = hash(bytes);
            for (const checkpoint of [captured, report]) {
              checkpoint.snapshot.evidence.attributes.target = structuredClone(wrong);
              checkpoint.target.attachment.attributes = structuredClone(wrong);
            }
          });
        }
      }, /fixed.*attributes|target.*contract|attributes.*contract/i],
    ]) {
      await t.test(label, () => rejectArtifactMutation(
        "handleRetention",
        javascript,
        mutate,
        pattern,
        "javascript",
      ));
    }
    for (const writer of ["javascript", "erlang"]) {
      for (const [field, value] of [
        ["revision", "00000000-0000-4000-8000-000000000000"],
        ["kind", "WrongKind"],
        ["factoryAvailable", false],
      ]) {
        await t.test(`${writer} actual commit event contradicts ${field}`, () =>
          rejectArtifactMutation("handleRetention", results[writer], (artifact, row) => {
            const mutate = (record) => {
              if (!record || typeof record !== "object") return;
              if (record.type === "commit" && Number.isSafeInteger(record.eventId)) {
                record[field] = value;
              }
              for (const child of Object.values(record)) mutate(child);
            };
            mutate(artifact);
            mutate(row);
          }, /commit event|event.*(?:revision|kind|factory)/i, writer));
      }
      await t.test(`${writer} fork request contradicts its source receipt`, () =>
        rejectArtifactMutation("handleRetention", results[writer], (artifact, row) => {
          for (const raw of [artifact.raw, row.raw]) {
            for (const { request } of raw.nativeReplies) {
              if (request.op === "fork") request.source = "nonexistent-branch";
            }
          }
        }, /fork.*source|branch.*source/i, writer));
    }
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("all transaction branch writers reject semantic counterexamples", {
  timeout: 900_000,
}, async (t) => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-transactions-${randomUUID()}`,
  );
  try {
    const results = await withLocalFloodgate(async (config) => {
      const captured = {};
      for (const writer of ["upstream", "javascript", "erlang"]) {
        captured[writer] = await runLifecycleInterop({
          config,
          scenario: `handleTransactionBranch:${writer}`,
          output: join(output, writer),
        });
      }
      return captured;
    });
    for (const [writer, result] of Object.entries(results)) {
      const section = result.report.sections.handleTransactionBranch;
      assert.equal(section.skipped, false);
      assert.deepEqual(section.expectedWriters, [writer]);
      assert.equal(section.rows.length, 1);
      await validateLifecycleSection(
        "handleTransactionBranch",
        section,
        result.artifacts,
        result.validationContext,
      );
    }

    const javascript = results.javascript;
    const mutateHistory = (artifact, row, mutate) => {
      mutate(row.history);
      mutate(artifact.history);
    };
    const mutateHistoryEvent = (history, eventId, mutate) => {
      const seen = new WeakSet();
      const visit = (value) => {
        if (value === null || typeof value !== "object" || seen.has(value)) return;
        seen.add(value);
        if (value.id === eventId) mutate(value);
        for (const child of Object.values(value)) visit(child);
      };
      visit(history);
    };
    for (const [label, mutate, pattern] of [
      ["missing commit", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          const step = history.steps.find(
            ({ id }) => id === "successful-transaction",
          );
          step.checkpoint.commits = step.checkpoint.commits.filter(
            ({ type }) => type !== "commit",
          );
          if (history === artifact.history) {
            artifact.raw.nativeReplies.find(({ request, result }) =>
              request.command === "checkpoint"
              && result.commits.some(
                ({ actionId }) => actionId === step.inverse.actionId,
              )
            ).result.commits = step.checkpoint.commits;
          }
        },
      ), /successful transaction.*commit|actual revision/i],
      ["false factory acquisition", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          history.steps.find(
            ({ id }) => id === "successful-transaction",
          ).inverse.factoryAvailable = false;
          if (history === artifact.history) {
            artifact.raw.nativeReplies.find(({ request }) =>
              request.op === "retainLastLocalCommit"
              && request.name === "successful-edit"
            ).result.factoryAvailable = false;
          }
        },
      ), /successful transaction.*inverse factory/i],
      ["false event acquisition", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          const step = history.steps.find(
            ({ id }) => id === "successful-transaction",
          );
          step.checkpoint.commits.find(({ type }) => type === "commit")
            .handleAcquired = false;
          if (history === artifact.history) {
            artifact.raw.nativeReplies.find(({ request, result }) =>
              request.command === "checkpoint"
              && result.commits.some(
                ({ actionId }) => actionId === step.inverse.actionId,
              )
            ).result.commits.find(({ type }) => type === "commit")
              .handleAcquired = false;
          }
        },
      ), /event acquisition/i],
      ["invented revision", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          const step = history.steps.find(
            ({ id }) => id === "branch-after-merge",
          );
          const invented = "00000000-0000-4000-8000-000000000001";
          step.inverse.revision = invented;
          step.checkpoint.commits.find(({ type }) => type === "commit")
            .revision = invented;
          if (history === artifact.history) {
            artifact.raw.nativeReplies.find(({ request }) =>
              request.op === "retainLastLocalCommit"
              && request.name === "merge-edit"
            ).result.revision = invented;
            artifact.raw.nativeReplies.find(({ request, result }) =>
              request.command === "checkpoint"
              && result.commits.some(
                ({ actionId }) => actionId === step.inverse.actionId,
              )
            ).result.commits.find(({ type }) => type === "commit")
              .revision = invented;
          }
        },
      ), /document compressor|revision/i],
      ["wrong inverse target", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          history.steps.find(
            ({ id }) => id === "handle-undo-peer-edit",
          ).target = row.targets.branch.path;
        },
      ), /insertion inverse names another target/i],
      ["wrong abort outcome", (artifact, row) => {
        mutateHistory(artifact, row, (history) => {
          history.steps.find(
            ({ id }) => id === "aborted-transaction",
          ).transaction.outcome = "committed";
        });
        artifact.raw.nativeReplies.find(({ request }) =>
          request.command === "transaction" && request.result === "abort"
        ).result.outcome = "committed";
      }, /aborted handle transaction/i],
      ["wrong branch lifetime", (artifact, row) => {
        mutateHistory(artifact, row, (history) => {
          history.steps.find(
            ({ id }) => id === "branch-after-merge",
          ).merge.disposed = false;
        });
        artifact.raw.nativeReplies.find(({ request }) =>
          request.op === "mergeBranch"
          && request.source === "working"
          && request.target === "main"
        ).result.disposed = false;
      }, /branch lifetime/i],
      ["branch traffic classified as document", (artifact, row) => {
        mutateHistory(artifact, row, (history) => {
          history.steps.find(
            ({ id }) => id === "branch-before-merge",
          ).edit.outboundCount = 1;
        });
        artifact.raw.nativeReplies.find(
          ({ request }) => request.op === "branchEdit"
            && request.branch === "working",
        ).result.outboundCount = 1;
      }, /branch-only edit reached document transport/i],
      ["peer target data lost after undo", (artifact, row) => {
        for (const peers of [row.peer.observations, artifact.peers]) {
          for (const peer of Object.values(peers)) {
            peer.targets.undo.peer = "lost";
          }
        }
      }, /lost the peer target edit/i],
      ["missing refusal side-effect proof", (artifact, row) => mutateHistory(
        artifact,
        row,
        (history) => {
          history.activeTarget.refusal.after = "changed";
          history.steps.find(({ id }) => id === "active-target")
            .refusal.after = "changed";
        },
      ), /preflight mutated runtime state/i],
    ]) {
      await t.test(label, () => rejectArtifactMutation(
        "handleTransactionBranch",
        javascript,
        mutate,
        pattern,
        "javascript",
      ));
    }
    const upstream = results.upstream;
    for (const [label, mutate, pattern] of [
      ["nested callback result replaced", (artifact, row) =>
        mutateHistory(artifact, row, (history) => {
          history.steps.find(({ id }) => id === "nested-transaction")
            .transaction = {
              outerResult: "forged-outer",
              innerResult: "forged-inner",
            };
        }), /nested transaction.*callback result/i],
      ["upstream revision settlement removed", (artifact, row) =>
        mutateHistory(artifact, row, (history) => {
          const step = history.steps.find(
            ({ id }) => id === "successful-transaction",
          );
          step.revisions = [];
          step.settlements = [];
        }), /successful transaction.*revision|settlement/i],
      ["upstream duplicate acquisition accepted", (artifact, row) =>
        mutateHistory(artifact, row, (history) => {
          const event = history.steps.find(
            ({ id }) => id === "successful-transaction",
          ).events.find(({ acquired }) => acquired);
          mutateHistoryEvent(history, event.id, (candidate) => {
            candidate.duplicateError = "";
          });
        }), /duplicate.*acquisition/i],
      ["upstream inverse left valid", (artifact, row) =>
        mutateHistory(artifact, row, (history) => {
          const event = history.steps.find(
            ({ id }) => id === "successful-transaction",
          ).events.find(({ acquired }) => acquired);
          mutateHistoryEvent(history, event.id, (candidate) => {
            candidate.disposed = false;
            candidate.status = "Valid";
          });
        }), /successful transaction.*inverse disposal/i],
      ["branch discard replaced by disposal", (artifact, row) =>
        mutateHistory(artifact, row, (history) => {
          history.steps.find(({ id }) => id === "branch-dropped").discard = {
            authoredKind: "Missing",
            disposed: false,
            status: "Valid",
          };
        }), /branch-dropped.*discard/i],
    ]) {
      await t.test(label, () => rejectArtifactMutation(
        "handleTransactionBranch",
        upstream,
        mutate,
        pattern,
        "upstream",
      ));
    }
    await t.test("inner active fingerprint changed", () =>
      rejectArtifactMutation(
        "handleTransactionBranch",
        javascript,
        (artifact, row) => mutateHistory(artifact, row, (history) => {
          history.activeTarget.before.runtime = "changed";
          history.steps.find(({ id }) => id === "active-target")
            .before.runtime = "changed";
        }),
        /active callback.*runtime fingerprint/i,
        "javascript",
      ));
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("one real writer slice rejects raw and persisted evidence mutations", {
  timeout: 300_000,
}, async () => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-writer-${randomUUID()}`,
  );
  try {
    const captured = await withLocalFloodgate(async (config) => {
      const results = {};
      for (const name of [
        "handleValues",
        "channelAttachment",
        "datastoreAttachment",
      ]) {
        results[name] = await runLifecycleInterop({
          config,
          scenario: `${name}:javascript`,
          output: join(output, name),
        });
      }
      return results;
    });
    for (const [name, result] of Object.entries(captured)) {
      const section = result.report.sections[name];
      const row = section.rows[0];
      assert(row.raw.submitted.every(({ submissions, hash: actualHash }) =>
        Array.isArray(submissions) && submissions.length > 0
          && /^[a-f0-9]{64}$/.test(actualHash)),
      `${name}: raw outbound submissions were not preserved`);
      assert(row.raw.sequenced.every(({ contents }) => contents !== undefined),
        `${name}: raw sequenced contents were not preserved`);
      assert.equal(row.raw.dependencies.source, "sequenced",
        `${name}: dependency order was not derived from sequenced bytes`);
      await validateLifecycleSection(
        name,
        section,
        result.artifacts,
        result.validationContext,
      );

      for (const [label, mutate, pattern] of [
        ["raw submission omission", (copy) => {
          copy.rows[0].raw.submitted = [];
        }, /submitted.*attach|raw.*submitted/i],
        ["raw sequenced omission", (copy) => {
          copy.rows[0].raw.sequenced.shift();
        }, /sequenced|service history|attach|allocation|target/i],
        ["raw attach reordering", (copy) => {
          const grouped = copy.rows[0].raw.sequenced
            .map(({ contents }) => contents)
            .find(({ contents }) => Array.isArray(contents) && contents.length > 2);
          const last = grouped.contents.length - 1;
          [grouped.contents[1], grouped.contents[last]] =
            [grouped.contents[last], grouped.contents[1]];
        }, /submitted contents|dependency|order|before attachment/i],
        ["raw target", (copy) => {
          const path = copy.rows[0].targets.map.path;
          copy.rows[0].raw.sequenced = replaceNested(
            copy.rows[0].raw.sequenced,
            path,
            "/wrong/raw-target",
          );
        }, /submitted contents|target|attachment/i],
        ["raw revision", (copy) => {
          assert(copy.rows[0].raw.sequenced.some(changeFirstRevision));
        }, /submitted contents|revision|dependency/i],
        ["missing native peer", (copy) => {
          delete copy.rows[0].peer.observations.erlang;
        }, /peer implementation coverage/i],
        ["divergent graph edge", (copy) => {
          copy.rows[0].peer.observations.erlang.graph.main.optional =
            "/wrong/peer-edge";
        }, /loaded graph edges/i],
        ["row pin", (copy) => {
          copy.rows[0].contract.reference.commit = "wrong";
        }, /pins|formats/i],
      ]) {
        const changed = structuredClone(section);
        mutate(changed);
        await assert.rejects(
          () => validateLifecycleSection(
            name,
            changed,
            result.artifacts,
            result.validationContext,
          ),
          pattern,
          `${name}: ${label}`,
        );
      }
    }

    const channel = captured.channelAttachment;
    await rejectArtifactMutation(
      "channelAttachment",
      channel,
      (artifact, row) => {
        const node = snapshotNode(artifact.snapshot, row.targets.map.path);
        const id = node.blobs[".attributes"];
        const attributes = JSON.parse(
          Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
        );
        attributes.packageVersion = "9.9.9";
        const bytes = Buffer.from(JSON.stringify(attributes));
        replaceSnapshotBlob(artifact, row, id, bytes);
        row.snapshot.evidence.targets.map.attributes = attributes;
        row.snapshot.evidence.targets.map.attributesSha256 =
          hash(JSON.stringify(attributes));
      },
      /persisted attributes|pinned attributes/i,
    );
    await rejectArtifactMutation(
      "channelAttachment",
      channel,
      (artifact, row) => {
        const id = artifact.snapshot.tree.blobs[".idCompressor"];
        const encoded = JSON.parse(
          Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
        );
        const state = Buffer.from(encoded, "base64");
        state.writeDoubleLE(3, 0);
        const bytes = Buffer.from(JSON.stringify(state.toString("base64")));
        replaceSnapshotBlob(artifact, row, id, bytes);
        row.snapshot.evidence.compressor = {
          ...row.snapshot.evidence.compressor,
          sha256: hash(bytes),
          stateSha256: hash(state),
          formatVersion: 3,
        };
      },
      /compressor format/i,
    );
    await rejectArtifactMutation(
      "channelAttachment",
      channel,
      (artifact, row) => {
        const main = snapshotNode(artifact.snapshot, "/A/_C");
        const forest = main.trees.indexes.trees.Forest;
        const id = forest.blobs.contents;
        const decoded = JSON.parse(
          Buffer.from(artifact.snapshot.blobs[id], "base64").toString("utf8"),
        );
        decoded.fields.data[0][2][0].url = "/wrong/stored-edge";
        const bytes = Buffer.from(JSON.stringify(decoded));
        replaceSnapshotBlob(artifact, row, id, bytes);
        row.snapshot.evidence.main.graph.optional = "/wrong/stored-edge";
      },
      /persisted main-tree graph/i,
    );
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("lifecycle synchronization waits for the native processed watermark", async () => {
  const container = () => ({
    isDirty: false,
    deltaManager: {
      inbound: { length: 0 },
      outbound: { length: 0 },
      lastSequenceNumber: 5,
    },
  });
  const creator = container();
  const writer = container();
  const peer = container();
  const receipts = [];
  await synchronize({
    creator: { container: creator },
    upstreamSession: { container: writer },
    peerSession: { container: peer },
    natives: [{
      async awaitSynced(minimumSequenceNumber) {
        receipts.push({ minimumSequenceNumber, sequenceNumber: 6 });
        creator.deltaManager.lastSequenceNumber = 6;
        writer.deltaManager.lastSequenceNumber = 6;
        setImmediate(() => {
          peer.deltaManager.lastSequenceNumber = 6;
        });
        return { sequenceNumber: 6 };
      },
    }],
  });
  assert.deepEqual(receipts, [{ minimumSequenceNumber: 5, sequenceNumber: 6 }]);
  assert.equal(peer.deltaManager.lastSequenceNumber, 6);
});

test("all implemented bounded rows validate exact peers publications and pins", {
  timeout: 600_000,
}, async (t) => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-nine-${randomUUID()}`,
  );
  try {
    const result = await withLocalFloodgate((config) =>
      runLifecycleInterop({ bounded: true, config, output }));
    assert.deepEqual(Object.keys(result.report.sections), [
      "handleValues",
      "channelAttachment",
      "datastoreAttachment",
      "handleTransactionBranch",
      "handleRetention",
      "handleReconnect",
    ]);
    assert.equal(Object.values(result.report.sections)
      .flatMap(({ rows }) => rows).length, 18);
    for (const [name, section] of Object.entries(result.report.sections)) {
      await validateLifecycleSection(name, section, result.artifacts);
    }
    await t.test("transaction selection and rows cannot shrink coverage", async () => {
      const section = structuredClone(
        result.report.sections.handleTransactionBranch,
      );
      section.selection = { kind: "writer", writer: "upstream" };
      section.expectedWriters = ["upstream"];
      section.rows = section.rows.filter(({ writer }) => writer === "upstream");
      await assert.rejects(
        () => validateLifecycleSection(
          "handleTransactionBranch",
          section,
          result.artifacts,
        ),
        /complete section writer selection|declared writers|required writer coverage/i,
      );
    });
    await t.test("retention selection and rows cannot shrink coverage", async () => {
      const section = structuredClone(result.report.sections.handleRetention);
      section.selection = { kind: "writer", writer: "upstream" };
      section.expectedWriters = ["upstream"];
      section.rows = section.rows.filter(({ writer }) => writer === "upstream");
      await assert.rejects(
        () => validateLifecycleSection(
          "handleRetention",
          section,
          result.artifacts,
        ),
        /complete section writer selection|declared writers|required writer coverage/i,
      );
    });
    await t.test("transaction peer declaration cannot shrink coverage", () =>
      rejectArtifactMutation(
        "handleTransactionBranch",
        result,
        (artifact, row) => {
          delete row.peer.observations.erlang;
          delete artifact.peers.erlang;
          row.peer.expectedImplementations =
            row.peer.expectedImplementations.filter(
              (implementation) => implementation !== "erlang",
            );
        },
        /peer implementation (?:policy|coverage)/i,
        "upstream",
      ));
    await t.test("retention peer declaration cannot shrink coverage", () =>
      rejectArtifactMutation(
        "handleRetention",
        result,
        (artifact, row) => {
          delete row.peer.observations.erlang;
          delete artifact.peers.erlang;
          row.peer.expectedImplementations =
            row.peer.expectedImplementations.filter(
              (implementation) => implementation !== "erlang",
            );
        },
        /peer implementation (?:policy|coverage)/i,
        "upstream",
      ));
    await rejectRoundOneCounterexamples(t, result);

    await t.test("allocation moved after its dependent uses", () =>
      rejectArtifactMutation(
        "channelAttachment",
        result,
        (artifact, row) => {
          moveAllocationAfterDependentUse(row.raw);
          moveAllocationAfterDependentUse(artifact.raw);
        },
        /allocation.*before|identity context/i,
        "upstream",
      ));

    for (const writer of ["upstream", "javascript", "erlang"]) {
      await t.test(`${writer} allocation moved after attachment only`, () =>
        rejectArtifactMutation(
          "channelAttachment",
          result,
          (artifact, row) => {
            moveAllocationAfterDependentUse(row.raw, true);
            moveAllocationAfterDependentUse(artifact.raw, true);
          },
          /allocation.*before|identity context/i,
          writer,
        ));
    }
    await t.test("compact additional-channel allocation moved after attachment", () =>
      rejectArtifactMutation(
        "datastoreAttachment",
        result,
        (artifact, row) => {
          const id = row.targets.additional.path.split("/").at(-1);
          assert(id.startsWith("_"), "Upstream additional channel is not compact");
          moveAllocationAfterDependentUse(row.raw, true, id);
          moveAllocationAfterDependentUse(artifact.raw, true, id);
        },
        /allocation.*before|identity context/i,
        "upstream",
      ));

    const upstreamRow = result.report.sections.channelAttachment.rows.find(
      ({ writer }) => writer === "upstream",
    );
    assert(upstreamRow.raw.dependencies.commits.every(({ revision }) =>
      revision < 0), "Upstream row no longer has all-negative revisions");
    const foreignRow = result.report.sections.handleValues.rows.find(
      ({ writer }) => writer === "javascript",
    );
    const foreignArtifact = JSON.parse(await readFile(
      join(result.artifacts.root, foreignRow.artifacts[0].path),
    ));
    const foreignCompressorId =
      foreignArtifact.snapshot.tree.blobs[".idCompressor"];
    const foreignCompressorBytes = Buffer.from(
      foreignArtifact.snapshot.blobs[foreignCompressorId],
      "base64",
    );
    await t.test("valid foreign compressor for all-negative revisions", () =>
      rejectArtifactMutation(
        "channelAttachment",
        result,
        (artifact, row) => {
          const id = artifact.snapshot.tree.blobs[".idCompressor"];
          const encoded = JSON.parse(foreignCompressorBytes.toString("utf8"));
          const state = Buffer.from(encoded, "base64");
          replaceSnapshotBlob(artifact, row, id, foreignCompressorBytes);
          row.snapshot.evidence.compressor = {
            ...row.snapshot.evidence.compressor,
            sha256: hash(foreignCompressorBytes),
            stateSha256: hash(state),
            byteLength: state.length,
          };
        },
        /compressor revision|finalized identity|originator/i,
        "upstream",
      ));

    const upstream = structuredClone(
      result.report.sections.channelAttachment,
    );
    const mutatedUpstreamRow = upstream.rows.find(
      ({ writer }) => writer === "upstream",
    );
    mutatedUpstreamRow.raw.publication.acknowledgementSequenceNumber =
      mutatedUpstreamRow.raw.sequenced.find(
        ({ type }) => type === "op",
      ).sequenceNumber;
    await assert.rejects(
      () => validateLifecycleSection(
        "channelAttachment",
        upstream,
        result.artifacts,
      ),
      /summaryAck|acknowledgement/i,
    );

    for (const [level, mutate, validate] of [
      ["wrapper", (copy) => {
        copy.contract.reference.version = "wrong";
      }, (copy) => validateLifecycleReport(copy, result.artifacts)],
      ["section", (copy) => {
        copy.contract.oldestSupportedClient = "wrong";
      }, (copy) => validateLifecycleSection(
        "handleValues",
        copy,
        result.artifacts,
      )],
      ["row", (copy) => {
        copy.rows[0].contract.formats.message = 6;
      }, (copy) => validateLifecycleSection(
        "handleValues",
        copy,
        result.artifacts,
      )],
    ]) {
      const copy = structuredClone(
        level === "wrapper"
          ? result.report
          : result.report.sections.handleValues,
      );
      mutate(copy);
      await assert.rejects(() => validate(copy), /pins|formats/i, level);
    }
    await rejectArtifactMutation(
      "handleValues",
      result,
      (artifact) => {
        artifact.contract.service.revision = "wrong";
      },
      /pins|formats/i,
    );
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test("construction failures close actual containers and failed-sync peers", {
  timeout: 300_000,
}, async () => {
  const output = join(
    import.meta.dirname,
    `.output/lifecycle-cleanup-${randomUUID()}`,
  );
  try {
    await withLocalFloodgate(async (config) => {
      const opened = [];
      let calls = 0;
      await assert.rejects(
        () => runLifecycleInterop({
          config,
          scenario: "handleValues:upstream",
          output: join(output, "container"),
          constructors: {
            nativeAdapter,
            openSession: async (...args) => {
              const session = await openSession(...args);
              opened.push(session.container);
              calls += 1;
              if (calls === 2) throw new Error("injected open-session failure");
              return session;
            },
          },
        }),
        /injected open-session failure/,
      );
      assert(opened.length > 0 && opened.every(({ closed }) => closed),
        "Partially constructed containers were not disposed");

      let peerClosed = false;
      await assert.rejects(
        () => runLifecycleInterop({
          config,
          scenario: "handleValues:javascript",
          output: join(output, "peer"),
          constructors: {
            openSession,
            nativeAdapter: async (target, ...args) => {
              const adapter = await nativeAdapter(target, ...args);
              if (target !== "erlang") return adapter;
              return {
                ...adapter,
                async awaitSynced() {
                  await adapter.awaitSynced();
                  throw new Error("injected peer awaitSynced failure");
                },
                async close() {
                  peerClosed = true;
                  await adapter.close();
                },
              };
            },
          },
        }),
        /injected peer awaitSynced failure/,
      );
      assert.equal(peerClosed, true, "Failed-sync native peer was not closed");
    });
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});
