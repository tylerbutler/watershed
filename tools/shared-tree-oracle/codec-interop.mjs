const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function requireValue(condition, detail) {
  if (!condition) throw new Error(`Invalid native codec artifact: ${detail}`);
}

export function validateNativeArtifact(artifact) {
  requireValue(object(artifact) && artifact.formatVersion === 1, "formatVersion");
  requireValue(JSON.stringify(artifact.reference) === JSON.stringify(reference), "reference");
  requireValue(artifact.target === "erlang" || artifact.target === "javascript", "target");
  requireValue(Array.isArray(artifact.items) && artifact.items.length > 0, "items");
  const ids = new Set();
  for (const item of artifact.items) {
    requireValue(object(item) && typeof item.id === "string" && item.id.length > 0, "item id");
    requireValue(!ids.has(item.id), `duplicate item ${item.id}`);
    ids.add(item.id);
    requireValue(["schema", "fieldBatch", "message", "summary"].includes(item.kind),
      `${item.id} kind`);
    requireValue(Object.hasOwn(item, "encoded"), `${item.id} encoded`);
    if (item.kind === "message" || item.kind === "summary") {
      requireValue(typeof item.compressor === "string" && item.compressor.length > 0,
        `${item.id} compressor`);
      requireValue(item.compressorMode === "ongoing" || item.compressorMode === "summary",
        `${item.id} compressorMode`);
      requireValue(typeof item.session === "string" && item.session.length > 0,
        `${item.id} session`);
    }
    if (item.kind === "message") {
      requireValue(object(item.initialSummary), `${item.id} initialSummary`);
      requireValue(Array.isArray(item.allocationRanges), `${item.id} allocationRanges`);
      for (const field of [
        "sequenceNumber", "referenceSequenceNumber", "minimumSequenceNumber",
      ]) {
        requireValue(Number.isSafeInteger(item[field]) && item[field] >= 0,
          `${item.id} ${field}`);
      }
      requireValue(item.indexInBatch === null
        || (Number.isSafeInteger(item.indexInBatch) && item.indexInBatch >= 0),
      `${item.id} indexInBatch`);
    }
  }
  return artifact;
}

export async function runCodecInterop() {
  throw new Error("Codec interoperability is not implemented");
}
