import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { validateContract } from "./contract.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
export function validateTrack(track) {
  if (!["core", "transfers"].includes(track)) throw new TypeError(`Unsupported eval track: ${track}`);
  return track;
}

export async function loadTrack(track = "core") {
  validateTrack(track);
  let task = await readFile(join(root, "task.md"), "utf8");
  let contractText = await readFile(join(root, "contract.json"), "utf8");
  let contract = JSON.parse(contractText);
  if (track === "transfers") {
    task += "\n" + await readFile(join(root, "tracks/transfers/task.md"), "utf8");
    const extra = JSON.parse(await readFile(join(root, "tracks/transfers/contract.json"), "utf8"));
    contract = { ...contract, task: extra.task, groups: [...contract.groups, ...extra.groups],
      checks: [...contract.checks, ...extra.checks] };
    contractText = JSON.stringify(contract, null, 2) + "\n";
  }
  validateContract(contract);
  return { track, task, contract, contractText };
}
