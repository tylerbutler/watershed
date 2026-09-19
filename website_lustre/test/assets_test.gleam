import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

pub fn images_match_contract_test() {
  [
    #(
      "favicon.svg",
      "50f5ef327569849e1390205aed7f94829154fbc0e3b64010b58de6f155a224fe",
    ),
    #(
      "og.png",
      "aaebdb7e74b35cba2540d3c6cd65fe356262de0cd33d788517b1b6aed8e4863c",
    ),
  ]
  |> list.each(fn(asset) {
    let assert Ok(bytes) = simplifile.read_bits("assets/" <> asset.0)
    crypto.hash(crypto.Sha256, bytes)
    |> bit_array.base16_encode
    |> string.lowercase
    |> should.equal(asset.1)
  })
}

pub fn fonts_and_styles_are_complete_test() {
  [
    "styles/site.css", "styles/guide-race.css", "scripts/field-notes.js",
    "scripts/motion.js", "scripts/guide-index.js", "scripts/concept-index.js",
    "fonts/archivo/wdth.css", "fonts/archivo/LICENSE",
    "fonts/jetbrains-mono/400.css", "fonts/jetbrains-mono/400-italic.css",
    "fonts/jetbrains-mono/700.css", "fonts/jetbrains-mono/LICENSE",
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

pub fn motion_is_visible_by_default_and_reduced_motion_safe_test() {
  let assert Ok(source) = simplifile.read("assets/scripts/motion.js")
  [
    "prefers-reduced-motion: reduce",
    "\"IntersectionObserver\" in window",
    "document.querySelectorAll(\"[data-reveal]\")",
    "duration: 560",
    "delay: Math.min(Number(el.dataset.revealIndex) * 90, 450)",
    "fill: \"backwards\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(source, expected) as expected
  })
  string.contains(source, ".hidden") |> should.be_false()
  ["guide-index.js", "concept-index.js"]
  |> list.each(fn(file) {
    let assert Ok(wrapper) = simplifile.read("assets/scripts/" <> file)
    string.contains(wrapper, "import { initReveals } from \"./motion.js\";")
    |> should.be_true()
    string.contains(wrapper, "initReveals();") |> should.be_true()
  })
}
