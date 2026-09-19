import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

type AssetSize {
  AssetSize(path: String, raw: Int, gzip: Int)
}

@external(javascript, "./browser/site.mjs", "gzipSize")
fn gzip_size(bytes: BitArray) -> Int

const raw_budget = 2_200_000

const gzip_budget = 520_000

pub fn generated_client_assets_stay_within_budget_test() {
  let paths = client_asset_paths("build/static")
  let sizes =
    paths
    |> list.map(fn(path) {
      let assert Ok(bytes) = simplifile.read_bits(path) as path
      AssetSize(path, bit_array.byte_size(bytes), gzip_size(bytes))
    })
  let raw = list.fold(sizes, 0, fn(total, asset) { total + asset.raw })
  let gzip = list.fold(sizes, 0, fn(total, asset) { total + asset.gzip })
  let entries =
    sizes
    |> list.map(fn(asset) {
      asset.path
      <> ": "
      <> int.to_string(asset.raw)
      <> " raw / "
      <> int.to_string(asset.gzip)
      <> " gzip"
    })
    |> string.join(with: "\n")
  let report =
    "Generated client assets exceed the budget: "
    <> int.to_string(raw)
    <> "/"
    <> int.to_string(raw_budget)
    <> " raw, "
    <> int.to_string(gzip)
    <> "/"
    <> int.to_string(gzip_budget)
    <> " gzip\n"
    <> entries
  let assert True = raw <= raw_budget && gzip <= gzip_budget as report
}

fn client_asset_paths(directory: String) {
  let assert Ok(entries) = simplifile.read_directory(directory)
  list.flat_map(entries, fn(entry) {
    let path = directory <> "/" <> entry
    case simplifile.is_directory(path) {
      Ok(True) -> client_asset_paths(path)
      _ ->
        case string.ends_with(path, ".js") || string.ends_with(path, ".css") {
          True -> [path]
          False -> []
        }
    }
  })
}

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
