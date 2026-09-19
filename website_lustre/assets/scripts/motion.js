// Scroll-linked reveals. Content is fully visible by default; when motion is
// allowed, elements are animated in *at trigger time* via WAAPI, so a failed
// script or a headless renderer never ships hidden content.
export function initReveals() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (!("IntersectionObserver" in window)) return;

  const variants = {
    rise: [
      { opacity: 0, transform: "translateY(16px)" },
      { opacity: 1, transform: "none" },
    ],
    // strata settle downward into place, like sediment
    settle: [
      { opacity: 0, transform: "translateY(-10px)" },
      { opacity: 1, transform: "none" },
    ],
  };

  const targets = [...document.querySelectorAll("[data-reveal]")];
  // Per-section stagger index so sibling reveals cascade.
  const groups = new Map();
  for (const el of targets) {
    const section = el.closest("section") ?? document.body;
    const index = groups.get(section) ?? 0;
    groups.set(section, index + 1);
    el.dataset.revealIndex = String(index);
  }

  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const el = entry.target;
        io.unobserve(el);
        const frames = variants[el.dataset.reveal] ?? variants.rise;
        el.animate(frames, {
          duration: 560,
          delay: Math.min(Number(el.dataset.revealIndex) * 90, 450),
          easing: "cubic-bezier(0.25, 1, 0.5, 1)",
          fill: "backwards",
        });
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0.15 },
  );

  for (const el of targets) io.observe(el);
}
