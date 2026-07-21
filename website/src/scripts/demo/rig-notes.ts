// Field notes for the sluice-rig demos (sequence, and any future rig page).
//
// The homepage engine's field-notes module (tutorial.js) snapshots live values
// by node identity, which requires renders that mutate nodes in place. The rig
// demos rebuild or re-position DOM per render, so this variant inverts the
// contract: the demo owns its diff — it knows which of its keyed elements
// changed — and calls `flashEls`; this module only draws. Same color grammar
// as tutorial.js (magenta --overprint for a pending local edit, ink --ink once
// sequenced) and flash-only: no static marks, per the event-driven model in
// docs/field-notes.md.
import { annotate } from "rough-notation";
import type { RoughAnnotationConfig } from "rough-notation/lib/model";
import { prefersReducedMotion } from "./timing.ts";

export interface RigNotes {
  /** Whether the field-notes checkbox is on. */
  readonly active: boolean;
  /** Circle-flash elements the demo diffed as changed. */
  flashEls(els: Array<Element | null | undefined>, pending: boolean): void;
}

interface FlashEntry {
  a: { remove(): void };
  timer: ReturnType<typeof setTimeout>;
}

export function createRigNotes(config: {
  /** The rig container (holds the op log). */
  rig: Element;
  /** The field-notes checkbox. */
  toggle: HTMLInputElement;
  /** The caption element shown while notes are on. */
  note: HTMLElement;
  /** Caption naming the merge rule in the ink/magenta language. */
  caption: string;
}): RigNotes {
  const cssVar = (name: string) =>
    getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  let active = false;
  let flashes: FlashEntry[] = [];

  function flash(el: Element | null, cfg: RoughAnnotationConfig, ttl: number) {
    if (!el) return;
    const a = annotate(el as HTMLElement, {
      animate: !prefersReducedMotion(),
      animationDuration: 450,
      ...cfg,
    });
    a.show();
    const entry: FlashEntry = {
      a,
      timer: setTimeout(() => {
        a.remove();
        flashes = flashes.filter((f) => f !== entry);
      }, ttl),
    };
    flashes.push(entry);
  }

  function clearFlashes() {
    for (const f of flashes) {
      clearTimeout(f.timer);
      f.a.remove();
    }
    flashes = [];
  }

  config.note.textContent = config.caption;
  config.toggle.addEventListener("change", () => {
    active = config.toggle.checked;
    config.note.hidden = !active;
    if (!active) clearFlashes();
  });

  // The rig prints one op-log line per sequenced op, so a childList mutation
  // is the "op sequenced" moment — box the newest line, like flashLog upstream.
  const log = config.rig.querySelector("[data-op-log]");
  if (log) {
    new MutationObserver(() => {
      if (!active) return;
      flash(
        log.querySelector("li"),
        { type: "box", color: cssVar("--ink"), strokeWidth: 2, padding: 3 },
        1400,
      );
    }).observe(log, { childList: true });
  }

  return {
    get active() {
      return active;
    },
    flashEls(els, pending) {
      if (!active) return;
      const color = pending ? cssVar("--overprint") : cssVar("--ink");
      for (const el of els)
        if (el)
          flash(el, { type: "circle", color, strokeWidth: 2, padding: 6 }, 1300);
    },
  };
}
