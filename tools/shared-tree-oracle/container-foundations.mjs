import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ContainerMessageType } from "@fluidframework/container-runtime/internal";
import { SummaryType } from "@fluidframework/driver-definitions";
import { DataStoreMessageType } from "@fluidframework/datastore/internal";
import {
  RequestParser,
  convertSummaryTreeToITree,
  encodeHandleForSerialization,
  generateHandleContextPath,
  processAttachMessageGCData,
} from "@fluidframework/runtime-utils/internal";

const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

function requireCase(existingCases, id) {
  const value = existingCases.find((item) => item?.id === id);
  if (value === undefined) {
    throw new Error(`container foundations require ${id}`);
  }
  if (
    value.formatVersion !== 1
    || value.reference?.package !== reference.package
    || value.reference?.version !== reference.version
    || value.reference?.commit !== reference.commit
  ) {
    throw new Error(`${id} has a different reference`);
  }
  return value;
}

async function containerRuntimePrivate(relativePath) {
  const entry = fileURLToPath(import.meta.resolve("@fluidframework/container-runtime/internal"));
  const packageRoot = dirname(dirname(entry));
  return import(pathToFileURL(join(packageRoot, "lib", relativePath)).href);
}

function blob(content) {
  return { type: SummaryType.Blob, content };
}

function tree(entries) {
  return { type: SummaryType.Tree, tree: entries };
}

function attachSnapshot(entries) {
  return convertSummaryTreeToITree(tree(entries));
}

function mapSnapshot(mapAttributes, mapHeader) {
  return attachSnapshot({
    ".attributes": blob(JSON.stringify(mapAttributes)),
    header: blob(JSON.stringify(mapHeader)),
  });
}

function datastoreSnapshot(component, channelId, channelSummary) {
  return attachSnapshot({
    ".component": blob(JSON.stringify(component)),
    ".channels": tree({ [channelId]: channelSummary }),
  });
}

function decodeContents(value) {
  return typeof value === "string" ? JSON.parse(value) : value;
}

function messageObservation(contents) {
  switch (contents?.type) {
    case ContainerMessageType.IdAllocation:
      return { kind: "idAllocation", range: contents.contents };
    case ContainerMessageType.Attach:
      return {
        kind: "datastoreAttach",
        dataStoreId: contents.contents.id,
        contents: contents.contents,
      };
    case ContainerMessageType.Alias:
      return {
        kind: "datastoreAlias",
        dataStoreId: contents.contents.internalId,
        alias: contents.contents.alias,
      };
    case ContainerMessageType.FluidDataStoreOp: {
      const dataStoreId = contents.contents.address;
      const inner = contents.contents.contents;
      if (inner?.type === DataStoreMessageType.ChannelOp) {
        return {
          kind: "channelOperation",
          route: {
            dataStoreId,
            channelId: inner.content.address,
          },
          contents: inner.content.contents,
        };
      }
      if (inner?.type === DataStoreMessageType.Attach) {
        return {
          kind: "channelAttach",
          route: {
            dataStoreId,
            channelId: inner.content.id,
          },
          channelType: inner.content.type,
          snapshot: inner.content.snapshot,
        };
      }
      throw new Error(`unsupported datastore message ${inner?.type}`);
    }
    default:
      throw new Error(`unsupported container message ${contents?.type}`);
  }
}

function groupedObservation(message) {
  const contents = decodeContents(message.contents);
  if (contents?.type !== "groupedBatch" || !Array.isArray(contents.contents)) {
    throw new Error("batched-commits has no grouped batch");
  }
  return {
    kind: "decodedBatch",
    grouped: true,
    outer: {
      clientId: message.clientId,
      clientSequenceNumber: message.clientSequenceNumber,
      minimumSequenceNumber: message.minimumSequenceNumber,
      referenceSequenceNumber: message.referenceSequenceNumber,
      sequenceNumber: message.sequenceNumber,
    },
    metadata: message.metadata,
    messages: contents.contents.map((item, index) => ({
      index,
      metadata: item.metadata,
      message: messageObservation(item.contents),
    })),
  };
}

function singletonObservation(id, contents, metadata) {
  return {
    kind: "decodedCase",
    id,
    grouped: false,
    metadata,
    messages: [{
      index: 0,
      metadata,
      message: messageObservation(contents),
    }],
  };
}

function bootstrapMessagesObservation(messages, projection) {
  return {
    kind: "bootstrapMessages",
    messages: messages.map((outer) => {
      const contents = decodeContents(outer.contents);
      const message = messageObservation(contents);
      const value = message.contents?.value;
      const handle = value?.type === "Plain" && value.value?.type === "__fluid_handle__"
        ? value.value
        : undefined;
      const route = handle === undefined
        ? undefined
        : RequestParser.getPathParts(handle.url);
      const targetType = route?.[0] === "A" && route?.[1] === "root"
        ? projection.mapAttributes.type
        : route?.[0] === "A" && route?.[1] === "_C"
          ? projection.treeAttributes.type
          : undefined;
      return {
        outer: {
          clientId: outer.clientId,
          clientSequenceNumber: outer.clientSequenceNumber,
          minimumSequenceNumber: outer.minimumSequenceNumber,
          referenceSequenceNumber: outer.referenceSequenceNumber,
          sequenceNumber: outer.sequenceNumber,
        },
        metadata: outer.metadata,
        message,
        ...(handle === undefined
          ? {}
          : {
              resolvedHandle: {
                path: handle.url,
                route: { dataStoreId: route[0], channelId: route[1] },
                targetType,
              },
            }),
      };
    }),
  };
}

