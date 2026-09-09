import { core } from "./core.mjs";

export function validateRequest(request) {
  return core().validate_request(request);
}

export function queryIndex(index, request) {
  return core().query_index(index, request);
}

export function renderText(view) {
  return core().render_text(view);
}
