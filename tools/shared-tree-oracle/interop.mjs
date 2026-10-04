import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import {
  access,
  mkdir,
  readFile,
  realpath,
  rename,
  stat,
  writeFile,
} from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import {
  isDeepStrictEqual,
  parseArgs,
  promisify,
  stripVTControlCharacters,
} from "node:util";
import {
  runService as runReconnectCases,
  runTransactionReconnect,
  validateResults as validateReconnectResults,
  validateTransactionReconnectResults,
} from "./client-interop.mjs";
import {
  acceptedTreeOperations,
  decodeTreeSubmissions,
  generateSchedules,
  decodeReconnectPayload,
  loadReplayArtifact,
  matchReconnectOperations,
  replayFailure,
  requiredFailureCells,
  requiredSchemaRaceCells,
  requiredScenarioCells,
  runDeterministicCases,
  runFailureCases,
  runIdentifierFields,
  runSchemaCompatibility,
  runSchemaRaces,
  runSchemaReconnect,
  runSeededSchedules,
  runTransactionScenarios,
  runUndoRedoScenarios,
  validateIdentifierFields,
  validateTransactionCallbacks,
  validateTransactionConstraints,
} from "./interop-scenarios.mjs";
import {
  preflight,
  excludedFeatures,
  serviceConfig,
  supportedFeatures,
  validatePreflight,
  withLocalFloodgate,
} from "./service.mjs";
import {
  runArrayReloadMatrix,
  runIdentifierReloadMatrix,
  runMapReloadMatrix,
  nativeStorageLoad,
  runReloadMatrix,
  runSchemaReloadMatrices,
  runTransactionReloadMatrix,
  runUndoRedoReloadMatrix,
  storageLoad,
  validateArrayResults,
  validateIdentifierReloadResults,
  validateMapResults,
  validateSchemaReloadResults,
  validateSchemaTailReloadResults,
  validateTransactionReloadResults,
} from "./summary-interop.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const nativeTargets = ["javascript", "erlang"];
const requiredSchemaSections = [
  "schemaCompatibility",
  "schemaRaces",
  "schemaReconnect",
  "schemaReloadMatrix",
  "schemaTailReloadMatrix",
];
const requiredTransactionSections = [
  "transactionCallbacks",
  "transactionConstraints",
  "transactionReconnect",
  "transactionReloadMatrix",
];
export const requiredUndoRedoSections = [
  "undoRedoKinds",
  "undoRedoConcurrent",
  "undoRedoReconnect",
  "undoRedoReloadMatrix",
];
const requiredSchemaRaceIds = requiredSchemaRaceCells().map(({ id }) => id);
const oracleDirectory = resolve(import.meta.dirname);
const repository = resolve(oracleDirectory, "../..");
const execute = promisify(execFile);
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const service = {
  implementation: "floodgate",
  revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
};
const profileDigest =
  "588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813";
const runtimeOptions = {
  enableRuntimeIdCompressor: "on",
  compressionOptions: {
    minimumBatchSizeInBytes: "Infinity",
    compressionAlgorithm: "lz4",
  },
  summaryOptions: {
    summaryConfigOverrides: { state: "disabled" },
  },
};
const documentSchema = {
  version: 1,
  refSeq: 0,
  info: { minVersionForCollab: "2.117.0" },
  runtime: {
    explicitSchemaControl: true,
    idCompressorMode: "on",
    opGroupingEnabled: true,
  },
};
const channelAttributes = {
  bootstrap: {
    type: "https://graph.microsoft.com/types/map",
    snapshotFormatVersion: "0.2",
    packageVersion: "3.1.0",
  },
  tree: {
    type: "https://graph.microsoft.com/types/tree",
    snapshotFormatVersion: "0.0.0",
    packageVersion: "3.1.0",
  },
};
const verifiedArtifactMaps = new WeakMap();

function object(value, message) {
  assert(value && typeof value === "object" && !Array.isArray(value), message);
  return value;
}

function historyCommits(history) {
  return history.trunk.map((entry) => entry.commit ?? entry);
}

function rawChangeCount(raw) {
  if (raw && typeof raw === "object" && Array.isArray(raw.changes)) {
    return raw.changes.length;
  }
  if (typeof raw !== "string") return null;
  if (/Changeset\((?:changes:\s*)?\[\]\)/.test(raw)) return 0;
  return /(?:SchemaChange|DataChange)/.test(raw) ? 1 : null;
}

function historyContains(history, accepted, kind) {
  return historyCommits(history).some(({ revision, changeset }) =>
    changeset?.changeCount > 0
      && (() => {
        try {
          const decoded = decodeReconnectPayload(changeset.raw);
          return decoded.kind === kind
            && isDeepStrictEqual(
              decoded,
              decodeReconnectPayload(accepted.changeset),
            );
        } catch {
          return false;
        }
      })());
}

function reconnectRetryTrace(value, label) {
  assert(Array.isArray(value), `${label} lacks reconnect retry evidence`);
  assert(value.length <= 1, `${label} exceeds the reconnect retry bound`);
  for (const retry of value) {
    object(retry, `${label} has invalid reconnect retry evidence`);
    assert.deepEqual(Object.keys(retry).sort(),
      ["attempt", "code", "message", "operation"],
    `${label} reconnect retry evidence is not sanitized`);
    assert.equal(retry.attempt, 1,
      `${label} reconnect retry has an invalid attempt`);
    assert.equal(retry.code, "connection-failed",
      `${label} reconnect retry has another error code`);
    assert.equal(retry.operation, "await-synced",
      `${label} reconnect retry has another operation`);
    assert([
      "channel connect failed: Transport(Timeout)",
      'channel connect failed: Transport(StreamError("Closed"))',
    ].includes(retry.message),
    `${label} reconnect retry has another transport failure`);
  }
}

function pinnedProfile(profile) {
  object(profile, "Missing SharedTree profile");
  assert.equal(profile.formatVersion, 1, "Unsupported profile format");
  assert.deepEqual(profile.reference, reference, "Stale upstream reference");
  assert.equal(profile.service?.implementation, service.implementation,
    "Unsupported service implementation");
  assert.equal(profile.service?.revision, service.revision,
    "Stale service revision");
  assert.equal(profile.service?.transport, "socket.io",
    "Unsupported service transport");
  assert.deepEqual(profile.service?.driverPolicies, {
    enableDiscovery: false,
    enableLongPollingDowngrade: false,
    enableRestLess: true,
    enableWholeSummaryUpload: false,
  }, "Unsupported service driver policies");
  assert.equal(profile.service?.deltaStorageRoute,
    "/deltas/{tenantId}/{documentId}", "Unsupported delta storage route");
  assert.deepEqual(profile.service?.nativeTransport, {
    protocol: "phoenix",
    endpoint: "/socket/websocket",
    javascript: "watershed/transport_js",
    erlang: "aquamarine/phoenix",
  }, "Unsupported native transport profile");
  assert.deepEqual(profile.container?.runtimeOptions, runtimeOptions,
    "Unsupported container runtime options");
  assert.deepEqual(profile.container?.summarizerRuntimeOptions, {
    enableRuntimeIdCompressor: "on",
    compressionOptions: {
      minimumBatchSizeInBytes: "Infinity",
      compressionAlgorithm: "lz4",
    },
    summaryOptions: {
      summaryConfigOverrides: {
        state: "disableHeuristics",
        maxAckWaitTime: 15000,
        maxOpsSinceLastSummary: 7000,
        initialSummarizerDelayMs: 0,
      },
    },
  }, "Unsupported summarizer runtime options");
  assert.equal(profile.container?.oldestSupportedClient, "2.117.0",
    "Unsupported oldest client");
  assert.deepEqual(profile.container?.documentSchema, documentSchema,
    "Unsupported document schema");
  assert.equal(profile.container?.summaryFormatVersion, 1,
    "Unsupported summary format");
  assert.equal(profile.container?.gcFeature, 3, "Unsupported GC feature");
  assert.equal(profile.container?.bootstrapPath, "/A/root",
    "Unsupported bootstrap path");
  assert.equal(profile.container?.treePath, "/A/_C", "Unsupported tree path");
  assert.deepEqual(profile.container?.channelAttributes, channelAttributes,
    "Unsupported channel attributes");
  assert.deepEqual(profile.container?.dataStoreTypes,
    ["org.watershed.shared-tree.m1.bootstrap"], "Unsupported data store");
  assert.deepEqual(profile.container?.bootstrapChannelTypes,
    ["https://graph.microsoft.com/types/map"], "Unsupported bootstrap channel");
  assert.deepEqual(profile.supportedFeatures, supportedFeatures,
    "Unsupported positive feature profile");
  assert.deepEqual(profile.excludedFeatures, excludedFeatures,
    "Unsupported excluded feature profile");
  assert.deepEqual(profile.compressorFormat, { version: 2, byteOrder: "LE" },
    "Unsupported compressor format");
  assert.deepEqual(
    profile.codecTree?.children?.map(({ name, version }) => [name, version]),
    [
      ["Forest", 2],
      ["Schema", 2],
      ["DetachedFieldIndex", 2],
      ["EditManager", 7],
      ["Message", 7],
      ["FieldBatch", 2],
    ],
    "Unsupported codec profile",
  );
  return profile;
}

function unsignedInteger(value, name, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) {
  assert(typeof value === "string" && /^(0|[1-9]\d*)$/.test(value),
    `${name} must be an unsigned integer`);
  const number = Number(value);
  assert(Number.isSafeInteger(number) && number >= minimum && number <= maximum,
    `${name} is outside the supported range`);
  return number;
}

export function parseInteropOptions(args, { cwd = process.cwd() } = {}) {
  const { values, positionals } = parseArgs({
    args,
    allowPositionals: false,
    strict: true,
    options: {
      profile: { type: "string" },
      iterations: { type: "string" },
      seed: { type: "string" },
      output: { type: "string" },
      replay: { type: "string" },
      "external-floodgate": { type: "boolean", default: false },
    },
  });
  assert.deepEqual(positionals, [], "Interop does not accept positional arguments");
  const outputDirectory = values.output === undefined
    ? join(oracleDirectory, ".output/interop")
    : resolve(cwd, values.output);
  if (values.replay !== undefined) {
    assert(values.profile === undefined && values.iterations === undefined
      && values.seed === undefined && values["external-floodgate"] === false,
    "Replay mode does not accept acceptance options");
    return {
      mode: "replay",
      profilePath: undefined,
      iterations: undefined,
      seed: undefined,
      outputDirectory,
      replayPath: resolve(cwd, values.replay),
      externalFloodgate: false,
    };
  }
  return {
    mode: "acceptance",
    profilePath: values.profile === undefined
      ? join(repository, "test/fixtures/shared_tree/profile.json")
      : resolve(cwd, values.profile),
    iterations: unsignedInteger(values.iterations ?? "300", "--iterations", 300),
    seed: unsignedInteger(values.seed ?? "42", "--seed", 0, 0xffff_ffff),
    outputDirectory,
    replayPath: undefined,
    externalFloodgate: values["external-floodgate"],
  };
}

export async function loadInteropProfile(path) {
  const bytes = await readFile(path);
  const digest = createHash("sha256").update(bytes).digest("hex");
  assert.equal(digest, profileDigest, "SharedTree profile bytes changed");
  const profile = pinnedProfile(JSON.parse(bytes.toString("utf8")));
  return {
    profile,
    profileDigest: digest,
    profilePath: resolve(path),
  };
}

function json(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

async function writeJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, json(value));
}

async function writeStatus(runDirectory, phase, details = {}) {
  const path = join(runDirectory, "status.json");
  const temporary = `${path}.tmp`;
  await writeJson(temporary, { formatVersion: 1, phase, ...details });
  await rename(temporary, path);
}

function attachFailureDetail(error, name, value) {
  try {
    error[name] = value;
  } catch {
    // The primary error remains authoritative even when it is immutable.
  }
}

export async function recordAcceptanceFailure({
  runDirectory,
  error,
  runId,
  profileDigest,
}) {
  const existingFailure = error.failurePath;
  const failurePath = existingFailure ?? join(runDirectory, "failure.json");
  const coordinatorFailurePath = existingFailure
    ? join(runDirectory, "coordinator-failure.json")
    : failurePath;
  let coordinatorFailureWritten = false;
  try {
    await writeJson(coordinatorFailurePath, {
      formatVersion: 1,
      kind: "coordinator-failure",
      runId,
      profileDigest,
      phase: "acceptance",
      ...(existingFailure === undefined ? {} : {
        primaryFailurePath: existingFailure,
      }),
      error: failureDiagnostic(error),
    });
    coordinatorFailureWritten = true;
    attachFailureDetail(error, "coordinatorFailurePath", coordinatorFailurePath);
  } catch (diagnosticError) {
    attachFailureDetail(error, "coordinatorDiagnosticError", diagnosticError);
  }
  if (existingFailure || coordinatorFailureWritten) {
    attachFailureDetail(error, "failurePath", failurePath);
  }
  try {
    await writeStatus(runDirectory, "failed", {
      ...(error.failurePath === undefined ? {} : { failurePath: error.failurePath }),
      ...(error.coordinatorFailurePath === undefined ? {} : {
        coordinatorFailurePath: error.coordinatorFailurePath,
      }),
    });
  } catch (statusPublicationError) {
    attachFailureDetail(error, "statusPublicationError", statusPublicationError);
  }
  throw error;
}

async function command(command, args, options = {}) {
  return execute(command, args, {
    cwd: repository,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    timeout: 30 * 60_000,
    ...options,
  });
}

async function prepareAcceptance(runDirectory, log) {
  await writeStatus(runDirectory, "preparing");
  log("shared-tree interop: verify pinned source and corpus");
  try {
    await access(join(oracleDirectory, ".output/source/source-smoke.json"));
  } catch {
    await command("npm", ["run", "source:capture"], { cwd: oracleDirectory });
  }
  await command("npm", ["run", "source:verify"], { cwd: oracleDirectory });
  await command("npm", ["run", "check"], { cwd: oracleDirectory });
  for (const target of nativeTargets) {
    log(`shared-tree interop: build ${target} native test modules`);
    await command("gleam", ["build", "--target", target]);
  }
}

export function parseTestCount(output, target) {
  const plain = stripVTControlCharacters(output);
  const legacy = [...plain.matchAll(/(\d+)\s+tests?,\s+(\d+)\s+failures?/gi)].at(-1);
  if (legacy) {
    assert.equal(Number(legacy[2]), 0, `${target} corpus reported failures`);
    assert(Number(legacy[1]) > 0, `${target} corpus executed zero tests`);
    return Number(legacy[1]);
  }
  const current = [...plain.matchAll(/Tests:\s+(\d+)\s+passed\s+\((\d+)\)/gi)].at(-1);
  assert(current, `${target} corpus output lacks an executed test count`);
  assert.equal(current[1], current[2], `${target} corpus summary is incomplete`);
  assert(Number(current[1]) > 0, `${target} corpus executed zero tests`);
  return Number(current[1]);
}

export function corpusCommand(target) {
  assert(nativeTargets.includes(target), `Unknown native corpus target: ${target}`);
  return ["test", "--target", target, "--", "shared_tree"];
}

export function failureDiagnostic(error) {
  return {
    name: error?.name ?? "Error",
    message: error?.message ?? String(error),
    ...(error?.code === undefined ? {} : { code: error.code }),
    ...(error?.stack === undefined ? {} : { stack: error.stack }),
    ...(error?.cause === undefined ? {} : {
      cause: error.cause instanceof Error
        ? failureDiagnostic(error.cause)
        : error.cause,
    }),
    ...(error?.artifactCaptureError === undefined ? {} : {
      artifactCaptureError: failureDiagnostic(error.artifactCaptureError),
    }),
    ...(Array.isArray(error?.cleanupErrors) && error.cleanupErrors.length > 0 ? {
      cleanupErrors: error.cleanupErrors.map(failureDiagnostic),
    } : {}),
  };
}

async function runCorpus(runDirectory, context, log) {
  const corpus = {};
  for (const target of nativeTargets) {
    await writeStatus(runDirectory, "corpus", { target });
    log(`shared-tree interop: corpus ${target}`);
    const args = corpusCommand(target);
    const result = await command("gleam", args);
    const output = `${result.stdout}\n${result.stderr}`;
    const executedCount = parseTestCount(output, target);
    const artifact = `corpus/${target}.json`;
    await writeJson(join(runDirectory, artifact), {
      formatVersion: 1,
      runId: context.runId,
      profileDigest: context.profileDigest,
      kind: "corpus",
      subject: target,
      documentId: null,
      command: ["gleam", ...args],
      exitCode: 0,
      executedCount,
      output,
    });
    corpus[target] = {
      target,
      runId: context.runId,
      profileDigest: context.profileDigest,
      passed: true,
      skipped: false,
      executedCount,
      artifacts: [artifact],
    };
  }
  return corpus;
}

async function readViewSchemas() {
  const objectFixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/schema-profile.json",
  ), "utf8"));
  assert.equal(objectFixture.reference.version, reference.version,
    "Pinned schema reference changed");
  const object = objectFixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  assert.equal(JSON.parse(object).root.kind, "Value",
    "Fixture is not the fixed root profile");
  const mapFixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/map-schema-content.json",
  ), "utf8"));
  assert.equal(mapFixture.reference.version, reference.version,
    "Pinned map schema reference changed");
  const map = mapFixture.input.schemas.objectContainedMap;
  assert.equal(typeof map, "string", "Fixture lacks the object-contained map schema");
  const schemaFixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/schema-evolution-compatibility.json",
  ), "utf8"));
  assert.equal(schemaFixture.reference.version, reference.version,
    "Pinned schema-evolution reference changed");
  const schema = Object.fromEntries(schemaFixture.input.schemas.map(({ id, raw }) =>
    [id, raw]));
  for (const label of ["v1", "optional", "object-union"]) {
    assert.equal(typeof schema[label], "string",
      `Schema-evolution fixture lacks ${label}`);
  }
  const arrayFixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/array-schema-content.json",
  ), "utf8"));
  assert.equal(arrayFixture.reference.version, reference.version,
    "Pinned array schema reference changed");
  const array = arrayFixture.input.schemas.objectArrays;
  assert.equal(typeof array, "string", "Fixture lacks the object-contained array schema");
  const identifierFixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/identifier-schema.json",
  ), "utf8"));
  assert.equal(identifierFixture.reference.version, reference.version,
    "Pinned Identifier schema reference changed");
  const identifier = JSON.stringify(identifierFixture.input.schema);
  assert.equal(JSON.parse(identifier).nodes[
    "org.watershed.shared-tree.identifiers.Point"
  ].kind.object.id.kind, "Identifier", "Fixture lacks the Identifier field kind");
  return { object, map, schema, array, identifier };
}

export function assertPreflightProfile(actual, expected) {
  const normalized = JSON.parse(JSON.stringify(actual, (_key, value) =>
    value === Infinity ? "Infinity" : value));
  assert.deepEqual(normalized, expected,
    "Current service preflight does not match the committed profile");
}

async function writePreflightArtifact(runDirectory, context, captured) {
  validatePreflight(captured.result);
  assertPreflightProfile(captured.profile, context.profile);
  const artifact = "service/preflight.json";
  await writeJson(join(runDirectory, artifact), {
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "service-preflight",
    subject: "service",
    documentId: null,
    reference,
    service,
    realService: true,
    result: captured.result,
    profile: captured.profile,
    capture: {
      documentId: captured.capture.documentId,
      summaryVersion: captured.capture.summaryVersion,
      summaryReferenceSequenceNumber:
        captured.capture.summaryReferenceSequenceNumber,
      summaryAcknowledgement: captured.capture.summaryAcknowledgement,
      bootstrapPath: captured.capture.bootstrapPath,
      treePath: captured.capture.treePath,
      observations: captured.capture.observations,
    },
  });
  return artifact;
}

