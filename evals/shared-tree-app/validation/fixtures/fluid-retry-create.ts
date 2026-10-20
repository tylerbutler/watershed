import type { Config } from "./domain.ts";
import { start as originalStart } from "./reference-model.ts";
export { nativeContainer, nativeView } from "./reference-model.ts";

export async function start(config: Config) {
  try {
    return await originalStart(config);
  } catch (error) {
    setTimeout(() => { void originalStart(config).catch(() => {}); }, 200);
    throw error;
  }
}
