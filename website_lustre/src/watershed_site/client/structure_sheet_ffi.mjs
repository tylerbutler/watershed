import { initDemo } from "../../../../../../../website/src/scripts/demo.ts";

function loadDemoStyles() {
  if (document.querySelector('link[data-structure-demo-styles]')) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "/styles/home.css";
  link.dataset.structureDemoStyles = "";
  document.head.append(link);
}

async function animatePanel(panel, opening, reduceMotion) {
  panel.getAnimations().forEach((animation) => animation.cancel());
  panel.classList.remove("is-opening", "is-closing");
  if (opening) panel.hidden = false;
  if (reduceMotion.matches) {
    if (!opening) panel.hidden = true;
    return;
  }

  panel.style.setProperty("--panel-height", `${panel.scrollHeight}px`);
  panel.classList.add(opening ? "is-opening" : "is-closing");
  await Promise.allSettled(
    panel.getAnimations().map((animation) => animation.finished),
  );
  panel.classList.remove("is-opening", "is-closing");
  panel.style.removeProperty("--panel-height");
  if (!opening) panel.hidden = true;
}

function showFallback(error) {
  console.error("watershed structure demo failed to start", error);
  document.querySelector("[data-demo-fallback]")?.removeAttribute("hidden");
  const status = document.querySelector("[data-status]");
  if (status instanceof HTMLElement) {
    status.innerHTML =
      '<span class="stamp revising">Offline</span> kernels did not load, see below';
  }
}

export function start() {
  const demo = document.querySelector("[data-family-demo] #demo");
  if (!(demo instanceof HTMLElement)) return;

  try {
    const rig = demo.querySelector("[data-demo-rig]");
    const skip = demo.querySelector(".demo-skip");
    if (!(rig instanceof HTMLElement) || !(skip instanceof HTMLAnchorElement)) {
      throw new Error("Structure demo markup is incomplete");
    }

    loadDemoStyles();
    initDemo();
    demo.dataset.mounted = "";

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let closeActiveDemo;
    let transitionPending = false;

    for (const button of document.querySelectorAll("[data-structure-toggle]")) {
      if (!(button instanceof HTMLButtonElement)) continue;
      const id = button.dataset.structureToggle;
      const plate = button.closest(".plate");
      const controls = plate?.querySelector("[data-structure-controls]");
      const description = plate?.querySelector(".plate-body");
      const panel = plate?.querySelector("[data-structure-demo]");
      const pick = demo.querySelector(`[data-dds-pick][value="${id}"]`);
      if (
        !id ||
        !(controls instanceof HTMLElement) ||
        !(description instanceof HTMLElement) ||
        !(panel instanceof HTMLElement) ||
        !(pick instanceof HTMLInputElement)
      ) {
        throw new Error(`Structure demo markup is incomplete for ${id}`);
      }

      const close = async () => {
        await animatePanel(panel, false, reduceMotion);
        description.hidden = false;
        button.setAttribute("aria-expanded", "false");
        button.textContent = "Try the live demo ↓";
      };

      button.addEventListener("click", async () => {
        if (transitionPending) return;
        transitionPending = true;
        try {
          if (!panel.hidden) {
            await close();
            closeActiveDemo = undefined;
            return;
          }
          await closeActiveDemo?.();
          panel.append(demo);
          description.hidden = true;
          button.setAttribute("aria-expanded", "true");
          button.textContent = "Close demo ↑";
          skip.href = `#${id}-after-demo`;
          rig.dataset.dds = id;
          pick.checked = true;
          pick.dispatchEvent(new Event("change", { bubbles: true }));
          closeActiveDemo = close;
          await animatePanel(panel, true, reduceMotion);
          button.scrollIntoView({ block: "nearest" });
        } finally {
          transitionPending = false;
        }
      });
      controls.hidden = false;
    }
  } catch (error) {
    showFallback(error);
  }
}
