/// <reference types="./component.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $port from "../watershed/port.mjs";

/**
 * The config JSON did not match the descriptor's decoder.
 */
export class InvalidConfig extends $CustomType {
  constructor(kind, version, reason) {
    super();
    this.kind = kind;
    this.version = version;
    this.reason = reason;
  }
}
export const ComponentError$InvalidConfig = (kind, version, reason) =>
  new InvalidConfig(kind, version, reason);
export const ComponentError$isInvalidConfig = (value) =>
  value instanceof InvalidConfig;
export const ComponentError$InvalidConfig$kind = (value) => value.kind;
export const ComponentError$InvalidConfig$0 = (value) => value.kind;
export const ComponentError$InvalidConfig$version = (value) => value.version;
export const ComponentError$InvalidConfig$1 = (value) => value.version;
export const ComponentError$InvalidConfig$reason = (value) => value.reason;
export const ComponentError$InvalidConfig$2 = (value) => value.reason;

/**
 * The config JSON decoded, but the component's start function failed.
 */
export class StartFailed extends $CustomType {
  constructor(kind, version, reason) {
    super();
    this.kind = kind;
    this.version = version;
    this.reason = reason;
  }
}
export const ComponentError$StartFailed = (kind, version, reason) =>
  new StartFailed(kind, version, reason);
export const ComponentError$isStartFailed = (value) =>
  value instanceof StartFailed;
export const ComponentError$StartFailed$kind = (value) => value.kind;
export const ComponentError$StartFailed$0 = (value) => value.kind;
export const ComponentError$StartFailed$version = (value) => value.version;
export const ComponentError$StartFailed$1 = (value) => value.version;
export const ComponentError$StartFailed$reason = (value) => value.reason;
export const ComponentError$StartFailed$2 = (value) => value.reason;

/**
 * The descriptor does not have a matching typed input handler.
 */
export class InputUnavailable extends $CustomType {
  constructor(kind, version, input_id) {
    super();
    this.kind = kind;
    this.version = version;
    this.input_id = input_id;
  }
}
export const ComponentError$InputUnavailable = (kind, version, input_id) =>
  new InputUnavailable(kind, version, input_id);
export const ComponentError$isInputUnavailable = (value) =>
  value instanceof InputUnavailable;
export const ComponentError$InputUnavailable$kind = (value) => value.kind;
export const ComponentError$InputUnavailable$0 = (value) => value.kind;
export const ComponentError$InputUnavailable$version = (value) => value.version;
export const ComponentError$InputUnavailable$1 = (value) => value.version;
export const ComponentError$InputUnavailable$input_id = (value) =>
  value.input_id;
export const ComponentError$InputUnavailable$2 = (value) => value.input_id;

/**
 * The input payload did not match the handler's decoder.
 */
export class InvalidInputPayload extends $CustomType {
  constructor(kind, version, input_id, reason) {
    super();
    this.kind = kind;
    this.version = version;
    this.input_id = input_id;
    this.reason = reason;
  }
}
export const ComponentError$InvalidInputPayload = (kind, version, input_id, reason) =>
  new InvalidInputPayload(kind, version, input_id, reason);
export const ComponentError$isInvalidInputPayload = (value) =>
  value instanceof InvalidInputPayload;
export const ComponentError$InvalidInputPayload$kind = (value) => value.kind;
export const ComponentError$InvalidInputPayload$0 = (value) => value.kind;
export const ComponentError$InvalidInputPayload$version = (value) =>
  value.version;
export const ComponentError$InvalidInputPayload$1 = (value) => value.version;
export const ComponentError$InvalidInputPayload$input_id = (value) =>
  value.input_id;
export const ComponentError$InvalidInputPayload$2 = (value) => value.input_id;
export const ComponentError$InvalidInputPayload$reason = (value) =>
  value.reason;
export const ComponentError$InvalidInputPayload$3 = (value) => value.reason;

/**
 * The typed input handler rejected the delivery.
 */
export class InputFailed extends $CustomType {
  constructor(kind, version, input_id, reason) {
    super();
    this.kind = kind;
    this.version = version;
    this.input_id = input_id;
    this.reason = reason;
  }
}
export const ComponentError$InputFailed = (kind, version, input_id, reason) =>
  new InputFailed(kind, version, input_id, reason);
export const ComponentError$isInputFailed = (value) =>
  value instanceof InputFailed;
export const ComponentError$InputFailed$kind = (value) => value.kind;
export const ComponentError$InputFailed$0 = (value) => value.kind;
export const ComponentError$InputFailed$version = (value) => value.version;
export const ComponentError$InputFailed$1 = (value) => value.version;
export const ComponentError$InputFailed$input_id = (value) => value.input_id;
export const ComponentError$InputFailed$2 = (value) => value.input_id;
export const ComponentError$InputFailed$reason = (value) => value.reason;
export const ComponentError$InputFailed$3 = (value) => value.reason;

