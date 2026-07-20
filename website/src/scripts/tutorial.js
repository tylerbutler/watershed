// Field-notes tutorial mode for the live DDS demo.
//
// When enabled, rough-notation marks annotate the *active* structure using the
// live demo's color grammar: ink marks a sequenced/converged fact, magenta marks
// a pending/optimistic one. Marks are hand-drawn on purpose — they read as an
// inspector's annotation over the precise printed survey sheet, not as chrome.
//
// Two models coexist:
//   • Static structures (e.g. Shared map) draw one or two persistent marks on
//     client A plus a bracket on the op log, re-drawn (pulsed) as ops converge.
//   • Counters (Shared counter / PN counter / G-counter) are event-driven: they
//     draw no static marks and instead *flash* each value element as it changes
//     through the flow — magenta while pending on the origin, then ink as the op
//     is sequenced and applied to each replica — plus a box on the log line as it
//     is sequenced. Flash marks are transient and remove themselves.
//
// To add a structure to the event-driven set, register its live value selectors
// in CHANGE_TARGETS and add a caption-only recipe. See docs/field-notes.md.
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

  // Structures whose field notes are event-driven: instead of static marks, the
  // listed elements are snapshotted before an op is applied and any whose text
  // changed are flashed. One selector set per structure — list every element
  // that carries a live value the user should watch converge.
  const CHANGE_TARGETS = {
    map: [".dds-map tbody [data-value]"],
    counter: ["[data-counter-value]"],
    pn: ["[data-pn-value]", "[data-pn-fill]", "[data-pn-cut]"],
    gcounter: ["[data-gcounter-value]", "[data-gcounter-author]"],
    orset: ["[data-orset-value]"],
    gset: ["[data-gset-value]"],
    twopset: ["[data-twopset-value]"],
    ormap: ["[data-ormap-value]"],
    claims: ["[data-holder]"],
    registers: ["[data-register-atomic]", "[data-register-lww]"],
    ordered: ["[data-ordered-queue]", "[data-ordered-jobs]"],
    tasks: ["[data-task-assignee]", "[data-task-waiters]"],
    pact: ["[data-pact-accepted]", "[data-pact-pending]"],
  };

  function isEventDriven(ddsId) {
    return Object.prototype.hasOwnProperty.call(CHANGE_TARGETS, ddsId);
  }

  // Snapshot the current text of every live-value element in one client's panel,
  // keyed by node (render mutates these nodes in place, so identity is stable).
  function snapshot(ddsId, clientEl) {
    const snap = new Map();
    const sels = CHANGE_TARGETS[ddsId];
    if (!sels || !clientEl) return snap;
    for (const sel of sels)
      for (const el of clientEl.querySelectorAll(sel))
        snap.set(el, el.textContent);
    return snap;
  }

  // After the op is applied, circle every value element whose text differs from
  // the snapshot. Magenta while the change is a pending local edit; ink once the
  // op is sequenced/applied.
  function flashChanged(ddsId, clientEl, snap, pending) {
    const sels = CHANGE_TARGETS[ddsId];
    if (!sels || !clientEl) return;
    const color = pending ? magenta() : ink();
    for (const sel of sels)
      for (const el of clientEl.querySelectorAll(sel))
        if (snap.get(el) !== el.textContent)
          flash(el, { type: "circle", color, strokeWidth: 2, padding: 6 });
  }

  // Wrap a state-mutating render so the elements it changes get flashed. Takes
  // the before snapshot, runs applyFn (the demo's render), then flashes diffs.
  // A no-op passthrough unless field notes are on and this is the active view.
  function trackChange(ddsId, clientEl, pending, applyFn) {
    if (!active || ddsId !== currentDds || !isEventDriven(ddsId)) {
      applyFn();
      return;
    }
    const snap = snapshot(ddsId, clientEl);
    applyFn();
    flashChanged(ddsId, clientEl, snap, pending);
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
    // Shared map is event-driven (see CHANGE_TARGETS): no static marks. Each
    // cell holds a whole value, so last-write-wins is visible as an overwrite —
    // the cell flashes magenta on a local edit, ink when a remote write lands.
    map() {
      setNote(
        "Shared map — one key, last write wins. Each cell holds a whole value: watch a cell flash magenta the moment a client edits it, then ink when a remote write overwrites it outright. It is replaced, never merged.",
      );
    },
    // Counters are event-driven (see CHANGE_TARGETS): no static marks. Every
    // value that changes is circled as it changes — magenta while pending on the
    // origin, ink as the op is sequenced and applied to each replica.
    counter() {
      setNote(
        "Shared counter — increments commute, so nothing is overwritten. Watch the total: it flashes magenta the moment a client edits it, then ink on every replica as the increment is sequenced and applied.",
      );
    },
    pn() {
      setNote(
        "PN counter — net = fill − cut, two monotone tallies that only ever grow. Watch the changed tally and the net value flash magenta on edit, then ink as the delta is sequenced and applied; a re-delivered delta is absorbed, so nothing moves.",
      );
    },
    // G-counter is event-driven too: each client owns one tally, the total is
    // their sum. The origin's tally and total flash magenta on edit, then ink on
    // each replica as the delta lands.
    gcounter() {
      setNote(
        "G-counter — each client owns one tally; the total is their sum. Watch every value that changes get circled as the delta flows: magenta while pending on the origin, ink as it is sequenced and applied to each replica.",
      );
    },
    // The sets are event-driven too (see CHANGE_TARGETS): no static marks. Each
    // row's state text is the live value — watch it flash magenta on a local
    // edit, then ink as the op is sequenced and applied to each replica.
    orset() {
      setNote(
        "OR-set — add-wins, observed-remove. Watch a marker's state flash magenta the moment a client edits it, then ink as the op is sequenced and applied. Race a clear against a concurrent re-mark and the marker stays present — the fresh tag was unseen by the clear.",
      );
    },
    gset() {
      setNote(
        "G-set — grow-only union; marking a benchmark is a permanent fact. Watch a row flash magenta on edit, then ink as the op is sequenced and applied to each replica. The registry only grows, and a re-delivered delta is absorbed, so nothing moves.",
      );
    },
    twopset() {
      setNote(
        "2P-set — tombstone wins; a retired marker never comes back. Watch a row flash magenta on edit, then ink as the op is sequenced and applied. Race a re-place against a retire and both replicas keep the tombstone; a re-delivered retire is absorbed, so nothing moves.",
      );
    },
    // OR-map is optimistic: logging or striking a stockpile mutates the local
    // ledger before it is sequenced, so the value flashes magenta on edit.
    ormap() {
      setNote(
        "OR-map — add-wins, observed-remove. Each stockpile carries its own ledger: watch a value flash magenta the moment a client logs or strikes it, then ink as the op is sequenced and applied to each replica. Race a strike against a concurrent log and the row survives, every logged yard intact.",
      );
    },
    // Claims are non-optimistic (see renderClaims in demo.js): a filed claim
    // prints nothing until it round-trips, so the origin never flashes magenta —
    // the holder only flashes ink on the writer that wins the slot.
    claims() {
      setNote(
        "Claims — first writer wins. A filed claim prints nothing optimistically: the holder stays ink until the sequencer stamps it, then flashes ink on the winner. Race two claims for one slot and only the first-sequenced writer lands; the loser's row never changes.",
      );
    },
    // Registers: the atomic slot is non-optimistic — a revision files without
    // moving the printed value, which flashes ink only as the op is sequenced.
    registers() {
      setNote(
        "Registers — atomic wins, losers retained as versions. A revision files without changing the slot: watch the atomic and LWW values flash ink as the op is sequenced and applied. A write that knew the current atomic sequence wins; concurrent losers still append a version, so LWW can diverge from atomic.",
      );
    },
    // Ordered collection is non-optimistic: adds and acquires take effect only in
    // server order, so the queue and held jobs flash ink as each op is sequenced.
    ordered() {
      setNote(
        "Ordered collection — FIFO by sequence. Adds enter the queue in server order and acquires take the front item: watch the queue and held-jobs values flash ink as each op is sequenced and applied. A racing acquire may come back empty because the earlier SN already took the front.",
      );
    },
    // TaskManager is optimistic: volunteering assigns locally before the op is
    // sequenced, so the assignee and waiters flash magenta on edit.
    tasks() {
      setNote(
        "TaskManager — one assignee, FIFO waiters. Volunteers join a per-task queue in sequenced order: watch the assignee and waiters flash magenta on a local volunteer, then ink as the op is sequenced and applied. The first connected volunteer owns the task; abandon promotes the next waiter.",
      );
    },
    // Pact map is non-optimistic: a proposal only prints once sequenced, and the
    // accepted value only lands after a full quorum signs off — both ink.
    pact() {
      setNote(
        "Pact map — quorum acceptance. A proposal first prints as pending with a frozen signoff list: watch the pending value flash ink as it is sequenced, then the accepted value flash ink once every connected client signs off. A leave drains the list.",
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
      // Every structure in the picker has a recipe above; this is only reached
      // if a new view is added without one. Point the reader at a covered view.
      setNote(
        "Field notes aren't marked up for this structure yet — switch to another view to see its behavior annotated.",
      );
    }
    // The persistent narration bracket is for the static structures; the
    // event-driven counters flash their log line per op instead.
    if (!isEventDriven(ddsId)) markNarration();
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
    trackChange,
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
