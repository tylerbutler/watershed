/// <reference types="./watershed.d.mts" />
import * as $promise from "../gleam_javascript/gleam/javascript/promise.mjs";
import * as $json from "../gleam_json/gleam/json.mjs";
import * as $dict from "../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../gleam_stdlib/gleam/list.mjs";
import * as $option from "../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../gleam_stdlib/gleam/option.mjs";
import * as $result from "../gleam_stdlib/gleam/result.mjs";
import * as $sequence from "../lattice_sequence/lattice_sequence/sequence.mjs";
import { Bias$Before$const, Bias$After$const } from "../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $token from "../signet/signet/types.mjs";
import * as $message from "../spillway/spillway/message.mjs";
import { ConnectMessage } from "../spillway/spillway/message.mjs";
import * as $types from "../spillway/spillway/types.mjs";
import {
  Client,
  ClientCapabilities,
  ClientDetails,
  ConnectionMode$WriteMode$const,
} from "../spillway/spillway/types.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "./gleam.mjs";
import * as $channel from "./watershed/channel.mjs";
import * as $claims_kernel from "./watershed/claims_kernel.mjs";
import * as $counter_kernel from "./watershed/counter_kernel.mjs";
import * as $directory_kernel from "./watershed/directory_kernel.mjs";
import * as $g_counter_kernel from "./watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "./watershed/g_set_kernel.mjs";
import * as $git_storage from "./watershed/git_storage.mjs";
import * as $handle from "./watershed/handle.mjs";
import * as $json_ot from "./watershed/json_ot.mjs";
import * as $json_ot_kernel from "./watershed/json_ot_kernel.mjs";
import * as $lww_map_kernel from "./watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "./watershed/lww_register_kernel.mjs";
import * as $map_kernel from "./watershed/map_kernel.mjs";
import * as $mv_register_kernel from "./watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "./watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "./watershed/or_set_kernel.mjs";
import * as $ordered_collection_kernel from "./watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "./watershed/pact_map_kernel.mjs";
import * as $pn_counter_kernel from "./watershed/pn_counter_kernel.mjs";
import * as $register_collection_kernel from "./watershed/register_collection_kernel.mjs";
import { ReadPolicy$Atomic$const } from "./watershed/register_collection_kernel.mjs";
import * as $rich_text from "./watershed/rich_text.mjs";
import * as $rich_text_kernel from "./watershed/rich_text_kernel.mjs";
import * as $runtime from "./watershed/runtime.mjs";
import * as $schema from "./watershed/schema.mjs";
import * as $sequence_kernel from "./watershed/sequence_kernel.mjs";
import * as $summary_policy from "./watershed/summary_policy.mjs";
import * as $task_manager_kernel from "./watershed/task_manager_kernel.mjs";
import * as $text_kernel from "./watershed/text_kernel.mjs";
import * as $transport_js from "./watershed/transport_js.mjs";
import * as $two_p_set_kernel from "./watershed/two_p_set_kernel.mjs";
import * as $wire from "./watershed/wire.mjs";
import * as $summary_blob from "./watershed/wire/summary_blob.mjs";

export class WatershedConfig extends $CustomType {
  constructor(url, tenant, document, token, user_id) {
    super();
    this.url = url;
    this.tenant = tenant;
    this.document = document;
    this.token = token;
    this.user_id = user_id;
  }
}
export const WatershedConfig$WatershedConfig = (url, tenant, document, token, user_id) =>
  new WatershedConfig(url, tenant, document, token, user_id);
export const WatershedConfig$isWatershedConfig = (value) =>
  value instanceof WatershedConfig;
export const WatershedConfig$WatershedConfig$url = (value) => value.url;
export const WatershedConfig$WatershedConfig$0 = (value) => value.url;
export const WatershedConfig$WatershedConfig$tenant = (value) => value.tenant;
export const WatershedConfig$WatershedConfig$1 = (value) => value.tenant;
export const WatershedConfig$WatershedConfig$document = (value) =>
  value.document;
export const WatershedConfig$WatershedConfig$2 = (value) => value.document;
export const WatershedConfig$WatershedConfig$token = (value) => value.token;
export const WatershedConfig$WatershedConfig$3 = (value) => value.token;
export const WatershedConfig$WatershedConfig$user_id = (value) => value.user_id;
export const WatershedConfig$WatershedConfig$4 = (value) => value.user_id;

class Document extends $CustomType {
  constructor(runtime) {
    super();
    this.runtime = runtime;
  }
}

class SubscriptionToken extends $CustomType {
  constructor(runtime_token) {
    super();
    this.runtime_token = runtime_token;
  }
}

class SharedMap extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class SharedCounter extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class OrMap extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class OrSet extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class RegisterCollection extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class Claims extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class TaskManager extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class PnCounter extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class GCounter extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class LwwRegister extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class LwwMap extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class PactMap extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class OrderedCollection extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class SharedSequence extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class SharedText extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class JsonOt extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class SharedRichText extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class GSet extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class TwoPSet extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class SharedDirectory extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

class TypedMap extends $CustomType {
  constructor(map) {
    super();
    this.map = map;
  }
}

class Ripple extends $CustomType {
  constructor(signal) {
    super();
    this.signal = signal;
  }
}

class MvRegister extends $CustomType {
  constructor(runtime, address) {
    super();
    this.runtime = runtime;
    this.address = address;
  }
}

const resolve_retry_milliseconds = 200;

const resolve_attempts = 25;

export const bias_before = Bias$Before$const;

export const bias_after = Bias$After$const;

/**
 * Connect to a document. The function returns the handle immediately. It calls
 * `on_ready` with `Ok(Nil)` after the handshake and the history replay
 * complete, or with `Error(reason)` when the server refuses the connection.
 */
export function connect(config, on_ready) {
  let topic = (("document:" + config.tenant) + ":") + config.document;
  let connect_message = new ConnectMessage(
    config.tenant,
    config.document,
    new Some(config.token),
    new Client(
      ConnectionMode$WriteMode$const,
      new ClientDetails(
        new ClientCapabilities(true),
        new Some("watershed-js"),
        Option$None$const,
        Option$None$const,
      ),
      $List$Empty$const,
      new $token.User(config.user_id, $dict.new$()),
      toList(["doc:read", "doc:write", "summary:write"]),
      Option$None$const,
    ),
    toList(["^0.1.0"]),
    Option$None$const,
    ConnectionMode$WriteMode$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
  let runtime = $runtime.start(config.url, topic, connect_message, on_ready);
  return new Document(runtime);
}

/**
 * Connect through an injected transport. The in-memory `sluice_js` test driver
 * uses this seam. `on_ready` still runs when the handshake completes, and the
 * driver causes that completion when it delivers the handshake frame on a
 * `settle` call. Do not use this function in production.
 */
export function connect_via(tenant, document, user_id, transport, on_ready) {
  let connect_message = new ConnectMessage(
    tenant,
    document,
    Option$None$const,
    new Client(
      ConnectionMode$WriteMode$const,
      new ClientDetails(
        new ClientCapabilities(true),
        new Some("watershed-js"),
        Option$None$const,
        Option$None$const,
      ),
      $List$Empty$const,
      new $token.User(user_id, $dict.new$()),
      toList(["doc:read", "doc:write", "summary:write"]),
      Option$None$const,
    ),
    toList(["^0.1.0"]),
    Option$None$const,
    ConnectionMode$WriteMode$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
    Option$None$const,
  );
  return new Document(
    $runtime.start_with_transport(
      "sluice",
      connect_message,
      transport,
      on_ready,
    ),
  );
}

/**
 * The runtime behind a document. This function is public for the `sluice_js`
 * test driver, which uses the runtime as the key of a paused client. It is not
 * part of the API for an application.
 */
export function runtime_of(document) {
  return document.runtime;
}

/**
 * The root map of the document, at the channel address `"root"`.
 */
export function root(document) {
  return new SharedMap(document.runtime, "root");
}

/**
 * Create a new map channel. The map starts *detached*, which means that it is
 * local only and its edits produce no operation. It stays detached until a
 * caller stores its handle, from `handle_of`, into an attached map. The
 * runtime then attaches it, with its snapshot, and it starts to synchronize
 * the edits of that map. The connection must be ready, which `on_ready`
 * reports.
 */
export function create_map(document) {
  let _pipe = $runtime.create_map(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedMap(document.runtime, address); },
  );
}

/**
 * The Fluid handle marker that references `map`. Store it as a value in
 * another map. Its shape is
 * `{"type": "__fluid_handle__", "url": "/<address>"}`.
 */
export function handle_of(map) {
  return $handle.encode_handle(map.address);
}

/**
 * Whether a value that you read from a map is a handle marker. See
 * `resolve`.
 */
export function is_handle(value) {
  return !isEqual($handle.parse_handle(value), new Error(undefined));
}

/**
 * Resolve a handle value, from `get` or from `entries`, to the SharedMap that
 * it references. A caller can retry after an error. A handle from a remote
 * value can stay unresolved for a short time, while the attach operation of
 * the channel that it references is still in flight.
 */
