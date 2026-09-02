// The clock and the voices. Everything collaborative lives in Gleam; this
// module owns Web Audio and nothing else.
//
// Two rules shape the design, and both exist to keep sync latency out of the
// audio path:
//
//  1. **The scheduler never calls into Gleam.** It reads `engine.pattern`, a
//     plain array of 4×16 booleans that Gleam overwrites whenever a channel
//     event lands. If the scheduler had to ask Gleam for the pattern, a slow
//     document read would become an audible glitch — and this demo's whole
//     purpose is that a glitch is never watershed's fault.
//
//  2. **Lookahead, not event-loop timing.** A 25ms interval wakes and schedules
//     every step falling inside the next 100ms against `ctx.currentTime`.
//     Scheduling straight from a timer callback puts JS timer jitter — tens of
//     milliseconds under load — directly onto 16th notes, where it is plainly
//     audible. This is the standard Web Audio pattern for exactly that reason.

const LOOKAHEAD_MS = 25;
const SCHEDULE_AHEAD_S = 0.1;
const STEP_COUNT = 16;
const TRACK_COUNT = 4;

// Track order must match `drum_machine_lustre.tracks()`.
const KICK = 0;
const SNARE = 1;
const HAT = 2;
const CLAP = 3;

function emptyPattern() {
  return Array.from({ length: TRACK_COUNT }, () =>
    new Array(STEP_COUNT).fill(false),
  );
}

export function createEngine() {
  return {
    ctx: null,
    master: null,
    noise: null,
    // The mutable snapshot the scheduler reads. Never replaced, only mutated
    // in place, so a scheduler tick can never observe a half-written pattern.
    pattern: emptyPattern(),
    mute: new Array(TRACK_COUNT).fill(false),
    bpm: 120,
    playing: false,
    timer: null,
    // The audio-clock time the next step is due at, and which step that is.
    nextStepTime: 0,
    nextStep: 0,
    // Steps already scheduled but not yet heard, as {step, time}. The playhead
    // drains this against `ctx.currentTime` so the highlight lands with the
    // sound rather than with the scheduling, which runs up to 100ms early.
    queue: [],
    audibleStep: -1,
    // rAF handle for the playhead loop, and the last step it painted.
    frame: null,
    paintedStep: -2,
    displayRevision: 0,
    paintedRevision: -1,
  };
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

// Browsers start an AudioContext suspended until a user gesture. A demo that
// is silently muted with no explanation reads as broken, so the app renders a
// click-to-start overlay and calls this from the click.
export function resume(engine, done) {
  try {
    if (engine.ctx === null) {
      const Ctx = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!Ctx) {
        done(false);
        return undefined;
      }
      engine.ctx = new Ctx();
      engine.master = engine.ctx.createGain();
      engine.master.gain.value = 0.8;
      engine.master.connect(engine.ctx.destination);
      engine.noise = buildNoise(engine.ctx);
    }
    engine.ctx
      .resume()
      .then(() => done(engine.ctx.state === "running"))
      .catch(() => done(false));
  } catch (_error) {
    done(false);
  }
  return undefined;
}

export function isRunning(engine) {
  return engine.ctx !== null && engine.ctx.state === "running";
}

export function start(engine) {
  if (engine.ctx === null || engine.playing) return undefined;
  engine.playing = true;
  engine.nextStep = 0;
  engine.nextStepTime = engine.ctx.currentTime + 0.05;
  engine.queue = [];
  engine.timer = setInterval(() => tick(engine), LOOKAHEAD_MS);
  tick(engine);
  return undefined;
}

export function stop(engine) {
  if (!engine.playing) return undefined;
  engine.playing = false;
  clearInterval(engine.timer);
  engine.timer = null;
  engine.queue = [];
  engine.audibleStep = -1;
  return undefined;
}

// ── State the scheduler reads ────────────────────────────────────────────────

