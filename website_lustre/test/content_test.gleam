import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import jot
import simplifile
import watershed_site/content
import watershed_site/error
import watershed_site/guide
import watershed_site/route
import watershed_site/snippet

fn parse(metadata: String) {
  content.parse(
    "---\n" <> metadata <> "\n---\n\n# Test",
    "page.djot",
    route.guide_race(),
  )
}

const required = "description = \"A test page.\"\nlayout = \"guide\"\nguide_step = \"race\""

pub fn race_copy_is_preserved_test() {
  let assert Ok(source) = content.load(route.guide_race())
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
        ..route.guide_race(),
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
    #("layout = \"guide\"\nguide_step = \"race\"", "description"),
    #(string.replace(required, "\"guide\"", "\"other\""), "layout"),
    #(string.replace(required, "\"race\"", "\"other\""), "guide_step"),
    #(string.replace(required, "\"race\"", "\"notes\""), "guide_step"),
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

pub fn concept_sheet_metadata_matches_its_route_test() {
  let page =
    "---\ndescription = \"Schema.\"\nlayout = \"concept-sheet\"\nconcept = \"schema\"\n---\n\nA page."
  content.parse(page, "schema.djot", route.foundation("schema"))
  |> should.be_ok()
  [
    #(
      string.replace(page, "concept = \"schema\"", "concept = \"unknown\""),
      "concept",
    ),
    #(
      string.replace(page, "concept = \"schema\"", "concept = \"topology\""),
      "concept",
    ),
    #(string.replace(page, "concept-sheet", "guide"), "layout"),
    #(
      string.replace(
        page,
        "concept = \"schema\"",
        "concept = \"schema\"\nguide_step = \"race\"",
      ),
      "guide_step",
    ),
  ]
  |> list.each(fn(pair) {
    let assert Error(error.InvalidFrontmatter("schema.djot", reason)) =
      content.parse(pair.0, "schema.djot", route.foundation("schema"))
    string.contains(reason, pair.1) |> should.be_true()
  })
}

pub fn component_model_index_metadata_matches_its_route_test() {
  let page =
    "---\ndescription = \"Components.\"\nlayout = \"concept-index\"\n---\n\nA page."
  let component_model =
    route.Route(
      path: "/component-model",
      layout: route.ConceptIndex,
      content_path: "component-model.djot",
      client_script: None,
      analytics: route.Tinylytics,
    )
  content.parse(page, "component-model.djot", component_model)
  |> should.be_ok()
}

pub fn raw_html_and_unknown_components_are_rejected_test() {
  content.load(
    route.Route(
      ..route.guide_race(),
      content_path: "test/fixtures/raw-html.djot",
    ),
  )
  |> should.equal(Error(error.RawHtml("test/fixtures/raw-html.djot")))
  content.load(
    route.Route(
      ..route.guide_race(),
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
    route.guide_race(),
  )
  |> should.equal(Error(error.RawHtml("nested.djot")))
}

pub fn guide_catalog_matches_astro_test() {
  let assert Ok(source) = simplifile.read("../website/src/data/guide.ts")
  string.split(source, "slug: \"")
  |> list.length
  |> should.equal(list.length(guide.all()) + 1)
  guide.all()
  |> list.each(fn(step) {
    [
      #("n", step.number),
      #("slug", string.replace(guide.path(step.slug), "/guide/", "")),
      #("title", step.title),
      #("goal", step.goal),
      #("surface", step.surface),
    ]
    |> list.each(fn(field) {
      string.contains(source, field.0 <> ": \"" <> field.1 <> "\"")
      |> should.be_true()
    })
  })
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
  content.parse(page, "page.djot", route.guide_race())
  |> should.equal(Error(error.UnknownPractice("page.djot", "missing")))
}
