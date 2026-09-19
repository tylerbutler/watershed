import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import watershed_site/view/examples

pub fn examples_page_renders_the_full_catalog_test() {
  let html = examples.view() |> element.to_document_string()
  [
    "Run the examples.",
    "Foundation and lifecycle",
    "Collaborative dice",
    "href=\"/structures/maps#map\"",
    "Treat the server as an optional decorator",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "e-entry") |> list.length |> should.equal(14)
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
