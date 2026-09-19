import { initHeroDrift } from "../../../../../../../website/src/scripts/hero-drift.js";

function initGaugeStrip() {
  const strip = document.querySelector("[data-gauge-strip]");
  const rig = document.querySelector("[data-demo-rig]");
  if (!strip || !rig) return;
  const proxy = strip.querySelector("[data-strip-race]");
  const race = document.querySelector("[data-race]");
  if (proxy instanceof HTMLButtonElement && race instanceof HTMLButtonElement) {
    proxy.addEventListener("click", () => race.click());
    proxy.disabled = false;
  }
  const sync = () => {
    for (const cell of strip.querySelectorAll("[data-strip-client]")) {
      const client = rig.querySelector(
        `[data-client="${cell.getAttribute("data-strip-client")}"]`,
      );
      if (!client) continue;
      for (const value of cell.querySelectorAll("[data-strip-key]")) {
        const row = client.querySelector(
          `.dds-map tr[data-key="${value.getAttribute("data-strip-key")}"]`,
        );
        value.textContent =
          row?.querySelector("[data-value]")?.textContent?.trim() ?? "";
        value.classList.toggle("pending", row?.classList.contains("pending"));
      }
    }
  };
  new MutationObserver(sync).observe(rig, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ["class"],
  });
  sync();
}

export function enhance() {
  const rig = document.querySelector("[data-demo-rig]");
  rig?.setAttribute("data-dds", "map");
  rig?.setAttribute("data-views", "map");
  initGaugeStrip();
  initHeroDrift();
}
