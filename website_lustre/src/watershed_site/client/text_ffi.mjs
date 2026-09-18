import { initTextDemo } from "../../../../../../../website/src/scripts/text-demo.ts";
import { initTextElementDemo } from "../../../../../../../website/src/scripts/text-element-demo.ts";

export function start() {
  try {
    initTextDemo();
    document.querySelector("#text-demo")?.setAttribute("data-mounted", "");
    initTextElementDemo();
    document.querySelector("#text-element-demo")?.setAttribute("data-mounted", "");
  } catch (error) {
    console.error("watershed text demos failed to start", error);
    document.querySelector("[data-text-fallback]")?.removeAttribute("hidden");
    document.querySelector("[data-text-element-fallback]")?.removeAttribute("hidden");
  }
}
