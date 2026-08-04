// Caret restoration for `watershed_lustre/textarea`.
//
// Everything else the component needs from the DOM it reads declaratively,
// through event decoders. This is the one thing with no declarative form:
// writing a selection back into a `<textarea>` is an imperative call that has
// to land after the vdom has patched the element's `value` and before the
// browser paints it. `effect.before_paint` is exactly that window, and it hands
// over the app root (or a shadow root) to search from — so several instances,
// and a future custom-element wrapper, both resolve to the right element.

export function restore_selection(root, instance, start, end) {
  const selector = `[data-watershed-textarea="${instance}"]`;
  const element =
    (root && typeof root.querySelector === "function"
      ? root.querySelector(selector)
      : null) ?? document.querySelector(selector);

  if (!element) return undefined;

  // Placing a caret in an element the user is not in would steal focus, which
  // is a worse outcome than a caret that drifted while they were elsewhere.
  const scope = element.getRootNode?.() ?? document;
  if (scope.activeElement !== element) return undefined;

  // Writing back the selection the element already has still fires `select` in
  // some browsers, which would loop straight back into re-anchoring.
  if (element.selectionStart === start && element.selectionEnd === end) {
    return undefined;
  }

  element.setSelectionRange(start, end);
  return undefined;
}