/**
 * The output is not declared by this descriptor.
 */
export class OutputUnavailable extends $CustomType {
  constructor(kind, version, output_id) {
    super();
    this.kind = kind;
    this.version = version;
    this.output_id = output_id;
  }
}
export const ComponentError$OutputUnavailable = (kind, version, output_id) =>
  new OutputUnavailable(kind, version, output_id);
export const ComponentError$isOutputUnavailable = (value) =>
  value instanceof OutputUnavailable;
export const ComponentError$OutputUnavailable$kind = (value) => value.kind;
export const ComponentError$OutputUnavailable$0 = (value) => value.kind;
export const ComponentError$OutputUnavailable$version = (value) =>
  value.version;
export const ComponentError$OutputUnavailable$1 = (value) => value.version;
export const ComponentError$OutputUnavailable$output_id = (value) =>
  value.output_id;
export const ComponentError$OutputUnavailable$2 = (value) => value.output_id;

/**
 * The component could not release its local resources.
 */
export class StopFailed extends $CustomType {
  constructor(kind, version, reason) {
    super();
    this.kind = kind;
    this.version = version;
    this.reason = reason;
  }
}
export const ComponentError$StopFailed = (kind, version, reason) =>
  new StopFailed(kind, version, reason);
export const ComponentError$isStopFailed = (value) =>
  value instanceof StopFailed;
export const ComponentError$StopFailed$kind = (value) => value.kind;
export const ComponentError$StopFailed$0 = (value) => value.kind;
export const ComponentError$StopFailed$version = (value) => value.version;
export const ComponentError$StopFailed$1 = (value) => value.version;
export const ComponentError$StopFailed$reason = (value) => value.reason;
export const ComponentError$StopFailed$2 = (value) => value.reason;

export const ComponentError$kind = (value) => value.kind;
export const ComponentError$version = (value) => value.version;

/**
 * A descriptor with the same kind and version is already in the catalog.
 */
export class DuplicateRegistration extends $CustomType {
  constructor(kind, version) {
    super();
    this.kind = kind;
    this.version = version;
  }
}
export const RegistrationError$DuplicateRegistration = (kind, version) =>
  new DuplicateRegistration(kind, version);
export const RegistrationError$isDuplicateRegistration = (value) =>
  value instanceof DuplicateRegistration;
export const RegistrationError$DuplicateRegistration$kind = (value) =>
  value.kind;
export const RegistrationError$DuplicateRegistration$0 = (value) => value.kind;
export const RegistrationError$DuplicateRegistration$version = (value) =>
  value.version;
export const RegistrationError$DuplicateRegistration$1 = (value) =>
  value.version;

/**
 * The catalog holds no descriptor for this kind, at any version.
 */
export class NotRegistered extends $CustomType {
  constructor(kind) {
    super();
    this.kind = kind;
  }
}
export const LookupError$NotRegistered = (kind) => new NotRegistered(kind);
export const LookupError$isNotRegistered = (value) =>
  value instanceof NotRegistered;
export const LookupError$NotRegistered$kind = (value) => value.kind;
export const LookupError$NotRegistered$0 = (value) => value.kind;

/**
 * The catalog holds this kind, but not the requested version.
 * `available` lists the registered versions of the kind, from the lowest
 * version to the highest version.
 */
export class UnsupportedVersion extends $CustomType {
  constructor(kind, requested, available) {
    super();
    this.kind = kind;
    this.requested = requested;
    this.available = available;
  }
}
export const LookupError$UnsupportedVersion = (kind, requested, available) =>
  new UnsupportedVersion(kind, requested, available);
export const LookupError$isUnsupportedVersion = (value) =>
  value instanceof UnsupportedVersion;
export const LookupError$UnsupportedVersion$kind = (value) => value.kind;
export const LookupError$UnsupportedVersion$0 = (value) => value.kind;
export const LookupError$UnsupportedVersion$requested = (value) =>
  value.requested;
export const LookupError$UnsupportedVersion$1 = (value) => value.requested;
export const LookupError$UnsupportedVersion$available = (value) =>
  value.available;
export const LookupError$UnsupportedVersion$2 = (value) => value.available;

export const LookupError$kind = (value) => value.kind;

class OutputEvent extends $CustomType {
  constructor(id, schema_id, payload) {
    super();
    this.id = id;
    this.schema_id = schema_id;
    this.payload = payload;
  }
}

class OutputEmitter extends $CustomType {
  constructor(publish) {
    super();
    this.publish = publish;
  }
}

class InputHandler extends $CustomType {
  constructor(descriptor, deliver) {
    super();
    this.descriptor = descriptor;
    this.deliver = deliver;
  }
}

class HandlerInvalidPayload extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}

class HandlerFailed extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}

