//// TP1 convergence property for the json0 transform matrix.
////
//// The json0 kernel rides the spillway central sequencer, so it only needs
//// TP1 (single-pair transform property): for any doc and any concurrent op
//// pair `a`, `b` generated against that doc,
////
////   apply(apply(doc, a), transform(b, a, Lft))
////     == apply(apply(doc, b), transform(a, b, Rgt))
////
//// This mirrors `bootstrapTransform`/`transformX` in ottypes/json0. Documents
//// and ops come from the shared `json_ot_gen` port of json0's fuzzer; we
//// assert convergence over a `FUZZ_ITERATIONS`-sized qcheck run.

import gleam/int
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz
import watershed/json_ot.{type JsonValue, type Op, Lft, Rgt}
import watershed/json_ot_gen

fn check_tp1(doc: JsonValue, a: Op, b: Op) -> Result(Bool, String) {
  use sa <- try_map(json_ot.apply(doc, a), "apply(doc, a)")
  use sb <- try_map(json_ot.apply(doc, b), "apply(doc, b)")
  use ba <- try_map(json_ot.transform(b, a, Lft), "transform(b, a, Lft)")
  use ab <- try_map(json_ot.transform(a, b, Rgt), "transform(a, b, Rgt)")
  use left <- try_map(json_ot.apply(sa, ba), "apply(apply(doc,a), b/a)")
  use right <- try_map(json_ot.apply(sb, ab), "apply(apply(doc,b), a/b)")
  Ok(left == right)
}

fn try_map(
  res: Result(t, e),
  label: String,
  then: fn(t) -> Result(Bool, String),
) -> Result(Bool, String) {
  case res {
    Ok(v) -> then(v)
    Error(err) -> Error(label <> " failed: " <> string.inspect(err))
  }
}

pub fn tp1_converges_test() {
  let config = kernel_fuzz.config_from_env()
  qcheck.run(config, qcheck.uniform_int(), fn(seed) {
    let rng = json_ot_gen.new_rng(seed)
    let #(doc, rng) = json_ot_gen.random_doc(rng)
    let #(a, rng) = json_ot_gen.gen_op(doc, rng)
    let #(b, _rng) = json_ot_gen.gen_op(doc, rng)
    case check_tp1(doc, a, b) {
      Ok(True) -> Nil
      other -> {
        let detail = case other {
          Ok(False) -> "results diverged"
          Error(msg) -> msg
          Ok(True) -> ""
        }
        panic as {
          "TP1 violated ("
          <> detail
          <> ")\n  seed="
          <> int.to_string(seed)
          <> "\n  doc="
          <> string.inspect(doc)
          <> "\n  a="
          <> string.inspect(a)
          <> "\n  b="
          <> string.inspect(b)
        }
      }
    }
  })
}
