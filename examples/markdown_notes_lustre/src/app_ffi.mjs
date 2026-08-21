// The demo's own URL reading. Kept here rather than in the library: which
// query parameters an application uses to configure signaling and ICE is the
// application's business, and watershed deliberately has no opinion about it.

export function queryParam(name, fallback) {
  const href = globalThis.location?.href;
  if (!href) return fallback;
  const value = new URL(href).searchParams.get(name);
  return value === null || value === "" ? fallback : value;
}

// Signaling failures arrive on a socket callback, outside Lustre's dispatch
// loop. The app hands us a sink once, on the effect that owns `dispatch`.
let signalingSink = () => {};

export function setSignalingSink(sink) {
  signalingSink = sink;
}

export function reportSignalingFailure(detail) {
  signalingSink(detail);
}

// Without this, the IndexedDB snapshot the app calls "disk-first" is evictable
// under storage pressure. Resolves false wherever the API is absent (node, old
// browsers) rather than throwing.
export function requestPersistentStorage() {
  const storage = globalThis.navigator?.storage;
  if (typeof storage?.persist !== "function") return Promise.resolve(false);
  return storage.persist().then(
    (granted) => granted === true,
    () => false,
  );
}

// One document-level key listener rather than a handler per control. The
// editor is a mapped child element and cannot dispatch the app's own `Msg`
// from its own attributes, so the chords are recognised here and the app is
// told what happened. preventDefault fires only on a recognised chord, so
// Tab, arrows and everything else keep their normal behaviour.
let shortcutSink = () => {};

export function setShortcutSink(sink) {
  shortcutSink = sink;
  if (typeof document === "undefined") return;
  if (document.__watershedShortcuts) return;
  document.__watershedShortcuts = true;
  document.addEventListener("keydown", (event) => {
    const action = shortcutFor(event);
    if (!action) return;
    event.preventDefault();
    shortcutSink(action[0], action[1]);
  });
}

// Returns [action, argument] for a recognised chord, or null.
function shortcutFor(event) {
  const active = document.activeElement;

  // Alt+Arrow over a note button reorders it. Alt is what editors use for
  // "move this line"; plain arrows still scroll the list.
  if (event.altKey && !event.ctrlKey && !event.metaKey) {
    const name = active?.dataset?.noteName;
    if (name && active.dataset.smoke === "note-open") {
      if (event.key === "ArrowUp") return ["move-up", name];
      if (event.key === "ArrowDown") return ["move-down", name];
    }
    return null;
  }

  // Formatting applies to the editor, so it only binds while the editor holds
  // focus — Cmd+B anywhere else on the page belongs to the browser.
  if (!(event.metaKey || event.ctrlKey) || event.altKey) return null;
  if (active?.dataset?.smoke !== "editor") return null;
  switch (event.key.toLowerCase()) {
    case "b":
      return ["bold", ""];
    case "i":
      return ["italic", ""];
    case "e":
      return ["code", ""];
    default:
      return null;
  }
}

// Reordering re-renders the list, which drops focus. Put it back on the note
// that just moved so a second press keeps moving the same note.
export function focusNoteButton(name) {
  if (typeof document === "undefined") return;
  requestAnimationFrame(() => {
    const selector = `[data-smoke="note-open"][data-note-name="${CSS.escape(name)}"]`;
    document.querySelector(selector)?.focus();
  });
}

// The recovery gate asks the user to overwrite bytes it cannot read. This is
// the escape hatch that makes that a choice rather than a gamble: the exported
// snapshot is the same importable JSON `crdt.import_snapshot` accepts.
export function downloadJson(filename, contents) {
  if (typeof document === "undefined") return;
  const url = URL.createObjectURL(
    new Blob([contents], { type: "application/json" }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Revoked on the next task so the click has certainly been dispatched.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

// Sharing the room means sharing this exact URL. The README said so; the UI
// did not, and the hint that mentioned it disappeared once the room opened.
export function copyCurrentUrl() {
  const href = globalThis.location?.href;
  if (!href) return;
  globalThis.navigator?.clipboard?.writeText(href).catch(() => {});
}

export function afterMs(delay, run) {
  setTimeout(run, delay);
}
