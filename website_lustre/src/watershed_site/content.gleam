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
import watershed_site/foundations
import watershed_site/guide
import watershed_site/practice
import watershed_site/route
import watershed_site/runtime
import watershed_site/snippet
import watershed_site/structures
import watershed_site/view/concept_index
import watershed_site/view/guide_index
import watershed_site/view/runtime_index
import watershed_site/view/runtime_sheet
import watershed_site/view/structures_index

pub type PageKind {
  Home
  GuideStep(guide.Slug)
  GuideIndex
  ConceptIndex
  ConceptSheet(foundations.Doc)
  RuntimeSheet(runtime.Doc)
  StructureIndex
  StructureSheet(structures.Family)
  Models
  Patterns
  Examples
  SharedTree
  Sudoku
  Directory
  CounterBug
  JsonOt
  MvRegister
  RichText
  Sequence
  Text
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
      case list.contains(["description", "og_title", "og_description"], name) {
        True -> Ok(Nil)
        False ->
          Error(error.InvalidFrontmatter(path, "Unknown field: " <> name))
      }
    }),
  )
  use description <- result.try(field(fields, "description", path))
  use kind <- result.try(route_kind(route, path))
  use og_title <- result.try(optional_field(fields, "og_title", path))
  use og_description <- result.try(optional_field(
    fields,
    "og_description",
    path,
  ))
  Ok(Metadata(description, kind, og_title, og_description))
}

fn route_kind(
  route: route.Route,
  path: String,
) -> Result(PageKind, BuildError) {
  let invalid = error.InvalidFrontmatter(path, "The route is not registered.")
  case route.layout {
    route.Home -> Ok(Home)
    route.Guide ->
      guide.all()
      |> list.find(fn(step) { guide.path(step.slug) == route.path })
      |> result.map(fn(step) { GuideStep(step.slug) })
      |> result.replace_error(invalid)
    route.GuideIndex -> Ok(GuideIndex)
    route.ConceptIndex -> Ok(ConceptIndex)
    route.ConceptSheet -> {
      use slug <- result.try(route_slug(route.path, invalid))
      case string.starts_with(route.path, "/runtime/") {
        True ->
          runtime.get(slug)
          |> result.map(RuntimeSheet)
          |> result.replace_error(invalid)
        False ->
          foundations.get(slug)
          |> result.map(ConceptSheet)
          |> result.replace_error(invalid)
      }
    }
    route.StructureIndex -> Ok(StructureIndex)
    route.StructureSheet -> {
      use slug <- result.try(route_slug(route.path, invalid))
      structures.get(slug)
      |> result.map(StructureSheet)
      |> result.replace_error(invalid)
    }
    route.Models -> Ok(Models)
    route.Patterns -> Ok(Patterns)
    route.Examples -> Ok(Examples)
    route.SharedTree -> Ok(SharedTree)
    route.Sudoku -> Ok(Sudoku)
    route.Directory -> Ok(Directory)
    route.CounterBug -> Ok(CounterBug)
    route.JsonOt -> Ok(JsonOt)
    route.MvRegister -> Ok(MvRegister)
    route.RichText -> Ok(RichText)
    route.Sequence -> Ok(Sequence)
    route.Text -> Ok(Text)
  }
}

fn route_slug(path: String, error: BuildError) -> Result(String, BuildError) {
  string.split(path, "/")
  |> list.last
  |> result.replace_error(error)
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
      jot.Codeblock(attributes, _, _) -> {
        use _ <- result.try(validate_snippet_attributes(attributes, path))
        case dict.get(attributes, "data-snippet") {
          Error(Nil) -> Ok(Nil)
          Ok(id) -> snippet.get(manifest, path, id) |> result.replace(Nil)
        }
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

fn validate_snippet_attributes(
  attributes: Dict(String, String),
  path: String,
) -> Result(Nil, BuildError) {
  use _ <- result.try(
    case
      dict.has_key(attributes, "data-snippet"),
      dict.has_key(attributes, "data-source-label")
    {
      True, True ->
        Error(error.InvalidContent(
          path,
          "data-source-label cannot override a generated data-snippet.",
        ))
      _, _ -> Ok(Nil)
    },
  )
  ["data-snippet", "data-source-label", "data-caption"]
  |> list.try_each(fn(name) {
    case dict.get(attributes, name) {
      Ok(value) ->
        case string.trim(value) {
          "" -> Error(error.InvalidContent(path, name <> " cannot be empty."))
          _ -> Ok(Nil)
        }
      Error(Nil) -> Ok(Nil)
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
          Error(Nil) | Ok("guide-race") | Ok("sharedtree-gaps") -> Ok(Nil)
          Ok("field-note-ref") ->
            case dict.get(attributes, "data-practice") {
              Error(Nil) ->
                Error(error.InvalidContent(
                  path,
                  "field-note-ref requires data-practice.",
                ))
              Ok(id) ->
                case practice.get(id) {
                  Ok(_) -> Ok(Nil)
                  Error(Nil) -> Error(error.UnknownPractice(path, id))
                }
            }
          Ok(name) ->
            case
              guide_index.component(name),
              concept_index.component(name),
              runtime_index.component(name),
              runtime_sheet.component(name),
              structures_index.component(name)
            {
              Ok(_), _, _, _, _
              | _, Ok(_), _, _, _
              | _, _, Ok(_), _, _
              | _, _, _, Ok(_), _
              | _, _, _, _, Ok(_)
              -> Ok(Nil)
              Error(Nil), Error(Nil), Error(Nil), Error(Nil), Error(Nil) ->
                Error(error.UnknownComponent(path, name))
            }
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
