/// <reference types="./presence_js.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, CustomType as $CustomType } from "../gleam.mjs";
import * as $watershed from "../watershed.mjs";
import * as $presence from "../watershed/presence.mjs";
import * as $runtime from "../watershed/runtime.mjs";
import * as $transport_js from "../watershed/transport_js.mjs";

class Handle extends $CustomType {
  constructor(cell) {
    super();
    this.cell = cell;
  }
}

class Driver extends $CustomType {
  constructor(runtime, broadcast, config, on_event, scheduler, meta, mode, session, key, implementation, stopped) {
    super();
    this.runtime = runtime;
    this.broadcast = broadcast;
    this.config = config;
    this.on_event = on_event;
    this.scheduler = scheduler;
    this.meta = meta;
    this.mode = mode;
    this.session = session;
    this.key = key;
    this.implementation = implementation;
    this.stopped = stopped;
  }
}

class Unresolved extends $CustomType {}
const Implementation$Unresolved$const = new Unresolved();

class ServerPresence extends $CustomType {
  constructor(tracker) {
    super();
    this.tracker = tracker;
  }
}

class RipplePresence extends $CustomType {
  constructor(sessions, cancel) {
    super();
    this.sessions = sessions;
    this.cancel = cancel;
  }
}

/**
 * Report a change. If nothing changed, report nothing, because a heartbeat
 * alone must not cause a re-render.
 * 
 * @ignore
 */
function report(cell, sessions, diff) {
  let $ = $presence.diff_is_empty(diff);
  if ($) {
    return undefined;
  } else {
    return $transport_js.get_cell(cell).on_event(
      new $presence.Changed(diff, $presence.session_entries(sessions)),
    );
  }
}

function commit_ripple(cell, sessions, cancel) {
  let driver = $transport_js.get_cell(cell);
  return $transport_js.set_cell(
    cell,
    new Driver(
      driver.runtime,
      driver.broadcast,
      driver.config,
      driver.on_event,
      driver.scheduler,
      driver.meta,
      driver.mode,
      driver.session,
      driver.key,
      new RipplePresence(sessions, cancel),
      driver.stopped,
    ),
  );
}

/**
 * An inbound ripple. The session id comes from the *server-stamped* client id
 * of the ripple, and never from the payload, so a sender cannot select its own
 * session. The driver drops a ripple without that id, because it cannot
 * attribute the ripple. It also drops a foreign kind and malformed metadata. A
 * ripple is best-effort input, and any peer on the document can emit one.
 * 
 * @ignore
 */
function on_ripple(cell, ripple) {
  let driver = $transport_js.get_cell(cell);
  let $ = driver.stopped;
  let $1 = driver.implementation;
  if ($) {
    return undefined;
  } else if ($1 instanceof Unresolved) {
    return undefined;
  } else if ($1 instanceof ServerPresence) {
    return undefined;
  } else {
    let sessions = $1.sessions;
    let cancel = $1.cancel;
    let $2 = $watershed.ripple_client_id(ripple);
    let $3 = $json.parse(
      $json.to_string($watershed.ripple_content(ripple)),
      $presence.ripple_decoder($presence.config_decoder(driver.config)),
    );
    if ($2 instanceof Some && $3 instanceof Ok) {
      let session_id = $2[0];
      let key = $3[0][0];
      let meta = $3[0][1];
      let clock = driver.scheduler.now_milliseconds;
      let $4 = $presence.observe_session(
        sessions,
        session_id,
        key,
        meta,
        clock(),
      );
      let sessions$1 = $4[0];
      let diff = $4[1];
      commit_ripple(cell, sessions$1, cancel);
      return report(cell, sessions$1, diff);
    } else {
      return undefined;
    }
  }
}

function commit_server(cell, tracker, events) {
  let driver = $transport_js.get_cell(cell);
  $transport_js.set_cell(
    cell,
    new Driver(
      driver.runtime,
      driver.broadcast,
      driver.config,
      driver.on_event,
      driver.scheduler,
      driver.meta,
      driver.mode,
      driver.session,
      driver.key,
      new ServerPresence(tracker),
      driver.stopped,
    ),
  );
  return $list.each(events, driver.on_event);
}

