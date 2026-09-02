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
    markers: List(String),
  )
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
              #(
                "origin",
                json.object([
                  #("kind", json.string("source")),
                  #("markers", json.array(entry.markers, json.string)),
                ]),
              ),
            ]),
          )
        }),
      ),
    ),
  ])
  |> json.to_string
}
