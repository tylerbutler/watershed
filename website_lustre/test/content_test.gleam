import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import watershed_site/content
import watershed_site/error
import watershed_site/guide
import watershed_site/route

fn parse(metadata: String) {
  content.parse(
    "---\n" <> metadata <> "\n---\n\n# Test",
    "page.djot",
    route.guide_race(),
  )
}

const required = "description = \"A test page.\"\nlayout = \"guide\"\nguide_step = \"race\""

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
    route.Guide,
    guide.Race,
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
