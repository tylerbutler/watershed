/// <reference types="./rich_text.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import { NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString } from "../watershed/json_ot.mjs";
import * as $attribute_map from "../watershed/rich_text/attribute_map.mjs";
import * as $operation_iterator from "../watershed/rich_text/operation_iterator.mjs";
import {
  Delete,
  DeleteKind,
  Insert,
  InsertEmbed,
  InsertText,
  Retain,
  RetainKind,
  SplitBoundary,
} from "../watershed/rich_text/operation_iterator.mjs";
import * as $utf16 from "../watershed/rich_text/utf16.mjs";

class Document extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Delta extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

export class Left extends $CustomType {}
export const Side$Left$const = new Left();
export const Side$Left = () => Side$Left$const;
export const Side$isLeft = (value) => value instanceof Left;

export class Right extends $CustomType {}
export const Side$Right$const = new Right();
export const Side$Right = () => Side$Right$const;
export const Side$isRight = (value) => value instanceof Right;

export class Selection extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const Selection$Selection = (index, length) =>
  new Selection(index, length);
export const Selection$isSelection = (value) => value instanceof Selection;
export const Selection$Selection$index = (value) => value.index;
export const Selection$Selection$0 = (value) => value.index;
export const Selection$Selection$length = (value) => value.length;
export const Selection$Selection$1 = (value) => value.length;

export class Malformed extends $CustomType {
  constructor(component, reason) {
    super();
    this.component = component;
    this.reason = reason;
  }
}
export const Error$Malformed = (component, reason) =>
  new Malformed(component, reason);
export const Error$isMalformed = (value) => value instanceof Malformed;
export const Error$Malformed$component = (value) => value.component;
export const Error$Malformed$0 = (value) => value.component;
export const Error$Malformed$reason = (value) => value.reason;
export const Error$Malformed$1 = (value) => value.reason;

export class InvalidApply extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const Error$InvalidApply = (reason) => new InvalidApply(reason);
export const Error$isInvalidApply = (value) => value instanceof InvalidApply;
export const Error$InvalidApply$reason = (value) => value.reason;
export const Error$InvalidApply$0 = (value) => value.reason;

export class InvalidBoundary extends $CustomType {
  constructor(offset) {
    super();
    this.offset = offset;
  }
}
export const Error$InvalidBoundary = (offset) => new InvalidBoundary(offset);
export const Error$isInvalidBoundary = (value) =>
  value instanceof InvalidBoundary;
export const Error$InvalidBoundary$offset = (value) => value.offset;
export const Error$InvalidBoundary$0 = (value) => value.offset;

export function empty_document() {
  return new Document($List$Empty$const);
}

export function empty_delta() {
  return new Delta($List$Empty$const);
}

export function attributes(entries) {
  return $attribute_map.from_list(entries);
}

function operations_document(document) {
  let operations = document[0];
  return operations;
}

function push_nonempty(operations, operation) {
  let $ = $list.reverse(operations);
  if ($ instanceof $Empty) {
    return toList([operation]);
  } else {
    let last = $.head;
    let before_reversed = $.tail;
    if (last instanceof InsertText) {
      if (operation instanceof InsertText) {
        let attributes_a = last[1];
        let attributes_b = operation[1];
        if (isEqual(attributes_a, attributes_b)) {
          let a = last[0];
          let b = operation[0];
          return $list.reverse(
            listPrepend(new InsertText(a + b, attributes_a), before_reversed),
          );
        } else {
          return $list.append(operations, toList([operation]));
        }
      } else {
        return $list.append(operations, toList([operation]));
      }
    } else if (last instanceof InsertEmbed) {
      return $list.append(operations, toList([operation]));
    } else if (last instanceof Delete) {
      if (operation instanceof InsertText) {
        let _pipe = push($list.reverse(before_reversed), operation);
        return $list.append(_pipe, toList([last]));
      } else if (operation instanceof InsertEmbed) {
        let _pipe = push($list.reverse(before_reversed), operation);
        return $list.append(_pipe, toList([last]));
      } else if (operation instanceof Delete) {
        let a = last[0];
        let b = operation[0];
        return $list.reverse(listPrepend(new Delete(a + b), before_reversed));
      } else {
        return $list.append(operations, toList([operation]));
      }
    } else if (operation instanceof Retain) {
      let attributes_a = last[1];
      let attributes_b = operation[1];
      if (isEqual(attributes_a, attributes_b)) {
        let a = last[0];
        let b = operation[0];
        return $list.reverse(
          listPrepend(new Retain(a + b, attributes_a), before_reversed),
        );
      } else {
        return $list.append(operations, toList([operation]));
      }
    } else {
      return $list.append(operations, toList([operation]));
    }
  }
}

function push(operations, operation) {
  if (operation instanceof InsertText) {
    let $ = operation[0];
    if ($ === "") {
      return operations;
    } else {
      return push_nonempty(operations, operation);
    }
  } else if (operation instanceof InsertEmbed) {
    return push_nonempty(operations, operation);
  } else if (operation instanceof Delete) {
    let amount = operation[0];
    if (amount <= 0) {
      return operations;
    } else {
      return push_nonempty(operations, operation);
    }
  } else {
    let amount = operation[0];
    if (amount <= 0) {
      return operations;
    } else {
      return push_nonempty(operations, operation);
    }
  }
}

function validate_text(text) {
  let $ = $utf16.valid(text);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      new Malformed("insert", "text contains an unpaired surrogate"),
    );
  }
}

/**
 * Build a normalized insert-only document from operations.
 */
