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
import { parseArgs, promisify, stripVTControlCharacters } from "node:util";
import {
  runService as runReconnectCases,
  validateResults as validateReconnectResults,
} from "./client-interop.mjs";
import {
  generateSchedules,
  loadReplayArtifact,
  replayFailure,
  requiredFailureCells,
  requiredScenarioCells,
  runDeterministicCases,
  runFailureCases,
  runSeededSchedules,
} from "./interop-scenarios.mjs";
import {
  preflight,
  excludedFeatures,
  serviceConfig,
  supportedFeatures,
  validatePreflight,
  withLocalFloodgate,
} from "./service.mjs";
import { runReloadMatrix } from "./summary-interop.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const nativeTargets = ["javascript", "erlang"];
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
  "a13390fcfcb551c142eee272db78b18fa899e9f2e7dc608e2ca71be06fee8fc2";
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
    iterations: unsignedInteger(values.iterations ?? "200", "--iterations", 200),
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

async function readViewSchema() {
  const fixture = JSON.parse(await readFile(join(
    repository,
    "test/fixtures/shared_tree/cases/schema-profile.json",
  ), "utf8"));
  assert.equal(fixture.reference.version, reference.version,
    "Pinned schema reference changed");
  const schema = fixture.input.summary.tree.indexes.tree.Schema.tree.SchemaString.content;
  assert.equal(JSON.parse(schema).root.kind, "Value",
    "Fixture is not the fixed root profile");
  return schema;
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

function artifactReferences(report) {
  return [
    report.service.preflightArtifact,
    ...report.deterministic.flatMap(({ artifacts }) => artifacts),
    ...report.reconnect.flatMap(({ evidence }) => evidence.artifacts),
    ...report.failures.flatMap(({ artifacts }) => artifacts),
    ...report.seeded.flatMap(({ artifacts }) => artifacts),
    ...Object.values(report.reload).flatMap((row) =>
      Object.values(row).flatMap(({ artifacts }) => artifacts)),
    ...Object.values(report.corpus).flatMap(({ artifacts }) => artifacts),
  ];
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

  await writeStatus(runDirectory, "reload");
  log("shared-tree interop: selected-summary reload matrix");
  const reload = await runReloadMatrix(config, context);

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
    seeded: seeded.results,
    reload,
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
  const context = {
    runId,
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    viewSchema: await readViewSchema(),
    artifactDirectory: runDirectory,
  };
  try {
    await prepareAcceptance(runDirectory, log);
    const corpus = await runCorpus(runDirectory, context, log);
    const run = (config) =>
      liveAcceptance(config, runDirectory, context, options, corpus, log);
    const report = options.externalFloodgate
      ? await run(serviceConfig(env))
      : await withLocalFloodgate(run);
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
  const context = {
    runId,
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    viewSchema: await readViewSchema(),
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

function exactImplementations(values, label) {
  assert.deepEqual([...values].sort(), [...implementations].sort(),
    `${label} must cover all three implementations`);
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

  if (item.order !== null) {
    const first = item.order.slice(0, -"-first".length);
    const ordered = [...evidence.submissions]
      .sort((left, right) => left.outerSequenceNumber - right.outerSequenceNumber);
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

export function validateInteropReport(report, expected) {
  object(report, "Missing interoperability report");
  object(expected, "Missing report expectations");
  assert.equal(expected.mode, "acceptance",
    "Replay mode cannot satisfy the acceptance gate");
  assert(Number.isSafeInteger(expected.iterations) && expected.iterations >= 200,
    "Acceptance requires at least 200 schedules");
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

  const requiredScenarios = requiredScenarioCells();
  const scenariosById = exactCells(
    report.deterministic,
    requiredScenarios,
    "Deterministic results",
  );
  for (const item of report.deterministic) {
    const cell = scenariosById.get(item.id);
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
  }, "Seeded producer accounting is incomplete");
  const schedules = generateSchedules({
    seed: expected.seed,
    iterations: expected.iterations,
  });
  const seededIndexes = new Set();
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
    assert.deepEqual(item.roles, schedule.roles, "Seeded roles changed");
    assert.deepEqual(item.actions, schedule.actions, "Seeded actions changed");
    measured(item, expected, implementations, evidence, `Seeded ${item.index}`);
  }
  assert.deepEqual([...seededIndexes].sort((a, b) => a - b),
    Array.from({ length: expected.iterations }, (_, index) => index),
  "Seeded results omit an index");

  validateReload(report, expected, evidence);
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
