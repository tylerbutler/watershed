import code_map/config
import code_map/model
import gleam/option.{None, Some}
import gleeunit/should

pub fn directory_boundaries_test() {
  config.beneath("src/a.ts", "src") |> should.be_true
  config.beneath("srcish/a.ts", "src") |> should.be_false
  config.relative_path("../src/a.ts") |> should.be_false
  config.relative_path("C:/src/a.ts") |> should.be_false
  config.relative_path("space \nname.ts") |> should.be_true
}

pub fn consumer_exclusions_test() {
  let config = model.Config(["build"], ["vendor"])
  config.classify(config, "nested/build/a.ts", ".ts", config.Regular)
  |> should.equal(config.Exclude(
    Some(model.TypeScript),
    "Config exclusion: build",
  ))
  config.classify(model.Config([], []), "build/a.ts", ".ts", config.Regular)
  |> should.equal(config.ReadSource(model.TypeScript))
  config.classify(config, "notes.md", ".md", config.Symlink)
  |> should.equal(config.Exclude(None, "Symlink (not followed)"))
}
