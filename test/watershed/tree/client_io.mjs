import { readFileSync } from "node:fs";
import { createInterface } from "node:readline";

export function descriptor() {
  if (!process.env.WATERSHED_DESCRIPTOR) throw new Error("Missing WATERSHED_DESCRIPTOR");
  return readFileSync(process.env.WATERSHED_DESCRIPTOR, "utf8");
}

export function token() {
  if (!process.env.WATERSHED_TOKEN) throw new Error("Missing WATERSHED_TOKEN");
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
  console.error(message);
  process.exitCode = 1;
}
