//// Repository-level test for watershed's own snippet configuration.
////
//// The configuration at `website/snippets.json` must name every
//// source-backed snippet the documentation website renders. This test
//// pins that inventory and proves the configuration still generates.

import gleam/list
import gleam/string
import gleeunit/should
import simplifile
import source_snippets/config
import source_snippets/extractor
import source_snippets/generator
import source_snippets/manifest

/// Path to watershed's configuration, relative to this package.
const config_path = "../../website/snippets.json"

/// Every output id the website renders from marked source.
///
/// Fifty-one come from guide and foundations sheets, seventeen from field
/// note practices, and ten from the standalone registry.
const expected_ids = [
  "foundations-lifecycle-assemble", "foundations-lifecycle-bootstrap",
  "foundations-lifecycle-connect", "foundations-lifecycle-ensure-channel",
  "foundations-lifecycle-ensured-arms", "foundations-lifecycle-readiness",
  "foundations-schema-channel-field-type", "foundations-schema-child-field-type",
  "foundations-schema-field-error", "foundations-schema-field-type",
  "foundations-schema-get-field", "foundations-schema-player-schema",
  "foundations-schema-stamp", "foundations-schema-sudoku-fields",
  "foundations-schema-text-child", "foundations-schema-title-field",
  "foundations-topology-create-map", "foundations-topology-handle-of",
  "foundations-topology-resolve", "foundations-topology-resolve-child",
  "foundations-topology-root-typed", "guide-connect-assemble",
  "guide-connect-bootstrap", "guide-connect-dev-constants", "guide-connect-init",
  "guide-connect-main", "guide-connect-readiness", "guide-connect-schema",
  "guide-notes-add-clicked", "guide-notes-add-note", "guide-notes-codec",
  "guide-notes-note-entries", "guide-notes-note-record", "guide-notes-ordering",
  "guide-notes-unfiled", "guide-presence-announce", "guide-presence-effect",
  "guide-presence-events", "guide-presence-focus-clicked",
  "guide-presence-focus-names", "guide-presence-payload",
  "guide-presence-remote-peers", "guide-testing-add-race",
  "guide-testing-board-of", "guide-testing-room", "guide-testing-vote-race",
  "guide-votes-card", "guide-votes-orphan-test", "guide-votes-vote-clicks",
  "guide-votes-vote-entries", "guide-votes-vote-ops", "homepage-beam",
  "optimistic-local", "p2p-config", "practice-anchors-not-offsets",
  "practice-authoritative-channel", "practice-claims-seeding",
  "practice-deterministic-death", "practice-diagnostics-first",
  "practice-fallible-edits", "practice-ffi-surface", "practice-presence-idiom",
  "practice-protocol-on-ripples", "practice-pure-modules",
  "practice-quorum-pending-roster", "practice-realtime-out-of-band",
  "practice-relay-decorator", "practice-shared-core-two-runtimes",
  "practice-stamp-schema", "practice-typedmap-panels",
  "practice-unsettled-writes", "sharedtree-bootstrap", "sharedtree-declare",
  "sharedtree-events", "sharedtree-nest", "sharedtree-per-kind",
  "sharedtree-read-write", "sharedtree-record",
]

fn load_config() -> config.Config {
  let assert Ok(text) = simplifile.read(config_path)
  let assert Ok(cfg) = config.decode_config(text)
  cfg
}

// ---------------------------------------------------------------------------
// Configuration shape
// ---------------------------------------------------------------------------

pub fn config_decodes_test() {
  let cfg = load_config()
  cfg.version |> should.equal(1)
  cfg.extensions |> list.contains(".gleam") |> should.be_true
  cfg.extensions |> list.contains(".mjs") |> should.be_true
}

pub fn source_root_resolves_to_repository_root_test() {
  let cfg = load_config()
  // `sourceRoot` is relative to the configuration file in `website/`.
  let resolved = "../../website/" <> cfg.source_root
  simplifile.is_file(resolved <> "/gleam.toml") |> should.equal(Ok(True))
  simplifile.is_directory(resolved <> "/examples") |> should.equal(Ok(True))
  simplifile.is_directory(resolved <> "/website") |> should.equal(Ok(True))
}

pub fn every_marker_root_exists_test() {
  let cfg = load_config()
  list.each(cfg.marker_roots, fn(root) {
    simplifile.is_directory("../../website/" <> cfg.source_root <> "/" <> root)
    |> should.equal(Ok(True))
  })
}

