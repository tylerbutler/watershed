//// Digest-gated save scheduling for `watershed/persist_js`.
////
//// An application calls `changed` after a local mutation. The periodic digest
//// sweep captures the remote edits. The `pagehide` event starts one final save
//// attempt. One controller runs one persistence write at a time.
////
//// JavaScript target only.

@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import watershed/crdt_js.{type CrdtDocument}
@target(javascript)
import watershed/persist_js.{type PersistenceError, type Storage}
@target(javascript)
import watershed/timer_js
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler}

const debounce_milliseconds = 500

const sweep_milliseconds = 5000

@target(javascript)
pub type Status {
  Saving
  Saved(digest: String)
  SaveFailed(error: PersistenceError)
}

@target(javascript)
pub opaque type Controller(root) {
  Controller(cell: Cell(State(root)))
}

@target(javascript)
type State(root) {
  State(
    save: fn(CrdtDocument(root), fn(Result(String, PersistenceError)) -> Nil) ->
      Nil,
    document: CrdtDocument(root),
    scheduler: Scheduler,
    on_status: fn(Status) -> Nil,
    last_saved: String,
    dirty: Bool,
    saving: Bool,
    pagehide_pending: Bool,
    debounce: Option(fn() -> Nil),
    sweep: Option(fn() -> Nil),
    remove_pagehide: fn() -> Nil,
    stopped: Bool,
  )
}

@target(javascript)
/// Start a controller that uses the browser timers and the `pagehide` event.
pub fn start(
  storage: Storage,
  document: CrdtDocument(root),
  on_status: fn(Status) -> Nil,
) -> Controller(root) {
  start_with(
    storage,
    document,
    on_status,
    transport_js.real_scheduler(),
    listen_pagehide,
  )
}

@target(javascript)
/// An injectable lifecycle, for deterministic tests.
pub fn start_with(
  storage: Storage,
  document: CrdtDocument(root),
  on_status: fn(Status) -> Nil,
  scheduler: Scheduler,
  listen_pagehide: fn(fn() -> Nil) -> fn() -> Nil,
) -> Controller(root) {
  start_with_save(
    document,
    on_status,
    scheduler,
    listen_pagehide,
    fn(document, done) { persist_js.save(storage, document, done) },
  )
}

@target(javascript)
/// An injectable lifecycle and save driver, for deterministic tests.
pub fn start_with_save(
  document: CrdtDocument(root),
  on_status: fn(Status) -> Nil,
  scheduler: Scheduler,
  listen_pagehide: fn(fn() -> Nil) -> fn() -> Nil,
  save: fn(CrdtDocument(root), fn(Result(String, PersistenceError)) -> Nil) ->
    Nil,
) -> Controller(root) {
  let cell =
    transport_js.new_cell(State(
      save:,
      document:,
      scheduler:,
      on_status:,
      last_saved: "",
      dirty: True,
      saving: False,
      pagehide_pending: False,
      debounce: None,
      sweep: None,
      remove_pagehide: fn() { Nil },
      stopped: False,
    ))
  let controller = Controller(cell:)
  let remove = listen_pagehide(fn() { request_pagehide_save(controller) })
  update(controller, fn(state) { State(..state, remove_pagehide: remove) })
  arm_debounce(controller)
  arm_sweep(controller)
  controller
}

@target(javascript)
/// Report a possible local edit. The digest comparison prevents a write for a
/// message that only moves the selection or changes nothing.
pub fn changed(controller: Controller(root)) -> Nil {
  update(controller, fn(state) { State(..state, dirty: True) })
  arm_debounce(controller)
}

@target(javascript)
/// Cancel the timers and remove the page lifecycle listener. An IndexedDB
/// write that is already in progress continues and reports its result.
pub fn stop(controller: Controller(root)) -> Nil {
  let state = get(controller)
  cancel(state.debounce)
  cancel(state.sweep)
  state.remove_pagehide()
  set(controller, State(..state, stopped: True, debounce: None, sweep: None))
}