export function resolve(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedMap(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * View a raw map through a schema. The use of the result selects the schema,
 * and an annotation can also select it, for example
 * `let players: TypedMap(Roster) = typed(map)`.
 */
export function typed(map) {
  return new TypedMap(map);
}

/**
 * The raw map below the typed view, to return to the untyped API.
 */
export function untyped(typed_map) {
  return typed_map.map;
}

/**
 * The root map of the document, viewed through the schema of that document.
 *
 * One document has one tag. The tag comes from the `Document(root)` value that
 * you pass, so it is fixed at the position where your application writes the
 * type concretely. That position is the `Msg` constructor that carries the
 * handle, or the `Model` field that holds it:
 *
 * ```gleam
 * GotHandle(Document(document_schema.Survey))
 * ```
 *
 * Every `root_typed` call on that document then agrees. A second schema at the
 * root is a compile error, and not a key namespace that two schemas share
 * quietly.
 *
 * A component that is generic in `root` can still call this function. But an
 * abstract tag has no field, so that component cannot read or write the root.
 * A nested panel is thus structurally unable to reach past its own child map.
 *
 * `typed(root(document))` is still available, and it is still unchecked. It is
 * the deliberate way to view the root through a foreign schema. Unlike the old
 * signature, you must now write it explicitly.
 */
export function root_typed(document) {
  return typed(root(document));
}

/**
 * Create a new detached map, viewed through a schema. The lifecycle is the
 * same as for `create_map`.
 */
export function create_typed_map(document) {
  let _pipe = create_map(document);
  return $result.map(_pipe, typed);
}

export function set(map, key, value) {
  return $runtime.set(map.runtime, map.address, key, value);
}

/**
 * Optimistically write a typed field.
 */
export function set_field(typed_map, field, value) {
  return set(
    typed_map.map,
    $schema.field_key(field),
    $schema.encode_value(field, value),
  );
}

export function delete$(map, key) {
  return $runtime.delete$(map.runtime, map.address, key);
}

/**
 * Optimistically delete a typed field.
 */
export function delete_field(typed_map, field) {
  return delete$(typed_map.map, $schema.field_key(field));
}

export function get(map, key) {
  return $runtime.get(map.runtime, map.address, key);
}

/**
 * Read a typed field. The result is `Ok(None)` when the key is absent, and
 * `Error(Invalid)` when the stored value does not decode to the type `a`.
 */
export function get_field(typed_map, field) {
  let $ = get(typed_map.map, $schema.field_key(field));
  if ($ instanceof Ok) {
    let stored = $[0];
    let _pipe = $schema.decode_value(field, stored);
    return $result.map(_pipe, (var0) => { return new Some(var0); });
  } else {
    return new Ok(Option$None$const);
  }
}

/**
 * Read a typed field that must exist. The result is `Error(Missing)` when the
 * key is absent.
 */
export function get_required(typed_map, field) {
  let $ = get_field(typed_map, field);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Some) {
      let value = $1[0];
      return new Ok(value);
    } else {
      return new Error(new $schema.Missing($schema.field_key(field)));
    }
  } else {
    return $;
  }
}

export function has(map, key) {
  return $result.is_ok(get(map, key));
}

/**
 * Whether a typed field is present. The function does not check that the
 * value decodes.
 */
export function has_field(typed_map, field) {
  return has(typed_map.map, $schema.field_key(field));
}

/**
 * Store a handle to a nested typed map under a child field.
 */
export function set_child(typed_map, field, child) {
  return set(typed_map.map, $schema.child_key(field), handle_of(child.map));
}

/**
 * Resolve the nested typed map that a child field references. The result is
 * `Ok(None)` when the key is absent. The function returns an error from
 * `resolve` without a change, and a caller can retry after it. That includes
 * the short-lived error for a channel that is not attached yet.
 */
export function resolve_child(document, typed_map, field) {
  let $ = get(typed_map.map, $schema.child_key(field));
  if ($ instanceof Ok) {
    let value = $[0];
    let _pipe = resolve(document, value);
    return $result.map(
      _pipe,
      (resolved) => { return new Some(typed(resolved)); },
    );
  } else {
    return new Ok(Option$None$const);
  }
}

export function entries(map) {
  return $runtime.entries(map.runtime, map.address);
}

/**
 * Read the whole map as a typed record, through a schema. The function returns
 * one `Result` value, after the version check and the seal check of that
 * schema. See `watershed/schema`.
 */
export function read(typed_map, map_schema) {
  return $schema.decode_entries(map_schema, entries(typed_map.map));
}

/**
 * Write a whole record through a schema, as one operation for each key.
 * Concurrent edits to two other keys thus still merge, and the record view
 * never overwrites the whole map. An optional prop with the value `None`
 * deletes its key.
 */
export function write(typed_map, map_schema, value) {
  return $list.each(
    $schema.encode_operations(map_schema, value),
    (operation) => {
      if (operation instanceof $schema.Put) {
        let key = operation.key;
        let entry_value = operation.value;
        return set(typed_map.map, key, entry_value);
      } else {
        let key = operation.key;
        return delete$(typed_map.map, key);
      }
    },
  );
}

/**
 * Write the version marker of a schema that has a version, one time. The usual
 * position for this call is immediately after you create the map. The function
 * does nothing for a schema with no version.
 */
export function stamp(typed_map, map_schema) {
  let $ = $schema.stamp_entry(map_schema);
  if ($ instanceof Some) {
    let entry = $[0];
    return set(typed_map.map, entry[0], entry[1]);
  } else {
    return undefined;
  }
}

/**
 * Resolve every key whose value is a handle to a typed child map. This is the
 * typed view of a dynamic collection, which is a map whose keys the compiler
 * does not know, for example a roster keyed by id. The function skips a key
 * whose value is not a handle. It returns the `Result` value of each child,
 * and a caller can retry after the short-lived error for a channel that is not
 * attached yet.
 */
export function typed_children(document, typed_map) {
  let _pipe = entries(typed_map.map);
  let _pipe$1 = $list.filter(_pipe, (entry) => { return is_handle(entry[1]); });
  return $list.map(
    _pipe$1,
    (entry) => {
      return [
        entry[0],
        (() => {
          let _pipe$2 = resolve(document, entry[1]);
          return $result.map(_pipe$2, typed);
        })(),
      ];
    },
  );
}

function put_channel_field(typed_map, field, handle_json) {
  return set(typed_map.map, $schema.channel_field_key(field), handle_json);
}

function get_channel_field(document, typed_map, field, resolver) {
  let $ = get(typed_map.map, $schema.channel_field_key(field));
  if ($ instanceof Ok) {
    let value = $[0];
    let _pipe = resolver(document, value);
    return $result.map(_pipe, (var0) => { return new Some(var0); });
  } else {
    return new Ok(Option$None$const);
  }
}

/**
 * Store a handle to an (untyped) nested map under a typed channel field.
 */
export function set_map_field(typed_map, field, map) {
  return put_channel_field(typed_map, field, handle_of(map));
}

/**
 * Resolve the map referenced by a typed channel field.
 */
export function resolve_map_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve);
}

/**
 * The Fluid handle marker that references `counter`. Store it as a value in a
 * map. See `handle_of`.
 */
export function counter_handle_of(counter) {
  return $handle.encode_handle(counter.address);
}

/**
 * Store a handle to `counter` under a typed channel field.
 */
export function set_counter_field(typed_map, field, counter) {
  return put_channel_field(typed_map, field, counter_handle_of(counter));
}

/**
 * Resolve a handle value to the SharedCounter that it references. The function
 * checks that the channel exists, and it does not check the channel type. To
 * resolve a channel that is not a counter gives a counter whose reads return
 * `None`. A caller can retry after an error, the same as for `resolve`.
 */
export function resolve_counter(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedCounter(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the counter referenced by a typed channel field.
 */
export function resolve_counter_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_counter);
}

export function or_map_handle_of(or_map) {
  return $handle.encode_handle(or_map.address);
}

/**
 * Store a handle to `or_map` under a typed channel field.
 */
export function set_or_map_field(typed_map, field, or_map) {
  return put_channel_field(typed_map, field, or_map_handle_of(or_map));
}

export function resolve_or_map(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new OrMap(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the OR-map referenced by a typed channel field.
 */
export function resolve_or_map_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_or_map);
}

export function or_set_handle_of(or_set) {
  return $handle.encode_handle(or_set.address);
}

/**
 * Store a handle to `or_set` under a typed channel field.
 */
export function set_or_set_field(typed_map, field, or_set) {
  return put_channel_field(typed_map, field, or_set_handle_of(or_set));
}

export function resolve_or_set(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new OrSet(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the OR-set referenced by a typed channel field.
 */
export function resolve_or_set_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_or_set);
}

export function sequence_handle_of(sequence) {
  return $handle.encode_handle(sequence.address);
}

export function set_sequence_field(typed_map, field, sequence) {
  return put_channel_field(typed_map, field, sequence_handle_of(sequence));
}

