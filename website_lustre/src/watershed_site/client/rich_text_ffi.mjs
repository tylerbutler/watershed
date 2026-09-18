import { initRichTextDemo } from "../../../../../../../website/src/scripts/rich-text-demo.ts";

export function start() {
  const demo = document.querySelector("#rt-demo");
  try {
    initRichTextDemo();
    demo?.setAttribute("data-mounted", "");
  } catch (error) {
    console.error("watershed rich-text demo failed to start", error);
    const note = document.querySelector("[data-rt-fallback]");
    if (note instanceof HTMLElement) note.hidden = false;
  }
}
