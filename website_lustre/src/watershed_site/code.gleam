import gleam/dict
import gleam/list
import gleam/option
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/ssg/djot
import smalto
import smalto/languages/gleam as gleam_language
import smalto/languages/javascript
import smalto/token
import watershed_site/snippet

pub fn block(snippet: snippet.Snippet, revision: String) -> Element(msg) {
  html.div([attribute.class("snippet-block")], [
    html.div([attribute.class("snippet-label")], [
      element.text(snippet.language),
      html.a(
        [
          attribute.class("snippet-source"),
          attribute.href(snippet.source_url(snippet, revision)),
        ],
        [element.text(snippet.source_path)],
      ),
    ]),
    html.pre([], [
      html.code(
        [
          attribute.class("language-" <> snippet.language),
          attribute.attribute("data-language", snippet.language),
        ],
        highlighted(snippet.language, snippet.code),
      ),
    ]),
  ])
}

pub fn highlighted(language: String, source: String) -> List(Element(msg)) {
  case language {
    "gleam" ->
      smalto.to_tokens(source, gleam_language.grammar()) |> list.map(token_view)
    "js" | "javascript" ->
      smalto.to_tokens(source, javascript.grammar()) |> list.map(token_view)
    _ -> [element.text(source)]
  }
}

fn token_view(item: token.Token) -> Element(msg) {
  case item {
    token.Whitespace(value) | token.Other(value) -> element.text(value)
    other ->
      html.span([attribute.class("smalto-" <> token.name(other))], [
        element.text(token.value(other)),
      ])
  }
}

pub fn renderer(
  manifest: snippet.Manifest,
  revision: String,
) -> djot.Renderer(Element(msg)) {
  djot.Renderer(
    ..djot.default_renderer(),
    codeblock: fn(attributes, language, source) {
      case dict.get(attributes, "data-snippet") {
        Ok(id) -> {
          let assert Ok(snippet) = dict.get(manifest.snippets, id)
          block(snippet, revision)
        }
        Error(Nil) -> {
          let language = option.unwrap(language, "text")
          html.pre([], [
            html.code(
              [
                attribute.attribute("data-language", language),
                attribute.class("language-" <> language),
              ],
              highlighted(language, source),
            ),
          ])
        }
      }
    },
    raw_html: fn(_) { element.text("Raw HTML is not permitted.") },
  )
}