/**
 * The connection closed. In server mode the tracker returns to the unsynced
 * state. A diff that arrives before the next snapshot thus queues. It does not
 * apply to a roster that no longer exists.
 *
 * The driver emits no event. A report of an empty roster on every short socket
 * failure would clear the interface for an interval that the next snapshot
 * closes in milliseconds.
 * 
 * @ignore
 */
function on_session_lost(cell) {
  let driver = $transport_js.get_cell(cell);
  let $ = driver.implementation;
  if ($ instanceof Unresolved) {
    return undefined;
  } else if ($ instanceof ServerPresence) {
    let tracker = $.tracker;
    return $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        driver.mode,
        Option$None$const,
        driver.key,
        new ServerPresence($presence.reset(tracker)),
        driver.stopped,
      ),
    );
  } else {
    let sessions = $.sessions;
    let cancel = $.cancel;
    let _block;
    let $2 = driver.session;
    if ($2 instanceof Some) {
      let session = $2[0];
      _block = $presence.forget_session(sessions, session);
    } else {
      _block = [sessions, $presence.no_change()];
    }
    let $1 = _block;
    let sessions$1 = $1[0];
    return $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        driver.mode,
        Option$None$const,
        driver.key,
        new RipplePresence(sessions$1, cancel),
        driver.stopped,
      ),
    );
  }
}

function broadcast_ripple(cell, meta) {
  let driver = $transport_js.get_cell(cell);
  return driver.broadcast(
    $presence.encode_ripple(
      driver.key,
      $presence.config_encode(driver.config),
      meta,
    ),
  );
}

function schedule(cell) {
  let driver = $transport_js.get_cell(cell);
  let $ = driver.implementation;
  if ($ instanceof Unresolved) {
    return undefined;
  } else if ($ instanceof ServerPresence) {
    return undefined;
  } else {
    let sessions = $.sessions;
    let previous = $.cancel;
    if (previous instanceof Some) {
      let cancel = previous[0];
      cancel();
    } else {
      undefined;
    }
    let arm = driver.scheduler.schedule;
    let cancel = arm(
      () => { return tick(cell); },
      $presence.config_heartbeat_milliseconds(driver.config),
    );
    return $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        driver.mode,
        driver.session,
        driver.key,
        new RipplePresence(sessions, new Some(cancel)),
        driver.stopped,
      ),
    );
  }
}

/**
 * One heartbeat. Refresh the local entry, remove the silent peers, broadcast,
 * and arm the timer again.
 *
 * The function refreshes the local entry, and it does not treat that entry as
 * a special case. A client never receives its own ripple, so nothing else
 * would keep the entry alive. The presence state includes the local session by
 * design.
 * 
 * @ignore
 */
function tick(cell) {
  let driver = $transport_js.get_cell(cell);
  let $ = driver.stopped;
  let $1 = driver.implementation;
  if ($) {
    return undefined;
  } else if ($1 instanceof Unresolved) {
    return undefined;
  } else if ($1 instanceof ServerPresence) {
    return undefined;
  } else {
    let sessions = $1.sessions;
    let cancel = $1.cancel;
    let clock = driver.scheduler.now_milliseconds;
    let now = clock();
    let _block;
    let $3 = driver.session;
    if ($3 instanceof Some) {
      let session = $3[0];
      _block = $presence.observe_session(
        sessions,
        session,
        driver.key,
        driver.meta,
        now,
      );
    } else {
      _block = [sessions, $presence.no_change()];
    }
    let $2 = _block;
    let sessions$1 = $2[0];
    let joined = $2[1];
    let $4 = $presence.expire_sessions(
      sessions$1,
      $presence.config_ttl_milliseconds(driver.config),
      now,
    );
    let sessions$2 = $4[0];
    let expired = $4[1];
    commit_ripple(cell, sessions$2, cancel);
    report(cell, sessions$2, joined);
    report(cell, sessions$2, expired);
    broadcast_ripple(cell, driver.meta);
    return schedule(cell);
  }
}