@target(javascript)
fn arm_debounce(controller: Controller(root)) -> Nil {
  let state = get(controller)
  case state.stopped || state.saving || option.is_some(state.debounce) {
    True -> Nil
    False -> {
      timer_js.arm(
        scheduler: state.scheduler,
        delay_milliseconds: debounce_milliseconds,
        action: fn() {
          update(controller, fn(current) { State(..current, debounce: None) })
          save_if_changed(controller)
        },
        wanted: fn() {
          let current = get(controller)
          !current.stopped
          && !current.saving
          && option.is_none(current.debounce)
        },
        store: fn(cancel) {
          update(controller, fn(current) {
            State(..current, debounce: Some(cancel))
          })
        },
      )
    }
  }
}

@target(javascript)
fn arm_sweep(controller: Controller(root)) -> Nil {
  let state = get(controller)
  case state.stopped || option.is_some(state.sweep) {
    True -> Nil
    False ->
      timer_js.arm(
        scheduler: state.scheduler,
        delay_milliseconds: sweep_milliseconds,
        action: fn() {
          let armed_asynchronously = option.is_some(get(controller).sweep)
          update(controller, fn(current) { State(..current, sweep: None) })
          save_if_changed(controller)
          case armed_asynchronously {
            True -> arm_sweep(controller)
            False -> Nil
          }
        },
        wanted: fn() {
          let current = get(controller)
          !current.stopped && option.is_none(current.sweep)
        },
        store: fn(cancel) {
          update(controller, fn(current) {
            State(..current, sweep: Some(cancel))
          })
        },
      )
  }
}

@target(javascript)
fn save_if_changed(controller: Controller(root)) -> Nil {
  let _ = start_save_if_changed(controller)
  Nil
}

@target(javascript)
fn request_pagehide_save(controller: Controller(root)) -> Nil {
  let state = get(controller)
  case state.stopped {
    True -> Nil
    False ->
      case state.saving {
        True ->
          update(controller, fn(current) {
            State(..current, pagehide_pending: True)
          })
        False -> save_if_changed(controller)
      }
  }
}

@target(javascript)
fn start_save_if_changed(controller: Controller(root)) -> Bool {
  let state = get(controller)
  let digest = crdt_js.digest(state.document)
  case state.stopped || state.saving || digest == state.last_saved {
    True -> False
    False -> {
      cancel(state.debounce)
      set(
        controller,
        State(..state, dirty: False, saving: True, debounce: None),
      )
      state.on_status(Saving)
      state.save(state.document, fn(outcome) {
        let current = get(controller)
        case outcome {
          Ok(saved_digest) -> {
            set(
              controller,
              State(..current, last_saved: saved_digest, saving: False),
            )
            current.on_status(Saved(saved_digest))
          }
          Error(error) -> {
            set(controller, State(..current, dirty: True, saving: False))
            current.on_status(SaveFailed(error))
          }
        }
        continue_after_save(controller)
      })
      True
    }
  }
}

@target(javascript)
fn continue_after_save(controller: Controller(root)) -> Nil {
  let state = get(controller)
  case state.pagehide_pending {
    True -> {
      update(controller, fn(current) {
        State(..current, pagehide_pending: False)
      })
      case start_save_if_changed(controller) {
        True -> Nil
        False -> arm_debounce_if_needed(controller)
      }
    }
    False -> arm_debounce_if_needed(controller)
  }
}

@target(javascript)
fn arm_debounce_if_needed(controller: Controller(root)) -> Nil {
  let state = get(controller)
  case
    !state.stopped
    && { state.dirty || crdt_js.digest(state.document) != state.last_saved }
  {
    True -> arm_debounce(controller)
    False -> Nil
  }
}

@target(javascript)
fn get(controller: Controller(root)) -> State(root) {
  let Controller(cell:) = controller
  transport_js.get_cell(cell)
}

@target(javascript)
fn set(controller: Controller(root), state: State(root)) -> Nil {
  let Controller(cell:) = controller
  transport_js.set_cell(cell, state)
}

@target(javascript)
fn update(
  controller: Controller(root),
  change: fn(State(root)) -> State(root),
) -> Nil {
  set(controller, change(get(controller)))
}

@target(javascript)
fn cancel(timer: Option(fn() -> Nil)) -> Nil {
  case timer {
    Some(stop) -> stop()
    None -> Nil
  }
}

@target(javascript)
@external(javascript, "./persist_js_ffi.mjs", "listenPagehide")
fn listen_pagehide(action: fn() -> Nil) -> fn() -> Nil
