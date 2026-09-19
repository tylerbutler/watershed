/// <reference types="./canonical_json.d.mts" />
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $float from "../../gleam_stdlib/gleam/float.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, toList, CustomType as $CustomType, toBitArray, stringBits } from "../gleam.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";

class Decimal extends $CustomType {
  constructor(negative, digits, point) {
    super();
    this.negative = negative;
    this.digits = digits;
    this.point = point;
  }
}

class Zero extends $CustomType {}
const Decimal$Zero$const = new Zero();

/**
 * The encoding of a number that is not finite. JSON has no form for an
 * infinity or a NaN. `to_string` must stay total and must emit JSON that a
 * parser accepts, so it writes what `JSON.stringify` writes: `null`.
 *
 * A value decoded from JSON can never carry such a number, because a parser
 * has no syntax for one. This case is thus reachable only from locally built
 * state, and only on JavaScript, where float arithmetic overflows to an
 * infinity. On Erlang it raises instead. The cost is that such a value hashes
 * as a null.
 * 
 * @ignore
 */
const non_finite = "null";

const plain_point_floor = -6;

/**
 * How far the decimal point can be from the first significant digit before
 * the layout changes to an exponent: 21 digits to the right of it, and 6
 * zeros to the left of it. Both limits come from `Number::toString` of
 * ECMAScript. That is the rule of one target, and it is now the rule here.
 * The choice of rule is arbitrary. To own the rule is not.
 * 
 * @ignore
 */
const plain_point_ceiling = 21;

/**
 * The largest finite double. An infinity is above it, and a NaN is false in
 * every comparison. One comparison thus finds both.
 * 
 * @ignore
 */
const largest_finite = 1.7976931348623157e308;

/**
 * The largest integer that a JavaScript number holds exactly, which is
 * 2^53 - 1. Above that value the two targets no longer hold the same value.
 * They hold the same double only.
 * 
 * @ignore
 */
const exact_int_ceiling = 9_007_199_254_740_991;

function hex_pair(code) {
  let _pipe = $int.to_base16(code);
  let _pipe$1 = $string.lowercase(_pipe);
  return $string.pad_start(_pipe$1, 2, "0");
}

function escaped(point) {
  let $ = $string.utf_codepoint_to_int(point);
  if ($ === 34) {
    return "\\\"";
  } else if ($ === 92) {
    return "\\\\";
  } else if ($ === 8) {
    return "\\b";
  } else if ($ === 9) {
    return "\\t";
  } else if ($ === 10) {
    return "\\n";
  } else if ($ === 12) {
    return "\\f";
  } else if ($ === 13) {
    return "\\r";
  } else {
    let code = $;
    let $1 = code < 0x20;
    if ($1) {
      return "\\u00" + hex_pair(code);
    } else {
      return $string.from_utf_codepoints(toList([point]));
    }
  }
}

function needs_escape(point) {
  let code = $string.utf_codepoint_to_int(point);
  return ((code < 0x20) || (code === 0x22)) || (code === 0x5c);
}

function quoted(text) {
  let points = $string.to_utf_codepoints(text);
  let $ = $list.any(points, needs_escape);
  if ($) {
    return ("\"" + $string.concat($list.map(points, escaped))) + "\"";
  } else {
    return ("\"" + text) + "\"";
  }
}

/**
 * Order two strings by their UTF-8 bytes, on every target. `string.compare`
 * does not do that.
 */
export function compare(left, right) {
  return $bit_array.compare(
    toBitArray([stringBits(left)]),
    toBitArray([stringBits(right)]),
  );
}

function scientific(digits, count, exponent) {
  let _block;
  if (count === 1) {
    _block = digits;
  } else {
    _block = ($string.slice(digits, 0, 1) + ".") + $string.drop_start(digits, 1);
  }
  let mantissa = _block;
  return (mantissa + "e") + $int.to_string(exponent);
}

function zeros(count) {
  return $string.repeat("0", count);
}

/**
 * Place the decimal point. The function pads the digits with zeros while the
 * point is after them. It puts a point between the digits while the point is
 * inside them. It writes `0.` and zeros while the point is a short distance
 * to the left of them. It writes an exponent when the point is further out
 * than that.
 * 
 * @ignore
 */
