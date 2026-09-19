/// <reference types="./operation_iterator.d.mts" />
import * as $int from "../../../gleam_stdlib/gleam/int.mjs";
import * as $result from "../../../gleam_stdlib/gleam/result.mjs";
import { Ok, Error, Empty as $Empty, CustomType as $CustomType } from "../../gleam.mjs";
import * as $json_ot from "../../watershed/json_ot.mjs";
import * as $attribute_map from "../../watershed/rich_text/attribute_map.mjs";
import * as $utf16 from "../../watershed/rich_text/utf16.mjs";

export class InsertText extends $CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
export const Operation$InsertText = ($0, $1) => new InsertText($0, $1);
export const Operation$isInsertText = (value) => value instanceof InsertText;
export const Operation$InsertText$0 = (value) => value[0];
export const Operation$InsertText$1 = (value) => value[1];

export class InsertEmbed extends $CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
export const Operation$InsertEmbed = ($0, $1) => new InsertEmbed($0, $1);
export const Operation$isInsertEmbed = (value) => value instanceof InsertEmbed;
export const Operation$InsertEmbed$0 = (value) => value[0];
export const Operation$InsertEmbed$1 = (value) => value[1];

export class Delete extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Operation$Delete = ($0) => new Delete($0);
export const Operation$isDelete = (value) => value instanceof Delete;
export const Operation$Delete$0 = (value) => value[0];

export class Retain extends $CustomType {
  constructor($0, $1) {
    super();
    this[0] = $0;
    this[1] = $1;
  }
}
export const Operation$Retain = ($0, $1) => new Retain($0, $1);
export const Operation$isRetain = (value) => value instanceof Retain;
export const Operation$Retain$0 = (value) => value[0];
export const Operation$Retain$1 = (value) => value[1];

export class Insert extends $CustomType {}
export const Kind$Insert$const = new Insert();
export const Kind$Insert = () => Kind$Insert$const;
export const Kind$isInsert = (value) => value instanceof Insert;

export class DeleteKind extends $CustomType {}
export const Kind$DeleteKind$const = new DeleteKind();
export const Kind$DeleteKind = () => Kind$DeleteKind$const;
export const Kind$isDeleteKind = (value) => value instanceof DeleteKind;

export class RetainKind extends $CustomType {}
export const Kind$RetainKind$const = new RetainKind();
export const Kind$RetainKind = () => Kind$RetainKind$const;
export const Kind$isRetainKind = (value) => value instanceof RetainKind;

export class SplitBoundary extends $CustomType {
  constructor(offset) {
    super();
    this.offset = offset;
  }
}
export const IteratorError$SplitBoundary = (offset) =>
  new SplitBoundary(offset);
export const IteratorError$isSplitBoundary = (value) =>
  value instanceof SplitBoundary;
export const IteratorError$SplitBoundary$offset = (value) => value.offset;
export const IteratorError$SplitBoundary$0 = (value) => value.offset;

export class Iterator extends $CustomType {
  constructor(operations, offset) {
    super();
    this.operations = operations;
    this.offset = offset;
  }
}
export const Iterator$Iterator = (operations, offset) =>
  new Iterator(operations, offset);
export const Iterator$isIterator = (value) => value instanceof Iterator;
export const Iterator$Iterator$operations = (value) => value.operations;
export const Iterator$Iterator$0 = (value) => value.operations;
export const Iterator$Iterator$offset = (value) => value.offset;
export const Iterator$Iterator$1 = (value) => value.offset;

export function new$(operations) {
  return new Iterator(operations, 0);
}

export function has_next(iterator) {
  let operations = iterator.operations;
  return !(operations instanceof $Empty);
}

export function peek_kind(iterator) {
  let operations = iterator.operations;
  if (operations instanceof $Empty) {
    return Kind$RetainKind$const;
  } else {
    let $ = operations.head;
    if ($ instanceof InsertText) {
      return Kind$Insert$const;
    } else if ($ instanceof InsertEmbed) {
      return Kind$Insert$const;
    } else if ($ instanceof Delete) {
      return Kind$DeleteKind$const;
    } else {
      return Kind$RetainKind$const;
    }
  }
}

export function length(operation) {
  if (operation instanceof InsertText) {
    let text = operation[0];
    return $utf16.length(text);
  } else if (operation instanceof InsertEmbed) {
    return 1;
  } else if (operation instanceof Delete) {
    let amount = operation[0];
    return amount;
  } else {
    let amount = operation[0];
    return amount;
  }
}

/**
 * The length that is left in the operation at the front. The result is
 * `Error(Nil)` when the iterator holds no operation.
 */
export function peek_length(iterator) {
  let operations = iterator.operations;
  let offset = iterator.offset;
  if (operations instanceof $Empty) {
    return new Error(undefined);
  } else {
    let operation = operations.head;
    return new Ok(length(operation) - offset);
  }
}

function split(operation, offset, amount) {
  if (operation instanceof InsertText) {
    let text = operation[0];
    let attributes$1 = operation[1];
    let _pipe = $utf16.slice(text, offset, amount);
    let _pipe$1 = $result.map(
      _pipe,
      (_capture) => { return new InsertText(_capture, attributes$1); },
    );
    return $result.map_error(
      _pipe$1,
      (_) => { return new SplitBoundary(offset + amount); },
    );
  } else if (operation instanceof InsertEmbed) {
    let value = operation[0];
    let attributes$1 = operation[1];
    return new Ok(new InsertEmbed(value, attributes$1));
  } else if (operation instanceof Delete) {
    return new Ok(new Delete(amount));
  } else {
    let attributes$1 = operation[1];
    return new Ok(new Retain(amount, attributes$1));
  }
}

export function take(iterator, requested) {
  let operations = iterator.operations;
  let offset = iterator.offset;
  if (operations instanceof $Empty) {
    return new Ok([new Retain(requested, $attribute_map.empty()), iterator]);
  } else {
    let operation = operations.head;
    let rest = operations.tail;
    let available = length(operation) - offset;
    let amount = $int.min(requested, available);
    let _block;
    let $ = amount === available;
    if ($) {
      _block = new Iterator(rest, 0);
    } else {
      _block = new Iterator(operations, offset + amount);
    }
    let next = _block;
    let _pipe = split(operation, offset, amount);
    return $result.map(_pipe, (part) => { return [part, next]; });
  }
}

export function attributes(operation) {
  if (operation instanceof InsertText) {
    let attributes$1 = operation[1];
    return attributes$1;
  } else if (operation instanceof InsertEmbed) {
    let attributes$1 = operation[1];
    return attributes$1;
  } else if (operation instanceof Delete) {
    return $attribute_map.empty();
  } else {
    let attributes$1 = operation[1];
    return attributes$1;
  }
}