export function resolve_sequence(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_sequence(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedSequence(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

export function resolve_sequence_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_sequence);
}

export function text_handle_of(text) {
  return $handle.encode_handle(text.address);
}

/**
 * Store a handle to `text` under a typed channel field.
 */
export function set_text_field(typed_map, field, text) {
  return put_channel_field(typed_map, field, text_handle_of(text));
}

export function resolve_text(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_text(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedText(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the text channel referenced by a typed channel field.
 */
export function resolve_text_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_text);
}

export function register_collection_handle_of(collection) {
  return $handle.encode_handle(collection.address);
}

/**
 * Store a handle to `collection` under a typed channel field.
 */
export function set_register_collection_field(typed_map, field, collection) {
  return put_channel_field(
    typed_map,
    field,
    register_collection_handle_of(collection),
  );
}

export function resolve_register_collection(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new RegisterCollection(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the register collection referenced by a typed channel field.
 */
export function resolve_register_collection_field(document, typed_map, field) {
  return get_channel_field(
    document,
    typed_map,
    field,
    resolve_register_collection,
  );
}

export function claims_handle_of(claims) {
  return $handle.encode_handle(claims.address);
}

/**
 * Store a handle to `claims` under a typed channel field.
 */
export function set_claims_field(typed_map, field, claims) {
  return put_channel_field(typed_map, field, claims_handle_of(claims));
}

export function resolve_claims(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new Claims(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the claims channel referenced by a typed channel field.
 */
export function resolve_claims_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_claims);
}

export function task_manager_handle_of(manager) {
  return $handle.encode_handle(manager.address);
}

/**
 * Store a handle to `manager` under a typed channel field.
 */
export function set_task_manager_field(typed_map, field, manager) {
  return put_channel_field(typed_map, field, task_manager_handle_of(manager));
}

export function resolve_task_manager(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new TaskManager(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the task manager referenced by a typed channel field.
 */
export function resolve_task_manager_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_task_manager);
}

export function pn_counter_handle_of(pn_counter) {
  return $handle.encode_handle(pn_counter.address);
}

/**
 * Store a handle to `pn_counter` under a typed channel field.
 */
export function set_pn_counter_field(typed_map, field, pn_counter) {
  return put_channel_field(typed_map, field, pn_counter_handle_of(pn_counter));
}

export function g_counter_handle_of(g_counter) {
  return $handle.encode_handle(g_counter.address);
}

/**
 * Store a handle to `g_counter` under a typed channel field.
 */
export function set_g_counter_field(typed_map, field, g_counter) {
  return put_channel_field(typed_map, field, g_counter_handle_of(g_counter));
}

export function resolve_pn_counter(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new PnCounter(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the PN-counter referenced by a typed channel field.
 */
export function resolve_pn_counter_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_pn_counter);
}

export function resolve_g_counter(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new GCounter(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Read the grow-only counter that `field` points at.
 */
export function resolve_g_counter_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_g_counter);
}

/**
 * Encode the register address as a handle.
 */
export function lww_register_handle_of(register) {
  return $handle.encode_handle(register.address);
}

/**
 * Store a register handle under a typed channel field.
 */
export function set_lww_register_field(typed_map, field, register) {
  return put_channel_field(typed_map, field, lww_register_handle_of(register));
}

/**
 * Resolve a handle marker and its address. Reads and writes report a
 * channel-kind mismatch.
 */
export function resolve_lww_register(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new LwwRegister(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the register referenced by a typed channel field.
 */
export function resolve_lww_register_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_lww_register);
}

export function pact_map_handle_of(pact_map) {
  return $handle.encode_handle(pact_map.address);
}

/**
 * Store a handle to `pact_map` under a typed channel field.
 */
export function set_pact_map_field(typed_map, field, pact_map) {
  return put_channel_field(typed_map, field, pact_map_handle_of(pact_map));
}

export function resolve_pact_map(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new PactMap(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the PactMap referenced by a typed channel field.
 */
export function resolve_pact_map_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_pact_map);
}

export function ordered_collection_handle_of(collection) {
  return $handle.encode_handle(collection.address);
}

/**
 * Store a handle to `collection` under a typed channel field.
 */
export function set_ordered_collection_field(typed_map, field, collection) {
  return put_channel_field(
    typed_map,
    field,
    ordered_collection_handle_of(collection),
  );
}

export function resolve_ordered_collection(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new OrderedCollection(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the ordered collection referenced by a typed channel field.
 */
export function resolve_ordered_collection_field(document, typed_map, field) {
  return get_channel_field(
    document,
    typed_map,
    field,
    resolve_ordered_collection,
  );
}

/**
 * The Fluid handle marker that references `json_ot`. Store it as a value in a
 * map. See `handle_of`.
 */
export function json_ot_handle_of(json_ot) {
  return $handle.encode_handle(json_ot.address);
}

/**
 * Store a handle to `json_ot` under a typed channel field.
 */
export function set_json_ot_field(typed_map, field, json_ot) {
  return put_channel_field(typed_map, field, json_ot_handle_of(json_ot));
}

/**
 * Resolve a handle value to the JsonOt value that it references. A caller can
 * retry after an error, the same as for `resolve`.
 */
export function resolve_json_ot(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new JsonOt(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the json0 channel referenced by a typed channel field.
 */
export function resolve_json_ot_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_json_ot);
}

/**
 * The Fluid handle marker that references `rich_text`. Store it as a value in a
 * map. See `handle_of`.
 */
export function rich_text_handle_of(rich_text) {
  return $handle.encode_handle(rich_text.address);
}

/**
 * Store a handle to `rich_text` under a typed channel field.
 */
export function set_rich_text_field(typed_map, field, rich_text) {
  return put_channel_field(typed_map, field, rich_text_handle_of(rich_text));
}

/**
 * Resolve a handle value to the SharedRichText value that it references. The
 * function checks that the channel exists, and it does not check the channel
 * type. A caller can retry after an error, the same as for `resolve`.
 */
export function resolve_rich_text(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedRichText(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the rich-text channel referenced by a typed channel field.
 */
export function resolve_rich_text_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_rich_text);
}

/**
 * The Fluid handle marker that references `set`. Store it as a value in a map.
 * See `handle_of`.
 */
export function g_set_handle_of(set) {
  return $handle.encode_handle(set.address);
}

/**
 * Store a handle to `set` under a typed channel field.
 */
export function set_g_set_field(typed_map, field, set) {
  return put_channel_field(typed_map, field, g_set_handle_of(set));
}

/**
 * Resolve a handle value to the GSet value that it references. A caller can
 * retry after an error, the same as for `resolve`.
 */
export function resolve_g_set(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new GSet(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the G-set referenced by a typed channel field.
 */
export function resolve_g_set_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_g_set);
}

/**
 * The Fluid handle marker that references `set`. Store it as a value in a map.
 * See `handle_of`.
 */
export function two_p_set_handle_of(set) {
  return $handle.encode_handle(set.address);
}

/**
 * Store a handle to `set` under a typed channel field.
 */
export function set_two_p_set_field(typed_map, field, set) {
  return put_channel_field(typed_map, field, two_p_set_handle_of(set));
}

/**
 * Resolve a handle value to the TwoPSet value that it references. A caller can
 * retry after an error, the same as for `resolve`.
 */
export function resolve_two_p_set(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new TwoPSet(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the 2P-set referenced by a typed channel field.
 */
export function resolve_two_p_set_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_two_p_set);
}

/**
 * The Fluid handle marker that references `directory`. Store it as a value in
 * a map. See `handle_of`.
 */
export function directory_handle_of(directory) {
  return $handle.encode_handle(directory.address);
}

/**
 * Store a handle to `directory` under a typed channel field.
 */
export function set_directory_field(typed_map, field, directory) {
  return put_channel_field(typed_map, field, directory_handle_of(directory));
}

/**
 * Resolve a handle value to the SharedDirectory value that it references. A
 * caller can retry after an error, the same as for `resolve`.
 */
export function resolve_directory(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new SharedDirectory(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

/**
 * Resolve the directory referenced by a typed channel field.
 */
export function resolve_directory_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_directory);
}

/**
 * Whether the document is caught up, which is true when the server acked every
 * local edit. The confirmed state is then complete and stable. Use this
 * function to wait for a quiet document before you summarize it.
 */
export function is_synced(document) {
  return $runtime.is_synced(document.runtime);
}

/**
 * Wait for synchronization within the resolve budget. Report a timeout if the
 * document does not synchronize.
 * 
 * @ignore
 */
function await_synced(document, attempts, next) {
  let $ = is_synced(document);
  let $1 = attempts <= 0;
  if ($) {
    return next(new Ok(undefined));
  } else if ($1) {
    return next(
      new Error("ensure: timed out waiting for document synchronization"),
    );
  } else {
    return $runtime.schedule(
      document.runtime,
      () => { return await_synced(document, attempts - 1, next); },
      resolve_retry_milliseconds,
    );
  }
}

/**
 * Resolve a field to its channel. The function tries again on a timer while the
 * handle is absent, and while the attach operation of the channel that it
 * references is still in flight.
 * 
 * @ignore
 */
function resolve_with_retry(document, resolve, attempts, done) {
  let $ = resolve();
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof Some) {
      let shared = $1[0];
      return done(new Ok(shared));
    } else {
      let n = attempts;
      if (n <= 1) {
        return done(
          new Error("ensure: no channel handle appeared under the field"),
        );
      } else {
        return $runtime.schedule(
          document.runtime,
          () => {
            return resolve_with_retry(document, resolve, attempts - 1, done);
          },
          resolve_retry_milliseconds,
        );
      }
    }
  } else {
    let n = attempts;
    if (n <= 1) {
      let reason = $[0];
      return done(new Error(reason));
    } else {
      return $runtime.schedule(
        document.runtime,
        () => {
          return resolve_with_retry(document, resolve, attempts - 1, done);
        },
        resolve_retry_milliseconds,
      );
    }
  }
}

/**
 * Wait for synchronization before reading `key`. Adopt an existing channel,
 * or seed a candidate and wait for its write to synchronize before resolving.
 * Either wait can return a timeout. A timeout does not undo a submitted seed.
 * A later write from another client can still replace the field.
 * 
 * @ignore
 */
function ensure_channel(document, typed_map, key, seed, resolve, done) {
  return await_synced(
    document,
    resolve_attempts,
    (synced) => {
      if (synced instanceof Ok) {
        let $ = has(typed_map.map, key);
        if ($) {
          return resolve_with_retry(document, resolve, resolve_attempts, done);
        } else {
          let $1 = seed();
          if ($1 instanceof Ok) {
            return await_synced(
              document,
              resolve_attempts,
              (synced) => {
                if (synced instanceof Ok) {
                  return resolve_with_retry(
                    document,
                    resolve,
                    resolve_attempts,
                    done,
                  );
                } else {
                  let reason = synced[0];
                  return done(new Error(reason));
                }
              },
            );
          } else {
            let reason = $1[0];
            return done(new Error(reason));
          }
        }
      } else {
        let reason = synced[0];
        return done(new Error(reason));
      }
    },
  );
}

/**
 * Make sure that a nested (untyped) map exists under `field`.
 */
export function ensure_map(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_map(document),
        (map) => { return set_map_field(typed_map, field, map); },
      );
    },
    () => { return resolve_map_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new counter channel. The detached lifecycle is the same as for
 * `create_map`. The channel is local only, until a caller stores its handle,
 * from `counter_handle_of`, into an attached map. The connection must be
 * ready, which `on_ready` reports.
 */
export function create_counter(document) {
  let _pipe = $runtime.create_counter(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedCounter(document.runtime, address); },
  );
}

/**
 * Make sure that a counter exists under `field`. If the slot is empty, the
 * function creates one.
 */
export function ensure_counter(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_counter(document),
        (counter) => { return set_counter_field(typed_map, field, counter); },
      );
    },
    () => { return resolve_counter_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create an OR-map with tally, LWW-register, string-set, or MV-register values.
 * The detached lifecycle is the same as for `create_map`.
 */
export function create_or_map(document, mode) {
  let _pipe = $runtime.create_or_map(document.runtime, mode);
  return $result.map(
    _pipe,
    (address) => { return new OrMap(document.runtime, address); },
  );
}

/**
 * Make sure that an OR-map exists under `field`. If none exists, the function
 * creates one in `mode`.
 */
export function ensure_or_map(document, typed_map, field, mode, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_or_map(document, mode),
        (or_map) => { return set_or_map_field(typed_map, field, or_map); },
      );
    },
    () => { return resolve_or_map_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new observed-remove set channel, for string elements.
 */
export function create_or_set(document) {
  let _pipe = $runtime.create_or_set(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new OrSet(document.runtime, address); },
  );
}

/**
 * Make sure that an OR-set exists under `field`.
 */
export function ensure_or_set(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_or_set(document),
        (or_set) => { return set_or_set_field(typed_map, field, or_set); },
      );
    },
    () => { return resolve_or_set_field(document, typed_map, field); },
    done,
  );
}

