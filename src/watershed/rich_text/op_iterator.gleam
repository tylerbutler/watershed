//// The splitting iterator used by Quill Delta compose and transform.

import gleam/int
import gleam/option.{type Option, None, Some}
import watershed/json_ot.{type JsonValue}
import watershed/rich_text/attribute_map.{type Attributes}
import watershed/rich_text/utf16

pub type Operation {
  InsertText(String, Attributes)
  InsertEmbed(JsonValue, Attributes)
  Delete(Int)
  Retain(Int, Attributes)
}

pub type Kind {
  Insert
  DeleteKind
  RetainKind
}

pub type Iterator {
  Iterator(ops: List(Operation), offset: Int)
}

pub fn new(ops: List(Operation)) -> Iterator {
  Iterator(ops, 0)
}

pub fn has_next(iterator: Iterator) -> Bool {
  let Iterator(ops, _) = iterator
  ops != []
}

pub fn peek_kind(iterator: Iterator) -> Kind {
  let Iterator(ops, _) = iterator
  case ops {
    [Delete(_), ..] -> DeleteKind
    [Retain(_, _), ..] -> RetainKind
    [InsertText(_, _), ..] -> Insert
    [InsertEmbed(_, _), ..] -> Insert
    [] -> RetainKind
  }
}

pub fn peek_length(iterator: Iterator) -> Option(Int) {
  let Iterator(ops, offset) = iterator
  case ops {
    [] -> None
    [op, ..] -> Some(length(op) - offset)
  }
}

pub fn take(iterator: Iterator, requested: Int) -> #(Operation, Iterator) {
  let Iterator(ops, offset) = iterator
  case ops {
    [] -> #(Retain(requested, attribute_map.empty()), iterator)
    [operation, ..rest] -> {
      let available = length(operation) - offset
      let amount = int.min(requested, available)
      let next = case amount == available {
        True -> Iterator(rest, 0)
        False -> Iterator(ops, offset + amount)
      }
      #(split(operation, offset, amount), next)
    }
  }
}

pub fn length(operation: Operation) -> Int {
  case operation {
    InsertText(text, _) -> utf16.length(text)
    InsertEmbed(_, _) -> 1
    Delete(amount) -> amount
    Retain(amount, _) -> amount
  }
}

pub fn attributes(operation: Operation) -> Attributes {
  case operation {
    InsertText(_, attrs) | InsertEmbed(_, attrs) | Retain(_, attrs) -> attrs
    Delete(_) -> attribute_map.empty()
  }
}

fn split(operation: Operation, offset: Int, amount: Int) -> Operation {
  case operation {
    InsertText(text, attrs) -> {
      let assert Ok(part) = utf16.slice(text, offset, amount)
      InsertText(part, attrs)
    }
    InsertEmbed(value, attrs) -> InsertEmbed(value, attrs)
    Delete(_) -> Delete(amount)
    Retain(_, attrs) -> Retain(amount, attrs)
  }
}
