//// A generic catalog of component descriptors.
////
//// A descriptor holds one component kind's start function, port list, and
//// config decoder. The config type stays hidden inside the descriptor, so
//// one catalog can hold descriptors for many component kinds. Every
//// descriptor in a catalog shares the same context type and the same
//// running-instance type, because the shell that starts a component and
//// the shell that receives the result never vary between components.
////
//// This module does not depend on the runtime target. The graph and
//// dispatch tasks build on the `Catalog` type to run one shell over many
//// component kinds.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/port

/// An error from starting or validating one component.
pub type ComponentError {
  /// The config JSON did not match the descriptor's decoder.
  InvalidConfig(kind: String, version: Int, reason: json.DecodeError)
  /// The config JSON decoded, but the component's start function failed.
  StartFailed(kind: String, version: Int, reason: String)
  /// The descriptor does not have a matching typed input handler.
  InputUnavailable(kind: String, version: Int, input_id: String)
  /// The input payload did not match the handler's decoder.
  InvalidInputPayload(
    kind: String,
    version: Int,
    input_id: String,
    reason: port.PortError,
  )
  /// The typed input handler rejected the delivery.
  InputFailed(kind: String, version: Int, input_id: String, reason: String)
  /// The output is not declared by this descriptor.
  OutputUnavailable(kind: String, version: Int, output_id: String)
  /// The component could not release its local resources.
  StopFailed(kind: String, version: Int, reason: String)
}

/// An error from registering a descriptor in a catalog.
pub type RegistrationError {
  /// A descriptor with the same kind and version is already in the catalog.
  DuplicateRegistration(kind: String, version: Int)
}

/// An error from looking up a descriptor in a catalog.
pub type LookupError {
  /// The catalog holds no descriptor for this kind, at any version.
  NotRegistered(kind: String)
  /// The catalog holds this kind, but not the requested version.
  /// `available` lists the registered versions of the kind, from the lowest
  /// version to the highest version.
  UnsupportedVersion(kind: String, requested: Int, available: List(Int))
}

/// One encoded output event from a running component.
///
/// Build this value with `emit`. The constructor keeps the output's payload
/// type until after its codec runs.
pub opaque type OutputEvent {
  OutputEvent(id: String, schema_id: String, payload: Json)
}

/// A capability that publishes asynchronous component outputs.
///
/// The runtime binds this capability to one component instance and lifecycle
/// generation. The runtime validates and dispatches each published batch.
pub opaque type OutputEmitter {
  OutputEmitter(publish: fn(List(OutputEvent)) -> Nil)
}

