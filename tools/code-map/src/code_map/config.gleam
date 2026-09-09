//// Repository-relative path rules.

import gleam/list
import gleam/string

pub fn relative_path(path: String) -> Bool {
  let drive = case string.to_utf_codepoints(path) {
    [letter, colon, ..] -> {
      let letter = string.utf_codepoint_to_int(letter)
      string.utf_codepoint_to_int(colon) == 58
      && {
        { letter >= 65 && letter <= 90 } || { letter >= 97 && letter <= 122 }
      }
    }
    _ -> False
  }
  path != ""
  && !drive
  && !string.contains(path, "\\")
  && !string.contains(path, "\u{0}")
  && list.all(string.split(path, "/"), fn(part) {
    part != "" && part != "." && part != ".."
  })
}

pub fn beneath(path: String, prefix: String) -> Bool {
  path == prefix || string.starts_with(path, prefix <> "/")
}
