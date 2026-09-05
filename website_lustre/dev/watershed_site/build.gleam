import argv
import envoy
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import watershed_site
import watershed_site/error
import watershed_site/route
import watershed_site/system

pub fn main() -> Nil {
  case argv.load().arguments {
    [] ->
      run("./dist", "./build/static", "../website/src/generated/snippets.json")
    [output] ->
      run(output, "./build/static", "../website/src/generated/snippets.json")
    [output, assets] ->
      run(output, assets, "../website/src/generated/snippets.json")
    [output, assets, manifest] -> run(output, assets, manifest)
    _ -> {
      io.println_error(
        "Expected at most three arguments: output, assets, and snippet manifest.",
      )
      system.halt(1)
    }
  }
}

fn run(output: String, assets: String, manifest: String) -> Nil {
  let revision = envoy.get("GITHUB_SHA") |> result.unwrap("main")
  case watershed_site.build(output, assets, manifest, revision) {
    Ok(Nil) ->
      io.println(
        "Generated "
        <> string.join(
          list.map(route.all(), fn(route) { route.path <> "/" }),
          ", ",
        )
        <> " in "
        <> output,
      )
    Error(reason) -> {
      io.println_error(error.describe(reason))
      system.halt(1)
    }
  }
}