function placed(digits, count, point) {
  let plain = (point <= plain_point_ceiling) && (point > plain_point_floor);
  let $ = point >= count;
  let $1 = point > 0;
  if (plain) {
    if ($) {
      return digits + zeros(point - count);
    } else if ($1) {
      return ($string.slice(digits, 0, point) + ".") + $string.drop_start(
        digits,
        point,
      );
    } else {
      return ("0." + zeros(- point)) + digits;
    }
  } else {
    return scientific(digits, count, point - 1);
  }
}

function laid_out(value) {
  if (value instanceof Decimal) {
    let negative = value.negative;
    let digits = value.digits;
    let point = value.point;
    let body = placed(digits, $string.length(digits), point);
    if (negative) {
      return "-" + body;
    } else {
      return body;
    }
  } else {
    return "0";
  }
}

function without_trailing_zeros(loop$digits) {
  while (true) {
    let digits = loop$digits;
    let $ = $string.ends_with(digits, "0");
    if ($) {
      loop$digits = $string.drop_end(digits, 1);
    } else {
      return digits;
    }
  }
}

function without_leading_zeros(loop$digits) {
  while (true) {
    let digits = loop$digits;
    let $ = $string.starts_with(digits, "0");
    if ($) {
      loop$digits = $string.drop_start(digits, 1);
    } else {
      return digits;
    }
  }
}

/**
 * JavaScript writes `e+21` and Erlang writes `e21`. The sign of a positive
 * exponent is also part of the layout.
 * 
 * @ignore
 */
function exponent_value(text) {
  let $ = $string.starts_with(text, "+");
  if ($) {
    return $int.parse($string.drop_start(text, 1));
  } else {
    return $int.parse(text);
  }
}

/**
 * Read the float printing of one target as digits and a decimal point
 * position, and discard the layout that the target chose. For one double,
 * Erlang prints `1.0e-5` and JavaScript prints `0.00001`.
 *
 * An `Error` result means text that no float printing produces. The caller
 * then encodes the value as `non_finite`. It does not guess at a number.
 * 
 * @ignore
 */
function significant(text) {
  let _block;
  let $1 = $string.starts_with(text, "-");
  if ($1) {
    _block = [true, $string.drop_start(text, 1)];
  } else {
    _block = [false, text];
  }
  let $ = _block;
  let negative = $[0];
  let unsigned = $[1];
  let _block$1;
  let $3 = $string.split_once(unsigned, "e");
  if ($3 instanceof Ok) {
    let mantissa = $3[0][0];
    let exponent = $3[0][1];
    _block$1 = [mantissa, exponent_value(exponent)];
  } else {
    _block$1 = [unsigned, new Ok(0)];
  }
  let $2 = _block$1;
  let mantissa = $2[0];
  let exponent = $2[1];
  if (exponent instanceof Ok) {
    let exponent$1 = exponent[0];
    let _block$2;
    let $5 = $string.split_once(mantissa, ".");
    if ($5 instanceof Ok) {
      let parts = $5[0];
      _block$2 = parts;
    } else {
      _block$2 = [mantissa, ""];
    }
    let $4 = _block$2;
    let whole = $4[0];
    let fraction = $4[1];
    let written = whole + fraction;
    let trimmed = without_leading_zeros(written);
    let digits = without_trailing_zeros(trimmed);
    let leading = $string.length(written) - $string.length(trimmed);
    if (digits === "") {
      return new Ok(Decimal$Zero$const);
    } else {
      return new Ok(
        new Decimal(
          negative,
          digits,
          ($string.length(whole) + exponent$1) - leading,
        ),
      );
    }
  } else {
    return new Error(undefined);
  }
}

/**
 * One form for each finite double, on every target. Both targets print the
 * shortest digits that read back as the same double, and they agree on those
 * digits. They then lay the digits out by their own rule, and they do not
 * agree on that rule. This function thus takes the digits and lays them out
 * again.
 * 
 * @ignore
 */
function float_to_string(value) {
  let $ = $float.absolute_value(value) <= largest_finite;
  if ($) {
    let $1 = significant($float.to_string(value));
    if ($1 instanceof Ok) {
      let decimal = $1[0];
      return laid_out(decimal);
    } else {
      return non_finite;
    }
  } else {
    return non_finite;
  }
}

