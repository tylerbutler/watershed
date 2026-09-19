import type * as _ from "../../gleam.d.mts";

export const empty_list: _.List<any>;

export const error_nil: _.Result<any, undefined>;

export function singleton_list<TCZ>(item: TCZ): _.List<TCZ>;
