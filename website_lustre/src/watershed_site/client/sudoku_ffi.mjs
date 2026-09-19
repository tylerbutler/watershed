import { Ok, Error } from "../../gleam.mjs";

const animated = new WeakSet();

function point(node, bounds) {
  const rect = node.getBoundingClientRect();
  return `translate(${rect.left + rect.width / 2 - bounds.left - 5}px, ${rect.top + rect.height / 2 - bounds.top - 5}px)`;
}

export function syncDom(root, paceQuarters, jitter, focusId) {
  const layer = root.querySelector('[data-testid="flow-layer"]');
  if (!layer) return new Error("Cannot find the flow layer.");
  const bounds = layer.getBoundingClientRect();
  for (const dot of layer.querySelectorAll("[data-flow-id]")) {
    if (animated.has(dot)) continue;
    const source = root.querySelector(`[data-flow-node="${dot.dataset.from}"]`);
    const target = root.querySelector(`[data-flow-node="${dot.dataset.to}"]`);
    if (!source || !target) return new Error("Cannot find a flow endpoint.");
    const latency = jitter ? Math.round(600 + Math.random() * 200) : 700;
    const duration = (latency * 4) / paceQuarters;
    const label = dot.querySelector(".flow-dot-label");
    if (label && !label.dataset.latency) {
      label.dataset.latency = String(latency);
      label.textContent = `${label.textContent} · ${latency} ms`;
    }
    animated.add(dot);
    dot.animate(
      [
        { transform: point(source, bounds) },
        { transform: point(target, bounds) },
      ],
      {
        duration: matchMedia("(prefers-reduced-motion: reduce)").matches
          ? 0
          : duration,
        fill: "forwards",
        easing: "linear",
      },
    );
  }
  if (focusId) {
    const cell = root.querySelector(`[data-testid="${focusId}"]`);
    if (!(cell instanceof HTMLButtonElement)) {
      return new Error("Cannot find the focused Sudoku cell.");
    }
    if (document.activeElement !== cell) cell.focus();
  }
  return new Ok(undefined);
}
