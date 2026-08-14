//// One byte sequence per logical JSON value, identical on every compile
//// target. Used by the CRDT document digest, which two peers compare
//// across a mesh that may mix a browser replica with a BEAM one.
////
//// `gleam/json` and `gleam/string` cannot supply that on their own:
////
//// - `string.compare` orders by UTF-8 bytes on Erlang and by UTF-16 code
////   units on JavaScript, so any sort keyed on it puts an astral
////   character on a different side of `U+FFFD` depending on the target;
//// - `json.float(1.0)` encodes `1.0` on Erlang and `1` on JavaScript,
////   `1.0e16` prints as `1.0e16` on one and `10000000000000000.0` on the
////   other, and `1.0e-5` prints as `1.0e-5` on one and `0.00001` on the
////   other;
//// - `json.string` escapes a control character as `\u000B` on Erlang and
////   `\u000b` on JavaScript.
////
//// Any of those makes two replicas holding identical state hash
//// differently, and a digest mismatch is a repair request — so a mixed
//// mesh would trade state forever without ever agreeing. This module owns
//// the encoding end to end instead: object members are emitted in UTF-8
//// byte order of their keys, strings are escaped by one fixed policy, and
//// numbers are rendered by one rule that gives `1` and `1.0` the same
//// text without ever merging two numbers that differ.
////
//// Numbers get that rule in two halves. An integer both targets hold
//// exactly — magnitude at most 2^53 - 1 — is written as its digits.
//// Everything else is a double, and no target's own printing is trusted
//// to lay one out: the shortest digits that read back as the same double
//// are the same on both targets, but Erlang and JavaScript place the
//// decimal point differently, so the digits are extracted and placed here
//// instead. Distinct doubles keep distinct text, because shortest
//// round-trip digits are unique per double.
////
//// Two limits are inherent rather than chosen. A JSON integer past 2^53
//// has already become the nearest double by the time JavaScript's parser
//// hands it over, so two such integers that share a double are one value
//// on that target and are encoded as one here; the difference is not lost
//// by this module, it is gone before this module is reached. And an
//// infinity or a NaN has no JSON spelling at all — see `non_finite`.

import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/string

import watershed/json_ot.{type JsonValue, type Num}

/// The largest integer a JavaScript number holds exactly, 2^53 - 1. Above
/// it the two targets no longer hold the same value, only the same double.
const exact_int_ceiling = 9_007_199_254_740_991

/// The largest finite double. An infinity is above it and a NaN compares
/// false against everything, so one comparison sorts out both.
const largest_finite = 1.7976931348623157e308

/// How far the decimal point may sit from the first significant digit
/// before the layout switches to an exponent: 21 digits to its right, 6
/// zeros to its left. Both come from ECMAScript's `Number::toString`,
/// which is one target's rule and now the rule here — the choice is
/// arbitrary, owning it is not.
const plain_point_ceiling = 21

const plain_point_floor = -6

/// What a non-finite number encodes as. JSON has no spelling for an
/// infinity or a NaN, and `to_string` has to stay total and keep emitting
/// parseable JSON, so it writes what `JSON.stringify` writes: `null`.
///
/// Nothing decoded from JSON can carry one — a parser has no syntax to
/// produce it — so this is reachable only from locally built state, and
/// only on JavaScript, where float arithmetic overflows to an infinity
/// instead of raising as it does on Erlang. The cost is that such a value
/// hashes like a null.
const non_finite = "null"

/// Encode a value canonically: sorted object keys, one escaping policy,
/// one number rendering. Array order is preserved — a caller that holds a
/// set in an array must order it first, with `sorted`.
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

/// Order two strings by their UTF-8 bytes on every target, which
/// `string.compare` does not do.
pub fn compare(left: String, right: String) -> Order {
  bit_array.compare(<<left:utf8>>, <<right:utf8>>)
}

/// Order an array that encodes a set, by each element's canonical bytes.
/// Each element is encoded once, not once per comparison.
pub fn sorted(items: List(JsonValue)) -> List(JsonValue) {
  items
  |> list.map(fn(item) { #(to_string(item), item) })
  |> list.sort(fn(left, right) { compare(left.0, right.0) })
  |> list.map(fn(pair) { pair.1 })
}

/// Render a number so that every JSON spelling of one value gives one
/// text — `1`, `1.0`, and `1e0` all become `1` — while two values that
/// differ keep two texts.
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

/// An integer past JavaScript's exact range. JavaScript's parser replaced
/// it with the nearest double before any of this ran, so the double is
/// what gets rendered — on both targets, so both agree.
fn wide_int_to_string(value: Int) -> String {
  case as_double(value) {
    Ok(double) -> float_to_string(double)
    Error(_) -> non_finite
  }
}

/// The conversion goes through the integer's own decimal text rather than
/// `int.to_float`, which raises `badarg` on Erlang for an integer outside
/// the double range — and a remote snapshot can carry one, where nothing
/// is allowed to crash. `float.parse` reports that as an error instead.
/// On JavaScript the integer is already a double and prints as one,
/// exponent and all, which `parse` reads back unchanged; one that
/// overflowed prints as `Infinity`, which it refuses.
fn as_double(value: Int) -> Result(Float, Nil) {
  float.parse(with_point(int.to_string(value)))
}

/// `float.parse` insists on a decimal point in the mantissa, and no
/// integer printing puts one there.
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

/// One spelling per finite double, on every target. Both targets print the
/// shortest digits that read back as the same double — that much they
/// agree on — and then lay them out by their own rule, which they do not
/// agree on. So the digits are taken and the layout is redone here.
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

/// A finite double as the layout needs it: `digits` are its shortest
/// round-trip significant digits, with no leading or trailing zero, and
/// the value is `0.<digits> × 10^point`. Every spelling of zero, signed or
/// not, is `Zero` — JSON has one zero.
type Decimal {
  Decimal(negative: Bool, digits: String, point: Int)
  Zero
}

/// Read one target's float printing — `1.0e-5` on Erlang, `0.00001` on
/// JavaScript for the same double — as digits and a decimal point
/// position, discarding the layout the target chose.
///
/// An `Error` means text no float printing produces; the caller encodes
/// that as `non_finite` rather than guessing at a number.
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

/// JavaScript writes `e+21` and Erlang writes `e21`; the sign of a
/// positive exponent is layout too.
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

/// Place the decimal point: digits padded with zeros while it sits past
/// them, a point among them while it sits inside, `0.` and zeros while it
/// sits just left of them, and an exponent once it is further out than
/// that.
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