function runtime_of(driver) {
  return driver.runtime;
}

function push(cell, event, meta) {
  let driver = $transport_js.get_cell(cell);
  return $runtime.send_presence(
    runtime_of(driver),
    event,
    $presence.encode_command($presence.config_encode(driver.config), meta),
  );
}

/**
 * A handshake settled. Resolve the mode if it is not resolved yet, take the
 * new session id, and join again.
 * 
 * @ignore
 */
function on_session(cell, client_id, presence_v1) {
  let driver = $transport_js.get_cell(cell);
  let _block;
  let $ = driver.mode;
  if ($ instanceof Some) {
    let mode$1 = $[0];
    _block = mode$1;
  } else {
    let $1 = $presence.config_mode(driver.config);
    if ($1 instanceof $presence.Auto) {
      if (presence_v1) {
        _block = $presence.Mode$Server$const;
      } else {
        _block = $presence.Mode$Ripple$const;
      }
    } else if ($1 instanceof $presence.Server) {
      _block = $1;
    } else {
      _block = $1;
    }
  }
  let resolved = _block;
  if (presence_v1) {
    if (resolved instanceof $presence.Auto) {
      let _block$1;
      let $1 = driver.implementation;
      if ($1 instanceof Unresolved) {
        _block$1 = $presence.sessions();
      } else if ($1 instanceof ServerPresence) {
        _block$1 = $presence.sessions();
      } else {
        let sessions = $1.sessions;
        let cancel = $1.cancel;
        if (cancel instanceof Some) {
          let cancel$1 = cancel[0];
          cancel$1();
        } else {
          undefined;
        }
        _block$1 = sessions;
      }
      let sessions = _block$1;
      $transport_js.set_cell(
        cell,
        new Driver(
          driver.runtime,
          driver.broadcast,
          driver.config,
          driver.on_event,
          driver.scheduler,
          driver.meta,
          new Some(resolved),
          new Some(client_id),
          driver.key,
          new RipplePresence(sessions, Option$None$const),
          driver.stopped,
        ),
      );
      return tick(cell);
    } else if (resolved instanceof $presence.Server) {
      $transport_js.set_cell(
        cell,
        new Driver(
          driver.runtime,
          driver.broadcast,
          driver.config,
          driver.on_event,
          driver.scheduler,
          driver.meta,
          new Some(resolved),
          new Some(client_id),
          driver.key,
          new ServerPresence($presence.tracker()),
          driver.stopped,
        ),
      );
      return push(cell, $presence.event_join, driver.meta);
    } else {
      let _block$1;
      let $1 = driver.implementation;
      if ($1 instanceof Unresolved) {
        _block$1 = $presence.sessions();
      } else if ($1 instanceof ServerPresence) {
        _block$1 = $presence.sessions();
      } else {
        let sessions = $1.sessions;
        let cancel = $1.cancel;
        if (cancel instanceof Some) {
          let cancel$1 = cancel[0];
          cancel$1();
        } else {
          undefined;
        }
        _block$1 = sessions;
      }
      let sessions = _block$1;
      $transport_js.set_cell(
        cell,
        new Driver(
          driver.runtime,
          driver.broadcast,
          driver.config,
          driver.on_event,
          driver.scheduler,
          driver.meta,
          new Some(resolved),
          new Some(client_id),
          driver.key,
          new RipplePresence(sessions, Option$None$const),
          driver.stopped,
        ),
      );
      return tick(cell);
    }
  } else if (resolved instanceof $presence.Auto) {
    let _block$1;
    let $1 = driver.implementation;
    if ($1 instanceof Unresolved) {
      _block$1 = $presence.sessions();
    } else if ($1 instanceof ServerPresence) {
      _block$1 = $presence.sessions();
    } else {
      let sessions = $1.sessions;
      let cancel = $1.cancel;
      if (cancel instanceof Some) {
        let cancel$1 = cancel[0];
        cancel$1();
      } else {
        undefined;
      }
      _block$1 = sessions;
    }
    let sessions = _block$1;
    $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        new Some(resolved),
        new Some(client_id),
        driver.key,
        new RipplePresence(sessions, Option$None$const),
        driver.stopped,
      ),
    );
    return tick(cell);
  } else if (resolved instanceof $presence.Server) {
    $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        new Some(resolved),
        driver.session,
        driver.key,
        driver.implementation,
        true,
      ),
    );
    return driver.on_event(
      new $presence.Failed($presence.PresenceError$UnsupportedPresence$const),
    );
  } else {
    let _block$1;
    let $1 = driver.implementation;
    if ($1 instanceof Unresolved) {
      _block$1 = $presence.sessions();
    } else if ($1 instanceof ServerPresence) {
      _block$1 = $presence.sessions();
    } else {
      let sessions = $1.sessions;
      let cancel = $1.cancel;
      if (cancel instanceof Some) {
        let cancel$1 = cancel[0];
        cancel$1();
      } else {
        undefined;
      }
      _block$1 = sessions;
    }
    let sessions = _block$1;
    $transport_js.set_cell(
      cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        new Some(resolved),
        new Some(client_id),
        driver.key,
        new RipplePresence(sessions, Option$None$const),
        driver.stopped,
      ),
    );
    return tick(cell);
  }
}

