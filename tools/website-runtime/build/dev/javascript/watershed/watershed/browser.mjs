/// <reference types="./browser.d.mts" />
import * as $id from "../watershed/id.mjs";
import { documentFromUrl as document_from_url } from "./browser_ffi.mjs";

/**
 * Return the document named by the current URL, or create a new name and add
 * it as the `document` query parameter.
 *
 * The prefix keeps the documents of different examples distinct. If you open
 * the resulting URL in another tab or another browser, you join the same
 * document.
 */
export function document_on_navigate(prefix) {
  return document_from_url((prefix + "-") + $id.uuid_v4());
}
