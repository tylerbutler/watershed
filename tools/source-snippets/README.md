# source-snippets

Internal Gleam tool that reads an explicit snippet configuration, validates
named source markers, and writes an ignored JSON manifest for the
documentation frontend.

## What it knows, and what it does not

The tool has four jobs: decode a versioned configuration, scan the configured
roots for marker directives, extract and compose the configured ranges, and
write a deterministic manifest atomically.

Everything else belongs to whoever runs it. The package has no idea what a
documentation site is. It does not know Astro, GitHub URLs, page names, syntax
themes, or which snippet is allowed to be hand-written. It takes paths,
extensions, ids, and markers, and it hands back JSON. Any Gleam project can
point it at its own sources with its own configuration.

Watershed's own configuration lives in `website/snippets.json`, and every
watershed path in this README — `website/`, `examples/`, the `just` recipe —
is an example of one project's choices, not a rule the package enforces. The
same is true of the `excludeDirs` values: `build` is where the Gleam compiler
happens to put its copies, and a project that generates elsewhere names its
own directories.

## Command

```
gleam run -m source_snippets/cli -- <config.json> <output.json>
```

`<config.json>` is a versioned JSON configuration file.
`<output.json>` is the path for the generated manifest. The parent directory
is created if absent. Output is written atomically: the tool writes to a
`.tmp` sibling first and renames only after generation and encoding succeed.
A valid existing output file is never removed on failure.

## Exit status and errors

The command exits `0` after a manifest is written, and `1` after printing one
line to stderr. Each line names the file, and where one applies, the snippet
id and the marker id, so the failure can be found without rerunning anything:

```
error: expected 2 arguments (config output), got 1
error: cannot read config: website/snippets.json
error: invalid config JSON
error: marker root not found: src
error: source file not found: examples/demo/src/demo.gleam
error: snippet "demo": invalid source path: ../../etc/passwd
error: snippet "demo": marker "demo-start" not found in examples/demo/src/demo.gleam
error: snippet "demo": extraction failed
error: marker "demo-start" found in both src/a.gleam and build/a.gleam
error: marker "demo-start" in src/a.gleam is not referenced by any snippet
error: marker "demo-start" has its pair in src/a.gleam and an extra end directive in src/b.gleam
error: cannot write output: website/src/generated/snippets.json
```

A failing run leaves the previous manifest in place, so a build that already
had good output keeps it.

## Configuration schema

```json
{
  "version": 1,
  "sourceRoot": "..",
  "markerRoots": ["src", "test", "examples"],
  "extensions": [".gleam", ".mjs"],
  "excludeDirs": ["build", ".git", "node_modules"],
  "snippets": [
    {
      "id": "guide-connect-start",
      "sourcePath": "examples/retro_tutorial/src/retro_tutorial.gleam",
      "language": "gleam",
      "markers": ["guide-connect-start"],
      "separator": "\n\n"
    },
    {
      "id": "guide-connect-schema",
      "sourcePath": "examples/retro_tutorial/src/retro_tutorial/schema.gleam",
      "language": "gleam",
      "wholeFile": true
    }
  ]
}
```

- `sourceRoot` — path relative to the configuration file.
- `markerRoots` — directories relative to `sourceRoot` to scan for markers.
- `extensions` — file extensions to scan (e.g. `".gleam"`, `".mjs"`).
- `excludeDirs` — directory *names* the scan skips at any depth. Optional;
  defaults to none. An entry with a path separator is rejected, because the
  scan compares each entry against a single directory name.
- `snippets[].id` — unique output identifier.
- `snippets[].sourcePath` — path relative to `sourceRoot`.
- `snippets[].language` — language tag for the frontend.
- `snippets[].markers` — ordered list of marker ids to join.
- `snippets[].separator` — string placed between joined ranges (default `"\n\n"`).
- `snippets[].wholeFile` — `true` selects the complete file instead of ranges.

### Choosing roots and exclusions

Prefer a few broad `markerRoots` over a long list of narrow ones: a narrow list
goes stale, and a source directory nobody listed is a source directory nobody
checks for broken markers. Broad roots reach generated output too, where the
compiler keeps copies of the same marked source under `build/`. Those copies
carry the same marker ids and read as duplicates, so name the generated and
vendored directories in `excludeDirs`.

### Selecting the code

A snippet selects marker ranges or a whole file. It cannot do both, and it
cannot do neither. The decoder rejects an entry that names `markers` and
`wholeFile` together, an entry that names neither, a `wholeFile` set to
anything other than `true`, and a `separator` on a whole-file entry — a
listing joins nothing, so a separator there has no meaning.

Use `wholeFile` when the sheet shows a complete module. A marker range cannot
hold one: `gleam format` moves a start marker written above a `////` module
doc comment below it, which drops the header out of the range.

A whole-file snippet reads the file and removes the marker directive lines.
The formatter puts a blank line on each side of a directive line that stands
between two items, so one of those two blank lines goes with the directive
and the seam keeps a single blank line. Every other byte stays, including the
last newline of the file.

A whole-file snippet is not a marker reference. It names no marker, so a
marker pair inside the file still needs a snippet that quotes it by name, or
the generator reports an orphan.

## Marker placement

Markers are inline comments placed directly around the code to extract.
Put the start marker above the item's doc comment when the doc comment
belongs in the snippet:

```gleam
// docs:snippet-start guide-connect-start
/// Public API doc comment.
pub fn connect(addr: String) -> Result(Socket, Error) {
  // ...
}
// docs:snippet-end guide-connect-start
```

`gleam format` binds a comment to the item below it, so a start marker written
between an attribute and its definition moves above the attribute, and the
attribute becomes part of the range. A start marker written above a module
doc comment (`////`) moves below it. Format the file and read the result
before you trust a boundary.

Marker ranges must not overlap or nest. When one sheet quotes a whole block
and another quotes part of it, split the block into adjacent ranges and let
the wider snippet list them in order.

Both marker lines are stripped from the extracted code. Leading whitespace
is dedented uniformly. Trailing blank lines before the end marker are removed.

Each marker id must be unique across all scanned files. Every discovered
marker must be referenced by a snippet (orphan markers are an error). A marker
may be referenced by more than one snippet.

The scan reads start directives and end directives, so an end directive with
no start is found too. When a snippet quotes it, the generator reports the
missing start; when nothing quotes it, the generator reports an orphan.

The scan asks the question one file at a time. A file that holds both halves
of a pair owns the marker. An end directive elsewhere with that same name is
a tail with no head, and the generator names both files. When the two halves
sit in different files and neither file holds a complete pair, the generator
reports the missing end against the file that opened the range.

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
    },
    "guide-connect-schema": {
      "code": "//// Typed schema.\n\npub fn title() { ... }\n",
      "language": "gleam",
      "sourcePath": "examples/retro_tutorial/src/retro_tutorial/schema.gleam",
      "origin": { "kind": "file" }
    }
  }
}
```

`origin.kind` is `"source"` for composed marker ranges and `"file"` for a
whole-file listing. A file listing carries no `markers`, because it selected
none.

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
