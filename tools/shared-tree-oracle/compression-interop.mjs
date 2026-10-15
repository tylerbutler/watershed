import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readdirSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const benchmarkFrameIds = ["benchmark-1mib", "benchmark-4mib"];

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const fixturePath = resolve(repository, "test/fixtures/shared_tree/compression.json");
const outputDirectory = resolve(directory, ".output/compression");
const reportPath = resolve(outputDirectory, "benchmark.json");
const inputsDirectory = resolve(outputDirectory, "benchmark-inputs");
const warmupCount = 2;
const timedCount = 7;
const maxRatio = 8;
const maxOutputBytes = 16 * 1024 * 1024;
const spillwayRevision = "25f515cf67027e4b2db2344c3abb2141056e45fc";
const floodgateRevision = "0eb493fc46d1bb9baf1151a6ccdde93544e057e7";
const legacyProfileSha256 =
  "29fe106785ec1705cd1ac4d45de8e88f9a6cc89487c3b7cd1df6ad65b318b1de";

function fail(message) {
  throw new Error(message);
}

export function median(samples) {
  if (samples.length === 0) fail("median requires samples");
  const ordered = samples.slice().sort((left, right) => left - right);
  return ordered[Math.floor(ordered.length / 2)];
}

export function validateBenchmarkReport(report) {
  for (const [target, measurements] of Object.entries(report.targets ?? {})) {
    for (const id of benchmarkFrameIds) {
      const measurement = measurements[id];
      if (!measurement || measurement.samplesMicroseconds?.length !== timedCount) {
        fail(`${target} ${id} must contain seven timed samples`);
      }
      if (measurement.outputMatches !== true) {
        fail(`${target} ${id} output did not match the captured producer bytes`);
      }
      if (measurement.medianMicroseconds !== median(measurement.samplesMicroseconds)) {
        fail(`${target} ${id} median does not match its samples`);
      }
    }
    const expectedRatio =
      measurements["benchmark-4mib"].medianMicroseconds /
      measurements["benchmark-1mib"].medianMicroseconds;
    if (Math.abs(measurements.ratio4MiBTo1MiB - expectedRatio) > 1e-12) {
      fail(`${target} ratio does not match its medians`);
    }
    if (measurements.ratio4MiBTo1MiB > maxRatio) {
      fail(`${target} ratio exceeds ${maxRatio}`);
    }
  }
  for (const target of ["javascript", "erlang"]) {
    if (!report.targets?.[target]) fail(`missing ${target} benchmark`);
  }
  return report;
}

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function selectedFrames(capture) {
  return benchmarkFrameIds.map((id) => {
    const entry = capture.frames.find((frame) => frame.id === id);
    if (!entry) fail(`missing captured frame ${id}`);
    const compressed = Buffer.from(entry.compressedBase64, "base64");
    const decoded = Buffer.from(entry.decodedBase64, "base64");
    if (decoded.length !== entry.measurements.decodedBytes) {
      fail(`${id} decoded size does not match capture metadata`);
    }
    return { id, entry, compressed, decoded };
  });
}

async function javascriptMeasurements(frames) {
  const [{ BitArray }, lz4] = await Promise.all([
    import(pathToFileURL(resolve(repository, "build/dev/javascript/prelude.mjs"))),
    import(pathToFileURL(resolve(
      repository,
      "build/dev/javascript/watershed/watershed/wire/lz4.mjs",
    ))),
  ]);
  const measurements = {};
  for (const frame of frames) {
    const input = new BitArray(new Uint8Array(frame.compressed));
    const decode = () => {
      const decoded = lz4.decompress(input, maxOutputBytes);
      if (decoded.constructor.name !== "Ok") fail(`javascript refused ${frame.id}`);
      return Buffer.from(decoded[0].rawBuffer);
    };
    for (let index = 0; index < warmupCount; index += 1) {
      if (!decode().equals(frame.decoded)) fail(`javascript warmup output differs for ${frame.id}`);
    }
    const samplesMicroseconds = [];
    for (let index = 0; index < timedCount; index += 1) {
      const started = performance.now();
      const output = decode();
      samplesMicroseconds.push((performance.now() - started) * 1000);
      if (!output.equals(frame.decoded)) fail(`javascript output differs for ${frame.id}`);
    }
    measurements[frame.id] = {
      decodedBytes: frame.decoded.length,
      compressedBytes: frame.compressed.length,
      warmups: warmupCount,
      samplesMicroseconds,
      medianMicroseconds: median(samplesMicroseconds),
      outputMatches: true,
    };
  }
  measurements.ratio4MiBTo1MiB =
    measurements["benchmark-4mib"].medianMicroseconds /
    measurements["benchmark-1mib"].medianMicroseconds;
  return measurements;
}