// `steps` is a `gleam/javascript/array` — a real JS array of step indices.
export function setTrack(engine, track, steps) {
  const row = engine.pattern[track];
  if (row === undefined) return undefined;
  row.fill(false);
  for (const step of steps) {
    if (step >= 0 && step < STEP_COUNT) row[step] = true;
  }
  engine.displayRevision += 1;
  return undefined;
}

export function setBpm(engine, bpm) {
  // Clamped rather than trusted: the tempo arrives from the document in DM6,
  // and a peer proposing 0 would divide by zero in `stepDuration`.
  engine.bpm = Math.min(240, Math.max(40, bpm));
  return undefined;
}

export function setMute(engine, track, muted) {
  engine.mute[track] = muted;
  engine.displayRevision += 1;
  return undefined;
}

export function setVolume(engine, percent) {
  const gain = Math.min(1, Math.max(0, percent / 100));
  if (engine.master !== null) {
    engine.master.gain.value = gain;
  }
  return undefined;
}

// ── Scheduler ────────────────────────────────────────────────────────────────

function stepDuration(engine) {
  // 16th notes: four steps to the beat.
  return 60 / engine.bpm / 4;
}

// docs:snippet-start practice-realtime-tick
function tick(engine) {
  const ctx = engine.ctx;
  if (ctx === null || !engine.playing) return;

  // Browsers throttle `setInterval` to about once a second in a background
  // tab, while the audio clock keeps running. Without this the next tick would
  // "catch up" by scheduling a second of steps whose times have already
  // passed, and Web Audio plays a past-dated start immediately — so returning
  // to the tab is greeted by a burst of every step it missed. Resync instead,
  // keeping the step index continuous so the pattern resumes in place.
  if (engine.nextStepTime < ctx.currentTime) {
    engine.nextStepTime = ctx.currentTime;
    engine.queue = [];
  }

  const horizon = ctx.currentTime + SCHEDULE_AHEAD_S;
  while (engine.nextStepTime < horizon) {
    scheduleStep(engine, engine.nextStep, engine.nextStepTime);
    engine.queue.push({ step: engine.nextStep, time: engine.nextStepTime });
    // Read the duration per step, so a tempo change mid-bar takes effect on
    // the next step rather than at the end of the loop.
    engine.nextStepTime += stepDuration(engine);
    engine.nextStep = (engine.nextStep + 1) % STEP_COUNT;
  }
}
// docs:snippet-end practice-realtime-tick

function scheduleStep(engine, step, time) {
  for (let track = 0; track < TRACK_COUNT; track++) {
    if (engine.mute[track]) continue;
    if (!engine.pattern[track][step]) continue;
    voice(engine, track, time);
  }
}

function voice(engine, track, time) {
  switch (track) {
    case KICK:
      kick(engine, time);
      break;
    case SNARE:
      snare(engine, time);
      break;
    case HAT:
      hat(engine, time);
      break;
    case CLAP:
      clap(engine, time);
      break;
  }
}

// ── Voices ───────────────────────────────────────────────────────────────────
//
// Synthesised rather than sampled: it keeps the repo free of binaries and
// removes an asset-loading failure mode that would look exactly like a sync
// bug to anyone watching.

// One second of white noise, generated once and replayed by the noise voices.
function buildNoise(ctx) {
  const buffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) {
    data[i] = Math.random() * 2 - 1;
  }
  return buffer;
}

function noiseBurst(engine, time, { filter, frequency, q, peak, decay }) {
  const ctx = engine.ctx;
  const source = ctx.createBufferSource();
  source.buffer = engine.noise;
  // A random offset into the buffer, so repeated hits are not identical.
  const band = ctx.createBiquadFilter();
  band.type = filter;
  band.frequency.value = frequency;
  band.Q.value = q;
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(peak, time);
  gain.gain.exponentialRampToValueAtTime(0.001, time + decay);
  source.connect(band).connect(gain).connect(engine.master);
  source.start(time, Math.random() * 0.5);
  source.stop(time + decay + 0.02);
}