async function attachReconnectArtifacts(runDirectory, context, results) {
  for (const item of results) {
    const artifact = `reconnect/${item.target}-${item.caseId}.json`;
    await writeJson(join(runDirectory, artifact), {
      formatVersion: 1,
      runId: context.runId,
      profileDigest: context.profileDigest,
      kind: "reconnect",
      subject: `${item.target}:${item.caseId}`,
      documentId: item.documentId,
      result: item,
    });
    item.profileDigest = context.profileDigest;
    item.evidence.artifacts = [artifact];
  }
}

async function attachSchemaArtifacts(runDirectory, context, section, items) {
  for (const item of items) {
    item.runId = context.runId;
    item.profileDigest = context.profileDigest;
    const persisted = JSON.parse(JSON.stringify(item));
    for (const name of Object.keys(item)) delete item[name];
    Object.assign(item, persisted);
    const results = section === "reconnect"
      ? item.observations.map((observation) => ({
        subject: `${item.target}:${observation.caseId}`,
        documentId: observation.documentId,
        result: observation,
      }))
      : [{
        subject: item.id ?? item.target ?? `${item.writer}-${item.reader}`,
        documentId: item.documentId ?? item.observations?.[0]?.documentId ?? null,
        result: Object.fromEntries(Object.entries(item)
          .filter(([name]) => name !== "artifacts")),
      }];
    item.artifacts = [];
    for (const result of results) {
      const artifact =
        `schema/${section}/${result.subject.replaceAll(":", "_")}.json`;
      await writeJson(join(runDirectory, artifact), {
        formatVersion: 1,
        runId: context.runId,
        profileDigest: context.profileDigest,
        kind: `schema-${section}`,
        ...result,
      });
      item.artifacts.push(artifact);
    }
  }
}

async function attachTransactionReconnectArtifacts(runDirectory, context, results) {
  for (const item of results) {
    const artifact = `transaction-reconnect/${item.target}-${item.caseId}.json`;
    await writeJson(join(runDirectory, artifact), {
      formatVersion: 1,
      runId: context.runId,
      profileDigest: context.profileDigest,
      kind: "transaction-reconnect",
      subject: `${item.target}:${item.caseId}`,
      documentId: item.documentId,
      result: item,
    });
    item.profileDigest = context.profileDigest;
    item.evidence.artifacts = [artifact];
  }
}

export function artifactReferences(report) {
  const references = [
    report.service.preflightArtifact,
    ...report.deterministic.flatMap(({ artifacts }) => artifacts),
    ...report.reconnect.flatMap(({ evidence }) => evidence.artifacts),
    ...report.failures.flatMap(({ artifacts }) => artifacts),
    ...report.seeded.flatMap(({ artifacts }) => artifacts),
    ...Object.values(report.reload).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...Object.values(report.mapReload).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...report.schemaCompatibility.flatMap(({ artifacts }) => artifacts),
    ...report.schemaRaces.flatMap(({ artifacts }) => artifacts),
    ...report.schemaReconnect.flatMap(({ artifacts }) => artifacts),
    ...report.identifierFields.pairs.flatMap(({ artifacts }) => artifacts),
    ...report.identifierFields.failures.flatMap(({ artifacts }) => artifacts),
    ...Object.values(report.identifierReloadMatrix).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...report.transactionCallbacks.pairs.flatMap(({ artifacts }) => artifacts),
    ...report.transactionConstraints.flatMap(({ artifacts }) => artifacts),
    ...report.transactionReconnect.flatMap(({ evidence }) => evidence.artifacts),
    ...Object.values(report.transactionReloadMatrix).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...report.undoRedoKinds.implementations.flatMap(({ artifacts }) => artifacts),
    ...report.undoRedoConcurrent.flatMap(({ artifacts }) => artifacts),
    ...report.undoRedoReconnect.flatMap(({ artifacts }) => artifacts),
    ...Object.values(report.undoRedoReloadMatrix).flatMap((row) =>
      Object.values(row).flatMap((stage) =>
        Object.values(stage).flatMap(({ artifacts }) => artifacts))),
    ...Object.values(report.schemaReloadMatrix).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...Object.values(report.schemaTailReloadMatrix).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...Object.values(report.arrayReload).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...Object.values(report.corpus).flatMap(({ artifacts }) => artifacts),
  ];
  const seen = new Set(references);
  for (const { sourceArtifacts = [] } of report.undoRedoKinds.implementations) {
    for (const reference of sourceArtifacts) {
      if (!seen.has(reference)) {
        references.push(reference);
        seen.add(reference);
      }
    }
  }
  return references;
}

async function liveAcceptance(config, runDirectory, context, options, corpus, log) {
  await writeStatus(runDirectory, "preflight");
  log("shared-tree interop: current service preflight");
  const captured = await preflight(config);
  const preflightArtifact = await writePreflightArtifact(
    runDirectory,
    context,
    captured,
  );

  await writeStatus(runDirectory, "deterministic");
  log("shared-tree interop: deterministic scenarios");
  const deterministic = await runDeterministicCases(config, context);

  await writeStatus(runDirectory, "reconnect");
  log("shared-tree interop: focused reconnect scenarios");
  const reconnect = (await runReconnectCases(config, {
    runId: context.runId,
    build: false,
  })).results;
  await attachReconnectArtifacts(runDirectory, context, reconnect);

  await writeStatus(runDirectory, "refusals");
  log("shared-tree interop: refusal scenarios");
  const failures = await runFailureCases(config, context);

  await writeStatus(runDirectory, "identifier-fields");
  log("shared-tree interop: Identifier mixed-client fields");
  const identifierFields = await runIdentifierFields(config, context, {
    failures: failures.filter(({ caseId }) => [
      "missing-allocation",
      "wrong-originator",
      "corrupt-numeric-identifier",
      "negative-originatorless-summary",
    ].includes(caseId)).map((item) => ({
      caseId: item.caseId,
      target: item.target,
      runId: item.runId,
      profileDigest: item.profileDigest,
      documentId: item.documentId,
      outcome: item.outcome,
      failureObserved: true,
      partialReadinessObserved: item.clientState !== "never-ready"
        ? false
        : item.writableTreeExposedAfterRefusal,
      partialMutationObserved: item.partialMutationObserved,
      typedError: item.typedError,
      artifacts: item.artifacts,
    })),
  });

  await writeStatus(runDirectory, "transaction-scenarios");
  log("shared-tree interop: mixed-client transactions");
  const transactions = await runTransactionScenarios(config, context);

  await writeStatus(runDirectory, "transaction-reconnect");
  log("shared-tree interop: transaction reconnect");
  const transactionReconnect = (await runTransactionReconnect(config, {
    runId: context.runId,
    build: false,
  })).results;
  await attachTransactionReconnectArtifacts(
    runDirectory,
    context,
    transactionReconnect,
  );

  await writeStatus(runDirectory, "transaction-reload");
  log("shared-tree interop: transaction selected-summary reload matrix");
  const transactionReloadMatrix = await runTransactionReloadMatrix(config, context);

  await writeStatus(runDirectory, "undo-redo");
  log("shared-tree interop: mixed-client undo and redo");
  const undoRedo = await runUndoRedoScenarios(config, context);
  const undoRedoReloadMatrix =
    await runUndoRedoReloadMatrix(config, context);

  await writeStatus(runDirectory, "reload");
  log("shared-tree interop: selected-summary reload matrix");
  const reload = await runReloadMatrix(config, context);

  await writeStatus(runDirectory, "map-reload");
  log("shared-tree interop: dynamic-map selected-summary reload matrix");
  const mapReload = await runMapReloadMatrix(config, context);

  await writeStatus(runDirectory, "schema-compatibility");
  log("shared-tree interop: schema compatibility");
  const schemaCompatibility = await runSchemaCompatibility(config, context);
  await attachSchemaArtifacts(
    runDirectory,
    context,
    "compatibility",
    schemaCompatibility,
  );

  await writeStatus(runDirectory, "schema-races");
  log("shared-tree interop: deterministic schema races");
  const schemaRaces = await runSchemaRaces(config, context);
  await attachSchemaArtifacts(runDirectory, context, "races", schemaRaces);

  await writeStatus(runDirectory, "schema-reconnect");
  log("shared-tree interop: schema reconnect");
  const schemaReconnect = await runSchemaReconnect(config, context);
  await attachSchemaArtifacts(runDirectory, context, "reconnect", schemaReconnect);

  await writeStatus(runDirectory, "schema-reload");
  log("shared-tree interop: schema selected-summary reload matrices");
  const {
    postUpgrade: schemaReloadMatrix,
    earlierSummary: schemaTailReloadMatrix,
  } = await runSchemaReloadMatrices(config, context);
  await attachSchemaArtifacts(
    runDirectory,
    context,
    "reload",
    Object.values(schemaReloadMatrix).flatMap((row) => Object.values(row)),
  );
  await attachSchemaArtifacts(
    runDirectory,
    context,
    "tail-reload",
    Object.values(schemaTailReloadMatrix).flatMap((row) => Object.values(row)),
  );

  await writeStatus(runDirectory, "array-reload");
  log("shared-tree interop: array selected-summary reload matrix");
  const arrayReload = await runArrayReloadMatrix(config, context);

  await writeStatus(runDirectory, "identifier-reload");
  log("shared-tree interop: Identifier selected-summary reload matrix");
  const identifierReloadMatrix = await runIdentifierReloadMatrix(config, context);

  await writeStatus(runDirectory, "seeded", {
    requested: options.iterations,
    seed: options.seed,
  });
  log(`shared-tree interop: ${options.iterations} seeded schedules`);
  const seeded = await runSeededSchedules(
    config,
    context,
    generateSchedules({ seed: options.seed, iterations: options.iterations }),
  );

  return {
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    profile: context.profile,
    reference,
    service: {
      ...service,
      runId: context.runId,
      profileDigest: context.profileDigest,
      preflightArtifact,
    },
    realService: true,
    mode: "acceptance",
    seed: options.seed,
    iterations: options.iterations,
    seededAccounting: seeded.accounting,
    deterministic,
    reconnect,
    failures,
    identifierFields,
    seeded: seeded.results,
    reload,
    mapReload,
    schemaCompatibility,
    schemaRaces,
    schemaReconnect,
    schemaReloadMatrix,
    schemaTailReloadMatrix,
    arrayReload,
    identifierReloadMatrix,
    transactionCallbacks: transactions.callbacks,
    transactionConstraints: transactions.constraints,
    transactionReconnect,
    transactionReloadMatrix,
    undoRedoKinds: undoRedo.kinds,
    undoRedoConcurrent: undoRedo.concurrent,
    undoRedoReconnect: undoRedo.reconnect,
    undoRedoReloadMatrix,
    corpus,
    skipped: [],
    divergences: [],
  };
}

async function acceptance(options, { env, stderr }) {
  const loaded = await loadInteropProfile(options.profilePath);
  const runId = randomUUID();
  const runDirectory = join(options.outputDirectory, runId);
  const log = (message) => stderr.write(`${message}\n`);
  await mkdir(runDirectory, { recursive: true });
  const viewSchemas = await readViewSchemas();
  const context = {
    runId,
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    viewSchema: viewSchemas.object,
    mapViewSchema: viewSchemas.map,
    schemaViews: viewSchemas.schema,
    arrayViewSchema: viewSchemas.array,
    identifierViewSchema: viewSchemas.identifier,
    artifactDirectory: runDirectory,
  };
  try {
    await prepareAcceptance(runDirectory, log);
    const corpus = await runCorpus(runDirectory, context, log);
    const run = (config) =>
      liveAcceptance(config, runDirectory, context, options, corpus, log);
    const liveReport = options.externalFloodgate
      ? await run(serviceConfig(env))
      : await withLocalFloodgate(run);
    const report = JSON.parse(JSON.stringify(liveReport));
    await writeStatus(runDirectory, "validating");
    const references = artifactReferences(report);
    const artifacts = await createArtifactEvidence(runDirectory, references);
    validateInteropReport(report, {
      runId,
      profileDigest: loaded.profileDigest,
      profile: loaded.profile,
      seed: options.seed,
      iterations: options.iterations,
      mode: "acceptance",
      artifactDirectory: runDirectory,
      artifacts,
    });
    const temporary = join(runDirectory, ".report.json");
    const reportPath = join(runDirectory, "report.json");
    await writeJson(temporary, report);
    await rename(temporary, reportPath);
    await writeStatus(runDirectory, "passed", { reportPath });
    return { reportPath, runId, report };
  } catch (error) {
    await recordAcceptanceFailure({
      runDirectory,
      error,
      runId,
      profileDigest: loaded.profileDigest,
    });
  }
}

async function replay(options, { env, stderr }) {
  const loaded = await loadInteropProfile(join(
    repository,
    "test/fixtures/shared_tree/profile.json",
  ));
  const artifact = await loadReplayArtifact(options.replayPath, {
    profileDigest: loaded.profileDigest,
  });
  const runId = randomUUID();
  const runDirectory = join(options.outputDirectory, runId);
  await mkdir(runDirectory, { recursive: true });
  const viewSchemas = await readViewSchemas();
  const context = {
    runId,
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    viewSchema: viewSchemas.object,
    mapViewSchema: viewSchemas.map,
    schemaViews: viewSchemas.schema,
    arrayViewSchema: viewSchemas.array,
    artifactDirectory: runDirectory,
  };
  const log = (message) => stderr.write(`${message}\n`);
  await prepareAcceptance(runDirectory, log);
  const result = await withLocalFloodgate(async (config) => {
    const captured = await preflight(config);
    await writePreflightArtifact(runDirectory, context, captured);
    return replayFailure(config, context, artifact);
  });
  const temporary = join(runDirectory, ".replay.json");
  const replayPath = join(runDirectory, "replay.json");
  await writeJson(temporary, result);
  await rename(temporary, replayPath);
  await writeStatus(runDirectory, "replayed", { replayPath });
  return { replayPath, runId, result };
}

export async function runInteropCommand(args, {
  cwd = process.cwd(),
  env = process.env,
  stdout = process.stdout,
  stderr = process.stderr,
  runAcceptance = acceptance,
  runReplay = replay,
} = {}) {
  const options = parseInteropOptions(args, { cwd });
  try {
    const result = options.mode === "replay"
      ? await runReplay(options, { env, stderr })
      : await runAcceptance(options, { env, stderr });
    stdout.write(json(result));
    return result;
  } catch (error) {
    if (error.failurePath) {
      stderr.write(`SharedTree interop failure: ${error.failurePath}\n`);
      if (error.coordinatorFailurePath
        && error.coordinatorFailurePath !== error.failurePath) {
        stderr.write(
          `SharedTree coordinator diagnostics: ${error.coordinatorFailurePath}\n`,
        );
      }
      try {
        const artifact = JSON.parse(await readFile(error.failurePath, "utf8"));
        if (artifact.kind === "seeded-failure") {
          stderr.write(
            `rtk proxy node smoke/shared_tree.mjs --replay ${
              JSON.stringify(error.failurePath)}\n`,
          );
        }
      } catch {
        // The original failure remains authoritative.
      }
    }
    throw error;
  }
}

function contained(root, path) {
  const difference = relative(root, path);
  return difference === "" || (!difference.startsWith("..") && !isAbsolute(difference));
}

export async function createArtifactEvidence(artifactDirectory, references) {
  assert(Array.isArray(references) && references.length > 0,
    "Artifact references are required");
  assert.equal(new Set(references).size, references.length,
    "Artifact references must be unique");
  const requestedRoot = resolve(artifactDirectory);
  const root = await realpath(requestedRoot);
  const evidence = new Map();
  for (const reference of references) {
    assert(typeof reference === "string" && reference.length > 0
      && !isAbsolute(reference), "Artifact references must be relative paths");
    const requested = resolve(root, reference);
    assert(contained(root, requested), "Artifact path escapes the owned directory");
    const actual = await realpath(requested);
    assert(contained(root, actual), "Artifact resolves outside the owned directory");
    const details = await stat(actual);
    assert(details.isFile() && details.size > 0,
      "Artifact must be a nonempty regular file");
    let claim;
    try {
      claim = JSON.parse(await readFile(actual, "utf8"));
    } catch (error) {
      throw new Error(`Artifact is not valid JSON: ${reference}`, { cause: error });
    }
    object(claim, `Artifact lacks a claim: ${reference}`);
    assert.equal(claim.formatVersion, 1, "Unsupported artifact claim format");
    assert(typeof claim.runId === "string" && claim.runId.length > 0,
      "Artifact claim lacks a run ID");
    assert(typeof claim.profileDigest === "string"
      && /^[0-9a-f]{64}$/.test(claim.profileDigest),
    "Artifact claim lacks a profile digest");
    assert(typeof claim.kind === "string" && claim.kind.length > 0,
      "Artifact claim lacks a kind");
    assert(typeof claim.subject === "string" && claim.subject.length > 0,
      "Artifact claim lacks a subject");
    assert(claim.documentId === null
      || (typeof claim.documentId === "string" && claim.documentId.length > 0),
    "Artifact claim has an invalid document ID");
    evidence.set(reference, Object.freeze({
      path: actual,
      size: details.size,
      claim: Object.freeze(claim),
    }));
  }
  verifiedArtifactMaps.set(evidence, { requestedRoot, root });
  return evidence;
}

function artifactEvidence(expected) {
  assert(expected.artifacts instanceof Map
    && verifiedArtifactMaps.has(expected.artifacts),
  "Expected verified artifact evidence");
  assert.equal(verifiedArtifactMaps.get(expected.artifacts).requestedRoot,
    resolve(expected.artifactDirectory), "Artifact evidence belongs to another root");
  return expected.artifacts;
}

function artifacts(item, evidence, expected, contract, label) {
  assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
    `${label} lacks artifact evidence`);
  assert.equal(new Set(item.artifacts).size, item.artifacts.length,
    `${label} repeats artifact evidence`);
  for (const reference of item.artifacts) {
    assert(evidence.has(reference), `${label} references an unverified artifact`);
    const claim = evidence.get(reference).claim;
    assert.equal(claim.runId, expected.runId,
      `${label} artifact belongs to another run`);
    assert.equal(claim.profileDigest, expected.profileDigest,
      `${label} artifact uses another profile`);
    assert.equal(claim.kind, contract.kind, `${label} artifact has another kind`);
    assert.equal(claim.subject, contract.subject,
      `${label} artifact describes another subject`);
    assert.equal(claim.documentId, contract.documentId,
      `${label} artifact describes another document`);
  }
}

function schemaArtifact(item, evidence, expected, kind, subject, documentId, label) {
  artifacts(item, evidence, expected, { kind, subject, documentId }, label);
  const measured = Object.fromEntries(Object.entries(item)
    .filter(([name]) => name !== "artifacts"));
  for (const reference of item.artifacts) {
    assert.deepEqual(evidence.get(reference).claim.result, measured,
      `${label} artifact differs from report evidence`);
  }
}

function exactImplementations(values, label) {
  assert.deepEqual([...values].sort(), [...implementations].sort(),
    `${label} must cover all three implementations`);
}

function schedulesForProfile(iterations, profile) {
  const profiles = ["object", "map", "schema", "array", "identifier"];
  const offset = profiles.indexOf(profile);
  assert(offset >= 0, `Unknown seeded profile: ${profile}`);
  return Math.floor((iterations + profiles.length - 1 - offset) / profiles.length);
}

function measuredPayload(item) {
  return {
    id: item.id,
    documentId: item.documentId,
    instanceIds: item.instanceIds,
    authorCoverage: item.authorCoverage,
    checkpoints: item.checkpoints,
    evidence: item.evidence,
  };
}

