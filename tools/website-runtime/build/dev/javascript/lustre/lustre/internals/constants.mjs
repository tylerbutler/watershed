/// <reference types="./constants.d.mts" />
import { Error, List$Empty$const as $List$Empty$const, prepend as listPrepend } from "../../gleam.mjs";

export const empty_list = $List$Empty$const;

export const error_nil = /* @__PURE__ */ new Error(undefined);

export function singleton_list(item) {
  return listPrepend(item, empty_list);
}
