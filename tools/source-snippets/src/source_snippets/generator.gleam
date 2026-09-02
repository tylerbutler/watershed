//// Generates a validated snippet manifest from a configuration file.
////
//// Scans configured source roots for marker directives, validates the
//// complete marker inventory, extracts and composes ranges, and returns
//// a manifest ready for encoding.

import filepath
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile
import source_snippets/config.{type Config, type SnippetSpec}
import source_snippets/extractor
import source_snippets/manifest.{
  type Manifest, type ManifestEntry, ManifestEntry,
}

/// A generated snippet before manifest encoding.
pub type GeneratedSnippet {
  GeneratedSnippet(
    code: String,
    language: String,
    source_path: String,
    markers: List(String),
  )
}

/// Errors during manifest generation.
pub type GenerateError {
  /// The configuration file could not be read.
  ConfigReadError(path: String)
  /// The configuration JSON is invalid.
  ConfigDecodeError(error: config.ConfigError)
  /// A configured marker root directory does not exist.
  MissingRoot(root: String)
  /// A configured source file does not exist.
  MissingSourceFile(path: String)
  /// A marker id appears in more than one source file.
  DuplicateMarkerAcrossFiles(
    marker: String,
    first_path: String,
    second_path: String,
  )
  /// A configured marker was not found in the source file.
  MarkerNotFound(snippet_id: String, marker: String, source_path: String)
  /// A marker extraction error from the extractor.
  ExtractionError(snippet_id: String, error: extractor.MarkerError)
  /// A discovered marker directive is not referenced by any snippet.
  OrphanMarker(marker: String, source_path: String)
  /// An end directive names a marker whose pair is complete in another file.
  StrayEndMarker(marker: String, pair_path: String, stray_path: String)
  /// A configured source path could not be normalized or escapes source root.
  InvalidSourcePath(snippet_id: String, source_path: String)
}

