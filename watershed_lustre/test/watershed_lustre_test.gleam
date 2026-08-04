//// Test entrypoint for the package's pure modules.
////
//// The root `watershed` package runs on startest, but startest's dependency
//// tree pins `gleam_stdlib < 1.0` while this package (and lustre) are on 1.x,
//// so the two cannot share a harness. gleeunit resolves cleanly here and needs
//// no assertion library on Gleam 1.11+ — plain `assert` is enough.

import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}
