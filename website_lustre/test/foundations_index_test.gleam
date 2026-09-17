import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import watershed_site/content
import watershed_site/page
import watershed_site/route
import watershed_site/snippet

pub fn foundations_index_renders_the_catalog_without_a_client_test() {
  let assert Ok(foundations) =
    route.all()
    |> list.find(fn(item) { item.path == "/foundations" })
  let assert Ok(source) = content.load(foundations)
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  let assert Ok(document) = page.render(source, foundations, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — foundations</title>",
    "content=\"https://watershed.tylerbutler.com/foundations/\" property=\"og:url\"",
    "id=\"content\"",
    "aria-labelledby=\"fh-ledger-title\"",
    "Before you",
    "<em>build anything.</em>",
    "href=\"/styles/concept-index.css\"",
    "src=\"/scripts/concept-index.js\" type=\"module\"",
    "href=\"/component-model\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "fh-item") |> list.length |> should.equal(3)
  ["schema", "topology", "lifecycle"]
  |> list.each(fn(slug) {
    find(tree, "href", "/foundations/" <> slug)
    |> list.is_empty
    |> should.be_false()
  })
  [
    "/guide_race.js", "/styles/guide-race.css", "astro-island", "/_astro/",
    "data-component", "canonical",
  ]
  |> list.each(fn(absent) {
    let assert False = string.contains(html, absent) as absent
  })
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
