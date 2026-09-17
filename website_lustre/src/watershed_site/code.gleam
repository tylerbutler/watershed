import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/ssg/djot
import smalto
import smalto/grammar.{type Grammar}
import smalto/languages/gleam as gleam_language
import smalto/languages/javascript
import smalto/token
import watershed_site/snippet

pub fn source_block(
  item: snippet.Snippet,
  source_url: Option(String),
  caption: Option(String),
) -> Element(msg) {
  block(item.code, item.language, Some(item.source_path), source_url, caption)
}

pub fn literal_block(
  source: String,
  language: String,
  source_label: Option(String),
  caption: Option(String),
) -> Element(msg) {
  block(source, language, source_label, None, caption)
}

fn block(
  source: String,
  language: String,
  source_label: Option(String),
  source_url: Option(String),
  caption: Option(String),
) -> Element(msg) {
  let label = case source_label {
    None -> []
    Some(label) -> [
      case source_url {
        None -> html.span([attribute.class("g-file")], [element.text(label)])
        Some(url) ->
          html.a([attribute.class("g-file"), attribute.href(url)], [
            element.text(label),
          ])
      },
    ]
  }
  let caption = case caption {
    None -> []
    Some(caption) -> [
      html.figcaption([attribute.class("annot")], [
        element.text(
          caption
          |> string.replace("%3F", "?")
          |> string.replace("%3D", "="),
        ),
      ]),
    ]
  }

  element.fragment(
    list.append(label, [
      html.figure([attribute.class("g-code")], [
        html.pre([], [
          html.code(
            [
              attribute.class("language-" <> language),
              attribute.attribute("data-language", language),
            ],
            highlighted(language, source),
          ),
        ]),
        ..caption
      ]),
    ]),
  )
}

pub fn highlighted(language: String, source: String) -> List(Element(msg)) {
  case language {
    "gleam" -> highlight(source, gleam_language.grammar())
    "js" | "javascript" -> highlight(source, javascript.grammar())
    _ -> [element.text(source)]
  }
}

fn highlight(source: String, grammar: Grammar) -> List(Element(msg)) {
  let tokens = smalto.to_tokens(source, grammar)
  case tokens |> list.map(token.value) |> string.concat == source {
    True -> list.map(tokens, token_view)
    False -> [element.text(source)]
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
  _revision: String,
) -> djot.Renderer(Element(msg)) {
  let default = djot.default_renderer()
  djot.Renderer(
    ..default,
    codeblock: fn(attributes, language, source) {
      case dict.get(attributes, "data-snippet") {
        Ok(id) -> {
          let assert Ok(snippet) = dict.get(manifest.snippets, id)
          source_block(
            snippet,
            None,
            attribute_value(attributes, "data-caption"),
          )
        }
        Error(Nil) -> {
          let language = option.unwrap(language, "text")
          literal_block(
            source,
            language,
            attribute_value(attributes, "data-source-label"),
            attribute_value(attributes, "data-caption"),
          )
        }
      }
    },
    link: fn(destination, attributes, content) {
      case destination {
        // Jot cannot nest inline code inside strong emphasis.
        Some("strong-code:") -> html.strong([], [html.code([], content)])
        _ -> default.link(destination, attributes, content)
      }
    },
    raw_html: fn(_) { element.text("Raw HTML is not permitted.") },
  )
}

fn attribute_value(
  attributes: dict.Dict(String, String),
  name: String,
) -> Option(String) {
  case dict.get(attributes, name) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}
