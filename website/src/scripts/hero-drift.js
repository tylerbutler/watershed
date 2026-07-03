// Ambient drift for the hero contour field. After (and during) the draw-in,
// the lines keep flexing slowly, like the surface of moving water. Geometry
// is re-derived each frame from the same generator the build used, with the
// drift amplitude ramping from zero — so the takeover is seamless and a
// failed script simply leaves the static field.
import { ROWS, contourPath } from "./contour-field.js";

const FRAME_MS = 38; // ~26fps; the motion is slow enough that this is smooth
const RAMP_S = 5; // seconds for drift amplitude to reach full strength

export function initHeroDrift() {
  const media = window.matchMedia("(prefers-reduced-motion: reduce)");
  if (media.matches) return;

  const field = document.querySelector("[data-contour-field]");
  if (!field) return;
  const paths = Array.from({ length: ROWS }, (_, i) =>
    field.querySelector(`#contour-${i}`),
  );
  if (paths.some((p) => !p)) return;

  let t = 0; // drift clock advances only while visible, so pauses don't jump
  let last = null;
  let raf = 0;
  let running = false;

  function frame(now) {
    raf = requestAnimationFrame(frame);
    if (last === null) {
      last = now;
      return;
    }
    const dt = now - last;
    if (dt < FRAME_MS) return;
    last = now;
    t += Math.min(dt, 100) / 1000;
    const amp = Math.min(t / RAMP_S, 1);
    for (let i = 0; i < paths.length; i++) {
      paths[i].setAttribute("d", contourPath(i, t, amp));
    }
  }

  function start() {
    if (running) return;
    running = true;
    last = null;
    raf = requestAnimationFrame(frame);
  }

  function stop() {
    running = false;
    cancelAnimationFrame(raf);
  }

  const io = new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) start();
    else stop();
  });
  io.observe(field);

  media.addEventListener("change", () => {
    if (!media.matches) return;
    stop();
    io.disconnect();
    for (let i = 0; i < paths.length; i++) {
      paths[i].setAttribute("d", contourPath(i));
    }
  });
}
