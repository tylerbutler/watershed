import gleam/float
import gleam/json
import gleam/order
import startest/expect

import watershed/canonical_json
import watershed/json_ot.{
  NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}

fn encoded(value: json_ot.JsonValue) -> String {
  canonical_json.to_string(value)
}

/// `U+1D11E` is above `U+FFFD` by code point and by UTF-8 bytes, but below
/// it as a UTF-16 surrogate pair — which is exactly what `string.compare`
/// sees on JavaScript and not what it sees on Erlang. Both targets run this
/// file, so a target-dependent comparison fails it on one of them.
pub fn strings_order_by_utf8_bytes_on_every_target_test() {
  canonical_json.compare("𝄞", "\u{FFFD}") |> expect.to_equal(order.Gt)
  canonical_json.compare("\u{FFFD}", "𝄞") |> expect.to_equal(order.Lt)
  canonical_json.compare("全", "𝄞") |> expect.to_equal(order.Lt)
  canonical_json.compare("Ａ", "全") |> expect.to_equal(order.Gt)
  canonical_json.compare("a", "a") |> expect.to_equal(order.Eq)
  canonical_json.compare("a", "ab") |> expect.to_equal(order.Lt)
  canonical_json.compare("", "a") |> expect.to_equal(order.Lt)
}

pub fn object_keys_emit_in_byte_order_test() {
  encoded(
    VObject([
      #("𝄞", VNull),
      #("\u{FFFD}", VBool(True)),
      #("全", VNumber(NInt(1))),
      #("b", VString("x")),
    ]),
  )
  |> expect.to_equal("{\"b\":\"x\",\"全\":1,\"\u{FFFD}\":true,\"𝄞\":null}")
}

/// Array order is state, so it is never touched by the encoder — only by a
/// caller that knows the array holds a set.
pub fn arrays_keep_their_order_until_sorted_test() {
  encoded(VArray([VString("b"), VString("a")]))
  |> expect.to_equal("[\"b\",\"a\"]")

  // Sorted by the bytes of each element's encoding, so a quoted string
  // (`0x22`) sorts ahead of a digit (`0x32`).
  canonical_json.sorted([
    VString("𝄞"),
    VString("\u{FFFD}"),
    VString("全"),
    VNumber(NInt(2)),
  ])
  |> VArray
  |> encoded
  |> expect.to_equal("[\"全\",\"\u{FFFD}\",\"𝄞\",2]")
}

/// The same JSON number decodes as a float on Erlang and an integer on
/// JavaScript, and `json.float` spells one value two ways across the two.
/// One value must give one text.
pub fn one_number_has_one_spelling_test() {
  encoded(VNumber(NInt(1))) |> expect.to_equal("1")
  encoded(VNumber(NFloat(1.0))) |> expect.to_equal("1")
  encoded(VNumber(NFloat(-0.0))) |> expect.to_equal("0")
  encoded(VNumber(NInt(0))) |> expect.to_equal("0")
  encoded(VNumber(NInt(-7))) |> expect.to_equal("-7")
  encoded(VNumber(NFloat(-7.0))) |> expect.to_equal("-7")
  encoded(VNumber(NFloat(100.0))) |> expect.to_equal("100")
  encoded(VNumber(NFloat(100.5))) |> expect.to_equal("100.5")

  // Erlang prints an integral double in exponent form from 1.0e16 up;
  // JavaScript only from 1.0e21. The layout is redone here, so neither
  // threshold shows through.
  encoded(VNumber(NFloat(1.0e16))) |> expect.to_equal("10000000000000000")
  encoded(VNumber(NFloat(1.0e21))) |> expect.to_equal("1e21")
  encoded(VNumber(NInt(float.truncate(1.0e21)))) |> expect.to_equal("1e21")
}

