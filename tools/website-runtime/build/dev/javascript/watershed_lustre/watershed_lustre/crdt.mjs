/// <reference types="./crdt.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $effect from "../../lustre/lustre/effect.mjs";
import * as $crdt_js from "../../watershed/watershed/crdt_js.mjs";
import * as $g_counter_kernel from "../../watershed/watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../../watershed/watershed/g_set_kernel.mjs";
import * as $lww_map_kernel from "../../watershed/watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../../watershed/watershed/lww_register_kernel.mjs";
import * as $mv_register_kernel from "../../watershed/watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../../watershed/watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "../../watershed/watershed/or_set_kernel.mjs";
import * as $p2p from "../../watershed/watershed/p2p.mjs";
import * as $p2p_transport_js from "../../watershed/watershed/p2p_transport_js.mjs";
import * as $persist_controller_js from "../../watershed/watershed/persist_controller_js.mjs";
import * as $persist_js from "../../watershed/watershed/persist_js.mjs";
import * as $pn_counter_kernel from "../../watershed/watershed/pn_counter_kernel.mjs";
import * as $schema from "../../watershed/watershed/schema.mjs";
import * as $sequence_kernel from "../../watershed/watershed/sequence_kernel.mjs";
import * as $text_kernel from "../../watershed/watershed/text_kernel.mjs";
import * as $two_p_set_kernel from "../../watershed/watershed/two_p_set_kernel.mjs";
import { Ok, CustomType as $CustomType } from "../gleam.mjs";
import { queue_microtask } from "../watershed_lustre_ffi.mjs";

export class NoLocalSnapshot extends $CustomType {}
export const PersistenceStatus$NoLocalSnapshot$const = new NoLocalSnapshot();
export const PersistenceStatus$NoLocalSnapshot = () =>
  PersistenceStatus$NoLocalSnapshot$const;
export const PersistenceStatus$isNoLocalSnapshot = (value) =>
  value instanceof NoLocalSnapshot;

export class LocalSnapshotReady extends $CustomType {}
export const PersistenceStatus$LocalSnapshotReady$const =
  new LocalSnapshotReady();
export const PersistenceStatus$LocalSnapshotReady = () =>
  PersistenceStatus$LocalSnapshotReady$const;
export const PersistenceStatus$isLocalSnapshotReady = (value) =>
  value instanceof LocalSnapshotReady;

export class PersistenceFailed extends $CustomType {
  constructor(error) {
    super();
    this.error = error;
  }
}
export const PersistenceStatus$PersistenceFailed = (error) =>
  new PersistenceFailed(error);
export const PersistenceStatus$isPersistenceFailed = (value) =>
  value instanceof PersistenceFailed;
export const PersistenceStatus$PersistenceFailed$error = (value) => value.error;
export const PersistenceStatus$PersistenceFailed$0 = (value) => value.error;

/**
 * Open from IndexedDB first, and then treat the network as an addition.
 *
 * A valid local snapshot dispatches `ready` before the network can succeed or
 * fail, so a user can edit the application offline immediately. Without a
 * usable local value, this function behaves as the ordinary `connect`. The
 * function reports stored bytes that it cannot load, and it keeps them in
 * storage.
 */