// A pitch-swept sine: 150Hz down to 45Hz in 120ms is the classic 808 thump.
function kick(engine, time) {
  const ctx = engine.ctx;
  const osc = ctx.createOscillator();
  osc.type = "sine";
  osc.frequency.setValueAtTime(150, time);
  osc.frequency.exponentialRampToValueAtTime(45, time + 0.12);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.9, time);
  gain.gain.exponentialRampToValueAtTime(0.001, time + 0.35);
  osc.connect(gain).connect(engine.master);
  osc.start(time);
  osc.stop(time + 0.4);
}

// Noise for the snares, plus a short triangle body so it has a pitch.
function snare(engine, time) {
  noiseBurst(engine, time, {
    filter: "bandpass",
    frequency: 1800,
    q: 0.7,
    peak: 0.5,
    decay: 0.18,
  });
  const ctx = engine.ctx;
  const body = ctx.createOscillator();
  body.type = "triangle";
  body.frequency.setValueAtTime(180, time);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.35, time);
  gain.gain.exponentialRampToValueAtTime(0.001, time + 0.1);
  body.connect(gain).connect(engine.master);
  body.start(time);
  body.stop(time + 0.12);
}

function hat(engine, time) {
  noiseBurst(engine, time, {
    filter: "highpass",
    frequency: 7000,
    q: 1,
    peak: 0.25,
    decay: 0.05,
  });
}

// Three bursts a few milliseconds apart — a clap is many hands, not one.
function clap(engine, time) {
  for (const offset of [0, 0.011, 0.023]) {
    noiseBurst(engine, time + offset, {
      filter: "bandpass",
      frequency: 1200,
      q: 1.4,
      peak: 0.35,
      decay: offset === 0.023 ? 0.14 : 0.045,
    });
  }
}

// ── Playhead ─────────────────────────────────────────────────────────────────
//
// Driven here rather than by a Lustre message per step. At 140 BPM a 16th-note
// playhead is ~9 messages a second, each one a full vdom diff of the grid, for
// a moving highlight that touches two elements.
//
// The app renders `<div id="playhead">` **empty** and never puts children in
// it, so Lustre's diff has nothing to patch and this module owns the subtree
// outright. That is the whole contract; do not render children into it.

export function startPlayhead(engine) {
  if (engine.frame !== null) return undefined;
  const loop = () => {
    paint(engine);
    engine.frame = requestAnimationFrame(loop);
  };
  engine.frame = requestAnimationFrame(loop);
  return undefined;
}

function paint(engine) {
  const el = globalThis.document?.getElementById("playhead");
  if (!el) return;
  if (el.childElementCount !== STEP_COUNT + 1) build(el);

  // Drain every step whose audio time has passed; the last one is what is
  // sounding now.
  if (engine.ctx !== null) {
    const now = engine.ctx.currentTime;
    while (engine.queue.length > 0 && engine.queue[0].time <= now) {
      engine.audibleStep = engine.queue.shift().step;
    }
  }
  const step = engine.playing ? engine.audibleStep : -1;
  if (
    step === engine.paintedStep &&
    engine.displayRevision === engine.paintedRevision
  ) {
    return;
  }
  engine.paintedStep = step;
  engine.paintedRevision = engine.displayRevision;
  for (let i = 0; i < STEP_COUNT; i++) {
    el.children[i + 1].classList.toggle("lit", i === step);
  }
  for (const cell of globalThis.document.querySelectorAll(".step.triggered")) {
    cell.classList.remove("triggered");
  }
  if (step < 0) return;
  for (let track = 0; track < TRACK_COUNT; track++) {
    if (engine.mute[track] || !engine.pattern[track][step]) continue;
    const cell = globalThis.document.querySelector(
      `.step[data-track="${track}"][data-step="${step}"]`,
    );
    cell?.classList.add("triggered");
  }
}

function build(el) {
  el.replaceChildren();
  // A leading spacer keeps the cells under the grid's step columns; the row
  // grid template is `4.5rem repeat(16, 1fr)`.
  el.appendChild(globalThis.document.createElement("span"));
  for (let i = 0; i < STEP_COUNT; i++) {
    const cell = globalThis.document.createElement("span");
    cell.className = "beat";
    el.appendChild(cell);
  }
}
