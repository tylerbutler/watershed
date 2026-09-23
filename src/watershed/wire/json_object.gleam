//// Read object members in JavaScript property order on both targets.
//// Retain source order except for array-index keys, which precede other keys.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

pub fn members(raw: String) -> Result(List(#(String, String)), String) {
  use decoded <- result.try(
    json.parse(raw, decode.dict(decode.string, decode.dynamic))
    |> result.map_error(fn(_) { "expected a JSON object" }),
  )
  let body = raw |> string.trim |> string.drop_start(1) |> string.drop_end(1)
  use entries <- result.try(case string.trim(body) {
    "" -> Ok([])
    _ ->
      list.try_map(split(body, ","), fn(member) {
        case split(member, ":") {
          [key, value] -> {
            use key <- result.try(
              json.parse(string.trim(key), decode.string)
              |> result.map_error(fn(_) { "invalid JSON object key" }),
            )
            Ok(#(key, string.trim(value)))
          }
          _ -> Error("invalid JSON object member")
        }
      })
  })
  case list.length(entries) == dict.size(decoded) {
    True -> Ok(javascript_order(entries))
    False -> Error("duplicate JSON object key")
  }
}

pub fn javascript_order(
  entries: List(#(String, value)),
) -> List(#(String, value)) {
  entries
  |> list.index_map(fn(entry, position) { #(entry, position) })
  |> list.sort(fn(left, right) {
    case array_index(left.0.0), array_index(right.0.0) {
      Some(a), Some(b) -> int.compare(a, b)
      Some(_), None -> order.Lt
      None, Some(_) -> order.Gt
      None, None -> int.compare(left.1, right.1)
    }
  })
  |> list.map(fn(entry) { entry.0 })
}

fn array_index(key: String) -> Option(Int) {
  case int.parse(key) {
    Ok(index) if index >= 0 && index < 4_294_967_295 ->
      case int.to_string(index) == key {
        True -> Some(index)
        False -> None
      }
    _ -> None
  }
}

fn split(raw: String, separator: String) -> List(String) {
  let characters =
    raw
    |> string.to_utf_codepoints
    |> list.map(fn(codepoint) { string.from_utf_codepoints([codepoint]) })
  split_loop(characters, separator, 0, False, False, [], [])
}

fn split_loop(
  characters: List(String),
  separator: String,
  depth: Int,
  quoted: Bool,
  escaped: Bool,
  current: List(String),
  parts: List(String),
) -> List(String) {
  case characters {
    [] -> list.reverse([string.concat(list.reverse(current)), ..parts])
    [character, ..rest] ->
      case quoted, escaped, character {
        True, True, _ ->
          split_loop(
            rest,
            separator,
            depth,
            True,
            False,
            [character, ..current],
            parts,
          )
        True, False, "\\" ->
          split_loop(
            rest,
            separator,
            depth,
            True,
            True,
            [character, ..current],
            parts,
          )
        _, False, "\"" ->
          split_loop(
            rest,
            separator,
            depth,
            !quoted,
            False,
            [character, ..current],
            parts,
          )
        False, _, "{" | False, _, "[" ->
          split_loop(
            rest,
            separator,
            depth + 1,
            False,
            False,
            [character, ..current],
            parts,
          )
        False, _, "}" | False, _, "]" ->
          split_loop(
            rest,
            separator,
            depth - 1,
            False,
            False,
            [character, ..current],
            parts,
          )
        False, _, _ if depth == 0 && character == separator ->
          split_loop(rest, separator, depth, False, False, [], [
            string.concat(list.reverse(current)),
            ..parts
          ])
        _, _, _ ->
          split_loop(
            rest,
            separator,
            depth,
            quoted,
            False,
            [character, ..current],
            parts,
          )
      }
  }
}
