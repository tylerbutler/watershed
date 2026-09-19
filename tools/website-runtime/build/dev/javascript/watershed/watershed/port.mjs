/// <reference types="./port.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

export class LocalInput extends $CustomType {}
export const InputClass$LocalInput$const = new LocalInput();
export const InputClass$LocalInput = () => InputClass$LocalInput$const;
export const InputClass$isLocalInput = (value) => value instanceof LocalInput;

export class CollaborativeInput extends $CustomType {
  constructor(capabilities) {
    super();
    this.capabilities = capabilities;
  }
}
export const InputClass$CollaborativeInput = (capabilities) =>
  new CollaborativeInput(capabilities);
export const InputClass$isCollaborativeInput = (value) =>
  value instanceof CollaborativeInput;
export const InputClass$CollaborativeInput$capabilities = (value) =>
  value.capabilities;
export const InputClass$CollaborativeInput$0 = (value) => value.capabilities;

export class OutputPort extends $CustomType {}
export const Direction$OutputPort$const = new OutputPort();
export const Direction$OutputPort = () => Direction$OutputPort$const;
export const Direction$isOutputPort = (value) => value instanceof OutputPort;

export class InputPort extends $CustomType {
  constructor(class$) {
    super();
    this.class = class$;
  }
}
export const Direction$InputPort = (class$) => new InputPort(class$);
export const Direction$isInputPort = (value) => value instanceof InputPort;
export const Direction$InputPort$class = (value) => value.class;
export const Direction$InputPort$0 = (value) => value.class;

export class OutputDirection extends $CustomType {}
export const DirectionKind$OutputDirection$const = new OutputDirection();
export const DirectionKind$OutputDirection = () =>
  DirectionKind$OutputDirection$const;
export const DirectionKind$isOutputDirection = (value) =>
  value instanceof OutputDirection;

export class InputDirection extends $CustomType {}
export const DirectionKind$InputDirection$const = new InputDirection();
export const DirectionKind$InputDirection = () =>
  DirectionKind$InputDirection$const;
export const DirectionKind$isInputDirection = (value) =>
  value instanceof InputDirection;

export class Descriptor extends $CustomType {
  constructor(id, direction, schema_id) {
    super();
    this.id = id;
    this.direction = direction;
    this.schema_id = schema_id;
  }
}
export const Descriptor$Descriptor = (id, direction, schema_id) =>
  new Descriptor(id, direction, schema_id);
export const Descriptor$isDescriptor = (value) => value instanceof Descriptor;
export const Descriptor$Descriptor$id = (value) => value.id;
export const Descriptor$Descriptor$0 = (value) => value.id;
export const Descriptor$Descriptor$direction = (value) => value.direction;
export const Descriptor$Descriptor$1 = (value) => value.direction;
export const Descriptor$Descriptor$schema_id = (value) => value.schema_id;
export const Descriptor$Descriptor$2 = (value) => value.schema_id;

class Output extends $CustomType {
  constructor(id, schema_id, encode) {
    super();
    this.id = id;
    this.schema_id = schema_id;
    this.encode = encode;
  }
}

class Input extends $CustomType {
  constructor(id, schema_id, decode, input_class) {
    super();
    this.id = id;
    this.schema_id = schema_id;
    this.decode = decode;
    this.input_class = input_class;
  }
}

export class ConnectionTemplate extends $CustomType {
  constructor(source_port, target_port, schema_id) {
    super();
    this.source_port = source_port;
    this.target_port = target_port;
    this.schema_id = schema_id;
  }
}
export const ConnectionTemplate$ConnectionTemplate = (source_port, target_port, schema_id) =>
  new ConnectionTemplate(source_port, target_port, schema_id);
export const ConnectionTemplate$isConnectionTemplate = (value) =>
  value instanceof ConnectionTemplate;
export const ConnectionTemplate$ConnectionTemplate$source_port = (value) =>
  value.source_port;
export const ConnectionTemplate$ConnectionTemplate$0 = (value) =>
  value.source_port;
export const ConnectionTemplate$ConnectionTemplate$target_port = (value) =>
  value.target_port;
export const ConnectionTemplate$ConnectionTemplate$1 = (value) =>
  value.target_port;
export const ConnectionTemplate$ConnectionTemplate$schema_id = (value) =>
  value.schema_id;
export const ConnectionTemplate$ConnectionTemplate$2 = (value) =>
  value.schema_id;