export function document_operations(document) {
  let operations = document[0];
  let $ = $list.try_fold(
    operations,
    $List$Empty$const,
    (acc, operation) => {
      if (operation instanceof InsertText) {
        let text = operation[0];
        let attributes$1 = operation[1];
        let $1 = validate_text(text);
        if ($1 instanceof Ok) {
          return new Ok(
            push(
              acc,
              new InsertText(text, $attribute_map.without_nulls(attributes$1)),
            ),
          );
        } else {
          return $1;
        }
      } else if (operation instanceof InsertEmbed) {
        let $1 = operation[0];
        if ($1 instanceof VNull) {
          return new Error(new Malformed("insert", "null embeds are not valid"));
        } else {
          let embed = $1;
          let attributes$1 = operation[1];
          return new Ok(
            push(
              acc,
              new InsertEmbed(embed, $attribute_map.without_nulls(attributes$1)),
            ),
          );
        }
      } else if (operation instanceof Delete) {
        return new Error(
          new Malformed("document", "documents may contain inserts only"),
        );
      } else {
        return new Error(
          new Malformed("document", "documents may contain inserts only"),
        );
      }
    },
  );
  if ($ instanceof Ok) {
    let operations$1 = $[0];
    return new Ok(new Document(operations$1));
  } else {
    return $;
  }
}

export function document_insert_text(document, text, attributes) {
  let $ = validate_text(text);
  if ($ instanceof Ok) {
    return document_operations(
      new Document(
        push(
          operations_document(document),
          new InsertText(text, $attribute_map.without_nulls(attributes)),
        ),
      ),
    );
  } else {
    return $;
  }
}

export function document_insert_embed(document, embed, attributes) {
  let $ = embed instanceof VNull;
  if ($) {
    return new Error(new Malformed("insert", "null embeds are not valid"));
  } else {
    return document_operations(
      new Document(
        push(
          operations_document(document),
          new InsertEmbed(embed, $attribute_map.without_nulls(attributes)),
        ),
      ),
    );
  }
}

function operations_delta(delta) {
  let operations = delta[0];
  return operations;
}

export function delta_insert_text(delta, text, attributes) {
  let $ = validate_text(text);
  if ($ instanceof Ok) {
    return new Ok(
      new Delta(
        push(
          operations_delta(delta),
          new InsertText(text, $attribute_map.without_nulls(attributes)),
        ),
      ),
    );
  } else {
    return $;
  }
}

export function delta_insert_embed(delta, embed, attributes) {
  let $ = embed instanceof VNull;
  if ($) {
    return new Error(new Malformed("insert", "null embeds are not valid"));
  } else {
    return new Ok(
      new Delta(
        push(
          operations_delta(delta),
          new InsertEmbed(embed, $attribute_map.without_nulls(attributes)),
        ),
      ),
    );
  }
}

export function delta_delete(delta, amount) {
  let $ = amount > 0;
  if ($) {
    return new Ok(new Delta(push(operations_delta(delta), new Delete(amount))));
  } else {
    return new Error(
      new Malformed("delete", "length must be a positive integer"),
    );
  }
}

export function delta_retain(delta, amount, attributes) {
  let $ = amount > 0;
  if ($) {
    return new Ok(
      new Delta(push(operations_delta(delta), new Retain(amount, attributes))),
    );
  } else {
    return new Error(
      new Malformed("retain", "length must be a positive integer"),
    );
  }
}

function chop(operations) {
  let $ = $list.reverse(operations);
  if ($ instanceof $Empty) {
    return operations;
  } else {
    let $1 = $.head;
    if ($1 instanceof Retain) {
      let rest = $.tail;
      let attributes$1 = $1[1];
      let $2 = $attribute_map.is_empty(attributes$1);
      if ($2) {
        return $list.reverse(rest);
      } else {
        return operations;
      }
    } else {
      return operations;
    }
  }
}

function normalize_operations(operations) {
  let _pipe = operations;
  let _pipe$1 = $list.try_fold(
    _pipe,
    $List$Empty$const,
    (acc, operation) => {
      if (operation instanceof InsertText) {
        let text = operation[0];
        let attributes$1 = operation[1];
        let $ = validate_text(text);
        if ($ instanceof Ok) {
          return new Ok(
            push(
              acc,
              new InsertText(text, $attribute_map.without_nulls(attributes$1)),
            ),
          );
        } else {
          return $;
        }
      } else if (operation instanceof InsertEmbed) {
        let $ = operation[0];
        if ($ instanceof VNull) {
          return new Error(new Malformed("insert", "null embeds are not valid"));
        } else {
          let embed = $;
          let attributes$1 = operation[1];
          return new Ok(
            push(
              acc,
              new InsertEmbed(embed, $attribute_map.without_nulls(attributes$1)),
            ),
          );
        }
      } else if (operation instanceof Delete) {
        let amount = operation[0];
        if (amount > 0) {
          return new Ok(push(acc, operation));
        } else {
          return new Error(
            new Malformed("delete", "length must be a positive integer"),
          );
        }
      } else {
        let amount = operation[0];
        if (amount > 0) {
          return new Ok(push(acc, operation));
        } else {
          return new Error(
            new Malformed("retain", "length must be a positive integer"),
          );
        }
      }
    },
  );
  return $result.map(_pipe$1, chop);
}

/**
 * Build a normalized operation delta. Use this function also to normalize
 * operations that you assemble with the public operation constructors.
 */
export function delta_operations(delta) {
  let operations = delta[0];
  let _pipe = normalize_operations(operations);
  return $result.map(_pipe, (var0) => { return new Delta(var0); });
}

export function insert_text(text, attributes) {
  return new InsertText(text, $attribute_map.without_nulls(attributes));
}

export function insert_embed(embed, attributes) {
  return new InsertEmbed(embed, $attribute_map.without_nulls(attributes));
}

export function delete$(amount) {
  return new Delete(amount);
}

export function retain(amount, attributes) {
  return new Retain(amount, attributes);
}

export function document_to_operations(document) {
  return operations_document(document);
}

export function delta_to_operations(delta) {
  return operations_delta(delta);
}

