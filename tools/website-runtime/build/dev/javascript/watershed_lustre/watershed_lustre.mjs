/// <reference types="./watershed_lustre.d.mts" />
import * as $promise from "../gleam_javascript/gleam/javascript/promise.mjs";
import * as $json from "../gleam_json/gleam/json.mjs";
import * as $effect from "../lustre/lustre/effect.mjs";
import * as $watershed from "../watershed/watershed.mjs";
import { WatershedConfig } from "../watershed/watershed.mjs";
import * as $claim_outcome_js from "../watershed/watershed/claim_outcome_js.mjs";
import * as $claims_kernel from "../watershed/watershed/claims_kernel.mjs";
import * as $counter_kernel from "../watershed/watershed/counter_kernel.mjs";
import * as $directory_kernel from "../watershed/watershed/directory_kernel.mjs";
import * as $g_counter_kernel from "../watershed/watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../watershed/watershed/g_set_kernel.mjs";
import * as $json_ot_kernel from "../watershed/watershed/json_ot_kernel.mjs";
import * as $lww_map_kernel from "../watershed/watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../watershed/watershed/lww_register_kernel.mjs";
import * as $map_kernel from "../watershed/watershed/map_kernel.mjs";
import * as $mv_register_kernel from "../watershed/watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../watershed/watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "../watershed/watershed/or_set_kernel.mjs";
import * as $ordered_collection_kernel from "../watershed/watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "../watershed/watershed/pact_map_kernel.mjs";
import * as $pn_counter_kernel from "../watershed/watershed/pn_counter_kernel.mjs";
import * as $presence from "../watershed/watershed/presence.mjs";
import * as $presence_js from "../watershed/watershed/presence_js.mjs";
import * as $register_collection_kernel from "../watershed/watershed/register_collection_kernel.mjs";
import * as $rich_text_kernel from "../watershed/watershed/rich_text_kernel.mjs";
import * as $runtime from "../watershed/watershed/runtime.mjs";
import * as $schema from "../watershed/watershed/schema.mjs";
import * as $sequence_kernel from "../watershed/watershed/sequence_kernel.mjs";
import * as $summary_policy from "../watershed/watershed/summary_policy.mjs";
import * as $task_manager_kernel from "../watershed/watershed/task_manager_kernel.mjs";
import * as $text_kernel from "../watershed/watershed/text_kernel.mjs";
import * as $two_p_set_kernel from "../watershed/watershed/two_p_set_kernel.mjs";
import { queue_microtask, set_timeout } from "./watershed_lustre_ffi.mjs";

/**
 * Connect to a document. `got_document` runs with the handle immediately. You
 * can start a root subscription and an optimistic edit at that point. To
 * create a nested channel, wait for `connected`. That callback runs with
 * `Ok(Nil)` after the handshake and the history replay complete, or with
 * `Error(reason)` when the server refuses the connection. This effect owns the
 * microtask for both callbacks.
 */
export function connect(config, got_document, connected) {
  return $effect.from(
    (dispatch) => {
      let document = $watershed.connect(
        config,
        (result) => {
          return queue_microtask(() => { return dispatch(connected(result)); });
        },
      );
      return queue_microtask(() => { return dispatch(got_document(document)); });
    },
  );
}

/**
 * The development form of `connect`. It creates the HS256 development token
 * from the tenant secret before it connects. That step is asynchronous,
 * through Web Crypto, and this effect handles the promise. Do not use this
 * function in production. The tenant secret must never reach the browser
 * there. Issue the tokens from a backend, and call `connect` instead.
 */