function pointed(mantissa) {
  let $ = $string.contains(mantissa, ".");
  if ($) {
    return mantissa;
  } else {
    return mantissa + ".0";
  }
}

/**
 * `float.parse` needs a decimal point in the mantissa, and no integer
 * printing puts one there.
 * 
 * @ignore
 */
function with_point(text) {
  let $ = $string.split_once(text, "e");
  if ($ instanceof Ok) {
    let mantissa = $[0][0];
    let exponent = $[0][1];
    return (pointed(mantissa) + "e") + exponent;
  } else {
    return pointed(text);
  }
}

/**
 * The conversion goes through the decimal text of the integer, and not
 * through `int.to_float`. On Erlang, `int.to_float` raises `badarg` for an
 * integer outside the double range. A remote snapshot can carry such an
 * integer, and nothing on that path can crash. `float.parse` returns an error
 * instead. On JavaScript the integer is already a double, and it prints as
 * one, with its exponent. `parse` reads that text back without a change. An
 * integer that overflowed prints as `Infinity`, and `parse` refuses it.
 * 
 * @ignore
 */
function as_double(value) {
  return $float.parse(with_point($int.to_string(value)));
}

/**
 * An integer above the exact range of JavaScript. The parser of JavaScript
 * replaced it with the nearest double before this code ran. The function thus
 * renders that double, on both targets, and the two targets agree.
 * 
 * @ignore
 */
function wide_int_to_string(value) {
  let $ = as_double(value);
  if ($ instanceof Ok) {
    let double = $[0];
    return float_to_string(double);
  } else {
    return non_finite;
  }
}

/**
 * Render a number, so that every JSON form of one value gives one text. `1`,
 * `1.0`, and `1e0` all become `1`. Two values that differ keep two texts.
 * 
 * @ignore
 */
function number_to_string(value) {
  if (value instanceof $json_ot.NInt) {
    let int = value[0];
    let $ = $int.absolute_value(int) <= exact_int_ceiling;
    if ($) {
      return $int.to_string(int);
    } else {
      return wide_int_to_string(int);
    }
  } else {
    let float = value[0];
    return float_to_string(float);
  }
}

/**
 * Encode a value in canonical form: sorted object keys, one escaping policy,
 * and one number rendering. The function keeps the array order. A caller that
 * holds a set in an array must sort that array first, with `sorted`.
 */
export function to_string(value) {
  if (value instanceof $json_ot.VNull) {
    return "null";
  } else if (value instanceof $json_ot.VBool) {
    let $ = value[0];
    if ($) {
      return "true";
    } else {
      return "false";
    }
  } else if (value instanceof $json_ot.VNumber) {
    let number = value[0];
    return number_to_string(number);
  } else if (value instanceof $json_ot.VString) {
    let text = value[0];
    return quoted(text);
  } else if (value instanceof $json_ot.VArray) {
    let items = value[0];
    let _block;
    let _pipe = $list.map(items, to_string);
    _block = $string.join(_pipe, ",");
    let body = _block;
    return ("[" + body) + "]";
  } else {
    let members = value[0];
    let _block;
    let _pipe = members;
    let _pipe$1 = $list.sort(
      _pipe,
      (left, right) => { return compare(left[0], right[0]); },
    );
    let _pipe$2 = $list.map(
      _pipe$1,
      (member) => { return (quoted(member[0]) + ":") + to_string(member[1]); },
    );
    _block = $string.join(_pipe$2, ",");
    let body = _block;
    return ("{" + body) + "}";
  }
}

/**
 * Order an array that encodes a set, by the canonical bytes of each element.
 * The function encodes each element one time, and not one time for each
 * comparison.
 */
export function sorted(items) {
  let _pipe = items;
  let _pipe$1 = $list.map(_pipe, (item) => { return [to_string(item), item]; });
  let _pipe$2 = $list.sort(
    _pipe$1,
    (left, right) => { return compare(left[0], right[0]); },
  );
  return $list.map(_pipe$2, (pair) => { return pair[1]; });
}
