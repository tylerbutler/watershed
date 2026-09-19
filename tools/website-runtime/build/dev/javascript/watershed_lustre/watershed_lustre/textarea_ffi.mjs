// DOM reads and writes for `watershed_lustre/textarea`.
//
// Everything the component can read declaratively it reads through event
// decoders. These two have no declarative form. Writing a selection back into a
// `<textarea>` is an imperative call that has to land after the vdom has
// patched the element's `value` and before the browser paints it; measuring
// where a peer's cursor falls means asking the layout engine a question only it
// can answer. `effect.before_paint` is exactly that window, and it hands over
// the app root (or a shadow root) to search from — so several instances, and a
// future custom-element wrapper, both resolve to the right element.
//
// `identity` is the coercion behind `dynamic_to_dom_root`: lustre hands the root over
// as a bare `Dynamic`, and this module relabels it as the opaque `DomRoot`
// instead of naming `restore_selection`/`measure_cursors`'s parameter after
// `gleam/dynamic`. The value crosses unchanged; only its Gleam-side type name
// changes.
export const identity = (value) => value;

const find = (root, attribute, instance) => {
  const selector = `[${attribute}="${instance}"]`;
  return (
    (root && typeof root.querySelector === "function"
      ? root.querySelector(selector)
      : null) ?? document.querySelector(selector)
  );
};

export function restore_selection(root, instance, start, end) {
  const element = find(root, "data-watershed-textarea", instance);

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

// Properties that decide where a glyph lands. Copied from the live textarea
// onto the mirror at measure time rather than written once in CSS, because the
// caller owns the textarea's appearance and may change it at any point — a
// mirror styled at mount would silently drift from the element it models.
// `boxSizing` and `width` are deliberately absent — both are derived below.
const MIRRORED = [
  "paddingTop",
  "paddingRight",
  "paddingBottom",
  "paddingLeft",
  "borderTopWidth",
  "borderRightWidth",
  "borderBottomWidth",
  "borderLeftWidth",
  "fontFamily",
  "fontSize",
  "fontWeight",
  "fontStyle",
  "fontVariant",
  "fontStretch",
  "letterSpacing",
  "wordSpacing",
  "lineHeight",
  "textIndent",
  "textTransform",
  "textRendering",
  "tabSize",
  "whiteSpace",
  "overflowWrap",
  "wordBreak",
];

// Measure where each peer's range falls, in pixels relative to the textarea's
// border box and corrected for its scroll offset.
//
// A `<textarea>`'s text lives in shadow DOM the page cannot reach, so there is
// no way to ask the browser where offset 37 is. The mirror sidesteps that: the
// same string, laid out the same way, in an element a DOM `Range` can address.
// `getClientRects` then returns one rect per line box, which is exactly the
// shape a wrapped selection needs, and a collapsed range still reports its
// position through `getBoundingClientRect`.
export function measure_cursors(root, instance, request) {
  const textarea = find(root, "data-watershed-textarea", instance);
  const mirror = find(root, "data-watershed-mirror", instance);
  if (!textarea || !mirror) return "[]";

  let ranges;
  try {
    ranges = JSON.parse(request);
  } catch {
    return "[]";
  }
  if (!Array.isArray(ranges) || ranges.length === 0) return "[]";

  const computed = getComputedStyle(textarea);
  for (const property of MIRRORED) mirror.style[property] = computed[property];

  // Sit the mirror exactly on the textarea's border box. They share a wrapper,
  // but the textarea is in flow and may carry a margin, so the wrapper's origin
  // is not the textarea's — and a mirror offset by even a few pixels reports
  // every cursor at the wrong place.
  mirror.style.top = `${textarea.offsetTop}px`;
  mirror.style.left = `${textarea.offsetLeft}px`;

  // Width decides where lines wrap, so it has to be the width the *text* gets,
  // not the element's. `clientWidth` already excludes the border and any
  // scrollbar; taking the padding off leaves the content box. Stated as
  // content-box explicitly, because `getComputedStyle().width` reports content
  // width regardless of the element's own `box-sizing` and copying both would
  // otherwise shrink the mirror by the padding.
  const px = (value) => Number.parseFloat(value) || 0;
  mirror.style.boxSizing = "content-box";
  mirror.style.width = `${
    textarea.clientWidth - px(computed.paddingLeft) - px(computed.paddingRight)
  }px`;
  // Grow downwards rather than scroll, so every line is laid out and
  // measurable even where the textarea itself has scrolled past it.
  mirror.style.height = "auto";
  mirror.style.overflow = "hidden";

  const text = mirror.firstChild;
  // No text node means an empty document: nothing to point at.
  if (!text || text.nodeType !== 3) {
    return JSON.stringify(
      ranges.map(({ id }) => ({ id, caret: null, bands: [] })),
    );
  }

  // Report in the overlay's coordinate system, which is the wrapper's padding
  // box — the wrapper carries no border or padding of its own, so its bounding
  // rect is that box. Subtracting the textarea's scroll is what makes a cursor
  // travel with the text it belongs to.
  const frame = mirror.parentElement.getBoundingClientRect();
  const shift = (rect) => ({
    x: rect.left - frame.left - textarea.scrollLeft,
    y: rect.top - frame.top - textarea.scrollTop,
    width: rect.width,
    height: rect.height,
  });

  const limit = text.data.length;
  const clamp = (n) => Math.max(0, Math.min(limit, typeof n === "number" ? n : 0));

  const measured = ranges.map(({ id, start, end }) => {
    const from = clamp(start);
    const to = clamp(end);
    const range = document.createRange();

    try {
      range.setStart(text, Math.min(from, to));
      range.setEnd(text, Math.max(from, to));
    } catch {
      return { id, caret: null, bands: [] };
    }

    if (from === to) {
      // A collapsed range has no client rects, but it does have a bounding
      // box — zero-width, at the position a caret would sit.
      return { id, caret: shift(range.getBoundingClientRect()), bands: [] };
    }

    const bands = Array.from(range.getClientRects())
      // Wrapping can emit degenerate rects at line ends; drawing them puts
      // stray slivers in the margin.
      .filter((rect) => rect.width > 0 && rect.height > 0)
      .map(shift);

    return { id, caret: null, bands };
  });

  return JSON.stringify(measured);
}
