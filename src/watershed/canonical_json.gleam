//// One byte sequence for each logical JSON value, the same on every compile
//// target. The CRDT document digest uses this module. Two peers compare that
//// digest across a mesh that can contain a browser replica and a BEAM
//// replica.
////
//// `gleam/json` and `gleam/string` alone cannot give that result:
////
//// - `string.compare` orders by UTF-8 bytes on Erlang, and by UTF-16 code
////   units on JavaScript. A sort that uses it thus puts an astral character
////   on a different side of `U+FFFD` on each target.
//// - `json.float(1.0)` encodes `1.0` on Erlang and `1` on JavaScript.
////   `1.0e16` prints as `1.0e16` on one target and as `10000000000000000.0`
////   on the other. `1.0e-5` prints as `1.0e-5` on one target and as
////   `0.00001` on the other.
//// - `json.string` escapes a control character as `\u000B` on Erlang and as
////   `\u000b` on JavaScript.
////
//// Each of those differences makes two replicas with identical state produce
//// different hashes. A digest mismatch is a repair request, so a mixed mesh
//// would exchange state without an end and never agree. This module thus owns
//// the whole encoding. It emits the members of an object in the UTF-8 byte
//// order of their keys. It escapes a string by one fixed policy. It renders a
//// number by one rule, which gives `1` and `1.0` the same text and never
//// gives two different numbers the same text.
////
//// That number rule has two halves. An integer that both targets hold
//// exactly, which is a magnitude of 2^53 - 1 or less, is written as its
//// digits. Every other number is a double, and this module does not trust the
//// printing of either target to lay one out. The shortest digits that read
//// back as the same double are the same on both targets, but Erlang and
//// JavaScript put the decimal point in different positions. This module thus
//// extracts the digits and places the point itself. Two different doubles
//// keep two different texts, because the shortest round-trip digits are
//// unique for each double.
////
//// Two limits are inherent, and this module did not choose them. The parser
//// of JavaScript replaces a JSON integer above 2^53 with the nearest double
//// before this module receives it. Two such integers that share a double are
//// one value on that target, and this module encodes them as one. This module
//// does not lose that difference; the difference is gone before the value
//// arrives here. An infinity and a NaN also have no JSON form at all. See
//// `non_finite`.

import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/string

import watershed/json_ot.{type JsonValue, type Num}

/// The largest integer that a JavaScript number holds exactly, which is
/// 2^53 - 1. Above that value the two targets no longer hold the same value.
/// They hold the same double only.
const exact_int_ceiling = 9_007_199_254_740_991

/// The largest finite double. An infinity is above it, and a NaN is false in
/// every comparison. One comparison thus finds both.
const largest_finite = 1.7976931348623157e308

/// How far the decimal point can be from the first significant digit before
/// the layout changes to an exponent: 21 digits to the right of it, and 6
/// zeros to the left of it. Both limits come from `Number::toString` of
/// ECMAScript. That is the rule of one target, and it is now the rule here.
/// The choice of rule is arbitrary. To own the rule is not.
const plain_point_ceiling = 21

const plain_point_floor = -6

/// The encoding of a number that is not finite. JSON has no form for an
/// infinity or a NaN. `to_string` must stay total and must emit JSON that a
/// parser accepts, so it writes what `JSON.stringify` writes: `null`.
///
/// A value decoded from JSON can never carry such a number, because a parser
/// has no syntax for one. This case is thus reachable only from locally built
/// state, and only on JavaScript, where float arithmetic overflows to an
/// infinity. On Erlang it raises instead. The cost is that such a value hashes
/// as a null.
const non_finite = "null"

/// Encode a value in canonical form: sorted object keys, one escaping policy,
/// and one number rendering. The function keeps the array order. A caller that
/// holds a set in an array must sort that array first, with `sorted`.
pub fn to_string(value: JsonValue) -> String {
  case value {
    json_ot.VNull -> "null"
    json_ot.VBool(True) -> "true"
    json_ot.VBool(False) -> "false"
    json_ot.VNumber(number) -> number_to_string(number)
    json_ot.VString(text) -> quoted(text)
    json_ot.VArray(items) -> {
      let body = list.map(items, to_string) |> string.join(",")
      "[" <> body <> "]"
    }
    json_ot.VObject(members) -> {
      let body =
        members
        |> list.sort(fn(left, right) { compare(left.0, right.0) })
        |> list.map(fn(member) {
          quoted(member.0) <> ":" <> to_string(member.1)
        })
        |> string.join(",")
      "{" <> body <> "}"
    }
  }
}

