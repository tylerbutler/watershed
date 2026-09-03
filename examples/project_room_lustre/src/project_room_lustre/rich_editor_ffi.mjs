const QuillConstructor =
  globalThis.__projectRoomQuillConstructor ?? (await import("quill")).default;

const USER_SOURCE = "user";
const API_SOURCE = "api";
const SILENT_SOURCE = "silent";

function message(error) {
  return error instanceof Error ? error.message : String(error);
}

function operations(value) {
  const decoded = typeof value === "string" ? JSON.parse(value) : value;
  if (Array.isArray(decoded)) return decoded;
  if (Array.isArray(decoded?.ops)) return decoded.ops;
  throw new TypeError("rich editor delta must contain an operation array");
}

function report(bridge, error) {
  bridge.onError(message(error));
}

export function mount(elementId, initialDocument, onUserDelta, onError) {
  const bridge = {
    destroyed: false,
    editor: null,
    onError,
    textChange: null,
  };

  try {
    const element = document.getElementById(elementId);
    if (element == null) {
      throw new Error(`rich editor element "${elementId}" was not found`);
    }

    const editor = new QuillConstructor(element, {
      theme: "snow",
      modules: {
        history: { userOnly: true },
      },
    });
    const textChange = (delta, _oldDelta, source) => {
      if (bridge.destroyed || source !== USER_SOURCE) return;
      try {
        onUserDelta(JSON.stringify(operations(delta)));
      } catch (error) {
        report(bridge, error);
      }
    };

    bridge.editor = editor;
    bridge.textChange = textChange;
    editor.on("text-change", textChange);
    editor.setContents(operations(initialDocument), SILENT_SOURCE);
  } catch (error) {
    report(bridge, error);
  }

  return bridge;
}

export function applyRemote(bridge, delta) {
  if (bridge?.destroyed || bridge?.editor == null) return;
  try {
    bridge.editor.updateContents(operations(delta), API_SOURCE);
  } catch (error) {
    report(bridge, error);
  }
}

export function loadDocument(bridge, document) {
  if (bridge?.destroyed || bridge?.editor == null) return;
  try {
    bridge.editor.setContents(operations(document), SILENT_SOURCE);
  } catch (error) {
    report(bridge, error);
  }
}

export function destroy(bridge) {
  if (bridge?.destroyed) return;
  bridge.destroyed = true;
  if (bridge.editor != null && bridge.textChange != null) {
    bridge.editor.off("text-change", bridge.textChange);
  }
}
