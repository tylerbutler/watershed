import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { nodeTestFiles } from "./test-files.mjs";

const websiteRoot = fileURLToPath(new URL("..", import.meta.url));

const child = spawn(
  process.execPath,
  ["--strip-types", "--test", "--test-concurrency=1", ...nodeTestFiles],
  {
    cwd: websiteRoot,
    stdio: "inherit",
  },
);

child.once("error", (error) => {
  console.error(error);
  process.exitCode = 1;
});
child.once("exit", (code, signal) => {
  if (code !== 0) {
    console.error(`Node test suite exited with ${code ?? signal}`);
    process.exitCode = code ?? 1;
  }
});
