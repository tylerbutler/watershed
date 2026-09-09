import code_map/model
import code_map/query
import code_map/query_codec
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn bounded_coverage_test() {
  let files =
    list.repeat(Nil, 60)
    |> list.index_map(fn(_, n) {
      let path = "group" <> int.to_string(n) <> "/a.ts"
      model.FileEntry(
        path,
        Some(model.TypeScript),
        model.ParseError,
        None,
        None,
        [],
        [model.Diagnostic(path, "bad", None)],
        [],
      )
    })
  let index = model.Index("", "", False, files)
  let assert Ok(view) = query.run(index, model.Overview)
  view.diagnostic_count |> should.equal(60)
  list.length(view.diagnostics) |> should.equal(50)
  let assert model.Summary(60, 0, groups, 60) = view.content
  list.length(groups) |> should.equal(50)
}

pub fn nullish_pagination_and_invalid_path_test() {
  json.parse("{\"command\":\"files\",\"limit\":null}", query_codec.request())
  |> should.equal(Ok(model.Files(None, model.Page(50, 0))))
  json.parse("{\"command\":\"files\",\"path\":null}", query_codec.request())
  |> should.be_error
}