export function document_length(document) {
  let _pipe = operations_document(document);
  return $list.fold(
    _pipe,
    0,
    (total, operation) => {
      return total + $operation_iterator.length(operation);
    },
  );
}

/**
 * The sum of the operation lengths. This is the same result as
 * `Delta#length()`.
 */
export function length(delta) {
  let _pipe = operations_delta(delta);
  return $list.fold(
    _pipe,
    0,
    (total, operation) => {
      return total + $operation_iterator.length(operation);
    },
  );
}

export function change_length(delta) {
  let _pipe = operations_delta(delta);
  return $list.fold(
    _pipe,
    0,
    (total, operation) => {
      if (operation instanceof InsertText) {
        return total + $operation_iterator.length(operation);
      } else if (operation instanceof InsertEmbed) {
        return total + $operation_iterator.length(operation);
      } else if (operation instanceof Delete) {
        let amount = operation[0];
        return total - amount;
      } else {
        return total;
      }
    },
  );
}

export function normalize(delta) {
  let operations = delta[0];
  let $ = normalize_operations(operations);
  if ($ instanceof Ok) {
    let normalized = $[0];
    return new Delta(normalized);
  } else {
    return delta;
  }
}

function iterator_error(error) {
  let offset = error.offset;
  return new InvalidBoundary(offset);
}

function take_checked(iterator, amount) {
  let _pipe = $operation_iterator.take(iterator, amount);
  return $result.map_error(_pipe, iterator_error);
}

function next_amount(a, b) {
  let $ = $operation_iterator.peek_length(a);
  let $1 = $operation_iterator.peek_length(b);
  if ($ instanceof Ok) {
    if ($1 instanceof Ok) {
      let left = $[0];
      let right = $1[0];
      return $int.min(left, right);
    } else {
      let left = $[0];
      return left;
    }
  } else if ($1 instanceof Ok) {
    let right = $1[0];
    return right;
  } else {
    return 1;
  }
}

function compose_loop(left, right, result) {
  let $ = $operation_iterator.has_next(left) || $operation_iterator.has_next(
    right,
  );
  if ($) {
    let amount = next_amount(left, right);
    let $1 = $operation_iterator.peek_kind(right);
    let $2 = $operation_iterator.peek_kind(left);
    if ($1 instanceof Insert) {
      return $result.try$(
        take_checked(right, amount),
        (_use0) => {
          let operation = _use0[0];
          let next_right = _use0[1];
          return compose_loop(left, next_right, push(result, operation));
        },
      );
    } else if ($1 instanceof DeleteKind) {
      if ($2 instanceof Insert) {
        return $result.try$(
          take_checked(left, amount),
          (_use0) => {
            let left_operation = _use0[0];
            let next_left = _use0[1];
            return $result.try$(
              take_checked(right, amount),
              (_use0) => {
                let right_operation = _use0[0];
                let next_right = _use0[1];
                let _block;
                if (right_operation instanceof InsertText) {
                  _block = result;
                } else if (right_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (right_operation instanceof Delete) {
                  if (left_operation instanceof InsertText) {
                    _block = result;
                  } else if (left_operation instanceof InsertEmbed) {
                    _block = result;
                  } else if (left_operation instanceof Delete) {
                    _block = result;
                  } else {
                    _block = push(result, new Delete(amount));
                  }
                } else {
                  let right_attributes = right_operation[1];
                  if (left_operation instanceof InsertText) {
                    let text = left_operation[0];
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new InsertText(
                        text,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          false,
                        ),
                      ),
                    );
                  } else if (left_operation instanceof InsertEmbed) {
                    let embed = left_operation[0];
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new InsertEmbed(
                        embed,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          false,
                        ),
                      ),
                    );
                  } else if (left_operation instanceof Delete) {
                    _block = result;
                  } else {
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new Retain(
                        amount,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          true,
                        ),
                      ),
                    );
                  }
                }
                let next_result = _block;
                return compose_loop(next_left, next_right, next_result);
              },
            );
          },
        );
      } else if ($2 instanceof DeleteKind) {
        return $result.try$(
          take_checked(left, amount),
          (_use0) => {
            let operation = _use0[0];
            let next_left = _use0[1];
            return compose_loop(next_left, right, push(result, operation));
          },
        );
      } else {
        return $result.try$(
          take_checked(left, amount),
          (_use0) => {
            let left_operation = _use0[0];
            let next_left = _use0[1];
            return $result.try$(
              take_checked(right, amount),
              (_use0) => {
                let right_operation = _use0[0];
                let next_right = _use0[1];
                let _block;
                if (right_operation instanceof InsertText) {
                  _block = result;
                } else if (right_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (right_operation instanceof Delete) {
                  if (left_operation instanceof InsertText) {
                    _block = result;
                  } else if (left_operation instanceof InsertEmbed) {
                    _block = result;
                  } else if (left_operation instanceof Delete) {
                    _block = result;
                  } else {
                    _block = push(result, new Delete(amount));
                  }
                } else {
                  let right_attributes = right_operation[1];
                  if (left_operation instanceof InsertText) {
                    let text = left_operation[0];
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new InsertText(
                        text,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          false,
                        ),
                      ),
                    );
                  } else if (left_operation instanceof InsertEmbed) {
                    let embed = left_operation[0];
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new InsertEmbed(
                        embed,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          false,
                        ),
                      ),
                    );
                  } else if (left_operation instanceof Delete) {
                    _block = result;
                  } else {
                    let left_attributes = left_operation[1];
                    _block = push(
                      result,
                      new Retain(
                        amount,
                        $attribute_map.compose(
                          left_attributes,
                          right_attributes,
                          true,
                        ),
                      ),
                    );
                  }
                }
                let next_result = _block;
                return compose_loop(next_left, next_right, next_result);
              },
            );
          },
        );
      }
    } else if ($2 instanceof Insert) {
      return $result.try$(
        take_checked(left, amount),
        (_use0) => {
          let left_operation = _use0[0];
          let next_left = _use0[1];
          return $result.try$(
            take_checked(right, amount),
            (_use0) => {
              let right_operation = _use0[0];
              let next_right = _use0[1];
              let _block;
              if (right_operation instanceof InsertText) {
                _block = result;
              } else if (right_operation instanceof InsertEmbed) {
                _block = result;
              } else if (right_operation instanceof Delete) {
                if (left_operation instanceof InsertText) {
                  _block = result;
                } else if (left_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (left_operation instanceof Delete) {
                  _block = result;
                } else {
                  _block = push(result, new Delete(amount));
                }
              } else {
                let right_attributes = right_operation[1];
                if (left_operation instanceof InsertText) {
                  let text = left_operation[0];
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new InsertText(
                      text,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        false,
                      ),
                    ),
                  );
                } else if (left_operation instanceof InsertEmbed) {
                  let embed = left_operation[0];
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new InsertEmbed(
                      embed,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        false,
                      ),
                    ),
                  );
                } else if (left_operation instanceof Delete) {
                  _block = result;
                } else {
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new Retain(
                      amount,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        true,
                      ),
                    ),
                  );
                }
              }
              let next_result = _block;
              return compose_loop(next_left, next_right, next_result);
            },
          );
        },
      );
    } else if ($2 instanceof DeleteKind) {
      return $result.try$(
        take_checked(left, amount),
        (_use0) => {
          let operation = _use0[0];
          let next_left = _use0[1];
          return compose_loop(next_left, right, push(result, operation));
        },
      );
    } else {
      return $result.try$(
        take_checked(left, amount),
        (_use0) => {
          let left_operation = _use0[0];
          let next_left = _use0[1];
          return $result.try$(
            take_checked(right, amount),
            (_use0) => {
              let right_operation = _use0[0];
              let next_right = _use0[1];
              let _block;
              if (right_operation instanceof InsertText) {
                _block = result;
              } else if (right_operation instanceof InsertEmbed) {
                _block = result;
              } else if (right_operation instanceof Delete) {
                if (left_operation instanceof InsertText) {
                  _block = result;
                } else if (left_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (left_operation instanceof Delete) {
                  _block = result;
                } else {
                  _block = push(result, new Delete(amount));
                }
              } else {
                let right_attributes = right_operation[1];
                if (left_operation instanceof InsertText) {
                  let text = left_operation[0];
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new InsertText(
                      text,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        false,
                      ),
                    ),
                  );
                } else if (left_operation instanceof InsertEmbed) {
                  let embed = left_operation[0];
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new InsertEmbed(
                      embed,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        false,
                      ),
                    ),
                  );
                } else if (left_operation instanceof Delete) {
                  _block = result;
                } else {
                  let left_attributes = left_operation[1];
                  _block = push(
                    result,
                    new Retain(
                      amount,
                      $attribute_map.compose(
                        left_attributes,
                        right_attributes,
                        true,
                      ),
                    ),
                  );
                }
              }
              let next_result = _block;
              return compose_loop(next_left, next_right, next_result);
            },
          );
        },
      );
    }
  } else {
    return new Ok(chop(result));
  }
}

