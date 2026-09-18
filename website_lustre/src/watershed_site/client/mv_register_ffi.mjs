import { initDemo } from "../../../../../../../website/src/scripts/demo.ts";

export function start() {
  const demo = document.querySelector("#demo");
  try {
    initDemo();
    demo?.setAttribute("data-mounted", "");
  } catch (error) {
    console.error("watershed demo failed to start", error);
    const note = document.querySelector("[data-demo-fallback]");
    if (note instanceof HTMLElement) note.hidden = false;
    const status = document.querySelector("[data-status]");
    if (status instanceof HTMLElement) {
      status.innerHTML =
        '<span class="stamp revising">Offline</span> kernels did not load, see below';
    }
  }
}
