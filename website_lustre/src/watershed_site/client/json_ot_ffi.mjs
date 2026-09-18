import { initJsonOtDemo } from "../../../../../../../website/src/scripts/json-ot-demo.ts";

export function start() {
  initJsonOtDemo();
  document.querySelector("#jot-demo")?.setAttribute("data-mounted", "");
}