function validateSeededTransactions(item, schedule) {
  const scheduled = schedule.actions.filter(({ type }) => type === "transaction");
  assert(Array.isArray(item.transactions),
    `Seeded ${item.index} lacks transaction evidence`);
  assert.equal(item.transactions.length, scheduled.length,
    `Seeded ${item.index} recorded another transaction count`);
  for (const [index, action] of scheduled.entries()) {
    const record = item.transactions[index];
    assert.equal(record.author, action.author,
      `Seeded ${item.index} transaction changed author`);
    assert.deepEqual(record.constraints, action.constraints,
      `Seeded ${item.index} transaction changed constraints`);
    assert.equal(record.requestedResult, action.result,
      `Seeded ${item.index} transaction changed the requested result`);
    assert.equal(record.outcome, action.result === "abort" ? "aborted" : "committed",
      `Seeded ${item.index} transaction reported another outcome`);
    assert.equal(record.outboundCount, action.result === "abort" ? 0 : 1,
      `Seeded ${item.index} transaction queued another outbound count`);
    assert.equal(record.nestedScopes,
      action.edits.filter(({ op }) => op === "transaction").length,
      `Seeded ${item.index} transaction changed the nested scope count`);
    assert.equal(record.editsApplied, action.edits.length,
      `Seeded ${item.index} transaction applied another edit count`);
    if (action.result === "abort") {
      assert.equal(record.commitRevision, null,
        `Seeded ${item.index} aborted transaction kept a commit`);
    } else {
      assert(typeof record.commitRevision === "string"
        && record.commitRevision.length > 0,
      `Seeded ${item.index} committed transaction lacks a revision`);
    }
  }
}

function seededMeasuredPayload(item) {
  return {
    index: item.index,
    seed: item.seed,
    subSeed: item.subSeed,
    template: item.template,
    roles: item.roles,
    actions: item.actions,
    documentId: item.documentId,
    instanceIds: item.instanceIds,
    authorCoverage: item.authorCoverage,
    checkpoints: item.checkpoints,
    identityMapping: item.identityMapping,
    summaries: item.summaries,
    reloads: item.reloads,
    schemaTransitions: item.schemaTransitions,
    transactions: item.transactions,
    undoRedo: item.undoRedo,
    evidence: item.evidence,
  };
}

function reloadMeasuredPayload(item) {
  return Object.fromEntries(Object.entries(item)
    .filter(([name]) => name !== "artifacts"));
}

function exactAuthors(values, authors, label) {
  assert(Array.isArray(values), `${label} lacks authors`);
  assert.deepEqual([...values].sort(), [...authors].sort(),
    `${label} has incorrect authors`);
  assert.equal(values.length, authors.length, `${label} repeats an author`);
}

function expectedRetainedObjectReferences(item) {
  if (["array-insert-remove", "array-overlapping-remove"].includes(item.family)) {
    return [false, false];
  }
  if (item.family === "array-move-delete") {
    const deleter = item.authors[1];
    return [item.order === `${deleter}-first`, item.order === `${deleter}-first`];
  }
  return [true, true];
}

function restoredDetachedPoints(removed) {
  return removed.flatMap((entry) => {
    if (!Array.isArray(entry) || entry.length !== 3) return [];
    const node = entry[2];
    if (node?.type !== "org.watershed.shared-tree.m1.Point") return [];
    const x = node.fields?.x?.[0]?.value;
    const y = node.fields?.y?.[0]?.value;
    return Number.isFinite(x) && Number.isFinite(y) ? [{ x, y }] : [];
  });
}

function deterministicEvidence(item, authors, label) {
  const evidence = object(item.evidence, `${label} lacks measured evidence`);
  assert(Array.isArray(evidence.authoredPrefixes)
    && evidence.authoredPrefixes.length === authors.length,
  `${label} lacks authored-prefix evidence`);
  exactAuthors(
    evidence.authoredPrefixes.map(({ author }) => author),
    authors,
    `${label} authored prefixes`,
  );
  assert(evidence.authoredPrefixes.every(({ referenceSequenceNumber }) =>
    Number.isSafeInteger(referenceSequenceNumber) && referenceSequenceNumber >= 0),
  `${label} has an invalid authored prefix`);
  assert(Array.isArray(evidence.submissions) && evidence.submissions.length >= authors.length,
    `${label} lacks decoded submissions`);
  exactAuthors(
    [...new Set(evidence.submissions.map(({ author }) => author))],
    authors,
    `${label} submissions`,
  );
  for (const submission of evidence.submissions) {
    assert(authors.includes(submission.author)
      && Number.isSafeInteger(submission.outerSequenceNumber)
      && Number.isSafeInteger(submission.innerIndex)
      && Number.isSafeInteger(submission.referenceSequenceNumber)
      && (submission.author === "upstream"
        ? submission.batchId === undefined
          || (typeof submission.batchId === "string" && submission.batchId.length > 0)
        : typeof submission.batchId === "string" && submission.batchId.length > 0)
      && Number.isSafeInteger(submission.revision)
      && typeof submission.originatorId === "string"
      && submission.originatorId.length > 0,
    `${label} has an invalid decoded submission`);
    assert(Array.isArray(submission.allocations),
      `${label} lacks decoded allocations`);
    for (const allocation of submission.allocations) {
      assert(typeof allocation.sessionId === "string" && allocation.sessionId.length > 0
        && Number.isSafeInteger(allocation.first)
        && Number.isSafeInteger(allocation.last)
        && allocation.first <= allocation.last,
      `${label} has an invalid allocation`);
    }
  }
  assert(evidence.submissions.some(({ allocations }) => allocations.length > 0),
    `${label} lacks decoded allocations`);
  const notifications = object(evidence.notifications,
    `${label} lacks notification evidence`);
  exactAuthors(notifications.intermediateLocalAuthors, authors,
    `${label} local notifications`);
  assert(Array.isArray(notifications.settledRemoteObservers),
    `${label} lacks remote notification evidence`);

  if (item.profile === "array") {
    const array = object(evidence.array, `${label} lacks array evidence`);
    assert(array.finalTree && typeof array.finalTree === "object",
      `${label} lacks the final tagged array tree`);
    assert(Array.isArray(array.retainedObjectReferences)
      && array.retainedObjectReferences.length === 2
      && array.retainedObjectReferences.every((retained) =>
        typeof retained === "boolean"),
    `${label} lacks measured retained object references`);
    assert.deepEqual(
      array.retainedObjectReferences,
      expectedRetainedObjectReferences(item),
      `${label} has incorrect retained object references`,
    );
    assert.equal(typeof array.childEditObserved, "boolean",
      `${label} lacks measured moved-child edit evidence`);
    if (["array-move-child-edit", "array-summary-tail"].includes(item.family)) {
      assert.equal(array.childEditObserved, true,
        `${label} lacks the targeted moved-child edit`);
    }
  }

  if (item.order !== null) {
    const first = item.order.slice(0, -"-first".length);
    const prefixes = new Map(evidence.authoredPrefixes.map(
      ({ author, referenceSequenceNumber }) => [author, referenceSequenceNumber],
    ));
    const ordered = evidence.submissions
      .filter(({ author, outerSequenceNumber }) =>
        outerSequenceNumber > prefixes.get(author))
      .sort((left, right) => left.outerSequenceNumber - right.outerSequenceNumber);
    exactAuthors(
      [...new Set(ordered.map(({ author }) => author))],
      authors,
      `${label} ordered submissions`,
    );
    assert.equal(ordered[0].author, first, `${label} used another service order`);
  }
  if (item.family === "grouped-commits") {
    const grouped = object(evidence.grouped, `${label} lacks grouped evidence`);
    const minimumCommits = item.authors[0] === "upstream" ? 3 : 1;
    assert(Number.isSafeInteger(grouped.outerSequenceNumber)
      && Array.isArray(grouped.commits) && grouped.commits.length >= minimumCommits,
    `${label} collapsed grouped commits`);
    assert(Array.isArray(grouped.allocations) && grouped.allocations.length > 0,
      `${label} lacks grouped allocation evidence`);
    assert.deepEqual(grouped.commits.map(({ innerIndex }) => innerIndex),
      grouped.commits.map((_commit, index) => grouped.allocations.length + index),
      `${label} has incomplete grouped inner indexes`);
    assert(grouped.commits.every(({ revision, originatorId }) =>
      Number.isSafeInteger(revision)
        && typeof originatorId === "string" && originatorId.length > 0),
    `${label} has invalid grouped commit identities`);
    const groupedSubmissions = evidence.submissions.filter(({ author,
      outerSequenceNumber }) =>
      author === item.authors[0]
        && outerSequenceNumber === grouped.outerSequenceNumber);
    assert.deepEqual(groupedSubmissions.map(({ innerIndex, revision,
      originatorId }) => ({ innerIndex, revision, originatorId })),
    grouped.commits, `${label} grouped commits differ from decoded submissions`);
    assert.deepEqual(groupedSubmissions[0]?.allocations, grouped.allocations,
      `${label} grouped allocations differ from decoded submissions`);
  }
  if (["parent-replacement-child-edit", "detached-child-reconciliation"]
    .includes(item.family)) {
    const retained = object(evidence.retained, `${label} lacks retained observations`);
    object(retained.upstreamReference, `${label} lacks the upstream retained reference`);
    assert(Array.isArray(retained.removed) && retained.removed.length > 0,
      `${label} lacks removed content`);
    assert(Array.isArray(retained.refreshers),
      `${label} lacks refresher history`);
    if (item.family === "detached-child-reconciliation"
      && item.authors[0] !== "upstream") {
      assert.deepEqual(retained.refreshers, [[1, 2], [42, 2]],
        `${label} has incorrect refresher history`);
    }
    assert.equal(retained.summaryConsumed, true,
      `${label} did not consume retained summary state`);
    assert.equal(retained.continuationObserved, true,
      `${label} lacks retained continuation evidence`);
  }
  if (item.family === "delivery-duplicates-gaps") {
    const delivery = object(evidence.delivery, `${label} lacks delivery evidence`);
    assert(Array.isArray(delivery.heldSequenceNumbers)
      && delivery.heldSequenceNumbers.length >= 2
      && Array.isArray(delivery.deliveredSequenceNumbers)
      && delivery.deliveredSequenceNumbers.length >= 3
      && Number.isSafeInteger(delivery.duplicateSequenceNumber)
      && delivery.gapRepairObserved === true
      && delivery.duplicateInvalidations === 0
      && delivery.duplicateAllocations === 0,
    `${label} lacks measured duplicate/gap behavior`);
  }
  if (item.family === "multi-session-ids") {
    assert(Array.isArray(evidence.sessions)
      && evidence.sessions.length === implementations.length,
    `${label} lacks multi-session identities`);
    exactImplementations(evidence.sessions.map(({ implementation }) => implementation),
      `${label} sessions`);
    assert(evidence.sessions.every(({ before, after, restored, restoredAfter }) =>
      typeof before === "string" && before.length > 0
        && typeof after === "string" && after.length > 0
        && typeof restored === "string" && restored.length > 0
        && restoredAfter === restored
        && before !== after),
    `${label} has invalid session restoration evidence`);
  }
  return evidence;
}

function seededEvidence(item, label) {
  const identities = object(item.identityMapping,
    `${label} lacks identity mapping`);
  exactImplementations(Object.keys(identities), `${label} identities`);
  for (const implementation of implementations) {
    const identity = object(identities[implementation],
      `${label} lacks ${implementation} identity`);
    assert.equal(identity.instanceId, item.instanceIds[implementation],
      `${label} identity uses another instance`);
    assert(Array.isArray(identity.clientIds) && identity.clientIds.length > 0
      && identity.clientIds.every((value) =>
        typeof value === "string" && value.length > 0),
    `${label} lacks client identities`);
    assert(Array.isArray(identity.originatorIds)
      && identity.originatorIds.length > 0
      && identity.originatorIds.every((value) =>
        typeof value === "string" && value.length > 0),
    `${label} lacks compressor identities`);
    assert(Array.isArray(identity.revisions) && identity.revisions.length > 0
      && identity.revisions.every(Number.isSafeInteger),
    `${label} lacks original revisions`);
    assert(Array.isArray(identity.sessionIds) && identity.sessionIds.length > 0
      && identity.sessionIds.every((value) =>
        typeof value === "string" && value.length > 0),
    `${label} lacks original sessions`);
  }
  const seeded = object(item.evidence, `${label} lacks seeded evidence`);
  assert(Array.isArray(seeded.submissions)
    && seeded.submissions.length >= implementations.length,
  `${label} lacks accepted submissions`);
  exactAuthors(
    [...new Set(seeded.submissions.map(({ author }) => author))],
    implementations,
    `${label} accepted submissions`,
  );
  assert(seeded.submissions.every(({ author, outerSequenceNumber, innerIndex,
    referenceSequenceNumber, revision, originatorId, allocations }) =>
    implementations.includes(author)
      && Number.isSafeInteger(outerSequenceNumber)
      && Number.isSafeInteger(innerIndex)
      && Number.isSafeInteger(referenceSequenceNumber)
      && Number.isSafeInteger(revision)
      && typeof originatorId === "string" && originatorId.length > 0
      && Array.isArray(allocations)),
  `${label} has an invalid accepted submission`);
  assert(Number.isSafeInteger(seeded.rawSequencedOperationCount)
    && seeded.rawSequencedOperationCount > 0,
  `${label} lacks raw sequenced operation accounting`);
  const releaseActions = item.actions.filter(({ type }) => type === "release");
  assert(Array.isArray(seeded.releases)
    && seeded.releases.length === releaseActions.length,
  `${label} has incomplete release evidence`);
  const acceptedSequenceNumbers = [];
  let previousAcceptedSequence = -1;
  for (const [index, action] of releaseActions.entries()) {
    const release = object(seeded.releases[index],
      `${label} lacks release ${index}`);
    assert.equal(release.author, action.author,
      `${label} release ${index} changed author`);
    assert.equal(release.direction, action.direction,
      `${label} release ${index} changed direction`);
    assert.equal(release.order, action.order,
      `${label} release ${index} changed order`);
    if (action.direction !== "outbound") continue;
    assert.equal(release.order, "fifo",
      `${label} outbound release ${index} is not FIFO`);
    assert(Number.isSafeInteger(release.afterSequence)
      && release.afterSequence >= previousAcceptedSequence,
    `${label} outbound release ${index} preceded prior acceptance`);
    assert(Number.isSafeInteger(release.pendingTreeCount)
      && release.pendingTreeCount > 0
      && release.acceptedCommitCount === release.pendingTreeCount,
    `${label} outbound release ${index} lacks accepted pending commits`);
    assert(Array.isArray(release.acceptedSequenceNumbers)
      && release.acceptedSequenceNumbers.length > 0
      && release.acceptedSequenceNumbers.every((sequenceNumber) =>
        Number.isSafeInteger(sequenceNumber)
          && sequenceNumber > release.afterSequence)
      && new Set(release.acceptedSequenceNumbers).size
        === release.acceptedSequenceNumbers.length,
    `${label} outbound release ${index} has invalid accepted sequences`);
    const accepted = new Set(release.acceptedSequenceNumbers);
    const matchingCommits = seeded.submissions.filter(({ author,
      outerSequenceNumber }) =>
      author === release.author && accepted.has(outerSequenceNumber));
    assert.equal(matchingCommits.length, release.acceptedCommitCount,
      `${label} outbound release ${index} accepted another commit count`);
    acceptedSequenceNumbers.push(...release.acceptedSequenceNumbers);
    previousAcceptedSequence = Math.max(...release.acceptedSequenceNumbers);
  }
  assert.equal(new Set(acceptedSequenceNumbers).size,
    acceptedSequenceNumbers.length,
  `${label} repeats an accepted sequence across releases`);
  const submissionSequences = new Set(seeded.submissions.map(
    ({ outerSequenceNumber }) => outerSequenceNumber,
  ));
  assert(acceptedSequenceNumbers.every((sequenceNumber) =>
    submissionSequences.has(sequenceNumber)),
  `${label} release evidence names an unknown submission`);
  const finalAcceptedSequence = Math.max(...acceptedSequenceNumbers);
  for (const [index, action] of releaseActions.entries()) {
    if (action.direction !== "inbound") continue;
    const release = seeded.releases[index];
    if (action.author === "upstream") {
      assert.equal(release.order, "fifo",
        `${label} upstream inbound release is not FIFO`);
      assert(Number.isSafeInteger(release.receivedThrough)
        && release.receivedThrough >= finalAcceptedSequence
        && Number.isSafeInteger(release.queuedCount)
        && release.queuedCount > 0,
      `${label} upstream inbound release lacks accepted sequencing`);
      continue;
    }
    assert(Array.isArray(release.heldSequenceNumbers)
      && Array.isArray(release.deliveredSequenceNumbers)
      && release.heldSequenceNumbers.length > 0
      && release.deliveredSequenceNumbers.length > 0
      && release.heldSequenceNumbers.every(Number.isSafeInteger)
      && release.deliveredSequenceNumbers.every(Number.isSafeInteger)
      && new Set(release.heldSequenceNumbers).size
        === release.heldSequenceNumbers.length
      && new Set(release.deliveredSequenceNumbers).size
        === release.deliveredSequenceNumbers.length,
    `${label} native inbound release ${index} lacks measured sequences`);
    assert(acceptedSequenceNumbers.every((sequenceNumber) =>
      release.heldSequenceNumbers.includes(sequenceNumber)
        && release.deliveredSequenceNumbers.includes(sequenceNumber)),
    `${label} native inbound release ${index} omitted accepted sequencing`);
    const deliveredAccepted = release.deliveredSequenceNumbers.filter(
      (sequenceNumber) => acceptedSequenceNumbers.includes(sequenceNumber),
    );
    assert.deepEqual(deliveredAccepted,
      action.order === "reverse"
        ? acceptedSequenceNumbers.toReversed()
        : acceptedSequenceNumbers,
    `${label} native inbound release ${index} changed delivery order`);
  }
  const summaryActions = item.actions.filter(({ type }) => type === "summarize");
  assert(Array.isArray(item.summaries)
    && item.summaries.length === summaryActions.length,
  `${label} has incomplete summary evidence`);
  assert(item.summaries.every(({ author }, index) =>
    author === summaryActions[index].author),
  `${label} summary author changed`);
  const reloadActions = item.actions.filter(({ type }) => type === "reload");
  assert(Array.isArray(item.reloads) && item.reloads.length === reloadActions.length,
    `${label} has incomplete reload evidence`);
  assert(item.reloads.every(({ author, instanceId, observation,
    selectedSummaryRequests }, index) =>
    author === reloadActions[index].author
      && typeof instanceId === "string" && instanceId.length > 0
      && !Object.values(item.instanceIds).includes(instanceId)
      && observation && typeof observation === "object"
      && Array.isArray(selectedSummaryRequests)),
  `${label} has invalid fresh reload evidence`);

  const lifecycleActions = item.actions.filter(({ type }) =>
    ["retain", "revert", "dispose"].includes(type));
  assert(Array.isArray(item.undoRedo)
    && item.undoRedo.length === lifecycleActions.length,
  `${label} has incomplete undo/redo lifecycle evidence`);
  for (const [index, action] of lifecycleActions.entries()) {
    const record = object(item.undoRedo[index],
      `${label} lacks undo/redo lifecycle ${index}`);
    assert.equal(record.author, action.author,
      `${label} lifecycle ${index} changed author`);
    assert.equal(record.name, action.name,
      `${label} lifecycle ${index} changed handle`);
    assert.equal(record.lifecycle, action.lifecycle,
      `${label} lifecycle ${index} changed phase`);
    const result = object(record.result,
      `${label} lifecycle ${index} lacks a result`);
    assert.equal(result.name, action.name,
      `${label} lifecycle ${index} returned another handle`);
    if (action.type === "retain") {
      assert.equal(record.type, "retain",
        `${label} lifecycle ${index} changed action`);
      assert.equal(result.kind, action.lifecycle === "undo" ? "Undo" : "Default",
        `${label} lifecycle ${index} retained another commit kind`);
      assert.equal(result.factoryAvailable, true,
        `${label} lifecycle ${index} lacks a factory`);
      assert.equal(result.status, "Valid",
        `${label} lifecycle ${index} retained an invalid handle`);
    } else if (action.type === "revert") {
      assert.equal(record.type, action.lifecycle,
        `${label} lifecycle ${index} changed revert phase`);
      assert.equal(record.dispose, action.dispose,
        `${label} lifecycle ${index} changed disposal`);
      assert.equal(result.authoredKind,
        action.lifecycle === "redo" ? "Redo" : "Undo",
      `${label} lifecycle ${index} authored another kind`);
      assert.equal(result.authoredCount, 1,
        `${label} lifecycle ${index} authored another commit count`);
      assert.equal(result.outboundCount, 1,
        `${label} lifecycle ${index} submitted another operation count`);
      assert.equal(result.status, action.dispose ? "Disposed" : "Valid",
        `${label} lifecycle ${index} has another handle transition`);
    } else {
      assert.equal(record.type, "dispose",
        `${label} lifecycle ${index} changed disposal action`);
      assert.equal(result.status, "Disposed",
        `${label} lifecycle ${index} did not dispose the handle`);
    }
  }
  const lifecycleAuthors = new Set(lifecycleActions.map(({ author }) => author));
  const lifecycleEvents = item.checkpoints.flatMap(({ observations }) =>
    observations
      .filter(({ implementation }) => lifecycleAuthors.has(implementation))
      .flatMap(({ commits }) => commits ?? []));
  const revertActions = lifecycleActions.filter(({ type }) => type === "revert");
  const expectedKinds = revertActions.map(({ lifecycle }) =>
    lifecycle === "redo" ? "Redo" : "Undo");
  const commitEvents = lifecycleEvents.filter(
    ({ type, local, kind }) =>
      type === "commit" && local === true && ["Undo", "Redo"].includes(kind),
  );
  const settlementEvents = lifecycleEvents.filter(
    ({ type, kind }) =>
      type === "settlement" && ["Undo", "Redo"].includes(kind),
  );
  assert.deepEqual(commitEvents.map(({ kind }) => kind), expectedKinds,
    `${label} lifecycle commit events are missing, duplicated, or reordered`);
  assert(commitEvents.every(({ factoryAvailable, handleAcquired }) =>
    factoryAvailable === true && handleAcquired === true),
  `${label} lifecycle commit event lacks its accepted factory`);
  assert.deepEqual(settlementEvents.map(({ kind, outcome }) => ({
    kind,
    outcome,
  })), expectedKinds.map((kind) => ({ kind, outcome: "FullyApplied" })),
  `${label} lifecycle settlements are missing, duplicated, or reordered`);

}

