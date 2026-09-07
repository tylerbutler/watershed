import { mock } from "node:test";

export function withTimers(work) {
  mock.timers.enable({ apis: ["setTimeout"] });
  try {
    return work((milliseconds) => mock.timers.tick(milliseconds));
  } finally {
    mock.timers.reset();
  }
}
