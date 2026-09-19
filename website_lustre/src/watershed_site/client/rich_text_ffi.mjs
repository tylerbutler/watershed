import Quill from "quill";
import "quill/dist/quill.snow.css";

const USER_SOURCE = "user";
const API_SOURCE = "api";
const SILENT_SOURCE = "silent";
const editors = new Map();
let scenariosBound = false;

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

function quill(id) {
  return editors.get(id)?.editor ?? null;
}

function bindScenarios() {
  if (scenariosBound) return;
  scenariosBound = true;
  document.querySelector("[data-rt-race-type]")?.addEventListener("click", () => {
    const a = quill("a");
    const b = quill("b");
    if (!a || !b) return;
    const at = Math.max(0, Math.floor(Math.min(a.getLength(), b.getLength()) / 2));
    a.insertText(at, "⟨A⟩", USER_SOURCE);
    b.insertText(at, "⟨B⟩", USER_SOURCE);
  });
  document.querySelector("[data-rt-race-format]")?.addEventListener("click", () => {
    const a = quill("a");
    const c = quill("c");
    if (!a || !c) return;
    const start = Math.max(0, Math.floor(a.getLength() / 3));
    const span = Math.max(1, Math.min(6, a.getLength() - start - 1));
    a.formatText(start, span, "bold", true, USER_SOURCE);
    c.formatText(start, span, "color", "#1d4ed8", USER_SOURCE);
  });
  document.querySelector("[data-rt-race-delete]")?.addEventListener("click", () => {
    const a = quill("a");
    const b = quill("b");
    if (!a || !b) return;
    const start = Math.max(0, Math.floor(b.getLength() / 4));
    const span = Math.max(1, Math.min(4, b.getLength() - start - 1));
    b.deleteText(start, span, USER_SOURCE);
    a.formatText(start, Math.min(span + 2, a.getLength() - start - 1), "italic", true, USER_SOURCE);
  });
  document.querySelector("[data-rt-embed]")?.addEventListener("click", () => {
    const c = quill("c");
    if (!c) return;
    const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="40">' +
      '<rect width="64" height="40" fill="#e8e3d8" stroke="#25203a"/>' +
      '<text x="32" y="24" font-size="11" text-anchor="middle" fill="#7a2455">stake</text>' +
      "</svg>";
    c.insertEmbed(
      Math.max(0, c.getLength() - 1),
      "image",
      `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`,
      USER_SOURCE,
    );
  });
}

export function mount(elementId, initialDocument, onUserDelta, onMounted, onError) {
  const bridge = {
    destroyed: false,
    editor: null,
    elementId,
    onError,
    textChange: null,
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
    bridge.editor = editor;
    bridge.textChange = textChange;
    editor.on("text-change", textChange);
    editor.setContents(operations(initialDocument), SILENT_SOURCE);
    editor.history.clear();
    const id = elementId.slice(-1);
    editors.set(id, bridge);
    bindScenarios();
    queueMicrotask(() => {
      if (!bridge.destroyed) onMounted(bridge);
    });
  } catch (error) {
    destroy(bridge);
    report(bridge, error);
  }
}

export function applyRemote(bridge, delta) {
  if (bridge?.destroyed || bridge?.editor == null) return;
  try {
    bridge.editor.updateContents(operations(delta), API_SOURCE);
  } catch (error) {
    report(bridge, error);
  }
}

export function setEnabled(bridge, enabled) {
  if (bridge?.destroyed || bridge?.editor == null) return;
  bridge.editor.enable(enabled);
}

export function destroy(bridge) {
  if (bridge?.destroyed) return;
  bridge.destroyed = true;
  if (bridge.editor != null && bridge.textChange != null) {
    bridge.editor.off("text-change", bridge.textChange);
  }
  const id = bridge.elementId?.slice(-1);
  if (id && editors.get(id) === bridge) editors.delete(id);
  bridge.editor = null;
  bridge.textChange = null;
}
