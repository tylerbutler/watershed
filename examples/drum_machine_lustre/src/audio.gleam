//// Gleam bindings to the Web Audio scheduler in `audio_ffi.mjs`.
////
//// The split is deliberate and load-bearing: this app's collaborative state
//// lives in watershed and its clock lives in Web Audio, and the two never talk
//// to each other. Gleam pushes a pattern snapshot into the engine whenever a
//// channel event lands; the engine's scheduler reads that snapshot and never
//// calls back. A slow document read therefore cannot become an audible glitch,
//// which matters because a glitch in a sync demo gets blamed on the sync.
////
//// Everything here is a side effect on a mutable JS object, so every function
//// returns `Nil`. The `Effect` wrappers at the bottom are for the two paths
//// that have to dispatch a message back into Lustre.

import gleam/javascript/array.{type Array}
import lustre/effect.{type Effect}

/// The scheduler, its voices, and the mutable pattern snapshot it reads.
/// Opaque: nothing outside `audio_ffi.mjs` may look inside it.
pub type Engine

@external(javascript, "./audio_ffi.mjs", "createEngine")
pub fn create() -> Engine

@external(javascript, "./audio_ffi.mjs", "isRunning")
pub fn is_running(engine: Engine) -> Bool

@external(javascript, "./audio_ffi.mjs", "resume")
fn resume_ffi(engine: Engine, done: fn(Bool) -> Nil) -> Nil

@external(javascript, "./audio_ffi.mjs", "start")
pub fn start(engine: Engine) -> Nil

@external(javascript, "./audio_ffi.mjs", "stop")
pub fn stop(engine: Engine) -> Nil

@external(javascript, "./audio_ffi.mjs", "setTrack")
pub fn set_track(engine: Engine, track: Int, steps: Array(Int)) -> Nil

@external(javascript, "./audio_ffi.mjs", "setBpm")
pub fn set_bpm(engine: Engine, bpm: Int) -> Nil

@external(javascript, "./audio_ffi.mjs", "setMute")
pub fn set_mute(engine: Engine, track: Int, muted: Bool) -> Nil

@external(javascript, "./audio_ffi.mjs", "setVolume")
pub fn set_volume(engine: Engine, percent: Int) -> Nil

@external(javascript, "./audio_ffi.mjs", "startPlayhead")
fn start_playhead_ffi(engine: Engine) -> Nil

/// Create the `AudioContext` and resume it. Must be called from a user
/// gesture — browsers refuse to start audio otherwise, which is why the app
/// has a click-to-start overlay rather than autoplaying.
pub fn resume(engine: Engine, to_msg: fn(Bool) -> msg) -> Effect(msg) {
  use dispatch <- effect.from
  resume_ffi(engine, fn(ok) { dispatch(to_msg(ok)) })
}

/// Begin the `requestAnimationFrame` loop that moves the playhead. Idempotent,
/// and safe to call before `#playhead` exists — the loop looks the element up
/// each frame and does nothing until it is there.
pub fn start_playhead(engine: Engine) -> Effect(msg) {
  use _dispatch <- effect.from
  start_playhead_ffi(engine)
}
