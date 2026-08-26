//// Pure helpers for the workspace tree and the JSON editor: path joining,
//// breadcrumbs, deterministic row ordering, and the two render rules that
//// need no live channel to check — a directory value that is not a `JsonOt`
//// handle, and a path that a folder delete has covered. Kept apart from
//// `json_workspace_lustre` so each rule has a test that starts and ends with
//// plain data, no `Document`, no `SharedDirectory`, no browser.

import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import watershed
import watershed/json_ot.{type JsonValue, type PathKey, Index, Key}

/// The path of the workspace root, and the path convention every
/// `directory_*` facade function takes: `"/"` at the root, `"/parent/child"`
/// below it.
pub const root_path = "/"

/// A tree name is not empty and does not contain a path separator.
pub fn valid_name(name: String) -> Bool {
  let name = string.trim(name)
  name != "" && !string.contains(name, "/")
}

/// Join a subdirectory or document `name` onto `path`.
pub fn join_path(path: String, name: String) -> String {
  case path {
    "/" -> "/" <> name
    _ -> path <> "/" <> name
  }
}

/// The path one level up from `path`. The root is its own parent, so a
/// caller can always navigate up without a special case for "already home".
pub fn parent_path(path: String) -> String {
  case name_segments(path) {
    [] -> root_path
    segments ->
      case list.reverse(segments) {
        [] -> root_path
        [_, ..rest] ->
          case list.reverse(rest) {
            [] -> root_path
            names -> "/" <> string.join(names, "/")
          }
      }
  }
}

fn name_segments(path: String) -> List(String) {
  string.split(path, "/") |> list.filter(fn(s) { s != "" })
}

/// Breadcrumbs from the root down to `path`, each paired with the path a
/// click on it should navigate to. The root always leads, labelled `"/"`.
pub fn breadcrumbs(path: String) -> List(#(String, String)) {
  let #(_, crumbs) =
    list.fold(
      name_segments(path),
      #(root_path, [#(root_path, root_path)]),
      fn(acc, name) {
        let #(prefix, crumbs) = acc
        let next = join_path(prefix, name)
        #(next, list.append(crumbs, [#(name, next)]))
      },
    )
  crumbs
}

/// One row of the tree listing at a path: a folder, or a document, with
/// whether its directory value failed to resolve to a `JsonOt` handle.
/// `entries` holding anything else is a corrupt write, not a crash — the
/// listing marks the row rather than guessing at its shape.
pub type Row {
  FolderRow(name: String, path: String)
  DocRow(name: String, path: String, corrupt: Bool)
}

/// Folders first, then documents, each block alphabetical — deterministic
/// regardless of the map's insertion order or of which peer wrote last.
pub fn rows(
  path: String,
  subdirectories: List(String),
  entries: List(#(String, Json)),
) -> List(Row) {
  let folders =
    subdirectories
    |> list.sort(string.compare)
    |> list.map(fn(name) { FolderRow(name, join_path(path, name)) })
  let docs =
    entries
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let #(name, value) = pair
      DocRow(name, join_path(path, name), corrupt: !watershed.is_handle(value))
    })
  list.append(folders, docs)
}

/// Whether `deleted_path` covers `target_path` — the same path, or an
/// ancestor of it. A folder delete removes reachability for everything
/// underneath it, so an open document's banner, and a browsing path bounced
/// back to the root, both have to fire from any ancestor, not only an exact
/// path match.
pub fn path_covers(deleted_path: String, target_path: String) -> Bool {
  case deleted_path {
    "/" -> True
    _ ->
      target_path == deleted_path
      || string.starts_with(target_path, deleted_path <> "/")
  }
}

/// Read the value at a JSON-OT path.
pub fn value_at(value: JsonValue, path: List(PathKey)) -> Option(JsonValue) {
  case path {
    [] -> Some(value)
    [Key(key), ..rest] ->
      case value {
        json_ot.VObject(members) ->
          case list.key_find(members, key) {
            Ok(value) -> value_at(value, rest)
            Error(_) -> None
          }
        _ -> None
      }
    [Index(index), ..rest] ->
      case value {
        json_ot.VArray(items) if index >= 0 ->
          case list.drop(items, index) {
            [value, ..] -> value_at(value, rest)
            [] -> None
          }
        _ -> None
      }
  }
}
