/// <reference types="./persist_controller_js.d.mts" />
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, CustomType as $CustomType } from "../gleam.mjs";
import * as $crdt_js from "../watershed/crdt_js.mjs";
import * as $persist_js from "../watershed/persist_js.mjs";
import * as $timer_js from "../watershed/timer_js.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";
import { listenPagehide as listen_pagehide } from "./persist_js_ffi.mjs";

export class Saving extends $CustomType {}
export const Status$Saving$const = new Saving();
export const Status$Saving = () => Status$Saving$const;
export const Status$isSaving = (value) => value instanceof Saving;

export class Saved extends $CustomType {
  constructor(digest) {
    super();
    this.digest = digest;
  }
}
export const Status$Saved = (digest) => new Saved(digest);
export const Status$isSaved = (value) => value instanceof Saved;
export const Status$Saved$digest = (value) => value.digest;
export const Status$Saved$0 = (value) => value.digest;

export class SaveFailed extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const Status$SaveFailed = (error) => new SaveFailed(error);
export const Status$isSaveFailed = (value) => value instanceof SaveFailed;
export const Status$SaveFailed$error = (value) => value.error;
export const Status$SaveFailed$0 = (value) => value.error;

class Controller extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class State extends $CustomType {
  constructor(save, document, scheduler, on_status, last_saved, dirty, saving, pagehide_pending, debounce, sweep, remove_pagehide, stopped) {
    super();
    this.save = save;
    this.document = document;
    this.scheduler = scheduler;
    this.on_status = on_status;
    this.last_saved = last_saved;
    this.dirty = dirty;
    this.saving = saving;
    this.pagehide_pending = pagehide_pending;
    this.debounce = debounce;
    this.sweep = sweep;
    this.remove_pagehide = remove_pagehide;
    this.stopped = stopped;
  }
}

const debounce_milliseconds = 500;

const sweep_milliseconds = 5000;

function get(controller) {
  let cell = controller.cell;
  return $transport_js.get_cell(cell);
}

function set(controller, state) {
  let cell = controller.cell;
  return $transport_js.set_cell(cell, state);
}

function update(controller, change) {
  return set(controller, change(get(controller)));
}

function cancel(timer) {
  if (timer instanceof Some) {
    let stop$1 = timer[0];
    return stop$1();
  } else {
    return undefined;
  }
}

function arm_debounce(controller) {
  let state = get(controller);
  let $ = (state.stopped || state.saving) || $option.is_some(state.debounce);
  if ($) {
    return undefined;
  } else {
    return $timer_js.arm(
      state.scheduler,
      debounce_milliseconds,
      () => {
        update(
          controller,
          (current) => {
            return new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              current.last_saved,
              current.dirty,
              current.saving,
              current.pagehide_pending,
              Option$None$const,
              current.sweep,
              current.remove_pagehide,
              current.stopped,
            );
          },
        );
        return save_if_changed(controller);
      },
      () => {
        let current = get(controller);
        return (!current.stopped && !current.saving) && $option.is_none(
          current.debounce,
        );
      },
      (cancel) => {
        return update(
          controller,
          (current) => {
            return new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              current.last_saved,
              current.dirty,
              current.saving,
              current.pagehide_pending,
              new Some(cancel),
              current.sweep,
              current.remove_pagehide,
              current.stopped,
            );
          },
        );
      },
    );
  }
}

function arm_debounce_if_needed(controller) {
  let state = get(controller);
  let $ = !state.stopped && (state.dirty || ($crdt_js.digest(state.document) !== state.last_saved));
  if ($) {
    return arm_debounce(controller);
  } else {
    return undefined;
  }
}

function continue_after_save(controller) {
  let state = get(controller);
  let $ = state.pagehide_pending;
  if ($) {
    update(
      controller,
      (current) => {
        return new State(
          current.save,
          current.document,
          current.scheduler,
          current.on_status,
          current.last_saved,
          current.dirty,
          current.saving,
          false,
          current.debounce,
          current.sweep,
          current.remove_pagehide,
          current.stopped,
        );
      },
    );
    let $1 = start_save_if_changed(controller);
    if ($1) {
      return undefined;
    } else {
      return arm_debounce_if_needed(controller);
    }
  } else {
    return arm_debounce_if_needed(controller);
  }
}

function start_save_if_changed(controller) {
  let state = get(controller);
  let digest = $crdt_js.digest(state.document);
  let $ = (state.stopped || state.saving) || (digest === state.last_saved);
  if ($) {
    return false;
  } else {
    cancel(state.debounce);
    set(
      controller,
      new State(
        state.save,
        state.document,
        state.scheduler,
        state.on_status,
        state.last_saved,
        false,
        true,
        state.pagehide_pending,
        Option$None$const,
        state.sweep,
        state.remove_pagehide,
        state.stopped,
      ),
    );
    state.on_status(Status$Saving$const);
    state.save(
      state.document,
      (outcome) => {
        let current = get(controller);
        if (outcome instanceof Ok) {
          let saved_digest = outcome[0];
          set(
            controller,
            new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              saved_digest,
              current.dirty,
              false,
              current.pagehide_pending,
              current.debounce,
              current.sweep,
              current.remove_pagehide,
              current.stopped,
            ),
          );
          current.on_status(new Saved(saved_digest));
        } else {
          let error = outcome[0];
          set(
            controller,
            new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              current.last_saved,
              true,
              false,
              current.pagehide_pending,
              current.debounce,
              current.sweep,
              current.remove_pagehide,
              current.stopped,
            ),
          );
          current.on_status(new SaveFailed(error));
        }
        return continue_after_save(controller);
      },
    );
    return true;
  }
}