function on_frame(cell, frame) {
  let driver = $transport_js.get_cell(cell);
  let $ = driver.stopped;
  if ($) {
    return undefined;
  } else {
    if (frame instanceof $runtime.PresenceState) {
      let payload = frame.payload;
      let $1 = driver.implementation;
      if ($1 instanceof Unresolved) {
        return undefined;
      } else if ($1 instanceof ServerPresence) {
        let tracker = $1.tracker;
        let $2 = $json.parse(
          payload,
          $presence.presence_state_decoder(
            $presence.config_decoder(driver.config),
          ),
        );
        if ($2 instanceof Ok) {
          let snapshot = $2[0];
          let $3 = $presence.apply_state(tracker, snapshot);
          let next = $3[0];
          let events = $3[1];
          return commit_server(cell, next, events);
        } else {
          return undefined;
        }
      } else {
        return undefined;
      }
    } else if (frame instanceof $runtime.PresenceDiff) {
      let payload = frame.payload;
      let $1 = driver.implementation;
      if ($1 instanceof Unresolved) {
        return undefined;
      } else if ($1 instanceof ServerPresence) {
        let tracker = $1.tracker;
        let $2 = $json.parse(
          payload,
          $presence.presence_diff_decoder(
            $presence.config_decoder(driver.config),
          ),
        );
        if ($2 instanceof Ok) {
          let diff = $2[0];
          let $3 = $presence.apply_diff(tracker, diff);
          let next = $3[0];
          let events = $3[1];
          return commit_server(cell, next, events);
        } else {
          return undefined;
        }
      } else {
        return undefined;
      }
    } else if (frame instanceof $runtime.PresenceError) {
      let payload = frame.payload;
      let $1 = $json.parse(payload, $presence.presence_error_decoder());
      if ($1 instanceof Ok) {
        let error = $1[0];
        return driver.on_event(new $presence.Failed(error));
      } else {
        return undefined;
      }
    } else if (frame instanceof $runtime.PresenceSession) {
      let client_id = frame.client_id;
      let presence_v1 = frame.presence_v1;
      return on_session(cell, client_id, presence_v1);
    } else {
      return on_session_lost(cell);
    }
  }
}

/**
 * `start`, but with a supplied clock and timer. Give `sluice_js.scheduler` to
 * advance a heartbeat or a TTL with the logical clock of a test, instead of a
 * wait for the real time.
 */