export function open(storage, config, connection, ready, status, persistence) {
  return $effect.from(
    (dispatch) => {
      return $persist_js.load(
        storage,
        config,
        (loaded) => {
          if (loaded instanceof Ok) {
            let $ = loaded[0];
            if ($ instanceof Some) {
              let document = $[0];
              let held = $crdt_js.attach(
                document,
                (_) => { return undefined; },
                (update) => {
                  return queue_microtask(
                    () => {
                      return queue_microtask(
                        () => { return dispatch(status(update)); },
                      );
                    },
                  );
                },
              );
              return queue_microtask(
                () => {
                  dispatch(
                    persistence(PersistenceStatus$LocalSnapshotReady$const),
                  );
                  dispatch(connection(held));
                  return queue_microtask(
                    () => { return dispatch(ready(new Ok(document))); },
                  );
                },
              );
            } else {
              queue_microtask(
                () => {
                  return dispatch(
                    persistence(PersistenceStatus$NoLocalSnapshot$const),
                  );
                },
              );
              let held = $crdt_js.connect(
                config,
                (outcome) => {
                  return queue_microtask(
                    () => {
                      return queue_microtask(
                        () => { return dispatch(ready(outcome)); },
                      );
                    },
                  );
                },
                (update) => {
                  return queue_microtask(
                    () => { return dispatch(status(update)); },
                  );
                },
              );
              return queue_microtask(
                () => { return dispatch(connection(held)); },
              );
            }
          } else {
            let error = loaded[0];
            queue_microtask(
              () => {
                return dispatch(persistence(new PersistenceFailed(error)));
              },
            );
            let held = $crdt_js.connect(
              config,
              (outcome) => {
                return queue_microtask(
                  () => {
                    return queue_microtask(
                      () => { return dispatch(ready(outcome)); },
                    );
                  },
                );
              },
              (update) => {
                return queue_microtask(
                  () => { return dispatch(status(update)); },
                );
              },
            );
            return queue_microtask(() => { return dispatch(connection(held)); });
          }
        },
      );
    },
  );
}

/**
 * The one shape that the three ways to come online share. Run the `crdt_js`
 * call, put its callbacks in a microtask, and deliver the `CrdtConnection`
 * value through `connection`, before `ready`.
 *
 * `ready` goes one microtask *deeper* than everything else. When the readiness
 * resolves synchronously, which occurs for a replica that is alone,
 * `on_ready` runs inside `run`, before the code below can queue the
 * `connection` dispatch. The extra step moves `ready` after that dispatch, so
 * an application always keeps the `CrdtConnection` value before it learns
 * that the room is usable. When the readiness resolves later, the extra step
 * delays `ready` by one microtask only.
 * 
 * @ignore
 */
function establish(run, connection, ready, status) {
  return $effect.from(
    (dispatch) => {
      let held = run(
        (outcome) => {
          return queue_microtask(
            () => {
              return queue_microtask(() => { return dispatch(ready(outcome)); });
            },
          );
        },
        (update) => {
          return queue_microtask(() => { return dispatch(status(update)); });
        },
      );
      return queue_microtask(() => { return dispatch(connection(held)); });
    },
  );
}

/**
 * Join a room. The function builds the document that `Config` describes and
 * connects it. `crdt_js.connect` is synchronous, so the document exists
 * before this effect returns, but its handle arrives through `ready`.
 *
 * `connection` runs one time, with the `CrdtConnection` value to keep in your
 * model. A later `close` call, or a re-`attach` of a snapshot, then has a
 * value to act on. `ready` runs exactly one time. It gives `Ok(document)`
 * when the state of the room merges, or immediately when this replica is
 * alone. It gives `Error(reason)` when the join fails. `status` runs for the
 * whole lifetime of the connection. All three go to a microtask before the
 * dispatch, and `connection` always arrives before `ready`. An application
 * thus holds the handle that `close` needs before it learns that the room is
 * usable.
 */
export function connect(config, connection, ready, status) {
  return establish(
    (on_ready, on_status) => {
      return $crdt_js.connect(config, on_ready, on_status);
    },
    connection,
    ready,
    status,
  );
}

/**
 * Bring a document that already exists online. That document is the one that
 * `import_snapshot` returns, or any `crdt_js.new_document` value. A handle and
 * a subscription that you took before the attach stay valid. The function
 * delivers `connection`, `ready`, and `status` exactly as `connect` does. Each
 * one goes to a microtask, and `connection` arrives first.
 */
