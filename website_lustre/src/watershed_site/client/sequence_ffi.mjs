import { initSequenceDemo } from "../../../../../../../website/src/scripts/sequence-demo.ts";

export function start() {
  const demo = document.querySelector("#route-demo");
  try {
    initSequenceDemo();
    demo?.setAttribute("data-mounted", "");
  } catch (error) {
    console.error("watershed sequence demo failed to start", error);
    const note = document.querySelector("[data-route-fallback]");
    if (note instanceof HTMLElement) note.hidden = false;
  }
}
