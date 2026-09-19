import Quill from "quill";
import QuillCursors from "quill-cursors";
import "quill/dist/quill.snow.css";

const USER_SOURCE = "user";
const API_SOURCE = "api";
const SILENT_SOURCE = "silent";
const IMAGE_DATA_URI =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="40">' +
      '<rect width="64" height="40" fill="#e8e3d8" stroke="#25203a"/>' +
      '<text x="32" y="24" font-size="11" text-anchor="middle" fill="#7a2455">stake</text>' +
      "</svg>",
  );

Quill.register("modules/cursors", QuillCursors);

function message(error) {
  return error instanceof Error ? error.message : String(error);
}

function operations(value) {
  const decoded = typeof value === "string" ? JSON.parse(value) : value;
  const result = Array.isArray(decoded)
    ? decoded
    : Array.isArray(decoded?.ops)
      ? decoded.ops
      : null;
  if (result == null) {
    throw new TypeError("Rich-text deltas must contain an operation array.");
  }
  return result;
}

function report(bridge, error) {
  queueMicrotask(() => {
    if (!bridge.destroyed) bridge.onError(message(error));
  });
}

function editor(bridge) {
  return bridge?.destroyed ? null : bridge?.editor ?? null;
}

export function mount(
  elementId,
  initialDocument,
  onUserDelta,
  onSelection,
  onMounted,
  onError,
) {
  const bridge = {
    cursors: null,
    destroyed: false,
    editor: null,
    element: null,
    elementId,
    knownCursors: new Set(),
    nativeSelection: null,
    onError,
    selectionChange: null,
    textChange: null,
    toolbar: null,
  };
  try {
    const element = document.getElementById(elementId);
    if (!(element instanceof HTMLElement)) {
      throw new Error(`Rich-text editor "${elementId}" was not found.`);
    }
    element.replaceChildren();
    const editor = new Quill(element, {
      theme: "snow",
      modules: {
        toolbar: [["bold", "italic", "underline"], ["image"]],
        cursors: { transformOnTextChange: false },
        history: { userOnly: true, delay: 400, maxStack: 100 },
      },
    });
    const textChange = (delta, _old, source) => {
      if (bridge.destroyed || source !== USER_SOURCE) return;
      try {
        const raw = JSON.stringify(operations(delta));
        queueMicrotask(() => {
          if (!bridge.destroyed) onUserDelta(raw);
        });
      } catch (error) {
        report(bridge, error);
      }
    };
    const publishSelection = (range) => {
      if (bridge.destroyed) return;
      queueMicrotask(() => {
        if (bridge.destroyed) return;
        if (range == null) onSelection(-1, -1);
        else onSelection(range.index, range.length);
      });
    };
    const selectionChange = (range) => publishSelection(range);
    const nativeSelection = () => {
      if (document.activeElement === editor.root) {
        publishSelection(editor.getSelection());
      }
    };
    bridge.editor = editor;
    bridge.element = element;
    bridge.toolbar = element.previousElementSibling?.classList.contains("ql-toolbar")
      ? element.previousElementSibling
      : null;
    bridge.cursors = editor.getModule("cursors");
    bridge.textChange = textChange;
    bridge.selectionChange = selectionChange;
    bridge.nativeSelection = nativeSelection;
    editor.on("text-change", textChange);
    editor.on("selection-change", selectionChange);
    document.addEventListener("selectionchange", nativeSelection);
    loadDocument(bridge, initialDocument);
    queueMicrotask(() => {
      if (!bridge.destroyed) onMounted(bridge);
    });
  } catch (error) {
    const reason = message(error);
    destroy(bridge);
    queueMicrotask(() => onError(reason));
  }
}

export function applyRemote(bridge, delta) {
  const instance = editor(bridge);
  if (instance == null) return;
  try {
    instance.updateContents(operations(delta), API_SOURCE);
  } catch (error) {
    report(bridge, error);
  }
}

export function setEnabled(bridge, enabled) {
  editor(bridge)?.enable(enabled);
}

export function loadDocument(bridge, document) {
  const instance = editor(bridge);
  if (instance == null) return;
  try {
    instance.setContents(operations(document), SILENT_SOURCE);
    instance.history.clear();
    bridge.cursors?.clearCursors();
    bridge.knownCursors.clear();
  } catch (error) {
    report(bridge, error);
  }
}

export function renderSelections(bridge, selections) {
  if (editor(bridge) == null || bridge.cursors == null) return;
  try {
    const peers = JSON.parse(selections);
    const seen = new Set();
    for (const peer of peers) {
      seen.add(peer.id);
      if (!bridge.knownCursors.has(peer.id)) {
        bridge.cursors.createCursor(peer.id, peer.name, peer.colour);
        bridge.knownCursors.add(peer.id);
      }
      bridge.cursors.moveCursor(peer.id, {
        index: peer.index,
        length: peer.length,
      });
    }
    for (const id of bridge.knownCursors) {
      if (!seen.has(id)) {
        bridge.cursors.removeCursor(id);
        bridge.knownCursors.delete(id);
      }
    }
  } catch (error) {
    report(bridge, error);
  }
}

export function raceType(bridgeA, bridgeB) {
  const a = editor(bridgeA);
  const b = editor(bridgeB);
  if (!a || !b) return;
  const at = Math.max(0, Math.floor(Math.min(a.getLength(), b.getLength()) / 2));
  a.insertText(at, "⟨A⟩", USER_SOURCE);
  b.insertText(at, "⟨B⟩", USER_SOURCE);
}

export function raceFormat(bridgeA, bridgeC) {
  const a = editor(bridgeA);
  const c = editor(bridgeC);
  if (!a || !c) return;
  const start = Math.max(0, Math.floor(a.getLength() / 3));
  const span = Math.max(1, Math.min(6, a.getLength() - start - 1));
  a.formatText(start, span, "bold", true, USER_SOURCE);
  c.formatText(start, span, "color", "#1d4ed8", USER_SOURCE);
}

export function raceDelete(bridgeA, bridgeB) {
  const a = editor(bridgeA);
  const b = editor(bridgeB);
  if (!a || !b) return;
  const start = Math.max(0, Math.floor(b.getLength() / 4));
  const span = Math.max(1, Math.min(4, b.getLength() - start - 1));
  b.deleteText(start, span, USER_SOURCE);
  a.formatText(
    start,
    Math.min(span + 2, a.getLength() - start - 1),
    "italic",
    true,
    USER_SOURCE,
  );
}

export function insertEmbed(bridge) {
  const instance = editor(bridge);
  if (instance == null) return;
  instance.insertEmbed(
    Math.max(0, instance.getLength() - 1),
    "image",
    IMAGE_DATA_URI,
    USER_SOURCE,
  );
}

export function destroy(bridge) {
  if (bridge?.destroyed) return;
  bridge.destroyed = true;
  if (bridge.editor != null && bridge.textChange != null) {
    bridge.editor.off("text-change", bridge.textChange);
  }
  if (bridge.editor != null && bridge.selectionChange != null) {
    bridge.editor.off("selection-change", bridge.selectionChange);
  }
  if (bridge.nativeSelection != null) {
    document.removeEventListener("selectionchange", bridge.nativeSelection);
  }
  bridge.cursors?.clearCursors();
  bridge.toolbar?.remove();
  bridge.element?.replaceChildren();
  bridge.editor = null;
  bridge.element = null;
  bridge.toolbar = null;
  bridge.cursors = null;
  bridge.textChange = null;
  bridge.selectionChange = null;
  bridge.nativeSelection = null;
  bridge.knownCursors.clear();
}