class Descriptor extends $CustomType {
  constructor(kind, version, ports, validate_config, start, inputs, stop) {
    super();
    this.kind = kind;
    this.version = version;
    this.ports = ports;
    this.validate_config = validate_config;
    this.start = start;
    this.inputs = inputs;
    this.stop = stop;
  }
}

class Catalog extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}

/**
 * Build an executable descriptor for one component kind.
 *
 * `start_component` calls `done` after the component has bootstrapped its
 * channels and installed its required subscriptions. The runtime does not
 * mark the instance ready before that callback.
 *
 * Call `done` exactly once. The first completion consumes the invocation.
 * An `Ok` first completion transfers the running value to the host.
 * The host stops a first late success if its generation is obsolete.
 * A duplicate completion transfers no ownership:
 * the starter must release any extra resources without stopping the accepted
 * value. The JavaScript host reports the violation and does not use the value.
 * An incomplete start stays pending until removal or shutdown. It has no
 * timeout.
 *
 * A starter that throws before it transfers resources through `done` must
 * release those resources itself. The host can release only resources it
 * owns. Rejecting returned state does not undo earlier channel mutations.
 *
 * `inputs` must contain the handlers for the input descriptors in `ports`.
 * Delivery rejects a missing handler or metadata that does not match the
 * handler's typed port.
 */
export function executable_descriptor(
  kind,
  version,
  config_decoder,
  start_component,
  inputs,
  stop_component,
  ports
) {
  let decode_config = (encoded) => {
    let $ = $json.parse($json.to_string(encoded), config_decoder);
    if ($ instanceof Ok) {
      return $;
    } else {
      let reason = $[0];
      return new Error(new InvalidConfig(kind, version, reason));
    }
  };
  return new Descriptor(
    kind,
    version,
    ports,
    (encoded) => {
      let _pipe = decode_config(encoded);
      return $result.map(_pipe, (_) => { return undefined; });
    },
    (context, encoded, done) => {
      let $ = decode_config(encoded);
      if ($ instanceof Ok) {
        let config = $[0];
        return start_component(
          context,
          config,
          (started) => {
            return done(
              (() => {
                let _pipe = started;
                return $result.map_error(
                  _pipe,
                  (reason) => { return new StartFailed(kind, version, reason); },
                );
              })(),
            );
          },
        );
      } else {
        let reason = $[0];
        return done(new Error(reason));
      }
    },
    inputs,
    (running) => {
      let _pipe = stop_component(running);
      return $result.map_error(
        _pipe,
        (reason) => { return new StopFailed(kind, version, reason); },
      );
    },
  );
}

/**
 * Build a descriptor for one component kind.
 *
 * `kind` and `version` name the component. `config_decoder` turns the
 * component's config JSON into the typed `config` value that
 * `start_component` needs. `start_component` builds the running instance
 * from a context value and the decoded config, or returns
 * `Error(reason)` with a plain-text reason. `ports` lists the component's
 * port metadata.
 */
export function descriptor(
  kind,
  version,
  config_decoder,
  start_component,
  ports
) {
  return executable_descriptor(
    kind,
    version,
    config_decoder,
    (context, config, done) => { return done(start_component(context, config)); },
    $List$Empty$const,
    (_) => { return new Ok(undefined); },
    ports,
  );
}

/**
 * Build a typed input handler for an executable descriptor.
 *
 * An error rejects the returned state. It does not undo channel mutations
 * that the handler has already submitted.
 */
export function input_handler(input, handle) {
  return new InputHandler(
    $port.input_descriptor(input),
    (running, encoded) => {
      return $result.try$(
        (() => {
          let _pipe = $port.decode(input, encoded);
          return $result.map_error(
            _pipe,
            (var0) => { return new HandlerInvalidPayload(var0); },
          );
        })(),
        (payload) => {
          let _pipe = handle(running, payload);
          return $result.map_error(
            _pipe,
            (var0) => { return new HandlerFailed(var0); },
          );
        },
      );
    },
  );
}

/**
 * Encode one typed output event.
 */
export function emit(output, payload) {
  let $ = $port.output_descriptor(output);
  let id = $.id;
  let schema_id = $.schema_id;
  return new OutputEvent(id, schema_id, $port.encode(output, payload));
}

/**
 * Build an asynchronous output capability.
 *
 * Runtime adapters use this function to bind the capability to an instance.
 */
export function output_emitter(publish) {
  return new OutputEmitter(publish);
}

/**
 * Publish one batch of asynchronous outputs.
 */
export function publish(emitter, events) {
  return emitter.publish(events);
}

/**
 * The port ID of an encoded output event.
 */
export function output_id(event) {
  return event.id;
}

/**
 * The payload of an encoded output event.
 */
export function output_payload(event) {
  return event.payload;
}

/**
 * The component kind a descriptor names.
 */
