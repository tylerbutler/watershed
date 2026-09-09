import { core } from "./core.mjs";

export async function parseGleam({ path, source }) {
  return core().parse_gleam(path, source);
}