// ---------------------------------------------------------------------------
// Complete inventory
// ---------------------------------------------------------------------------

pub fn config_declares_every_website_snippet_test() {
  let ids =
    load_config().snippets
    |> list.map(fn(spec) { spec.id })
    |> list.sort(string.compare)

  ids |> should.equal(expected_ids)
}

pub fn inventory_counts_by_area_test() {
  let ids = load_config().snippets |> list.map(fn(spec) { spec.id })

  let count = fn(prefix) {
    list.count(ids, fn(id) { string.starts_with(id, prefix) })
  }

  // Guide and foundations sheets extract directly.
  { count("guide-") + count("foundations-") } |> should.equal(51)
  // One snippet per field note practice.
  count("practice-") |> should.equal(17)
  // The homepage, runtime sheets, and the SharedTree comparison.
  { count("homepage-") + count("optimistic-") + count("p2p-") }
  |> should.equal(3)
  count("sharedtree-") |> should.equal(7)
  list.length(ids) |> should.equal(78)
}

/// The guide's schema sheet shows a complete module.
///
/// The formatter puts a marker directive below the `////` module
/// documentation, so a marker range cannot hold the head of the file. The
/// whole-file selector reads the file and removes the directive lines.
pub fn guide_connect_schema_selects_the_whole_file_test() {
  let cfg = load_config()
  let assert Ok(spec) =
    list.find(cfg.snippets, fn(spec: config.SnippetSpec) {
      spec.id == "guide-connect-schema"
    })

  spec.selection |> should.equal(config.WholeFileSelection)
  spec.source_path
  |> should.equal(
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam",
  )
}

pub fn guide_connect_schema_generates_the_exact_module_test() {
  let cfg = load_config()
  let assert Ok(generated) = generator.generate(config_path)
  let assert Ok(entry) =
    list.find(generated.snippets, fn(entry: manifest.ManifestEntry) {
      entry.id == "guide-connect-schema"
    })

  entry.origin |> should.equal(manifest.FileOrigin)

  let assert Ok(source) =
    simplifile.read(
      "../../website/" <> cfg.source_root <> "/" <> entry.source_path,
    )

  // The generated listing is the source file without its directive lines.
  entry.code |> should.equal(extractor.without_directives(source))
  string.starts_with(
    entry.code,
    "//// Typed schema for the tutorial retro board.",
  )
  |> should.be_true
  string.contains(entry.code, "pub fn votes()") |> should.be_true
}

/// A whole-file snippet is not a marker reference.
///
/// The schema module holds the `retro-schema-title` pair, and the schema
/// sheet quotes it. The file listing must not stand in for that reference.
pub fn whole_file_snippets_declare_no_markers_test() {
  let cfg = load_config()
  list.each(cfg.snippets, fn(spec: config.SnippetSpec) {
    case spec.selection {
      config.WholeFileSelection -> Nil
      config.MarkerSelection(markers, _) ->
        case markers {
          [] -> panic as { spec.id <> " declares no markers" }
          _ -> Nil
        }
    }
  })
}

pub fn every_snippet_names_an_existing_source_test() {
  let cfg = load_config()
  list.each(cfg.snippets, fn(spec) {
    let path = "../../website/" <> cfg.source_root <> "/" <> spec.source_path
    case simplifile.is_file(path) {
      Ok(True) -> Nil
      _ ->
        panic as { spec.id <> " names a missing source: " <> spec.source_path }
    }
  })
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

pub fn configuration_generates_a_complete_manifest_test() {
  let assert Ok(generated) = generator.generate(config_path)

  generated.version |> should.equal(1)

  let ids =
    generated.snippets
    |> list.map(fn(entry: manifest.ManifestEntry) { entry.id })
    |> list.sort(string.compare)

  ids |> should.equal(expected_ids)
}

pub fn every_generated_snippet_holds_code_test() {
  let assert Ok(generated) = generator.generate(config_path)

  list.each(generated.snippets, fn(entry: manifest.ManifestEntry) {
    case string.trim(entry.code) {
      "" -> panic as { entry.id <> " generated an empty snippet" }
      _ -> Nil
    }
    case string.contains(entry.code, "docs:snippet-") {
      True -> panic as { entry.id <> " leaks a marker directive" }
      False -> Nil
    }
  })
}
