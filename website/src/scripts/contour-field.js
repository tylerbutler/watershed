// Pseudo-topographic contour field for the hero. Contours are labeled with
// server sequence numbers (SNs) instead of elevations: state flows downhill
// toward sequencing.
//
// Shared by the build-time hero markup and the client drift loop — both must
// sample identically, or the JS takeover visibly jumps.
export const W = 1300;
export const H = 860;
export const ROWS = 13;
const SEED_PHASE = 0.9;

// Slow two-frequency vertical flex, phase-shifted along x and by row so each
// line bends like water instead of translating rigidly. `amp` ramps 0→1 on
// the client; at amp 0 the geometry is exactly the static build-time field.
function drift(t, x, row, amp) {
  return (
    amp *
    (Math.sin(t * 0.4 + (x / W) * 4.2 + row * 0.9) * 3.2 +
      Math.sin(t * 0.23 + (x / W) * 2.1 + row * 1.7) * 1.8)
  );
}

export function contourPath(row, t = 0, amp = 0) {
  const baseY = 40 + row * 62;
  const pts = [];
  for (let x = -40; x <= W + 40; x += 100) {
    const tx = x / W;
    const y =
      baseY +
      Math.sin(tx * Math.PI * 2 + SEED_PHASE + row * 0.55) * (26 + row * 2.4) +
      Math.sin(tx * Math.PI * 5 + SEED_PHASE * 1.7) * 9 +
      tx * row * 14 + // drift downhill to the right
      drift(t, x, row, amp);
    pts.push([x, y]);
  }
  let d = `M ${pts[0][0]} ${pts[0][1].toFixed(1)}`;
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1];
    const [x1, y1] = pts[i];
    const cx = (x0 + x1) / 2;
    d += ` C ${cx} ${y0.toFixed(1)}, ${cx} ${y1.toFixed(1)}, ${x1} ${y1.toFixed(1)}`;
  }
  return d;
}
