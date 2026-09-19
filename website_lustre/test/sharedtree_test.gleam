import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import watershed_site/view/sharedtree

pub fn sharedtree_view_renders_comparison_frame_test() {
  let html =
    sharedtree.view([element.text("comparison body")])
    |> element.to_document_string()
  [
    "Two places to put",
    "the guarantee.",
    "comparison body",
    "SharedTree documentation",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "scope", "row") |> list.length |> should.equal(13)
  find(tree, "class", "st-table-scroll") |> list.length |> should.equal(1)
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
