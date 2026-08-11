// The pixel buffer and its <canvas>, owned outright by this module.
//
// The app renders `<canvas id="canvas">` and never puts children in it, so
// Lustre's diff has nothing to patch and cannot wipe the drawing out from under
// us. That is the same contract the drum machine's `#playhead` has, and for the
// same reason: 4096 vdom nodes re-diffed on every remote event would dominate
// the profile and make watershed look slow for reasons that have nothing to do
// with watershed.
//
// Two rules keep it working:
//
//   1. The element's `width`/`height` attributes must stay static in `view`.
//      Re-setting either one resets the drawing surface, so a diff that
//      rewrites them clears the picture.
//   2. The context is resolved lazily, on every call, and the module no-ops
//      until the element exists. This is why no mount-ordering effect is
//      needed: state that arrives before the first paint is written to the
//      buffer, and the buffer is flushed to the canvas the moment the element
//      turns up.
//
// `globalThis.document?.` rather than a bare `document`, because the smoke
// bundle loads this module under Node.

const SIZE = 64;

// Index 0 is "erase" and is not in this table — it clears the pixel instead of
// filling it, so the element's CSS background shows through and the canvas
// tracks light/dark mode for free.
export function createCanvas(paletteJson) {
  return {
    palette: JSON.parse(paletteJson),
    cells: new Uint8Array(SIZE * SIZE),
    ctx: null,
  };
}

// The 2D context, or null while the element is still absent. On the call that
// first resolves it, everything painted so far is flushed to the surface.
function context(canvas) {
  if (canvas.ctx) return canvas.ctx;
  const element = globalThis.document?.getElementById("canvas");
  if (!element || typeof element.getContext !== "function") return null;
  const ctx = element.getContext("2d");
  if (!ctx) return null;
  canvas.ctx = ctx;
  flush(canvas, ctx);
  return ctx;
}

function flush(canvas, ctx) {
  ctx.clearRect(0, 0, SIZE, SIZE);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const color = canvas.cells[y * SIZE + x];
      if (color !== 0) draw(canvas, ctx, x, y, color);
    }
  }
}

function draw(canvas, ctx, x, y, color) {
  if (color === 0) {
    ctx.clearRect(x, y, 1, 1);
    return;
  }
  ctx.fillStyle = canvas.palette[color] ?? canvas.palette[0];
  ctx.fillRect(x, y, 1, 1);
}

// Write one cell. Buffer first, so a paint that lands before the element exists
// is still there for `flush` to pick up.
export function paintCell(canvas, x, y, color) {
  if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return undefined;
  canvas.cells[y * SIZE + x] = color;
  const ctx = context(canvas);
  if (ctx) draw(canvas, ctx, x, y, color);
  return undefined;
}

// Bulk seed, for the state a joiner receives in one go. Parallel arrays rather
// than a list of tuples: this runs once with up to 4096 entries, and the flat
// form crosses the FFI boundary without allocating a wrapper per cell.
export function paintMany(canvas, xs, ys, colors) {
  const count = Math.min(xs.length, ys.length, colors.length);
  for (let i = 0; i < count; i++) {
    const x = xs[i];
    const y = ys[i];
    if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) continue;
    canvas.cells[y * SIZE + x] = colors[i];
  }
  const ctx = context(canvas);
  if (ctx) flush(canvas, ctx);
  return undefined;
}

// The palette index currently at a cell — what an "is this already that
// colour?" check reads, so a drag across one cell emits one op and not thirty.
export function colorAt(canvas, x, y) {
  if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return 0;
  return canvas.cells[y * SIZE + x];
}
