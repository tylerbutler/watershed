import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import support
import watershed_site/content
import watershed_site/page
import watershed_site/snippet

pub fn component_model_index_renders_its_catalog_test() {
  let component_model = support.route("/component-model")
  let assert Ok(source) = content.load(component_model)
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  let assert Ok(document) =
    page.render(source, component_model, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — component model</title>",
    "content=\"https://watershed.tylerbutler.com/component-model/\" property=\"og:url\"",
    "id=\"content\"",
    "aria-labelledby=\"fh-ledger-title\"",
    "Give users",
    "<em>the parts.</em>",
    "href=\"/styles/concept-index.css\"",
    "src=\"/scripts/concept-index.js\" type=\"module\"",
    "href=\"/foundations\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "fh-item") |> list.length |> should.equal(3)
  ["components", "ports", "workspaces"]
  |> list.each(fn(slug) {
    find(tree, "href", "/component-model/" <> slug)
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
