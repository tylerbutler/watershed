import gleam/list
import gleam/string
import lustre/element
import watershed_site/content
import watershed_site/page
import watershed_site/route
import watershed_site/snippet

pub fn foundations_pages_render_shared_layout_and_snippets_test() {
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  [
    #(
      "/foundations/schema",
      "Schemas and fields",
      "src/watershed/schema.gleam",
      "/foundations/topology",
    ),
    #(
      "/foundations/topology",
      "Documents and handles",
      "src/watershed.gleam",
      "/foundations/lifecycle",
    ),
    #(
      "/foundations/lifecycle",
      "Starting a document",
      "watershed_lustre/src/watershed_lustre.gleam",
      "/guide",
    ),
  ]
  |> list.each(fn(expected) {
    let assert Ok(item) =
      route.all()
      |> list.find(fn(item) { item.path == expected.0 })
    let assert Ok(source) = content.load(item)
    let assert Ok(document) = page.render(source, item, manifest, "test")
    let html = element.to_document_string(document)
    [
      "<title>watershed — " <> string.lowercase(expected.1) <> "</title>",
      "class=\"fd-hero\"",
      "class=\"doc-body\"",
      "class=\"fd-pager\"",
      "aria-label=\"Foundations sheets\"",
      "href=\"/styles/concept-sheet.css\"",
      "data-language=\"gleam\"",
      expected.2,
      "href=\"" <> expected.3 <> "\"",
    ]
    |> list.each(fn(value) {
      let assert True = string.contains(html, value) as value
    })
    ["astro-island", "/_astro/", "data-component", "canonical"]
    |> list.each(fn(absent) {
      let assert False = string.contains(html, absent) as absent
    })
  })
}
