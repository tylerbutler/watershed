import { pathToFileURL } from "node:url";
import { launchBrowser } from "../lib/cdp.mjs";
import { wait } from "../lib/conditions.mjs";

export async function smoke(url) {
  const browser = await launchBrowser({});
  try {
    const context = await browser.context();
    const page = await context.page();
    await page.goto(url);
    const read = async () => {
      const state = await page.evaluate(`({
        phase: document.querySelector("[data-state]")?.getAttribute("data-state"),
        snapshot: globalThis.__incidentEval?.snapshot(),
        errors: Array.from(document.querySelectorAll("[role=alert]"), el => el.textContent),
        count: document.querySelectorAll("[data-incident-id]").length,
      })`);
      const errors = [...state.errors, ...(state.snapshot?.errors ?? []), ...page.errors()];
      if (errors.length) throw new Error(`Native model error: ${errors.join("; ")}`);
      return state;
    };
    const initial = await wait("model ready", read, state =>
      state.phase === "ready" && state.snapshot?.phase === "ready");
    if (initial.count !== 0 || initial.snapshot.board.incidents.length !== 0) {
      throw new Error("Smoke check requires a new empty document");
    }
    await page.click("[data-action=add-incident]");
    await wait("created incident", read, state =>
      state.snapshot.board.incidents.length === 1 && state.count === 1);
    await page.fill("[data-incident-id] [data-field=title]", "Investigate smoke check");
    await wait("updated title", read, state =>
      state.snapshot.board.incidents[0]?.title === "Investigate smoke check");
    await page.click("[data-action=close]");
    await wait("model closed", read, state =>
      state.phase === "closed" && state.snapshot.phase === "closed");
  } finally {
    await browser.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (!process.argv[2]) throw new Error("Usage: node public/smoke.mjs APP_URL");
    await smoke(process.argv[2]);
    console.log("Public create/edit/read smoke check passed");
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
