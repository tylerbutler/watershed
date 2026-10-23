import { chmod, mkdir, realpath, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { stringify } from "yaml";
import { execOwned } from "./process.mjs";

export function offlineSetupCommands(sdk) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown setup SDK");
  const directories = sdk === "watershed" ? ["node_modules", "build"] : ["node_modules"];
  // Archive copies preserve a task-private SELinux label that the grading role cannot read.
  const script = `import { cp } from "node:fs/promises"; for (const name of ${JSON.stringify(directories)}) ` +
    'await cp("/opt/shared-tree/baseline/" + name, name, { recursive: true, verbatimSymlinks: true });';
  return [`node --input-type=module -e ${JSON.stringify(script)}`];
}

export async function writeRoleCompose({ sdk, images, serviceImage, gradingOutput, out, runId,
  auth = "provider", wireApi = "completions" }) {
  if (!["provider", "copilot"].includes(auth)) throw new TypeError("auth must be provider or copilot");
  if (!["completions", "responses", "messages"].includes(wireApi) || (auth === "provider" && wireApi !== "completions")) {
    throw new TypeError("Unsupported authentication/protocol combination");
  }
  if (!["watershed", "fluid"].includes(sdk) || images?.sdk !== sdk || !gradingOutput || !out) {
    throw new TypeError("Compose requires matching SDK images, fresh grading output, and an output file");
  }
  for (const image of [images.task?.id, images.grade?.id, serviceImage]) {
    if (typeof image !== "string" || !/^sha256:[a-f0-9]{64}$/.test(image)) {
      throw new TypeError("Compose images must be immutable sha256 image IDs");
    }
  }
  if (runId !== undefined && !/^[a-z0-9][a-z0-9-]*$/.test(runId)) throw new TypeError("Invalid Compose run ID");
  const ownership = runId === undefined ? {} : { labels: { "com.watershed.shared-tree-eval.run": runId } };
  await mkdir(resolve(gradingOutput), { mode: 0o700 });
  const outputRoot = await realpath(gradingOutput);
  // Vally's non-root grade UID must write across the engine's host UID mapping.
  await chmod(outputRoot, 0o777);
  const hardened = { cap_drop: ["ALL"], security_opt: ["no-new-privileges:true"] };
  const health = test => ({ test, interval: "2s", timeout: "3s", retries: 30, start_period: "15s" });
  const nodeHealth = url => health(["CMD", "node", "-e",
    `fetch(${JSON.stringify(url)}, {signal: AbortSignal.timeout(2000)})` +
    ".then(r => process.exit(r.status < 500 ? 0 : 1)).catch(() => process.exit(1))"]);
  const service = sdk === "watershed" ? {
    tmpfs: ["/data:rw,mode=1777"],
    environment: {
      FLOODGATE_BIND: "0.0.0.0", FLOODGATE_STORAGE_BACKEND: "memory",
      FLOODGATE_PUBLIC_URL: "http://127.0.0.1:4173/api",
      FLOODGATE_TENANT_ID: "dev-tenant", FLOODGATE_JWT_SECRET: "levee-dev-secret-change-in-production",
      FLOODGATE_ALLOWED_ORIGINS: "*",
    },
    healthcheck: health(["CMD", "wget", "--no-verbose", "--tries=1", "--spider",
      "http://127.0.0.1:3000/health"]),
  } : {
    user: "1000:1000", working_dir: "/data",
    tmpfs: ["/data:rw,mode=1777"],
    command: ["sh", "-c", "mkdir -p /data/storage && exec node " +
      "/opt/shared-tree/baseline/node_modules/@fluidframework/azure-local-service/index.js"],
    environment: { PORT: "3000", storage: "/data/storage", db__path: "/data/db" },
    healthcheck: nodeHealth("http://127.0.0.1:3000"),
  };
  const roles = Object.fromEntries(["task", "grade"].map(role => [role, {
    image: images[role].id, profiles: [`vally-${role}`], ...ownership,
    networks: ["default"],
    environment: { SHARED_TREE_SERVICE_URL: "http://sdk-service:3000" },
    depends_on: { "sdk-service": { condition: "service_healthy" },
      ...(role === "task" ? { "provider-gateway": { condition: "service_healthy" } } : {}) },
    ...(role === "grade" ? {
      volumes: [{ type: "bind", source: outputRoot, target: "/eval-results" }],
    } : {}),
  }]));
  const compose = {
    services: {
      ...roles,
      "sdk-service": {
        ...hardened, ...ownership, image: serviceImage, profiles: ["vally-task", "vally-grade"],
        networks: ["default"], ...service,
      },
      "provider-gateway": {
        ...hardened, ...ownership, image: images.task.id, profiles: ["vally-task"],
        networks: ["default", "provider-outbound"],
        command: ["node", "/opt/shared-tree/docker/gateway.mjs"],
        environment: {
          SHARED_TREE_AUTH_MODE: auth,
          SHARED_TREE_WIRE_API: wireApi,
          SHARED_TREE_PROVIDER_URL: "${SHARED_TREE_PROVIDER_URL:?Provider URL is required}",
          SHARED_TREE_PROVIDER_API_KEY: "${SHARED_TREE_PROVIDER_API_KEY:?Provider key is required}",
          SHARED_TREE_PROVIDER_MODEL: "${SHARED_TREE_PROVIDER_MODEL:?Provider model is required}",
        },
        healthcheck: nodeHealth("http://127.0.0.1:8080/health"),
      },
    },
    networks: { default: { internal: true, ...ownership }, "provider-outbound": { ...ownership } },
  };
  await writeFile(resolve(out), stringify(compose), { flag: "wx", mode: 0o600 });
  return { composeFile: resolve(out), gradingOutput: outputRoot };
}

export async function cleanupVallyRun({ runId, env = process.env }) {
  if (typeof runId !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(runId)) throw new TypeError("Invalid cleanup run ID");
  const run = async args => (await execOwned("docker", args, {
    env, timeout: 30_000, maxBuffer: 1024 * 1024,
  })).stdout;
  const removed = [];
  const preserved = [];
  for (const kind of ["container", "network", "volume"]) {
    const labels = kind === "volume" ? ["com.microsoft.vally.run"]
      : ["com.watershed.shared-tree-eval.run", "com.microsoft.vally.run"];
    const resources = new Set();
    for (const label of labels) {
      const listed = await run([kind, "ls", ...(kind === "container" ? ["--all"] : []),
        "--quiet", "--filter", `label=${label}=${runId}`]);
      for (const id of listed.trim().split(/\s+/).filter(Boolean)) resources.add(id);
    }
    for (const id of resources) {
      const [resource] = JSON.parse(await run([kind, "inspect", id]));
      const inspected = kind === "container" ? resource?.Config?.Labels : resource?.Labels;
      if (!labels.some(label => inspected?.[label] === runId)) {
        throw new Error(`Refusing ${kind} cleanup: inspected ownership label does not match ${runId}`);
      }
      // Vally may retain the only copy of agent work after an export failure.
      if (kind === "volume") {
        preserved.push({ kind, id });
        continue;
      }
      await run([kind, "rm", ...(kind === "container" ? ["--force"] : []), id]);
      removed.push({ kind, id });
    }
  }
  return { removed, preserved };
}
