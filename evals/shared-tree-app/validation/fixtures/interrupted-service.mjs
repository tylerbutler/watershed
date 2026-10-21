import assert from "node:assert/strict";
import { mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { startServices } from "../../lib/services.mjs";
import { wait } from "../../lib/conditions.mjs";

export async function interruptServiceDuringGrade({ sdk, baseline, work, grade }) {
  const root = join(work, "external-service");
  const health = join(root, "dist/index.html");
  await mkdir(join(root, "dist"), { recursive: true });
  await symlink(join(baseline, "node_modules"), join(root, "node_modules"));
  await writeFile(health, "Native service available\n");
  const external = await startServices({ sdk, root, stateRoot: work,
    runId: "validation-interrupted" });
  const previous = process.env.SHARED_TREE_SERVICE_URL;
  let grading;
  try {
    const origin = new URL(external.appUrl).origin;
    process.env.SHARED_TREE_SERVICE_URL = origin;
    grading = grade();
    await Promise.race([
      wait("real candidate document creation before interruption",
        async () => external.diagnostics().completedWrites, count => count > 0, 180_000),
      grading.then(() => { throw new Error("Grading finished before service interruption"); }),
    ]);
    // Mark the owned endpoint unhealthy before shutdown drops WebSockets.
    // Otherwise its static index can still return 200 during the grader's health probe.
    await rm(health);
    const status = (await fetch(origin, { signal: AbortSignal.timeout(3000) })).status;
    assert.ok(status >= 500, `Shutdown health must fail before transport closes; received HTTP ${status}`);
    await external.close();
    assert.equal(await external.health(), false, "The real native service must also be stopped");
    return await grading;
  } finally {
    if (previous === undefined) delete process.env.SHARED_TREE_SERVICE_URL;
    else process.env.SHARED_TREE_SERVICE_URL = previous;
    await external.close();
    await grading?.catch(() => {});
  }
}
