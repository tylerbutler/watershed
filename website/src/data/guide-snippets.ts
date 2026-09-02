// ──────────────────────────────────────────────────────────────────────────
// Guide snippet registry — the guide sheets' source-backed listings that no
// page can extract for itself.
//
// The one entry here is a whole-file listing. A marker range cannot hold a
// complete module: the Gleam formatter moves a directive written above the
// `////` module doc comment below it, so the header would drop out of the
// listing. `website/snippets.json` declares the same id with `wholeFile`,
// and the Gleam generator produces the same string.
//
// Transitional. The generated manifest replaces the body of this registry;
// the pages that read it keep asking for the same ids.
// ──────────────────────────────────────────────────────────────────────────
import { snippetFromWholeFile, type Snippet } from "../lib/snippet.ts";

// ── Raw source imports (Gleam — compiled examples) ─────────────────────────
import retroSchemaSource from "../../../examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam?raw";

// ── Source paths (repo-relative, for citation and links) ───────────────────
const paths = {
  retroSchema:
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam",
} as const;

/** Every guide snippet the sheets cannot extract themselves, keyed by id. */
export const guideSnippets: Record<string, Snippet> = {
  // guide/connect — the tutorial board's whole schema module. The
  // foundations schema sheet quotes `title` from it by marker, so the
  // directives are dropped from this listing.
  "guide-connect-schema": snippetFromWholeFile(
    retroSchemaSource, paths.retroSchema, "gleam",
  ),
};