export function attach(document, connection, ready, status) {
  return establish(
    (on_ready, on_status) => {
      return $crdt_js.attach(document, on_ready, on_status);
    },
    connection,
    ready,
    status,
  );
}

/**
 * `attach` against a replacement browser seam. A test can thus drive the
 * bootstrap order and the merge behaviour deterministically, and it needs no
 * browser. This is the same seam that `crdt_js.attach_with_rtc` gives, for the
 * same reason. Production code must use `connect` or `attach`.
 */
export function attach_with_rtc(document, connection, ready, status, rtc) {
  return establish(
    (on_ready, on_status) => {
      return $crdt_js.attach_with_rtc(document, on_ready, on_status, rtc);
    },
    connection,
    ready,
    status,
  );
}

/**
 * Leave the signaling, close every peer, remove every subscription, and stop
 * the document. A second call has no more effect. The effect returns nothing.
 * A readiness that is still open resolves through the `ready` callback that
 * opened the connection.
 */
export function close(connection) {
  return $effect.from((_) => { return $crdt_js.close(connection); });
}

/**
 * Start the digest-gated local persistence for a document that is ready.
 */
export function start_persistence(storage, document, started, status) {
  return $effect.from(
    (dispatch) => {
      let controller = $persist_controller_js.start(
        storage,
        document,
        (update) => {
          return queue_microtask(() => { return dispatch(status(update)); });
        },
      );
      return queue_microtask(() => { return dispatch(started(controller)); });
    },
  );
}

/**
 * Tell the save controller that a local mutation can have occurred.
 */
export function persistence_changed(controller) {
  return $effect.from(
    (_) => { return $persist_controller_js.changed(controller); },
  );
}

/**
 * Stop the local persistence timers and the page lifecycle handling.
 */
export function stop_persistence(controller) {
  return $effect.from(
    (_) => { return $persist_controller_js.stop(controller); },
  );
}

/**
 * The one shape that every `subscribe_*` function shares. Take the `crdt_js`
 * subscribe function of that kind, with its handler not applied yet, put each
 * event in a microtask, and deliver the `Subscription` value through
 * `subscribed`, also in a microtask.
 * 
 * @ignore
 */
function subscribe(run, subscribed, event) {
  return $effect.from(
    (dispatch) => {
      let subscription = run(
        (inner) => {
          return queue_microtask(() => { return dispatch(event(inner)); });
        },
      );
      return queue_microtask(
        () => { return dispatch(subscribed(subscription)); },
      );
    },
  );
}

/**
 * Subscribe to a peer-to-peer PN counter. `event` receives every local and
 * remote `pn_counter_kernel.PnCounterEvent` value.
 */
