import assert from "node:assert/strict";
import crypto from "node:crypto";
import { syncBuiltinESMExports } from "node:module";
import { performance } from "node:perf_hooks";
import { mock } from "node:test";

assert.equal(process.env.WATERSHED_ORACLE_DETERMINISTIC, "1",
  "Deterministic entropy is restricted to the isolated development oracle");

let counter = 0;
function bytes(size) {
  const output = Buffer.alloc(size);
  for (let offset = 0; offset < size; offset += 32) {
    crypto.createHash("sha256").update(`watershed-tree-corpus-v1:${counter++}`)
      .digest().copy(output, offset, 0, Math.min(32, size - offset));
  }
  return output;
}

function fill(buffer, offset = 0, size = buffer.byteLength - offset) {
  const target = ArrayBuffer.isView(buffer)
    ? Buffer.from(buffer.buffer, buffer.byteOffset, buffer.byteLength)
    : Buffer.from(buffer);
  assert(Number.isSafeInteger(offset) && offset >= 0);
  assert(Number.isSafeInteger(size) && size >= 0 && offset + size <= target.length);
  bytes(size).copy(target, offset);
  return buffer;
}

function uuid() {
  const value = bytes(16);
  value[6] = (value[6] & 0x0f) | 0x40;
  value[8] = (value[8] & 0x3f) | 0x80;
  const hex = value.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

crypto.randomUUID = uuid;
crypto.randomFillSync = fill;
crypto.randomBytes = (size, callback) => {
  const value = bytes(size);
  if (callback === undefined) return value;
  queueMicrotask(() => callback(null, value));
};
Object.defineProperty(crypto.webcrypto, "randomUUID", { value: uuid });
Object.defineProperty(crypto.webcrypto, "getRandomValues", {
  value: (array) => {
    assert(ArrayBuffer.isView(array) && array.byteLength <= 65_536);
    return fill(array);
  },
});
Math.random = () => bytes(4).readUInt32LE() / 0x1_0000_0000;
syncBuiltinESMExports();
mock.timers.enable({ apis: ["Date"], now: 1_700_000_000_000 });

export function freezePerformanceClock() {
  // Upstream benchmark imports calibrate this clock; freeze it only after imports complete.
  Object.defineProperty(performance, "now", { value: () => 0, configurable: true });
}
