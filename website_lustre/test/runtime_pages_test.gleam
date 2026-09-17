import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import lustre/element
import watershed_site/content
import watershed_site/page
import watershed_site/route
import watershed_site/runtime
import watershed_site/snippet

pub fn optimistic_renders_the_runtime_sheet_and_snippet_test() {
  let assert Ok(doc) = runtime.get("optimistic")
  let assert #(Error(Nil), Ok(next)) = runtime.neighbours("optimistic")
  next.slug |> should.equal("reconnect")

  let page_route = route.runtime("optimistic")
  page_route
  |> should.equal(route.Route(
    path: "/runtime/optimistic",
    layout: route.ConceptSheet,
    content_path: "content/runtime/optimistic.djot",
    client_script: None,
    analytics: route.Tinylytics,
  ))
  route.stylesheets(page_route)
  |> should.equal(["/styles/site.css", "/styles/concept-sheet.css"])

  let assert Ok(source) = content.load(page_route)
  source.metadata.kind |> should.equal(content.RuntimeSheet(doc))
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  let assert Ok(document) = page.render(source, page_route, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — optimistic edits</title>",
    "content=\"https://watershed.tylerbutler.com/runtime/optimistic/\" property=\"og:url\"",
    "class=\"r-hero fd-hero\"",
    "Runtime behavior",
    "Every edit is a bet on the order",
    "tools/website-samples/src/website_samples/optimistic_sample.gleam",
    "aria-label=\"Runtime sheets\"",
    "href=\"/runtime/reconnect\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  [
    "/guide_race.js",
    "astro-island",
    "/_astro/",
    "@vite",
    "data-component",
  ]
  |> list.each(fn(absent) {
    let assert False = string.contains(html, absent) as absent
  })
}

pub fn reconnect_renders_the_runtime_sheet_without_a_client_test() {
  let assert Ok(doc) = runtime.get("reconnect")
  let assert #(Ok(previous), Ok(next)) = runtime.neighbours("reconnect")
  previous.slug |> should.equal("optimistic")
  next.slug |> should.equal("redelivery")

  let page_route = route.runtime("reconnect")
  let assert Ok(source) = content.load(page_route)
  source.metadata.kind |> should.equal(content.RuntimeSheet(doc))
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  let assert Ok(document) = page.render(source, page_route, manifest, "test")
  let html = element.to_document_string(document)
  [
    "<title>watershed — reconnect &amp; resync</title>",
    "A dropped link is not a lost document",
    "href=\"/runtime/optimistic\"",
    "href=\"/runtime/redelivery\"",
    "aria-label=\"Runtime sheets\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  ["/guide_race.js", "astro-island", "/_astro/", "@vite", "data-component"]
  |> list.each(fn(absent) {
    let assert False = string.contains(html, absent) as absent
  })
}
