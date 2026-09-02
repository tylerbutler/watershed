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
import gleam/json.{type Json}
import gleam/result
import watershed/port

/// An error from starting or validating one component.
pub type ComponentError {
  /// The config JSON did not match the descriptor's decoder.
  InvalidConfig(kind: String, version: Int, reason: json.DecodeError)
  /// The config JSON decoded, but the component's start function failed.
  StartFailed(kind: String, version: Int, reason: String)
}

/// An error from registering a descriptor in a catalog.
pub type RegistrationError {
  /// A descriptor with the same kind and version is already in the catalog.
  DuplicateRegistration(kind: String, version: Int)
}

/// An error from looking up a descriptor in a catalog.
pub type LookupError {
  /// No descriptor with this kind and version is in the catalog.
  NotRegistered(kind: String, version: Int)
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
    start: fn(context, Json) -> Result(running, ComponentError),
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
    start: fn(context, encoded) {
      use config <- result.try(decode_config(encoded))
      start_component(context, config)
      |> result.map_error(fn(reason) { StartFailed(kind, version, reason) })
    },
  )
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
) -> Result(running, ComponentError) {
  descriptor.start(context, config)
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
/// Returns `Error(NotRegistered(..))` when no descriptor matches.
pub fn find(
  catalog: Catalog(context, running),
  kind: String,
  version: Int,
) -> Result(Descriptor(context, running), LookupError) {
  dict.get(catalog.entries, #(kind, version))
  |> result.replace_error(NotRegistered(kind, version))
}
