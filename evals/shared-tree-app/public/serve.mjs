import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { startServices } from "../lib/services.mjs";

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const { values } = parseArgs({ options: {
      sdk: { type: "string" },
      root: { type: "string", default: process.cwd() },
    } });
    let stopping = false;
    let requestStop;
    const stopped = new Promise(resolve => { requestStop = resolve; });
    const stop = () => {
      if (!stopping) console.error("Shutdown requested; waiting for service startup and cleanup");
      stopping = true;
      requestStop();
    };
    process.on("SIGINT", stop);
    process.on("SIGTERM", stop);
    try {
      const services = await startServices({
        sdk: values.sdk, root: resolve(values.root), runId: "public-dev",
      });
      if (!stopping) console.log(services.appUrl);
      await stopped;
      await services.close();
    } finally {
      process.removeListener("SIGINT", stop);
      process.removeListener("SIGTERM", stop);
    }
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  }
}
