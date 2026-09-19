import fixtures/catalog_contract
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import html_parser
import lustre/element
import support
import watershed_site/content
import watershed_site/page
import watershed_site/route
import watershed_site/runtime
import watershed_site/snippet

pub fn runtime_catalog_matches_contract_test() {
  runtime.all() |> should.equal(catalog_contract.runtime())
}

pub fn runtime_index_renders_the_catalog_without_a_client_test() {
  let runtime_route = support.route("/runtime")
  runtime_route
  |> should.equal(route.Route(
    path: "/runtime",
    layout: route.ConceptIndex,
    content_path: "content/runtime/index.djot",
    client_script: None,
  ))
  route.stylesheets(runtime_route)
  |> should.equal(["/styles/site.css", "/styles/concept-index.css"])
  let assert Ok(source) = content.load(runtime_route)
  source.metadata.kind |> should.equal(content.ConceptIndex)
  let assert Ok(manifest) = snippet.load("src/generated/snippets.json")
  let assert Ok(document) = page.render(source, runtime_route, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — runtime behavior</title>",
    "content=\"https://watershed.tylerbutler.com/runtime/\" property=\"og:url\"",
    "id=\"content\"",
    "aria-labelledby=\"fh-ledger-title\"",
    "How watershed behaves at runtime",
    "Runtime<br><em>behavior.</em>",
    "href=\"/styles/concept-index.css\"",
    "src=\"/scripts/concept-index.js\" type=\"module\"",
    "href=\"/guide/presence\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  let tree = html_parser.as_tree(html)
  find(tree, "class", "fh-item") |> list.length |> should.equal(5)
  ["optimistic", "reconnect", "redelivery", "presence", "p2p"]
  |> list.each(fn(slug) {
    find(tree, "href", "/runtime/" <> slug)
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
