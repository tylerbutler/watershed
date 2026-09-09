import code_map/cache
import code_map/model
import gleam/option.{None, Some}
import gleeunit/should

pub fn retry_failed_parse_test() {
  let prior =
    model.FileEntry(
      "a.ts",
      Some(model.TypeScript),
      model.ParseError,
      None,
      Some("hash"),
      [],
      [model.Diagnostic("a.ts", "bad", None)],
      [],
    )
  let job = cache.ParseJob("a.ts", model.TypeScript, "hash")
  let plan =
    cache.prepare(
      Some(model.Index("tool", "config", False, [prior])),
      [cache.ReadyToParse(job)],
      "tool",
      "config",
    )
  cache.jobs(plan) |> should.equal([job])
  let assert Ok(index) =
    cache.finish(plan, [#("a.ts", model.ParseResult([], [], []))])
  index.complete |> should.be_true
  let assert [file] = index.files
  file.status |> should.equal(model.Indexed)
}

pub fn duplicate_parser_result_test() {
  let plan =
    cache.prepare(
      None,
      [cache.ReadyToParse(cache.ParseJob("a.ts", model.TypeScript, "hash"))],
      "tool",
      "config",
    )
  let parsed = #("a.ts", model.ParseResult([], [], []))
  cache.finish(plan, [parsed, parsed]) |> should.be_error
}
