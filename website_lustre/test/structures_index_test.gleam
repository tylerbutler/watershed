import gleam/list
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import support
import watershed_site/content
import watershed_site/page
import watershed_site/snippet

pub fn structures_index_renders_the_field_atlas_without_a_client_test() {
  let structures = support.route("/structures")
  let assert Ok(source) = content.load(structures)
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  let assert Ok(document) = page.render(source, structures, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — data structures</title>",
    "content=\"https://watershed.tylerbutler.com/structures/\" property=\"og:url\"",
    "Every structure,",
    "<em>by family.</em>",
    "href=\"/styles/structures-index.css\"",
    "src=\"/scripts/concept-index.js\" type=\"module\"",
    "class=\"cta-quiet\" href=\"/models\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "family") |> list.length |> should.equal(7)
  [
    "counters", "sets", "registers", "maps", "sequences", "coordination",
    "transforms",
  ]
  |> list.each(fn(slug) {
    find(tree, "href", "/structures/" <> slug)
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
