//// Plans parse reuse and assembles a complete on-disk snapshot.

import code_map/model
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string

pub type ParseJob {
  ParseJob(path: String, language: model.Language, hash: String)
}

pub type Candidate {
  ReadyToParse(ParseJob)
  Classified(model.FileEntry)
}

type Slot {
  Retained(model.FileEntry)
  Pending(ParseJob)
}

pub opaque type RefreshPlan {
  RefreshPlan(tool_hash: String, config_hash: String, slots: List(Slot))
}

pub fn candidate_path(candidate: Candidate) -> String {
  case candidate {
    ReadyToParse(job) -> job.path
    Classified(file) -> file.path
  }
}

pub fn prepare(
  previous: Option(model.Index),
  candidates: List(Candidate),
  tool_hash: String,
  config_hash: String,
) -> RefreshPlan {
  let cached = case previous {
    Some(index)
      if index.tool_hash == tool_hash && index.config_hash == config_hash
    -> dict.from_list(list.map(index.files, fn(file) { #(file.path, file) }))
    _ -> dict.new()
  }
  let slots =
    candidates
    |> list.sort(fn(a, b) {
      string.compare(candidate_path(a), candidate_path(b))
    })
    |> list.map(fn(candidate) {
      case candidate {
        Classified(file) -> Retained(file)
        ReadyToParse(job) -> {
          let hash = Some(job.hash)
          case dict.get(cached, job.path) {
            Ok(file) if file.status == model.Indexed && file.hash == hash ->
              Retained(file)
            _ -> Pending(job)
          }
        }
      }
    })
  RefreshPlan(tool_hash, config_hash, slots)
}

pub fn jobs(plan: RefreshPlan) -> List(ParseJob) {
  list.filter_map(plan.slots, fn(slot) {
    case slot {
      Pending(job) -> Ok(job)
      Retained(_) -> Error(Nil)
    }
  })
}

pub fn finish(
  plan: RefreshPlan,
  results: List(#(String, model.ParseResult)),
) -> Result(model.Index, model.Error) {
  let pending = set.from_list(list.map(jobs(plan), fn(job) { job.path }))
  let parsed = dict.from_list(results)
  use _ <- result.try(
    case
      dict.size(parsed) == list.length(results)
      && dict.size(parsed) == set.size(pending)
      && list.all(dict.keys(parsed), fn(path) { set.contains(pending, path) })
    {
      True -> Ok(Nil)
      False ->
        Error(model.RefreshError(
          "missing, duplicate, or unexpected parser results",
        ))
    },
  )
  use files <- result.try(
    list.try_map(plan.slots, fn(slot) {
      case slot {
        Retained(file) -> Ok(file)
        Pending(job) -> {
          use parsed <- result.try(
            dict.get(parsed, job.path)
            |> result.map_error(fn(_) {
              model.RefreshError("missing parser result for " <> job.path)
            }),
          )
          let #(status, symbols) = case parsed.diagnostics {
            [] -> #(model.Indexed, parsed.symbols)
            _ -> #(model.ParseError, [])
          }
          Ok(model.FileEntry(
            job.path,
            Some(job.language),
            status,
            None,
            Some(job.hash),
            symbols,
            parsed.diagnostics,
            parsed.skipped_regions,
          ))
        }
      }
    }),
  )
  Ok(model.Index(
    plan.tool_hash,
    plan.config_hash,
    !list.any(files, fn(file) { model.failed(file.status) }),
    files,
  ))
}