function erlangSamples(compressedPath, decodedPath) {
  const erlangBuild = resolve(repository, "build/dev/erlang");
  const codePaths = readdirSync(erlangBuild, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .flatMap((entry) => ["-pa", resolve(erlangBuild, entry.name, "ebin")]);
  const quote = (value) => value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
  const expression = `
    {ok, Frame} = file:read_file("${quote(compressedPath)}"),
    {ok, Expected} = file:read_file("${quote(decodedPath)}"),
    Decode = fun() -> 'watershed@wire@lz4':decompress(Frame, ${maxOutputBytes}) end,
    lists:foreach(fun(_) -> {ok, Expected} = Decode() end, lists:seq(1, ${warmupCount})),
    Samples = lists:map(fun(_) ->
      {Micros, {ok, Output}} = timer:tc(Decode),
      true = (Output =:= Expected),
      Micros
    end, lists:seq(1, ${timedCount})),
    io:format("~p~n", [Samples]),
    halt().
  `;
  const output = execFileSync("erl", [
    ...codePaths, "-noshell", "-eval", expression,
  ], { cwd: repository, encoding: "utf8", maxBuffer: 1024 * 1024 });
  return output.trim().slice(1, -1).split(",").map(Number);
}

async function erlangMeasurements(frames) {
  const measurements = {};
  await mkdir(inputsDirectory, { recursive: true });
  try {
    for (const frame of frames) {
      const compressedPath = resolve(inputsDirectory, `${frame.id}.lz4`);
      const decodedPath = resolve(inputsDirectory, `${frame.id}.decoded`);
      await Promise.all([
        writeFile(compressedPath, frame.compressed),
        writeFile(decodedPath, frame.decoded),
      ]);
      const samplesMicroseconds = erlangSamples(compressedPath, decodedPath);
      measurements[frame.id] = {
        decodedBytes: frame.decoded.length,
        compressedBytes: frame.compressed.length,
        warmups: warmupCount,
        samplesMicroseconds,
        medianMicroseconds: median(samplesMicroseconds),
        outputMatches: true,
      };
    }
  } finally {
    await rm(inputsDirectory, { recursive: true, force: true });
  }
  measurements.ratio4MiBTo1MiB =
    measurements["benchmark-4mib"].medianMicroseconds /
    measurements["benchmark-1mib"].medianMicroseconds;
  return measurements;
}

export async function runBenchmark() {
  const capture = JSON.parse(await readFile(fixturePath, "utf8"));
  const frames = selectedFrames(capture);
  execFileSync("gleam", ["build", "--target", "javascript"], {
    cwd: repository,
    stdio: "inherit",
  });
  const javascript = await javascriptMeasurements(frames);
  execFileSync("gleam", ["build", "--target", "erlang"], {
    cwd: repository,
    stdio: "inherit",
  });
  const erlang = await erlangMeasurements(frames);
  const report = validateBenchmarkReport({
    formatVersion: 1,
    generatedAt: new Date().toISOString(),
    identity: {
      fluid: capture.upstream,
      probe: {
        path: capture.probe.path,
        sha256: capture.probe.digest,
        treePath: capture.probe.treePath,
        treeSha256: capture.probe.treeDigest,
      },
      spillwayRevision,
      floodgateRevision,
      legacyProfileSha256,
      frames: Object.fromEntries(frames.map((frame) => [frame.id, {
        compressedBytes: frame.compressed.length,
        compressedSha256: sha256(frame.compressed),
        decodedBytes: frame.decoded.length,
        decodedSha256: sha256(frame.decoded),
      }])),
    },
    protocol: {
      warmupsPerTargetAndSize: warmupCount,
      timedRunsPerTargetAndSize: timedCount,
      maximumRatio4MiBTo1MiB: maxRatio,
      processStartupExcluded: true,
    },
    targets: { javascript, erlang },
  });
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

async function main() {
  if (process.argv[2] !== "benchmark" || process.argv.length !== 3) {
    fail("usage: node compression-interop.mjs benchmark");
  }
  const report = await runBenchmark();
  console.log(JSON.stringify({
    report: reportPath,
    javascript: report.targets.javascript.ratio4MiBTo1MiB,
    erlang: report.targets.erlang.ratio4MiBTo1MiB,
  }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
