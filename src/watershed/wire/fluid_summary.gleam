//// Lossless Fluid summary trees, blobs, and prior-summary references.
////
//// A summary handle is a logical path in the supplied previous summary. It is
//// not a Git object ID. Resolution returns a tree with no handles.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import gleam/uri

import watershed/canonical_json

pub type HandleKind {
  TreeHandle
  BlobHandle
}

pub type SummaryEntry {
  SummaryTree(entries: List(#(String, SummaryEntry)))
  SummaryBlob(bytes: BitArray)
  SummaryHandle(path: String, kind: HandleKind)
}

pub type SummaryError {
  MissingEntry(path: String)
  CyclicReference(path: String)
  WrongKind(path: String, expected: HandleKind)
  MalformedEntry(path: String, detail: String)
  UnsupportedEntry(path: String, detail: String)
}

type SnapshotNode {
  SnapshotNode(
    id: String,
    blobs: Dict(String, String),
    trees: Dict(String, SnapshotNode),
    commits: Dict(String, Dynamic),
  )
}

pub fn resolve(
  entry: SummaryEntry,
  previous: Option(SummaryEntry),
) -> Result(SummaryEntry, SummaryError) {
  resolve_entry(entry, previous, [], "/")
}

fn resolve_entry(
  entry: SummaryEntry,
  previous: Option(SummaryEntry),
  active: List(String),
  path: String,
) -> Result(SummaryEntry, SummaryError) {
  case entry {
    SummaryBlob(_) -> Ok(entry)
    SummaryTree(entries) -> {
      use Nil <- result.try(validate_names(entries, path))
      entries
      |> list.try_map(fn(item) {
        use value <- result.try(resolve_entry(
          item.1,
          previous,
          active,
          child_path(path, item.0),
        ))
        Ok(#(item.0, value))
      })
      |> result.map(SummaryTree)
    }
    SummaryHandle(handle_path, expected) -> {
      use previous <- result.try(case previous {
        Some(previous) -> Ok(previous)
        _ -> Error(MissingEntry(handle_path))
      })
      use components <- result.try(decode_path(handle_path))
      let reference = canonical_path(components)
      case list.contains(active, reference) {
        True -> Error(CyclicReference(reference))
        False -> {
          use target <- result.try(find_entry(
            previous,
            components,
            handle_path,
            "/",
          ))
          case entry_kind(target) == expected {
            False -> Error(WrongKind(handle_path, expected))
            True ->
              resolve_entry(
                target,
                Some(previous),
                [reference, ..active],
                reference,
              )
          }
        }
      }
    }
  }
}

fn entry_kind(entry: SummaryEntry) -> HandleKind {
  case entry {
    SummaryTree(_) -> TreeHandle
    SummaryBlob(_) -> BlobHandle
    SummaryHandle(_, kind) -> kind
  }
}

fn find_entry(
  entry: SummaryEntry,
  components: List(String),
  original_path: String,
  current_path: String,
) -> Result(SummaryEntry, SummaryError) {
  case components {
    [] -> Ok(entry)
    [name, ..rest] ->
      case entry {
        SummaryTree(entries) -> {
          use Nil <- result.try(validate_names(entries, current_path))
          use child <- result.try(
            entries
            |> list.find(fn(item) { item.0 == name })
            |> result.replace_error(MissingEntry(original_path)),
          )
          find_entry(
            child.1,
            rest,
            original_path,
            child_path(current_path, name),
          )
        }
        SummaryBlob(_) | SummaryHandle(_, _) ->
          Error(WrongKind(original_path, TreeHandle))
      }
  }
}

fn validate_names(
  entries: List(#(String, SummaryEntry)),
  path: String,
) -> Result(Nil, SummaryError) {
  use _ <- result.try(
    list.try_fold(entries, dict.new(), fn(seen, entry) {
      case dict.has_key(seen, entry.0) {
        True -> Error(MalformedEntry(path, "duplicate entry: " <> entry.0))
        False -> Ok(dict.insert(seen, entry.0, Nil))
      }
    }),
  )
  Ok(Nil)
}

fn decode_path(path: String) -> Result(List(String), SummaryError) {
  let parts = case string.split(path, "/") {
    ["", ..rest] -> rest
    parts -> parts
  }
  parts
  |> list.try_map(fn(part) {
    uri.percent_decode(part)
    |> result.replace_error(MalformedEntry(path, "invalid percent encoding"))
  })
}

fn canonical_path(components: List(String)) -> String {
  case components {
    [] -> ""
    _ -> "/" <> string.join(list.map(components, encode_component), "/")
  }
}

fn child_path(parent: String, name: String) -> String {
  let encoded = encode_component(name)
  case parent {
    "/" | "" -> "/" <> encoded
    _ -> parent <> "/" <> encoded
  }
}

/// Encode one summary or Git tree path component like `encodeURIComponent`.
pub fn encode_component(value: String) -> String {
  value
  |> uri.percent_encode
  |> string.replace("+", "%2B")
  |> string.replace("$", "%24")
}

pub fn from_snapshot(
  tree: Json,
  blobs: Dict(String, BitArray),
) -> Result(SummaryEntry, SummaryError) {
  use snapshot <- result.try(
    json.parse(json.to_string(tree), snapshot_decoder())
    |> result.map_error(fn(error) { MalformedEntry("/", string.inspect(error)) }),
  )
  materialize_snapshot(snapshot, blobs, "/")
}

fn materialize_snapshot(
  snapshot: SnapshotNode,
  blobs: Dict(String, BitArray),
  path: String,
) -> Result(SummaryEntry, SummaryError) {
  let commits = sorted_entries(snapshot.commits)
  case commits {
    [commit, ..] ->
      Error(UnsupportedEntry(
        child_path(path, commit.0),
        "snapshot commits are not supported",
      ))
    [] -> {
      use Nil <- result.try(validate_snapshot_names(snapshot, path))
      let blob_entries =
        snapshot.blobs
        |> sorted_entries
        |> list.map(fn(entry) { #(entry.0, Ok(entry.1)) })
      let tree_entries =
        snapshot.trees
        |> sorted_entries
        |> list.map(fn(entry) { #(entry.0, Error(entry.1)) })
      use entries <- result.try(
        list.append(blob_entries, tree_entries)
        |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
        |> list.try_map(fn(entry) {
          let entry_path = child_path(path, entry.0)
          case entry.1 {
            Ok(blob_id) ->
              blobs
              |> dict.get(blob_id)
              |> result.replace_error(MissingEntry(
                entry_path <> " (snapshot blob " <> blob_id <> ")",
              ))
              |> result.map(fn(bytes) { #(entry.0, SummaryBlob(bytes)) })
            Error(tree) -> {
              use value <- result.try(materialize_snapshot(
                tree,
                blobs,
                entry_path,
              ))
              Ok(#(entry.0, value))
            }
          }
        }),
      )
      Ok(SummaryTree(entries))
    }
  }
}

fn validate_snapshot_names(
  snapshot: SnapshotNode,
  path: String,
) -> Result(Nil, SummaryError) {
  use _ <- result.try(
    list.try_fold(dict.to_list(snapshot.trees), snapshot.blobs, fn(seen, entry) {
      case dict.has_key(seen, entry.0) {
        True -> Error(MalformedEntry(path, "duplicate entry: " <> entry.0))
        False -> Ok(dict.insert(seen, entry.0, ""))
      }
    }),
  )
  Ok(Nil)
}

fn sorted_entries(values: Dict(String, value)) -> List(#(String, value)) {
  values
  |> dict.to_list
  |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
}

fn snapshot_decoder() -> decode.Decoder(SnapshotNode) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  let allowed = ["blobs", "commits", "id", "trees"]
  case
    fields
    |> dict.to_list
    |> list.all(fn(entry) { list.contains(allowed, entry.0) })
  {
    False ->
      decode.failure(
        SnapshotNode("", dict.new(), dict.new(), dict.new()),
        "snapshot fields",
      )
    True -> {
      use id <- decode.field("id", decode.string)
      use blobs <- decode.field(
        "blobs",
        decode.dict(decode.string, decode.string),
      )
      use trees <- decode.field(
        "trees",
        decode.dict(decode.string, decode.recursive(snapshot_decoder)),
      )
      use commits <- decode.optional_field(
        "commits",
        dict.new(),
        decode.dict(decode.string, decode.dynamic),
      )
      decode.success(SnapshotNode(id:, blobs:, trees:, commits:))
    }
  }
}