function save_if_changed(controller) {
  let $ = start_save_if_changed(controller);
  
  return undefined;
}

function arm_sweep(controller) {
  let state = get(controller);
  let $ = state.stopped || $option.is_some(state.sweep);
  if ($) {
    return undefined;
  } else {
    return $timer_js.arm(
      state.scheduler,
      sweep_milliseconds,
      () => {
        let armed_asynchronously = $option.is_some(get(controller).sweep);
        update(
          controller,
          (current) => {
            return new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              current.last_saved,
              current.dirty,
              current.saving,
              current.pagehide_pending,
              current.debounce,
              Option$None$const,
              current.remove_pagehide,
              current.stopped,
            );
          },
        );
        save_if_changed(controller);
        if (armed_asynchronously) {
          return arm_sweep(controller);
        } else {
          return undefined;
        }
      },
      () => {
        let current = get(controller);
        return !current.stopped && $option.is_none(current.sweep);
      },
      (cancel) => {
        return update(
          controller,
          (current) => {
            return new State(
              current.save,
              current.document,
              current.scheduler,
              current.on_status,
              current.last_saved,
              current.dirty,
              current.saving,
              current.pagehide_pending,
              current.debounce,
              new Some(cancel),
              current.remove_pagehide,
              current.stopped,
            );
          },
        );
      },
    );
  }
}

function request_pagehide_save(controller) {
  let state = get(controller);
  let $ = state.stopped;
  if ($) {
    return undefined;
  } else {
    let $1 = state.saving;
    if ($1) {
      return update(
        controller,
        (current) => {
          return new State(
            current.save,
            current.document,
            current.scheduler,
            current.on_status,
            current.last_saved,
            current.dirty,
            current.saving,
            true,
            current.debounce,
            current.sweep,
            current.remove_pagehide,
            current.stopped,
          );
        },
      );
    } else {
      return save_if_changed(controller);
    }
  }
}

/**
 * An injectable lifecycle and save driver, for deterministic tests.
 */
export function start_with_save(
  document,
  on_status,
  scheduler,
  listen_pagehide,
  save
) {
  let cell = $transport_js.new_cell(
    new State(
      save,
      document,
      scheduler,
      on_status,
      "",
      true,
      false,
      false,
      Option$None$const,
      Option$None$const,
      () => { return undefined; },
      false,
    ),
  );
  let controller = new Controller(cell);
  let remove = listen_pagehide(
    () => { return request_pagehide_save(controller); },
  );
  update(
    controller,
    (state) => {
      return new State(
        state.save,
        state.document,
        state.scheduler,
        state.on_status,
        state.last_saved,
        state.dirty,
        state.saving,
        state.pagehide_pending,
        state.debounce,
        state.sweep,
        remove,
        state.stopped,
      );
    },
  );
  arm_debounce(controller);
  arm_sweep(controller);
  return controller;
}

/**
 * An injectable lifecycle, for deterministic tests.
 */
export function start_with(
  storage,
  document,
  on_status,
  scheduler,
  listen_pagehide
) {
  return start_with_save(
    document,
    on_status,
    scheduler,
    listen_pagehide,
    (document, done) => { return $persist_js.save(storage, document, done); },
  );
}

/**
 * Start a controller that uses the browser timers and the `pagehide` event.
 */
export function start(storage, document, on_status) {
  return start_with(
    storage,
    document,
    on_status,
    $transport_js.real_scheduler(),
    listen_pagehide,
  );
}

/**
 * Report a possible local edit. The digest comparison prevents a write for a
 * message that only moves the selection or changes nothing.
 */
export function changed(controller) {
  update(
    controller,
    (state) => {
      return new State(
        state.save,
        state.document,
        state.scheduler,
        state.on_status,
        state.last_saved,
        true,
        state.saving,
        state.pagehide_pending,
        state.debounce,
        state.sweep,
        state.remove_pagehide,
        state.stopped,
      );
    },
  );
  return arm_debounce(controller);
}

/**
 * Cancel the timers and remove the page lifecycle listener. An IndexedDB
 * write that is already in progress continues and reports its result.
 */
export function stop(controller) {
  let state = get(controller);
  cancel(state.debounce);
  cancel(state.sweep);
  state.remove_pagehide();
  return set(
    controller,
    new State(
      state.save,
      state.document,
      state.scheduler,
      state.on_status,
      state.last_saved,
      state.dirty,
      state.saving,
      state.pagehide_pending,
      Option$None$const,
      Option$None$const,
      state.remove_pagehide,
      true,
    ),
  );
}
