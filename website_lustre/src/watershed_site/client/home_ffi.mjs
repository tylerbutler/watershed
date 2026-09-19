const WIDTH = 1300;
const ROWS = 13;
const FRAME_MS = 38;
const RAMP_SECONDS = 5;
const SEED_PHASE = 0.9;
const controllers = new WeakMap();

function drift(time, x, row, amplitude) {
  return amplitude * (
    Math.sin(time * 0.4 + (x / WIDTH) * 4.2 + row * 0.9) * 3.2
    + Math.sin(time * 0.23 + (x / WIDTH) * 2.1 + row * 1.7) * 1.8
  );
}

function contourPath(row, time = 0, amplitude = 0) {
  const baseY = 40 + row * 62;
  const points = [];
  for (let x = -40; x <= WIDTH + 40; x += 100) {
    const progress = x / WIDTH;
    const y =
      baseY
      + Math.sin(progress * Math.PI * 2 + SEED_PHASE + row * 0.55)
        * (26 + row * 2.4)
      + Math.sin(progress * Math.PI * 5 + SEED_PHASE * 1.7) * 9
      + progress * row * 14
      + drift(time, x, row, amplitude);
    points.push([x, y]);
  }

  let path = `M ${points[0][0]} ${points[0][1].toFixed(1)}`;
  for (let index = 1; index < points.length; index += 1) {
    const [previousX, previousY] = points[index - 1];
    const [x, y] = points[index];
    const controlX = (previousX + x) / 2;
    path += ` C ${controlX} ${previousY.toFixed(1)}, ${controlX} ${y.toFixed(1)}, ${x} ${y.toFixed(1)}`;
  }
  return path;
}

function reset(paths) {
  paths.forEach((path, index) => {
    path.setAttribute("d", contourPath(index));
  });
}

export function stopHeroDrift(root) {
  const controller = controllers.get(root);
  if (!controller) return;
  controller.stop();
  controllers.delete(root);
}

export function startHeroDrift(root) {
  stopHeroDrift(root);
  const ownerDocument = root?.ownerDocument ?? document;
  const field = ownerDocument.querySelector("[data-contour-field]");
  const media = ownerDocument.defaultView?.matchMedia(
    "(prefers-reduced-motion: reduce)",
  );
  const paths = Array.from(
    { length: ROWS },
    (_, index) => field?.querySelector(`#contour-${index}`),
  );
  if (!field || !media || paths.some((path) => !path)) return;
  if (media.matches) {
    reset(paths);
    return;
  }

  const view = ownerDocument.defaultView;
  let elapsed = 0;
  let last = null;
  let frameId = 0;
  let running = false;
  let observer;

  const stopFrames = () => {
    running = false;
    view.cancelAnimationFrame(frameId);
  };
  const frame = (now) => {
    frameId = view.requestAnimationFrame(frame);
    if (last === null) {
      last = now;
      return;
    }
    const delta = now - last;
    if (delta < FRAME_MS) return;
    last = now;
    elapsed += Math.min(delta, 100) / 1000;
    const amplitude = Math.min(elapsed / RAMP_SECONDS, 1);
    paths.forEach((path, index) => {
      path.setAttribute("d", contourPath(index, elapsed, amplitude));
    });
  };
  const startFrames = () => {
    if (running) return;
    running = true;
    last = null;
    frameId = view.requestAnimationFrame(frame);
  };
  const onMotionChange = () => {
    if (!media.matches) return;
    stopHeroDrift(root);
    reset(paths);
  };

  observer = new view.IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) startFrames();
    else stopFrames();
  });
  observer.observe(field);
  media.addEventListener("change", onMotionChange);
  controllers.set(root, {
    stop() {
      stopFrames();
      observer.disconnect();
      media.removeEventListener("change", onMotionChange);
    },
  });
}
