import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element
import watershed_site/content
import watershed_site/guide
import watershed_site/page
import watershed_site/route

pub fn fixture() -> page.GuidePage(Nil) {
  page.GuidePage(
    route.guide_race(),
    content.Metadata(
      "A guide description.",
      route.Guide,
      guide.Race,
      None,
      None,
    ),
    guide.get(guide.Race),
    [element.text("Guide content")],
    element.none(),
  )
}

pub fn document_preserves_metadata_and_navigation_test() {
  let html = page.view(fixture()) |> element.to_document_string
  [
    "<!doctype html>", "<html lang=\"en\">",
    "<title>watershed — try two edits at once</title>",
    "content=\"A guide description.\" name=\"description\"",
    "content=\"watershed — try two edits at once\" property=\"og:title\"",
    "content=\"A guide description.\" property=\"og:description\"",
    "content=\"website\" property=\"og:type\"",
    "content=\"https://watershed.tylerbutler.com/guide/race\" property=\"og:url\"",
    "content=\"https://watershed.tylerbutler.com/og.png\" property=\"og:image\"",
    "content=\"2400\" property=\"og:image:width\"",
    "content=\"1260\" property=\"og:image:height\"", "property=\"og:image:alt\"",
    "content=\"summary_large_image\" name=\"twitter:card\"",
    "href=\"/favicon.svg\"", "href=\"/styles/site.css\"",
    "href=\"/styles/guide-race.css\"",
    "defer src=\"https://tinylytics.app/embed/uhk_zvSq2fBb_T2hTaLx/min.js?hits&amp;events&amp;beacon\"",
    "src=\"/watershed_site_client_guide_race.mjs\" type=\"module\"",
    "Sheet index", "Adjoining sheets", "Field atlas",
    "aria-current=\"page\" class=\"si-link annot\" href=\"/guide\"",
    "href=\"/guide/notes\"", "href=\"/guide/votes\"", "Step 03",
    "Packages and protocol boundaries", "Guide content",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  ["canonical", "/_astro/", "astro-island", "@vite", "client:load"]
  |> list.each(fn(absent) { string.contains(html, absent) |> should.be_false() })
}

pub fn analytics_and_client_entry_follow_route_policy_test() {
  let original = fixture()
  let without_scripts =
    page.GuidePage(
      ..original,
      route: route.Route(
        ..original.route,
        analytics: route.NoAnalytics,
        client_script: None,
      ),
    )
  let html = page.view(without_scripts) |> element.to_document_string
  string.contains(html, "tinylytics") |> should.be_false()
  string.contains(html, "type=\"module\"") |> should.be_false()
}

pub fn social_overrides_do_not_change_document_title_test() {
  let original = fixture()
  let html =
    page.view(
      page.GuidePage(
        ..original,
        metadata: content.Metadata(
          ..original.metadata,
          og_title: Some("Social"),
          og_description: Some("Social description"),
        ),
      ),
    )
    |> element.to_document_string
  string.contains(html, "<title>watershed — try two edits at once</title>")
  |> should.be_true()
  string.contains(html, "content=\"Social\" property=\"og:title\"")
  |> should.be_true()
  string.contains(
    html,
    "content=\"Social description\" property=\"og:description\"",
  )
  |> should.be_true()
}
