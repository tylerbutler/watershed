//// Extracts named declarations without resolving imports or running source.

import code_map/model
import code_map/symbols
import glance
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glexer
import glexer/token

pub type Kind {
  Function
  Type
  Constant
}

pub type Declaration {
  Declaration(
    name: String,
    container: List(String),
    kind: Kind,
    publicity: glance.Publicity,
    location: glance.Span,
    signature_end: Int,
    target: Option(String),
  )
}

pub fn parse(source: String) -> Result(List(Declaration), glance.Error) {
  use module <- result.try(glance.module(source))
  let functions =
    list.flat_map(module.functions, fn(definition) {
      let f = definition.definition
      let target = target_of(definition.attributes)
      [
        Declaration(
          f.name,
          [],
          Function,
          f.publicity,
          f.location,
          f.location.end,
          target,
        ),
        ..statements(f.body, [f.name], target)
      ]
    })
  let types =
    list.map(module.custom_types, fn(d) {
      let t = d.definition
      Declaration(
        t.name,
        [],
        Type,
        t.publicity,
        t.location,
        t.location.end,
        target_of(d.attributes),
      )
    })
  let aliases =
    list.map(module.type_aliases, fn(d) {
      let t = d.definition
      Declaration(
        t.name,
        [],
        Type,
        t.publicity,
        t.location,
        t.location.end,
        target_of(d.attributes),
      )
    })
  let constants =
    list.map(module.constants, fn(d) {
      let c = d.definition
      let location = glance.Span(c.location.start, expression_end(c.value))
      Declaration(
        c.name,
        [],
        Constant,
        c.publicity,
        location,
        location.end,
        target_of(d.attributes),
      )
    })
  let tokens =
    glexer.new(source)
    |> glexer.discard_comments
    |> glexer.discard_whitespace
    |> glexer.lex
  list.flatten([functions, types, aliases, constants])
  |> list.map(fn(d) { Declaration(..d, signature_end: header_end(d, tokens)) })
  |> list.sort(fn(a, b) { int.compare(a.location.start, b.location.start) })
  |> Ok
}

