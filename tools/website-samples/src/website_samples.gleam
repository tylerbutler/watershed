//// Compiled Gleam fixtures for the watershed website.
////
//// Each submodule holds one or more API samples that the website extracts
//// through `?raw` imports and named markers. The package targets JavaScript
//// and compiles against the live watershed and watershed_lustre APIs, so a
//// drift in the real API breaks the website build.
////
//// This package is not an application example. It exists only so that the
//// synthetic snippets on comparison and runtime pages are compiled Gleam
//// instead of handwritten strings.

pub fn placeholder() -> Nil {
  Nil
}
