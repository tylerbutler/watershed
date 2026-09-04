import gleam/dict
import gleam/string
import gleeunit/should
import jot
import lustre/element
import lustre/ssg/djot
import simplifile
import watershed_site/code
import watershed_site/content
import watershed_site/error
import watershed_site/snippet

const manifest_path = "../website/src/generated/snippets.json"

pub fn real_manifest_decodes_test() {
  let assert Ok(manifest) = snippet.load(manifest_path)
  manifest.version |> should.equal(1)
  let assert Ok(entry) =
    snippet.get(manifest, "page.djot", "foundations-schema-title-field")
  string.contains(entry.code, "pub fn") |> should.be_true()
  snippet.get(manifest, "page.djot", "missing")
  |> should.equal(Error(error.MissingSnippet("page.djot", "missing")))
}

pub fn invalid_manifests_are_rejected_test() {
  let assert Error(error.InvalidSnippetManifest("bad.json", reason)) =
    snippet.decode("{\"version\":2,\"snippets\":{}}", "bad.json")
  string.contains(reason, "2") |> should.be_true()
  snippet.decode("{\"version\":1}", "bad.json") |> should.be_error()
  snippet.decode(
    "{\"version\":1,\"snippets\":{\"bad\":{\"code\":\"x\"}}}",
    "bad.json",
  )
  |> should.be_error()
}

pub fn origins_decode_test() {
  let assert Ok(manifest) =
    snippet.decode(
      "{\"version\":1,\"snippets\":{\"source\":{\"code\":\"x\",\"language\":\"gleam\",\"sourcePath\":\"x.gleam\",\"origin\":{\"kind\":\"source\",\"markers\":[\"one\"]}},\"file\":{\"code\":\"x\",\"language\":\"js\",\"sourcePath\":\"x.mjs\",\"origin\":{\"kind\":\"file\"}}}}",
      "test.json",
    )
  let assert Ok(source) = dict.get(manifest.snippets, "source")
  let assert Ok(file) = dict.get(manifest.snippets, "file")
  source.origin |> should.equal(snippet.Source(["one"]))
  file.origin |> should.equal(snippet.File)
}

pub fn snippet_fixture_uses_manifest_and_highlights_test() {
  let assert Ok(manifest) = snippet.load(manifest_path)
  let assert Ok(fixture) = simplifile.read("test/fixtures/snippet.djot")
  content.validate_snippets(jot.parse(fixture), manifest, "fixture.djot")
  |> should.be_ok()
  let html =
    djot.render(fixture, code.renderer(manifest, "abc123"))
    |> element.fragment
    |> element.to_string
  string.contains(html, "ignored fixture text") |> should.be_false()
  string.contains(html, "smalto-keyword") |> should.be_true()
  string.contains(html, "https://github.com/tylerbutler/watershed/blob/abc123/")
  |> should.be_true()
  let assert Ok(entry) =
    snippet.get(manifest, "fixture.djot", "foundations-schema-title-field")
  string.contains(html, entry.source_path) |> should.be_true()
}

pub fn unknown_language_escapes_source_test() {
  code.highlighted("unknown", "<script>alert(1)</script>")
  |> element.fragment
  |> element.to_string
  |> should.equal(
    "<!-- lustre:fragment -->&lt;script&gt;alert(1)&lt;/script&gt;<!-- /lustre:fragment -->",
  )
}

pub fn missing_snippet_stops_validation_test() {
  let manifest = snippet.Manifest(1, dict.new())
  content.validate_snippets(
    jot.parse("{data-snippet=\"missing\"}\n```gleam\nx\n```"),
    manifest,
    "page.djot",
  )
  |> should.equal(Error(error.MissingSnippet("page.djot", "missing")))
}