export function connect_dev(
  url,
  tenant,
  secret,
  document_id,
  user_id,
  got_document,
  connected
) {
  return $effect.from(
    (dispatch) => {
      let $ = $promise.map(
        $watershed.dev_token(secret, tenant, document_id, user_id),
        (token) => {
          let config = new WatershedConfig(
            url,
            tenant,
            document_id,
            token,
            user_id,
          );
          let document = $watershed.connect(
            config,
            (result) => {
              return queue_microtask(
                () => { return dispatch(connected(result)); },
              );
            },
          );
          return queue_microtask(
            () => { return dispatch(got_document(document)); },
          );
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a map channel. `to_msg` receives every local and remote
 * `map_kernel.MapEvent` value.
 */
export function subscribe(map, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe(
        map,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a directory channel. Every event carries the `path` of the
 * subdirectory that it happened in, so one subscription covers the whole
 * tree: the value writes, the clears, and the creation and deletion of a
 * subdirectory.
 */
export function subscribe_directory(directory, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_directory(
        directory,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a counter channel.
 */
export function subscribe_counter(counter, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_counter(
        counter,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to an OR-map channel. In `OrSetMode`, `SetMembersUpdated` carries
 * sorted members. A metadata-only add emits no visible-value event.
 */
export function subscribe_or_map(or_map, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_or_map(
        or_map,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Replace observed alternatives when Lustre performs the effect.
 * A subscription delivers the resulting event in a microtask.
 */
export function or_map_set_mv_register(or_map, key, value) {
  return $effect.from(
    (_) => { return $watershed.or_map_set_mv_register(or_map, key, value); },
  );
}

/**
 * Subscribe to an OR-set channel.
 */
export function subscribe_or_set(or_set, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_or_set(
        or_set,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a grow-only set. `ElementAdded` is the only event that this
 * channel produces, because a G-set has no remove operation.
 */
export function subscribe_g_set(g_set, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_g_set(
        g_set,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a two-phase set, which produces `ElementAdded` and
 * `ElementRemoved`. A removal is permanent. You cannot add an element again
 * after you remove it.
 */
export function subscribe_two_p_set(two_p_set, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_two_p_set(
        two_p_set,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to visible map changes. Metadata-only edits emit no event.
 */
export function subscribe_lww_map(map, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_lww_map(
        map,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to local and remote visible-value changes in an LWW register.
 */
export function subscribe_lww_register(register, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_lww_register(
        register,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to changes in the register alternatives.
 */
export function subscribe_mv_register(register, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_mv_register(
        register,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a PN-counter channel.
 */
export function subscribe_pn_counter(pn_counter, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_pn_counter(
        pn_counter,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a grow-only counter channel.
 */
export function subscribe_g_counter(g_counter, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_g_counter(
        g_counter,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to the consensus transitions of a PactMap, which are `WentPending`
 * and `WentAccepted`.
 */
export function subscribe_pact_map(pact_map, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_pact_map(
        pact_map,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to the queue events of an ordered collection.
 */
export function subscribe_ordered_collection(collection, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_ordered_collection(
        collection,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Acquire the head of an ordered collection, and deliver the consensus outcome
 * as a message.
 *
 * The outcome is `AcquiredItem` when this client won the head. That message
 * carries the acquire id for the later complete or release. The outcome is
 * `QueueEmpty` when the queue became empty before the operation sequenced. An
 * acquire that loses emits no event, so `QueueEmpty` is the only signal that a
 * loser receives. The outcome is `Aborted` when the document closes while the
 * acquire is still in flight.
 *
 * The queue is not optimistic. Nothing changes until the operation sequences,
 * so render the interval as pending.
 */
export function ordered_acquire(collection, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.ordered_acquire_with_outcome(
        collection,
        (outcome) => {
          return queue_microtask(() => { return dispatch(to_msg(outcome)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a register collection channel.
 */
export function subscribe_register_collection(collection, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_register_collection(
        collection,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a claims channel.
 */
export function subscribe_claims(claims, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_claims(
        claims,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * The shared code of `claim_once` and `compare_and_set_claim`.
 *
 * Two synchronous replies never reach the wire: `AlreadyClaimed` and
 * `AlreadyPendingLocally`. Each one resolves to an immediate outcome. The
 * asynchronous reply, which is `Pending`, resolves when its promise settles.
 * Both paths use the same microtask as every other binding in this module.
 *
 * `WrongChannelType` covers two different runtime replies. In the first, the
 * address does not name a claims channel. A typed `ClaimsChannel` field always
 * resolves a real channel, so that reply is unreachable through one. In the
 * second, the runtime is neither `Ready` nor `Reconnecting`, because it is
 * still connecting or it is permanently `Failed`. That reply *is* reachable,
 * for example when a click on a claim races a disconnect.
 *
 * Both replies become `Aborted`. A fifth outcome would add nothing, because a
 * caller would act on the two in the same way: something prevented this
 * attempt from reaching the wire.
 * 
 * @ignore
 */
function deliver_claim_outcome(reply, resolve) {
  return $claim_outcome_js.observe(
    reply,
    (outcome) => { return queue_microtask(() => { return resolve(outcome); }); },
  );
}

/**
 * Attempt a first-writer-wins claim on `key`, and deliver the outcome as a
 * message. A claims read is not optimistic. Nothing in the view that this
 * client has of `key` changes until the outcome arrives. Render the interval
 * between this call and its message as pending.
 *
 * `to_msg` receives exactly one `claims_kernel.ClaimOutcome` value. It is
 * `Accepted` when the value of this client won. It is `Lost` when another
 * client already claimed the key, either synchronously, because a committed
 * claim existed at the time of this call, or after the operation sequences,
 * because a concurrent attempt won the race. It is `Aborted` when the client
 * could not submit the claim at all, because it is still connecting or it
 * failed permanently. A caller must not treat `Aborted` as "nothing happened".
 * Report it, the same as any other connection failure.
 */
export function claim_once(claims, key, value, to_msg) {
  return $effect.from(
    (dispatch) => {
      return deliver_claim_outcome(
        $watershed.claim_once(claims, key, value),
        (outcome) => { return dispatch(to_msg(outcome)); },
      );
    },
  );
}

/**
 * A compare-and-set claim on `key`. It takes the key from the client that
 * holds it now, if no write has sequenced after the committed entry that this
 * call reads its `reference_sequence_number` from. It delivers its outcome in
 * the same way as `claim_once`. Here `Lost` means that a concurrent attempt to
 * take the key won the race. It does not mean that another client already
 * claimed the key.
 */
export function compare_and_set_claim(claims, key, value, to_msg) {
  return $effect.from(
    (dispatch) => {
      return deliver_claim_outcome(
        $watershed.compare_and_set_claim(claims, key, value),
        (outcome) => { return dispatch(to_msg(outcome)); },
      );
    },
  );
}

/**
 * Subscribe to a task manager channel.
 */
export function subscribe_task_manager(manager, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_task_manager(
        manager,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a sequence channel. `to_msg` receives every local and remote
 * `sequence_kernel.SequenceEvent` value, which carries the full list of values
 * after the edit. An insert, a delete, a move, and a replace all arrive in the
 * same form.
 */
export function subscribe_sequence(sequence, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_sequence(
        sequence,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a text channel. `to_msg` receives every local and remote
 * `text_kernel.TextEvent` value, which is a `TextChanged` event that carries
 * the full optimistic string after the edit. An insert, a delete, a replace,
 * and an append all arrive in the same form, and none of them carries a stale
 * author index. Read the channel again on that event, to render the committed
 * optimistic state.
 */
export function subscribe_text(text, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_text(
        text,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a text channel and return its cancellation token in a message.
 *
 * Use this form when a nested component can bind to a different text channel
 * during its lifetime. Call `watershed.unsubscribe` with the token before the
 * component releases the old binding.
 */
export function subscribe_text_cancellable(text, to_msg, subscribed) {
  return $effect.from(
    (dispatch) => {
      let token = $watershed.subscribe_text(
        text,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      return queue_microtask(() => { return dispatch(subscribed(token)); });
    },
  );
}

/**
 * Subscribe to a rich text channel. `to_msg` receives every local and remote
 * `rich_text_kernel.RichTextChanged` value, which carries the `Delta` that the
 * kernel applied. Read the channel again with `watershed.rich_text_view` to
 * render it.
 */
export function subscribe_rich_text(rich_text, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_rich_text(
        rich_text,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to a JSON-OT document. `DocumentChanged` carries the path that
 * changed, and not the new value, so read the channel again to render it.
 */
export function subscribe_json_ot(json_ot, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_json_ot(
        json_ot,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to the inbound ephemeral ripples of the document. Those are the
 * transient messages of presence: a cursor, a selection, and a typing
 * indicator.
 */
export function subscribe_ripples(document, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.subscribe_ripples(
        document,
        (ripple) => {
          return queue_microtask(() => { return dispatch(to_msg(ripple)); });
        },
      );
    },
  );
}

/**
 * Subscribe to one typed field. Every local or remote write to the key of that
 * field dispatches a `FieldChange` value. It carries the new value and the
 * previous value, both decoded at the boundary. Each one is `Error(Invalid)`
 * when a peer wrote a value that does not match the field type.
 */
export function subscribe_field(typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_field(
        typed_map,
        field,
        (change) => {
          return queue_microtask(() => { return dispatch(to_msg(change)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Subscribe to the whole-map events of a typed map, and stay in the typed API.
 * Use `subscribe_field` to watch one field instead.
 */
export function subscribe_typed(typed_map, to_msg) {
  return $effect.from(
    (dispatch) => {
      let $ = $watershed.subscribe_typed(
        typed_map,
        (event) => {
          return queue_microtask(() => { return dispatch(to_msg(event)); });
        },
      );
      
      return undefined;
    },
  );
}

/**
 * Make sure that a nested (untyped) map exists under `field`.
 */
export function ensure_map(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_map(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a directory exists under `field`. If none exists, the effect
 * creates one with an empty root.
 */
export function ensure_directory(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_directory(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a counter exists under `field`. If the slot is empty, the
 * effect creates one.
 */
export function ensure_counter(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_counter(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that an OR-map exists under `field`. If none exists, the effect
 * creates one in `mode`. Use `OrSetMode` for string-set values. An existing
 * channel keeps its mode.
 */
export function ensure_or_map(document, typed_map, field, mode, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_or_map(
        document,
        typed_map,
        field,
        mode,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that an OR-set exists under `field`.
 */
export function ensure_or_set(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_or_set(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a grow-only set exists under `field`.
 */
export function ensure_g_set(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_g_set(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a two-phase set exists under `field`.
 */
export function ensure_two_p_set(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_two_p_set(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a register collection exists under `field`.
 */
export function ensure_register_collection(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_register_collection(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a claims channel exists under `field`.
 */
export function ensure_claims(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_claims(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a task manager exists under `field`.
 */
export function ensure_task_manager(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_task_manager(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a PN-counter exists under `field`. If the slot is empty, the
 * effect creates one.
 */
export function ensure_pn_counter(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_pn_counter(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a grow-only counter exists under `field`. If the slot is
 * empty, the effect creates one.
 */
export function ensure_g_counter(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_g_counter(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Adopt or create an LWW map when the effect runs.
 */
export function ensure_lww_map(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_lww_map(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that an LWW register exists under `field`.
 */
export function ensure_lww_register(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_lww_register(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that an MV register exists under `field`.
 */
export function ensure_mv_register(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_mv_register(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a PactMap exists under `field`.
 */
export function ensure_pact_map(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_pact_map(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that an ordered collection exists under `field`.
 */
export function ensure_ordered_collection(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_ordered_collection(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a sequence exists under `field`. If none exists, the effect
 * creates an empty one.
 */
export function ensure_sequence(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_sequence(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a text channel exists under `field`. If none exists, the
 * effect creates an empty one.
 */
export function ensure_text(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_text(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a rich text channel exists under `field`. If none exists, the
 * effect creates one with an empty document.
 */
export function ensure_rich_text(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_rich_text(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a JSON-OT document exists under `field`.
 */
export function ensure_json_ot(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_json_ot(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Make sure that a nested *typed* child map exists under a child field.
 */
export function ensure_child(document, typed_map, field, to_msg) {
  return $effect.from(
    (dispatch) => {
      return $watershed.ensure_child(
        document,
        typed_map,
        field,
        (result) => {
          return queue_microtask(() => { return dispatch(to_msg(result)); });
        },
      );
    },
  );
}

/**
 * Set a plain typed field to `default`, and only when its key is absent now.
 * The write is synchronous and dispatches no message. Put it in a batch with
 * the channel effects above, to make the bootstrap declarative in `init`.
 */
export function ensure_field(typed_map, field, default$) {
  return $effect.from(
    (_) => { return $watershed.ensure_field(typed_map, field, default$); },
  );
}

/**
 * Dispatch `msg` after `ms` milliseconds. This is the timer effect that an
 * application uses for a heartbeat, a debounce, and a retry, and the
 * application thus writes no `setTimeout` FFI. The timer runs outside every
 * `update` call, so this effect needs no microtask.
 */
export function after(milliseconds, msg) {
  return $effect.from(
    (dispatch) => {
      return set_timeout(() => { return dispatch(msg); }, milliseconds);
    },
  );
}

/**
 * Broadcast an ephemeral ripple to every other connected client. The effect
 * dispatches no message back.
 */
export function submit_ripple(document, ripple_type, content) {
  return $effect.from(
    (_) => { return $watershed.submit_ripple(document, ripple_type, content); },
  );
}

/**
 * A hook that injects a fault, for a test or a demo. It closes the socket, so
 * that the client runs the reconnect and reconcile path. The pending edits and
 * the in-flight edits all stay.
 */
export function force_reconnect(document) {
  return $effect.from((_) => { return $watershed.force_reconnect(document); });
}

/**
 * Go offline and stay offline. A read and an edit both continue to work. The
 * edits queue, and they go out when `go_online` reconnects. The effect does
 * nothing unless the document is connected.
 *
 * Bind this function and `go_online` directly to a toggle:
 *
 * ```gleam
 * ToggledOffline(offline) -> #(
 *   Model(..model, offline:),
 *   case offline {
 *     True -> watershed_lustre.go_offline(document)
 *     False -> watershed_lustre.go_online(document)
 *   },
 * )
 * ```
 */
export function go_offline(document) {
  return $effect.from((_) => { return $watershed.go_offline(document); });
}

/**
 * Return from `go_offline`. The client replays the interval and sends the
 * edits from it. The effect does nothing unless the document is offline now.
 */
export function go_online(document) {
  return $effect.from((_) => { return $watershed.go_online(document); });
}

/**
 * Start to track presence on `document`, with `initial` as the metadata of
 * this client.
 *
 * `started` runs with the `Handle` value of the driver. Keep that value in
 * your model, so that you can update it later. `on_event` runs with every
 * `presence.Event` value. A `State` event replaces the whole roster. A
 * `Changed` event carries a change and the roster that results. A `Failed`
 * event reports a failure. Render on whichever event suits your application.
 * The roster in a `Changed` event is always complete.
 */
export function presence(document, config, initial, started, on_event) {
  return $effect.from(
    (dispatch) => {
      let handle = $presence_js.start(
        document,
        config,
        initial,
        (event) => {
          return queue_microtask(() => { return dispatch(on_event(event)); });
        },
      );
      return queue_microtask(() => { return dispatch(started(handle)); });
    },
  );
}

/**
 * Replace the presence metadata of this client. The effect dispatches no
 * message back.
 */
export function update_presence(handle, metadata) {
  return $effect.from((_) => { return $presence_js.update(handle, metadata); });
}

/**
 * Stop the presence tracking. In server mode the peers see the departure
 * immediately. In ripple mode they see it when the TTL expires.
 */
export function stop_presence(handle) {
  return $effect.from((_) => { return $presence_js.stop(handle); });
}

/**
 * Set or re-enable the automatic summary policy for this client.
 *
 * New connections use `summary_policy.policy()`: a threshold of 500 sequenced
 * messages and a 3 second delay window. This effect replaces that policy.
 * It dispatches no message. The policy applies from the next sequenced
 * message. Use it in the update that receives the `Document` value.
 */
export function auto_summarize(document, policy) {
  return $effect.from(
    (_) => { return $watershed.auto_summarize(document, policy); },
  );
}

/**
 * Stop automatic summaries for this client. Other clients keep their policies.
 * An upload that has already started can finish.
 */
export function stop_auto_summarize(document) {
  return $effect.from(
    (_) => { return $watershed.stop_auto_summarize(document); },
  );
}
