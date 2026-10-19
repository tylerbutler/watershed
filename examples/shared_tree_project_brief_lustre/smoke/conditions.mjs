import { sleep } from "../../../smoke/cdp.mjs";

export async function bounded(label, action, timeout = 5000) {
  const deadline = performance.now() + timeout;
  let timer;
  try {
    const result = await Promise.race([
      Promise.resolve().then(action),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeout}ms`)), timeout);
      }),
    ]);
    if (performance.now() >= deadline) throw new Error(`${label} timed out after ${timeout}ms (late result)`);
    return result;
  } finally { clearTimeout(timer); }
}

export async function wait(label, probe, predicate, timeout = 20_000) {
  const deadline = performance.now() + timeout;
  let last;
  try {
    while (performance.now() < deadline) {
      last = await bounded(`${label}: probe`, probe, Math.min(5000, deadline - performance.now()));
      if (performance.now() >= deadline) break;
      if (predicate(last)) return last;
      await sleep(Math.min(50, Math.max(0, deadline - performance.now())));
    }
  } catch (error) {
    throw new Error(`${label}: ${error.message}; last=${JSON.stringify(last)}`, { cause: error });
  }
  throw new Error(`${label} timed out after ${timeout}ms: ${JSON.stringify(last)}`);
}
