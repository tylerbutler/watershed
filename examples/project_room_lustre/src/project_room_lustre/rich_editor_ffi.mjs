const QuillConstructor =
  globalThis.__projectRoomQuillConstructor ??
  (typeof document === "undefined" ? null : (await import("quill")).default);

const USER_SOURCE = "user";
const API_SOURCE = "api";
const SILENT_SOURCE = "silent";

function message(error) {
  return error instanceof Error ? error.message : String(error);
}

function validateOperation(operation) {
  if (
    operation === null ||
    typeof operation !== "object" ||
    Array.isArray(operation)
  ) {
    throw new TypeError("rich editor operations must be objects");
  }

  const actionKeys = ["insert", "delete", "retain"].filter((key) =>
    Object.hasOwn(operation, key)
  );
  const validKeys = new Set([...actionKeys, "attributes"]);
  if (
    actionKeys.length !== 1 ||
    Object.keys(operation).some((key) => !validKeys.has(key))
  ) {
    throw new TypeError(
      "rich editor operations must contain exactly one action",
    );
  }

  const action = actionKeys[0];
  if (action === "insert" && operation.insert === null) {
    throw new TypeError("rich editor inserts must not be null");
  }
  if (
    action !== "insert" &&
    (!Number.isInteger(operation[action]) || operation[action] <= 0)
  ) {
    throw new TypeError(`rich editor ${action} values must be positive integers`);
  }
  if (
    Object.hasOwn(operation, "attributes") &&
    (operation.attributes === null ||
      typeof operation.attributes !== "object" ||
      Array.isArray(operation.attributes))
  ) {
    throw new TypeError("rich editor attributes must be an object");
  }
}

function operations(value) {
  const decoded = typeof value === "string" ? JSON.parse(value) : value;
  const result = Array.isArray(decoded)
    ? decoded
    : Array.isArray(decoded?.ops)
      ? decoded.ops
      : null;
  if (result === null) {
    throw new TypeError("rich editor delta must contain an operation array");
  }
  result.forEach(validateOperation);
  return result;
}

function report(bridge, error) {
  const reason = message(error);
  queueMicrotask(() => bridge.onError(reason));
}

export function queue(action) {
  queueMicrotask(action);
}

export function mount(
  elementId,
  initialDocument,
  onUserDelta,
  onMounted,
  onError,
) {
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
    if (QuillConstructor == null) {
      throw new Error("rich editor is unavailable outside a browser");
    }

    const editor = new QuillConstructor(element, {
      modules: {
        history: { userOnly: true },
      },
    });
    const textChange = (delta, _oldDelta, source) => {
      if (bridge.destroyed || source !== USER_SOURCE) return;
      try {
        const change = JSON.stringify(operations(delta));
        queueMicrotask(() => {
          if (!bridge.destroyed) onUserDelta(change);
        });
      } catch (error) {
        report(bridge, error);
      }
    };

    bridge.editor = editor;
    bridge.textChange = textChange;
    editor.on("text-change", textChange);
    queueMicrotask(() => {
      if (!bridge.destroyed) onMounted(bridge);
    });
    editor.setContents(operations(initialDocument), SILENT_SOURCE);
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
  bridge.editor = null;
  bridge.textChange = null;
}
