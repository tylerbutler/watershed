//// Refresh inputs from the Node I/O shell.

import code_map/cache
import code_map/codec
import code_map/config
import code_map/model
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set

pub fn previous(
  value: decode.Dynamic,
) -> Result(Option(model.Index), model.Error) {
  decode.run(value, decode.optional(codec.index()))
  |> result.map_error(fn(_) { model.CacheError })
}

fn candidate() -> decode.Decoder(cache.Candidate) {
  use status <- decode.field("status", decode.string)
  case status {
    "pending" -> {
      use path <- decode.field("path", codec.path())
      use language <- decode.field("language", codec.language())
      use hash <- decode.field("hash", codec.hash())
      decode.success(cache.ReadyToParse(cache.ParseJob(path, language, hash)))
    }
    _ -> decode.map(codec.file(), cache.Classified)
  }
}

pub fn candidates(
  value: decode.Dynamic,
) -> Result(List(cache.Candidate), model.Error) {
  let decoder =
    codec.checked(
      decode.list(candidate()),
      fn(candidates) {
        set.size(set.from_list(list.map(candidates, cache.candidate_path)))
        == list.length(candidates)
      },
      "unique candidate paths",
    )
  decode.run(value, decoder)
  |> result.map_error(fn(_) { model.RefreshError("invalid file candidates") })
}

fn parse_result(path: String) -> decode.Decoder(model.ParseResult) {
  use symbols <- decode.field("symbols", decode.list(codec.symbol(path)))
  use diagnostics <- decode.field(
    "diagnostics",
    decode.list(codec.checked(
      codec.diagnostic(),
      fn(d) { d.path == path },
      "matching diagnostic path",
    )),
  )
  use regions <- decode.field("skippedRegions", decode.list(codec.region()))
  decode.success(model.ParseResult(symbols, diagnostics, regions))
}

pub fn results(
  value: decode.Dynamic,
) -> Result(List(#(String, model.ParseResult)), model.Error) {
  let decoder = {
    use path <- decode.field("path", codec.path())
    use result <- decode.field("result", parse_result(path))
    decode.success(#(path, result))
  }
  decode.run(value, decode.list(decoder))
  |> result.map_error(fn(_) { model.ParserError("invalid parse results") })
}

pub fn encode_jobs(plan: cache.RefreshPlan) -> json.Json {
  cache.jobs(plan)
  |> json.array(fn(job) {
    json.object([
      #("path", json.string(job.path)),
      #("language", json.string(codec.language_name(job.language))),
      #("hash", json.string(job.hash)),
    ])
  })
}

pub type Options {
  Options(root: String, rebuild: Bool, config: Option(model.Config))
}

pub fn options(
  root: decode.Dynamic,
  value: decode.Dynamic,
) -> Result(Options, model.Error) {
  use root <- result.try(
    decode.run(
      root,
      codec.checked(decode.string, fn(s) { s != "" }, "root directory"),
    )
    |> result.map_error(fn(_) { model.RefreshError("invalid root directory") }),
  )
  let configuration = {
    use raw <- decode.then(codec.config())
    case config.validate(raw) {
      Ok(config) -> decode.success(config)
      Error(_) -> decode.failure(raw, "valid configuration")
    }
  }
  let decoder = {
    use _ <- decode.then(codec.known_fields(["rebuild", "config"]))
    use rebuild <- decode.optional_field(
      "rebuild",
      False,
      codec.undefined_default(decode.bool, False),
    )
    use config <- decode.optional_field(
      "config",
      None,
      codec.undefined_default(decode.map(configuration, Some), None),
    )
    decode.success(Options(root, rebuild, config))
  }
  decode.run(value, decoder)
  |> result.map_error(fn(_) {
    model.RefreshError("invalid index options or config")
  })
}
