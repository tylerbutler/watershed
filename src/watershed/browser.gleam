//// Browser-specific helpers for collaborative document routing.

@target(javascript)
import watershed/ids

@target(javascript)
/// Return the document named by the current URL, or create a new name and add
/// it as the `document` query parameter.
///
/// The prefix keeps documents from different examples distinct. Reusing the
/// resulting URL in another tab or browser joins the same document.
pub fn document_on_navigate(prefix: String) -> String {
  document_from_url(prefix <> "-" <> ids.uuid_v4())
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "documentFromUrl")
fn document_from_url(generated: String) -> String
