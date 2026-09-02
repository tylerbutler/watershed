//// Public API for the source-snippet tool.
////
//// Re-exports types and functions from internal modules: extractor,
//// config, generator, and manifest.

import source_snippets/config
import source_snippets/extractor
import source_snippets/generator
import source_snippets/manifest

// ---------------------------------------------------------------------------
// Extractor
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

pub type Config =
  config.Config

pub type SnippetSpec =
  config.SnippetSpec

pub type ConfigError =
  config.ConfigError

/// Decodes a JSON string into a validated configuration.
pub fn decode_config(json: String) -> Result(Config, ConfigError) {
  config.decode_config(json)
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

pub type GeneratedSnippet =
  generator.GeneratedSnippet

pub type GenerateError =
  generator.GenerateError

/// Generates a manifest from a configuration file path.
pub fn generate(config_path: String) -> Result(Manifest, GenerateError) {
  generator.generate(config_path)
}

// ---------------------------------------------------------------------------
// Manifest
// ---------------------------------------------------------------------------

pub type Manifest =
  manifest.Manifest

pub type ManifestEntry =
  manifest.ManifestEntry

/// Encodes a manifest to a deterministic JSON string.
pub fn encode(m: Manifest) -> String {
  manifest.encode(m)
}