/**
 * The payload did not match the input port's decoder.
 */
export class InvalidPayload extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const PortError$InvalidPayload = (reason) => new InvalidPayload(reason);
export const PortError$isInvalidPayload = (value) =>
  value instanceof InvalidPayload;
export const PortError$InvalidPayload$reason = (value) => value.reason;
export const PortError$InvalidPayload$0 = (value) => value.reason;

/**
 * The output port and the input port carry different schema IDs.
 */
export class SchemaMismatch extends $CustomType {
  constructor(source, target) {
    super();
    this.source = source;
    this.target = target;
  }
}
export const PortError$SchemaMismatch = (source, target) =>
  new SchemaMismatch(source, target);
export const PortError$isSchemaMismatch = (value) =>
  value instanceof SchemaMismatch;
export const PortError$SchemaMismatch$source = (value) => value.source;
export const PortError$SchemaMismatch$0 = (value) => value.source;
export const PortError$SchemaMismatch$target = (value) => value.target;
export const PortError$SchemaMismatch$1 = (value) => value.target;

/**
 * Declare an output port.
 *
 * `id` names the port inside its component. `schema_id` names the payload
 * schema, and it must match the schema ID of any input port this output
 * connects to. `encode` turns one payload into JSON.
 *
 * The codec module owns the namespaced schema ID. Use a new schema version
 * for an incompatible payload change. Equal IDs do not prove codec agreement.
 */
export function output(id, schema_id, encode) {
  return new Output(id, schema_id, encode);
}

/**
 * Declare an input port that changes local state only.
 *
 * A local input changes this client's presentation state or controller
 * state, for example a selection or a filter. It does not change a
 * collaborative channel. It receives a payload only from a local intent.
 *
 * `id` names the port inside its component. `schema_id` names the payload
 * schema. `decoder` turns JSON back into one payload.
 */
export function local_input(id, schema_id, decoder) {
  return new Input(id, schema_id, decoder, InputClass$LocalInput$const);
}

/**
 * Declare an input port that runs a target-owned mutation.
 *
 * The component that owns the port performs the mutation on the client
 * that started the source event. Watershed then replicates the result. The
 * port receives a payload only from a local intent, the same as a local
 * input.
 *
 * `capabilities` names the channel mutations this input can perform, for
 * example `["sequence:insert"]`. A host reads this list to show the
 * shared-state effect of a connection before it stores the connection. No
 * function in this release rejects a connection because of capabilities.
 * These strings are not authorization. A mutable channel handle remains
 * mutable regardless of the capabilities listed here.
 */
export function collaborative_input(id, schema_id, decoder, capabilities) {
  return new Input(id, schema_id, decoder, new CollaborativeInput(capabilities));
}

/**
 * The kind of one direction, without the input class.
 */
export function direction_kind(direction) {
  if (direction instanceof OutputPort) {
    return DirectionKind$OutputDirection$const;
  } else {
    return DirectionKind$InputDirection$const;
  }
}

/**
 * Erase an output port's payload type to its `Descriptor`.
 */
export function output_descriptor(output) {
  return new Descriptor(output.id, Direction$OutputPort$const, output.schema_id);
}

/**
 * Erase an input port's payload type to its `Descriptor`.
 */
export function input_descriptor(input) {
  return new Descriptor(
    input.id,
    new InputPort(input.input_class),
    input.schema_id,
  );
}

/**
 * Encode one payload with an output port's codec.
 */
export function encode(output, payload) {
  return output.encode(payload);
}

/**
 * Decode one payload with an input port's codec.
 *
 * Returns `Error(InvalidPayload(reason))` when the JSON does not match the
 * port's decoder.
 */
export function decode(input, payload) {
  let $ = $json.parse($json.to_string(payload), input.decode);
  if ($ instanceof Ok) {
    return $;
  } else {
    let reason = $[0];
    return new Error(new InvalidPayload(reason));
  }
}

/**
 * Link an output port to an input port with the same payload type.
 *
 * Returns `Error(SchemaMismatch(..))` when the two ports name different
 * schema IDs, even though the compiler already checked the payload type.
 */
export function connect(output, input) {
  let $ = output.schema_id === input.schema_id;
  if ($) {
    return new Ok(new ConnectionTemplate(output.id, input.id, output.schema_id));
  } else {
    return new Error(new SchemaMismatch(output.schema_id, input.schema_id));
  }
}
