import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jot
import lustre/ssg/djot
import simplifile
import tom
import watershed_site/error.{type BuildError}
import watershed_site/guide
import watershed_site/route
import watershed_site/snippet
import watershed_site/view/guide_index

pub type PageKind {
  GuideStep(guide.Slug)
  GuideIndex
}

pub type Metadata {
  Metadata(
    description: String,
    kind: PageKind,
    og_title: Option(String),
    og_description: Option(String),
  )
}

pub type Source {
  Source(path: String, metadata: Metadata, body: String, document: jot.Document)
}

pub fn load(route: route.Route) -> Result(Source, BuildError) {
  use source <- result.try(
    simplifile.read(route.content_path)
    |> result.map_error(fn(reason) {
      error.CannotRead(route.content_path, string.inspect(reason))
    }),
  )
  parse(source, route.content_path, route)
}

pub fn parse(
  source: String,
  path: String,
  route: route.Route,
) -> Result(Source, BuildError) {
  use fields <- result.try(
    djot.metadata(source)
    |> result.map_error(fn(reason) {
      error.InvalidFrontmatter(path, string.inspect(reason))
    }),
  )
  use metadata <- result.try(decode_metadata(fields, path, route))
  let body = djot.content(source)
  let document = jot.parse(body)
  use _ <- result.try(validate(document, path))
  Ok(Source(path, metadata, body, document))
}

fn field(
  fields: Dict(String, tom.Toml),
  name: String,
  path: String,
) -> Result(String, BuildError) {
  tom.get_string(fields, [name])
  |> result.map_error(fn(reason) {
    error.InvalidFrontmatter(path, name <> ": " <> string.inspect(reason))
  })
}

fn optional_field(
  fields: Dict(String, tom.Toml),
  name: String,
  path: String,
) -> Result(Option(String), BuildError) {
  case dict.has_key(fields, name) {
    False -> Ok(None)
    True -> field(fields, name, path) |> result.map(Some)
  }
}

fn decode_metadata(
  fields: Dict(String, tom.Toml),
  path: String,
  route: route.Route,
) -> Result(Metadata, BuildError) {
  use _ <- result.try(
    list.try_each(dict.keys(fields), fn(name) {
      case
        list.contains(
          ["description", "layout", "guide_step", "og_title", "og_description"],
          name,
        )
      {
        True -> Ok(Nil)
        False ->
          Error(error.InvalidFrontmatter(path, "Unknown field: " <> name))
      }
    }),
  )
  use description <- result.try(field(fields, "description", path))
  use layout <- result.try(field(fields, "layout", path))
  use kind <- result.try(case layout, route.layout {
    "guide", route.Guide -> decode_step(fields, path, route)
    "guide-index", route.GuideIndex ->
      case dict.has_key(fields, "guide_step"), route.path {
        True, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "guide_step: The guide index cannot name a step.",
          ))
        False, "/guide" -> Ok(GuideIndex)
        False, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The guide index path must be /guide.",
          ))
      }
    _, _ ->
      Error(error.InvalidFrontmatter(
        path,
        "layout: The layout does not match the route.",
      ))
  })
  use og_title <- result.try(optional_field(fields, "og_title", path))
  use og_description <- result.try(optional_field(
    fields,
    "og_description",
    path,
  ))
  Ok(Metadata(description, kind, og_title, og_description))
}

fn decode_step(
  fields: Dict(String, tom.Toml),
  path: String,
  route: route.Route,
) -> Result(PageKind, BuildError) {
  use slug <- result.try(field(fields, "guide_step", path))
  use step <- result.try(
    guide.from_string(slug)
    |> result.replace_error(error.InvalidFrontmatter(
      path,
      "guide_step: Unknown step: " <> slug,
    )),
  )
  use _ <- result.try(case guide.path(step) == route.path {
    True -> Ok(Nil)
    False ->
      Error(error.InvalidFrontmatter(
        path,
        "guide_step: The path does not match " <> route.path,
      ))
  })
  Ok(GuideStep(step))
}

pub fn validate(
  document: jot.Document,
  path: String,
) -> Result(Nil, BuildError) {
  use _ <- result.try(validate_blocks(document.content, path))
  document.footnotes |> dict.values |> list.try_each(validate_blocks(_, path))
}

pub fn validate_snippets(
  document: jot.Document,
  manifest: snippet.Manifest,
  path: String,
) -> Result(Nil, BuildError) {
  use _ <- result.try(snippet_blocks(document.content, manifest, path))
  document.footnotes
  |> dict.values
  |> list.try_each(snippet_blocks(_, manifest, path))
}

fn snippet_blocks(
  blocks: List(jot.Container),
  manifest: snippet.Manifest,
  path: String,
) -> Result(Nil, BuildError) {
  list.try_each(blocks, fn(block) {
    case block {
      jot.Codeblock(attributes, _, _) ->
        case dict.get(attributes, "data-snippet") {
          Error(Nil) -> Ok(Nil)
          Ok(id) -> snippet.get(manifest, path, id) |> result.replace(Nil)
        }
      jot.Div(_, children) | jot.BlockQuote(_, children) ->
        snippet_blocks(children, manifest, path)
      jot.BulletList(_, _, items) ->
        list.try_each(items, snippet_blocks(_, manifest, path))
      jot.RawBlock(_) -> Error(error.RawHtml(path))
      jot.Paragraph(_, _) | jot.Heading(_, _, _) | jot.ThematicBreak -> Ok(Nil)
    }
  })
}

fn validate_blocks(
  blocks: List(jot.Container),
  path: String,
) -> Result(Nil, BuildError) {
  list.try_each(blocks, fn(block) {
    case block {
      jot.RawBlock(_) -> Error(error.RawHtml(path))
      jot.Div(attributes, children) -> {
        use _ <- result.try(case dict.get(attributes, "data-component") {
          Error(Nil) | Ok("guide-race") -> Ok(Nil)
          Ok(name) ->
            guide_index.component(name)
            |> result.replace(Nil)
            |> result.replace_error(error.UnknownComponent(path, name))
        })
        validate_blocks(children, path)
      }
      jot.BlockQuote(_, children) -> validate_blocks(children, path)
      jot.BulletList(_, _, items) ->
        list.try_each(items, validate_blocks(_, path))
      jot.Paragraph(_, children) | jot.Heading(_, _, children) ->
        validate_inlines(children)
      jot.ThematicBreak | jot.Codeblock(_, _, _) -> Ok(Nil)
    }
  })
}

fn validate_inlines(inlines: List(jot.Inline)) -> Result(Nil, BuildError) {
  list.try_each(inlines, fn(inline) {
    case inline {
      jot.Link(_, children, _)
      | jot.Image(_, children, _)
      | jot.Span(_, children)
      | jot.Emphasis(children)
      | jot.Strong(children) -> validate_inlines(children)
      jot.Linebreak
      | jot.NonBreakingSpace
      | jot.Text(_)
      | jot.Footnote(_)
      | jot.Code(_)
      | jot.MathInline(_)
      | jot.MathDisplay(_) -> Ok(Nil)
    }
  })
}
