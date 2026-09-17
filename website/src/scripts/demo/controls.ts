// The demo control cluster: an optional animation-speed (playback) slider and
// an optional jitter toggle. Owns the reactive reads of those inputs and
// derives the two functions the transport needs:
//
//   • sampleLatency() — the fixed network delay for one hop, optionally
//     jittered so ops stop travelling in lock-step.
//   • paced(ms)       — convert a base duration into wall-clock ms at the
//     current playback speed (lower speed → longer on-screen durations).
//
// Jitter changes the *simulation*; animation speed only changes how fast you
// watch it.

const LINK_LATENCY_MS = 1000;
const JITTER_MS = 100;

export interface LatencyControls {
  /** Modelled per-hop latency in ms, jittered when the toggle is on. */
  sampleLatency(): number;
  /** Scale a base duration/delay to wall-clock ms at the current speed. */
  paced(ms: number): number;
  /** Current playback multiplier (1 = real-time). */
  readonly animSpeed: number;
}

export interface LatencyControlsOptions {
  paceInput?: HTMLInputElement | null;
  paceOut?: HTMLElement | null;
  varianceToggle?: HTMLInputElement | null;
  /** Fallback playback speed when no pace slider is present. */
  defaultSpeed?: number;
}

export function createLatencyControls(
  opts: LatencyControlsOptions,
): LatencyControls {
  const {
    paceInput,
    paceOut,
    varianceToggle,
    defaultSpeed = 1,
  } = opts;

  let animSpeed = paceInput ? Number(paceInput.value) : defaultSpeed;
  let variance = varianceToggle ? varianceToggle.checked : false;

  if (paceInput && paceOut) {
    const fmt = (v: number) => `${v}×`;
    paceOut.textContent = fmt(animSpeed);
    paceInput.addEventListener("input", () => {
      animSpeed = Number(paceInput.value);
      paceOut.textContent = fmt(animSpeed);
    });
  }

  if (varianceToggle) {
    varianceToggle.addEventListener("change", () => {
      variance = varianceToggle.checked;
    });
  }

  return {
    sampleLatency() {
      if (!variance) return LINK_LATENCY_MS;
      return LINK_LATENCY_MS + Math.round(Math.random() * JITTER_MS * 2 - JITTER_MS);
    },
    paced(ms: number) {
      return ms / animSpeed;
    },
    get animSpeed() {
      return animSpeed;
    },
  };
}
