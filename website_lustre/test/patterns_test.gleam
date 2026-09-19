import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import support
import watershed_site/content
import watershed_site/page
import watershed_site/snippet

pub fn patterns_page_renders_every_practice_test() {
  let patterns = support.route("/patterns")
  let assert Ok(source) = content.load(patterns)
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  let assert Ok(document) = page.render(source, patterns, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — patterns from the examples</title>",
    "Implementation patterns",
    "from the examples.",
    "Treat the server as an optional decorator",
    "Test client death deterministically",
    "href=\"/styles/patterns.css\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "p-rule-link") |> list.length |> should.equal(17)
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
