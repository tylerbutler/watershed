//// Typed data ports for a component.
////
//// A port is a named point of data flow. An output port sends a payload
//// out of a component. An input port receives a payload into a component.
//// Each port carries a schema ID and a payload codec, so a connection
//// between two ports can check the types at compile time and check the
//// schema ID at connection time.
////
//// This module does not depend on the runtime target. The catalog and
//// graph tasks build on these types to route payloads between components.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

/// What an input port can change.
///
/// A local input changes only this client's presentation state or
/// controller state. A collaborative input runs a target-owned mutation on
/// the client that started the source event. Watershed then replicates the
/// result. Both classes receive a payload only from a local intent. No other
/// client sends a payload to an input port.
pub type InputClass {
  LocalInput
  CollaborativeInput(capabilities: List(String))
}

/// The direction of data flow through a port.
///
/// An input port always carries its input class. A port therefore cannot be
/// an input port without a class.
pub type Direction {
  OutputPort
  InputPort(class: InputClass)
}

/// The direction a check requires. This type holds no input class, because
/// a check cannot know the class of the input port it expects.
pub type DirectionKind {
  OutputDirection
  InputDirection
}

/// The erased metadata of one port. Use this type to list, log, or render
/// ports without the payload type.
pub type Descriptor {
  Descriptor(id: String, direction: Direction, schema_id: String)
}

/// An output port. The payload type parameter keeps `connect` from linking
/// two ports with mismatched payload types.
pub opaque type Output(payload) {
  Output(id: String, schema_id: String, encode: fn(payload) -> Json)
}

/// An input port. The payload type parameter keeps `connect` from linking
/// two ports with mismatched payload types.
pub opaque type Input(payload) {
  Input(
    id: String,
    schema_id: String,
    decode: Decoder(payload),
    input_class: InputClass,
  )
}

/// A checked link between one output port and one input port. Build this
/// value with `connect`. Do not build one by hand.
pub type ConnectionTemplate {
  ConnectionTemplate(
    source_port: String,
    target_port: String,
    schema_id: String,
  )
}

/// An error from a port operation.
pub type PortError {
  /// The payload did not match the input port's decoder.
  InvalidPayload(reason: json.DecodeError)
  /// The output port and the input port carry different schema IDs.
  SchemaMismatch(source: String, target: String)
}

/// Declare an output port.
///
/// `id` names the port inside its component. `schema_id` names the payload
/// schema, and it must match the schema ID of any input port this output
/// connects to. `encode` turns one payload into JSON.
pub fn output(
  id: String,
  schema_id: String,
  encode: fn(payload) -> Json,
) -> Output(payload) {
  Output(id: id, schema_id: schema_id, encode: encode)
}

/// Declare an input port that changes local state only.
///
/// A local input changes this client's presentation state or controller
/// state, for example a selection or a filter. It does not change a
/// collaborative channel. It receives a payload only from a local intent.
///
/// `id` names the port inside its component. `schema_id` names the payload
/// schema. `decoder` turns JSON back into one payload.
pub fn local_input(
  id: String,
  schema_id: String,
  decoder: Decoder(payload),
) -> Input(payload) {
  Input(id: id, schema_id: schema_id, decode: decoder, input_class: LocalInput)
}

/// Declare an input port that runs a target-owned mutation.
///
/// The component that owns the port performs the mutation on the client
/// that started the source event. Watershed then replicates the result. The
/// port receives a payload only from a local intent, the same as a local
/// input.
///
/// `capabilities` names the channel mutations this input can perform, for
/// example `["sequence:insert"]`. A host reads this list to show the
/// shared-state effect of a connection before it stores the connection. No
/// function in this release rejects a connection because of capabilities.
pub fn collaborative_input(
  id: String,
  schema_id: String,
  decoder: Decoder(payload),
  capabilities: List(String),
) -> Input(payload) {
  Input(
    id: id,
    schema_id: schema_id,
    decode: decoder,
    input_class: CollaborativeInput(capabilities: capabilities),
  )
}

/// The kind of one direction, without the input class.
pub fn direction_kind(direction: Direction) -> DirectionKind {
  case direction {
    OutputPort -> OutputDirection
    InputPort(_) -> InputDirection
  }
}

/// Erase an output port's payload type to its `Descriptor`.
pub fn output_descriptor(output: Output(payload)) -> Descriptor {
  Descriptor(id: output.id, direction: OutputPort, schema_id: output.schema_id)
}

/// Erase an input port's payload type to its `Descriptor`.
pub fn input_descriptor(input: Input(payload)) -> Descriptor {
  Descriptor(
    id: input.id,
    direction: InputPort(input.input_class),
    schema_id: input.schema_id,
  )
}

/// Encode one payload with an output port's codec.
pub fn encode(output: Output(payload), payload: payload) -> Json {
  output.encode(payload)
}

/// Decode one payload with an input port's codec.
///
/// Returns `Error(InvalidPayload(reason))` when the JSON does not match the
/// port's decoder.
pub fn decode(
  input: Input(payload),
  payload: Json,
) -> Result(payload, PortError) {
  case json.parse(json.to_string(payload), input.decode) {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(InvalidPayload(reason))
  }
}

// docs:snippet-start foundations-ports-connect
/// Link an output port to an input port with the same payload type.
///
/// Returns `Error(SchemaMismatch(..))` when the two ports name different
/// schema IDs, even though the compiler already checked the payload type.
pub fn connect(
  output: Output(payload),
  input: Input(payload),
) -> Result(ConnectionTemplate, PortError) {
  case output.schema_id == input.schema_id {
    True ->
      Ok(ConnectionTemplate(
        source_port: output.id,
        target_port: input.id,
        schema_id: output.schema_id,
      ))
    False ->
      Error(SchemaMismatch(source: output.schema_id, target: input.schema_id))
  }
}
// docs:snippet-end foundations-ports-connect
