import { Ok, Error } from "../../gleam.mjs";

const animated = new WeakSet();

export function animateFlows(root, duration) {
  const layer = root.querySelector('[data-testid="flow-layer"]');
  if (!layer) return new Error("Cannot find the flow layer.");
  const bounds = layer.getBoundingClientRect();
  for (const dot of layer.querySelectorAll("[data-flow-id]")) {
    if (animated.has(dot)) continue;
    const source = root.querySelector(`[data-flow-node="${dot.dataset.from}"]`);
    const target = root.querySelector(`[data-flow-node="${dot.dataset.to}"]`);
    if (!source || !target) return new Error("Cannot find a flow endpoint.");
    const point = (node) => {
      const rect = node.getBoundingClientRect();
      return `translate(${rect.left + rect.width / 2 - bounds.left - 5}px, ${rect.top + rect.height / 2 - bounds.top - 5}px)`;
    };
    animated.add(dot);
    dot.animate(
      [{ transform: point(source) }, { transform: point(target) }],
      {
        duration: matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : duration,
        fill: "forwards",
        easing: "linear",
      },
    );
  }
  return new Ok(undefined);
}
