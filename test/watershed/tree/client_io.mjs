import { readFileSync } from "node:fs";
import { createInterface } from "node:readline";

function startup(code, operation, message) {
  process.stderr.write(`${JSON.stringify({
    kind: "startup-error",
    code,
    operation,
    message,
  })}\n`);
  process.exit(1);
}

export function descriptor() {
  if (!process.env.WATERSHED_DESCRIPTOR) {
    startup("descriptor-decode-failed", "descriptor", "Missing WATERSHED_DESCRIPTOR");
  }
  try {
    return readFileSync(process.env.WATERSHED_DESCRIPTOR, "utf8");
  } catch (error) {
    startup("descriptor-decode-failed", "descriptor", error.message);
  }
}

export function token() {
  if (!process.env.WATERSHED_TOKEN) {
    startup("bootstrap-failed", "connect", "Missing WATERSHED_TOKEN");
  }
  return process.env.WATERSHED_TOKEN;
}

export function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function lines(handle, finish) {
  try {
    for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
      const reply = await handle(line);
      process.stdout.write(`${reply}\n`);
    }
  } finally {
    finish();
  }
  await new Promise((resolve) => process.stdout.write("", resolve));
  process.exit(0);
}

export function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}
