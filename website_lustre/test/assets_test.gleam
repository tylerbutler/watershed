import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

pub fn images_match_production_test() {
  ["favicon.svg", "og.png"]
  |> list.each(fn(file) {
    let assert Ok(original) = simplifile.read_bits("../website/public/" <> file)
    simplifile.read_bits("assets/" <> file) |> should.equal(Ok(original))
  })
}

pub fn fonts_and_styles_are_complete_test() {
  [
    "styles/site.css", "styles/guide-race.css", "fonts/archivo/wdth.css",
    "fonts/archivo/LICENSE", "fonts/jetbrains-mono/400.css",
    "fonts/jetbrains-mono/400-italic.css", "fonts/jetbrains-mono/700.css",
    "fonts/jetbrains-mono/LICENSE",
  ]
  |> list.each(fn(file) {
    let assert Ok(_) = simplifile.read("assets/" <> file) as file
  })
  let assert Ok(hashes) = simplifile.read("test/fixtures/font-hashes.txt")
  hashes
  |> string.trim
  |> string.split("\n")
  |> list.each(fn(line) {
    let assert [expected, path] = string.split(line, "  ")
    let assert Ok(bytes) = simplifile.read_bits("assets/" <> path) as path
    crypto.hash(crypto.Sha256, bytes)
    |> bit_array.base16_encode
    |> string.lowercase
    |> should.equal(expected)
  })
}
