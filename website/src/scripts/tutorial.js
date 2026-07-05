// Field-notes tutorial mode for the live DDS demo.
//
// When enabled, rough-notation marks are drawn over the *active* structure to
// point at its one defining characteristic, using the same color grammar as the
// live demo: ink marks a sequenced/converged fact worth noticing, magenta marks
// the pending/optimistic bit. Marks are hand-drawn on purpose — they read as an
// inspector's annotation over the precise printed survey sheet, not as chrome.
//
// Discipline: at most one or two marks per structure, drawn on client A only, so
// each mark keeps meaning. The proof set is map / counter / pn; other structures
// show a caption pointing at the supported three until their recipes land.
import { annotate } from "rough-notation";

const cssVar = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();

export function createFieldNotes({ rig, prefersReducedMotion, duration }) {
  let annotations = [];
  let noteEl = null;
  let active = false;
  let currentDds = null;

  const ink = () => cssVar("--ink");
  const magenta = () => cssVar("--overprint");

  // Query inside client A's panel only — one replica carries every mark.
  const q = (sel) => rig.querySelector(`[data-client="a"] ${sel}`);

  function ensureNote() {
    if (noteEl) return noteEl;
    noteEl = document.createElement("p");
    noteEl.className = "field-note";
    noteEl.setAttribute("role", "note");
    rig.before(noteEl);
    return noteEl;
  }

  function setNote(text) {
    const el = ensureNote();
    el.textContent = text;
    el.hidden = false;
  }

  function mark(el, config) {
    if (!el) return;
    const a = annotate(el, {
      animate: !prefersReducedMotion(),
      animationDuration: duration(700),
      ...config,
    });
    annotations.push(a);
    a.show();
  }

  function clear() {
    for (const a of annotations) a.remove();
    annotations = [];
  }

  // Each recipe draws 1–2 marks and sets the margin caption. The mark points at
  // *where on the sheet* the merge rule is visible; the caption names the rule.
  const RECIPES = {
    map() {
      setNote(
        "Shared map — one key, last write wins. The circled cell holds a whole value: a race replaces it outright, it never merges.",
      );
      mark(q(".dds-map tbody tr:first-child [data-value]"), {
        type: "circle",
        color: ink(),
        strokeWidth: 2,
        padding: 6,
      });
    },
    counter() {
      setNote(
        "Shared counter — increments commute. Each bracketed ± is a delta that prints magenta until sequenced; the circled total converges on the sum, nothing overwritten.",
      );
      mark(q(".dds-counter [data-counter-value]"), {
        type: "circle",
        color: ink(),
        strokeWidth: 2,
        padding: 8,
      });
      mark(q(".dds-counter .counter-actions"), {
        type: "bracket",
        brackets: ["bottom"],
        color: magenta(),
        strokeWidth: 3,
        padding: 6,
      });
    },
    pn() {
      setNote(
        "PN counter — net = fill − cut. The boxed ledger holds two monotone tallies that only ever grow; re-delivering a delta is absorbed, so it counts exactly once.",
      );
      mark(q(".dds-pn .pn-ledger"), {
        type: "box",
        color: ink(),
        strokeWidth: 2,
        padding: 4,
      });
      mark(q(".dds-pn [data-pn-value]"), {
        type: "circle",
        color: ink(),
        strokeWidth: 2,
        padding: 8,
      });
    },
  };

  function render(ddsId) {
    currentDds = ddsId;
    clear();
    if (!active) {
      if (noteEl) noteEl.hidden = true;
      return;
    }
    const recipe = RECIPES[ddsId];
    if (recipe) {
      recipe();
    } else {
      setNote(
        "Field notes cover Shared map, Shared counter, and PN counter so far — switch to one of those to see its defining behavior marked up.",
      );
    }
  }

  function setActive(on) {
    active = on;
    render(currentDds);
  }

  return {
    render,
    setActive,
    get active() {
      return active;
    },
    // Rough-notation marks are absolutely positioned; redraw after a resize.
    reflow() {
      if (active) render(currentDds);
    },
  };
}
