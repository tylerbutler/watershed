import { setTimeout as sleep } from "node:timers/promises";

export async function bounded(label, action, timeoutMs = 5000) {
  const deadline = performance.now() + timeoutMs;
  let timer;
  try {
    const value = await Promise.race([
      Promise.resolve().then(action),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} timed out`)), timeoutMs);
      }),
    ]);
    if (performance.now() >= deadline) throw new Error(`${label} timed out (late result)`);
    return value;
  } finally {
    clearTimeout(timer);
  }
}

export async function wait(label, probe, predicate, timeoutMs = 20_000) {
  const deadline = performance.now() + timeoutMs;
  let last;
  while (performance.now() < deadline) {
    last = await bounded(label, probe, Math.min(5000, deadline - performance.now()));
    if (performance.now() < deadline && predicate(last)) return last;
    await sleep(Math.min(50, Math.max(0, deadline - performance.now())));
  }
  throw new Error(`${label} timed out; last=${JSON.stringify(last)}`);
}
