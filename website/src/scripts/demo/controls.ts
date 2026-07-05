// The demo control cluster: a link-latency slider, an optional animation-speed
// (playback) slider, and an optional jitter toggle. Owns the reactive reads of
// those inputs and derives the two functions the transport needs:
//
//   • sampleLatency() — the modelled network delay for one hop, optionally
//     jittered by ±`jitterMs` so ops stop travelling in lock-step.
//   • paced(ms)       — convert a base duration into wall-clock ms at the
//     current playback speed (lower speed → longer on-screen durations).
//
// Latency and jitter change the *simulation*; animation speed only changes how
// fast you watch it.

export interface LatencyControls {
  /** Modelled per-hop latency in ms, jittered when the toggle is on. */
  sampleLatency(): number;
  /** Scale a base duration/delay to wall-clock ms at the current speed. */
  paced(ms: number): number;
  /** Current raw slider latency in ms (un-jittered). */
  readonly latency: number;
  /** Current playback multiplier (1 = real-time). */
  readonly animSpeed: number;
}

export interface LatencyControlsOptions {
  latencyInput: HTMLInputElement;
  latencyOut: HTMLElement;
  paceInput?: HTMLInputElement | null;
  paceOut?: HTMLElement | null;
  varianceToggle?: HTMLInputElement | null;
  /** Peak jitter magnitude in ms; the sample is uniform on ±jitterMs. */
  jitterMs?: number;
  /** Fallback playback speed when no pace slider is present. */
  defaultSpeed?: number;
}

export function createLatencyControls(
  opts: LatencyControlsOptions,
): LatencyControls {
  const {
    latencyInput,
    latencyOut,
    paceInput,
    paceOut,
    varianceToggle,
    jitterMs = 50,
    defaultSpeed = 0.5,
  } = opts;

  let latency = Number(latencyInput.value);
  let animSpeed = paceInput ? Number(paceInput.value) : defaultSpeed;
  let variance = varianceToggle ? varianceToggle.checked : false;

  latencyOut.textContent = `${latency} ms`;
  latencyInput.addEventListener("input", () => {
    latency = Number(latencyInput.value);
    latencyOut.textContent = `${latency} ms`;
  });

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
      if (!variance) return latency;
      return Math.max(0, latency + Math.round(Math.random() * jitterMs * 2 - jitterMs));
    },
    paced(ms: number) {
      return ms / animSpeed;
    },
    get latency() {
      return latency;
    },
    get animSpeed() {
      return animSpeed;
    },
  };
}
