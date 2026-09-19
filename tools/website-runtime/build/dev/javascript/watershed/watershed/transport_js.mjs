/// <reference types="./transport_js.d.mts" />
import * as $promise from "../../gleam_javascript/gleam/javascript/promise.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";
import {
  connect,
  push,
  dropSocket as drop_socket,
  holdSocket as hold_socket,
  resumeSocket as resume_socket,
  close,
  newCell as new_cell,
  getCell as get_cell,
  setCell as set_cell,
  nowMs as now_milliseconds,
  setTimer as set_timer,
  clearTimer as clear_timer,
  mintDevToken as mint_dev_token,
} from "./transport_ffi.mjs";

export {
  clear_timer,
  close,
  connect,
  drop_socket,
  get_cell,
  hold_socket,
  mint_dev_token,
  new_cell,
  now_milliseconds,
  push,
  resume_socket,
  set_cell,
  set_timer,
};

export class Scheduler extends $CustomType {
  constructor(now_milliseconds, schedule) {
    super();
    this.now_milliseconds = now_milliseconds;
    this.schedule = schedule;
  }
}
export const Scheduler$Scheduler = (now_milliseconds, schedule) =>
  new Scheduler(now_milliseconds, schedule);
export const Scheduler$isScheduler = (value) => value instanceof Scheduler;
export const Scheduler$Scheduler$now_milliseconds = (value) =>
  value.now_milliseconds;
export const Scheduler$Scheduler$0 = (value) => value.now_milliseconds;
export const Scheduler$Scheduler$schedule = (value) => value.schedule;
export const Scheduler$Scheduler$1 = (value) => value.schedule;

/**
 * The real clock and `setTimeout`.
 */
export function real_scheduler() {
  return new Scheduler(
    now_milliseconds,
    (action, milliseconds) => {
      let id = set_timer(action, milliseconds);
      return () => { return clear_timer(id); };
    },
  );
}
