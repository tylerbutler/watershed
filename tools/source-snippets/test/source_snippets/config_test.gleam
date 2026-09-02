import gleam/string
import gleeunit/should
import source_snippets/config.{
  Config, ConflictingSelection, DuplicateId, EmptyExtensions, EmptyId,
  EmptyLanguage, EmptyMarkers, EmptyPath, EmptyRoot, EmptySourceRoot, FieldError,
  JsonSyntax, MarkerSelection, MissingSelection, RepeatedMarker,
  SeparatorWithWholeFile, SnippetSpec, UnsupportedExtension, UnsupportedVersion,
  WholeFileNotTrue, WholeFileSelection, decode_config,
}

// ---------------------------------------------------------------------------
// Valid config
// ---------------------------------------------------------------------------

pub fn decode_minimal_valid_config_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"my-snippet\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"my-snippet\"]
      }
    ]
  }"
  let result = decode_config(json)
  result
  |> should.be_ok
  |> should.equal(
    Config(
      version: 1,
      source_root: "..",
      marker_roots: ["src"],
      extensions: [".gleam"],
      snippets: [
        SnippetSpec(
          id: "my-snippet",
          source_path: "src/main.gleam",
          language: "gleam",
          selection: MarkerSelection(markers: ["my-snippet"], separator: "\n\n"),
        ),
      ],
    ),
  )
}

pub fn decode_config_with_custom_separator_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"joined\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"a\", \"b\"],
        \"separator\": \"\\n// ...\\n\"
      }
    ]
  }"
  let result = decode_config(json)
  let config = should.be_ok(result)
  let assert [spec] = config.snippets
  spec.selection
  |> should.equal(MarkerSelection(markers: ["a", "b"], separator: "\n// ...\n"))
}

// ---------------------------------------------------------------------------
// Selection: markers or whole file, never both and never neither
// ---------------------------------------------------------------------------

pub fn decode_whole_file_snippet_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"wholeFile\": true
      }
    ]
  }"
  let config = should.be_ok(decode_config(json))
  let assert [spec] = config.snippets
  spec.selection |> should.equal(WholeFileSelection)
}

pub fn decode_whole_file_false_rejected_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"wholeFile\": false
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(WholeFileNotTrue("listing"))
}

pub fn decode_both_selectors_rejected_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"a\"],
        \"wholeFile\": true
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(ConflictingSelection("listing"))
}

pub fn decode_both_selectors_rejected_when_whole_file_is_false_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"a\"],
        \"wholeFile\": false
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(ConflictingSelection("listing"))
}

pub fn decode_no_selector_rejected_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\"
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(MissingSelection("listing"))
}

pub fn decode_separator_with_whole_file_rejected_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"wholeFile\": true,
        \"separator\": \"\\n\\n\"
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(SeparatorWithWholeFile("listing"))
}

pub fn decode_wrong_type_whole_file_rejected_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"listing\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"wholeFile\": \"yes\"
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> {
        should.be_true(
          string.contains(field, "snippets")
          && string.contains(field, "wholeFile"),
        )
      }
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_config_with_multiple_extensions_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\", \"test\"],
    \"extensions\": [\".gleam\", \".mjs\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"s1\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_ok
}

// ---------------------------------------------------------------------------
// JSON syntax
// ---------------------------------------------------------------------------

pub fn decode_invalid_json_test() {
  decode_config("{not valid json}")
  |> should.be_error
  |> should.equal(JsonSyntax("invalid JSON"))
}

// ---------------------------------------------------------------------------
// Version errors
// ---------------------------------------------------------------------------

pub fn decode_unsupported_version_test() {
  let json =
    "{
    \"version\": 99,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(UnsupportedVersion(99))
}

pub fn decode_version_zero_test() {
  let json =
    "{
    \"version\": 0,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(UnsupportedVersion(0))
}

// ---------------------------------------------------------------------------
// Source root errors
// ---------------------------------------------------------------------------

pub fn decode_empty_source_root_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptySourceRoot)
}

pub fn decode_whitespace_source_root_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"   \",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptySourceRoot)
}

// ---------------------------------------------------------------------------
// Marker root errors
// ---------------------------------------------------------------------------

pub fn decode_empty_root_entry_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\", \"\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyRoot)
}

// ---------------------------------------------------------------------------
// Extension errors
// ---------------------------------------------------------------------------

pub fn decode_empty_extensions_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyExtensions)
}

pub fn decode_unsupported_extension_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\", \".py\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(UnsupportedExtension(".py"))
}

// ---------------------------------------------------------------------------
// Snippet id errors
// ---------------------------------------------------------------------------

pub fn decode_empty_snippet_id_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"x\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyId(0))
}

pub fn decode_duplicate_snippet_ids_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"dup\",
        \"sourcePath\": \"src/a.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"x\"]
      },
      {
        \"id\": \"dup\",
        \"sourcePath\": \"src/b.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"y\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(DuplicateId("dup"))
}

// ---------------------------------------------------------------------------
// Snippet field errors
// ---------------------------------------------------------------------------

pub fn decode_empty_source_path_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"\",
        \"language\": \"gleam\",
        \"markers\": [\"s1\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyPath("s1"))
}

pub fn decode_empty_language_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"\",
        \"markers\": [\"s1\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyLanguage("s1"))
}

pub fn decode_empty_markers_list_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": []
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(EmptyMarkers("s1"))
}

pub fn decode_repeated_marker_in_snippet_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"a\", \"b\", \"a\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> should.equal(RepeatedMarker("s1", "a"))
}

// ---------------------------------------------------------------------------
// Missing required fields
// ---------------------------------------------------------------------------

pub fn decode_missing_version_field_test() {
  let json =
    "{
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("version")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_missing_snippets_field_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"]
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("snippets")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Wrong-type top-level fields
// ---------------------------------------------------------------------------

pub fn decode_wrong_type_version_test() {
  let json =
    "{
    \"version\": \"one\",
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("version")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_wrong_type_source_root_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": 42,
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("sourceRoot")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_wrong_type_marker_roots_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": \"src\",
    \"extensions\": [\".gleam\"],
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("markerRoots")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_wrong_type_extensions_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": \".gleam\",
    \"snippets\": []
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> field |> should.equal("extensions")
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Wrong-type nested snippet fields
// ---------------------------------------------------------------------------

pub fn decode_wrong_type_snippet_id_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": 123,
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": [\"x\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> {
        // Field path should include snippet context.
        should.be_true(
          string.contains(field, "snippets") && string.contains(field, "id"),
        )
      }
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_wrong_type_snippet_markers_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"sourcePath\": \"src/main.gleam\",
        \"language\": \"gleam\",
        \"markers\": \"not-an-array\"
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> {
        should.be_true(
          string.contains(field, "snippets")
          && string.contains(field, "markers"),
        )
      }
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}

pub fn decode_missing_snippet_source_path_test() {
  let json =
    "{
    \"version\": 1,
    \"sourceRoot\": \"..\",
    \"markerRoots\": [\"src\"],
    \"extensions\": [\".gleam\"],
    \"snippets\": [
      {
        \"id\": \"s1\",
        \"language\": \"gleam\",
        \"markers\": [\"x\"]
      }
    ]
  }"
  decode_config(json)
  |> should.be_error
  |> fn(err) {
    case err {
      FieldError(field, _) -> {
        should.be_true(
          string.contains(field, "snippets")
          && string.contains(field, "sourcePath"),
        )
      }
      other -> {
        let _ = other
        should.fail()
      }
    }
  }
}
