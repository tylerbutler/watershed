export function fakeEditor(onUpdate) {
  return {
    destroyed: false,
    editor: {
      updateContents() {
        onUpdate();
      },
    },
    onError() {},
    textChange: null,
  };
}

export function editorDestroyed(editor) {
  return editor.destroyed;
}