function encodedObservation(id, contents, accepted) {
  return { kind: "encodedCase", id, contents, upstreamAccepted: accepted };
}

function snapshotProjection(snapshot) {
  const channels = snapshot.tree.trees[".channels"].trees.A.trees[".channels"].trees;
  const mapTree = channels.root;
  const treeTree = channels._C;
  const read = (id) => JSON.parse(Buffer.from(snapshot.blobs[id], "base64"));
  return {
    mapHeader: read(mapTree.blobs.header),
    mapAttributes: read(mapTree.blobs[".attributes"]),
    treeAttributes: read(treeTree.blobs[".attributes"]),
  };
}

export async function captureContainerFoundations(existingCases) {
  const bootstrap = requireCase(existingCases, "bootstrap-map-handles");
  const batched = requireCase(existingCases, "batched-commits");
  const initialSnapshot = bootstrap.input.decoderInput.initialSnapshot;
  const bootstrapMessages = bootstrap.input.decoderInput.bootstrapMessages;
  const groupedWireMessages = batched.input.decoderInput.groupedWireMessages;
  if (!Array.isArray(bootstrapMessages) || bootstrapMessages.length === 0) {
    throw new Error("bootstrap-map-handles has no bootstrap messages");
  }
  if (!Array.isArray(groupedWireMessages) || groupedWireMessages.length === 0) {
    throw new Error("batched-commits has no grouped wire messages");
  }

  const projection = snapshotProjection(initialSnapshot);
  const mapSnapshotValue = mapSnapshot(
    projection.mapAttributes,
    projection.mapHeader,
  );
  const datastoreAttachSnapshot = datastoreSnapshot(
    {
      pkg: ["org.watershed.shared-tree.m1.bootstrap"],
      summaryFormatVersion: 2,
      isRootDataStore: false,
    },
    "root",
    tree({
      ".attributes": blob(JSON.stringify(projection.mapAttributes)),
      header: blob(JSON.stringify(projection.mapHeader)),
    }),
  );

  const singleton = {
    type: ContainerMessageType.FluidDataStoreOp,
    contents: {
      address: "A",
      contents: {
        type: DataStoreMessageType.ChannelOp,
        content: {
          address: "root",
          contents: { type: "delete", key: "tree" },
        },
      },
    },
  };
  const datastoreAttach = {
    type: ContainerMessageType.Attach,
    contents: {
      id: "B",
      type: "org.watershed.shared-tree.m1.bootstrap",
      snapshot: datastoreAttachSnapshot,
    },
  };
  const alias = {
    type: ContainerMessageType.Alias,
    contents: { internalId: "B", alias: "secondary" },
  };
  const channelAttach = {
    type: ContainerMessageType.FluidDataStoreOp,
    contents: {
      address: "A",
      contents: {
        type: DataStoreMessageType.Attach,
        content: {
          id: "root-copy",
          type: projection.mapAttributes.type,
          snapshot: mapSnapshotValue,
        },
      },
    },
  };

  const [{ isDataStoreAliasMessage }, { OpGroupingManager, isGroupedBatch }] =
    await Promise.all([
      containerRuntimePrivate("dataStore.js"),
      containerRuntimePrivate("opLifecycle/opGroupingManager.js"),
    ]);
  const aliasAccepted = isDataStoreAliasMessage(alias.contents);
  processAttachMessageGCData(datastoreAttach.contents.snapshot, () => {});
  processAttachMessageGCData(
    channelAttach.contents.contents.content.snapshot,
    () => {},
  );

  const manager = new OpGroupingManager(
    { groupedBatchingEnabled: true },
    { send: () => {} },
  );
  const grouped = manager.groupBatch({
    contentSizeInBytes: 0,
    hasReentrantOps: false,
    referenceSequenceNumber: 0,
    messages: [
      {
        contents: JSON.stringify(singleton),
        metadata: { batch: true, batchId: "container-foundations" },
        referenceSequenceNumber: 0,
      },
      {
        contents: JSON.stringify(alias),
        metadata: { batch: false },
        referenceSequenceNumber: 0,
      },
    ],
  });
  const groupedContents = JSON.parse(grouped.messages[0].contents);
  const groupedAccepted = isGroupedBatch({ contents: groupedContents });

  const absolutePath = generateHandleContextPath("/A/_C");
  const relativePath = generateHandleContextPath("_C", { absolutePath: "/A" });
  const serializedHandle = encodeHandleForSerialization({ absolutePath });
  const escapedPath = "/A%2FB/caf%C3%A9";
  const escapedParts = RequestParser.getPathParts(escapedPath);

  const decodeCases = [
    { id: "singleton-channel-op", contents: singleton, metadata: { outer: "single" } },
    { id: "datastore-attach", contents: datastoreAttach, metadata: null },
    { id: "datastore-alias", contents: alias },
    { id: "channel-attach", contents: channelAttach },
  ];
  const encodeCases = [
    {
      id: "channel-operation",
      message: messageObservation(singleton),
      expected: singleton,
    },
    {
      id: "datastore-attach",
      message: messageObservation(datastoreAttach),
      expected: datastoreAttach,
    },
    {
      id: "datastore-alias",
      message: messageObservation(alias),
      expected: alias,
    },
    {
      id: "channel-attach",
      message: messageObservation(channelAttach),
      expected: channelAttach,
    },
    {
      id: "grouped-batch",
      batch: {
        grouped: true,
        metadata: grouped.messages[0].metadata,
        messages: [
          {
            index: 0,
            metadata: { batch: true, batchId: "container-foundations" },
            message: messageObservation(singleton),
          },
          {
            index: 1,
            metadata: { batch: false },
            message: messageObservation(alias),
          },
        ],
      },
      expected: groupedContents,
    },
  ];
  const handleCases = [
    {
      id: "absolute",
      value: serializedHandle,
      contextPath: "/B",
      expectedPath: absolutePath,
    },
    {
      id: "relative",
      value: { type: "__fluid_handle__", url: "_C" },
      contextPath: "/A",
      expectedPath: relativePath,
    },
    {
      id: "escaped",
      value: { type: "__fluid_handle__", url: escapedPath },
      contextPath: "/B",
      expectedPath: escapedPath,
    },
  ];

  const bootstrapObservation = {
    kind: "bootstrap",
    mapType: projection.mapAttributes.type,
    mapSnapshotFormatVersion: projection.mapAttributes.snapshotFormatVersion,
    mapPackageVersion: projection.mapAttributes.packageVersion,
    valueType: projection.mapHeader.content.tree.type,
    handleType: projection.mapHeader.content.tree.value.type,
    handlePath: projection.mapHeader.content.tree.value.url,
    route: { dataStoreId: "A", channelId: "_C" },
    treeType: projection.treeAttributes.type,
    treeSnapshotFormatVersion: projection.treeAttributes.snapshotFormatVersion,
    treePackageVersion: projection.treeAttributes.packageVersion,
  };

  return {
    formatVersion: 1,
    reference,
    id: "container-foundations",
    domain: "container",
    input: {
      initialSnapshot,
      bootstrapMessages,
      groupedWireMessages,
      decodeCases,
      encodeCases,
      handleCases,
    },
    expected: {
      observations: [
        singletonObservation(
          decodeCases[0].id,
          decodeCases[0].contents,
          decodeCases[0].metadata,
        ),
        singletonObservation(
          decodeCases[1].id,
          decodeCases[1].contents,
          decodeCases[1].metadata,
        ),
        singletonObservation(
          decodeCases[2].id,
          decodeCases[2].contents,
          decodeCases[2].metadata,
        ),
        singletonObservation(
          decodeCases[3].id,
          decodeCases[3].contents,
          decodeCases[3].metadata,
        ),
        groupedObservation(groupedWireMessages[0]),
        bootstrapMessagesObservation(bootstrapMessages, projection),
        ...handleCases.map((item) => ({
          kind: "handle",
          id: item.id,
          path: item.expectedPath,
          parts: RequestParser.getPathParts(item.expectedPath),
          encoded: encodeHandleForSerialization({ absolutePath: item.expectedPath }),
        })),
        ...encodeCases.map((item) =>
          encodedObservation(
            item.id,
            item.expected,
            item.id === "grouped-batch" ? groupedAccepted : true,
          )),
        bootstrapObservation,
      ],
    },
    raw: {
      source: {
        containerMessages: "packages/runtime/container-runtime/src/messageTypes.ts",
        datastoreMessages: "packages/runtime/datastore/src/dataStoreRuntime.ts",
        handles: "packages/runtime/runtime-utils/src/handles.ts",
        handlePaths: "packages/runtime/runtime-utils/src/dataStoreHandleContextUtils.ts",
        requestPaths: "packages/runtime/runtime-utils/src/requestParser.ts",
        grouping:
          "packages/runtime/container-runtime/src/opLifecycle/opGroupingManager.ts",
      },
      consumers: {
        alias: { accepted: aliasAccepted, message: alias },
        datastoreAttach: { accepted: true, message: datastoreAttach },
        channelAttach: { accepted: true, message: channelAttach },
        groupedBatch: { accepted: groupedAccepted, contents: groupedContents },
        handle: {
          absolute: absolutePath,
          relative: relativePath,
          serialized: serializedHandle,
          escapedPath,
          escapedParts,
        },
      },
      bootstrap: projection,
    },
  };
}
