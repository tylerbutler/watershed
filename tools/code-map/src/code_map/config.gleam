//// Repository-relative path rules.

import code_map/model
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string

pub fn relative_path(path: String) -> Bool {
  let drive = case string.to_utf_codepoints(path) {
    [letter, colon, ..] -> {
      let letter = string.utf_codepoint_to_int(letter)
      string.utf_codepoint_to_int(colon) == 58
      && {
        { letter >= 65 && letter <= 90 } || { letter >= 97 && letter <= 122 }
      }
    }
    _ -> False
  }
  path != ""
  && !drive
  && !string.contains(path, "\\")
  && !string.contains(path, "\u{0}")
  && list.all(string.split(path, "/"), fn(part) {
    part != "" && part != "." && part != ".."
  })
}

pub fn beneath(path: String, prefix: String) -> Bool {
  path == prefix || string.starts_with(path, prefix <> "/")
}

pub fn validate(value: model.Config) -> Result(model.Config, model.Error) {
  let unique = fn(values) {
    set.size(set.from_list(values)) == list.length(values)
  }
  case
    unique(value.exclude_dirs)
    && unique(value.exclude_paths)
    && list.all(value.exclude_dirs, fn(p) {
      relative_path(p) && !string.contains(p, "/")
    })
    && list.all(value.exclude_paths, relative_path)
  {
    True ->
      Ok(model.Config(
        list.sort(value.exclude_dirs, string.compare),
        list.sort(value.exclude_paths, string.compare),
      ))
    False ->
      Error(model.ConfigError(
        "exclusions must contain unique relative paths or directory names",
      ))
  }
}

pub const extensions = [
  ".gleam",
  ".js",
  ".mjs",
  ".cjs",
  ".jsx",
  ".ts",
  ".mts",
  ".cts",
  ".tsx",
  ".astro",
]

pub fn language(extension: String) -> Option(model.Language) {
  case string.lowercase(extension) {
    ".gleam" -> Some(model.Gleam)
    ".astro" -> Some(model.Astro)
    ".ts" | ".mts" | ".cts" | ".tsx" -> Some(model.TypeScript)
    ".js" | ".mjs" | ".cjs" | ".jsx" -> Some(model.JavaScript)
    _ -> None
  }
}

pub fn inventory_paths(
  paths: List(String),
) -> Result(List(String), model.Error) {
  let paths =
    paths
    |> list.filter(fn(p) { p != "" && !beneath(p, ".code-map") })
    |> set.from_list
    |> set.to_list
    |> list.sort(string.compare)
  case list.all(paths, relative_path) {
    True -> Ok(paths)
    False -> Error(model.RefreshError("Git returned an unsupported path"))
  }
}

pub type FileKind {
  Regular
  Symlink
  Other
}

pub type Classification {
  ReadSource(model.Language)
  Exclude(Option(model.Language), String)
  UnsupportedFormat(String)
}

pub fn classify(
  config: model.Config,
  path: String,
  extension: String,
  kind: FileKind,
) -> Classification {
  let language = language(extension)
  let components = string.split(path, "/")
  let directory = list.take(components, list.length(components) - 1)
  let exclusion =
    list.find(config.exclude_paths, fn(prefix) { beneath(path, prefix) })
    |> result.or(
      list.find(directory, fn(part) { list.contains(config.exclude_dirs, part) }),
    )
  case exclusion, kind, language {
    Ok(reason), _, _ -> Exclude(language, "Config exclusion: " <> reason)
    Error(_), Symlink, _ -> Exclude(language, "Symlink (not followed)")
    Error(_), Other, _ -> Exclude(language, "Not a regular file")
    Error(_), Regular, Some(language) -> ReadSource(language)
    Error(_), Regular, None ->
      UnsupportedFormat(
        "No parser for "
        <> case extension {
          "" -> "extensionless files"
          extension -> string.lowercase(extension)
        },
      )
  }
}
