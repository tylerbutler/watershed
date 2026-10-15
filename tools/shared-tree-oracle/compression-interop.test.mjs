import assert from "node:assert/strict";
import test from "node:test";

import {
  benchmarkFrameIds,
  median,
  validateBenchmarkReport,
} from "./compression-interop.mjs";

test("benchmarks the captured exact-size producer frames", () => {
  assert.deepEqual(benchmarkFrameIds, ["benchmark-1mib", "benchmark-4mib"]);
});

test("uses the middle of seven ordered measurements", () => {
  assert.equal(median([9, 7, 3, 5, 1, 11, 13]), 7);
});

test("requires validated output and linear-enough target scaling", () => {
  const report = {
    targets: {
      javascript: {
        "benchmark-1mib": { samplesMicroseconds: [1, 2, 3, 4, 5, 6, 7], medianMicroseconds: 4, outputMatches: true },
        "benchmark-4mib": { samplesMicroseconds: [8, 9, 10, 11, 12, 13, 14], medianMicroseconds: 11, outputMatches: true },
        ratio4MiBTo1MiB: 2.75,
      },
      erlang: {
        "benchmark-1mib": { samplesMicroseconds: [2, 3, 4, 5, 6, 7, 8], medianMicroseconds: 5, outputMatches: true },
        "benchmark-4mib": { samplesMicroseconds: [12, 13, 14, 15, 16, 17, 18], medianMicroseconds: 15, outputMatches: true },
        ratio4MiBTo1MiB: 3,
      },
    },
  };
  assert.equal(validateBenchmarkReport(report), report);

  const quadratic = structuredClone(report);
  quadratic.targets.javascript.ratio4MiBTo1MiB = 8.01;
  assert.throws(() => validateBenchmarkReport(quadratic), /javascript.*ratio/i);

  const wrongOutput = structuredClone(report);
  wrongOutput.targets.erlang["benchmark-4mib"].outputMatches = false;
  assert.throws(() => validateBenchmarkReport(wrongOutput), /erlang.*output/i);
});
