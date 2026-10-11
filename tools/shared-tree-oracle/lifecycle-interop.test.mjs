import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import {
  runLifecycleInterop,
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
  return Object.values(value).some(changeFirstRevision);
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
      () => validateLifecycleSection(name, section, artifacts),
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
      await validateLifecycleSection(name, section, result.artifacts);

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
          () => validateLifecycleSection(name, changed, result.artifacts),
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

test("all nine foundation rows validate exact peers publications and pins", {
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
    ]);
    assert.equal(Object.values(result.report.sections)
      .flatMap(({ rows }) => rows).length, 9);
    for (const [name, section] of Object.entries(result.report.sections)) {
      await validateLifecycleSection(name, section, result.artifacts);
    }
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