/**
 * Quill Delta compose. The kernel interprets `b` against the result of `a`.
 */
export function compose(a, b) {
  let left = $operation_iterator.new$(operations_delta(a));
  let right = $operation_iterator.new$(operations_delta(b));
  let _pipe = compose_loop(left, right, $List$Empty$const);
  return $result.map(_pipe, (var0) => { return new Delta(var0); });
}

function consume_document(loop$document, loop$amount, loop$offset) {
  while (true) {
    let document = loop$document;
    let amount = loop$amount;
    let offset = loop$offset;
    let $ = amount === 0;
    if ($) {
      return new Ok([document, offset]);
    } else {
      if (document instanceof $Empty) {
        return new Ok([$List$Empty$const, offset + amount]);
      } else {
        let $1 = document.head;
        if ($1 instanceof InsertText) {
          let rest = document.tail;
          let text = $1[0];
          let attributes$1 = $1[1];
          let width = $utf16.length(text);
          let $2 = amount < width;
          if ($2) {
            let $3 = $utf16.boundary(text, amount);
            if ($3) {
              return $result.try$(
                (() => {
                  let _pipe = $utf16.slice(text, amount, width - amount);
                  return $result.map_error(
                    _pipe,
                    (_) => { return new InvalidBoundary(offset + amount); },
                  );
                })(),
                (remaining_text) => {
                  return new Ok(
                    [
                      listPrepend(
                        new InsertText(remaining_text, attributes$1),
                        rest,
                      ),
                      offset + amount,
                    ],
                  );
                },
              );
            } else {
              return new Error(new InvalidBoundary(offset + amount));
            }
          } else {
            loop$document = rest;
            loop$amount = amount - width;
            loop$offset = offset + width;
          }
        } else if ($1 instanceof InsertEmbed) {
          let rest = document.tail;
          loop$document = rest;
          loop$amount = amount - 1;
          loop$offset = offset + 1;
        } else if ($1 instanceof Delete) {
          let rest = document.tail;
          loop$document = rest;
          loop$amount = amount;
          loop$offset = offset;
        } else {
          let rest = document.tail;
          loop$document = rest;
          loop$amount = amount;
          loop$offset = offset;
        }
      }
    }
  }
}