function validateSeededRawLifecycle(item, raw, label) {
  assert.deepEqual(raw.checkpoints, item.checkpoints,
    `${label} raw checkpoints differ from the report`);
  assert.deepEqual(raw.lifecycle, item.undoRedo,
    `${label} raw lifecycle differs from the report`);
  assert(Array.isArray(raw.sequencedHistory),
    `${label} lacks raw sequenced history`);
  const events = raw.checkpoints.flatMap(({ observations }) =>
    observations.flatMap(({ commits }) => commits ?? []));
  const commits = events.filter(
    ({ type, local }) => type === "commit" && local === true,
  );
  assert(commits.some(({ kind }) => kind === "Default"),
    `${label} lacks the retained Default factory event`);
  for (const [index, record] of item.undoRedo.entries()) {
    const result = successfulResult(record.result,
      `${label} lifecycle ${index}`);
    if (record.type === "retain") {
      const kind = record.lifecycle === "undo" ? "Undo" : "Default";
      validateRetainedAction(
        raw,
        result,
        kind,
        commits,
        `${label} lifecycle ${index}`,
      );
      continue;
    }
    if (record.type === "undo" || record.type === "redo") {
      const kind = record.type === "redo" ? "Redo" : "Undo";
      validateSequencedAction(
        raw,
        result,
        kind,
        `${label} lifecycle ${index}`,
      );
    }
  }
}

function measured(item, expected, authors, evidence, label) {
  assert.equal(item.runId, expected.runId, `${label} belongs to another run`);
  assert.equal(item.profileDigest, expected.profileDigest,
    `${label} uses another profile`);
  assert(typeof item.documentId === "string" && item.documentId.length > 0,
    `${label} lacks a document ID`);
  const instanceIds = object(item.instanceIds, `${label} lacks client instances`);
  exactImplementations(Object.keys(instanceIds), `${label} client instances`);
  assert(implementations.every((implementation) =>
    typeof instanceIds[implementation] === "string"
      && instanceIds[implementation].length > 0),
  `${label} has an invalid client instance`);
  assert.equal(new Set(Object.values(instanceIds)).size, implementations.length,
    `${label} reuses a client instance`);
  assert.deepEqual([...new Set(item.authorCoverage)].sort(),
    [...authors].sort(), `${label} lacks measured author coverage`);
  assert.equal(item.authorCoverage.length, authors.length,
    `${label} repeats measured author coverage`);
  assert(Array.isArray(item.checkpoints) && item.checkpoints.length >= 2,
    `${label} lacks checkpoints`);
  assert.equal(item.checkpoints.filter(
    ({ label: checkpointLabel, stage }) =>
      checkpointLabel === "initial" && stage === "quiescent",
  ).length, 1, `${label} lacks the initial common barrier`);
  assert(item.checkpoints.some(({ stage }) => stage === "intermediate"),
    `${label} lacks an intermediate checkpoint`);
  const pendingRequired = authors.length > 1 || [
    "detached-child-reconciliation",
    "several-pending-edits",
    "grouped-commits",
    "delivery-duplicates-gaps",
    "multi-session-ids",
  ].includes(item.family);
  if (pendingRequired) {
    const intermediate = item.checkpoints.filter(({ stage }) => stage === "intermediate");
    for (const author of authors) {
      assert(intermediate.some(({ observations }) => observations.some(
        ({ implementation, pendingTreeCount, inflightSubmissionCount }) =>
          implementation === author
          && (pendingTreeCount > 0 || inflightSubmissionCount > 0),
      )), `${label} lacks measured pending state for ${author}`);
    }
  }
  const quiescent = item.checkpoints.filter(({ stage }) => stage === "quiescent");
  assert(quiescent.length > 0, `${label} lacks a quiescent checkpoint`);
  const reconnectRetries = Object.fromEntries(
    nativeTargets.map((target) => [target, []]),
  );
  for (const checkpoint of item.checkpoints) {
    assert(typeof checkpoint.label === "string" && checkpoint.label.length > 0,
      `${label} has an unnamed checkpoint`);
    assert(["intermediate", "quiescent"].includes(checkpoint.stage),
      `${label} has an unknown checkpoint stage`);
    assert(Array.isArray(checkpoint.observations),
      `${label} lacks checkpoint observations`);
    exactImplementations(
      checkpoint.observations.map(({ implementation }) => implementation),
      `${label} checkpoint`,
    );
    for (const observation of checkpoint.observations) {
      assert.equal(observation.instanceId, instanceIds[observation.implementation],
        `${label} checkpoint uses another client instance`);
      assert(Number.isSafeInteger(observation.sequenceNumber)
        && observation.sequenceNumber >= 0, `${label} has an invalid watermark`);
      assert(Number.isSafeInteger(observation.pendingTreeCount)
        && observation.pendingTreeCount >= 0, `${label} has invalid pending state`);
      assert(Number.isSafeInteger(observation.inflightSubmissionCount)
        && observation.inflightSubmissionCount >= 0,
      `${label} has invalid in-flight state`);
      object(observation.wholeTree, `${label} lacks a whole-tree observation`);
      if (observation.implementation !== "upstream") {
        reconnectRetryTrace(
          observation.reconnectRetries,
          `${label} ${observation.implementation} checkpoint`,
        );
        const prior = reconnectRetries[observation.implementation];
        assert(observation.reconnectRetries.length >= prior.length,
          `${label} reconnect retry evidence moved backwards`);
        assert.deepEqual(
          observation.reconnectRetries.slice(0, prior.length),
          prior,
          `${label} reconnect retry evidence changed`,
        );
        reconnectRetries[observation.implementation] =
          structuredClone(observation.reconnectRetries);
      }
    }
    if (checkpoint.stage === "quiescent") {
      const [first, ...rest] = checkpoint.observations;
      assert(rest.every(({ sequenceNumber }) =>
        sequenceNumber === first.sequenceNumber),
      `${label} quiescent clients have different watermarks`);
      assert(checkpoint.observations.every(({ pendingTreeCount,
        inflightSubmissionCount }) =>
        pendingTreeCount === 0 && inflightSubmissionCount === 0),
      `${label} is not quiescent`);
      assert(checkpoint.observations.every(({ wholeTree }) =>
        assert.deepEqual(wholeTree, first.wholeTree) === undefined),
      `${label} quiescent roots differ`);
    }
  }
  assert.equal(item.passed, true, `${label} did not pass`);
  assert.equal(item.skipped, false, `${label} was skipped`);
  if (label.startsWith("Deterministic ")) {
    deterministicEvidence(item, authors, label);
  } else if (label.startsWith("Seeded ")) {
    seededEvidence(item, label);
  }
  artifacts(item, evidence, expected, {
    kind: label.startsWith("Seeded ") ? "seeded" : "deterministic",
    subject: label.startsWith("Seeded ") ? String(item.index) : item.id,
    documentId: item.documentId,
  }, label);
  if (label.startsWith("Deterministic ")) {
    for (const reference of item.artifacts) {
      assert.deepEqual(evidence.get(reference).claim.measured, measuredPayload(item),
        `${label} artifact measured payload differs`);
    }
  } else if (label.startsWith("Seeded ")) {
    for (const reference of item.artifacts) {
      assert.deepEqual(evidence.get(reference).claim.measured,
        seededMeasuredPayload(item),
      `${label} artifact measured payload differs`);
      validateSeededRawLifecycle(
        item,
        evidence.get(reference).claim.raw,
        label,
      );
    }
  }
  for (const reference of item.artifacts) {
    const gates = object(
      evidence.get(reference).claim.raw?.gates,
      `${label} artifact lacks raw gate evidence`,
    );
    for (const target of nativeTargets) {
      reconnectRetryTrace(
        object(gates[target], `${label} artifact lacks ${target} gate evidence`)
          .reconnectRetries,
        `${label} ${target} raw gate`,
      );
      assert.deepEqual(gates[target].reconnectRetries, reconnectRetries[target],
        `${label} ${target} raw retry trace differs from checkpoints`);
    }
  }
}

function exactCells(actual, required, label) {
  assert(Array.isArray(actual) && actual.length === required.length,
    `${label} has incomplete coverage`);
  const requiredById = new Map(required.map((cell) => [cell.id, cell]));
  assert.equal(requiredById.size, required.length, `${label} catalogue repeats a cell`);
  const seen = new Set();
  for (const item of actual) {
    assert(requiredById.has(item.id), `${label} contains an unknown cell`);
    assert(!seen.has(item.id), `${label} repeats a cell`);
    seen.add(item.id);
  }
  return requiredById;
}

function validateFailures(report, expected, evidence) {
  const required = requiredFailureCells();
  const requiredById = exactCells(report.failures, required, "Failure results");
  for (const item of report.failures) {
    const cell = requiredById.get(item.id);
    assert.equal(item.caseId, cell.caseId, "Failure case ID changed");
    assert.equal(item.target, cell.target, "Failure target changed");
    assert.equal(item.kind, cell.kind, "Failure kind changed");
    assert.equal(item.stage, cell.expectedStage, "Failure occurred at another stage");
    assert.equal(item.typedError?.code, cell.errorCode,
      "Failure returned another error code");
    assert.equal(item.typedError?.operation, cell.errorOperation,
      "Failure diagnostic names another operation");
    assert(typeof item.typedError?.message === "string"
      && item.typedError.message.length > 0,
    "Failure lacks a source diagnostic");
    for (const term of cell.diagnosticTerms) {
      assert(item.typedError.message.toLowerCase().includes(term.toLowerCase()),
        `Failure diagnostic lacks source reason or location: ${term}`);
    }
    assert(!/timed out|unavailable service|missing executable|invalid json|exited/i
      .test(item.typedError.message),
    "Infrastructure failure counted as a semantic refusal");
    assert.equal(item.runId, expected.runId, "Failure belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Failure uses another profile");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      "Failure lacks a document ID");
    assert.equal(item.outcome, "refused", "Negative input was not refused");
    assert.equal(item.clientState, cell.clientState,
      "Failure has another observable client state");
    assert.equal(item.partialMutationObserved, false,
      "Failed input exposed a partial mutation");
    assert.equal(item.unrelatedDocumentPassed, true,
      "Failure was not isolated to its document");
    assert.equal(item.writableTreeExposedAfterRefusal,
      cell.clientState === "ready-local",
    "Failure exposed the wrong post-refusal tree state");
    if (cell.kind === "local-refusal") {
      assert.deepEqual(item.after?.root, item.before?.root,
        "Local refusal changed the whole tree");
      assert.equal(item.after?.pendingTreeCount, item.before?.pendingTreeCount,
        "Local refusal changed pending state");
      assert.equal(item.outboundTreeMessages, 0,
        "Local refusal emitted tree traffic");
      assert.equal(item.continuationPeerObserved, true,
        "Local refusal did not preserve valid continuation");
      assert.deepEqual(item.after?.events, [],
        "Local refusal emitted a visible-change event");
    }
    artifacts(item, evidence, expected, {
      kind: "failure",
      subject: item.id,
      documentId: item.documentId,
    }, `Failure ${item.id}`);
  }
}