export function create_sequence(document) {
  let _pipe = $runtime.create_sequence(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedSequence(document.runtime, address); },
  );
}

export function ensure_sequence(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_sequence(document),
        (sequence) => { return set_sequence_field(typed_map, field, sequence); },
      );
    },
    () => { return resolve_sequence_field(document, typed_map, field); },
    done,
  );
}

export function create_text(document) {
  let _pipe = $runtime.create_text(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedText(document.runtime, address); },
  );
}

/**
 * Make sure that a text channel exists under `field`. If the slot is empty,
 * the function creates one.
 */
export function ensure_text(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_text(document),
        (text) => { return set_text_field(typed_map, field, text); },
      );
    },
    () => { return resolve_text_field(document, typed_map, field); },
    done,
  );
}

export function create_register_collection(document) {
  let _pipe = $runtime.create_register_collection(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new RegisterCollection(document.runtime, address); },
  );
}

/**
 * Make sure that a register collection exists under `field`.
 */
export function ensure_register_collection(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_register_collection(document),
        (registers) => {
          return set_register_collection_field(typed_map, field, registers);
        },
      );
    },
    () => {
      return resolve_register_collection_field(document, typed_map, field);
    },
    done,
  );
}

export function create_claims(document) {
  let _pipe = $runtime.create_claims(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new Claims(document.runtime, address); },
  );
}

/**
 * Make sure that a claims channel exists under `field`.
 */
export function ensure_claims(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_claims(document),
        (claims) => { return set_claims_field(typed_map, field, claims); },
      );
    },
    () => { return resolve_claims_field(document, typed_map, field); },
    done,
  );
}

export function create_task_manager(document) {
  let _pipe = $runtime.create_task_manager(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new TaskManager(document.runtime, address); },
  );
}

/**
 * Make sure that a task manager exists under `field`.
 */
export function ensure_task_manager(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_task_manager(document),
        (tasks) => { return set_task_manager_field(typed_map, field, tasks); },
      );
    },
    () => { return resolve_task_manager_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new PN-counter channel. The detached lifecycle is the same as for
 * `create_map`.
 */
export function create_pn_counter(document) {
  let _pipe = $runtime.create_pn_counter(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new PnCounter(document.runtime, address); },
  );
}

/**
 * Make sure that a PN-counter exists under `field`. If the slot is empty, the
 * function creates one.
 */
export function ensure_pn_counter(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_pn_counter(document),
        (pn_counter) => {
          return set_pn_counter_field(typed_map, field, pn_counter);
        },
      );
    },
    () => { return resolve_pn_counter_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new grow-only counter channel. The detached lifecycle is the same
 * as for `create_map`.
 */
export function create_g_counter(document) {
  let _pipe = $runtime.create_g_counter(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new GCounter(document.runtime, address); },
  );
}

/**
 * Make sure that a grow-only counter exists under `field`. If the slot is
 * empty, the function creates one.
 */
export function ensure_g_counter(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_g_counter(document),
        (g_counter) => {
          return set_g_counter_field(typed_map, field, g_counter);
        },
      );
    },
    () => { return resolve_g_counter_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a detached string register with an empty initial value.
 * The lifecycle is the same as for `create_map`.
 */
export function create_lww_register(document) {
  let _pipe = $runtime.create_lww_register(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new LwwRegister(document.runtime, address); },
  );
}

/**
 * Wait for synchronization, then adopt the register under `field`.
 * Create one if the field is empty.
 */
export function ensure_lww_register(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_lww_register(document),
        (register) => {
          return set_lww_register_field(typed_map, field, register);
        },
      );
    },
    () => { return resolve_lww_register_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new PactMap channel. The detached lifecycle is the same as for
 * `create_map`.
 */
export function create_pact_map(document) {
  let _pipe = $runtime.create_pact_map(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new PactMap(document.runtime, address); },
  );
}

/**
 * Make sure that a PactMap exists under `field`.
 */
export function ensure_pact_map(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_pact_map(document),
        (pact_map) => { return set_pact_map_field(typed_map, field, pact_map); },
      );
    },
    () => { return resolve_pact_map_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new ConsensusOrderedCollection channel. The detached lifecycle is
 * the same as for `create_map`.
 */
export function create_ordered_collection(document) {
  let _pipe = $runtime.create_ordered_collection(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new OrderedCollection(document.runtime, address); },
  );
}

/**
 * Make sure that an ordered collection exists under `field`.
 */
export function ensure_ordered_collection(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_ordered_collection(document),
        (collection) => {
          return set_ordered_collection_field(typed_map, field, collection);
        },
      );
    },
    () => {
      return resolve_ordered_collection_field(document, typed_map, field);
    },
    done,
  );
}

/**
 * Create a new json0 channel. The detached lifecycle is the same as for
 * `create_map`. The channel is local only, until a caller stores its handle,
 * from `json_ot_handle_of`, into an attached container.
 */
export function create_json_ot(document) {
  let _pipe = $runtime.create_json_ot(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new JsonOt(document.runtime, address); },
  );
}

/**
 * Make sure that a json0 channel exists under `field`. If none exists, the
 * function creates one.
 */
export function ensure_json_ot(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_json_ot(document),
        (json_ot) => { return set_json_ot_field(typed_map, field, json_ot); },
      );
    },
    () => { return resolve_json_ot_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new rich-text channel. The detached lifecycle is the same as for
 * `create_map`. The channel is local only, until a caller stores its handle,
 * from `rich_text_handle_of`, into an attached container.
 */
export function create_rich_text(document) {
  let _pipe = $runtime.create_rich_text(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedRichText(document.runtime, address); },
  );
}

/**
 * Make sure that a rich-text channel exists under `field`. If none exists,
 * the function creates one.
 */
export function ensure_rich_text(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_rich_text(document),
        (rich_text) => {
          return set_rich_text_field(typed_map, field, rich_text);
        },
      );
    },
    () => { return resolve_rich_text_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new grow-only set channel. The detached lifecycle is the same as
 * for `create_map`. The channel is local only, until a caller stores its
 * handle, from `g_set_handle_of`, into an attached container.
 */
export function create_g_set(document) {
  let _pipe = $runtime.create_g_set(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new GSet(document.runtime, address); },
  );
}

/**
 * Make sure that a G-set exists under `field`. If none exists, the function
 * creates one.
 */
export function ensure_g_set(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_g_set(document),
        (set) => { return set_g_set_field(typed_map, field, set); },
      );
    },
    () => { return resolve_g_set_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new two-phase set channel. The detached lifecycle is the same as
 * for `create_map`. The channel is local only, until a caller stores its
 * handle, from `two_p_set_handle_of`, into an attached map. A remove writes a
 * permanent tombstone, and a remove wins against a concurrent add.
 */
export function create_two_p_set(document) {
  let _pipe = $runtime.create_two_p_set(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new TwoPSet(document.runtime, address); },
  );
}

/**
 * Make sure that a 2P-set exists under `field`. If none exists, the function
 * creates one.
 */
export function ensure_two_p_set(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_two_p_set(document),
        (set) => { return set_two_p_set_field(typed_map, field, set); },
      );
    },
    () => { return resolve_two_p_set_field(document, typed_map, field); },
    done,
  );
}

/**
 * Create a new directory channel, which is a hierarchical map keyed by
 * absolute paths. The root path is `"/"`. The detached lifecycle is the same
 * as for `create_map`. The channel is local only, until a caller stores its
 * handle, from `directory_handle_of`, into an attached map.
 */
export function create_directory(document) {
  let _pipe = $runtime.create_directory(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new SharedDirectory(document.runtime, address); },
  );
}

/**
 * Make sure that a directory exists under `field`. If none exists, the
 * function creates one.
 */
export function ensure_directory(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_directory(document),
        (directory) => {
          return set_directory_field(typed_map, field, directory);
        },
      );
    },
    () => { return resolve_directory_field(document, typed_map, field); },
    done,
  );
}

/**
 * Make sure that a nested *typed* child map exists under a child field.
 */
export function ensure_child(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.child_key(field),
    () => {
      return $result.map(
        create_map(document),
        (child) => { return set_child(typed_map, field, typed(child)); },
      );
    },
    () => { return resolve_child(document, typed_map, field); },
    done,
  );
}

/**
 * Set a plain typed field to `default`, and only when its key is absent now.
 * Every client in a race writes the value, and the last-writer-wins rule on
 * that key settles one of them.
 */
