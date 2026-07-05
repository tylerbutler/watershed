// Field-notes tutorial mode for the live DDS demo.
//
// When enabled, rough-notation marks annotate the *active* structure using the
// live demo's color grammar: ink marks a sequenced/converged fact, magenta marks
// a pending/optimistic one. Marks are hand-drawn on purpose — they read as an
// inspector's annotation over the precise printed survey sheet, not as chrome.
//
// Two models coexist:
//   • Static structures (map / counter / pn) draw one or two persistent marks on
//     client A plus a bracket on the op log, re-drawn (pulsed) as ops converge.
//   • G-counter is event-driven: it draws no static marks and instead *flashes*
//     each element as it changes through the flow — the origin's tally + total
//     (magenta, pending), the log line as it is sequenced, then the tally +
//     total on each replica as the delta lands (ink) — via transient marks that
//     remove themselves.
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

  // Transient "flash" marks highlight an element *as it changes* during the
  // animation, then remove themselves. They live in their own registry so the
  // persistent recipe marks (clear/render) never disturb an in-flight flash.
  let flashes = [];
  function flash(el, config, ttl = 1300) {
    if (!el) return;
    const a = annotate(el, {
      animate: !prefersReducedMotion(),
      animationDuration: duration(450),
      ...config,
    });
    a.show();
    const entry = { a, timer: null };
    entry.timer = setTimeout(() => {
      a.remove();
      flashes = flashes.filter((f) => f !== entry);
    }, duration(ttl));
    flashes.push(entry);
  }
  function clearFlashes() {
    for (const f of flashes) {
      clearTimeout(f.timer);
      f.a.remove();
    }
    flashes = [];
  }

  // Circle the two elements a G-counter change touches on one replica: the
  // author's own tally and the derived total. Magenta while the value is a
  // pending local edit; ink once the delta has been sequenced/applied.
  function flashGCounterChange(clientEl, authorId, pending) {
    if (!clientEl) return;
    const color = pending ? magenta() : ink();
    flash(clientEl.querySelector(`[data-gcounter-author="${authorId}"]`), {
      type: "circle",
      color,
      strokeWidth: 2,
      padding: 5,
    });
    flash(clientEl.querySelector("[data-gcounter-value]"), {
      type: "circle",
      color,
      strokeWidth: 2,
      padding: 7,
    });
  }

  // Highlight the newest op-log line as it is sequenced.
  function flashLog() {
    flash(
      rig.querySelector("[data-op-log] li"),
      { type: "box", color: ink(), strokeWidth: 2, padding: 3 },
      1400,
    );
  }

  // The op log is the live narration — a new line prints as each op is
  // sequenced. Bracketing the log block draws the eye to the running
  // explanation while the flow animates. Drawn for every structure (the log is
  // structure-agnostic) and re-drawn on each pulse, so it tracks the animation.
  function markNarration() {
    const log = rig.querySelector("[data-op-log]");
    if (!log || log.childElementCount === 0) return;
    mark(log, {
      type: "bracket",
      brackets: ["left"],
      color: ink(),
      strokeWidth: 2.5,
      padding: 8,
    });
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
    // G-counter is fully event-driven: no static marks. Every element that
    // changes during the flow is circled as it changes — the author tally and
    // total on the origin (magenta, pending), the log line as it is sequenced,
    // then the tally and total on each replica as the delta lands (ink).
    gcounter() {
      setNote(
        "G-counter — each client owns one tally; the total is their sum. Watch every value that changes get circled as the delta flows: magenta while pending on the origin, ink as it is sequenced and applied to each replica.",
      );
    },
  };

  function render(ddsId) {
    if (ddsId !== currentDds) clearFlashes();
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
        "Field notes cover Shared map, Shared counter, PN counter, and G-counter so far — switch to one of those to see its behavior marked up.",
      );
    }
    // The persistent narration bracket is for the static structures; G-counter
    // flashes its log line per op instead.
    if (ddsId !== "gcounter") markNarration();
  }

  function setActive(on) {
    active = on;
    if (!on) clearFlashes();
    render(currentDds);
  }

  return {
    render,
    setActive,
    get active() {
      return active;
    },
    flashGCounterChange,
    flashLog,
    // Redraw the active structure's marks with the draw-in animation, so they
    // appear in sync with the demo's flow when an op converges.
    pulse() {
      if (active) render(currentDds);
    },
    // Rough-notation marks are absolutely positioned; redraw after a resize.
    reflow() {
      if (active) render(currentDds);
    },
  };
}