/// Order two strings by their UTF-8 bytes, on every target. `string.compare`
/// does not do that.
pub fn compare(left: String, right: String) -> Order {
  bit_array.compare(<<left:utf8>>, <<right:utf8>>)
}

/// Order an array that encodes a set, by the canonical bytes of each element.
/// The function encodes each element one time, and not one time for each
/// comparison.
pub fn sorted(items: List(JsonValue)) -> List(JsonValue) {
  items
  |> list.map(fn(item) { #(to_string(item), item) })
  |> list.sort(fn(left, right) { compare(left.0, right.0) })
  |> list.map(fn(pair) { pair.1 })
}

/// Render a number, so that every JSON form of one value gives one text. `1`,
/// `1.0`, and `1e0` all become `1`. Two values that differ keep two texts.
fn number_to_string(value: Num) -> String {
  case value {
    json_ot.NInt(int) ->
      case int.absolute_value(int) <= exact_int_ceiling {
        True -> int.to_string(int)
        False -> wide_int_to_string(int)
      }
    json_ot.NFloat(float) -> float_to_string(float)
  }
}

/// An integer above the exact range of JavaScript. The parser of JavaScript
/// replaced it with the nearest double before this code ran. The function thus
/// renders that double, on both targets, and the two targets agree.
fn wide_int_to_string(value: Int) -> String {
  case as_double(value) {
    Ok(double) -> float_to_string(double)
    Error(_) -> non_finite
  }
}

/// The conversion goes through the decimal text of the integer, and not
/// through `int.to_float`. On Erlang, `int.to_float` raises `badarg` for an
/// integer outside the double range. A remote snapshot can carry such an
/// integer, and nothing on that path can crash. `float.parse` returns an error
/// instead. On JavaScript the integer is already a double, and it prints as
/// one, with its exponent. `parse` reads that text back without a change. An
/// integer that overflowed prints as `Infinity`, and `parse` refuses it.
fn as_double(value: Int) -> Result(Float, Nil) {
  float.parse(with_point(int.to_string(value)))
}

/// `float.parse` needs a decimal point in the mantissa, and no integer
/// printing puts one there.
fn with_point(text: String) -> String {
  case string.split_once(text, "e") {
    Ok(#(mantissa, exponent)) -> pointed(mantissa) <> "e" <> exponent
    Error(_) -> pointed(text)
  }
}

fn pointed(mantissa: String) -> String {
  case string.contains(mantissa, ".") {
    True -> mantissa
    False -> mantissa <> ".0"
  }
}

/// One form for each finite double, on every target. Both targets print the
/// shortest digits that read back as the same double, and they agree on those
/// digits. They then lay the digits out by their own rule, and they do not
/// agree on that rule. This function thus takes the digits and lays them out
/// again.
fn float_to_string(value: Float) -> String {
  case float.absolute_value(value) <=. largest_finite {
    False -> non_finite
    True ->
      case significant(float.to_string(value)) {
        Ok(decimal) -> laid_out(decimal)
        Error(_) -> non_finite
      }
  }
}

/// A finite double in the form that the layout needs. `digits` holds the
/// shortest round-trip significant digits, with no leading zero and no
/// trailing zero. The value is `0.<digits> × 10^point`. Every form of zero is
/// `Zero`, with a sign or without one, because JSON has one zero.
type Decimal {
  Decimal(negative: Bool, digits: String, point: Int)
  Zero
}

/// Read the float printing of one target as digits and a decimal point
/// position, and discard the layout that the target chose. For one double,
/// Erlang prints `1.0e-5` and JavaScript prints `0.00001`.
///
/// An `Error` result means text that no float printing produces. The caller
/// then encodes the value as `non_finite`. It does not guess at a number.
fn significant(text: String) -> Result(Decimal, Nil) {
  let #(negative, unsigned) = case string.starts_with(text, "-") {
    True -> #(True, string.drop_start(text, 1))
    False -> #(False, text)
  }
  let #(mantissa, exponent) = case string.split_once(unsigned, "e") {
    Ok(#(mantissa, exponent)) -> #(mantissa, exponent_value(exponent))
    Error(_) -> #(unsigned, Ok(0))
  }
  case exponent {
    Error(_) -> Error(Nil)
    Ok(exponent) -> {
      let #(whole, fraction) = case string.split_once(mantissa, ".") {
        Ok(parts) -> parts
        Error(_) -> #(mantissa, "")
      }
      let written = whole <> fraction
      let trimmed = without_leading_zeros(written)
      let digits = without_trailing_zeros(trimmed)
      let leading = string.length(written) - string.length(trimmed)
      case digits {
        "" -> Ok(Zero)
        _ ->
          Ok(Decimal(
            negative: negative,
            digits: digits,
            point: string.length(whole) + exponent - leading,
          ))
      }
    }
  }
}

/// JavaScript writes `e+21` and Erlang writes `e21`. The sign of a positive
/// exponent is also part of the layout.
fn exponent_value(text: String) -> Result(Int, Nil) {
  case string.starts_with(text, "+") {
    True -> int.parse(string.drop_start(text, 1))
    False -> int.parse(text)
  }
}

fn without_leading_zeros(digits: String) -> String {
  case string.starts_with(digits, "0") {
    True -> without_leading_zeros(string.drop_start(digits, 1))
    False -> digits
  }
}

fn without_trailing_zeros(digits: String) -> String {
  case string.ends_with(digits, "0") {
    True -> without_trailing_zeros(string.drop_end(digits, 1))
    False -> digits
  }
}

fn laid_out(value: Decimal) -> String {
  case value {
    Zero -> "0"
    Decimal(negative, digits, point) -> {
      let body = placed(digits, string.length(digits), point)
      case negative {
        True -> "-" <> body
        False -> body
      }
    }
  }
}

/// Place the decimal point. The function pads the digits with zeros while the
/// point is after them. It puts a point between the digits while the point is
/// inside them. It writes `0.` and zeros while the point is a short distance
/// to the left of them. It writes an exponent when the point is further out
/// than that.
fn placed(digits: String, count: Int, point: Int) -> String {
  let plain = point <= plain_point_ceiling && point > plain_point_floor
  case plain, point >= count, point > 0 {
    True, True, _ -> digits <> zeros(point - count)
    True, False, True ->
      string.slice(digits, 0, point) <> "." <> string.drop_start(digits, point)
    True, False, False -> "0." <> zeros(-point) <> digits
    False, _, _ -> scientific(digits, count, point - 1)
  }
}

fn scientific(digits: String, count: Int, exponent: Int) -> String {
  let mantissa = case count {
    1 -> digits
    _ -> string.slice(digits, 0, 1) <> "." <> string.drop_start(digits, 1)
  }
  mantissa <> "e" <> int.to_string(exponent)
}

fn zeros(count: Int) -> String {
  string.repeat("0", count)
}

fn quoted(text: String) -> String {
  let points = string.to_utf_codepoints(text)
  case list.any(points, needs_escape) {
    False -> "\"" <> text <> "\""
    True -> "\"" <> string.concat(list.map(points, escaped)) <> "\""
  }
}

fn needs_escape(point: UtfCodepoint) -> Bool {
  let code = string.utf_codepoint_to_int(point)
  code < 0x20 || code == 0x22 || code == 0x5c
}

fn escaped(point: UtfCodepoint) -> String {
  case string.utf_codepoint_to_int(point) {
    0x22 -> "\\\""
    0x5c -> "\\\\"
    0x08 -> "\\b"
    0x09 -> "\\t"
    0x0a -> "\\n"
    0x0c -> "\\f"
    0x0d -> "\\r"
    code ->
      case code < 0x20 {
        True -> "\\u00" <> hex_pair(code)
        False -> string.from_utf_codepoints([point])
      }
  }
}

fn hex_pair(code: Int) -> String {
  int.to_base16(code)
  |> string.lowercase
  |> string.pad_start(to: 2, with: "0")
}