export function ensure_field(typed_map, field, default$) {
  let $ = has_field(typed_map, field);
  if ($) {
    return undefined;
  } else {
    return set_field(typed_map, field, default$);
  }
}

/**
 * Increment the counter optimistically. A negative amount decrements it.
 */
export function increment(counter, amount) {
  return $runtime.increment(counter.runtime, counter.address, amount);
}

/**
 * The current optimistic value of the counter. The result is `Error(Nil)` when the
 * address does not name a counter channel.
 */
export function counter_value(counter) {
  return $runtime.counter_value(counter.runtime, counter.address);
}

/**
 * Register `handler` for the events of a channel. The function calls that
 * handler only for the events that `narrow` accepts, and it decodes each one to
 * the event type of that channel kind. A subscriber thus never sees the union
 * of 14 variants. The `subscribe_*` function of each kind uses this
 * function.
 * 
 * @ignore
 */
function subscribe_narrowed(runtime, address, handler, narrow) {
  return new SubscriptionToken(
    $runtime.subscribe(
      runtime,
      address,
      (event) => {
        let $ = narrow(event);
        if ($ instanceof Some) {
          let inner = $[0];
          return handler(inner);
        } else {
          return undefined;
        }
      },
    ),
  );
}

/**
 * Remove one channel subscription. A second call has no more effect.
 */
export function unsubscribe(token) {
  return $runtime.unsubscribe(token.runtime_token);
}

/**
 * Register a callback for every local change and remote change to this counter
 * channel. The handler receives a `counter_kernel.CounterEvent` value, and it
 * receives no other kind of event.
 */
