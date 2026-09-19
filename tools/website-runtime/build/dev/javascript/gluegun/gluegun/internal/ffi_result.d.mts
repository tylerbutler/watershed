import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $error from "../../gluegun/error.d.mts";
import type * as $internal from "../../gluegun/internal.d.mts";

export function decode_request_result(
  result: _.Result<$dynamic.Dynamic$, $dynamic.Dynamic$>
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function decode_nil_result(
  result: _.Result<$dynamic.Dynamic$, $dynamic.Dynamic$>
): _.Result<undefined, $error.GluegunError$>;