export function subscribe_pn_counter(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_pn_counter(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer grow-only counter. `event` receives every local
 * and remote `g_counter_kernel.GCounterEvent` value.
 */
export function subscribe_g_counter(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_g_counter(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to visible map changes. Metadata-only edits emit no event.
 */
export function subscribe_lww_map(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_lww_map(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to local and remote visible-value changes in a peer-to-peer LWW
 * register.
 */
export function subscribe_lww_register(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_lww_register(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to changes in the peer-to-peer register alternatives.
 */
export function subscribe_mv_register(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_mv_register(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer OR-map. In `OrSetMode`, `SetMembersUpdated`
 * carries sorted members. A metadata-only add emits no visible-value event.
 * Retain the delivered subscription for `unsubscribe`.
 */
export function subscribe_or_map(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_or_map(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer OR-set.
 */
export function subscribe_or_set(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_or_set(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer grow-only set. `ElementAdded` is the only event
 * that this channel produces, because a G-set has no remove operation.
 */
export function subscribe_g_set(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_g_set(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer two-phase set, which produces `ElementAdded`
 * and `ElementRemoved`. A removal is permanent. You cannot add an element
 * again after you remove it.
 */
export function subscribe_two_p_set(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_two_p_set(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer sequence. `event` receives every
 * `sequence_kernel.SequenceEvent` value, which carries the full list of
 * values after the edit. An insert, a delete, a move, and a replace all
 * arrive in the same form.
 */
export function subscribe_sequence(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_sequence(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Subscribe to a peer-to-peer text channel. `event` receives every
 * `text_kernel.TextEvent` value, which is a `TextChanged` event that carries
 * the full string after the edit. An insert, a delete, a replace, and an
 * append all arrive in the same form.
 */
export function subscribe_text(handle, subscribed, event) {
  return subscribe(
    (_capture) => { return $crdt_js.subscribe_text(handle, _capture); },
    subscribed,
    event,
  );
}

/**
 * Remove one subscription from the functions above. A second call has no more
 * effect. Use this function to clean up one channel while the document stays
 * connected. `close` removes every subscription.
 */
export function unsubscribe(subscription) {
  return $effect.from((_) => { return $crdt_js.unsubscribe(subscription); });
}

/**
 * Run one effectful `crdt_js` operation *when Lustre performs the effect*,
 * and never when your code builds that effect inside `update`. The function
 * then delivers the result through the message constructor of the caller, in
 * a microtask. The outcome thus reaches `dispatch` in the same way as every
 * other callback here. `operation` is a thunk, so the edit, the broadcast,
 * and the fan-out to the subscribers all happen in the effect phase, and not
 * while `update` still runs.
 *
 * Compose this function with a typed `crdt_js` edit.
 * The `or_map_set_mv_register` convenience function uses this helper.
 *
 * ```gleam
 * crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
 * crdt.perform(fn() { crdt_js.or_map_set(map, key: "k", value: "v") }, Wrote)
 * ```
 *
 * A string-set map uses the same handle and subscription with `OrSetMode`:
 *
 * ```gleam
 * crdt.perform(
 *   fn() { crdt_js.or_map_add_member(map, "inspection-brief", "reviewed") },
 *   Outcome,
 * )
 * crdt.perform(
 *   fn() { crdt_js.or_map_remove_member(map, "inspection-brief", "draft") },
 *   Outcome,
 * )
 * crdt.perform(
 *   fn() { crdt_js.or_map_remove_key(map, "inspection-brief") },
 *   Outcome,
 * )
 * ```
 *
 * Removing the last member retains an empty key. Key removal also clears
 * observed members. Concurrent unobserved additions survive.
 *
 * The function passes the `Result` value through without a change. An edit
 * that the channel does not support, or that is invalid, stays an `Error`. It
 * never becomes an `Ok`.
 */
export function perform(operation, outcome) {
  return $effect.from(
    (dispatch) => {
      let result = operation();
      return queue_microtask(() => { return dispatch(outcome(result)); });
    },
  );
}

/**
 * Replace observed alternatives in the effect phase and defer the result.
 */
export function or_map_set_mv_register(handle, key, value, outcome) {
  return perform(
    () => { return $crdt_js.or_map_set_mv_register(handle, key, value); },
    outcome,
  );
}

/**
 * Export the whole snapshot that `import_snapshot` can read, which is the full
 * CRDT state of every channel in canonical order, and deliver it through
 * `exported`, in a microtask. The moment of the capture is effectful, because
 * it reads the live state of the document. This is thus an effect, and not a
 * pure read. Dispatch it when you intend to store the result.
 */
export function export_snapshot(document, exported) {
  return perform(() => { return $crdt_js.export_snapshot(document); }, exported);
}

/**
 * Build a detached document again from an exported snapshot, and deliver it
 * through `imported`, in a microtask. The function checks the size, the
 * protocol, the room, the compatibility, the root type, and the eligibility of
 * every channel, before it loads a channel. On an `Ok` result, give the
 * document to `attach` to bring it online.
 */
export function import_snapshot(config, snapshot, imported) {
  return perform(
    () => { return $crdt_js.import_snapshot(config, snapshot); },
    imported,
  );
}