export function subscribe_counter(counter, handler) {
  return subscribe_narrowed(
    counter.runtime,
    counter.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function or_map_increment(or_map, key, amount) {
  return $runtime.or_map_increment(or_map.runtime, or_map.address, key, amount);
}

export function or_map_set(or_map, key, value) {
  return $runtime.or_map_set(or_map.runtime, or_map.address, key, value);
}

export function or_map_set_json(or_map, key, value) {
  return or_map_set(or_map, key, $json.to_string(value));
}

/**
 * Replace the observed alternatives of an MV-register key.
 */
export function or_map_set_mv_register(or_map, key, value) {
  return $runtime.or_map_set_mv_register(
    or_map.runtime,
    or_map.address,
    key,
    value,
  );
}

/**
 * Read MV-register alternatives. An absent key or another mode returns an error.
 */
export function or_map_values(or_map, key) {
  return $runtime.or_map_values(or_map.runtime, or_map.address, key);
}

export function or_map_remove(or_map, key) {
  return $runtime.or_map_remove(or_map.runtime, or_map.address, key);
}

/**
 * Add a string member in `OrSetMode`. An absent key becomes present.
 * A duplicate add replicates a fresh tag without a visible-value event.
 */
export function or_map_add_member(or_map, key, member) {
  return $runtime.or_map_add_member(or_map.runtime, or_map.address, key, member);
}

/**
 * Remove observed member tags in `OrSetMode`. An absent member is a no-op.
 * Removing the last member keeps the key present with `SetMembers([])`.
 */
export function or_map_remove_member(or_map, key, member) {
  return $runtime.or_map_remove_member(
    or_map.runtime,
    or_map.address,
    key,
    member,
  );
}

/**
 * Remove a key and return edit failures. In `OrSetMode`, this also clears
 * observed members. Concurrent unobserved additions survive.
 */
export function or_map_remove_key(or_map, key) {
  return $runtime.or_map_remove_key(or_map.runtime, or_map.address, key);
}

export function or_map_value(or_map, key) {
  return $runtime.or_map_value(or_map.runtime, or_map.address, key);
}

export function or_map_entries(or_map) {
  return $runtime.or_map_entries(or_map.runtime, or_map.address);
}

export function or_map_keys(or_map) {
  return $runtime.or_map_keys(or_map.runtime, or_map.address);
}

export function subscribe_or_map(or_map, handler) {
  return subscribe_narrowed(
    or_map.runtime,
    or_map.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function or_set_add(or_set, element) {
  return $runtime.or_set_add(or_set.runtime, or_set.address, element);
}

export function or_set_remove(or_set, element) {
  return $runtime.or_set_remove(or_set.runtime, or_set.address, element);
}

export function or_set_contains(or_set, element) {
  return $runtime.or_set_contains(or_set.runtime, or_set.address, element);
}

export function or_set_values(or_set) {
  return $runtime.or_set_values(or_set.runtime, or_set.address);
}

export function subscribe_or_set(or_set, handler) {
  return subscribe_narrowed(
    or_set.runtime,
    or_set.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Insert `value` at `index`, counted from zero, in the range `0` to the length
 * of the sequence.
 */
export function sequence_insert(sequence, index, value) {
  return $runtime.sequence_insert(
    sequence.runtime,
    sequence.address,
    index,
    value,
  );
}

/**
 * Delete the value at `index`, counted from zero, in the range `0` to
 * `length - 1`.
 */
export function sequence_delete(sequence, index) {
  return $runtime.sequence_delete(sequence.runtime, sequence.address, index);
}

/**
 * Move a value between two indexes, counted from zero. The function reads the
 * destination index after it removes the value from the source index.
 */
export function sequence_move(sequence, from_index, to_index) {
  return $runtime.sequence_move(
    sequence.runtime,
    sequence.address,
    from_index,
    to_index,
  );
}

/**
 * Replace the value at `index`, counted from zero, as one collaborative
 * operation.
 */
export function sequence_replace(sequence, index, value) {
  return $runtime.sequence_replace(
    sequence.runtime,
    sequence.address,
    index,
    value,
  );
}

export function sequence_values(sequence) {
  return $runtime.sequence_values(sequence.runtime, sequence.address);
}

export function sequence_length(sequence) {
  return $runtime.sequence_length(sequence.runtime, sequence.address);
}

export function subscribe_sequence(sequence, handler) {
  return subscribe_narrowed(
    sequence.runtime,
    sequence.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Insert `value` at the optimistic grapheme `index`, in the range `0` to the
 * length of the text. An empty `value` at a valid index changes nothing.
 */
export function text_insert(text, index, value) {
  return $runtime.text_insert(text.runtime, text.address, index, value);
}

/**
 * Delete the graphemes in `[start, end)`. An empty range with valid bounds
 * changes nothing.
 */
export function text_delete_range(text, start, end) {
  return $runtime.text_delete_range(text.runtime, text.address, start, end);
}

/**
 * Replace the graphemes in `[start, end)` with `value`, as one collaborative
 * operation. Only an empty range that you replace with `""` changes
 * nothing.
 */
export function text_replace_range(text, start, end, value) {
  return $runtime.text_replace_range(
    text.runtime,
    text.address,
    start,
    end,
    value,
  );
}

/**
 * Insert `value` at the end of the text. An empty `value` changes nothing.
 */
export function text_append(text, value) {
  return $runtime.text_append(text.runtime, text.address, value);
}

/**
 * The current visible optimistic string of the text.
 */
export function text_value(text) {
  return $runtime.text_value(text.runtime, text.address);
}

/**
 * The current optimistic grapheme count of the text.
 */
export function text_length(text) {
  return $runtime.text_length(text.runtime, text.address);
}

/**
 * The graphemes in `[start, end)` of the optimistic string of the text. The
 * result is an error string when the range `start..end` is invalid.
 */
export function text_substring(text, start, end) {
  return $runtime.text_substring(text.runtime, text.address, start, end);
}

/**
 * Create a stable anchor at the gap before the optimistic grapheme at `index`.
 * `bias_before` and `bias_after` set the bias. The result is an error string
 * when the index is out of bounds.
 */
export function text_anchor_at(text, index, bias) {
  return $runtime.text_anchor_at(text.runtime, text.address, index, bias);
}

/**
 * Resolve an anchor to a current optimistic grapheme index. The result is an
 * error string when the anchor target is stale or unknown.
 */
export function text_resolve_anchor(text, anchor) {
  return $runtime.text_resolve_anchor(text.runtime, text.address, anchor);
}

/**
 * An anchor at the start of the text. It always resolves to 0. The function is
 * pure. It needs no `SharedText` value, because the anchor carries no document
 * state.
 */
export function text_start_anchor() {
  return $runtime.text_start_anchor();
}

/**
 * An anchor at the end of the text. It always resolves to the current grapheme
 * count, and it moves as the text becomes longer. The function is pure, the
 * same as `text_start_anchor`.
 */
export function text_end_anchor() {
  return $runtime.text_end_anchor();
}

/**
 * Encode an anchor as a self-describing JSON value, for example to send it
 * through presence for a shared cursor.
 */
export function text_anchor_to_json(anchor) {
  return $runtime.text_anchor_to_json(anchor);
}

/**
 * Decode an anchor from a JSON string that `text_anchor_to_json` produced. The
 * result is an error string for malformed JSON.
 */
export function text_anchor_from_json(json_string) {
  return $runtime.text_anchor_from_json(json_string);
}

/**
 * Register a callback for every local change and remote change to this text
 * channel. The handler receives a `text_kernel.TextEvent` value, and it
 * receives no other kind of event.
 */
export function subscribe_text(text, handler) {
  return subscribe_narrowed(
    text.runtime,
    text.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        let inner = event[0];
        return new Some(inner);
      }
    },
  );
}

export function register_write(collection, key, value) {
  return $runtime.register_write(
    collection.runtime,
    collection.address,
    key,
    value,
  );
}

export function register_read(collection, key, policy) {
  return $runtime.register_read(
    collection.runtime,
    collection.address,
    key,
    policy,
  );
}

export function register_get(collection, key) {
  return register_read(collection, key, ReadPolicy$Atomic$const);
}

export function register_versions(collection, key) {
  return $runtime.register_versions(collection.runtime, collection.address, key);
}

export function register_keys(collection) {
  return $runtime.register_keys(collection.runtime, collection.address);
}

export function subscribe_register_collection(collection, handler) {
  return subscribe_narrowed(
    collection.runtime,
    collection.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function claim_once(claims, key, value) {
  return $runtime.claim_once(claims.runtime, claims.address, key, value);
}

export function compare_and_set_claim(claims, key, value) {
  return $runtime.compare_and_set_claim(
    claims.runtime,
    claims.address,
    key,
    value,
  );
}

export function get_claim(claims, key) {
  return $runtime.get_claim(claims.runtime, claims.address, key);
}

export function has_claim(claims, key) {
  return $runtime.has_claim(claims.runtime, claims.address, key);
}

export function subscribe_claims(claims, handler) {
  return subscribe_narrowed(
    claims.runtime,
    claims.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function volunteer_for_task(manager, task_id) {
  return $runtime.task_manager_volunteer(
    manager.runtime,
    manager.address,
    task_id,
  );
}

export function abandon_task(manager, task_id) {
  return $runtime.task_manager_abandon(
    manager.runtime,
    manager.address,
    task_id,
  );
}

export function complete_task(manager, task_id) {
  return $runtime.task_manager_complete(
    manager.runtime,
    manager.address,
    task_id,
  );
}

export function task_assigned(manager, task_id) {
  return $runtime.task_manager_assigned(
    manager.runtime,
    manager.address,
    task_id,
  );
}

export function task_queued(manager, task_id) {
  return $runtime.task_manager_queued(manager.runtime, manager.address, task_id);
}

export function task_queues(manager) {
  return $runtime.task_manager_queues(manager.runtime, manager.address);
}

export function subscribe_task_manager(manager, handler) {
  return subscribe_narrowed(
    manager.runtime,
    manager.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `amount` optimistically. A negative amount decrements the counter.
 */
export function pn_counter_update(pn_counter, amount) {
  return $runtime.pn_counter_update(
    pn_counter.runtime,
    pn_counter.address,
    amount,
  );
}

/**
 * The current optimistic value of the counter. The result is `Error(Nil)` when the
 * address does not name a PN-counter channel.
 */
export function pn_counter_value(pn_counter) {
  return $runtime.pn_counter_value(pn_counter.runtime, pn_counter.address);
}

/**
 * Register a callback for every local change and remote change to this
 * PN-counter.
 */
export function subscribe_pn_counter(pn_counter, handler) {
  return subscribe_narrowed(
    pn_counter.runtime,
    pn_counter.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `amount` optimistically. The amount must not be negative. The result is
 * an error with a description for a negative amount, and the counter does not
 * change.
 */
export function g_counter_increment(g_counter, amount) {
  return $runtime.g_counter_increment(
    g_counter.runtime,
    g_counter.address,
    amount,
  );
}

/**
 * The current optimistic value of the counter. The result is `Error(Nil)`
 * when the address does not name a grow-only counter channel.
 */
export function g_counter_value(g_counter) {
  return $runtime.g_counter_value(g_counter.runtime, g_counter.address);
}

/**
 * Register a callback for every local change and remote change to this
 * grow-only counter.
 */
export function subscribe_g_counter(g_counter, handler) {
  return subscribe_narrowed(
    g_counter.runtime,
    g_counter.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Create an empty detached map. Store its handle in an attached container
 * to replicate it.
 */
export function create_lww_map(document) {
  let _pipe = $runtime.create_lww_map(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new LwwMap(document.runtime, address); },
  );
}

export function lww_map_handle_of(map) {
  return $handle.encode_handle(map.address);
}

export function resolve_lww_map(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    let _pipe = $runtime.resolve_address(document.runtime, address);
    return $result.map(
      _pipe,
      (_) => { return new LwwMap(document.runtime, address); },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

export function set_lww_map_field(typed_map, field, map) {
  return put_channel_field(typed_map, field, lww_map_handle_of(map));
}

export function resolve_lww_map_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_lww_map);
}

/**
 * Wait for synchronization, then adopt the map or create one.
 */
export function ensure_lww_map(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_lww_map(document),
        (map) => { return set_lww_map_field(typed_map, field, map); },
      );
    },
    () => { return resolve_lww_map_field(document, typed_map, field); },
    done,
  );
}

/**
 * Set a string with the runtime clock. Return channel and clock errors.
 */
export function lww_map_set(map, key, value) {
  return $runtime.lww_map_set(map.runtime, map.address, key, value);
}

/**
 * Retain a tombstone even if the key is absent.
 */
export function lww_map_remove(map, key) {
  return $runtime.lww_map_remove(map.runtime, map.address, key);
}

/**
 * Read the optimistic value. Missing keys and wrong channel kinds return an error.
 */
export function lww_map_get(map, key) {
  return $runtime.lww_map_get(map.runtime, map.address, key);
}

/**
 * Read visible entries in key order.
 */
export function lww_map_entries(map) {
  return $runtime.lww_map_entries(map.runtime, map.address);
}

export function lww_map_keys(map) {
  return $runtime.lww_map_keys(map.runtime, map.address);
}

/**
 * Subscribe to visible changes. Metadata-only edits emit no event.
 */
export function subscribe_lww_map(map, handler) {
  return subscribe_narrowed(
    map.runtime,
    map.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Set the value optimistically with a timestamp from the runtime.
 * A same-value write replicates newer metadata without a change event.
 * Return channel and clock failures to the caller.
 */
export function lww_register_set(register, value) {
  return $runtime.lww_register_set(register.runtime, register.address, value);
}

/**
 * Read the optimistic value. Return `Error(Nil)` if the address does not
 * name an LWW-register channel.
 */
export function lww_register_value(register) {
  return $runtime.lww_register_value(register.runtime, register.address);
}

/**
 * Register a callback for local and remote visible-value changes.
 */
export function subscribe_lww_register(register, handler) {
  return subscribe_narrowed(
    register.runtime,
    register.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Propose `value` for `key`. This write is a consensus write, and it is not
 * optimistic. The value stays pending until the server sequencing accepts
 * it.
 */
export function pact_map_set(pact_map, key, value) {
  return $runtime.pact_map_set(pact_map.runtime, pact_map.address, key, value);
}

/**
 * Propose a delete for `key`. A delete writes a tombstone.
 */
export function pact_map_delete(pact_map, key) {
  return $runtime.pact_map_delete(pact_map.runtime, pact_map.address, key);
}

/**
 * The accepted value for `key`. The result is `Error(Nil)` when the value is
 * pending, when the key is absent, and when the address does not name a
 * PactMap channel.
 */
export function pact_map_get(pact_map, key) {
  return $runtime.pact_map_get(pact_map.runtime, pact_map.address, key);
}

/**
 * Every key with an accepted pact or a pending pact.
 */
export function pact_map_keys(pact_map) {
  return $runtime.pact_map_keys(pact_map.runtime, pact_map.address);
}

/**
 * Register a callback for the consensus transitions of this PactMap. Those
 * transitions are `WentPending`, when a proposal sequences, and
 * `WentAccepted`, when its signoff list becomes empty.
 *
 * Those two transitions *are* the protocol. Without this callback a PactMap
 * only accepts a write and answers a read. An application can then propose a
 * value and read a value, and it cannot learn that the proposal of a peer
 * arrived. That one difference separates a PactMap from a map.
 */
export function subscribe_pact_map(pact_map, handler) {
  return subscribe_narrowed(
    pact_map.runtime,
    pact_map.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Whether `key` has a proposal now that no room has settled, which is a
 * pending proposal.
 */
export function pact_map_is_pending(pact_map, key) {
  return $runtime.pact_map_is_pending(pact_map.runtime, pact_map.address, key);
}

/**
 * The full pending proposal for `key`, which is the value that waits for
 * agreement, with the signoff list that it waits on. The result is `Error(Nil)` when
 * nothing is pending.
 */
export function pact_map_pending(pact_map, key) {
  return $runtime.pact_map_pending(pact_map.runtime, pact_map.address, key);
}

/**
 * The clients whose agreement `key` still waits on. The result is `Error(Nil)` when
 * nothing is pending.
 *
 * This list changes a progress indicator into an explanation.
 * `pact_map_is_pending` reports *that* a value is unsettled. This function
 * reports *which clients* it waits on. The kernel freezes the list from the
 * connected roster when the proposal sequences, so the list names the room at
 * that moment. A client that left after that moment leaves the list when its
 * `"leave"` message sequences, and not before.
 */
export function pact_map_pending_signoffs(pact_map, key) {
  let _pipe = pact_map_pending(pact_map, key);
  return $result.map(_pipe, (pending) => { return pending.expected_signoffs; });
}

/**
 * The accepted entry for `key`: the agreed value, with the sequence number
 * that it settled at. The result is `Error(Nil)` when the key is absent, and when
 * the value is still pending.
 */
export function pact_map_get_with_details(pact_map, key) {
  return $runtime.pact_map_get_with_details(
    pact_map.runtime,
    pact_map.address,
    key,
  );
}

/**
 * Add `value` at the end of the collection.
 */
export function ordered_add(collection, value) {
  return $runtime.ordered_add(collection.runtime, collection.address, value);
}

/**
 * Acquire the head item, and return the acquire id. A later `complete` call or
 * `release` call uses that id.
 */
export function ordered_acquire(collection) {
  return $runtime.ordered_acquire(collection.runtime, collection.address);
}

/**
 * The same as `ordered_acquire`, and the function also reports the consensus
 * outcome of the acquire.
 *
 * `on_outcome` runs exactly one time. It gives `AcquiredItem` when this client
 * won the head. It gives `QueueEmpty` when the queue became empty before the
 * operation sequenced. An acquire that loses emits no event, so `QueueEmpty`
 * is the only signal that a loser receives. It gives `Aborted` when the
 * document closes while the acquire is still in flight.
 */
export function ordered_acquire_with_outcome(collection, on_outcome) {
  return $runtime.ordered_acquire_with_outcome(
    collection.runtime,
    collection.address,
    on_outcome,
  );
}

/**
 * Complete an acquired item, and remove it permanently.
 */
export function ordered_complete(collection, acquire_id) {
  return $runtime.ordered_complete(
    collection.runtime,
    collection.address,
    acquire_id,
  );
}

/**
 * Release an acquired item back to the collection, for another consumer.
 */
export function ordered_release(collection, acquire_id) {
  return $runtime.ordered_release(
    collection.runtime,
    collection.address,
    acquire_id,
  );
}

/**
 * The number of items in the collection now. The result is `Error(Nil)` when the
 * address does not name an ordered-collection channel.
 */
export function ordered_size(collection) {
  return $runtime.ordered_size(collection.runtime, collection.address);
}

/**
 * The values in the queue, which no client acquired yet, front first.
 */
export function ordered_queue(collection) {
  return $runtime.ordered_queue(collection.runtime, collection.address);
}

/**
 * The jobs that clients hold now, keyed by acquire id and sorted by that id.
 */
export function ordered_jobs(collection) {
  return $runtime.ordered_jobs(collection.runtime, collection.address);
}

/**
 * Register a callback for the queue events of this ordered collection. Those
 * events report an item that a client added, acquired, or completed, and an
 * item that the kernel released again after a client left.
 */
export function subscribe_ordered_collection(collection, handler) {
  return subscribe_narrowed(
    collection.runtime,
    collection.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Submit a json0 operation to the channel, optimistically. An operation is a
 * list of components.
 */
export function submit_json_ot(json_ot, operation) {
  return $runtime.submit_json_ot(json_ot.runtime, json_ot.address, operation);
}

/**
 * The current optimistic document of the json0 channel. The result is `Error(Nil)`
 * when the address does not name a json0 channel.
 */
export function json_ot_view(json_ot) {
  return $runtime.json_ot_view(json_ot.runtime, json_ot.address);
}

/**
 * Register a callback for every local change and remote change to this json0
 * channel.
 */
export function subscribe_json_ot(json_ot, handler) {
  return subscribe_narrowed(
    json_ot.runtime,
    json_ot.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Submit a rich-text delta to the channel, optimistically.
 */
export function submit_rich_text(rich_text, delta) {
  return $runtime.submit_rich_text(rich_text.runtime, rich_text.address, delta);
}

/**
 * The current optimistic rich-text document of the channel. The result is
 * `Error(Nil)` when the address does not name a rich-text channel.
 */
export function rich_text_view(rich_text) {
  return $runtime.rich_text_view(rich_text.runtime, rich_text.address);
}

/**
 * Register a callback for every local change and remote change to this
 * rich-text channel.
 */
export function subscribe_rich_text(rich_text, handler) {
  return subscribe_narrowed(
    rich_text.runtime,
    rich_text.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        let inner = event[0];
        return new Some(inner);
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `element` to the set, optimistically.
 */
export function g_set_add(set, element) {
  return $runtime.g_set_add(set.runtime, set.address, element);
}

/**
 * Whether `element` is in the current optimistic state of the set.
 */
export function g_set_contains(set, element) {
  return $runtime.g_set_contains(set.runtime, set.address, element);
}

/**
 * The current optimistic members of the set.
 */
export function g_set_values(set) {
  return $runtime.g_set_values(set.runtime, set.address);
}

/**
 * Register a callback for every local change and remote change to this set.
 */
export function subscribe_g_set(set, handler) {
  return subscribe_narrowed(
    set.runtime,
    set.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Add `element` to the set, optimistically. If you add an element that a client
 * removed before, the kernel records the add, and the element does not become
 * active again.
 */
export function two_p_set_add(set, element) {
  return $runtime.two_p_set_add(set.runtime, set.address, element);
}

/**
 * Remove `element` from the set, optimistically. A remove writes a permanent
 * tombstone.
 */
export function two_p_set_remove(set, element) {
  return $runtime.two_p_set_remove(set.runtime, set.address, element);
}

/**
 * Whether `element` is in the current optimistic state of the set.
 */
export function two_p_set_contains(set, element) {
  return $runtime.two_p_set_contains(set.runtime, set.address, element);
}

/**
 * The current optimistic members of the set.
 */
export function two_p_set_values(set) {
  return $runtime.two_p_set_values(set.runtime, set.address);
}

/**
 * Register a callback for every local change and remote change to this set.
 */
export function subscribe_two_p_set(set, handler) {
  return subscribe_narrowed(
    set.runtime,
    set.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Set `key` to `value` in the subdirectory at `path`, optimistically. The root
 * path is `"/"`. This function attaches each detached channel referenced by
 * `value` before it submits the directory operation.
 */
export function directory_set(directory, path, key, value) {
  return $runtime.directory_set(
    directory.runtime,
    directory.address,
    path,
    key,
    value,
  );
}

/**
 * Remove `key` from the subdirectory at `path`, optimistically.
 */
export function directory_delete(directory, path, key) {
  return $runtime.directory_delete(
    directory.runtime,
    directory.address,
    path,
    key,
  );
}

/**
 * Remove every key from the subdirectory at `path`, optimistically.
 */
export function directory_clear(directory, path) {
  return $runtime.directory_clear(directory.runtime, directory.address, path);
}

/**
 * Create a subdirectory named `name` under `path`, optimistically.
 */
export function directory_create_subdirectory(directory, path, name) {
  return $runtime.directory_create_subdirectory(
    directory.runtime,
    directory.address,
    path,
    name,
  );
}

/**
 * Delete the subdirectory named `name` under `path`, optimistically. The
 * delete also removes every value in that subdirectory.
 */
export function directory_delete_subdirectory(directory, path, name) {
  return $runtime.directory_delete_subdirectory(
    directory.runtime,
    directory.address,
    path,
    name,
  );
}

/**
 * The current optimistic value at `key`, in the subdirectory at `path`. The
 * result is `Error(Nil)` when the key is absent.
 */
export function directory_get(directory, path, key) {
  return $runtime.directory_get(directory.runtime, directory.address, path, key);
}

/**
 * The current optimistic `#(key, value)` entries in the subdirectory at
 * `path`.
 */
export function directory_entries(directory, path) {
  return $runtime.directory_entries(directory.runtime, directory.address, path);
}

/**
 * The names of the direct subdirectories under `path`.
 */
export function directory_subdirectories(directory, path) {
  return $runtime.directory_subdirectories(
    directory.runtime,
    directory.address,
    path,
  );
}

/**
 * Whether a subdirectory named `name` exists under `path`.
 */
export function directory_has_subdirectory(directory, path, name) {
  return $runtime.directory_has_subdirectory(
    directory.runtime,
    directory.address,
    path,
    name,
  );
}

/**
 * Register a callback for every local change and remote change to this
 * directory.
 */
export function subscribe_directory(directory, handler) {
  return subscribe_narrowed(
    directory.runtime,
    directory.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

export function close(document) {
  return $runtime.close(document.runtime);
}

/**
 * A hook that injects a fault, for a test or a demo. It closes the socket, so
 * that the client runs the reconnect and reconcile path. The pending edits and
 * the in-flight edits all stay.
 */
export function force_reconnect(document) {
  return $runtime.force_reconnect(document.runtime);
}

/**
 * Go offline and stay offline. The document continues to answer a read and to
 * accept an edit. The edits queue as pending entries, and they go out when
 * `go_online` reconnects.
 *
 * This function is `force_reconnect` with a pause. `force_reconnect` goes away
 * and comes back in one step, which leaves no interval to edit in. `close`
 * cannot replace it either, because `close` ends the runtime. To come back
 * after a `close` needs a new `connect` call, and the empty core of that
 * runtime holds none of the edits from the offline interval.
 *
 * The function does nothing unless the document is connected, so an interface
 * can bind it directly to a toggle:
 *
 * ```gleam
 * case offline {
 *   True -> watershed.go_offline(document)
 *   False -> watershed.go_online(document)
 * }
 * ```
 *
 * While the document is offline, `diagnostics(document).phase` is
 * `"reconnecting"`, and `in_flight_count` is the number of edits that wait to
 * reach the server. An indicator that reads "3 changes not yet saved" needs
 * that count.
 */
export function go_offline(document) {
  return $runtime.go_offline(document.runtime);
}

/**
 * Return from `go_offline`. The client replays the interval and sends the edits
 * from it. The function does nothing unless the document is offline now.
 */
export function go_online(document) {
  return $runtime.go_online(document.runtime);
}

/**
 * The id that the server assigned to this client. The result is `None` until
 * the first handshake completes.
 *
 * You need this id to find your own identity in a list from *another*
 * component. A consensus kernel reports its membership as the integer ids that
 * it uses to tie-break. `pact_map_pending_signoffs` of a `PactMap` is one
 * example. Without this id you cannot find the entry of your own tab. Convert
 * the id with `watershed/client_id.to_int`. That function performs the same
 * derivation as the runtime and the kernels, so the two results always
 * agree.
 *
 * ```gleam
 * let mine = watershed.client_id(document) |> option.map(client_id.to_int)
 * let waiting_on_me = case mine, pact_map_pending_signoffs(pact, "bpm") {
 *   Some(me), Some(ids) -> list.contains(ids, me)
 *   _, _ -> False
 * }
 * ```
 *
 * Read this id again after a reconnect. Do not cache it. The new handshake can
 * assign a different id, and a stale id then matches nothing, and it reports
 * nothing.
 */
export function client_id(document) {
  return $runtime.client_id(document.runtime);
}

/**
 * Broadcast an ephemeral ripple to every other connected client. A ripple has
 * a `type` tag and any JSON `content`. It expects no reply, and it has no
 * order, no ack, and no catch-up. The function does nothing until the first
 * handshake assigns a client id.
 */
export function submit_ripple(document, ripple_type, content) {
  return $runtime.send_ripple(document.runtime, ripple_type, content);
}

/**
 * Register a callback for every inbound ripple on the document.
 */
export function subscribe_ripples(document, handler) {
  return $runtime.subscribe_ripples(
    document.runtime,
    (signal) => { return handler(new Ripple(signal)); },
  );
}

/**
 * The `type` tag of the ripple, if the ripple has one.
 */
export function ripple_type(ripple) {
  return ripple.signal.signal_type;
}

/**
 * The JSON payload of the ripple. The wire carries only JSON in this field.
 * The function gives the payload as `Json`, and the caller decodes it with
 * `gleam/json`.
 */
export function ripple_content(ripple) {
  return $wire.dynamic_to_json(ripple.signal.content);
}

/**
 * The id of the client that sent the ripple, if the server stamped one. The
 * result is `None` for a ripple that the server produced.
 */
export function ripple_client_id(ripple) {
  return ripple.signal.client_id;
}

/**
 * Take a snapshot of the connection state and the sequencing state of the
 * document runtime.
 */
export function diagnostics(document) {
  return $runtime.diagnostics(document.runtime);
}

/**
 * Summarize the current confirmed state of the document to the storage of
 * floodgate. A later client can then start from that snapshot, and it does not
 * replay the full operation history. The promise resolves after publication
 * with the Git commit ID from `summaryAck`. The connection must be synchronized,
 * and the token must carry the `summary:write` scope.
 */
export function summarize(document) {
  return $runtime.summarize(document.runtime);
}

/**
 * Set or re-enable the automatic summary policy for this client.
 *
 * New connections use `summary_policy.policy()`: a threshold of 500 sequenced
 * messages and a 3 second delay window. This function replaces that policy.
 * The runtime attempts a checkpoint when the threshold is reached and this
 * client is settled. A later client can load the checkpoint and replay the
 * subsequent messages.
 *
 * It is safe to install the policy on every client in a room. The attempts
 * spread across a delay window, and the first summary that sequences stops the
 * other attempts. A lost race costs one unnecessary upload.
 *
 * The token must carry the `summary:write` scope, which `connect` includes by
 * default. The policy applies from the next sequenced operation.
 */
export function auto_summarize(document, policy) {
  return $runtime.auto_summarize(document.runtime, new Some(policy));
}

/**
 * Stop the automatic summaries. An attempt that is already scheduled still
 * checks again before it acts, and it then finds no policy.
 * An upload that has already started can finish. Other clients keep their
 * policies.
 */
export function stop_auto_summarize(document) {
  return $runtime.auto_summarize(document.runtime, Option$None$const);
}

/**
 * The number of messages that sequenced after the newest summary that this
 * client knows about. An automatic policy compares that number with its
 * threshold, and a client that joins replays those messages on top of the
 * checkpoint.
 *
 * On a document that no client has summarized, this number is the whole
 * log.
 */
export function operations_since_summary(document) {
  return $runtime.operations_since_summary(document.runtime);
}

/**
 * List the published summary commits of the document, newest first. This is
 * the client half of the `getVersions` function of Fluid. Each successful
 * `summarize` call publishes one version. A new connection starts from the newest one. The
 * token must carry the `doc:read` scope.
 */
export function get_versions(document, count) {
  return $runtime.get_versions(document.runtime, count);
}

/**
 * Read the confirmed state that a published summary commit captured.
 * `get_versions` and the resolution of `summarize` both give the commit ID.
 * The function returns the stored snapshot blob, which holds the
 * entries in insertion order with the sequence number that the writer captured
 * them at. The read is at one point in time, and it does not change the live
 * document.
 */
export function load_version(document, handle) {
  return $runtime.load_version(document.runtime, handle);
}

export function clear(map) {
  return $runtime.clear(map.runtime, map.address);
}

export function keys(map) {
  return $runtime.keys(map.runtime, map.address);
}

export function size(map) {
  return $runtime.size(map.runtime, map.address);
}

/**
 * Register a callback for every local change and remote change to this map
 * channel. The handler receives a `map_kernel.MapEvent` value, and it receives
 * no other kind of event.
 */
export function subscribe(map, handler) {
  return subscribe_narrowed(
    map.runtime,
    map.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}

/**
 * Subscribe to the whole-map events of a typed map, and stay in the typed API.
 * `handler` receives a `map_kernel.MapEvent` value and no other kind of event,
 * the same as in `subscribe`. Use `subscribe_field` instead to watch one typed
 * field.
 */
export function subscribe_typed(typed_map, handler) {
  return subscribe(typed_map.map, handler);
}

/**
 * Convert a channel event from the fan-out into a typed change for `field`,
 * which is under `key`. The result is `None` when the event is for another
 * key, and when it is for another channel kind.
 * 
 * @ignore
 */
function field_change(field, key, event) {
  if (event instanceof $channel.MapEvent) {
    let $ = event[0];
    if ($ instanceof $map_kernel.ValueChanged) {
      let k = $.key;
      if (k === key) {
        let previous = $.previous_value;
        let value = $.value;
        let local = $.local;
        return new Some(
          new $schema.FieldChange(
            $schema.decode_optional(field, value),
            $schema.decode_optional(field, previous),
            local,
          ),
        );
      } else {
        return Option$None$const;
      }
    } else {
      let local = $.local;
      return new Some(
        new $schema.FieldChange(
          new Ok(Option$None$const),
          new Ok(Option$None$const),
          local,
        ),
      );
    }
  } else if (event instanceof $channel.CounterEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.PnCounterEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.GCounterEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.LwwRegisterEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.LwwMapEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.MvRegisterEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.OrMapEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.OrSetEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.GSetEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.TwoPSetEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.RegisterCollectionEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.ClaimsEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.TaskManagerEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.PactMapEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.JsonOtEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.DirectoryEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.OrderedCollectionEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.SequenceEvent) {
    return Option$None$const;
  } else if (event instanceof $channel.RichTextEvent) {
    return Option$None$const;
  } else {
    return Option$None$const;
  }
}

/**
 * Subscribe to the changes of one typed field. Every local or remote write to
 * the key of `field` calls `handler` with a `FieldChange` value. That value
 * carries the new value and the previous value, both decoded at the boundary.
 * Each one is `Error(Invalid)` when a peer wrote a value that does not match
 * the field type. A `Cleared` event on the map arrives as
 * `FieldChange(Ok(None), Ok(None), local)`, because a clear carries no previous
 * value for each key.
 */
export function subscribe_field(typed_map, field, handler) {
  let key = $schema.field_key(field);
  return new SubscriptionToken(
    $runtime.subscribe(
      typed_map.map.runtime,
      typed_map.map.address,
      (event) => {
        let $ = field_change(field, key, event);
        if ($ instanceof Some) {
          let change = $[0];
          return handler(change);
        } else {
          return undefined;
        }
      },
    ),
  );
}

/**
 * Mint an HS256 development JWT for `just server`, which runs in development
 * mode. The function signs with Web Crypto, so the token resolves
 * asynchronously. Do not use this function in production. The tenant secret
 * must never reach the browser there.
 */
export function dev_token(secret, tenant, document, user_id) {
  return $transport_js.mint_dev_token(secret, tenant, document, user_id);
}

export function create_mv_register(document) {
  let _pipe = $runtime.create_mv_register(document.runtime);
  return $result.map(
    _pipe,
    (address) => { return new MvRegister(document.runtime, address); },
  );
}

export function mv_register_handle_of(mv_register) {
  return $handle.encode_handle(mv_register.address);
}

export function mv_register_values(mv_register) {
  return $runtime.mv_register_values(mv_register.runtime, mv_register.address);
}

export function resolve_mv_register(document, value) {
  let $ = $handle.parse_handle(value);
  if ($ instanceof Ok) {
    let address = $[0];
    return $result.try$(
      $runtime.resolve_address(document.runtime, address),
      (_) => {
        let register = new MvRegister(document.runtime, address);
        let _pipe = mv_register_values(register);
        let _pipe$1 = $result.replace_error(
          _pipe,
          "address does not name an MV-register channel",
        );
        return $result.map(_pipe$1, (_) => { return register; });
      },
    );
  } else {
    return new Error("value is not a handle marker");
  }
}

export function set_mv_register_field(typed_map, field, mv_register) {
  return put_channel_field(typed_map, field, mv_register_handle_of(mv_register));
}

export function resolve_mv_register_field(document, typed_map, field) {
  return get_channel_field(document, typed_map, field, resolve_mv_register);
}

export function ensure_mv_register(document, typed_map, field, done) {
  return ensure_channel(
    document,
    typed_map,
    $schema.channel_field_key(field),
    () => {
      return $result.map(
        create_mv_register(document),
        (mv_register) => {
          return set_mv_register_field(typed_map, field, mv_register);
        },
      );
    },
    () => { return resolve_mv_register_field(document, typed_map, field); },
    done,
  );
}

export function mv_register_set(mv_register, value) {
  return $runtime.mv_register_set(
    mv_register.runtime,
    mv_register.address,
    value,
  );
}

export function subscribe_mv_register(mv_register, handler) {
  return subscribe_narrowed(
    mv_register.runtime,
    mv_register.address,
    handler,
    (event) => {
      if (event instanceof $channel.MapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.CounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PnCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GCounterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwRegisterEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.LwwMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.MvRegisterEvent) {
        let inner = event[0];
        return new Some(inner);
      } else if (event instanceof $channel.OrMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.GSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TwoPSetEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RegisterCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.ClaimsEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.TaskManagerEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.PactMapEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.JsonOtEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.DirectoryEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.OrderedCollectionEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.SequenceEvent) {
        return Option$None$const;
      } else if (event instanceof $channel.RichTextEvent) {
        return Option$None$const;
      } else {
        return Option$None$const;
      }
    },
  );
}