/// One typed input handler after its payload type has been hidden.
///
/// Build this value with `input_handler`. The handler keeps the typed decoder
/// and function together after registration.
pub opaque type InputHandler(running) {
  InputHandler(
    descriptor: port.Descriptor,
    deliver: fn(running, Json) ->
      Result(#(running, List(OutputEvent)), InputHandlerError),
  )
}

type InputHandlerError {
  HandlerInvalidPayload(reason: port.PortError)
  HandlerFailed(reason: String)
}

/// One component kind's start function, port list, and config decoder.
///
/// The `config` type parameter stays hidden: two descriptors with
/// different config types can share one `Catalog(context, running)`, because
/// `config` never appears in this type's public signature.
pub opaque type Descriptor(context, running) {
  Descriptor(
    kind: String,
    version: Int,
    ports: List(port.Descriptor),
    validate_config: fn(Json) -> Result(Nil, ComponentError),
    start: fn(context, Json, fn(Result(running, ComponentError)) -> Nil) -> Nil,
    inputs: List(InputHandler(running)),
    stop: fn(running) -> Result(Nil, ComponentError),
  )
}

/// A set of registered descriptors, keyed by kind and version.
///
/// Every descriptor in one catalog shares the same `context` and `running`
/// types, but each descriptor can hide a different config type.
pub opaque type Catalog(context, running) {
  Catalog(entries: Dict(#(String, Int), Descriptor(context, running)))
}

/// Build a descriptor for one component kind.
///
/// `kind` and `version` name the component. `config_decoder` turns the
/// component's config JSON into the typed `config` value that
/// `start_component` needs. `start_component` builds the running instance
/// from a context value and the decoded config, or returns
/// `Error(reason)` with a plain-text reason. `ports` lists the component's
/// port metadata.
pub fn descriptor(
  kind kind: String,
  version version: Int,
  config_decoder config_decoder: Decoder(config),
  start start_component: fn(context, config) -> Result(running, String),
  ports ports: List(port.Descriptor),
) -> Descriptor(context, running) {
  executable_descriptor(
    kind: kind,
    version: version,
    config_decoder: config_decoder,
    start: fn(context, config, done) { done(start_component(context, config)) },
    inputs: [],
    stop: fn(_) { Ok(Nil) },
    ports: ports,
  )
}

/// Build an executable descriptor for one component kind.
///
/// `start_component` calls `done` after the component has bootstrapped its
/// channels and installed its required subscriptions. The runtime does not
/// mark the instance ready before that callback.
///
/// `inputs` must contain the handlers for the input descriptors in `ports`.
/// Delivery rejects a missing handler or metadata that does not match the
/// handler's typed port.
pub fn executable_descriptor(
  kind kind: String,
  version version: Int,
  config_decoder config_decoder: Decoder(config),
  start start_component: fn(context, config, fn(Result(running, String)) -> Nil) ->
    Nil,
  inputs inputs: List(InputHandler(running)),
  stop stop_component: fn(running) -> Result(Nil, String),
  ports ports: List(port.Descriptor),
) -> Descriptor(context, running) {
  let decode_config = fn(encoded: Json) {
    case json.parse(json.to_string(encoded), config_decoder) {
      Ok(config) -> Ok(config)
      Error(reason) -> Error(InvalidConfig(kind, version, reason))
    }
  }

  Descriptor(
    kind: kind,
    version: version,
    ports: ports,
    validate_config: fn(encoded) {
      decode_config(encoded)
      |> result.map(fn(_) { Nil })
    },
    start: fn(context, encoded, done) {
      case decode_config(encoded) {
        Error(reason) -> done(Error(reason))
        Ok(config) ->
          start_component(context, config, fn(started) {
            done(
              started
              |> result.map_error(fn(reason) {
                StartFailed(kind, version, reason)
              }),
            )
          })
      }
    },
    inputs: inputs,
    stop: fn(running) {
      stop_component(running)
      |> result.map_error(fn(reason) { StopFailed(kind, version, reason) })
    },
  )
}

/// Build a typed input handler for an executable descriptor.
pub fn input_handler(
  input input: port.Input(payload),
  handle handle: fn(running, payload) ->
    Result(#(running, List(OutputEvent)), String),
) -> InputHandler(running) {
  InputHandler(
    descriptor: port.input_descriptor(input),
    deliver: fn(running, encoded) {
      use payload <- result.try(
        port.decode(input, encoded)
        |> result.map_error(HandlerInvalidPayload),
      )
      handle(running, payload)
      |> result.map_error(HandlerFailed)
    },
  )
}

/// Encode one typed output event.
pub fn emit(output: port.Output(payload), payload: payload) -> OutputEvent {
  let port.Descriptor(id:, schema_id:, ..) = port.output_descriptor(output)
  OutputEvent(
    id: id,
    schema_id: schema_id,
    payload: port.encode(output, payload),
  )
}

/// Build an asynchronous output capability.
///
/// Runtime adapters use this function to bind the capability to an instance.
pub fn output_emitter(publish: fn(List(OutputEvent)) -> Nil) -> OutputEmitter {
  OutputEmitter(publish)
}

/// Publish one batch of asynchronous outputs.
pub fn publish(emitter: OutputEmitter, events: List(OutputEvent)) -> Nil {
  emitter.publish(events)
}

/// The port ID of an encoded output event.
pub fn output_id(event: OutputEvent) -> String {
  event.id
}

/// The payload of an encoded output event.
pub fn output_payload(event: OutputEvent) -> Json {
  event.payload
}

/// The component kind a descriptor names.
pub fn kind(descriptor: Descriptor(context, running)) -> String {
  descriptor.kind
}

/// The version a descriptor names.
pub fn version(descriptor: Descriptor(context, running)) -> Int {
  descriptor.version
}

/// The port metadata a descriptor lists.
pub fn ports(
  descriptor: Descriptor(context, running),
) -> List(port.Descriptor) {
  descriptor.ports
}

/// Check config JSON against a descriptor's decoder, without starting the
/// component.
pub fn validate_config(
  descriptor: Descriptor(context, running),
  config: Json,
) -> Result(Nil, ComponentError) {
  descriptor.validate_config(config)
}

/// Decode config JSON and start one running instance of a descriptor's
/// component.
///
/// Returns `Error(InvalidConfig(..))` when the config JSON does not match
/// the descriptor's decoder, or `Error(StartFailed(..))` when the decoded
/// config is valid but the component's start function fails.
pub fn start(
  descriptor: Descriptor(context, running),
  context: context,
  config: Json,
  done: fn(Result(running, ComponentError)) -> Nil,
) -> Nil {
  descriptor.start(context, config, done)
}

/// Deliver an encoded payload to one typed input handler.
pub fn deliver(
  descriptor: Descriptor(context, running),
  running: running,
  input_id: String,
  payload: Json,
) -> Result(#(running, List(OutputEvent)), ComponentError) {
  case matching_input(descriptor, input_id) {
    None ->
      Error(InputUnavailable(descriptor.kind, descriptor.version, input_id))
    Some(handler) ->
      handler.deliver(running, payload)
      |> result.map_error(fn(reason) {
        case reason {
          HandlerInvalidPayload(reason) ->
            InvalidInputPayload(
              descriptor.kind,
              descriptor.version,
              input_id,
              reason,
            )
          HandlerFailed(reason) ->
            InputFailed(descriptor.kind, descriptor.version, input_id, reason)
        }
      })
  }
}

/// Check that an output event belongs to this descriptor.
pub fn validate_output(
  descriptor: Descriptor(context, running),
  event: OutputEvent,
) -> Result(Nil, ComponentError) {
  let declared =
    list.any(descriptor.ports, fn(candidate) {
      candidate
      == port.Descriptor(
        id: event.id,
        direction: port.OutputPort,
        schema_id: event.schema_id,
      )
    })
  case declared {
    True -> Ok(Nil)
    False ->
      Error(OutputUnavailable(descriptor.kind, descriptor.version, event.id))
  }
}

/// Release one running component's local resources.
pub fn stop(
  descriptor: Descriptor(context, running),
  running: running,
) -> Result(Nil, ComponentError) {
  descriptor.stop(running)
}

/// An empty catalog.
pub fn new_catalog() -> Catalog(context, running) {
  Catalog(entries: dict.new())
}

/// Add a descriptor to a catalog.
///
/// Returns `Error(DuplicateRegistration(..))` when the catalog already
/// holds a descriptor with the same kind and version.
pub fn register(
  catalog: Catalog(context, running),
  descriptor: Descriptor(context, running),
) -> Result(Catalog(context, running), RegistrationError) {
  let key = #(descriptor.kind, descriptor.version)
  case dict.has_key(catalog.entries, key) {
    True -> Error(DuplicateRegistration(descriptor.kind, descriptor.version))
    False -> Ok(Catalog(entries: dict.insert(catalog.entries, key, descriptor)))
  }
}

/// Find a descriptor in a catalog by kind and version.
///
/// Returns `Error(NotRegistered(kind))` when the catalog holds no version of
/// the kind. Returns `Error(UnsupportedVersion(..))` when the catalog holds
/// the kind at other versions. The two errors let a caller show the correct
/// cause to a user: this host does not know the kind, or this host does not
/// register the requested version.
pub fn find(
  catalog: Catalog(context, running),
  kind: String,
  version: Int,
) -> Result(Descriptor(context, running), LookupError) {
  case dict.get(catalog.entries, #(kind, version)) {
    Ok(descriptor) -> Ok(descriptor)
    Error(Nil) ->
      case registered_versions(catalog, kind) {
        [] -> Error(NotRegistered(kind))
        available -> Error(UnsupportedVersion(kind, version, available))
      }
  }
}

/// The versions a catalog holds for one kind, from the lowest version to the
/// highest version. The sort keeps the list the same on every target.
fn registered_versions(
  catalog: Catalog(context, running),
  kind: String,
) -> List(Int) {
  dict.keys(catalog.entries)
  |> list.filter_map(fn(key) {
    case key.0 == kind {
      True -> Ok(key.1)
      False -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

fn matching_input(
  descriptor: Descriptor(context, running),
  input_id: String,
) -> Option(InputHandler(running)) {
  list.find(descriptor.inputs, fn(handler) {
    let port.Descriptor(id:, ..) = handler.descriptor
    id == input_id && list.contains(descriptor.ports, handler.descriptor)
  })
  |> result.map(Some)
  |> result.unwrap(None)
}