function validateReload(report, expected, evidence) {
  exactImplementations(Object.keys(report.reload), "Reload writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    exactImplementations(Object.keys(report.reload[writer]), `Reload readers for ${writer}`);
    for (const reader of implementations) {
      const item = object(report.reload[writer][reader],
        `Missing reload cell ${writer}->${reader}`);
      assert.equal(item.writer, writer, "Reload writer changed");
      assert.equal(item.reader, reader, "Reload reader changed");
      assert.equal(item.runId, expected.runId, "Reload belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "Reload uses another profile");
      assert(typeof item.writerVersion === "string" && item.writerVersion.length > 0,
        "Reload lacks a writer version");
      assert.equal(item.loadedVersion, item.writerVersion,
        "Reload selected another version");
      assert(typeof item.readerInstanceId === "string"
        && item.readerInstanceId.length > 0, "Reload lacks a fresh reader");
      assert(!readerInstances.has(item.readerInstanceId),
        "Reload reused a reader instance");
      readerInstances.add(item.readerInstanceId);
      assert(Number.isSafeInteger(item.snapshotSequenceNumber)
        && Number.isSafeInteger(item.dataEditSequenceNumber)
        && Number.isSafeInteger(item.publicationSequenceNumber)
        && item.snapshotSequenceNumber < item.dataEditSequenceNumber
        && item.dataEditSequenceNumber < item.publicationSequenceNumber,
      "Reload lacks a measured snapshot tail");
      assert(Number.isSafeInteger(item.replayWatermark)
        && item.replayWatermark >= item.publicationSequenceNumber,
      "Reload lacks a measured replay watermark");
      assert(Number.isSafeInteger(item.replayStartSequenceNumber)
        && item.replayStartSequenceNumber >= item.snapshotSequenceNumber,
      "Reload fell back to origin replay");
      assert(reader === "upstream"
        ? item.replayEvidence === "upstream-delta-storage"
        : ["native-delivery", "native-handshake"].includes(item.replayEvidence),
      "Reload lacks measured replay evidence");
      assert(Array.isArray(item.selectedSummaryRequests)
        && item.selectedSummaryRequests.includes(item.loadedVersion),
      "Reload did not consume the selected summary");
      assert(typeof item.scenarioId === "string" && item.scenarioId.length > 0,
        "Reload lacks a summary scenario ID");
      assert.equal(item.loaded, true, "Reload did not load");
      assert.equal(item.continuedEditing, true, "Reload did not continue editing");
      assert.equal(item.peerObservedEdit, true,
        "Reload continuation lacked an independent peer");
      assert.equal(item.pendingTreeCount, 0, "Reload has pending tree commits");
      assert.equal(item.inflightSubmissionCount, 0,
        "Reload has in-flight submissions");
      object(item.wholeTree, "Reload lacks a whole-tree observation");
      assert(typeof item.documentId === "string" && item.documentId.length > 0,
        "Reload lacks a document ID");
      assert.equal(item.writerVersionBeforeLoad, item.writerVersion,
        "Reload writer head changed before load");
      assert.equal(item.writerVersionAfterLoad, item.writerVersion,
        "Reload writer head changed after continuation");
      assert(Number.isSafeInteger(item.tailSequenceNumber)
        && item.tailSequenceNumber > item.publicationSequenceNumber,
      "Reload lacks a measured operation after publication");
      const retained = object(item.retained, "Reload lacks retained state");
      assert.deepEqual(retained.visible, { x: 3, y: 4 },
        "Reload visible point changed to detached content");
      assert.deepEqual(retained.detached, { x: 42, y: 7 },
        "Reload detached point lost retained edits");
      assert(Array.isArray(retained.removed) && retained.removed.length > 0,
        "Reload lacks removed content");
      assert(restoredDetachedPoints(retained.removed).some(({ x, y }) =>
        x === retained.detached.x && y === retained.detached.y),
      "Reload removed content lacks the retained detached point");
      assert.equal(retained.upstreamSelectedVersion, item.writerVersion,
        "Retained verifier selected another summary");
      assert.equal(retained.summaryConsumed, true,
        "Retained verifier did not consume the selected summary");
      const writerIdentity = object(retained.writerIdentity,
        "Reload lacks writer identity evidence");
      assert(Array.isArray(writerIdentity.clientIds)
        && writerIdentity.clientIds.length > 0,
      "Reload lacks writer client IDs");
      assert(Array.isArray(writerIdentity.originatorIds)
        && writerIdentity.originatorIds.length === 1,
      "Reload lacks one stable writer compressor identity");
      assert(Array.isArray(writerIdentity.resubmissions),
        "Reload lacks resubmission metadata");
      assert(writerIdentity.resubmissions.every(({ referenceSequenceNumber,
        revision, originatorId, refresher }) =>
        Number.isSafeInteger(referenceSequenceNumber)
          && (Number.isSafeInteger(revision)
            || (typeof revision === "string" && revision.length > 0))
          && typeof originatorId === "string"
          && writerIdentity.originatorIds.includes(originatorId)
          && (refresher === undefined
            || (Array.isArray(refresher) && refresher.length === 2
              && refresher.every(Number.isFinite)))),
      "Reload has invalid resubmission identity");
      if (writer !== "upstream") {
        assert.deepEqual(
          writerIdentity.resubmissions.map(({ refresher }) => refresher),
          [[1, 2], [42, 2]],
          "Reload native writer retained metadata changed",
        );
      }
      const continuationIdentity = object(item.continuationIdentity,
        "Reload lacks continuation identity");
      assert(typeof continuationIdentity.clientId === "string"
        && continuationIdentity.clientId.length > 0,
      "Reload continuation lacks a client ID");
      assert(Number.isSafeInteger(continuationIdentity.referenceSequenceNumber),
        "Reload continuation lacks a reference sequence");
      assert(Array.isArray(continuationIdentity.revisions)
        && continuationIdentity.revisions.length > 0
        && continuationIdentity.revisions.every(({ revision, originatorId }) =>
          Number.isSafeInteger(revision)
            && typeof originatorId === "string"
            && originatorId.length > 0),
      "Reload continuation lacks compressor metadata");
      artifacts(item, evidence, expected, {
        kind: "reload",
        subject: `${writer}->${reader}`,
        documentId: item.documentId,
      }, `Reload ${writer}->${reader}`);
      for (const reference of item.artifacts) {
        const claim = evidence.get(reference).claim;
        assert.deepEqual(claim.measured,
          reloadMeasuredPayload(item),
        `Reload ${writer}->${reader} artifact differs from measured evidence`);
        if (reader === "upstream") continue;
        const load = object(claim.raw?.load,
          "Reload artifact lacks raw native load evidence");
        assert(Array.isArray(load.handshakes) && load.handshakes.length > 0,
          "Reload artifact lacks native handshake evidence");
        const initialSequenceNumbers = load.handshakes.flatMap((handshake) => {
          assert((handshake.checkpointSequenceNumber === undefined
            || Number.isSafeInteger(handshake.checkpointSequenceNumber))
            && (handshake.summarySequenceNumber === undefined
              || Number.isSafeInteger(handshake.summarySequenceNumber))
            && Array.isArray(handshake.initialMessageSequenceNumbers)
            && handshake.initialMessageSequenceNumbers.every(Number.isSafeInteger),
          "Reload artifact has invalid native handshake evidence");
          return handshake.initialMessageSequenceNumbers;
        });
        assert(Array.isArray(load.repairRequests)
          && load.repairRequests.every(({ from, topic, hash }) =>
            Number.isSafeInteger(from)
              && (topic === undefined || typeof topic === "string")
              && typeof hash === "string" && hash.length > 0),
        "Reload artifact has invalid repair-request evidence");
        if (item.replayEvidence === "native-handshake") {
          const applied = initialSequenceNumbers.filter(
            (sequenceNumber) => sequenceNumber > item.snapshotSequenceNumber,
          );
          assert(applied.length > 0
            && Math.min(...applied) - 1 === item.replayStartSequenceNumber,
          "Reload native handshake does not prove the applied replay floor");
        }
      }
    }
  }
}

function validateMapReload(report, expected, evidence) {
  validateMapResults(report.mapReload);
  for (const writer of implementations) {
    for (const reader of implementations) {
      const item = report.mapReload[writer][reader];
      assert.equal(item.runId, expected.runId,
        "Map reload belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "Map reload uses another profile");
      assert.equal(item.writerVersionBeforeLoad, item.writerVersion,
        "Map reload writer head changed before load");
      assert.equal(item.writerVersionAfterLoad, item.writerVersion,
        "Map reload writer head changed after continuation");
      assert(Number.isSafeInteger(item.tailSequenceNumber)
        && item.tailSequenceNumber > item.publicationSequenceNumber,
      "Map reload lacks a measured operation after publication");
      artifacts(item, evidence, expected, {
        kind: "map-reload",
        subject: `${writer}->${reader}`,
        documentId: item.documentId,
      }, `Map reload ${writer}->${reader}`);
      for (const reference of item.artifacts) {
        const claim = evidence.get(reference).claim;
        assert.deepEqual(claim.measured,
          reloadMeasuredPayload(item),
        `Map reload ${writer}->${reader} artifact differs from measured evidence`);
        if (reader === "upstream") continue;
        const load = object(claim.raw?.load,
          "Map reload artifact lacks raw native load evidence");
        assert(Array.isArray(load.handshakes) && load.handshakes.length > 0,
          "Map reload artifact lacks native handshake evidence");
        assert(Array.isArray(load.repairRequests),
          "Map reload artifact lacks repair-request evidence");
      }
    }
  }
}

function observations(item, label) {
  assert.equal(item?.skipped, false, `${label} was skipped`);
  assert(Array.isArray(item?.observations) && item.observations.length > 0,
    `${label} has zero observations`);
}

function validateSchemaSections(report, expected, evidence) {
  for (const section of requiredSchemaSections) {
    assert(report[section] !== undefined, `Missing ${section}`);
  }

  assert.deepEqual(
    report.schemaCompatibility.map(({ target }) => target).sort(),
    [...implementations].sort(),
    "schemaCompatibility lacks a target",
  );
  for (const item of report.schemaCompatibility) {
    assert.equal(item.runId, expected.runId,
      "schemaCompatibility belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "schemaCompatibility uses another profile");
    assert(typeof item.target === "string" && item.target.length > 0,
      "schemaCompatibility lacks a target");
    assert.equal(item.protocolVersion, reference.version,
      "schemaCompatibility used another protocol version");
    observations(item, `schemaCompatibility ${item.target}`);
    const observation = item.observations[0];
    assert(typeof observation.documentId === "string"
      && observation.documentId.length > 0,
    "schemaCompatibility lacks a document");
    assert(typeof observation.instanceId === "string"
      && observation.instanceId.length > 0,
    "schemaCompatibility lacks an instance");
    assert.deepEqual(observation.compatibility, {
      canView: false,
      canUpgrade: true,
      isEquivalent: false,
    }, "schemaCompatibility reported another result");
    schemaArtifact(item, evidence, expected, "schema-compatibility",
      item.target, observation.documentId, `schemaCompatibility ${item.target}`);
  }

  assert.deepEqual(
    report.schemaRaces.map(({ id }) => id).sort(),
    [...requiredSchemaRaceIds].sort(),
    "schemaRaces lacks a race ordering",
  );
  for (const item of report.schemaRaces) {
    assert.equal(item.runId, expected.runId, "schemaRaces belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "schemaRaces uses another profile");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      `${item.id} lacks a document`);
    assert(item.instanceIds && implementations.every((target) =>
      typeof item.instanceIds[target] === "string"
      && item.instanceIds[target].length > 0),
    `${item.id} lacks client instances`);
    observations(item, `schemaRaces ${item.id}`);
    const observation = item.observations[0];
    if (item.family === "upgrade-then-edit") {
      assert.equal(observation.dependentEditRetained, true,
        `${item.id} lost its causal dependent edit`);
      assert(Array.isArray(observation.referenceSequenceNumbers)
        && observation.referenceSequenceNumbers.length > 0,
      `${item.id} lacks causal sequence evidence`);
    } else {
      assert.equal(observation.sequenceNumbers.length, 2,
        `${item.id} lacks both sequenced submissions`);
      assert.equal(new Set(observation.referenceSequenceNumbers).size, 1,
        `${item.id} was not concurrent`);
      assert.equal(observation.oldViewRejected, true,
        `${item.id} did not invalidate the old view`);
      assert.equal(observation.documentHealthy, true,
        `${item.id} left the document unhealthy`);
      assert(Array.isArray(observation.submissions)
        && observation.submissions.length === 2,
      `${item.id} lacks decoded race submissions`);
      assert(typeof observation.losingAuthor === "string"
        && [item.upgrader, item.competitor].includes(observation.losingAuthor),
      `${item.id} lacks the losing author`);
      assert(Array.isArray(observation.rollback?.observations),
        `${item.id} lacks a pre-ack rollback checkpoint`);
      const loser = observation.rollback.observations.find(
        ({ implementation }) => implementation === observation.losingAuthor,
      );
      assert(loser?.pendingTreeCount > 0 && loser.history,
        `${item.id} lacks the loser's pending rollback state`);
      const notifications = object(observation.notifications,
        `${item.id} lacks typed notifications`);
      assert(Object.values(notifications).some(({ schema }) =>
        Array.isArray(schema) && schema.length > 0),
      `${item.id} lacks schema notifications`);
      if (item.family === "schema-data") {
        assert(Object.values(notifications).some(({ data }) =>
          Array.isArray(data) && data.length > 0),
        `${item.id} lacks data notifications`);
      }
      if (item.family === "schema-schema") {
        assert.equal(observation.intermediateRollback, true,
          `${item.id} lacks rollback evidence`);
        assert.equal(observation.reconciledPending?.changeset?.changeCount, 0,
          `${item.id} lacks an empty losing outer change`);
        const raw = observation.reconciledPending.changeset.raw;
        assert(
          (typeof raw === "string" && raw.length > 0)
          || (raw && typeof raw === "object" && Object.keys(raw).length > 0),
        `${item.id} lacks raw losing changeset evidence`);
        const losingCommit = observation.losingSubmission.commits[0];
        assert.equal(observation.originalPending?.originatorId,
          losingCommit.originatorId,
        `${item.id} original pending change identifies another originator`);
        assert.deepEqual(
          decodeReconnectPayload(
            observation.originalPending.changeset.payload
              ?? observation.originalPending.changeset.raw,
          ),
          decodeReconnectPayload(losingCommit.changeset),
        `${item.id} original pending change differs from the losing operation`);
        assert.equal(String(observation.reconciledPending.revision),
          String(observation.originalPending.revision),
        `${item.id} rollback identifies another revision`);
        assert.equal(observation.reconciledPending.originatorId,
          losingCommit.originatorId,
        `${item.id} rollback identifies another originator`);
        assert.equal(rawChangeCount(raw), 0,
          `${item.id} rollback raw payload is not empty`);
      }
    }
    schemaArtifact(item, evidence, expected, "schema-races", item.id,
      item.documentId, `schemaRaces ${item.id}`);
  }

  assert.deepEqual(
    report.schemaReconnect.map(({ target }) => target).sort(),
    [...implementations].sort(),
    "schemaReconnect lacks a target",
  );
  for (const item of report.schemaReconnect) {
    assert.equal(item.runId, expected.runId,
      "schemaReconnect belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "schemaReconnect uses another profile");
    observations(item, `schemaReconnect ${item.target}`);
    assert.deepEqual(item.observations.map(({ caseId }) => caseId).sort(), [
      "upgrade-accepted-before-drop",
      "upgrade-unacknowledged",
    ], `schemaReconnect ${item.target} lacks a reconnect case`);
    const unacknowledged = item.observations.find(
      ({ caseId }) => caseId === "upgrade-unacknowledged",
    );
    const accepted = item.observations.find(
      ({ caseId }) => caseId === "upgrade-accepted-before-drop",
    );
    assert.equal(unacknowledged.acceptedBeforeDrop, false);
    assert.equal(unacknowledged.acceptedSequenceNumber, null);
    assert(unacknowledged.pendingTreeCount > 0,
      `${item.target} lacks an unacknowledged pending schema change`);
    assert.equal(accepted.acceptedBeforeDrop, true);
    assert(Number.isSafeInteger(accepted.acceptedSequenceNumber),
      `${item.target} lacks accepted-before-drop sequence evidence`);
    for (const observation of item.observations) {
      assert(typeof observation.documentId === "string"
        && observation.documentId.length > 0,
      `${item.target} reconnect lacks a document`);
      assert(typeof observation.instanceId === "string"
        && observation.instanceId.length > 0,
      `${item.target} reconnect lacks an instance`);
      assert(Array.isArray(observation.originalRevisions)
        && observation.originalRevisions.length >= 2,
      `${item.target} reconnect lacks original revisions`);
      assert(Array.isArray(observation.acceptedCommits)
        && observation.acceptedCommits.length === 2,
      `${item.target} reconnect lacks accepted revisions`);
      assert(Array.isArray(observation.originalOperations)
        && observation.originalOperations.length === 2,
      `${item.target} reconnect lacks original operation semantics`);
      assert(Array.isArray(observation.acceptedMappings)
        && observation.acceptedMappings.length === 2,
      `${item.target} reconnect lacks one-to-one acceptance mapping`);
      assert(observation.acceptedCommits.every(({ revision, originatorId,
        changeset }) =>
        (typeof revision === "string" || Number.isSafeInteger(revision))
          && typeof originatorId === "string" && originatorId.length > 0
          && Array.isArray(changeset) && changeset.length > 0),
      `${item.target} reconnect has erased or fictitious accepted commits`);
      assert(observation.originalOperations.every(({ revision, originatorId,
        payload }) =>
        observation.originalRevisions.map(String).includes(String(revision))
          && typeof originatorId === "string" && originatorId.length > 0
          && payload !== undefined),
      `${item.target} reconnect has fictitious original operations`);
      const mappings = matchReconnectOperations(
        observation.originalOperations,
        observation.acceptedCommits.map((commit) => ({
          ...commit,
          payload: commit.changeset,
        })),
      );
      assert.deepEqual(observation.acceptedMappings, mappings,
        `${item.target} reconnect recorded another acceptance mapping`);
      assert.equal(observation.orderedReplay, true,
        `${item.target} reconnect did not preserve upgrade ordering`);
      assert.equal(observation.exactlyOnce, true,
        `${item.target} reconnect did not prove exactly-once acceptance`);
      assert.equal(observation.allClientsObservedDependentData, true,
        `${item.target} reconnect did not converge on every client`);
      assert(Array.isArray(observation.pending?.history?.pending)
        && observation.pending.history.pending.length >= 2,
      `${item.target} reconnect lacks pending history`);
      const reference = item.artifacts.find((candidate) => {
        const claim = evidence.get(candidate)?.claim;
        return claim?.subject === `${item.target}:${observation.caseId}`;
      });
      assert(reference, `${item.target} reconnect lacks case artifact evidence`);
      const claim = evidence.get(reference).claim;
      assert.equal(claim.runId, expected.runId,
        `${item.target} reconnect artifact belongs to another run`);
      assert.equal(claim.profileDigest, expected.profileDigest,
        `${item.target} reconnect artifact uses another profile`);
      assert.equal(claim.kind, "schema-reconnect",
        `${item.target} reconnect artifact has another kind`);
      assert.equal(claim.documentId, observation.documentId,
        `${item.target} reconnect artifact describes another document`);
      assert.deepEqual(claim.result, observation,
        `${item.target} reconnect artifact differs from report evidence`);
    }
    assert.equal(item.artifacts.length, item.observations.length,
      `${item.target} reconnect has unrelated artifact evidence`);
  }

  validateSchemaReloadResults(report.schemaReloadMatrix);
  for (const row of Object.values(report.schemaReloadMatrix)) {
    for (const item of Object.values(row)) {
      assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
        `schemaReloadMatrix ${item.writer}->${item.reader} lacks artifact evidence`);
      assert.equal(item.runId, expected.runId,
        "schemaReloadMatrix belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "schemaReloadMatrix uses another profile");
      const observation = item.observations[0];
      assert(typeof observation.documentId === "string"
        && observation.documentId.length > 0,
      "schemaReloadMatrix lacks a document");
      assert(typeof observation.readerInstanceId === "string"
        && observation.readerInstanceId.length > 0,
      "schemaReloadMatrix lacks a reader instance");
      assert(typeof observation.pendingWriterInstanceId === "string"
        && observation.pendingWriterInstanceId.length > 0,
      "schemaReloadMatrix lacks the pending writer instance");
      assert(typeof observation.loadedVersion === "string"
        && observation.loadedVersion === observation.upgradedSummaryVersion,
      "schemaReloadMatrix did not load the post-upgrade summary");
      assert(Array.isArray(observation.selectedSummaryRequests)
        && observation.selectedSummaryRequests.includes(observation.loadedVersion),
      "schemaReloadMatrix did not select its summary");
      assert(Number.isSafeInteger(observation.pendingSummaryReferenceSequenceNumber)
        && Number.isSafeInteger(observation.schemaUpgradeSequenceNumber)
        && observation.schemaUpgradeSequenceNumber
          > observation.pendingSummaryReferenceSequenceNumber,
      "schemaReloadMatrix lacks an upgrade-bearing tail");
      assert(observation.freshLoadCheckpoint?.history
        && observation.beforeContinuation?.history,
        "schemaReloadMatrix lacks fresh pre-continuation state");
      const retainedCommit = observation.acceptedRetainedPeer?.commits?.find(
        ({ changeset }) => changeset.some((change) => change.data !== undefined),
      );
      const upgradeCommit = observation.acceptedUpgrade?.commits?.find(
        ({ changeset }) => changeset.some((change) => change.schema !== undefined),
      );
      assert(retainedCommit && upgradeCommit,
        "schemaReloadMatrix lacks accepted retained and upgrade operations");
      assert(observation.pendingWriterCheckpoint?.history?.pending?.length > 0,
        "schemaReloadMatrix lacks writer pending history");
      assert.equal(observation.pendingStoredState?.version,
        observation.pendingSummaryVersion,
      "schemaReloadMatrix inspected another baseline summary");
      assert.equal(observation.pendingSummaryPublication?.version,
        observation.pendingSummaryVersion,
      "schemaReloadMatrix publication names another pending summary version");
      assert(observation.pendingSummaryPublication?.snapshotSequenceNumber
        >= observation.pendingSummaryReferenceSequenceNumber,
      "schemaReloadMatrix publication preceded the capture sequence");
      assert(observation.pendingPublicationVerification?.load
        ?.selectedSummaryRequests.includes(observation.pendingSummaryVersion),
      "schemaReloadMatrix did not freshly load the pending summary");
      assert.deepEqual(
        observation.pendingPublicationVerification.checkpoint.wholeTree,
        observation.captureSequencedCheckpoint.wholeTree,
      "schemaReloadMatrix pending publication decoded another sequenced tree");
      assert(typeof observation.pendingStoredState?.rootTreeId === "string"
        && observation.pendingStoredState.treeIds?.includes(
          observation.pendingStoredState.rootTreeId,
        ),
      "schemaReloadMatrix lacks the selected summary tree");
      assert(typeof observation.pendingStoredState?.schema?.id === "string"
        && typeof observation.pendingStoredState.schema.content === "string"
        && typeof observation.pendingStoredState?.forest?.treeId === "string"
        && observation.pendingStoredState.forest.blobs?.length > 0,
      "schemaReloadMatrix lacks stored schema and forest blobs");
      assert.equal(observation.pendingSummaryCapture?.sequenceNumber,
        observation.pendingSummaryReferenceSequenceNumber,
      "schemaReloadMatrix pending encoder used another sequence point");
      assert.equal(observation.upgradedStoredState?.version,
        observation.loadedVersion,
      "schemaReloadMatrix inspected another upgraded summary");
      assert.equal(observation.pendingSummaryBinding?.schema,
        "sequenced-at-capture",
      "schemaReloadMatrix lacks schema summary binding");
      assert.equal(observation.pendingSummaryBinding?.forest,
        "sequenced-at-capture",
      "schemaReloadMatrix lacks forest summary binding");
      assert.equal(observation.retainedEncoderReference?.sequenceNumber,
        observation.acceptedRetainedPeer?.outerSequenceNumber,
      "schemaReloadMatrix retained encoder reference identifies another operation");
      assert.equal(observation.pendingSummaryReferenceSequenceNumber,
        observation.captureEncoderReference.sequenceNumber,
      "schemaReloadMatrix capture does not identify its sequenced state");
      assert(observation.sequencedEncoderReference?.sequenceNumber
        >= observation.schemaUpgradeSequenceNumber,
      "schemaReloadMatrix encoder reference precedes the sequenced upgrade");
      assert(observation.sequencedWriterCheckpoint?.sequenceNumber
          >= observation.schemaUpgradeSequenceNumber
        && observation.sequencedWriterCheckpoint.pendingTreeCount === 0,
      "schemaReloadMatrix encoder reference precedes upgrade reconciliation");
      assert.equal(observation.pendingSummaryBinding?.upgradeSequenceNumber,
        observation.sequencedEncoderReference.sequenceNumber,
      "schemaReloadMatrix binding identifies another sequence point");
      assert.equal(observation.pendingSummaryBinding?.captureSequenceNumber,
        observation.pendingSummaryReferenceSequenceNumber,
      "schemaReloadMatrix binding identifies another capture sequence point");
      const sequencedCaptureReference =
        observation.pendingSummaryCaptureSourceBehavior
            === "upstream-optimistic-encoder-retained-future-state"
          ? observation.captureEncoderReference
          : observation.retainedEncoderReference;
      assert.deepEqual(JSON.parse(observation.pendingSummaryCapture.schema.content),
        JSON.parse(sequencedCaptureReference.schema.content),
      "schemaReloadMatrix pending schema differs from sequenced state at capture");
      const pendingForestContents = observation.pendingSummaryCapture.forest
        .map(({ content }) => content).sort();
      assert.deepEqual(pendingForestContents,
        sequencedCaptureReference.forest
          .map(({ content }) => content).sort(),
      "schemaReloadMatrix pending forest differs from sequenced state at capture");
      const acceptedSchemaChange = observation.acceptedUpgrade?.commits
        ?.flatMap(({ changeset }) => changeset)
        .find((change) => change?.schema !== undefined);
      assert(acceptedSchemaChange,
      "schemaReloadMatrix lacks decoded accepted upgrade history");
      assert.deepEqual(JSON.parse(observation.pendingStoredState.schema.content),
        acceptedSchemaChange.schema.old,
      "schemaReloadMatrix stored pending schema instead of historical schema");
      schemaArtifact(item, evidence, expected, "schema-reload",
        `${item.writer}-${item.reader}`, observation.documentId,
        `schemaReloadMatrix ${item.writer}->${item.reader}`);
    }
  }

  validateSchemaTailReloadResults(report.schemaTailReloadMatrix);
  for (const row of Object.values(report.schemaTailReloadMatrix)) {
    for (const item of Object.values(row)) {
      assert.equal(item.runId, expected.runId,
        "schemaTailReloadMatrix belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "schemaTailReloadMatrix uses another profile");
      const observation = item.observations[0];
      schemaArtifact(item, evidence, expected, "schema-tail-reload",
        `${item.writer}-${item.reader}`, observation.documentId,
        `schemaTailReloadMatrix ${item.writer}->${item.reader}`);
    }
  }
}

function validateArrayReload(report, expected, evidence) {
  validateArrayResults(report.arrayReload);
  for (const writer of implementations) {
    for (const reader of implementations) {
      const item = report.arrayReload[writer][reader];
      assert.equal(item.runId, expected.runId,
        "Array reload belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "Array reload uses another profile");
      assert.equal(item.writerVersionBeforeLoad, item.writerVersion,
        "Array reload writer head changed before load");
      assert.equal(item.writerVersionAfterLoad, item.writerVersion,
        "Array reload writer head changed after continuation");
      assert(Number.isSafeInteger(item.tailSequenceNumber)
        && item.tailSequenceNumber > item.publicationSequenceNumber,
      "Array reload lacks a measured operation after publication");
      artifacts(item, evidence, expected, {
        kind: "array-reload",
        subject: `${writer}->${reader}`,
        documentId: item.documentId,
      }, `Array reload ${writer}->${reader}`);
      for (const reference of item.artifacts) {
        const claim = evidence.get(reference).claim;
        assert.deepEqual(claim.measured,
          reloadMeasuredPayload(item),
        `Array reload ${writer}->${reader} artifact differs from measured evidence`);
        if (reader === "upstream") continue;
        const load = object(claim.raw?.load,
          "Array reload artifact lacks raw native load evidence");
        assert(Array.isArray(load.handshakes) && load.handshakes.length > 0,
          "Array reload artifact lacks native handshake evidence");
        assert(Array.isArray(load.repairRequests),
          "Array reload artifact lacks repair-request evidence");
      }
    }
  }
}

function validateIdentifierSections(report, expected, evidence) {
  validateIdentifierFields(report.identifierFields);
  for (const item of report.identifierFields.pairs) {
    assert.equal(item.runId, expected.runId,
      "Identifier pair belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Identifier pair uses another profile");
    artifacts(item, evidence, expected, {
      kind: "identifier-fields",
      subject: item.id,
      documentId: item.documentId,
    }, `Identifier pair ${item.id}`);
  }
  for (const item of report.identifierFields.failures) {
    assert.equal(item.runId, expected.runId,
      "Identifier refusal belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Identifier refusal uses another profile");
    artifacts(item, evidence, expected, {
      kind: "identifier-refusal",
      subject: `${item.caseId}:${item.target}`,
      documentId: item.documentId,
    }, `Identifier refusal ${item.caseId}:${item.target}`);
  }
  validateIdentifierReloadResults(report.identifierReloadMatrix);
  for (const writer of implementations) {
    for (const reader of implementations) {
      const item = report.identifierReloadMatrix[writer][reader];
      assert.equal(item.runId, expected.runId,
        "Identifier reload belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "Identifier reload uses another profile");
      artifacts(item, evidence, expected, {
        kind: "identifier-reload",
        subject: `${writer}->${reader}`,
        documentId: item.documentId,
      }, `Identifier reload ${writer}->${reader}`);
    }
  }
}

function validateTransactionSections(report, expected, evidence) {
  for (const section of requiredTransactionSections) {
    assert(report[section] !== undefined, `Missing ${section}`);
  }
  validateTransactionCallbacks(report.transactionCallbacks);
  for (const item of report.transactionCallbacks.pairs) {
    assert.equal(item.runId, expected.runId,
      "Transaction pair belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Transaction pair uses another profile");
    artifacts(item, evidence, expected, {
      kind: "transaction-callbacks",
      subject: item.id,
      documentId: item.documentId,
    }, `Transaction pair ${item.id}`);
  }
  validateTransactionConstraints(report.transactionConstraints);
  for (const item of report.transactionConstraints) {
    assert.equal(item.runId, expected.runId,
      "Transaction constraint belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Transaction constraint uses another profile");
    artifacts(item, evidence, expected, {
      kind: "transaction-constraint",
      subject: item.id,
      documentId: item.documentId,
    }, `Transaction constraint ${item.id}`);
  }
  validateTransactionReconnectResults(report.transactionReconnect, expected.runId);
  for (const item of report.transactionReconnect) {
    assert.equal(item.profileDigest, expected.profileDigest,
      "Transaction reconnect uses another profile");
    artifacts(item.evidence, evidence, expected, {
      kind: "transaction-reconnect",
      subject: `${item.target}:${item.caseId}`,
      documentId: item.documentId,
    }, `Transaction reconnect ${item.target}:${item.caseId}`);
  }
  validateTransactionReloadResults(report.transactionReloadMatrix);
  for (const writer of implementations) {
    for (const reader of implementations) {
      const item = report.transactionReloadMatrix[writer][reader];
      assert.equal(item.runId, expected.runId,
        "Transaction reload belongs to another run");
      assert.equal(item.profileDigest, expected.profileDigest,
        "Transaction reload uses another profile");
      artifacts(item, evidence, expected, {
        kind: "transaction-reload",
        subject: `${writer}->${reader}`,
        documentId: item.documentId,
      }, `Transaction reload ${writer}->${reader}`);
    }
  }
}

function undoRedoMeasuredPayload(item) {
  return Object.fromEntries(Object.entries(item)
    .filter(([name]) => name !== "artifacts"));
}

function validUndoRedoRow(item, evidence, expected, contract, label) {
  assert.equal(item.runId, expected.runId, `${label} belongs to another run`);
  assert.equal(item.profileDigest, expected.profileDigest,
    `${label} uses another profile`);
  assert(typeof item.documentId === "string" && item.documentId.length > 0,
    `${label} lacks a document ID`);
  assert.equal(item.passed, true, `${label} did not pass`);
  assert.equal(item.failed, false, `${label} is marked failed`);
  assert.equal(item.skipped, false, `${label} was skipped`);
  assert.equal(item.error, null, `${label} contains an error`);
  artifacts(item, evidence, expected, contract, label);
  for (const reference of item.artifacts) {
    const claim = evidence.get(reference).claim;
    assert.deepEqual(claim.measured, undoRedoMeasuredPayload(item),
      `${label} artifact measured payload differs`);
    object(claim.raw, `${label} artifact lacks raw observations`);
  }
}

function undoRedoArtifact(item, evidence, label) {
  assert.equal(item.artifacts.length, 1,
    `${label} must resolve to one source artifact`);
  return evidence.get(item.artifacts[0]).claim;
}

function successfulResult(result, label) {
  object(result, `${label} lacks a result`);
  assert.equal(result.error, undefined, `${label} contains an error`);
  assert.notEqual(result.settlement, "FullyDropped",
    `${label} contains a failed settlement`);
  return result;
}

function jsonValue(value, label) {
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    assert.fail(`${label} is not valid JSON`);
  }
}

function decodedPayloadOperation(payload, clientSequenceNumber, label) {
  assert(typeof payload?.clientId === "string" && payload.clientId.length > 0,
    `${label} payload lacks a client ID`);
  assert(Array.isArray(payload.messageBatches),
    `${label} payload lacks message batches`);
  const operations = payload.messageBatches.flat();
  const operation = operations.find(
    (candidate) => candidate.clientSequenceNumber === clientSequenceNumber,
  );
  assert(operation, `${label} payload lacks its operation`);
  const outer = jsonValue(operation.contents, `${label} operation contents`);
  const items = outer?.type === "groupedBatch" && Array.isArray(outer.contents)
    ? outer.contents
    : outer?.type === "component"
      ? [{ contents: outer }]
      : [];
  const commits = items.flatMap((item) => {
    const tree = item.contents?.type === "component"
      ? item.contents.contents?.contents?.content?.contents
      : undefined;
    if (tree?.revision === undefined
      || typeof tree?.originatorId !== "string"
      || !Array.isArray(tree?.changeset)) {
      return [];
    }
    return [{
      revision: tree.revision,
      originatorId: tree.originatorId,
      changeset: tree.changeset,
    }];
  });
  assert(commits.length > 0, `${label} lacks a decoded tree commit`);
  return {
    clientId: payload.clientId,
    clientSequenceNumber,
    operationId: `revision:${commits.map(({ originatorId, revision }) =>
      `${originatorId}:${revision}`).join(",")}`,
    commits,
  };
}

function decodedOutboundOperation(record, label) {
  object(record, `${label} lacks an outbound record`);
  assert(Number.isSafeInteger(record.sendId) && record.sendId > 0,
    `${label} has an invalid send ID`);
  assert(["original", "reconnect-retry", "duplicate-send"]
    .includes(record.classification),
    `${label} has an unknown send classification`);
  assert(typeof record.clientId === "string" && record.clientId.length > 0,
    `${label} lacks a client ID`);
  assert(typeof record.clientInstanceId === "string"
    && record.clientInstanceId.length > 0,
  `${label} lacks a client instance ID`);
  assert(typeof record.transportId === "string" && record.transportId.length > 0,
    `${label} lacks a transport identity`);
  assert(Number.isSafeInteger(record.connectionEpoch)
    && record.connectionEpoch > 0,
  `${label} lacks a connection epoch`);
  assert(typeof record.stableRevision === "string"
    && record.stableRevision.length > 0,
  `${label} lacks a stable revision`);
  assert(Number.isSafeInteger(record.clientSequenceNumber)
    && record.clientSequenceNumber >= 0,
  `${label} lacks a client sequence number`);
  const payload = object(record.payload, `${label} lacks the raw submit payload`);
  assert.equal(payload.clientId, record.clientId,
    `${label} payload names another client`);
  const decoded = decodedPayloadOperation(
    payload,
    record.clientSequenceNumber,
    label,
  );
  assert.equal(record.operationId, decoded.operationId,
  `${label} has an unstable operation ID`);
  return { record, commits: decoded.commits };
}

function exactOutboundEvidence(
  records,
  transportObservations,
  transportConnections,
  eventId,
  label,
) {
  assert(Array.isArray(records),
    `${label} lacks native outbound send records`);
  const decoded = records.map((record, index) =>
    decodedOutboundOperation(record, `${label} outbound ${index}`));
  assert(Array.isArray(transportConnections)
    && transportConnections.length > 0,
  `${label} lacks raw transport connections`);
  const connections = new Map();
  for (const connection of transportConnections) {
    assert(typeof connection.connectionId === "string"
      && connection.connectionId.length > 0,
    `${label} has an invalid transport connection`);
    assert(Number.isSafeInteger(connection.epoch) && connection.epoch > 0,
      `${label} transport connection lacks an epoch`);
    assert.equal(connection.state, "opened",
      `${label} transport connection was not opened`);
    assert(!connections.has(connection.connectionId),
      `${label} repeats a transport connection`);
    connections.set(connection.connectionId, connection);
  }
  assert(Array.isArray(transportObservations),
    `${label} lacks raw transport occurrences`);
  const occurrences = transportObservations.flatMap((observation, index) => {
    const occurrenceId = observation.occurrenceId ?? observation.id;
    assert(Number.isSafeInteger(occurrenceId) && occurrenceId > 0,
      `${label} transport occurrence ${index} lacks an ID`);
    const connection = connections.get(observation.connectionId);
    assert(connection,
      `${label} transport occurrence ${index} lacks its connection`);
    const submissions = observation.submissions;
    assert(Array.isArray(submissions) && submissions.length > 0,
      `${label} transport occurrence ${index} lacks submissions`);
    return submissions.flatMap((payload, submissionIndex) =>
      payload.messageBatches.flat().map((operation, operationIndex) => ({
        occurrenceId,
        connection,
        payload,
        ...decodedPayloadOperation(
          payload,
          operation.clientSequenceNumber,
          `${label} transport occurrence ${index}.${submissionIndex}.${operationIndex}`,
        ),
      })));
  });
  assert.equal(occurrences.length, decoded.length,
    `${label} outbound records differ from raw transport occurrences`);
  const matched = new Set();
  const classified = occurrences.map((occurrence) => {
    const match = decoded.findIndex(({ record, commits }, index) =>
      !matched.has(index)
        && record.clientId === occurrence.clientId
        && record.clientSequenceNumber === occurrence.clientSequenceNumber
        && record.operationId === occurrence.operationId
        && isDeepStrictEqual(commits, occurrence.commits));
    assert(match >= 0, `${label} transport occurrence has no outbound record`);
    matched.add(match);
    return { occurrence, outbound: decoded[match] };
  });
  const seen = new Map();
  for (const evidence of classified) {
    const { occurrence, outbound } = evidence;
    const original = seen.get(occurrence.operationId);
    const classification = original === undefined
      ? "original"
      : original.connection.connectionId === occurrence.connection.connectionId
        ? "duplicate-send"
        : "reconnect-retry";
    assert.equal(outbound.record.classification, classification,
      `${label} outbound classification differs from raw transport evidence`);
    assert.equal(outbound.record.transportId, occurrence.connection.connectionId,
      `${label} outbound transport differs from raw transport evidence`);
    assert.equal(outbound.record.connectionEpoch, occurrence.connection.epoch,
      `${label} outbound epoch differs from raw transport evidence`);
    if (classification === "reconnect-retry") {
      assert(occurrence.connection.epoch > original.connection.epoch,
        `${label} retry lacks a later observed connection epoch`);
    }
    if (original === undefined) seen.set(occurrence.operationId, occurrence);
    evidence.classification = classification;
  }
  const originals = classified.filter(
    ({ classification }) => classification === "original",
  ).map(({ outbound }) => outbound);
  assert.equal(originals.length, 1,
    `${label} requires exactly one original outbound send`);
  assert.equal(classified.filter(
    ({ classification }) => classification === "duplicate-send",
  ).length, 0, `${label} contains another send on the same transport`);
  assert(classified.every(({ outbound }) =>
    outbound.record.operationId === originals[0].record.operationId),
  `${label} transport occurrence names another operation`);
  assert.equal(new Set(decoded.map(({ record }) => record.sendId)).size,
    decoded.length, `${label} repeats a send occurrence`);
  assert.equal(originals[0].record.authoredEventId,
    eventId,
  `${label} outbound send names another authored event`);
  return { ...originals[0], records: decoded };
}

function exactActionEvidence(result, label) {
  successfulResult(result, label);
  assert(Array.isArray(result.authoredEventIds)
    && result.authoredEventIds.length === 1
    && Number.isSafeInteger(result.authoredEventIds[0]),
  `${label} lacks one authored event ID`);
  assert(Array.isArray(result.submittedRevisions)
    && result.submittedRevisions.length === 1
    && typeof result.submittedRevisions[0] === "string"
    && result.submittedRevisions[0].length > 0,
  `${label} lacks one submitted revision`);
  assert.equal(result.authoredCount, result.authoredEventIds.length,
    `${label} authored count differs from event evidence`);
  const original = exactOutboundEvidence(
    result.outboundRecords,
    result.transportObservations,
    result.transportConnections,
    result.authoredEventIds[0],
    label,
  );
  assert.equal(original.record.stableRevision, result.submittedRevisions[0],
    `${label} outbound send resolves to another stable revision`);
  assert(typeof result.actionId === "string" && result.actionId.length > 0,
    `${label} lacks an action identity`);
  assert.equal(result.revisionResolution?.actionId, result.actionId,
    `${label} revision resolution names another action`);
  assert.equal(result.revisionResolution?.stableRevision,
    result.submittedRevisions[0],
  `${label} revision resolution names another stable revision`);
  assert.equal(result.outboundCount, 1,
    `${label} outbound count differs from original send evidence`);
  return original;
}

function localCommitEvents(raw, author, label) {
  const trace = object(raw.eventTrace, `${label} lacks raw event traces`);
  const events = author === undefined ? trace : trace[author];
  assert(Array.isArray(events), `${label} lacks local commit events`);
  const commits = events.filter(
    ({ type, local }) => type === "commit" && local === true,
  );
  assert(commits.every(({ eventId }) => Number.isSafeInteger(eventId)),
    `${label} local commits lack event IDs`);
  assert.equal(new Set(commits.map(({ eventId }) => eventId)).size,
    commits.length, `${label} repeats a local commit event ID`);
  assert(commits.every((commit, index) =>
    index === 0 || commit.eventId > commits[index - 1].eventId),
  `${label} local commit event IDs are not monotonic`);
  return { events, commits };
}

function offsetUuid(value, offset, label) {
  if (offset === 0) return value;
  assert.match(value,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    `${label} allocation session is not a UUID`);
  const hex = value.replaceAll("-", "");
  const next = (BigInt(`0x${hex}`) + BigInt(offset))
    .toString(16).padStart(32, "0");
  return `${next.slice(0, 8)}-${next.slice(8, 12)}-${next.slice(12, 16)}-${next.slice(16, 20)}-${next.slice(20)}`;
}

function acceptedStableRevision(submission, outbound, resolution, label) {
  assert.equal(submission.commits.length, 1,
    `${label} accepted operation has another commit count`);
  const commit = submission.commits[0];
  assert.equal(outbound.commits.length, 1,
    `${label} outbound operation has another commit count`);
  const submitted = outbound.commits[0];
  assert.equal(submitted.originatorId, commit.originatorId,
    `${label} accepted commit has another originator`);
  object(resolution, `${label} lacks its action-to-wire revision resolution`);
  assert(typeof resolution.stableRevision === "string"
    && resolution.stableRevision.length > 0,
  `${label} revision resolution lacks a stable revision`);
  const localRevision = resolution.localRevision != null
      && Number.isSafeInteger(Number(resolution.localRevision))
    ? Number(resolution.localRevision)
    : undefined;
  if (localRevision !== undefined) {
    assert.equal(submitted.revision, localRevision,
      `${label} revision resolution differs from the accepted wire revision`);
    assert.equal(commit.revision, localRevision,
      `${label} accepted commit differs from the resolved wire revision`);
  }
  const allocations = submission.allocations.filter(
    ({ sessionId, first, last }) =>
      sessionId === commit.originatorId
        && Array.from(
          { length: last - first + 1 },
          (_, index) => offsetUuid(sessionId, first + index - 1, label),
        ).includes(resolution.stableRevision),
  );
  assert.equal(allocations.length, 1,
    `${label} accepted operation lacks one exact revision allocation`);
  const allocation = allocations[0];
  return resolution.stableRevision;
}

function acceptedOutboundOperation(raw, outbound, resolution, label) {
  assert(Array.isArray(raw.acceptedOperationPayloads),
    `${label} lacks preserved raw accepted operations`);
  const acceptedSubmissions = decodeTreeSubmissions(
    raw.acceptedOperationPayloads,
  );
  const acceptedOperations = acceptedTreeOperations(raw.acceptedOperationPayloads);
  assert(acceptedOperations.length > 0,
    `${label} raw accepted operations contain no tree commits`);
  if (raw.acceptedOperations !== undefined) {
    assert.deepEqual(raw.acceptedOperations, acceptedOperations,
      `${label} derived accepted operations changed`);
  }
  const operationIds = acceptedOperations.map(({ operationId }) => operationId);
  assert.equal(new Set(operationIds).size, operationIds.length,
    `${label} contains duplicate accepted operations`);
  const accepted = acceptedOperations.filter(
    ({ operationId }) => operationId === outbound.record.operationId,
  );
  assert.equal(accepted.length, 1,
    `${label} does not identify exactly one accepted raw operation`);
  const sent = outbound.records.find(({ record, commits }) =>
    record.clientId === accepted[0].clientId
      && record.clientSequenceNumber === accepted[0].clientSequenceNumber
      && isDeepStrictEqual(commits, accepted[0].commits));
  assert(sent, `${label} accepted operation does not match an outbound send`);
  assert.deepEqual(accepted[0].commits, sent.commits,
    `${label} accepted operation differs from the outbound payload`);
  const submission = acceptedSubmissions.find(
    ({ clientId, clientSequenceNumber }) =>
      clientId === accepted[0].clientId
        && clientSequenceNumber === accepted[0].clientSequenceNumber,
  );
  assert(submission, `${label} lacks its decoded accepted submission`);
  return {
    ...accepted[0],
    stableRevision: acceptedStableRevision(
      submission,
      outbound,
      resolution,
      label,
    ),
  };
}

function validateRetainedAction(raw, result, kind, events, label) {
  successfulResult(result, label);
  assert(Number.isSafeInteger(result.eventId),
    `${label} lacks a retained event ID`);
  assert(typeof result.actionId === "string" && result.actionId.length > 0,
    `${label} lacks a retained action ID`);
  assert(typeof result.revision === "string" && result.revision.length > 0,
    `${label} lacks a retained revision`);
  const outbound = exactOutboundEvidence(
    result.outboundRecords,
    result.transportObservations,
    result.transportConnections,
    result.eventId,
    label,
  );
  assert.equal(outbound.record.stableRevision, result.revision,
    `${label} outbound send resolves to another stable revision`);
  assert.equal(result.revisionResolution?.actionId, result.actionId,
    `${label} revision resolution names another action`);
  assert.equal(result.revisionResolution?.stableRevision, result.revision,
    `${label} revision resolution names another stable revision`);
  const checkpoints = Array.isArray(raw.checkpoints) ? raw.checkpoints : [];
  const checkpointEvents = checkpoints.flatMap(({ observations }) =>
    (observations ?? [])
      .filter(({ instanceId }) =>
        instanceId === outbound.record.clientInstanceId)
      .flatMap(({ commits }) => commits ?? []));
  const scopedEvents = checkpointEvents.length > 0 ? checkpointEvents : events;
  const authored = scopedEvents.find((event) =>
    event.type === "commit"
      && event.local === true
      && event.kind === kind
      && event.eventId === result.eventId);
  assert(authored, `${label} does not identify its retained commit event`);
  assert.equal(authored.factoryAvailable, true,
    `${label} retained commit event lacks a factory`);
  assert.equal(authored.handleAcquired, true,
    `${label} retained commit event lacks an acquired handle`);
  assert.equal(authored.actionId, result.actionId,
    `${label} retained event has another action identity`);
  assert(authored.revision === result.revision
      || (result.revisionResolution?.localRevision != null
        && String(authored.revision)
          === String(result.revisionResolution.localRevision))
      || authored.revision == null,
    `${label} retained event has another revision`);
  const accepted = acceptedOutboundOperation(
    raw,
    outbound,
    result.revisionResolution,
    label,
  );
  assert.equal(accepted.stableRevision, result.revision,
    `${label} retained revision differs from the accepted wire identity`);
}

function validateSequencedAction(raw, result, kind, label) {
  const outbound = exactActionEvidence(result, label);
  const eventId = result.authoredEventIds[0];
  const revision = result.submittedRevisions[0];
  const checkpoints = Array.isArray(raw.checkpoints) ? raw.checkpoints : [];
  const checkpointEvents = checkpoints.flatMap(({ observations }) =>
    (observations ?? [])
      .filter(({ instanceId }) =>
        instanceId === outbound.record.clientInstanceId)
      .flatMap(({ commits }) => commits ?? []));
  const events = checkpointEvents.length > 0
    ? checkpointEvents
    : Array.isArray(raw.eventTrace)
      ? raw.eventTrace
      : raw.eventTrace
        ? Object.values(raw.eventTrace).flat()
        : raw.final?.commits ?? [];
  const authored = events.find((event) =>
    event.type === "commit"
      && event.local === true
      && event.kind === kind
      && event.eventId === eventId);
  assert(authored, `${label} does not identify its authored commit event`);
  assert.equal(authored.actionId, result.actionId,
    `${label} commit event has another action identity`);
  assert(authored.revision === revision
      || (result.revisionResolution?.localRevision != null
        && String(authored.revision)
          === String(result.revisionResolution.localRevision))
      || authored.revision == null,
    `${label} commit event has another revision`);
  assert(Array.isArray(raw.sequencedHistory),
    `${label} lacks raw sequenced history`);
  const wireRevision = result.revisionResolution?.localRevision;
  assert(raw.sequencedHistory.some((entry) =>
    entry.revision === revision
      || (wireRevision != null
        && String(entry.revision) === String(wireRevision))),
  `${label} lacks its resolved sequenced revision`);
  const accepted = acceptedOutboundOperation(
    raw,
    outbound,
    result.revisionResolution,
    label,
  );
  assert.equal(accepted.stableRevision, revision,
    `${label} submitted revision differs from the accepted wire identity`);
  assert(events.some((event) =>
    event.type === "settlement"
      && event.kind === kind
      && event.actionId === authored.actionId
      && (event.revision === revision || event.revision == null)
      && event.outcome === "FullyApplied"),
  `${label} lacks a successful settlement`);
}

function validateUndoRedoScenarioArtifact(item, raw, label) {
  object(raw, `${label} lacks raw source evidence`);
  for (const phase of ["authored", "concurrent", "undone", "redone"]) {
    object(raw.checkpoints?.[phase], `${label} lacks the ${phase} checkpoint`);
    assert.deepEqual(raw.checkpoints[phase].wholeTree,
      item.snapshots?.[phase],
    `${label} ${phase} differs from its source checkpoint`);
    assert.deepEqual(raw.checkpoints[phase].wholeTree,
      item.expectedSnapshots?.[phase],
    `${label} ${phase} differs from its expected tree`);
  }
  assert.deepEqual(raw.checkpoints.redone.wholeTree, item.finalTree,
    `${label} final tree differs from its source checkpoint`);
  const trace = object(raw.eventTrace, `${label} lacks raw event traces`);
  const authorEvents = trace[item.authors?.[0] ?? item.implementation];
  assert(Array.isArray(authorEvents), `${label} lacks author events`);
  const local = authorEvents.filter(
    ({ type, local: isLocal }) => type === "commit" && isLocal === true,
  );
  assert.deepEqual(local.slice(-3).map(({ kind }) => kind), item.localKinds,
    `${label} raw local events changed`);
  assert(local.slice(-3).every(({ factoryAvailable, handleAcquired }) =>
    factoryAvailable === true && handleAcquired === true),
  `${label} raw local event lacks its factory`);
  const settlements = authorEvents.filter(({ type }) => type === "settlement");
  assert.deepEqual(settlements.slice(-3).map(({ outcome }) => outcome),
    item.settlements, `${label} raw settlements changed`);
  const lifecycle = raw.lifecycle;
  assert(Array.isArray(lifecycle) && lifecycle.length === 4,
    `${label} lacks raw handle lifecycle`);
  assert.equal(lifecycle[0].result.status, "Valid",
    `${label} retained another edit status`);
  assert.equal(lifecycle[1].result.status, "Disposed",
    `${label} undo kept another edit status`);
  assert.equal(lifecycle[2].result.status, "Valid",
    `${label} retained another undo status`);
  assert.equal(lifecycle[3].result.status, "Disposed",
    `${label} redo kept another undo status`);
  validateRetainedAction(
    raw,
    lifecycle[0].result,
    "Default",
    authorEvents,
    `${label} retained edit`,
  );
  validateSequencedAction(raw, lifecycle[1].result, "Undo", `${label} undo`);
  validateRetainedAction(
    raw,
    lifecycle[2].result,
    "Undo",
    authorEvents,
    `${label} retained undo`,
  );
  validateSequencedAction(raw, lifecycle[3].result, "Redo", `${label} redo`);
  if (item.authors) {
    const peerEvents = trace[item.authors[1]];
    assert(Array.isArray(peerEvents), `${label} lacks peer events`);
    const remote = peerEvents.filter(
      ({ type, local: isLocal }) => type === "commit" && isLocal === false,
    );
    assert(remote.length > 0
      && remote.every(({ factoryAvailable }) => factoryAvailable === false),
    `${label} lacks remote events without factories`);
  }
}

function validateCommitLifecycle(item, label, handleStatuses) {
  assert.deepEqual(item.localKinds, ["Default", "Undo", "Redo"],
    `${label} local commit kinds changed`);
  assert.deepEqual(item.factoryAvailability, [true, true, true],
    `${label} factory availability changed`);
  assert.deepEqual(item.handleStatuses, handleStatuses,
    `${label} handle statuses changed`);
  assert.deepEqual(item.settlements,
    ["FullyApplied", "FullyApplied", "FullyApplied"],
    `${label} lacks settlement observations`);
  assert.deepEqual(item.authoredCounts, [1, 1, 1],
    `${label} authored another commit count`);
  assert.deepEqual(item.outboundCounts, [1, 1, 1],
    `${label} submitted another operation count`);
}

function validateUndoRedoSections(report, evidence, expected) {
  for (const section of requiredUndoRedoSections) {
    assert(report[section] !== undefined, `Missing ${section}`);
  }
  const kinds = object(report.undoRedoKinds,
    "Undo/redo kinds evidence must be an object");
  assert(Array.isArray(kinds.implementations)
    && kinds.implementations.length === implementations.length,
  "Undo/redo kinds require every implementation");
  assert.deepEqual(
    kinds.implementations.map(({ implementation }) => implementation).sort(),
    [...implementations].sort(),
    "Undo/redo kinds lack an implementation",
  );
  for (const item of kinds.implementations) {
    validateCommitLifecycle(
      item,
      `${item.implementation} undo/redo kinds`,
      ["Valid", "Disposed"],
    );
    object(item.finalTree, `${item.implementation} lacks a final tree`);
    validUndoRedoRow(item, evidence, expected, {
      kind: "undo-redo-kind",
      subject: item.implementation,
      documentId: item.documentId,
    }, `${item.implementation} undo/redo kinds`);
    for (const reference of item.artifacts) {
      const raw = evidence.get(reference).claim.raw;
      assert.equal(raw.sourceId, item.sourceId,
        `${item.implementation} undo/redo kind artifact names another source`);
      assert(Array.isArray(raw.sourceArtifacts) && raw.sourceArtifacts.length > 0,
        `${item.implementation} undo/redo kind artifact lacks source evidence`);
      assert.equal(raw.sourceArtifacts.length, 1,
        `${item.implementation} undo/redo kind has multiple sources`);
      const sourceReference = raw.sourceArtifacts[0];
      assert(evidence.has(sourceReference),
        `${item.implementation} undo/redo kind source is not verified`);
      const source = evidence.get(sourceReference).claim;
      assert.equal(source.kind, "undo-redo",
        `${item.implementation} undo/redo kind source has another kind`);
      assert.equal(source.subject, item.sourceId,
        `${item.implementation} undo/redo kind source has another subject`);
      const sourceItem = object(source.measured,
        `${item.implementation} undo/redo kind source lacks measured evidence`);
      validateCommitLifecycle(
        sourceItem,
        `${item.implementation} undo/redo kind source`,
        ["Valid", "Disposed", "Disposed"],
      );
      validateUndoRedoScenarioArtifact(
        sourceItem,
        source.raw,
        `${item.implementation} undo/redo kind source`,
      );
      assert.deepEqual(sourceItem.localKinds, item.localKinds,
        `${item.implementation} undo/redo kinds differ from source events`);
      assert.deepEqual(sourceItem.settlements, item.settlements,
        `${item.implementation} settlements differ from source events`);
      assert.deepEqual(sourceItem.finalTree, item.finalTree,
        `${item.implementation} final tree differs from its source`);
    }
  }

  const pairs = [
    ["javascript", "upstream"],
    ["erlang", "upstream"],
    ["javascript", "erlang"],
  ];
  const fieldKinds = ["object", "map", "array", "move", "transaction"];
  const orders = ["a-first", "b-first"];
  const concurrent = report.undoRedoConcurrent;
  assert(Array.isArray(concurrent), "Undo/redo concurrent evidence must be an array");
  assert.equal(concurrent.length, pairs.length * fieldKinds.length * orders.length,
    "Undo/redo concurrent evidence lacks a field-kind row or race ordering");
  const cells = new Map(concurrent.map((item) => [item.id, item]));
  for (const authors of pairs) {
    for (const fieldKind of fieldKinds) {
      for (const order of orders) {
        const id = `undo-redo:${authors.join("<->")}:${fieldKind}:${order}`;
        const item = cells.get(id);
        assert(item, `Undo/redo concurrent evidence lacks ${id}`);
        assert.deepEqual(item.authors, authors, `${id} authors changed`);
        assert.equal(item.fieldKind, fieldKind, `${id} field kind changed`);
        assert.equal(item.order, order, `${id} race ordering changed`);
        validateCommitLifecycle(item, id, ["Valid", "Disposed", "Disposed"]);
        assert.equal(item.remoteFactoryAvailable, false,
          `${id} gave the peer a revertible factory`);
        assert.equal(item.passed, true, `${id} failed`);
        assert.equal(item.skipped, false, `${id} was skipped`);
        for (const phase of ["authored", "concurrent", "undone", "redone"]) {
          object(item.snapshots?.[phase], `${id} lacks the ${phase} snapshot`);
          assert.deepEqual(item.snapshots[phase], item.expectedSnapshots?.[phase],
            `${id} ${phase} whole tree differs from its expectation`);
        }
        assert.deepEqual(item.finalTree, item.expectedSnapshots.redone,
          `${id} final tree differs from the redone expectation`);
        validUndoRedoRow(item, evidence, expected, {
          kind: "undo-redo",
          subject: id,
          documentId: item.documentId,
        }, id);
        for (const reference of item.artifacts) {
          const raw = evidence.get(reference).claim.raw;
          validateUndoRedoScenarioArtifact(item, raw, id);
        }
      }
    }
  }

  assert(Array.isArray(report.undoRedoReconnect)
    && report.undoRedoReconnect.length === nativeTargets.length,
  "Undo/redo reconnect requires every native implementation");
  for (const implementation of nativeTargets) {
    const item = report.undoRedoReconnect.find(
      (candidate) => candidate.implementation === implementation,
    );
    assert(item, `Undo/redo reconnect lacks ${implementation}`);
    assert.equal(item.liveHandleBeforeDisconnect, "Valid",
      `${implementation} handle was not live before disconnect`);
    assert.equal(item.liveHandleAfterReconnect, "Valid",
      `${implementation} handle did not survive reconnect`);
    assert.equal(item.postUndoHandleStatus, "Disposed",
      `${implementation} reconnect handle stayed valid after undo`);
    assert.equal(item.undoKind, "Undo",
      `${implementation} reconnect authored another commit kind`);
    assert.equal(item.settlement, "FullyApplied",
      `${implementation} reconnect lacks settlement observation`);
    assert.equal(item.outboundCount, 1,
      `${implementation} reconnect submitted another operation count`);
    assert.equal(item.authoredCount, 1,
      `${implementation} reconnect authored another commit count`);
    assert.deepEqual(item.finalTree, item.expectedTree,
      `${implementation} reconnect restored another tree`);
    validUndoRedoRow(item, evidence, expected, {
      kind: "undo-redo-reconnect",
      subject: item.id,
      documentId: item.documentId,
    }, `${implementation} reconnect`);
    for (const reference of item.artifacts) {
      const raw = evidence.get(reference).claim.raw;
      assert(Array.isArray(raw.eventTrace) && raw.eventTrace.length > 0,
        `${implementation} reconnect lacks raw events`);
      const observation = raw.checkpoint?.observations?.find(
        (candidate) => candidate.implementation === implementation,
      );
      assert(observation,
        `${implementation} reconnect lacks its raw checkpoint observation`);
      assert.deepEqual(observation.wholeTree, item.finalTree,
        `${implementation} reconnect differs from raw checkpoint`);
      const reconnect = object(raw.reconnectLifecycle,
        `${implementation} reconnect lacks raw lifecycle observations`);
      assert.deepEqual(reconnect.beforeDisconnect, raw.retained,
        `${implementation} reconnect retained evidence changed`);
      assert.equal(reconnect.beforeDisconnect.factoryAvailable, true,
        `${implementation} reconnect retained no local factory`);
      assert.equal(reconnect.beforeDisconnect.status,
        item.liveHandleBeforeDisconnect,
      `${implementation} reconnect pre-disconnect status changed`);
      assert.equal(reconnect.afterReconnect.status,
        item.liveHandleAfterReconnect,
      `${implementation} reconnect post-reconnect status changed`);
      assert.equal(reconnect.postUndo.status, item.postUndoHandleStatus,
        `${implementation} reconnect post-undo status changed`);
      assert(raw.eventTrace.filter(
        ({ type, local }) => type === "commit" && local === true,
      ).every(({ factoryAvailable }) => factoryAvailable === true),
      `${implementation} reconnect removed a local event factory`);
      validateRetainedAction(
        raw,
        raw.retained,
        "Default",
        raw.eventTrace,
        `${implementation} reconnect retained edit`,
      );
      validateSequencedAction(
        raw,
        raw.lifecycle,
        "Undo",
        `${implementation} reconnect undo`,
      );
      assert.deepEqual(raw.handleNames, ["edit"],
        `${implementation} reconnect names another handle`);
    }
  }

  const reload = object(report.undoRedoReloadMatrix,
    "Undo/redo reload matrix must be an object");
  for (const writer of implementations) {
    const row = object(reload[writer],
      `Undo/redo reload matrix lacks writer ${writer}`);
    for (const stage of ["undo", "redo"]) {
      const summaries = object(row[stage],
        `Undo/redo reload matrix lacks ${writer} ${stage}`);
      assert.deepEqual(Object.keys(summaries).sort(), [...implementations].sort(),
        `Undo/redo reload matrix lacks a reader cell for ${writer} ${stage}`);
      for (const reader of implementations) {
        const item = summaries[reader];
        assert.equal(item.writer, writer, "Undo/redo reload writer changed");
        assert.equal(item.reader, reader, "Undo/redo reload reader changed");
        assert.equal(item.stage, stage, "Undo/redo reload stage changed");
        assert.equal(item.loaded, true, "Undo/redo reload did not load");
        assert.deepEqual(item.loadedTree, item.expectedPublishedTree,
          "Undo/redo reload loaded another published tree");
        assert.deepEqual(item.finalTree, item.expectedPublishedTree,
          "Undo/redo reload restored another final tree");
        assert.equal(item.historicalHandleAvailable, false,
          "Undo/redo reload recreated a historical handle");
        assert.match(item.historicalRetainError,
          /No unretained local commit is available/,
        "Undo/redo reload returned another historical retain error");
        assert(Array.isArray(item.historicalLoadCommits)
          && item.historicalLoadCommits.every(
            ({ type, local, factoryAvailable }) =>
              type !== "commit" || (local !== true && factoryAvailable !== true),
          ),
        "Undo/redo reload observed a historical local commit or factory");
        assert.equal(item.loadedVersion, item.writerVersion,
          "Undo/redo reload selected another writer version");
        assert(Number.isSafeInteger(item.snapshotSequenceNumber)
          && item.snapshotSequenceNumber >= 0
          && item.publicationReferenceSequenceNumber
            === item.snapshotSequenceNumber
          && item.consumedSnapshotSequenceNumber
            === item.snapshotSequenceNumber
          && Number.isSafeInteger(item.replayStartSequenceNumber)
          && item.replayStartSequenceNumber >= item.snapshotSequenceNumber,
        "Undo/redo reload lacks exact snapshot replay evidence");
        assert(Array.isArray(item.selectedSummaryRequests)
          && item.selectedSummaryRequests.includes(item.writerVersion),
        "Undo/redo reload did not request the published writer version");
        const load = object(item.loadEvidence,
          "Undo/redo reload lacks storage load evidence");
        assert.equal(load.loadedVersion, item.writerVersion,
          "Undo/redo reload load evidence names another version");
        assert.equal(load.snapshotSequenceNumber,
          item.consumedSnapshotSequenceNumber,
        "Undo/redo reload load response names another snapshot sequence");
        const rawLoadIdentity = object(load.rawLoadIdentity,
          "Undo/redo reload lacks raw reader load identity");
        assert.equal(rawLoadIdentity.loadedVersion, item.writerVersion,
          "Undo/redo reload raw reader identity names another version");
        assert.equal(rawLoadIdentity.snapshotSequenceNumber,
          item.snapshotSequenceNumber,
        "Undo/redo reload raw reader identity names another snapshot sequence");
        assert.equal(load.replayStartSequenceNumber,
          item.replayStartSequenceNumber,
        "Undo/redo reload load evidence names another sequence");
        assert.deepEqual(load.selectedSummaryRequests,
          item.selectedSummaryRequests,
        "Undo/redo reload selected-summary evidence changed");
        assert.equal(item.newLocalKind, "Default",
          "Undo/redo reload authored another local kind");
        assert.equal(item.newFactoryAvailable, true,
          "Undo/redo reload lacked a new local factory");
        assert.equal(item.undoKind, "Undo",
          "Undo/redo reload did not undo the new local commit");
        assert.equal(item.settlement, "FullyApplied",
          "Undo/redo reload lacks settlement observation");
        assert.equal(item.outboundCount, 1,
          "Undo/redo reload submitted another operation count");
        assert.equal(item.authoredCount, 1,
          "Undo/redo reload authored another commit count");
        assert.equal(item.newHandleStatus, "Valid",
          "Undo/redo reload created another handle status");
        assert.equal(item.postUndoHandleStatus, "Disposed",
          "Undo/redo reload handle stayed valid after undo");
        object(item.finalTree, "Undo/redo reload lacks a final tree");
        validUndoRedoRow(item, evidence, expected, {
          kind: "undo-redo-reload",
          subject: `${writer}:${stage}->${reader}`,
          documentId: item.documentId,
        }, `Undo/redo reload ${writer}:${stage}->${reader}`);
        for (const reference of item.artifacts) {
          const raw = evidence.get(reference).claim.raw;
          assert.equal(raw.publication?.version, item.writerVersion,
            "Undo/redo reload raw publication names another version");
          assert.equal(raw.publication?.snapshotSequenceNumber,
            item.snapshotSequenceNumber,
          "Undo/redo reload publication sequence changed");
          assert.equal(raw.publication?.referenceSequenceNumber,
            item.snapshotSequenceNumber,
          "Undo/redo reload publication boundary changed");
          assert.deepEqual(raw.publication?.checkpoint?.wholeTree,
            item.expectedPublishedTree,
          "Undo/redo reload expected tree differs from the published checkpoint");
          assert.deepEqual(raw.loaded?.wholeTree,
            raw.publication?.checkpoint?.wholeTree,
          "Undo/redo reload loaded tree differs from the published checkpoint");
          assert.deepEqual(raw.final?.wholeTree,
            raw.publication?.checkpoint?.wholeTree,
          "Undo/redo reload final tree differs from the published checkpoint");
          assert.deepEqual(raw.load, item.loadEvidence,
            "Undo/redo reload raw load evidence changed");
          assert.deepEqual(raw.loaded?.rawLoadIdentity,
            item.loadEvidence.rawLoadIdentity,
          "Undo/redo reload raw reader identity changed");
          assert.deepEqual(raw.loaded?.wholeTree, item.loadedTree,
            "Undo/redo reload loaded tree differs from raw checkpoint");
          assert.deepEqual(raw.loaded?.commits, item.historicalLoadCommits,
            "Undo/redo reload raw historical commits changed");
          assert.deepEqual(raw.final?.wholeTree, item.finalTree,
            "Undo/redo reload final tree differs from raw checkpoint");
          assert(Array.isArray(raw.boundaryStorageResponses),
            "Undo/redo reload lacks raw boundary storage responses");
          const boundaryLoad = reader === "upstream"
            ? storageLoad(raw.boundaryStorageResponses, item.writerVersion)
            : nativeStorageLoad(
                raw.boundaryStorageResponses,
                item.writerVersion,
              );
          assert.deepEqual(boundaryLoad.rawLoadIdentity,
            item.loadEvidence.rawLoadIdentity,
          "Undo/redo reload copied identity differs from the storage response");
          assert.deepEqual(boundaryLoad.selectedSummaryRequests,
            item.loadEvidence.selectedSummaryRequests,
          "Undo/redo reload copied version differs from the storage response");
          assert.equal(boundaryLoad.snapshotSequenceNumber,
            item.snapshotSequenceNumber,
          "Undo/redo reload storage response names another snapshot");
          if (reader === "upstream") {
            assert.equal(boundaryLoad.replayStartSequenceNumber,
              item.replayStartSequenceNumber,
            "Undo/redo reload storage replay boundary changed");
          }
          if (reader === "upstream") {
            assert.equal(rawLoadIdentity.treeId,
              item.loadEvidence.selectedSummaryTreeId,
            "Undo/redo reload upstream identity names another tree");
            assert(item.loadEvidence.selectedTreeRequests.includes(
              rawLoadIdentity.treeId),
            "Undo/redo reload upstream reader did not request its tree");
            const blob = item.loadEvidence.selectedBlobRequests.find(
              ({ id }) => id === rawLoadIdentity.blobId);
            assert(blob,
              "Undo/redo reload upstream reader lacks its attributes blob");
            assert.equal(blob.hash, rawLoadIdentity.blobHash,
              "Undo/redo reload upstream blob response hash changed");
            assert.equal(blob.snapshotSequenceNumber,
              item.snapshotSequenceNumber,
            "Undo/redo reload upstream blob names another snapshot");
          } else {
            const storage = object(raw.storageResponses,
              "Undo/redo reload lacks selected storage responses");
            const commit = object(storage.commit,
              "Undo/redo reload lacks its selected commit response");
            assert.equal(commit.kind, "commit",
              "Undo/redo reload selected commit has another kind");
            assert.equal(commit.requestedId, item.writerVersion,
              "Undo/redo reload selected commit has another version");
            assert.equal(rawLoadIdentity.commitId, commit.requestedId,
              "Undo/redo reload raw identity names another commit");
            const trees = storage.trees;
            assert(Array.isArray(trees) && trees.length > 0,
              "Undo/redo reload lacks selected tree responses");
            const root = trees.find(
              ({ requestedId }) => requestedId === commit.treeId);
            assert(root, "Undo/redo reload lacks its selected root tree");
            let protocolEntry = root.entries?.find(
              ({ path, type }) => path === ".protocol" && type === "tree");
            if (protocolEntry === undefined) {
              const appEntry = root.entries?.find(
                ({ path, type }) => path === ".app" && type === "tree");
              assert(appEntry,
                "Undo/redo reload root tree lacks .app or .protocol");
              const app = trees.find(
                ({ requestedId }) => requestedId === appEntry.id);
              assert(app, "Undo/redo reload lacks its selected .app tree");
              protocolEntry = app.entries?.find(
                ({ path, type }) => path === ".protocol" && type === "tree");
            }
            assert(protocolEntry,
              "Undo/redo reload root tree lacks .protocol");
            const protocol = trees.find(
              ({ requestedId }) => requestedId === protocolEntry.id);
            assert(protocol,
              "Undo/redo reload lacks its selected protocol tree");
            assert.equal(rawLoadIdentity.rootTreeId, root.requestedId,
              "Undo/redo reload raw identity names another root tree");
            assert.equal(rawLoadIdentity.protocolTreeId, protocol.requestedId,
              "Undo/redo reload raw identity names another protocol tree");
            const attributes = protocol.entries?.find(
              ({ path, type }) => path === "attributes" && type === "blob");
            assert(attributes,
              "Undo/redo reload protocol tree lacks attributes");
            const blob = object(storage.blob,
              "Undo/redo reload lacks its selected attributes blob");
            assert.equal(blob.requestedId, attributes.id,
              "Undo/redo reload selected another attributes blob");
            assert.equal(rawLoadIdentity.blobId, blob.requestedId,
              "Undo/redo reload raw identity names another attributes blob");
            assert.equal(blob.snapshotSequenceNumber,
              item.snapshotSequenceNumber,
            "Undo/redo reload blob response names another snapshot");
            assert.equal(blob.responseHash,
              item.loadEvidence.rawLoadIdentity.responseHash,
            "Undo/redo reload blob response hash changed");
          }
          validateRetainedAction(
            raw,
            raw.retained,
            "Default",
            raw.final?.commits ?? [],
            `Undo/redo reload ${writer}:${stage}->${reader} retained edit`,
          );
          validateSequencedAction(
            raw,
            raw.lifecycle,
            "Undo",
            `Undo/redo reload ${writer}:${stage}->${reader}`,
          );
          assert.equal(raw.retained?.factoryAvailable, true,
            "Undo/redo reload retained no new local factory");
          assert.equal(raw.postUndoStatus?.status, item.postUndoHandleStatus,
            "Undo/redo reload post-undo status changed");
          assert.deepEqual(raw.handleNames, ["post-load"],
            "Undo/redo reload names another handle");
        }
      }
    }
  }
}

export function validateInteropReport(report, expected) {
  object(report, "Missing interoperability report");
  object(expected, "Missing report expectations");
  assert.equal(expected.mode, "acceptance",
    "Replay mode cannot satisfy the acceptance gate");
  assert(Number.isSafeInteger(expected.iterations) && expected.iterations >= 300,
    "Acceptance requires at least 300 schedules");
  assert(Number.isSafeInteger(expected.seed)
    && expected.seed >= 0 && expected.seed <= 0xffff_ffff,
  "Expected seed is outside the supported range");
  pinnedProfile(expected.profile);
  const evidence = artifactEvidence(expected);
  assert.equal(report.formatVersion, 1, "Unsupported report format");
  assert.equal(report.runId, expected.runId, "Report belongs to another run");
  assert.equal(report.profileDigest, expected.profileDigest,
    "Report uses another profile");
  assert.deepEqual(report.profile, expected.profile, "Report profile changed");
  pinnedProfile(report.profile);
  assert.deepEqual(report.reference, reference, "Report reference changed");
  assert.equal(report.service?.implementation, service.implementation,
    "Report used another service");
  assert.equal(report.service?.revision, service.revision,
    "Report used another service revision");
  assert.equal(report.service?.runId, expected.runId,
    "Service evidence belongs to another run");
  assert.equal(report.service?.profileDigest, expected.profileDigest,
    "Service evidence uses another profile");
  assert(evidence.has(report.service?.preflightArtifact),
    "Service lacks verified preflight evidence");
  const preflight = evidence.get(report.service.preflightArtifact).claim;
  assert.equal(preflight.runId, expected.runId,
    "Service artifact belongs to another run");
  assert.equal(preflight.profileDigest, expected.profileDigest,
    "Service artifact uses another profile");
  assert.equal(preflight.kind, "service-preflight",
    "Service artifact has another kind");
  assert.equal(preflight.subject, "service",
    "Service artifact describes another subject");
  assert.equal(preflight.documentId, null,
    "Service artifact is scoped to a document");
  assert.deepEqual(preflight.reference, reference,
    "Service artifact uses another reference");
  assert.deepEqual(preflight.service, service,
    "Service artifact uses another service");
  assert.equal(preflight.realService, true,
    "Service artifact does not prove a real service");
  assert.equal(report.realService, true, "Report did not use the real service");
  assert.equal(report.mode, expected.mode, "Report used another execution mode");
  assert.equal(report.seed, expected.seed, "Report used another seed");
  assert.equal(report.iterations, expected.iterations,
    "Report used another iteration count");
  assert.deepEqual(report.skipped, [], "Report contains skipped work");
  assert.deepEqual(report.divergences, [], "Report contains divergences");
  validateSchemaSections(report, expected, evidence);
  validateIdentifierSections(report, expected, evidence);
  validateTransactionSections(report, expected, evidence);
  validateUndoRedoSections(report, evidence, expected);

  const requiredScenarios = requiredScenarioCells();
  const scenariosById = exactCells(
    report.deterministic,
    requiredScenarios,
    "Deterministic results",
  );
  for (const item of report.deterministic) {
    const cell = scenariosById.get(item.id);
    assert.equal(item.profile, cell.profile, "Deterministic profile changed");
    assert.equal(item.family, cell.family, "Deterministic family changed");
    assert.deepEqual(item.authors, cell.authors, "Deterministic authors changed");
    assert.equal(item.order, cell.order, "Deterministic order changed");
    assert.equal(item.variation, cell.variation, "Deterministic variation changed");
    measured(item, expected, cell.authors, evidence, `Deterministic ${item.id}`);
  }

  validateReconnectResults(report.reconnect, expected.runId);
  for (const item of report.reconnect) {
    assert.equal(item.profileDigest, expected.profileDigest,
      "Reconnect result uses another profile");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      "Reconnect result lacks a document ID");
    artifacts(item.evidence, evidence, expected, {
      kind: "reconnect",
      subject: `${item.target}:${item.caseId}`,
      documentId: item.documentId,
    }, `Reconnect ${item.target}:${item.caseId}`);
  }
  validateFailures(report, expected, evidence);

  assert(Array.isArray(report.seeded)
    && report.seeded.length === expected.iterations,
  "Seeded results have incomplete coverage");
  assert.deepEqual(report.seededAccounting, {
    requested: expected.iterations,
    generated: expected.iterations,
    executed: expected.iterations,
    seed: expected.seed,
    profiles: Object.fromEntries(
      ["object", "map", "schema", "array", "identifier"].map((profile) => [
        profile,
        schedulesForProfile(expected.iterations, profile),
      ]),
    ),
  }, "Seeded producer accounting is incomplete");
  const schedules = generateSchedules({
    seed: expected.seed,
    iterations: expected.iterations,
  });
  const seededIndexes = new Set();
  const lifecycleCoverage = new Set();
  for (const item of report.seeded) {
    assert(Number.isSafeInteger(item.index)
      && item.index >= 0 && item.index < expected.iterations,
    "Seeded result has an invalid index");
    assert(!seededIndexes.has(item.index), "Seeded result repeats an index");
    seededIndexes.add(item.index);
    assert.equal(item.seed, expected.seed, "Seeded result uses another seed");
    const schedule = schedules[item.index];
    assert.equal(item.subSeed, schedule.subSeed, "Seeded sub-seed changed");
    assert.equal(item.template, schedule.template, "Seeded template changed");
    assert.equal(item.profile, schedule.profile, "Seeded profile changed");
    assert.deepEqual(item.roles, schedule.roles, "Seeded roles changed");
    assert.deepEqual(item.actions, schedule.actions, "Seeded actions changed");
    const retainIndex = item.actions.findIndex(
      ({ type, lifecycle }) => type === "retain" && lifecycle === "edit",
    );
    const undoIndex = item.actions.findIndex(
      ({ type, lifecycle }) => type === "revert" && lifecycle === "undo",
    );
    const redoIndex = item.actions.findIndex(
      ({ type, lifecycle }) => type === "revert" && lifecycle === "redo",
    );
    const disposeIndex = item.actions.findIndex(
      ({ type }) => type === "dispose",
    );
    assert(retainIndex >= 0 && undoIndex > retainIndex
      && redoIndex > undoIndex && disposeIndex > redoIndex,
    `Seeded ${item.index} lacks an ordered retained lifetime`);
    for (const action of item.actions.slice(retainIndex + 1, undoIndex)) {
      lifecycleCoverage.add(action.type);
    }
    validateSeededTransactions(item, schedule);
    measured(item, expected, implementations, evidence, `Seeded ${item.index}`);
  }
  assert.deepEqual([...seededIndexes].sort((a, b) => a - b),
    Array.from({ length: expected.iterations }, (_, index) => index),
  "Seeded results omit an index");
  for (const type of [
    "set",
    "map-set",
    "array-insert",
    "release",
    "checkpoint",
    "transaction",
    "disconnect",
    "reconnect",
    "summarize",
    "reload",
  ]) {
    assert(lifecycleCoverage.has(type),
      `Seeded undo/redo lifetimes lack intervening ${type} coverage`);
  }

  validateReload(report, expected, evidence);
  validateMapReload(report, expected, evidence);
  validateArrayReload(report, expected, evidence);
  assert.deepEqual(Object.keys(report.corpus).sort(), [...nativeTargets].sort(),
    "Corpus evidence lacks a native target");
  for (const target of nativeTargets) {
    const item = object(report.corpus[target], `Missing ${target} corpus evidence`);
    assert.equal(item.target, target, "Corpus target changed");
    assert.equal(item.runId, expected.runId, "Corpus evidence belongs to another run");
    assert.equal(item.profileDigest, expected.profileDigest,
      "Corpus evidence uses another profile");
    assert.equal(item.passed, true, "Corpus evidence failed");
    assert.equal(item.skipped, false, "Corpus evidence was skipped");
    assert(Number.isSafeInteger(item.executedCount) && item.executedCount > 0,
      "Corpus evidence has no executed tests");
    artifacts(item, evidence, expected, {
      kind: "corpus",
      subject: target,
      documentId: null,
    }, `${target} corpus`);
    for (const reference of item.artifacts) {
      const claim = evidence.get(reference).claim;
      assert.deepEqual(claim.command, ["gleam", ...corpusCommand(target)],
        `${target} corpus used another command`);
      assert.equal(claim.exitCode, 0, `${target} corpus command failed`);
      assert.equal(claim.executedCount, item.executedCount,
        `${target} corpus count differs from its artifact`);
      assert(typeof claim.output === "string" && claim.output.length > 0,
        `${target} corpus artifact lacks command output`);
      assert.equal(parseTestCount(claim.output, target), item.executedCount,
        `${target} corpus output has another test count`);
    }
  }
  return report;
}