fn target_of(attributes: List(glance.Attribute)) -> Option(String) {
  list.find_map(attributes, fn(attribute) {
    case attribute {
      glance.Attribute("target", [glance.Variable(_, name)]) -> Ok(name)
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

fn header_end(
  d: Declaration,
  tokens: List(#(token.Token, glexer.Position)),
) -> Int {
  tokens
  |> list.find_map(fn(pair) {
    let #(t, position) = pair
    case
      position.byte_offset >= d.location.start
      && position.byte_offset < d.signature_end
    {
      False -> Error(Nil)
      True ->
        case d.kind, t {
          Constant, token.Equal -> Ok(position.byte_offset)
          Type, token.LeftBrace -> Ok(position.byte_offset)
          Function, token.LeftBrace -> Ok(position.byte_offset)
          _, _ -> Error(Nil)
        }
    }
  })
  |> result.unwrap(d.signature_end)
}

// Glance adds UTF-8 lengths to lexer offsets for terminal string literals.
// On JavaScript those lexer offsets are UTF-16. Correct this at the boundary.
fn expression_end(value: glance.Expression) -> Int {
  case value {
    glance.String(location, text) ->
      location.start
      + 2
      + list.fold(string.to_utf_codepoints(text), 0, fn(total, cp) {
        total
        + case string.utf_codepoint_to_int(cp) > 65_535 {
          True -> 2
          False -> 1
        }
      })
    glance.BinaryOperator(_, _, _, right) -> expression_end(right)
    _ -> value.location.end
  }
}

fn statements(
  items: List(glance.Statement),
  scope: List(String),
  target: Option(String),
) -> List(Declaration) {
  list.flat_map(items, fn(item) {
    case item {
      glance.Assignment(location, _, pattern, _, value) -> {
        case pattern, value {
          glance.PatternVariable(_, name), glance.Fn(..)
          | glance.PatternVariable(_, name), glance.FnCapture(..)
          -> {
            let nested = list.append(scope, [name])
            let signature_end = case value {
              glance.FnCapture(..) -> pattern.location.end
              _ -> location.end
            }
            [
              Declaration(
                name,
                scope,
                Function,
                glance.Private,
                location,
                signature_end,
                target,
              ),
              ..expression(value, nested, target)
            ]
          }
          _, _ -> expression(value, scope, target)
        }
      }
      glance.Use(_, _, value) | glance.Expression(value) ->
        expression(value, scope, target)
      glance.Assert(_, value, message) ->
        list.append(
          expression(value, scope, target),
          optional(message, scope, target),
        )
    }
  })
}

fn optional(
  value: Option(glance.Expression),
  scope: List(String),
  target: Option(String),
) -> List(Declaration) {
  case value {
    Some(value) -> expression(value, scope, target)
    None -> []
  }
}

fn field(value: glance.Field(glance.Expression)) -> glance.Expression {
  case value {
    glance.LabelledField(_, _, value) | glance.UnlabelledField(value) -> value
    glance.ShorthandField(name, location) -> glance.Variable(location, name)
  }
}

fn expression(
  value: glance.Expression,
  scope: List(String),
  target: Option(String),
) -> List(Declaration) {
  let walk = fn(value) { expression(value, scope, target) }
  case value {
    glance.Block(_, body) | glance.Fn(_, _, _, body) ->
      statements(body, scope, target)
    glance.NegateInt(_, value)
    | glance.NegateBool(_, value)
    | glance.FieldAccess(_, value, _)
    | glance.TupleIndex(_, value, _) -> walk(value)
    glance.Panic(_, message) | glance.Todo(_, message) ->
      optional(message, scope, target)
    glance.Tuple(_, values) -> list.flat_map(values, walk)
    glance.List(_, values, rest) ->
      list.append(list.flat_map(values, walk), optional(rest, scope, target))
    glance.Call(_, function, arguments) ->
      list.flat_map([function, ..list.map(arguments, field)], walk)
    glance.FnCapture(_, _, function, before, after) ->
      list.flat_map(
        [function, ..list.map(list.append(before, after), field)],
        walk,
      )
    glance.BinaryOperator(_, _, left, right) ->
      list.append(walk(left), walk(right))
    glance.Echo(_, value, message) ->
      list.append(
        optional(value, scope, target),
        optional(message, scope, target),
      )
    glance.Case(_, subjects, clauses) ->
      list.append(
        list.flat_map(subjects, walk),
        list.flat_map(clauses, fn(clause) {
          list.append(optional(clause.guard, scope, target), walk(clause.body))
        }),
      )
    glance.RecordUpdate(_, _, _, record, fields) ->
      list.append(
        walk(record),
        list.flat_map(fields, fn(f) { optional(f.item, scope, target) }),
      )
    glance.BitString(_, segments) ->
      list.flat_map(segments, fn(segment) {
        let #(value, options) = segment
        list.append(
          walk(value),
          list.flat_map(options, fn(option) {
            case option {
              glance.SizeValueOption(value) -> walk(value)
              _ -> []
            }
          }),
        )
      })
    glance.Int(..)
    | glance.Float(..)
    | glance.String(..)
    | glance.Variable(..) -> []
  }
}

/// Extracts symbols with original-source positions.
pub fn extract(
  path: String,
  source: String,
) -> Result(model.ParseResult, model.Error) {
  let #(declarations, diagnostics) = case parse(source) {
    Ok(declarations) -> #(declarations, [])
    Error(error) -> {
      let #(message, offset) = case error {
        glance.UnexpectedEndOfInput -> #("Unexpected end of input", -1)
        glance.UnexpectedToken(t, position) -> #(
          "Unexpected token: " <> token.to_source(t),
          position.byte_offset,
        )
      }
      let range = case offset < 0 {
        True -> None
        False -> Some(symbols.range_at(source, offset, offset))
      }
      #([], [model.Diagnostic(path, message, range)])
    }
  }
  use raw <- result.try(
    list.try_map(declarations, fn(d) {
      use target <- result.try(case d.target {
        None -> Ok(None)
        Some("erlang") -> Ok(Some(model.ErlangTarget))
        Some("javascript") -> Ok(Some(model.JavaScriptTarget))
        Some(_) -> Error(model.ParserError("invalid Gleam target"))
      })
      let public = d.publicity == glance.Public
      Ok(symbols.from_span(
        source,
        d.name,
        d.container,
        case d.kind {
          Function -> model.Function
          Type -> model.Type
          Constant -> model.Constant
        },
        case public {
          True -> model.Public
          False -> model.Private
        },
        public,
        target,
        d.location.start,
        d.location.end,
        d.signature_end,
      ))
    }),
  )
  symbols.normalize_parse(path, raw, diagnostics, [])
}