export function kind(descriptor) {
  return descriptor.kind;
}

/**
 * The version a descriptor names.
 */
export function version(descriptor) {
  return descriptor.version;
}

/**
 * The port metadata a descriptor lists.
 */
export function ports(descriptor) {
  return descriptor.ports;
}

/**
 * Check config JSON against a descriptor's decoder, without starting the
 * component.
 */
export function validate_config(descriptor, config) {
  return descriptor.validate_config(config);
}

/**
 * Decode config JSON and start one running instance of a descriptor's
 * component.
 *
 * Returns `Error(InvalidConfig(..))` when the config JSON does not match
 * the descriptor's decoder, or `Error(StartFailed(..))` when the decoded
 * config is valid but the component's start function fails.
 */
export function start(descriptor, context, config, done) {
  return descriptor.start(context, config, done);
}

function matching_input(descriptor, input_id) {
  let _pipe = $list.find(
    descriptor.inputs,
    (handler) => {
      let $ = handler.descriptor;
      let id = $.id;
      return (id === input_id) && $list.contains(
        descriptor.ports,
        handler.descriptor,
      );
    },
  );
  let _pipe$1 = $result.map(_pipe, (var0) => { return new Some(var0); });
  return $result.unwrap(_pipe$1, Option$None$const);
}

/**
 * Deliver an encoded payload to one typed input handler.
 */
export function deliver(descriptor, running, input_id, payload) {
  let $ = matching_input(descriptor, input_id);
  if ($ instanceof Some) {
    let handler = $[0];
    let _pipe = handler.deliver(running, payload);
    return $result.map_error(
      _pipe,
      (reason) => {
        if (reason instanceof HandlerInvalidPayload) {
          let reason$1 = reason.reason;
          return new InvalidInputPayload(
            descriptor.kind,
            descriptor.version,
            input_id,
            reason$1,
          );
        } else {
          let reason$1 = reason.reason;
          return new InputFailed(
            descriptor.kind,
            descriptor.version,
            input_id,
            reason$1,
          );
        }
      },
    );
  } else {
    return new Error(
      new InputUnavailable(descriptor.kind, descriptor.version, input_id),
    );
  }
}

/**
 * Check that an output event belongs to this descriptor.
 */
export function validate_output(descriptor, event) {
  let declared = $list.any(
    descriptor.ports,
    (candidate) => {
      return isEqual(
        candidate,
        new $port.Descriptor(
          event.id,
          $port.Direction$OutputPort$const,
          event.schema_id,
        )
      );
    },
  );
  if (declared) {
    return new Ok(undefined);
  } else {
    return new Error(
      new OutputUnavailable(descriptor.kind, descriptor.version, event.id),
    );
  }
}

/**
 * Release one running component's local resources.
 */
export function stop(descriptor, running) {
  return descriptor.stop(running);
}

/**
 * An empty catalog.
 */
export function new_catalog() {
  return new Catalog($dict.new$());
}

/**
 * Add a descriptor to a catalog.
 *
 * Returns `Error(DuplicateRegistration(..))` when the catalog already
 * holds a descriptor with the same kind and version.
 */
export function register(catalog, descriptor) {
  let key = [descriptor.kind, descriptor.version];
  let $ = $dict.has_key(catalog.entries, key);
  if ($) {
    return new Error(
      new DuplicateRegistration(descriptor.kind, descriptor.version),
    );
  } else {
    return new Ok(new Catalog($dict.insert(catalog.entries, key, descriptor)));
  }
}

/**
 * The versions a catalog holds for one kind, from the lowest version to the
 * highest version. The sort keeps the list the same on every target.
 * 
 * @ignore
 */
function registered_versions(catalog, kind) {
  let _pipe = $dict.keys(catalog.entries);
  let _pipe$1 = $list.filter_map(
    _pipe,
    (key) => {
      let $ = key[0] === kind;
      if ($) {
        return new Ok(key[1]);
      } else {
        return new Error(undefined);
      }
    },
  );
  return $list.sort(_pipe$1, $int.compare);
}

/**
 * Find a descriptor in a catalog by kind and version.
 *
 * Returns `Error(NotRegistered(kind))` when the catalog holds no version of
 * the kind. Returns `Error(UnsupportedVersion(..))` when the catalog holds
 * the kind at other versions. The two errors let a caller show the correct
 * cause to a user: this host does not know the kind, or this host does not
 * register the requested version.
 */
export function find(catalog, kind, version) {
  let $ = $dict.get(catalog.entries, [kind, version]);
  if ($ instanceof Ok) {
    return $;
  } else {
    let $1 = registered_versions(catalog, kind);
    if ($1 instanceof $Empty) {
      return new Error(new NotRegistered(kind));
    } else {
      let available = $1;
      return new Error(new UnsupportedVersion(kind, version, available));
    }
  }
}
