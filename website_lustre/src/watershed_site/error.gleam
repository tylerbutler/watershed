pub type BuildError {
  DuplicateRoute(
    path: String,
    first_content_path: String,
    second_content_path: String,
  )
  CannotRead(path: String, reason: String)
  InvalidFrontmatter(path: String, reason: String)
  InvalidContent(path: String, reason: String)
  InvalidSnippetManifest(path: String, reason: String)
  MissingSnippet(path: String, id: String)
  UnknownComponent(path: String, name: String)
  RawHtml(path: String)
  SiteGenerationFailed(reason: String)
}

pub fn describe(error: BuildError) -> String {
  case error {
    DuplicateRoute(path, first, second) ->
      "Duplicate route " <> path <> ": " <> first <> " and " <> second
    CannotRead(path, reason) -> "Cannot read " <> path <> ": " <> reason
    InvalidFrontmatter(path, reason) ->
      path <> ": Invalid frontmatter: " <> reason
    InvalidContent(path, reason) -> path <> ": Invalid content: " <> reason
    InvalidSnippetManifest(path, reason) ->
      path <> ": Invalid snippet manifest: " <> reason
    MissingSnippet(path, id) -> path <> ": Missing snippet: " <> id
    UnknownComponent(path, name) -> path <> ": Unknown component: " <> name
    RawHtml(path) -> path <> ": Raw HTML is not permitted."
    SiteGenerationFailed(reason) -> "Site generation failed: " <> reason
  }
}
