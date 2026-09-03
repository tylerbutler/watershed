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
