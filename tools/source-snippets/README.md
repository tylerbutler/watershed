# source-snippets

Internal Gleam tool that reads an explicit snippet configuration, validates
named source markers, and writes an ignored JSON manifest for the
documentation frontend.

## Command

```
gleam run -m source_snippets/cli -- <config.json> <output.json>
```

`<config.json>` is a versioned JSON configuration file.
`<output.json>` is the path for the generated manifest. The parent directory
is created if absent. Output is written atomically: the tool writes to a
`.tmp` sibling first and renames only after generation and encoding succeed.
A valid existing output file is never removed on failure.

## Configuration schema

```json
{
  "version": 1,
  "sourceRoot": "..",
  "markerRoots": ["src", "test", "examples"],
  "extensions": [".gleam", ".mjs"],
  "snippets": [
    {
      "id": "guide-connect-start",
      "sourcePath": "examples/retro_tutorial/src/retro_tutorial.gleam",
      "language": "gleam",
      "markers": ["guide-connect-start"],
      "separator": "\n\n"
    }
  ]
}
```

- `sourceRoot` — path relative to the configuration file.
- `markerRoots` — directories relative to `sourceRoot` to scan for markers.
- `extensions` — file extensions to scan (e.g. `".gleam"`, `".mjs"`).
- `snippets[].id` — unique output identifier.
- `snippets[].sourcePath` — path relative to `sourceRoot`.
- `snippets[].language` — language tag for the frontend.
- `snippets[].markers` — ordered list of marker ids to join.
- `snippets[].separator` — string placed between joined ranges (default `"\n\n"`).

## Marker placement

Markers are inline comments placed directly around the code to extract.
Place them outside Gleam doc comments so the extracted code compiles cleanly:

```gleam
/// Public API doc comment.
// docs:snippet-start guide-connect-start
pub fn connect(addr: String) -> Result(Socket, Error) {
  // ...
}
// docs:snippet-end guide-connect-start
```

Both marker lines are stripped from the extracted code. Leading whitespace
is dedented uniformly. Trailing blank lines before the end marker are removed.

Each marker id must be unique across all scanned files. Every discovered
marker pair must be referenced by exactly one snippet (orphan markers are an
error). A marker may be referenced by more than one snippet.

## Generated manifest

`<output.json>` is not committed and is listed in `.gitignore`.

```json
{
  "version": 1,
  "snippets": {
    "guide-connect-start": {
      "code": "pub fn connect(addr: String) -> Result(Socket, Error) { ... }",
      "language": "gleam",
      "sourcePath": "examples/retro_tutorial/src/retro_tutorial.gleam",
      "origin": {
        "kind": "source",
        "markers": ["guide-connect-start"]
      }
    }
  }
}
```

Entries are sorted by id for deterministic output.

## Build integration

Run the generator before `pnpm build` and `pnpm dev`. Example `just` recipe:

```just
snippets:
    cd tools/source-snippets && gleam run -m source_snippets/cli -- \
        ../../website/snippets.json \
        ../../website/src/generated/snippets.json
```

The generated file path should be added to `.gitignore`.
