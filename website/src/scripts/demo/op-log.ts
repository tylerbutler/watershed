// A tiny op-log helper shared by the demos. Callers build their own list-item
// DOM (the formatting differs per demo); this just handles insertion policy:
//
//   • "prepend" — newest on top, trimmed to `max` entries (interactive demos)
//   • "append"  — newest at the bottom, auto-scrolled (scripted walkthroughs)

export interface OpLog {
  /** Insert an already-built <li> per the configured policy. */
  push(li: HTMLElement): void;
  /** Remove every entry. */
  clear(): void;
}

export interface OpLogOptions {
  mode?: "prepend" | "append";
  /** Max retained entries (prepend mode only). Omit for unbounded. */
  max?: number;
}

export function createOpLog(el: HTMLElement, opts: OpLogOptions = {}): OpLog {
  const { mode = "prepend", max } = opts;

  return {
    push(li: HTMLElement) {
      if (mode === "append") {
        el.appendChild(li);
        el.scrollTop = el.scrollHeight;
      } else {
        el.prepend(li);
        if (max !== undefined) {
          while (el.children.length > max) el.lastChild?.remove();
        }
      }
    },
    clear() {
      el.replaceChildren();
    },
  };
}
