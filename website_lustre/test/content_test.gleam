import fixtures/catalog_contract
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import jot
import support
import watershed_site/content
import watershed_site/error
import watershed_site/guide
import watershed_site/route
import watershed_site/snippet

fn parse(metadata: String) {
  content.parse(
    "---\n" <> metadata <> "\n---\n\n# Test",
    "page.djot",
    support.route("/guide/race"),
  )
}

const required = "description = \"A test page.\""

pub fn race_copy_is_preserved_test() {
  let assert Ok(source) = content.load(support.route("/guide/race"))
  source.metadata.description
  |> should.equal(
    "Step three of the watershed build guide: add notes from two tabs at the same instant and confirm that both appear on the shared board.",
  )
  source.metadata.kind |> should.equal(content.GuideStep(guide.Race))
  let components =
    list.filter(source.document.content, fn(block) {
      case block {
        jot.Div(attributes, _) ->
          dict.get(attributes, "data-component") == Ok("guide-race")
        _ -> False
      }
    })
  list.length(components) |> should.equal(1)
  [
    "Add notes from both tabs at once",
    "Open the board in two tabs. In each one, type a different note into",
    "and click Add in both at the same moment.",
    "Both notes show up, in both tabs, in the same order. Nothing is lost.",
    "Each note uses a different key",
    "Notes are keyed by note id in an",
    "so two adds write two different keys — there's nothing for them to collide over.",
    "Store the board as a plain map keyed by column instead, and you'd get one note back, not two: a map with one key per column has one slot per column, so the second note overwrites the first — that's what “last write wins” means. Keying by note id means there's no shared slot to overwrite.",
  ]
  |> list.each(fn(text) {
    let assert True = string.contains(source.body, text) as text
  })
}

pub fn valid_metadata_test() {
  let assert Ok(source) =
    content.load(
      route.Route(
        ..support.route("/guide/race"),
        content_path: "test/fixtures/valid-page.djot",
      ),
    )
  source.metadata
  |> should.equal(content.Metadata(
    "A test page.",
    content.GuideStep(guide.Race),
    None,
    None,
  ))
}

pub fn route_defines_page_kind_test() {
  let assert Ok(source) = parse(required)
  source.metadata.kind |> should.equal(content.GuideStep(guide.Race))
}

pub fn optional_metadata_test() {
  let assert Ok(source) =
    parse(
      required
      <> "\nog_title = \"Social title\"\nog_description = \"Social description\"",
    )
  source.metadata.og_title |> should.equal(Some("Social title"))
  source.metadata.og_description |> should.equal(Some("Social description"))
}

pub fn invalid_metadata_has_file_and_field_test() {
  [
    #("", "description"),
    #(required <> "\nlayout = \"guide\"", "layout"),
    #(required <> "\nguide_step = \"race\"", "guide_step"),
    #(required <> "\nconcept = \"schema\"", "concept"),
    #(required <> "\nfamily = \"maps\"", "family"),
    #(required <> "\nextra = 1", "extra"),
    #(required <> "\nog_title = 1", "og_title"),
    #(required <> "\nog_description = false", "og_description"),
  ]
  |> list.each(fn(pair) {
    let assert Error(error.InvalidFrontmatter(path, reason)) = parse(pair.0)
    path |> should.equal("page.djot")
    string.contains(reason, pair.1) |> should.be_true()
  })
  let assert Error(error.InvalidFrontmatter("page.djot", _)) =
    parse("description = [")
}

pub fn route_defines_specialized_page_kinds_test() {
  let page = "---\ndescription = \"Test.\"\n---\n\nA page."
  let assert Ok(concept) =
    content.parse(page, "page.djot", support.route("/foundations/" <> "schema"))
  let assert content.ConceptSheet(_) = concept.metadata.kind
  let assert Ok(runtime) =
    content.parse(page, "page.djot", support.route("/runtime/" <> "optimistic"))
  let assert content.RuntimeSheet(_) = runtime.metadata.kind
  let assert Ok(structure) =
    content.parse(page, "page.djot", support.route("/structures/" <> "maps"))
  let assert content.StructureSheet(_) = structure.metadata.kind
}

pub fn raw_html_and_unknown_components_are_rejected_test() {
  content.load(
    route.Route(
      ..support.route("/guide/race"),
      content_path: "test/fixtures/raw-html.djot",
    ),
  )
  |> should.equal(Error(error.RawHtml("test/fixtures/raw-html.djot")))
  content.load(
    route.Route(
      ..support.route("/guide/race"),
      content_path: "test/fixtures/unknown-component.djot",
    ),
  )
  |> should.equal(
    Error(error.UnknownComponent(
      "test/fixtures/unknown-component.djot",
      "not-registered",
    )),
  )
}

pub fn nested_raw_html_is_rejected_test() {
  content.parse(
    "---\n" <> required <> "\n---\n\n::: outer\n```=html\nbad\n```\n:::",
    "nested.djot",
    support.route("/guide/race"),
  )
  |> should.equal(Error(error.RawHtml("nested.djot")))
}

pub fn guide_catalog_matches_contract_test() {
  guide.all() |> should.equal(catalog_contract.guide())
  guide.neighbours(guide.Race)
  |> should.equal(#(Some(guide.get(guide.Notes)), Some(guide.get(guide.Votes))))
  guide.neighbours(guide.Connect).0 |> should.equal(None)
  guide.neighbours(guide.Testing).1 |> should.equal(None)
}

pub fn invalid_snippet_attributes_are_rejected_test() {
  let manifest = snippet.Manifest(1, dict.new())
  [
    #(
      "{data-snippet=\"missing\" data-source-label=\"label\"}\n```gleam\nx\n```",
      "data-source-label",
    ),
    #("{data-source-label=\"\"}\n```text\nx\n```", "data-source-label"),
    #("{data-caption=\"\"}\n```text\nx\n```", "data-caption"),
  ]
  |> list.each(fn(item) {
    let assert Error(error.InvalidContent("page.djot", reason)) =
      content.validate_snippets(jot.parse(item.0), manifest, "page.djot")
    string.contains(reason, item.1) |> should.be_true()
  })
}

pub fn stale_field_note_references_are_rejected_test() {
  let page =
    "---\n"
    <> required
    <> "\n---\n\n{data-component=\"field-note-ref\" data-practice=\"missing\"}\n:::\n:::"
  content.parse(page, "page.djot", support.route("/guide/race"))
  |> should.equal(Error(error.UnknownPractice("page.djot", "missing")))
}
