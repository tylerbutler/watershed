import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import watershed_site/content
import watershed_site/error
import watershed_site/page
import watershed_site/route
import watershed_site/snippet

fn index_route() {
  let assert Ok(route) =
    list.find(route.all(), fn(route) { route.path == "/guide" })
  route
}

pub fn guide_index_renders_all_six_steps_without_a_client_test() {
  let route = index_route()
  route.client_script |> should.equal(None)
  let assert Ok(source) = content.load(route)
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  let assert Ok(document) = page.render(source, route, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — build guide</title>",
    "content=\"https://watershed.tylerbutler.com/guide/\" property=\"og:url\"",
    "id=\"content\"",
    "aria-labelledby=\"gi-build-title\"",
    "aria-labelledby=\"gi-ledger-title\"",
    "aria-labelledby=\"gi-companion-title\"",
    "The retro board document shape",
    "Build a multiplayer app,",
    "<em>step by step.</em>",
    "href=\"/styles/guide-index.css\"",
    "src=\"/scripts/guide-index.js\" type=\"module\"",
    "href=\"/examples\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "gi-step") |> list.length |> should.equal(6)
  ["connect", "notes", "race", "votes", "presence", "testing"]
  |> list.each(fn(slug) {
    find(tree, "href", "/guide/" <> slug)
    |> list.is_empty
    |> should.be_false()
  })
  [
    "/guide_race.js", "/styles/guide-race.css", "guide-race-mount",
    "astro-island", "/_astro/", "data-component", "canonical",
  ]
  |> list.each(fn(absent) {
    let assert False = string.contains(html, absent) as absent
  })
}

pub fn guide_index_metadata_rejects_step_and_layout_mismatches_test() {
  let route = index_route()
  let metadata = "---\ndescription = \"Guide.\"\nlayout = \"guide-index\"\n"
  content.parse(metadata <> "---\n\nA guide.", "index.djot", route)
  |> should.be_ok()
  [
    #(metadata <> "guide_step = \"race\"\n", "guide_step"),
    #(metadata <> "extra = true\n", "extra"),
    #("---\ndescription = \"Guide.\"\nlayout = \"guide\"\n", "layout"),
  ]
  |> list.each(fn(pair) {
    let assert Error(error.InvalidFrontmatter("index.djot", reason)) =
      content.parse(pair.0 <> "---\n\nA guide.", "index.djot", route)
    string.contains(reason, pair.1) |> should.be_true()
  })
  content.parse(
    metadata <> "---\n\nA guide.",
    "index.djot",
    route.Route(..route, path: "/other"),
  )
  |> should.be_error()
}

fn find(
  tree: html_parser.Element,
  key: String,
  value: String,
) -> List(html_parser.Element) {
  case tree {
    html_parser.StartElement(_, attributes, children) -> {
      let matches = case
        list.contains(attributes, html_parser.Attribute(key, value))
      {
        True -> [tree]
        False -> []
      }
      list.append(matches, list.flat_map(children, find(_, key, value)))
    }
    _ -> []
  }
}
