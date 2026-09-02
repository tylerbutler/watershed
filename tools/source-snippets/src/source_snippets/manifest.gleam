//// JSON manifest encoding for generated source snippets.
////
//// Encodes a version-1 manifest with deterministic key ordering.

import gleam/json
import gleam/list
import gleam/string

/// The complete generated manifest.
pub type Manifest {
  Manifest(version: Int, snippets: List(ManifestEntry))
}

/// A single snippet entry in the manifest.
pub type ManifestEntry {
  ManifestEntry(
    id: String,
    code: String,
    language: String,
    source_path: String,
    origin: Origin,
  )
}

/// Where the code of an entry comes from.
///
/// The manifest must describe a file listing as a file listing. A reader of
/// the manifest can then tell a composed range from a complete module.
pub type Origin {
  /// The named marker ranges, in composition order.
  MarkerOrigin(markers: List(String))
  /// The complete source file, without its marker directive lines.
  FileOrigin
}

/// Encodes a manifest to a deterministic JSON string.
///
/// Entries are sorted by id for stable output.
pub fn encode(manifest: Manifest) -> String {
  let sorted =
    manifest.snippets
    |> list.sort(fn(a, b) { string.compare(a.id, b.id) })

  json.object([
    #("version", json.int(manifest.version)),
    #(
      "snippets",
      json.object(
        list.map(sorted, fn(entry) {
          #(
            entry.id,
            json.object([
              #("code", json.string(entry.code)),
              #("language", json.string(entry.language)),
              #("sourcePath", json.string(entry.source_path)),
              #("origin", encode_origin(entry.origin)),
            ]),
          )
        }),
      ),
    ),
  ])
  |> json.to_string
}

fn encode_origin(origin: Origin) -> json.Json {
  case origin {
    MarkerOrigin(markers) ->
      json.object([
        #("kind", json.string("source")),
        #("markers", json.array(markers, json.string)),
      ])
    FileOrigin -> json.object([#("kind", json.string("file"))])
  }
}
