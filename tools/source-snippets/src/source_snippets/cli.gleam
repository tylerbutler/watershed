//// CLI entry point for the source-snippet generator.
////
//// Usage: gleam run -m source_snippets/cli -- <config.json> <output.json>
////
//// Writes output atomically: generates to a .tmp sibling, renames only
//// after generation and encoding succeed. Does not delete valid output
//// on failure.

import argv
import filepath
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import simplifile
import source_snippets/generator
import source_snippets/manifest
import source_snippets/system

/// Errors produced by the CLI.
pub type CliError {
  /// Expected exactly 2 positional arguments; received count.
  WrongArgumentCount(count: Int)
  /// Manifest generation failed.
  GenerationFailed(error: generator.GenerateError)
  /// Output file could not be written.
  OutputWriteError(path: String)
}

/// Entry point called by `gleam run -m source_snippets/cli`.
pub fn main() {
  case run(argv.load().arguments) {
    Ok(Nil) -> Nil
    Error(e) -> {
      io.println_error(format_error(e))
      system.halt(1)
    }
  }
}

/// Runs the generator with the given argument list.
///
/// Expects exactly two arguments: the config path and the output path.
/// Creates the output parent directory if absent.
/// Writes to <output>.tmp first; renames only on success.
pub fn run(arguments: List(String)) -> Result(Nil, CliError) {
  case arguments {
    [config_path, output_path] -> {
      use m <- result.try(
        generator.generate(config_path)
        |> result.map_error(GenerationFailed),
      )
      let json = manifest.encode(m)
      let tmp_path = output_path <> ".tmp"
      use _ <- result.try(ensure_parent(output_path))
      use _ <- result.try(
        simplifile.write(tmp_path, json)
        |> result.map_error(fn(_) { OutputWriteError(tmp_path) }),
      )
      simplifile.rename(tmp_path, output_path)
      |> result.map_error(fn(_) {
        let _ = simplifile.delete(tmp_path)
        OutputWriteError(output_path)
      })
    }
    _ -> Error(WrongArgumentCount(list.length(arguments)))
  }
}

/// Formats a CLI error as an actionable one-line message.
///
/// The message names the relevant file path and marker id so the
/// caller can locate and fix the problem without additional context.
pub fn format_error(e: CliError) -> String {
  case e {
    WrongArgumentCount(n) ->
      "error: expected 2 arguments (config output), got " <> int.to_string(n)
    GenerationFailed(generator.ConfigReadError(path)) ->
      "error: cannot read config: " <> path
    GenerationFailed(generator.ConfigDecodeError(_)) ->
      "error: invalid config JSON"
    GenerationFailed(generator.MissingRoot(root)) ->
      "error: marker root not found: " <> root
    GenerationFailed(generator.MissingSourceFile(path)) ->
      "error: source file not found: " <> path
    GenerationFailed(generator.DuplicateMarkerAcrossFiles(marker, first, second)) ->
      "error: marker \""
      <> marker
      <> "\" found in both "
      <> first
      <> " and "
      <> second
    GenerationFailed(generator.MarkerNotFound(snippet_id, marker, path)) ->
      "error: snippet \""
      <> snippet_id
      <> "\": marker \""
      <> marker
      <> "\" not found in "
      <> path
    GenerationFailed(generator.ExtractionError(snippet_id, _)) ->
      "error: snippet \"" <> snippet_id <> "\": extraction failed"
    GenerationFailed(generator.OrphanMarker(marker, path)) ->
      "error: marker \""
      <> marker
      <> "\" in "
      <> path
      <> " is not referenced by any snippet"
    GenerationFailed(generator.InvalidSourcePath(snippet_id, path)) ->
      "error: snippet \"" <> snippet_id <> "\": invalid source path: " <> path
    OutputWriteError(path) -> "error: cannot write output: " <> path
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn ensure_parent(output_path: String) -> Result(Nil, CliError) {
  case filepath.directory_name(output_path) {
    "" | "." -> Ok(Nil)
    dir ->
      simplifile.create_directory_all(dir)
      |> result.map_error(fn(_) { OutputWriteError(output_path) })
  }
}