/// Generates a manifest from a configuration file path.
///
/// Reads the configuration, resolves the source root relative to the
/// configuration file, scans marker roots, validates the complete
/// marker inventory, and composes output snippets.
pub fn generate(config_path: String) -> Result(Manifest, GenerateError) {
  let config_dir = dir_of(config_path)

  use config_text <- result_try(
    simplifile.read(config_path)
    |> result.map_error(fn(_) { ConfigReadError(config_path) }),
  )

  use cfg <- result_try(
    config.decode_config(config_text)
    |> result.map_error(ConfigDecodeError),
  )

  let source_root = resolve_path(config_dir, cfg.source_root)

  use normalized_snippets <- result_try(normalize_snippet_paths(cfg.snippets))

  let cfg = config.Config(..cfg, snippets: normalized_snippets)

  use _ <- result_try(validate_roots_exist(source_root, cfg.marker_roots))

  use inventory <- result_try(scan_inventory(
    source_root,
    cfg.marker_roots,
    cfg.extensions,
    cfg.exclude_dirs,
  ))

  use _ <- result_try(check_no_orphans(inventory, cfg.snippets))

  use entries <- result_try(compose_all(cfg, source_root, inventory))

  Ok(manifest.Manifest(version: 1, snippets: entries))
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

fn dir_of(path: String) -> String {
  case filepath.directory_name(path) {
    "" -> "."
    dir -> dir
  }
}

fn resolve_path(base: String, relative: String) -> String {
  case string.starts_with(relative, "/") {
    True -> relative
    False -> filepath.join(base, relative)
  }
}

// ---------------------------------------------------------------------------
// Path normalization
// ---------------------------------------------------------------------------

/// Normalizes source paths in snippet specs.
///
/// Resolves `.` and `..` segments via `filepath.expand`. Rejects paths
/// that escape the source root (leading `..` after expansion).
fn normalize_snippet_paths(
  specs: List(config.SnippetSpec),
) -> Result(List(config.SnippetSpec), GenerateError) {
  list.try_map(specs, fn(spec) {
    case filepath.expand(spec.source_path) {
      Error(Nil) -> Error(InvalidSourcePath(spec.id, spec.source_path))
      Ok(normalized) -> Ok(config.SnippetSpec(..spec, source_path: normalized))
    }
  })
}

// ---------------------------------------------------------------------------
// Root validation
// ---------------------------------------------------------------------------

fn validate_roots_exist(
  source_root: String,
  roots: List(String),
) -> Result(Nil, GenerateError) {
  list.try_each(roots, fn(root) {
    let full = filepath.join(source_root, root)
    case simplifile.is_directory(full) {
      Ok(True) -> Ok(Nil)
      _ -> Error(MissingRoot(root))
    }
  })
}

// ---------------------------------------------------------------------------
// Marker inventory scanning
// ---------------------------------------------------------------------------

/// Maps marker name -> (source_path relative to source_root, full file content).
type MarkerInventory =
  dict.Dict(String, #(String, String))

/// One scanned file: its path relative to the source root, its content, and
/// the marker names its start and end directives carry.
///
/// The two name lists answer the question the scan asks one file at a time:
/// does *this* file hold both halves of the pair?
type ScannedSource {
  ScannedSource(
    path: String,
    content: String,
    starts: List(String),
    ends: List(String),
  )
}

fn scan_inventory(
  source_root: String,
  marker_roots: List(String),
  extensions: List(String),
  exclude_dirs: List(String),
) -> Result(MarkerInventory, GenerateError) {
  let root_paths =
    list.map(marker_roots, fn(r) { filepath.join(source_root, r) })
  use files <- result_try(collect_source_files(
    root_paths,
    extensions,
    exclude_dirs,
  ))
  use sources <- result_try(read_sources(files, source_root, []))

  // A start directive claims the marker. An end directive claims the marker
  // only when no start directive claims it. A pair that is split across two
  // files therefore reports the missing end, not a duplicate.
  use with_starts <- result_try(add_start_markers(sources, dict.new()))
  add_end_markers(sources, with_starts, paired_markers(sources), with_starts)
}

fn collect_source_files(
  dirs: List(String),
  extensions: List(String),
  exclude_dirs: List(String),
) -> Result(List(String), GenerateError) {
  list.try_fold(dirs, [], fn(acc, dir) {
    use entries <- result_try(
      list_files_recursive(dir, exclude_dirs)
      |> result.map_error(fn(_) { MissingRoot(dir) }),
    )
    let matching =
      list.filter(entries, fn(path) {
        list.any(extensions, fn(ext) { string.ends_with(path, ext) })
      })
    Ok(list.append(acc, matching))
  })
}

fn list_files_recursive(
  dir: String,
  exclude_dirs: List(String),
) -> Result(List(String), simplifile.FileError) {
  case simplifile.read_directory(dir) {
    Error(e) -> Error(e)
    Ok(entries) -> {
      let kept = list.filter(entries, fn(e) { !list.contains(exclude_dirs, e) })
      let full_entries = list.map(kept, fn(e) { filepath.join(dir, e) })
      list.try_fold(full_entries, [], fn(acc, entry) {
        case simplifile.is_directory(entry) {
          Ok(True) -> {
            case list_files_recursive(entry, exclude_dirs) {
              Ok(sub_files) -> Ok(list.append(acc, sub_files))
              Error(e) -> Error(e)
            }
          }
          _ -> Ok(list.append(acc, [entry]))
        }
      })
    }
  }
}

fn read_sources(
  files: List(String),
  source_root: String,
  acc: List(ScannedSource),
) -> Result(List(ScannedSource), GenerateError) {
  case files {
    [] -> Ok(list.reverse(acc))
    [file, ..rest] ->
      case simplifile.read(file) {
        Error(_) -> Error(MissingSourceFile(file))
        Ok(content) ->
          read_sources(rest, source_root, [
            ScannedSource(
              path: make_relative(file, source_root),
              content:,
              starts: extractor.marker_names(content),
              ends: extractor.end_marker_names(content),
            ),
            ..acc
          ])
      }
  }
}

/// Names the markers that have both halves of the pair inside one file.
///
/// The scan reads every file before it judges any end directive, so the
/// order in which the files arrive does not change the report.
fn paired_markers(sources: List(ScannedSource)) -> set.Set(String) {
  list.fold(sources, set.new(), fn(acc, source) {
    list.fold(source.starts, acc, fn(names, marker) {
      case list.contains(source.ends, marker) {
        True -> set.insert(names, marker)
        False -> names
      }
    })
  })
}

fn add_start_markers(
  sources: List(ScannedSource),
  acc: MarkerInventory,
) -> Result(MarkerInventory, GenerateError) {
  case sources {
    [] -> Ok(acc)
    [source, ..rest] -> {
      use new_acc <- result_try(add_markers_to_inventory(
        source.starts,
        source,
        acc,
      ))
      add_start_markers(rest, new_acc)
    }
  }
}

fn add_end_markers(
  sources: List(ScannedSource),
  starts: MarkerInventory,
  paired: set.Set(String),
  acc: MarkerInventory,
) -> Result(MarkerInventory, GenerateError) {
  case sources {
    [] -> Ok(acc)
    [source, ..rest] -> {
      use new_acc <- result_try(add_ends_to_inventory(
        source.ends,
        source,
        starts,
        paired,
        acc,
      ))
      add_end_markers(rest, starts, paired, new_acc)
    }
  }
}

/// Files an end directive in the inventory, or reports the structure it broke.
///
/// The file that holds the matching start directive owns the marker. An end
/// directive in a second file is a stray tail when that pair is complete. It
/// is the far half of a split pair when the pair is not complete, and the
/// owning file reports the missing end. An end directive that no start
/// directive answers claims the marker itself, which makes it visible to the
/// orphan check and to extraction.
fn add_ends_to_inventory(
  markers: List(String),
  source: ScannedSource,
  starts: MarkerInventory,
  paired: set.Set(String),
  acc: MarkerInventory,
) -> Result(MarkerInventory, GenerateError) {
  case markers {
    [] -> Ok(acc)
    [marker, ..rest] ->
      case list.contains(source.starts, marker) {
        // This file holds the matching start directive.
        True -> add_ends_to_inventory(rest, source, starts, paired, acc)
        False ->
          case dict.get(starts, marker) {
            Ok(#(start_path, _)) ->
              case set.contains(paired, marker) {
                True -> Error(StrayEndMarker(marker, start_path, source.path))
                // The pair is split across two files. The file with the start
                // directive owns the marker and reports the missing end.
                False ->
                  add_ends_to_inventory(rest, source, starts, paired, acc)
              }
            Error(Nil) ->
              case dict.get(acc, marker) {
                Ok(#(existing_path, _)) ->
                  case existing_path == source.path {
                    True ->
                      add_ends_to_inventory(rest, source, starts, paired, acc)
                    False ->
                      Error(DuplicateMarkerAcrossFiles(
                        marker,
                        existing_path,
                        source.path,
                      ))
                  }
                Error(Nil) ->
                  add_ends_to_inventory(
                    rest,
                    source,
                    starts,
                    paired,
                    dict.insert(acc, marker, #(source.path, source.content)),
                  )
              }
          }
      }
  }
}

fn make_relative(full_path: String, base: String) -> String {
  let base_prefix = case string.ends_with(base, "/") {
    True -> base
    False -> base <> "/"
  }
  case string.starts_with(full_path, base_prefix) {
    True -> string.drop_start(full_path, string.length(base_prefix))
    False -> full_path
  }
}

fn add_markers_to_inventory(
  markers: List(String),
  source: ScannedSource,
  acc: MarkerInventory,
) -> Result(MarkerInventory, GenerateError) {
  case markers {
    [] -> Ok(acc)
    [marker, ..rest] -> {
      case dict.get(acc, marker) {
        Ok(#(existing_path, _)) ->
          case existing_path == source.path {
            True ->
              // Same file, extractor will catch duplicate starts.
              add_markers_to_inventory(rest, source, acc)
            False ->
              Error(DuplicateMarkerAcrossFiles(
                marker,
                existing_path,
                source.path,
              ))
          }
        Error(Nil) -> {
          let new_acc = dict.insert(acc, marker, #(source.path, source.content))
          add_markers_to_inventory(rest, source, new_acc)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Orphan check
// ---------------------------------------------------------------------------

fn check_no_orphans(
  inventory: MarkerInventory,
  snippets: List(SnippetSpec),
) -> Result(Nil, GenerateError) {
  let referenced =
    list.fold(snippets, set.new(), fn(acc, spec) {
      // A whole-file snippet names no marker, so it cannot make one used.
      case spec.selection {
        config.WholeFileSelection -> acc
        config.MarkerSelection(markers, _) ->
          list.fold(markers, acc, fn(s, m) { set.insert(s, m) })
      }
    })

  let orphans =
    dict.to_list(inventory)
    |> list.filter(fn(pair) {
      let #(marker, _) = pair
      !set.contains(referenced, marker)
    })

  case orphans {
    [] -> Ok(Nil)
    [#(marker, #(path, _)), ..] -> Error(OrphanMarker(marker, path))
  }
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

fn compose_all(
  cfg: Config,
  source_root: String,
  inventory: MarkerInventory,
) -> Result(List(ManifestEntry), GenerateError) {
  list.try_map(cfg.snippets, fn(spec) {
    compose_one(spec, source_root, inventory)
  })
}

fn compose_one(
  spec: SnippetSpec,
  source_root: String,
  inventory: MarkerInventory,
) -> Result(ManifestEntry, GenerateError) {
  let source_file = filepath.join(source_root, spec.source_path)
  use content <- result_try(
    simplifile.read(source_file)
    |> result.map_error(fn(_) { MissingSourceFile(spec.source_path) }),
  )

  case spec.selection {
    config.WholeFileSelection ->
      Ok(ManifestEntry(
        id: spec.id,
        code: extractor.without_directives(content),
        language: spec.language,
        source_path: spec.source_path,
        origin: manifest.FileOrigin,
      ))
    config.MarkerSelection(markers, separator) ->
      compose_ranges(spec, content, inventory, markers, separator)
  }
}

fn compose_ranges(
  spec: SnippetSpec,
  content: String,
  inventory: MarkerInventory,
  markers: List(String),
  separator: String,
) -> Result(ManifestEntry, GenerateError) {
  use ranges <- result_try(
    list.try_map(markers, fn(marker) {
      // Validate that the marker exists in the inventory for this source path.
      case dict.get(inventory, marker) {
        Error(Nil) -> Error(MarkerNotFound(spec.id, marker, spec.source_path))
        Ok(#(inv_path, _)) -> {
          case inv_path == spec.source_path {
            False -> Error(MarkerNotFound(spec.id, marker, spec.source_path))
            True ->
              extractor.extract(content, spec.source_path, marker)
              |> result.map_error(fn(e) { ExtractionError(spec.id, e) })
          }
        }
      }
    }),
  )

  let code =
    ranges
    |> list.map(fn(r: extractor.MarkerRange) { r.code })
    |> string.join(separator)

  Ok(ManifestEntry(
    id: spec.id,
    code:,
    language: spec.language,
    source_path: spec.source_path,
    origin: manifest.MarkerOrigin(markers),
  ))
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}
