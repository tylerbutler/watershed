//// Canonical, JSON-valued Quill attribute maps.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import watershed/json_ot.{type JsonValue, VNull}

pub opaque type Attributes {
  Attributes(List(#(String, JsonValue)))
}

pub fn empty() -> Attributes {
  Attributes([])
}

pub fn from_list(entries: List(#(String, JsonValue))) -> Attributes {
  Attributes(entries |> list.fold([], put))
}

pub fn to_list(attributes: Attributes) -> List(#(String, JsonValue)) {
  let Attributes(entries) = attributes
  entries
}

pub fn is_empty(attributes: Attributes) -> Bool {
  let Attributes(entries) = attributes
  entries == []
}

pub fn get(attributes: Attributes, key: String) -> Option(JsonValue) {
  let Attributes(entries) = attributes
  case list.key_find(entries, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

pub fn without_nulls(attributes: Attributes) -> Attributes {
  let Attributes(entries) = attributes
  Attributes(list.filter(entries, fn(entry) { entry.1 != VNull }))
}

/// Quill AttributeMap.compose. Nulls are retained only for retain patches.
pub fn compose(a: Attributes, b: Attributes, keep_null: Bool) -> Attributes {
  let Attributes(left) = a
  let Attributes(right) = b
  let seeded = case keep_null {
    True -> right
    False -> list.filter(right, fn(entry) { entry.1 != VNull })
  }
  Attributes(
    left
    |> list.fold(seeded, fn(acc, entry) {
      case get(Attributes(right), entry.0) {
        None -> put(acc, entry)
        Some(_) -> acc
      }
    }),
  )
}

/// Attribute changes which restore `base` after applying `patch`.
pub fn invert(patch: Attributes, base: Attributes) -> Attributes {
  let Attributes(patch_entries) = patch
  let Attributes(base_entries) = base
  let restored =
    base_entries
    |> list.fold([], fn(acc, entry) {
      case get(Attributes(patch_entries), entry.0) {
        Some(value) if value != entry.1 -> put(acc, entry)
        _ -> acc
      }
    })
  Attributes(
    patch_entries
    |> list.fold(restored, fn(acc, entry) {
      case get(Attributes(base_entries), entry.0) {
        None -> put(acc, #(entry.0, VNull))
        _ -> acc
      }
    }),
  )
}

/// Transform `other` attributes through `base`, using Quill priority rules.
pub fn transform(
  base: Attributes,
  other: Attributes,
  priority: Bool,
) -> Attributes {
  case priority {
    False -> other
    True -> {
      let Attributes(entries) = other
      Attributes(
        entries
        |> list.fold([], fn(acc, entry) {
          case get(base, entry.0) {
            None -> put(acc, entry)
            Some(_) -> acc
          }
        }),
      )
    }
  }
}

fn put(
  entries: List(#(String, JsonValue)),
  entry: #(String, JsonValue),
) -> List(#(String, JsonValue)) {
  let without = list.filter(entries, fn(current) { current.0 != entry.0 })
  insert_sorted(without, entry)
}

fn insert_sorted(
  entries: List(#(String, JsonValue)),
  entry: #(String, JsonValue),
) -> List(#(String, JsonValue)) {
  case entries {
    [] -> [entry]
    [first, ..rest] ->
      case string.compare(entry.0, first.0) {
        order.Lt -> [entry, first, ..rest]
        _ -> [first, ..insert_sorted(rest, entry)]
      }
  }
}
