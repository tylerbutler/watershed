import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import support
import watershed_site/content
import watershed_site/page
import watershed_site/snippet

pub fn models_page_renders_all_three_convergence_models_test() {
  let models = support.route("/models")
  let assert Ok(source) = content.load(models)
  let assert Ok(manifest) = snippet.load("src/generated/snippets.json")
  let assert Ok(document) = page.render(source, models, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — DDS vs CRDT vs OT</title>",
    "Three ways to",
    "<em>agree on state.</em>",
    "Distributed Data Structure",
    "Conflict-free Replicated Data Type",
    "Operational Transform",
    "href=\"/styles/models.css\"",
    "src=\"/scripts/concept-index.js\" type=\"module\"",
    "href=\"/structures/maps#map\"",
    "href=\"/rich-text\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "mod-card") |> list.length |> should.equal(3)
  find(tree, "class", "mod-table") |> list.length |> should.equal(1)
  ["/guide_race.js", "canonical"]
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
