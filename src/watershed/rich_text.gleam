//// Pure, checked port of rich-text@4.1.0 / quill-delta@4.2.1.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNull, VNumber, VObject, VString,
}
import watershed/rich_text/attribute_map.{type Attributes}
import watershed/rich_text/op_iterator.{
  type Iterator, type Operation, Delete, DeleteKind, Insert, InsertEmbed,
  InsertText, Retain, RetainKind,
}
import watershed/rich_text/utf16

pub opaque type Document {
  Document(List(Operation))
}

pub opaque type Delta {
  Delta(List(Operation))
}

pub type Side {
  Left
  Right
}

pub type Selection {
  Selection(index: Int, length: Int)
}

pub type Error {
  Malformed(component: String, reason: String)
  InvalidApply(reason: String)
  InvalidBoundary(offset: Int)
}

pub fn empty_document() -> Document {
  Document([])
}

pub fn empty_delta() -> Delta {
  Delta([])
}

pub fn attributes(entries: List(#(String, JsonValue))) -> Attributes {
  attribute_map.from_list(entries)
}

pub fn document_insert_text(
  document: Document,
  text: String,
  attributes: Attributes,
) -> Result(Document, Error) {
  case validate_text(text) {
    Ok(_) ->
      document_operations(
        Document(push(
          operations_document(document),
          InsertText(text, attribute_map.without_nulls(attributes)),
        )),
      )
    Error(error) -> Error(error)
  }
}

pub fn document_insert_embed(
  document: Document,
  embed: JsonValue,
  attributes: Attributes,
) -> Result(Document, Error) {
  case embed == VNull {
    True -> Error(Malformed("insert", "null embeds are not valid"))
    False ->
      document_operations(
        Document(push(
          operations_document(document),
          InsertEmbed(embed, attribute_map.without_nulls(attributes)),
        )),
      )
  }
}

pub fn delta_insert_text(
  delta: Delta,
  text: String,
  attributes: Attributes,
) -> Result(Delta, Error) {
  case validate_text(text) {
    Ok(_) ->
      Ok(
        Delta(push(
          operations_delta(delta),
          InsertText(text, attribute_map.without_nulls(attributes)),
        )),
      )
    Error(error) -> Error(error)
  }
}

pub fn delta_insert_embed(
  delta: Delta,
  embed: JsonValue,
  attributes: Attributes,
) -> Result(Delta, Error) {
  case embed == VNull {
    True -> Error(Malformed("insert", "null embeds are not valid"))
    False ->
      Ok(
        Delta(push(
          operations_delta(delta),
          InsertEmbed(embed, attribute_map.without_nulls(attributes)),
        )),
      )
  }
}

pub fn delta_delete(delta: Delta, amount: Int) -> Result(Delta, Error) {
  case amount > 0 {
    True -> Ok(Delta(push(operations_delta(delta), Delete(amount))))
    False -> Error(Malformed("delete", "length must be a positive integer"))
  }
}

pub fn delta_retain(
  delta: Delta,
  amount: Int,
  attributes: Attributes,
) -> Result(Delta, Error) {
  case amount > 0 {
    True -> Ok(Delta(push(operations_delta(delta), Retain(amount, attributes))))
    False -> Error(Malformed("retain", "length must be a positive integer"))
  }
}

/// Build a normalized insert-only document from operations.
pub fn document_operations(document: Document) -> Result(Document, Error) {
  let Document(ops) = document
  case
    list.try_fold(ops, [], fn(acc, op) {
      case op {
        InsertText(text, attrs) ->
          case validate_text(text) {
            Ok(_) ->
              Ok(push(acc, InsertText(text, attribute_map.without_nulls(attrs))))
            Error(error) -> Error(error)
          }
        InsertEmbed(VNull, _) ->
          Error(Malformed("insert", "null embeds are not valid"))
        InsertEmbed(embed, attrs) ->
          Ok(push(acc, InsertEmbed(embed, attribute_map.without_nulls(attrs))))
        _ -> Error(Malformed("document", "documents may contain inserts only"))
      }
    })
  {
    Ok(ops) -> Ok(Document(ops))
    Error(error) -> Error(error)
  }
}

/// Build a normalized operation delta. This is also useful to normalize
/// operations assembled from the public operation constructors.
pub fn delta_operations(delta: Delta) -> Result(Delta, Error) {
  let Delta(ops) = delta
  normalize_operations(ops) |> result.map(Delta)
}

pub fn insert_text(text: String, attributes: Attributes) -> Operation {
  InsertText(text, attribute_map.without_nulls(attributes))
}

pub fn insert_embed(embed: JsonValue, attributes: Attributes) -> Operation {
  InsertEmbed(embed, attribute_map.without_nulls(attributes))
}

pub fn delete(amount: Int) -> Operation {
  Delete(amount)
}

pub fn retain(amount: Int, attributes: Attributes) -> Operation {
  Retain(amount, attributes)
}

pub fn document_ops(document: Document) -> List(Operation) {
  operations_document(document)
}

pub fn delta_ops(delta: Delta) -> List(Operation) {
  operations_delta(delta)
}

pub fn document_length(document: Document) -> Int {
  operations_document(document)
  |> list.fold(0, fn(total, op) { total + op_iterator.length(op) })
}

/// The sum of operation lengths, matching Delta#length().
pub fn length(delta: Delta) -> Int {
  operations_delta(delta)
  |> list.fold(0, fn(total, op) { total + op_iterator.length(op) })
}

pub fn change_length(delta: Delta) -> Int {
  operations_delta(delta)
  |> list.fold(0, fn(total, op) {
    case op {
      InsertText(_, _) | InsertEmbed(_, _) -> total + op_iterator.length(op)
      Delete(amount) -> total - amount
      Retain(_, _) -> total
    }
  })
}

pub fn normalize(delta: Delta) -> Delta {
  let Delta(ops) = delta
  case normalize_operations(ops) {
    Ok(normalized) -> Delta(normalized)
    Error(_) -> delta
  }
}

/// Quill Delta compose. `b` is interpreted against the result of `a`.
pub fn compose(a: Delta, b: Delta) -> Delta {
  let left = op_iterator.new(operations_delta(a))
  let right = op_iterator.new(operations_delta(b))
  Delta(compose_loop(left, right, []))
}

/// Apply is deliberately the same compose routine as upstream
/// `snapshot.compose(delta)`, then checks that its result remains a document.
pub fn apply(document: Document, delta: Delta) -> Result(Document, Error) {
  use _ <- result.try(validate_application_boundaries(
    operations_document(document),
    operations_delta(delta),
  ))
  let snapshot = Delta(operations_document(document))
  let Delta(result_ops) = compose(snapshot, delta)
  document_operations(Document(result_ops))
  |> result.map_error(fn(error) {
    case error {
      Malformed(_, reason) -> InvalidApply(reason)
      other -> other
    }
  })
}

/// rich-text adapter semantics: `b.transform(a, side == Left)`.
pub fn transform(a: Delta, b: Delta, side: Side) -> Delta {
  transform_core(
    op_iterator.new(operations_delta(b)),
    op_iterator.new(operations_delta(a)),
    side == Left,
    [],
  )
  |> Delta
}

pub fn invert(delta: Delta, base: Document) -> Result(Delta, Error) {
  invert_loop(
    operations_delta(delta),
    op_iterator.new(operations_document(base)),
    [],
  )
  |> result.map(fn(ops) { Delta(ops) })
}

/// rich-text's transformCursor: `delta.transformPosition(index, !is_own_op)`.
pub fn transform_position(delta: Delta, index: Int, is_own_op: Bool) -> Int {
  transform_position_loop(
    op_iterator.new(operations_delta(delta)),
    index,
    0,
    !is_own_op,
  )
}

pub fn transform_selection(
  delta: Delta,
  selection: Selection,
  is_own_op: Bool,
) -> Selection {
  let Selection(index, selected_length) = selection
  let start = transform_position(delta, index, is_own_op)
  let end = transform_position(delta, index + selected_length, is_own_op)
  Selection(start, end - start)
}

pub fn selection(index: Int, length: Int) -> Result(Selection, Error) {
  case index >= 0 && length >= 0 {
    True -> Ok(Selection(index, length))
    False ->
      Error(Malformed("selection", "index and length must be non-negative"))
  }
}

pub fn selection_index(selection: Selection) -> Int {
  selection.index
}

pub fn selection_length(selection: Selection) -> Int {
  selection.length
}

// ── JSON codecs ─────────────────────────────────────────────────────────────

pub fn document_to_json(document: Document) -> Json {
  json.array(operations_document(document), operation_to_json)
}

pub fn delta_to_json(delta: Delta) -> Json {
  json.array(operations_delta(delta), operation_to_json)
}

pub fn document_from_json(value: JsonValue) -> Result(Document, Error) {
  decode_operations(value, True)
  |> result.map(Document)
  |> result.try(document_operations)
}

pub fn delta_from_json(value: JsonValue) -> Result(Delta, Error) {
  decode_operations(value, False)
  |> result.map(Delta)
  |> result.try(delta_operations)
}

pub fn document_from_json_string(raw: String) -> Result(Document, Error) {
  json_ot.from_json_string(raw)
  |> result.map_error(fn(_) { Malformed("document", "invalid JSON") })
  |> result.try(document_from_json)
}

pub fn delta_from_json_string(raw: String) -> Result(Delta, Error) {
  json_ot.from_json_string(raw)
  |> result.map_error(fn(_) { Malformed("delta", "invalid JSON") })
  |> result.try(delta_from_json)
}

fn operation_to_json(operation: Operation) -> Json {
  case operation {
    InsertText(text, attrs) ->
      with_attributes([#("insert", json.string(text))], attrs)
    InsertEmbed(embed, attrs) ->
      with_attributes([#("insert", json_ot.to_json(embed))], attrs)
    Delete(amount) -> json.object([#("delete", json.int(amount))])
    Retain(amount, attrs) ->
      with_attributes([#("retain", json.int(amount))], attrs)
  }
}

fn with_attributes(fields: List(#(String, Json)), attrs: Attributes) -> Json {
  case attribute_map.is_empty(attrs) {
    True -> json.object(fields)
    False ->
      json.object(
        list.append(fields, [#("attributes", attributes_to_json(attrs))]),
      )
  }
}

fn attributes_to_json(attrs: Attributes) -> Json {
  attrs
  |> attribute_map.to_list
  |> list.map(fn(entry) { #(entry.0, json_ot.to_json(entry.1)) })
  |> json.object
}

fn decode_operations(
  value: JsonValue,
  document_only: Bool,
) -> Result(List(Operation), Error) {
  case value {
    VArray(values) -> decode_operations_list(values, document_only, 0, [])
    _ -> Error(Malformed("operations", "must be an array"))
  }
}

fn decode_operations_list(
  values: List(JsonValue),
  document_only: Bool,
  index: Int,
  operations: List(Operation),
) -> Result(List(Operation), Error) {
  case values {
    [] -> Ok(operations)
    [value, ..rest] -> {
      use operation <- result.try(decode_operation(value, index, document_only))
      decode_operations_list(
        rest,
        document_only,
        index + 1,
        push(operations, operation),
      )
    }
  }
}

fn decode_operation(
  value: JsonValue,
  index: Int,
  document_only: Bool,
) -> Result(Operation, Error) {
  case value {
    VObject(fields) -> {
      let insert = field(fields, "insert")
      let delete = field(fields, "delete")
      let retain = field(fields, "retain")
      let action_count = count_present([insert, delete, retain])
      case fields_are_valid(fields) {
        False ->
          Error(Malformed(
            "operation " <> int.to_string(index),
            "contains an unknown field",
          ))
        True ->
          case action_count {
            1 ->
              decode_action(
                insert,
                delete,
                retain,
                field(fields, "attributes"),
                index,
                document_only,
              )
            0 ->
              Error(Malformed(
                "operation " <> int.to_string(index),
                "missing action key",
              ))
            _ ->
              Error(Malformed(
                "operation " <> int.to_string(index),
                "must have exactly one action key",
              ))
          }
      }
    }
    _ ->
      Error(Malformed("operation " <> int.to_string(index), "must be an object"))
  }
}

fn fields_are_valid(fields: List(#(String, JsonValue))) -> Bool {
  list.all(fields, fn(field) {
    field.0 == "insert"
    || field.0 == "delete"
    || field.0 == "retain"
    || field.0 == "attributes"
  })
}

fn decode_action(
  inserted: Option(JsonValue),
  deleted: Option(JsonValue),
  retained: Option(JsonValue),
  raw_attributes: Option(JsonValue),
  index: Int,
  document_only: Bool,
) -> Result(Operation, Error) {
  use attrs <- result.try(decode_attributes(raw_attributes, index))
  case inserted, deleted, retained {
    Some(VString(text)), _, _ -> {
      use _ <- result.try(validate_text(text))
      Ok(InsertText(text, attribute_map.without_nulls(attrs)))
    }
    Some(VNull), _, _ ->
      Error(Malformed(
        "operation " <> int.to_string(index),
        "null insert is invalid",
      ))
    Some(embed), _, _ ->
      Ok(InsertEmbed(embed, attribute_map.without_nulls(attrs)))
    _, Some(_value), _ if document_only ->
      Error(Malformed("document", "delete operation is not allowed"))
    _, _, Some(_value) if document_only ->
      Error(Malformed("document", "retain operation is not allowed"))
    _, Some(value), _ ->
      decode_length(value, "delete", index) |> result.map(Delete)
    _, _, Some(value) ->
      decode_length(value, "retain", index)
      |> result.map(fn(amount) { Retain(amount, attrs) })
    _, _, _ ->
      Error(Malformed(
        "operation " <> int.to_string(index),
        "missing action key",
      ))
  }
}

fn decode_attributes(
  raw: Option(JsonValue),
  index: Int,
) -> Result(Attributes, Error) {
  case raw {
    None -> Ok(attribute_map.empty())
    Some(VObject(entries)) -> Ok(attribute_map.from_list(entries))
    Some(_) ->
      Error(Malformed(
        "operation " <> int.to_string(index),
        "attributes must be an object",
      ))
  }
}

fn decode_length(
  value: JsonValue,
  kind: String,
  index: Int,
) -> Result(Int, Error) {
  case value {
    VNumber(NInt(amount)) if amount > 0 -> Ok(amount)
    _ ->
      Error(Malformed(
        "operation " <> int.to_string(index),
        kind <> " must be a positive integer",
      ))
  }
}

fn field(
  fields: List(#(String, JsonValue)),
  name: String,
) -> Option(JsonValue) {
  case list.key_find(fields, name) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn count_present(values: List(Option(a))) -> Int {
  values
  |> list.fold(0, fn(count, value) {
    case value {
      Some(_) -> count + 1
      None -> count
    }
  })
}

// ── Delta algorithms ────────────────────────────────────────────────────────

fn compose_loop(
  left: Iterator,
  right: Iterator,
  result: List(Operation),
) -> List(Operation) {
  case op_iterator.has_next(left) || op_iterator.has_next(right) {
    False -> chop(result)
    True -> {
      let amount = next_amount(left, right)
      case op_iterator.peek_kind(right), op_iterator.peek_kind(left) {
        Insert, _ -> {
          let #(op, next_right) = op_iterator.take(right, amount)
          compose_loop(left, next_right, push(result, op))
        }
        _, DeleteKind -> {
          let #(op, next_left) = op_iterator.take(left, amount)
          compose_loop(next_left, right, push(result, op))
        }
        _, _ -> {
          let #(left_op, next_left) = op_iterator.take(left, amount)
          let #(right_op, next_right) = op_iterator.take(right, amount)
          let next_result = case right_op {
            Retain(_, right_attrs) ->
              case left_op {
                Retain(_, left_attrs) ->
                  push(
                    result,
                    Retain(
                      amount,
                      attribute_map.compose(left_attrs, right_attrs, True),
                    ),
                  )
                InsertText(text, left_attrs) ->
                  push(
                    result,
                    InsertText(
                      text,
                      attribute_map.compose(left_attrs, right_attrs, False),
                    ),
                  )
                InsertEmbed(embed, left_attrs) ->
                  push(
                    result,
                    InsertEmbed(
                      embed,
                      attribute_map.compose(left_attrs, right_attrs, False),
                    ),
                  )
                Delete(_) -> result
              }
            Delete(_) ->
              case left_op {
                Retain(_, _) -> push(result, Delete(amount))
                _ -> result
              }
            _ -> result
          }
          compose_loop(next_left, next_right, next_result)
        }
      }
    }
  }
}

fn transform_core(
  source: Iterator,
  other: Iterator,
  priority: Bool,
  result: List(Operation),
) -> List(Operation) {
  case op_iterator.has_next(source) || op_iterator.has_next(other) {
    False -> chop(result)
    True ->
      case op_iterator.peek_kind(source), op_iterator.peek_kind(other) {
        Insert, Insert if priority -> {
          let amount = unwrap_length(source)
          let #(op, next_source) = op_iterator.take(source, amount)
          transform_core(
            next_source,
            other,
            priority,
            push(result, Retain(op_iterator.length(op), attribute_map.empty())),
          )
        }
        Insert, RetainKind -> {
          let amount = unwrap_length(source)
          let #(op, next_source) = op_iterator.take(source, amount)
          transform_core(
            next_source,
            other,
            priority,
            push(result, Retain(op_iterator.length(op), attribute_map.empty())),
          )
        }
        Insert, DeleteKind -> {
          let amount = unwrap_length(source)
          let #(op, next_source) = op_iterator.take(source, amount)
          transform_core(
            next_source,
            other,
            priority,
            push(result, Retain(op_iterator.length(op), attribute_map.empty())),
          )
        }
        _, Insert -> {
          let amount = unwrap_length(other)
          let #(op, next_other) = op_iterator.take(other, amount)
          transform_core(source, next_other, priority, push(result, op))
        }
        _, _ -> {
          let amount = next_amount(source, other)
          let #(source_op, next_source) = op_iterator.take(source, amount)
          let #(other_op, next_other) = op_iterator.take(other, amount)
          let next_result = case source_op, other_op {
            Delete(_), _ -> result
            _, Delete(_) -> push(result, other_op)
            _, Retain(_, other_attrs) ->
              push(
                result,
                Retain(
                  amount,
                  attribute_map.transform(
                    op_iterator.attributes(source_op),
                    other_attrs,
                    priority,
                  ),
                ),
              )
            _, _ -> result
          }
          transform_core(next_source, next_other, priority, next_result)
        }
      }
  }
}

fn invert_loop(
  operations: List(Operation),
  base: Iterator,
  result: List(Operation),
) -> Result(List(Operation), Error) {
  case operations {
    [] -> Ok(chop(result))
    [op, ..rest] ->
      case op {
        InsertText(_, _) | InsertEmbed(_, _) ->
          invert_loop(rest, base, push(result, Delete(op_iterator.length(op))))
        Delete(amount) -> {
          use #(pieces, next_base) <- result.try(
            take_document(base, amount, []),
          )
          invert_loop(rest, next_base, list.fold(pieces, result, push))
        }
        Retain(amount, attrs) ->
          case attribute_map.is_empty(attrs) {
            True -> {
              use next_base <- result.try(advance(base, amount))
              invert_loop(
                rest,
                next_base,
                push(result, Retain(amount, attribute_map.empty())),
              )
            }
            False -> {
              use #(pieces, next_base) <- result.try(
                take_document(base, amount, []),
              )
              let next_result =
                pieces
                |> list.fold(result, fn(acc, piece) {
                  push(
                    acc,
                    Retain(
                      op_iterator.length(piece),
                      attribute_map.invert(attrs, op_iterator.attributes(piece)),
                    ),
                  )
                })
              invert_loop(rest, next_base, next_result)
            }
          }
      }
  }
}

fn take_document(
  iterator: Iterator,
  amount: Int,
  pieces: List(Operation),
) -> Result(#(List(Operation), Iterator), Error) {
  case amount == 0 {
    True -> Ok(#(pieces, iterator))
    False ->
      case op_iterator.peek_length(iterator) {
        // Quill's Delta#slice returns the available document suffix rather
        // than throwing. Invert therefore preserves that harmless behavior
        // for non-contextual deltas; apply remains checked separately.
        None -> Ok(#(pieces, iterator))
        Some(available) -> {
          let take = int.min(amount, available)
          let #(piece, next) = op_iterator.take(iterator, take)
          take_document(next, amount - take, list.append(pieces, [piece]))
        }
      }
  }
}

fn advance(iterator: Iterator, amount: Int) -> Result(Iterator, Error) {
  take_document(iterator, amount, []) |> result.map(fn(pair) { pair.1 })
}

fn transform_position_loop(
  iterator: Iterator,
  index: Int,
  offset: Int,
  priority: Bool,
) -> Int {
  case op_iterator.has_next(iterator) && offset <= index {
    False -> index
    True -> {
      let amount = unwrap_length(iterator)
      let kind = op_iterator.peek_kind(iterator)
      let #(_, next) = op_iterator.take(iterator, amount)
      case kind {
        DeleteKind ->
          transform_position_loop(
            next,
            index - int.min(amount, index - offset),
            offset + amount,
            priority,
          )
        Insert ->
          case offset < index || !priority {
            True ->
              transform_position_loop(
                next,
                index + amount,
                offset + amount,
                priority,
              )
            False ->
              transform_position_loop(next, index, offset + amount, priority)
          }
        _ -> transform_position_loop(next, index, offset + amount, priority)
      }
    }
  }
}

fn next_amount(a: Iterator, b: Iterator) -> Int {
  case op_iterator.peek_length(a), op_iterator.peek_length(b) {
    Some(left), Some(right) -> int.min(left, right)
    Some(left), None -> left
    None, Some(right) -> right
    None, None -> 1
  }
}

fn unwrap_length(iterator: Iterator) -> Int {
  let assert Some(amount) = op_iterator.peek_length(iterator)
  amount
}

fn normalize_operations(
  operations: List(Operation),
) -> Result(List(Operation), Error) {
  operations
  |> list.try_fold([], fn(acc, op) {
    case op {
      InsertText(text, attrs) ->
        case validate_text(text) {
          Ok(_) ->
            Ok(push(acc, InsertText(text, attribute_map.without_nulls(attrs))))
          Error(error) -> Error(error)
        }
      InsertEmbed(VNull, _) ->
        Error(Malformed("insert", "null embeds are not valid"))
      InsertEmbed(embed, attrs) ->
        Ok(push(acc, InsertEmbed(embed, attribute_map.without_nulls(attrs))))
      Delete(amount) if amount > 0 -> Ok(push(acc, op))
      Retain(amount, _) if amount > 0 -> Ok(push(acc, op))
      Delete(_) ->
        Error(Malformed("delete", "length must be a positive integer"))
      Retain(_, _) ->
        Error(Malformed("retain", "length must be a positive integer"))
    }
  })
  |> result.map(chop)
}

fn push(operations: List(Operation), operation: Operation) -> List(Operation) {
  case operation {
    InsertText("", _) -> operations
    Delete(amount) if amount <= 0 -> operations
    Retain(amount, _) if amount <= 0 -> operations
    _ -> push_nonempty(operations, operation)
  }
}

fn push_nonempty(
  operations: List(Operation),
  operation: Operation,
) -> List(Operation) {
  case list.reverse(operations) {
    [] -> [operation]
    [last, ..before_reversed] ->
      case last, operation {
        Delete(a), Delete(b) -> list.reverse([Delete(a + b), ..before_reversed])
        Delete(_), InsertText(_, _) ->
          push(list.reverse(before_reversed), operation) |> list.append([last])
        Delete(_), InsertEmbed(_, _) ->
          push(list.reverse(before_reversed), operation) |> list.append([last])
        InsertText(a, attrs_a), InsertText(b, attrs_b) if attrs_a == attrs_b ->
          list.reverse([InsertText(a <> b, attrs_a), ..before_reversed])
        Retain(a, attrs_a), Retain(b, attrs_b) if attrs_a == attrs_b ->
          list.reverse([Retain(a + b, attrs_a), ..before_reversed])
        _, _ -> list.append(operations, [operation])
      }
  }
}

fn chop(operations: List(Operation)) -> List(Operation) {
  case list.reverse(operations) {
    [Retain(_, attrs), ..rest] ->
      case attribute_map.is_empty(attrs) {
        True -> list.reverse(rest)
        False -> operations
      }
    _ -> operations
  }
}

fn operations_document(document: Document) -> List(Operation) {
  let Document(operations) = document
  operations
}

fn operations_delta(delta: Delta) -> List(Operation) {
  let Delta(operations) = delta
  operations
}

fn validate_text(text: String) -> Result(Nil, Error) {
  case utf16.valid(text) {
    True -> Ok(Nil)
    False -> Error(Malformed("insert", "text contains an unpaired surrogate"))
  }
}

/// Detect the one context-dependent malformed shape: a retain/delete endpoint
/// in the middle of a supplementary scalar's UTF-16 surrogate pair.
fn validate_application_boundaries(
  document: List(Operation),
  delta: List(Operation),
) -> Result(Nil, Error) {
  validate_application_operations(document, delta, 0)
}

fn validate_application_operations(
  document: List(Operation),
  delta: List(Operation),
  offset: Int,
) -> Result(Nil, Error) {
  case delta {
    [] -> Ok(Nil)
    [InsertText(_, _), ..rest] | [InsertEmbed(_, _), ..rest] ->
      validate_application_operations(document, rest, offset)
    [Delete(amount), ..rest] | [Retain(amount, _), ..rest] -> {
      use #(remaining, next_offset) <- result.try(consume_document(
        document,
        amount,
        offset,
      ))
      validate_application_operations(remaining, rest, next_offset)
    }
  }
}

fn consume_document(
  document: List(Operation),
  amount: Int,
  offset: Int,
) -> Result(#(List(Operation), Int), Error) {
  case amount == 0 {
    True -> Ok(#(document, offset))
    False ->
      case document {
        [] -> Ok(#([], offset + amount))
        [InsertText(text, attrs), ..rest] -> {
          let width = utf16.length(text)
          case amount < width {
            True ->
              case utf16.boundary(text, amount) {
                False -> Error(InvalidBoundary(offset + amount))
                True -> {
                  let assert Ok(remaining_text) =
                    utf16.slice(text, amount, width - amount)
                  Ok(#(
                    [InsertText(remaining_text, attrs), ..rest],
                    offset + amount,
                  ))
                }
              }
            False -> consume_document(rest, amount - width, offset + width)
          }
        }
        [InsertEmbed(_, _), ..rest] ->
          consume_document(rest, amount - 1, offset + 1)
        [Delete(_), ..rest] | [Retain(_, _), ..rest] ->
          consume_document(rest, amount, offset)
      }
  }
}
