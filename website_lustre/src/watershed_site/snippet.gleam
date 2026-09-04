import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import simplifile
import watershed_site/error.{type BuildError}

pub type Manifest {
  Manifest(version: Int, snippets: Dict(String, Snippet))
}

pub type Snippet {
  Snippet(code: String, language: String, source_path: String, origin: Origin)
}

pub type Origin {
  Source(markers: List(String))
  File
}

pub fn load(path: String) -> Result(Manifest, BuildError) {
  use source <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(reason) {
      error.CannotRead(path, string.inspect(reason))
    }),
  )
  decode(source, path)
}

pub fn decode(source: String, path: String) -> Result(Manifest, BuildError) {
  let version_decoder = {
    use version <- decode.field("version", decode.int)
    decode.success(version)
  }
  use version <- result.try(
    json.parse(source, version_decoder)
    |> result.map_error(fn(reason) {
      error.InvalidSnippetManifest(path, string.inspect(reason))
    }),
  )
  use _ <- result.try(case version {
    1 -> Ok(Nil)
    _ ->
      Error(error.InvalidSnippetManifest(
        path,
        "Unsupported version: " <> int.to_string(version),
      ))
  })
  let manifest_decoder = {
    use snippets <- decode.field(
      "snippets",
      decode.dict(decode.string, entry_decoder()),
    )
    decode.success(Manifest(version, snippets))
  }
  json.parse(source, manifest_decoder)
  |> result.map_error(fn(reason) {
    error.InvalidSnippetManifest(path, string.inspect(reason))
  })
}

fn entry_decoder() -> decode.Decoder(Snippet) {
  use code <- decode.field("code", decode.string)
  use language <- decode.field("language", decode.string)
  use source_path <- decode.field("sourcePath", decode.string)
  use origin <- decode.field("origin", origin_decoder())
  decode.success(Snippet(code, language, source_path, origin))
}

fn origin_decoder() -> decode.Decoder(Origin) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "source" -> {
      use markers <- decode.field("markers", decode.list(decode.string))
      decode.success(Source(markers))
    }
    "file" -> decode.success(File)
    _ -> decode.failure(File, "source or file")
  }
}

pub fn get(
  manifest: Manifest,
  path: String,
  id: String,
) -> Result(Snippet, BuildError) {
  dict.get(manifest.snippets, id)
  |> result.replace_error(error.MissingSnippet(path, id))
}

pub fn source_url(snippet: Snippet, revision: String) -> String {
  "https://github.com/tylerbutler/watershed/blob/"
  <> revision
  <> "/"
  <> snippet.source_path
}