/// The band Erlang writes as `1.0e-5` and JavaScript writes as `0.00001`:
/// same double, same shortest digits, different layout. Both targets run
/// this file, so a spelling taken from either one's printing fails on the
/// other.
pub fn small_floats_have_one_spelling_test() {
  encoded(VNumber(NFloat(1.0e-4))) |> expect.to_equal("0.0001")
  encoded(VNumber(NFloat(1.0e-5))) |> expect.to_equal("0.00001")
  encoded(VNumber(NFloat(1.0e-6))) |> expect.to_equal("0.000001")
  encoded(VNumber(NFloat(9.9e-5))) |> expect.to_equal("0.000099")
  encoded(VNumber(NFloat(1.234e-5))) |> expect.to_equal("0.00001234")
  encoded(VNumber(NFloat(-1.0e-5))) |> expect.to_equal("-0.00001")
  encoded(VNumber(NFloat(-9.9e-5))) |> expect.to_equal("-0.000099")

  // The band is not a rounding: every double in it keeps its own text.
  encoded(VNumber(NFloat(1.0e-5)))
  |> expect.to_not_equal(encoded(VNumber(NFloat(1.0000000000000002e-5))))
}

/// Where the layout switches between plain digits and an exponent, on both
/// sides of zero. These are the four values a rule of this shape can only
/// get wrong one at a time.
pub fn layout_boundaries_hold_on_every_target_test() {
  encoded(VNumber(NFloat(1.0e-6))) |> expect.to_equal("0.000001")
  encoded(VNumber(NFloat(9.999999e-7))) |> expect.to_equal("9.999999e-7")
  encoded(VNumber(NFloat(1.0e-7))) |> expect.to_equal("1e-7")
  encoded(VNumber(NFloat(1.0e20))) |> expect.to_equal("100000000000000000000")
  encoded(VNumber(NFloat(1.0e21))) |> expect.to_equal("1e21")
  encoded(VNumber(NFloat(1.0e22))) |> expect.to_equal("1e22")
  encoded(VNumber(NFloat(-1.0e21))) |> expect.to_equal("-1e21")

  // The extremes of the type, where a decimal exponent is the only
  // layout either target will print.
  encoded(VNumber(NFloat(5.0e-324))) |> expect.to_equal("5e-324")
  encoded(VNumber(NFloat(2.2250738585072014e-308)))
  |> expect.to_equal("2.2250738585072014e-308")
  encoded(VNumber(NFloat(1.7976931348623157e308)))
  |> expect.to_equal("1.7976931348623157e308")
}

/// Past 2^53 an integer is a double on JavaScript before any encoder sees
/// it, and Erlang's exact integer has to be spelled the same way or the
/// two hash apart. Every value here is built by arithmetic rather than
/// written: the literals are not representable on JavaScript, which is
/// the point, and the compiler warns about writing them.
pub fn wide_integers_and_doubles_share_one_spelling_test() {
  let two_to_the_53 = 9_007_199_254_740_991 + 1

  encoded(VNumber(NInt(two_to_the_53))) |> expect.to_equal("9007199254740992")
  encoded(VNumber(NInt(-1 * two_to_the_53)))
  |> expect.to_equal("-9007199254740992")

  // An integer whose double has more exact decimal digits than its
  // shortest round-trip spelling: the double is 12345678901234567168,
  // and writing that out is what the two targets used to disagree about.
  let wide = float.truncate(1.2345678901234567e19)
  encoded(VNumber(NInt(wide))) |> expect.to_equal("12345678901234567000")
  encoded(VNumber(NInt(-1 * wide))) |> expect.to_equal("-12345678901234567000")
  encoded(VNumber(NFloat(1.2345678901234567e19)))
  |> expect.to_equal(encoded(VNumber(NInt(wide))))

  // Non-round integers, arrived at by arithmetic that rounds the same way
  // on both targets: exactly on Erlang, then once into a double; already
  // in doubles on JavaScript.
  encoded(VNumber(NInt(two_to_the_53 * 1000 + 123)))
  |> expect.to_equal("9007199254740992000")
  encoded(VNumber(NInt(two_to_the_53 * 3 + 1)))
  |> expect.to_equal("27021597764222976")
  encoded(VNumber(NInt(1_234_567_890_123_456 * 10 + 7)))
  |> expect.to_equal("12345678901234568")

  // Two integers this size that share a double share a spelling. That is
  // not this encoder rounding them together: JavaScript's parser merged
  // them before the encoder ran, and nothing downstream can tell them
  // apart on that target.
  encoded(VNumber(NInt(two_to_the_53 + 1)))
  |> expect.to_equal(encoded(VNumber(NInt(two_to_the_53))))

  // Distinct doubles stay distinct, which is what the spelling has to
  // preserve. 4096 is two units in the last place at this magnitude, so
  // both targets land on a genuinely different double.
  encoded(VNumber(NInt(two_to_the_53 + 2)))
  |> expect.to_not_equal(encoded(VNumber(NInt(two_to_the_53))))
  encoded(VNumber(NInt(wide + 4096)))
  |> expect.to_not_equal(encoded(VNumber(NInt(wide))))
  encoded(VNumber(NInt(wide + 4096)))
  |> expect.to_equal("12345678901234571000")
}

