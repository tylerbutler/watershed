export function recordMounted(editor) {
  const panel = document.getElementById("editor");
  globalThis.__watershedRichEditorLifecycle = {
    editor,
    panelConnected: panel?.isConnected === true,
  };
}