function validate_application_operations(loop$document, loop$delta, loop$offset) {
  while (true) {
    let document = loop$document;
    let delta = loop$delta;
    let offset = loop$offset;
    if (delta instanceof $Empty) {
      return new Ok(undefined);
    } else {
      let $ = delta.head;
      if ($ instanceof InsertText) {
        let rest = delta.tail;
        loop$document = document;
        loop$delta = rest;
        loop$offset = offset;
      } else if ($ instanceof InsertEmbed) {
        let rest = delta.tail;
        loop$document = document;
        loop$delta = rest;
        loop$offset = offset;
      } else if ($ instanceof Delete) {
        let rest = delta.tail;
        let amount = $[0];
        return $result.try$(
          consume_document(document, amount, offset),
          (_use0) => {
            let remaining = _use0[0];
            let next_offset = _use0[1];
            return validate_application_operations(remaining, rest, next_offset);
          },
        );
      } else {
        let rest = delta.tail;
        let amount = $[0];
        return $result.try$(
          consume_document(document, amount, offset),
          (_use0) => {
            let remaining = _use0[0];
            let next_offset = _use0[1];
            return validate_application_operations(remaining, rest, next_offset);
          },
        );
      }
    }
  }
}

/**
 * Detect the one malformed shape that depends on context. That shape is a
 * retain endpoint or a delete endpoint inside the UTF-16 surrogate pair of a
 * supplementary scalar.
 * 
 * @ignore
 */
function validate_application_boundaries(document, delta) {
  return validate_application_operations(document, delta, 0);
}

/**
 * Apply uses the same compose routine as the upstream
 * `snapshot.compose(delta)`. This is deliberate. It then checks that the
 * result is still a document.
 */
export function apply(document, delta) {
  return $result.try$(
    validate_application_boundaries(
      operations_document(document),
      operations_delta(delta),
    ),
    (_) => {
      let snapshot = new Delta(operations_document(document));
      return $result.try$(
        compose(snapshot, delta),
        (_use0) => {
          let result_operations = _use0[0];
          let _pipe = document_operations(new Document(result_operations));
          return $result.map_error(
            _pipe,
            (error) => {
              if (error instanceof Malformed) {
                let reason = error.reason;
                return new InvalidApply(reason);
              } else if (error instanceof InvalidApply) {
                return error;
              } else {
                return error;
              }
            },
          );
        },
      );
    },
  );
}

function take_remaining(iterator) {
  let $ = $operation_iterator.peek_length(iterator);
  if ($ instanceof Ok) {
    let amount = $[0];
    return take_checked(iterator, amount);
  } else {
    return new Error(new InvalidApply("iterator unexpectedly exhausted"));
  }
}

