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
      case
        list.contains(
          [
            "description", "layout", "guide_step", "concept", "og_title",
            "og_description", "family",
          ],
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
    "home", route.Home ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/" -> Ok(Home)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The home page metadata is invalid.",
          ))
      }
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
    "concept-index", route.ConceptIndex ->
      case dict.has_key(fields, "guide_step"), route.path {
        True, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "guide_step: A concept index cannot name a guide step.",
          ))
        False, "/foundations" | False, "/component-model" | False, "/runtime" ->
          Ok(ConceptIndex)
        False, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The concept index path is not registered.",
          ))
      }
    "concept-sheet", route.ConceptSheet -> {
      use _ <- result.try(case dict.has_key(fields, "guide_step") {
        True ->
          Error(error.InvalidFrontmatter(
            path,
            "guide_step: A concept sheet cannot name a guide step.",
          ))
        False -> Ok(Nil)
      })
      use slug <- result.try(field(fields, "concept", path))
      case string.starts_with(route.path, "/runtime/") {
        True -> {
          use doc <- result.try(
            runtime.get(slug)
            |> result.replace_error(error.InvalidFrontmatter(
              path,
              "concept: Unknown runtime behavior: " <> slug,
            )),
          )
          case route.path == "/runtime/" <> slug {
            True -> Ok(RuntimeSheet(doc))
            False ->
              Error(error.InvalidFrontmatter(
                path,
                "concept: The path does not match " <> route.path,
              ))
          }
        }
        False -> {
          use doc <- result.try(
            foundations.get(slug)
            |> result.replace_error(error.InvalidFrontmatter(
              path,
              "concept: Unknown foundation: " <> slug,
            )),
          )
          let foundations.Section(path: section_path, ..) =
            foundations.section(slug)
          case route.path == section_path <> "/" <> slug {
            True -> Ok(ConceptSheet(doc))
            False ->
              Error(error.InvalidFrontmatter(
                path,
                "concept: The path does not match " <> route.path,
              ))
          }
        }
      }
    }
    "structure-index", route.StructureIndex ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        route.path
      {
        False, False, "/structures" -> Ok(StructureIndex)
        True, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "guide_step: The field atlas cannot name a guide step.",
          ))
        _, True, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "concept: The field atlas cannot name a concept.",
          ))
        _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The field atlas path must be /structures.",
          ))
      }
    "structure-sheet", route.StructureSheet -> {
      use _ <- result.try(case dict.has_key(fields, "guide_step") {
        True ->
          Error(error.InvalidFrontmatter(
            path,
            "guide_step: A field atlas sheet cannot name a guide step.",
          ))
        False -> Ok(Nil)
      })
      use slug <- result.try(field(fields, "family", path))
      use family <- result.try(
        structures.get(slug)
        |> result.replace_error(error.InvalidFrontmatter(
          path,
          "family: Unknown structure family: " <> slug,
        )),
      )
      case route.path == "/structures/" <> slug {
        True -> Ok(StructureSheet(family))
        False ->
          Error(error.InvalidFrontmatter(
            path,
            "family: The path does not match " <> route.path,
          ))
      }
    }
    "models", route.Models ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/models" -> Ok(Models)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The models page metadata is invalid.",
          ))
      }
    "patterns", route.Patterns ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/patterns" -> Ok(Patterns)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The patterns page metadata is invalid.",
          ))
      }
    "examples", route.Examples ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/examples" -> Ok(Examples)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The examples page metadata is invalid.",
          ))
      }
    "sharedtree", route.SharedTree ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/sharedtree" -> Ok(SharedTree)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The SharedTree page metadata is invalid.",
          ))
      }
    "sudoku", route.Sudoku ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/sudoku" -> Ok(Sudoku)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The Sudoku page metadata is invalid.",
          ))
      }
    "directory", route.Directory ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/directory" -> Ok(Directory)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The directory page metadata is invalid.",
          ))
      }
    "counter-bug", route.CounterBug ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/counter-bug" -> Ok(CounterBug)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The counter bug page metadata is invalid.",
          ))
      }
    "json-ot", route.JsonOt ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/json-ot" -> Ok(JsonOt)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The JSON OT page metadata is invalid.",
          ))
      }
    "mv-register", route.MvRegister ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/mv-register" -> Ok(MvRegister)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The MV register page metadata is invalid.",
          ))
      }
    "rich-text", route.RichText ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/rich-text" -> Ok(RichText)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The rich text page metadata is invalid.",
          ))
      }
    "sequence", route.Sequence ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/sequence" -> Ok(Sequence)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The sequence page metadata is invalid.",
          ))
      }
    "text", route.Text ->
      case
        dict.has_key(fields, "guide_step"),
        dict.has_key(fields, "concept"),
        dict.has_key(fields, "family"),
        route.path
      {
        False, False, False, "/text" -> Ok(Text)
        _, _, _, _ ->
          Error(error.InvalidFrontmatter(
            path,
            "layout: The text page metadata is invalid.",
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
