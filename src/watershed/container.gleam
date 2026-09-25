//// Native creation of the fixed SharedTree container profile.

import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import watershed/fluid_ids
import watershed/git_storage
import watershed/id
import watershed/tree/schema
import watershed/tree/types
import watershed/wire/fluid_document
import watershed/wire/fluid_summary

pub type CreateConfig {
  /// Use an HTTP service URL without user information, query, or fragment.
  /// Supply a tenant-write token. Do not supply a tenant secret.
  CreateConfig(base_url: String, tenant: String, token: String)
}

pub type CreateError {
  InvalidConfiguration(detail: String)
  InvalidInitialTree(types.TreeError)
  InvalidIdentity(fluid_ids.IdError)
  InvalidSummary(fluid_summary.SummaryError)
  StorageFailed(git_storage.StorageError)
}

@target(erlang)
/// Create a persisted container and return its assigned ID. Connect separately.
/// A lost response can leave an unknown created document. Do not retry this
/// operation automatically. This function starts no document runtime or
/// WebSocket connection.
pub fn create_tree(
  config: CreateConfig,
  stored: schema.StoredSchema,
  initial_root: Option(types.TreeValue),
) -> Result(String, CreateError) {
  use summary <- result.try(prepare(config, stored, initial_root))
  git_storage.create_document(
    base_url: config.base_url,
    tenant: config.tenant,
    token: config.token,
    summary: summary,
  )
  |> result.map_error(StorageFailed)
}

@target(javascript)
/// Create a persisted container and return its assigned ID. Connect separately.
/// A lost response can leave an unknown created document. Do not retry this
/// operation automatically. This function starts no document runtime or
/// WebSocket connection.
pub fn create_tree(
  config: CreateConfig,
  stored: schema.StoredSchema,
  initial_root: Option(types.TreeValue),
) -> Promise(Result(String, CreateError)) {
  case prepare(config, stored, initial_root) {
    Error(error) -> promise.resolve(Error(error))
    Ok(summary) ->
      git_storage.create_document(
        base_url: config.base_url,
        tenant: config.tenant,
        token: config.token,
        summary: summary,
      )
      |> promise.map(result.map_error(_, StorageFailed))
  }
}

fn prepare(
  config: CreateConfig,
  stored: schema.StoredSchema,
  initial_root: Option(types.TreeValue),
) -> Result(fluid_document.DocumentSummary, CreateError) {
  use url <- result.try(
    uri.parse(config.base_url)
    |> result.replace_error(InvalidConfiguration("invalid service URL")),
  )
  use _ <- result.try(case url {
    uri.Uri(
      scheme: Some(scheme),
      host: Some(host),
      userinfo: None,
      query: None,
      fragment: None,
      ..,
    )
      if host != "" && scheme == "http" || host != "" && scheme == "https"
    -> Ok(Nil)
    _ ->
      Error(InvalidConfiguration(
        "use an HTTP service URL without credentials, query, or fragment",
      ))
  })
  use _ <- result.try(case url.port {
    None -> Ok(Nil)
    Some(port) if port > 0 && port <= 65_535 -> Ok(Nil)
    _ -> Error(InvalidConfiguration("service port must be between 1 and 65535"))
  })
  use _ <- result.try(case valid_service_url(config.base_url) {
    True -> Ok(Nil)
    False -> Error(InvalidConfiguration("invalid service URL"))
  })
  use _ <- result.try(
    case
      string.trim(config.tenant) == ""
      || config.tenant == "."
      || config.tenant == ".."
      || config.token == ""
      || list.any(string.to_utf_codepoints(config.token), fn(codepoint) {
        let value = string.utf_codepoint_to_int(codepoint)
        value <= 32 || value >= 127
      })
    {
      True ->
        Error(InvalidConfiguration(
          "use a nonempty tenant path component and a visible ASCII token",
        ))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(
    schema.validate_root_field(stored, initial_root)
    |> result.map_error(InvalidInitialTree),
  )
  use session <- result.try(
    fluid_ids.session_id(id.uuid_v4()) |> result.map_error(InvalidIdentity),
  )
  use view <- result.try(
    fluid_ids.stable_id(id.uuid_v4()) |> result.map_error(InvalidIdentity),
  )
  fluid_document.initial_tree(stored, initial_root, session, view)
  |> result.map_error(InvalidSummary)
}

@external(erlang, "watershed_container_ffi", "valid_service_url")
@external(javascript, "./git_storage_ffi.mjs", "valid_service_url")
fn valid_service_url(url: String) -> Bool

/// Describe a failure without exposing tokens or response bodies.
pub fn error_to_string(error: CreateError) -> String {
  case error {
    InvalidConfiguration(detail) -> "invalid creation configuration: " <> detail
    InvalidInitialTree(error) ->
      "invalid initial tree: " <> string.inspect(error)
    InvalidIdentity(_) -> "could not generate a container identity"
    InvalidSummary(error) ->
      "invalid initial summary: " <> string.inspect(error)
    StorageFailed(error) ->
      case error {
        git_storage.UnexpectedStatus(_, status, _) ->
          "container creation answered HTTP "
          <> int.to_string(status)
          <> case status < 400 || status >= 500 {
            True -> "; creation may have succeeded; do not retry automatically"
            False -> ""
          }
        git_storage.RequestFailed(_, _)
        | git_storage.BodyReadFailed(_, _)
        | git_storage.ResponseDecodeFailed(_, _) ->
          "container creation response failed; creation may have succeeded; do not retry automatically"
        git_storage.BadRequestUrl(_) -> "invalid container creation URL"
        git_storage.SummaryStructure(_) -> "invalid container creation summary"
        git_storage.InvalidVersionCount(_)
        | git_storage.HierarchyBlobUnreadable(_, _, _)
        | git_storage.HierarchyObjectMissing(_, _, _) ->
          "container creation storage operation failed"
      }
  }
}