pub fn distinct_numbers_keep_distinct_spellings_test() {
  encoded(VNumber(NFloat(1.5))) |> expect.to_equal("1.5")
  encoded(VNumber(NFloat(0.1))) |> expect.to_equal("0.1")
  encoded(VNumber(NFloat(1.5)))
  |> expect.to_not_equal(encoded(VNumber(NFloat(1.6))))
  encoded(VNumber(NFloat(1.0)))
  |> expect.to_not_equal(encoded(VNumber(NFloat(1.0000000000000002))))
  encoded(VNumber(NInt(1))) |> expect.to_not_equal(encoded(VNumber(NInt(2))))
  encoded(VNumber(NFloat(1.0000000000000002)))
  |> expect.to_equal("1.0000000000000002")
}

/// `gleam/json` escapes a control character as `\u000B` on Erlang and
/// `\u000b` on JavaScript, so the escaping policy is owned here: lowercase
/// hex, the short forms where JSON defines them, and every printable
/// character — astral ones included — left raw.
pub fn strings_escape_by_one_policy_test() {
  encoded(VString("a\u{000B}b")) |> expect.to_equal("\"a\\u000bb\"")
  encoded(VString("\u{0000}\u{001F}")) |> expect.to_equal("\"\\u0000\\u001f\"")
  encoded(VString("\"\\")) |> expect.to_equal("\"\\\"\\\\\"")
  encoded(VString("\n\t\r\f")) |> expect.to_equal("\"\\n\\t\\r\\f\"")
  encoded(VString("𝄞全Ａ")) |> expect.to_equal("\"𝄞全Ａ\"")
  encoded(VString("")) |> expect.to_equal("\"\"")
}

pub fn scalars_encode_as_json_test() {
  encoded(VNull) |> expect.to_equal("null")
  encoded(VBool(True)) |> expect.to_equal("true")
  encoded(VBool(False)) |> expect.to_equal("false")
  encoded(VObject([])) |> expect.to_equal("{}")
  encoded(VArray([])) |> expect.to_equal("[]")
}

/// An integer past the double range reaches this encoder from any remote
/// snapshot carrying one. It is a different thing on each target — an
/// exact integer Erlang cannot convert without raising `badarg`, an
/// infinity on JavaScript, where `float.to_string` writes `Infinity.0` and
/// `json.parse` would then choke on the digest bytes. JSON can spell
/// neither, so both encode as `null`: total, valid, and the same on both.
pub fn a_number_outside_the_double_range_encodes_as_null_test() {
  encoded(VNumber(NInt(power_of_ten(400)))) |> expect.to_equal("null")
  encoded(VNumber(NInt(-1 * power_of_ten(400)))) |> expect.to_equal("null")

  // And it stays JSON: the encoded document parses on either target.
  let document =
    VObject([#("n", VNumber(NInt(power_of_ten(400)))), #("ok", VBool(True))])
  encoded(document) |> expect.to_equal("{\"n\":null,\"ok\":true}")
  json.parse(encoded(document), json_ot.decoder())
  |> expect.to_equal(Ok(VObject([#("n", VNull), #("ok", VBool(True))])))
}

fn power_of_ten(exponent: Int) -> Int {
  case exponent {
    0 -> 1
    _ -> 10 * power_of_ten(exponent - 1)
  }
}
