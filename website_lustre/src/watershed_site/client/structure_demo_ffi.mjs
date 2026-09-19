export function familySlug() {
  return document.querySelector("[data-structure-family]")?.dataset
    .structureFamily ?? "";
}

export function setupDemo(selector) {
  const root = document.querySelector(selector);
  if (!root) return;

  const position = () => {
    const rig = root.querySelector("[data-demo-rig]");
    if (!rig) return;
    const bounds = rig.getBoundingClientRect();
    for (const dot of root.querySelectorAll("[data-flow-id]")) {
      const source = root.querySelector(`[data-flow-node="${dot.dataset.from}"]`);
      const target = root.querySelector(`[data-flow-node="${dot.dataset.to}"]`);
      if (!source || !target) continue;
      const from = source.getBoundingClientRect();
      const to = target.getBoundingClientRect();
      dot.style.setProperty("--from-x", `${from.left + from.width / 2 - bounds.left}px`);
      dot.style.setProperty("--from-y", `${from.top + from.height / 2 - bounds.top}px`);
      dot.style.setProperty("--to-x", `${to.left + to.width / 2 - bounds.left}px`);
      dot.style.setProperty("--to-y", `${to.top + to.height / 2 - bounds.top}px`);
    }
  };

  const observer = new MutationObserver(position);
  observer.observe(root, { childList: true, subtree: true });
  addEventListener("resize", position);
  position();
}