function transform_core(source, other, priority, result) {
  let $ = $operation_iterator.has_next(source) || $operation_iterator.has_next(
    other,
  );
  if ($) {
    let $1 = $operation_iterator.peek_kind(source);
    let $2 = $operation_iterator.peek_kind(other);
    if ($1 instanceof Insert) {
      let other_kind = $2;
      let $3 = priority || (!(other_kind instanceof Insert));
      if ($3) {
        return $result.try$(
          take_remaining(source),
          (_use0) => {
            let operation = _use0[0];
            let next_source = _use0[1];
            return transform_core(
              next_source,
              other,
              priority,
              push(
                result,
                new Retain(
                  $operation_iterator.length(operation),
                  $attribute_map.empty(),
                ),
              ),
            );
          },
        );
      } else {
        return $result.try$(
          take_remaining(other),
          (_use0) => {
            let operation = _use0[0];
            let next_other = _use0[1];
            return transform_core(
              source,
              next_other,
              priority,
              push(result, operation),
            );
          },
        );
      }
    } else if ($1 instanceof DeleteKind) {
      if ($2 instanceof Insert) {
        return $result.try$(
          take_remaining(other),
          (_use0) => {
            let operation = _use0[0];
            let next_other = _use0[1];
            return transform_core(
              source,
              next_other,
              priority,
              push(result, operation),
            );
          },
        );
      } else if ($2 instanceof DeleteKind) {
        let amount = next_amount(source, other);
        return $result.try$(
          take_checked(source, amount),
          (_use0) => {
            let source_operation = _use0[0];
            let next_source = _use0[1];
            return $result.try$(
              take_checked(other, amount),
              (_use0) => {
                let other_operation = _use0[0];
                let next_other = _use0[1];
                let _block;
                if (source_operation instanceof Delete) {
                  _block = result;
                } else if (other_operation instanceof InsertText) {
                  _block = result;
                } else if (other_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (other_operation instanceof Delete) {
                  _block = push(result, other_operation);
                } else {
                  let other_attributes = other_operation[1];
                  _block = push(
                    result,
                    new Retain(
                      amount,
                      $attribute_map.transform(
                        $operation_iterator.attributes(source_operation),
                        other_attributes,
                        priority,
                      ),
                    ),
                  );
                }
                let next_result = _block;
                return transform_core(
                  next_source,
                  next_other,
                  priority,
                  next_result,
                );
              },
            );
          },
        );
      } else {
        let amount = next_amount(source, other);
        return $result.try$(
          take_checked(source, amount),
          (_use0) => {
            let source_operation = _use0[0];
            let next_source = _use0[1];
            return $result.try$(
              take_checked(other, amount),
              (_use0) => {
                let other_operation = _use0[0];
                let next_other = _use0[1];
                let _block;
                if (source_operation instanceof Delete) {
                  _block = result;
                } else if (other_operation instanceof InsertText) {
                  _block = result;
                } else if (other_operation instanceof InsertEmbed) {
                  _block = result;
                } else if (other_operation instanceof Delete) {
                  _block = push(result, other_operation);
                } else {
                  let other_attributes = other_operation[1];
                  _block = push(
                    result,
                    new Retain(
                      amount,
                      $attribute_map.transform(
                        $operation_iterator.attributes(source_operation),
                        other_attributes,
                        priority,
                      ),
                    ),
                  );
                }
                let next_result = _block;
                return transform_core(
                  next_source,
                  next_other,
                  priority,
                  next_result,
                );
              },
            );
          },
        );
      }
    } else if ($2 instanceof Insert) {
      return $result.try$(
        take_remaining(other),
        (_use0) => {
          let operation = _use0[0];
          let next_other = _use0[1];
          return transform_core(
            source,
            next_other,
            priority,
            push(result, operation),
          );
        },
      );
    } else if ($2 instanceof DeleteKind) {
      let amount = next_amount(source, other);
      return $result.try$(
        take_checked(source, amount),
        (_use0) => {
          let source_operation = _use0[0];
          let next_source = _use0[1];
          return $result.try$(
            take_checked(other, amount),
            (_use0) => {
              let other_operation = _use0[0];
              let next_other = _use0[1];
              let _block;
              if (source_operation instanceof Delete) {
                _block = result;
              } else if (other_operation instanceof InsertText) {
                _block = result;
              } else if (other_operation instanceof InsertEmbed) {
                _block = result;
              } else if (other_operation instanceof Delete) {
                _block = push(result, other_operation);
              } else {
                let other_attributes = other_operation[1];
                _block = push(
                  result,
                  new Retain(
                    amount,
                    $attribute_map.transform(
                      $operation_iterator.attributes(source_operation),
                      other_attributes,
                      priority,
                    ),
                  ),
                );
              }
              let next_result = _block;
              return transform_core(
                next_source,
                next_other,
                priority,
                next_result,
              );
            },
          );
        },
      );
    } else {
      let amount = next_amount(source, other);
      return $result.try$(
        take_checked(source, amount),
        (_use0) => {
          let source_operation = _use0[0];
          let next_source = _use0[1];
          return $result.try$(
            take_checked(other, amount),
            (_use0) => {
              let other_operation = _use0[0];
              let next_other = _use0[1];
              let _block;
              if (source_operation instanceof Delete) {
                _block = result;
              } else if (other_operation instanceof InsertText) {
                _block = result;
              } else if (other_operation instanceof InsertEmbed) {
                _block = result;
              } else if (other_operation instanceof Delete) {
                _block = push(result, other_operation);
              } else {
                let other_attributes = other_operation[1];
                _block = push(
                  result,
                  new Retain(
                    amount,
                    $attribute_map.transform(
                      $operation_iterator.attributes(source_operation),
                      other_attributes,
                      priority,
                    ),
                  ),
                );
              }
              let next_result = _block;
              return transform_core(
                next_source,
                next_other,
                priority,
                next_result,
              );
            },
          );
        },
      );
    }
  } else {
    return new Ok(chop(result));
  }
}

/**
 * The rich-text adapter behaviour: `b.transform(a, side == Left)`.
 */
export function transform(a, b, side) {
  let _pipe = transform_core(
    $operation_iterator.new$(operations_delta(b)),
    $operation_iterator.new$(operations_delta(a)),
    side instanceof Left,
    $List$Empty$const,
  );
  return $result.map(_pipe, (var0) => { return new Delta(var0); });
}

function take_document(iterator, amount, pieces) {
  let $ = amount === 0;
  if ($) {
    return new Ok([pieces, iterator]);
  } else {
    let $1 = $operation_iterator.peek_length(iterator);
    if ($1 instanceof Ok) {
      let available = $1[0];
      let take = $int.min(amount, available);
      return $result.try$(
        take_checked(iterator, take),
        (_use0) => {
          let piece = _use0[0];
          let next = _use0[1];
          return take_document(
            next,
            amount - take,
            $list.append(pieces, toList([piece])),
          );
        },
      );
    } else {
      return new Ok([pieces, iterator]);
    }
  }
}

function advance(iterator, amount) {
  let _pipe = take_document(iterator, amount, $List$Empty$const);
  return $result.map(_pipe, (pair) => { return pair[1]; });
}

function invert_loop(loop$operations, loop$base, loop$result) {
  while (true) {
    let operations = loop$operations;
    let base = loop$base;
    let result = loop$result;
    if (operations instanceof $Empty) {
      return new Ok(chop(result));
    } else {
      let operation = operations.head;
      let rest = operations.tail;
      if (operation instanceof InsertText) {
        loop$operations = rest;
        loop$base = base;
        loop$result = push(
          result,
          new Delete($operation_iterator.length(operation)),
        );
      } else if (operation instanceof InsertEmbed) {
        loop$operations = rest;
        loop$base = base;
        loop$result = push(
          result,
          new Delete($operation_iterator.length(operation)),
        );
      } else if (operation instanceof Delete) {
        let amount = operation[0];
        return $result.try$(
          take_document(base, amount, $List$Empty$const),
          (_use0) => {
            let pieces = _use0[0];
            let next_base = _use0[1];
            return invert_loop(
              rest,
              next_base,
              $list.fold(pieces, result, push),
            );
          },
        );
      } else {
        let amount = operation[0];
        let attributes$1 = operation[1];
        let $ = $attribute_map.is_empty(attributes$1);
        if ($) {
          return $result.try$(
            advance(base, amount),
            (next_base) => {
              return invert_loop(
                rest,
                next_base,
                push(result, new Retain(amount, $attribute_map.empty())),
              );
            },
          );
        } else {
          return $result.try$(
            take_document(base, amount, $List$Empty$const),
            (_use0) => {
              let pieces = _use0[0];
              let next_base = _use0[1];
              let _block;
              let _pipe = pieces;
              _block = $list.fold(
                _pipe,
                result,
                (acc, piece) => {
                  return push(
                    acc,
                    new Retain(
                      $operation_iterator.length(piece),
                      $attribute_map.invert(
                        attributes$1,
                        $operation_iterator.attributes(piece),
                      ),
                    ),
                  );
                },
              );
              let next_result = _block;
              return invert_loop(rest, next_base, next_result);
            },
          );
        }
      }
    }
  }
}

export function invert(delta, base) {
  let _pipe = invert_loop(
    operations_delta(delta),
    $operation_iterator.new$(operations_document(base)),
    $List$Empty$const,
  );
  return $result.map(_pipe, (operations) => { return new Delta(operations); });
}

function transform_position_loop(iterator, index, offset, priority) {
  let $ = $operation_iterator.has_next(iterator) && (offset <= index);
  if ($) {
    let kind = $operation_iterator.peek_kind(iterator);
    return $result.try$(
      take_remaining(iterator),
      (_use0) => {
        let operation = _use0[0];
        let next = _use0[1];
        let amount = $operation_iterator.length(operation);
        if (kind instanceof Insert) {
          let $1 = (offset < index) || !priority;
          if ($1) {
            return transform_position_loop(
              next,
              index + amount,
              offset + amount,
              priority,
            );
          } else {
            return transform_position_loop(
              next,
              index,
              offset + amount,
              priority,
            );
          }
        } else if (kind instanceof DeleteKind) {
          return transform_position_loop(
            next,
            index - $int.min(amount, index - offset),
            offset,
            priority,
          );
        } else {
          return transform_position_loop(next, index, offset + amount, priority);
        }
      },
    );
  } else {
    return new Ok(index);
  }
}

/**
 * The `transformCursor` function of rich-text:
 * `delta.transformPosition(index, !is_own_operation)`.
 */
export function transform_position(delta, index, is_own_operation) {
  return transform_position_loop(
    $operation_iterator.new$(operations_delta(delta)),
    index,
    0,
    !is_own_operation,
  );
}

export function transform_selection(delta, selection, is_own_operation) {
  let index = selection.index;
  let selected_length = selection.length;
  return $result.try$(
    transform_position(delta, index, is_own_operation),
    (start) => {
      return $result.try$(
        transform_position(delta, index + selected_length, is_own_operation),
        (end) => { return new Ok(new Selection(start, end - start)); },
      );
    },
  );
}

export function selection(index, length) {
  let $ = (index >= 0) && (length >= 0);
  if ($) {
    return new Ok(new Selection(index, length));
  } else {
    return new Error(
      new Malformed("selection", "index and length must be non-negative"),
    );
  }
}

export function selection_index(selection) {
  return selection.index;
}

export function selection_length(selection) {
  return selection.length;
}

function attributes_to_json(attributes) {
  let _pipe = attributes;
  let _pipe$1 = $attribute_map.to_list(_pipe);
  let _pipe$2 = $list.map(
    _pipe$1,
    (entry) => { return [entry[0], $json_ot.to_json(entry[1])]; },
  );
  return $json.object(_pipe$2);
}

function with_attributes(fields, attributes) {
  let $ = $attribute_map.is_empty(attributes);
  if ($) {
    return $json.object(fields);
  } else {
    return $json.object(
      $list.append(
        fields,
        toList([["attributes", attributes_to_json(attributes)]]),
      ),
    );
  }
}

function operation_to_json(operation) {
  if (operation instanceof InsertText) {
    let text = operation[0];
    let attributes$1 = operation[1];
    return with_attributes(
      toList([["insert", $json.string(text)]]),
      attributes$1,
    );
  } else if (operation instanceof InsertEmbed) {
    let embed = operation[0];
    let attributes$1 = operation[1];
    return with_attributes(
      toList([["insert", $json_ot.to_json(embed)]]),
      attributes$1,
    );
  } else if (operation instanceof Delete) {
    let amount = operation[0];
    return $json.object(toList([["delete", $json.int(amount)]]));
  } else {
    let amount = operation[0];
    let attributes$1 = operation[1];
    return with_attributes(
      toList([["retain", $json.int(amount)]]),
      attributes$1,
    );
  }
}

export function document_to_json(document) {
  return $json.array(operations_document(document), operation_to_json);
}

export function delta_to_json(delta) {
  return $json.array(operations_delta(delta), operation_to_json);
}

function field(fields, name) {
  let $ = $list.key_find(fields, name);
  if ($ instanceof Ok) {
    let value = $[0];
    return new Some(value);
  } else {
    return Option$None$const;
  }
}

function decode_length(value, kind, index) {
  if (value instanceof VNull) {
    return new Error(
      new Malformed(
        "operation " + $int.to_string(index),
        kind + " must be a positive integer",
      ),
    );
  } else if (value instanceof VBool) {
    return new Error(
      new Malformed(
        "operation " + $int.to_string(index),
        kind + " must be a positive integer",
      ),
    );
  } else if (value instanceof VNumber) {
    let $ = value[0];
    if ($ instanceof NInt) {
      let amount = $[0];
      if (amount > 0) {
        return new Ok(amount);
      } else {
        return new Error(
          new Malformed(
            "operation " + $int.to_string(index),
            kind + " must be a positive integer",
          ),
        );
      }
    } else {
      return new Error(
        new Malformed(
          "operation " + $int.to_string(index),
          kind + " must be a positive integer",
        ),
      );
    }
  } else if (value instanceof VString) {
    return new Error(
      new Malformed(
        "operation " + $int.to_string(index),
        kind + " must be a positive integer",
      ),
    );
  } else if (value instanceof VArray) {
    return new Error(
      new Malformed(
        "operation " + $int.to_string(index),
        kind + " must be a positive integer",
      ),
    );
  } else {
    return new Error(
      new Malformed(
        "operation " + $int.to_string(index),
        kind + " must be a positive integer",
      ),
    );
  }
}

function decode_attributes(raw, index) {
  if (raw instanceof Some) {
    let $ = raw[0];
    if ($ instanceof VObject) {
      let entries = $[0];
      return new Ok($attribute_map.from_list(entries));
    } else {
      return new Error(
        new Malformed(
          "operation " + $int.to_string(index),
          "attributes must be an object",
        ),
      );
    }
  } else {
    return new Ok($attribute_map.empty());
  }
}

function decode_action(
  inserted,
  deleted,
  retained,
  raw_attributes,
  index,
  document_only
) {
  return $result.try$(
    decode_attributes(raw_attributes, index),
    (attributes) => {
      if (inserted instanceof Some) {
        let $ = inserted[0];
        if ($ instanceof VNull) {
          return new Error(
            new Malformed(
              "operation " + $int.to_string(index),
              "null insert is invalid",
            ),
          );
        } else if ($ instanceof VString) {
          let text = $[0];
          return $result.try$(
            validate_text(text),
            (_) => {
              return new Ok(
                new InsertText(text, $attribute_map.without_nulls(attributes)),
              );
            },
          );
        } else {
          let embed = $;
          return new Ok(
            new InsertEmbed(embed, $attribute_map.without_nulls(attributes)),
          );
        }
      } else if (deleted instanceof Some) {
        if (document_only) {
          return new Error(
            new Malformed("document", "delete operation is not allowed"),
          );
        } else if (retained instanceof Some && document_only) {
          return new Error(
            new Malformed("document", "retain operation is not allowed"),
          );
        } else {
          let value = deleted[0];
          let _pipe = decode_length(value, "delete", index);
          return $result.map(_pipe, (var0) => { return new Delete(var0); });
        }
      } else if (retained instanceof Some) {
        if (document_only) {
          return new Error(
            new Malformed("document", "retain operation is not allowed"),
          );
        } else {
          let value = retained[0];
          let _pipe = decode_length(value, "retain", index);
          return $result.map(
            _pipe,
            (amount) => { return new Retain(amount, attributes); },
          );
        }
      } else {
        return new Error(
          new Malformed(
            "operation " + $int.to_string(index),
            "missing action key",
          ),
        );
      }
    },
  );
}

function fields_are_valid(fields) {
  return $list.all(
    fields,
    (field) => {
      return (((field[0] === "insert") || (field[0] === "delete")) || (field[0] === "retain")) || (field[0] === "attributes");
    },
  );
}

function count_present(values) {
  let _pipe = values;
  return $list.fold(
    _pipe,
    0,
    (count, value) => {
      if (value instanceof Some) {
        return count + 1;
      } else {
        return count;
      }
    },
  );
}

function decode_operation(value, index, document_only) {
  if (value instanceof VNull) {
    return new Error(
      new Malformed("operation " + $int.to_string(index), "must be an object"),
    );
  } else if (value instanceof VBool) {
    return new Error(
      new Malformed("operation " + $int.to_string(index), "must be an object"),
    );
  } else if (value instanceof VNumber) {
    return new Error(
      new Malformed("operation " + $int.to_string(index), "must be an object"),
    );
  } else if (value instanceof VString) {
    return new Error(
      new Malformed("operation " + $int.to_string(index), "must be an object"),
    );
  } else if (value instanceof VArray) {
    return new Error(
      new Malformed("operation " + $int.to_string(index), "must be an object"),
    );
  } else {
    let fields = value[0];
    let insert = field(fields, "insert");
    let delete$1 = field(fields, "delete");
    let retain$1 = field(fields, "retain");
    let action_count = count_present(toList([insert, delete$1, retain$1]));
    let $ = fields_are_valid(fields);
    if ($) {
      if (action_count === 1) {
        return decode_action(
          insert,
          delete$1,
          retain$1,
          field(fields, "attributes"),
          index,
          document_only,
        );
      } else if (action_count === 0) {
        return new Error(
          new Malformed(
            "operation " + $int.to_string(index),
            "missing action key",
          ),
        );
      } else {
        return new Error(
          new Malformed(
            "operation " + $int.to_string(index),
            "must have exactly one action key",
          ),
        );
      }
    } else {
      return new Error(
        new Malformed(
          "operation " + $int.to_string(index),
          "contains an unknown field",
        ),
      );
    }
  }
}

function decode_operations_list(values, document_only, index, operations) {
  if (values instanceof $Empty) {
    return new Ok(operations);
  } else {
    let value = values.head;
    let rest = values.tail;
    return $result.try$(
      decode_operation(value, index, document_only),
      (operation) => {
        return decode_operations_list(
          rest,
          document_only,
          index + 1,
          push(operations, operation),
        );
      },
    );
  }
}

function decode_operations(value, document_only) {
  if (value instanceof VNull) {
    return new Error(new Malformed("operations", "must be an array"));
  } else if (value instanceof VBool) {
    return new Error(new Malformed("operations", "must be an array"));
  } else if (value instanceof VNumber) {
    return new Error(new Malformed("operations", "must be an array"));
  } else if (value instanceof VString) {
    return new Error(new Malformed("operations", "must be an array"));
  } else if (value instanceof VArray) {
    let values = value[0];
    return decode_operations_list(values, document_only, 0, $List$Empty$const);
  } else {
    return new Error(new Malformed("operations", "must be an array"));
  }
}

export function document_from_json(value) {
  let _pipe = decode_operations(value, true);
  let _pipe$1 = $result.map(_pipe, (var0) => { return new Document(var0); });
  return $result.try$(_pipe$1, document_operations);
}

export function delta_from_json(value) {
  let _pipe = decode_operations(value, false);
  let _pipe$1 = $result.map(_pipe, (var0) => { return new Delta(var0); });
  return $result.try$(_pipe$1, delta_operations);
}

export function parse_document(raw) {
  let _pipe = $json_ot.parse_json(raw);
  let _pipe$1 = $result.map_error(
    _pipe,
    (_) => { return new Malformed("document", "invalid JSON"); },
  );
  return $result.try$(_pipe$1, document_from_json);
}

export function parse_delta(raw) {
  let _pipe = $json_ot.parse_json(raw);
  let _pipe$1 = $result.map_error(
    _pipe,
    (_) => { return new Malformed("delta", "invalid JSON"); },
  );
  return $result.try$(_pipe$1, delta_from_json);
}
