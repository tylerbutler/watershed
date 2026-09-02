//// Public API for the source-snippet marker extractor.
////
//// Re-exports types and functions from `source_snippets/extractor`.

import source_snippets/extractor

pub type MarkerRange =
  extractor.MarkerRange

pub type MarkerError =
  extractor.MarkerError

/// Returns the names of all start markers found in the source.
pub fn marker_names(source: String) -> List(String) {
  extractor.marker_names(source)
}

/// Extracts the named marker range from source.
pub fn extract(
  source: String,
  source_path: String,
  marker: String,
) -> Result(MarkerRange, MarkerError) {
  extractor.extract(source, source_path, marker)
}