export function start_with_scheduler(
  document,
  config,
  initial,
  on_event,
  scheduler
) {
  let runtime = $watershed.runtime_of(document);
  let cell = $transport_js.new_cell(
    new Driver(
      runtime,
      (content) => {
        return $watershed.submit_ripple(
          document,
          $presence.ripple_type,
          content,
        );
      },
      config,
      on_event,
      scheduler,
      initial,
      Option$None$const,
      Option$None$const,
      $runtime.user_id(runtime),
      Implementation$Unresolved$const,
      false,
    ),
  );
  $runtime.subscribe_presence(
    runtime,
    (frame) => { return on_frame(cell, frame); },
  );
  $watershed.subscribe_ripples(
    document,
    (ripple) => { return on_ripple(cell, ripple); },
  );
  return new Handle(cell);
}

/**
 * Start to track presence on `document`, with `initial` as the metadata of
 * this client.
 *
 * The metadata is a required argument, and not a separate announcement. There
 * is thus no interval in which the handle runs but has no metadata to send.
 */
export function start(document, config, initial, on_event) {
  return start_with_scheduler(
    document,
    config,
    initial,
    on_event,
    $transport_js.real_scheduler(),
  );
}

/**
 * Replace the metadata of this client. In server mode the driver pushes the
 * change immediately. In ripple mode the next heartbeat carries it, and the
 * peers see the change as a leave and then a join.
 */
export function update(handle, meta) {
  let driver = $transport_js.get_cell(handle.cell);
  let $ = driver.stopped;
  if ($) {
    return undefined;
  } else {
    $transport_js.set_cell(
      handle.cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        meta,
        driver.mode,
        driver.session,
        driver.key,
        driver.implementation,
        driver.stopped,
      ),
    );
    let $1 = driver.implementation;
    let $2 = driver.session;
    if ($2 instanceof Some) {
      if ($1 instanceof Unresolved) {
        return undefined;
      } else if ($1 instanceof ServerPresence) {
        return push(handle.cell, $presence.event_update, meta);
      } else {
        return broadcast_ripple(handle.cell, meta);
      }
    } else if ($1 instanceof Unresolved) {
      return undefined;
    } else if ($1 instanceof ServerPresence) {
      return undefined;
    } else {
      return broadcast_ripple(handle.cell, meta);
    }
  }
}

/**
 * Stop the tracking. In server mode the client leaves immediately. In ripple
 * mode the peers see the departure when the TTL expires, because there is no
 * message to send.
 */
export function stop(handle) {
  let driver = $transport_js.get_cell(handle.cell);
  let $ = driver.stopped;
  if ($) {
    return undefined;
  } else {
    let $1 = driver.implementation;
    if ($1 instanceof Unresolved) {
      undefined;
    } else if ($1 instanceof ServerPresence) {
      $runtime.send_presence(
        runtime_of(driver),
        $presence.event_leave,
        $presence.encode_leave(),
      );
    } else {
      let cancel = $1.cancel;
      if (cancel instanceof Some) {
        let cancel$1 = cancel[0];
        cancel$1();
      } else {
        undefined;
      }
    }
    return $transport_js.set_cell(
      handle.cell,
      new Driver(
        driver.runtime,
        driver.broadcast,
        driver.config,
        driver.on_event,
        driver.scheduler,
        driver.meta,
        driver.mode,
        driver.session,
        driver.key,
        driver.implementation,
        true,
      ),
    );
  }
}

/**
 * The implementation that this handle resolved to. The result is `None`
 * before the first handshake settles. Use this function for diagnostics and
 * tests. The two modes fail at different times, and you cannot debug that
 * difference if the mode is hidden.
 */
export function mode(handle) {
  return $transport_js.get_cell(handle.cell).mode;
}

/**
 * The session id of this client, for `presence.remote_entries`. The result is
 * `None` before the first handshake.
 */
export function local_session(handle) {
  return $transport_js.get_cell(handle.cell).session;
}
