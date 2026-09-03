import { start } from "../build/dev/javascript/project_room_lustre/rich_editor_browser_test.mjs";

export async function run() {
  delete globalThis.__watershedRichEditorLifecycle;
  start();

  const panel = document.getElementById("editor");
  if (panel === null || !panel.isConnected) {
    return "FAIL: Lustre did not render the editor panel";
  }

  const deadline = performance.now() + 2000;
  while (
    document.getElementById("status")?.textContent === "waiting" &&
    performance.now() < deadline
  ) {
    await new Promise(requestAnimationFrame);
  }

  const status = document.getElementById("status")?.textContent;
  if (status?.startsWith("failed:")) {
    return "FAIL: " + status;
  }
  if (status !== "mounted") {
    return "FAIL: Lustre did not receive Quill's mount callback";
  }

  const lifecycle = globalThis.__watershedRichEditorLifecycle;
  if (lifecycle === undefined || !lifecycle.panelConnected) {
    return "FAIL: the editor panel was absent when Quill mounted";
  }

  const quill = lifecycle.editor.editor;
  const operations = quill.getContents().ops;
  const expected = [
    { insert: "Heading" },
    { attributes: { header: 1 }, insert: "\n" },
  ];
  if (JSON.stringify(operations) !== JSON.stringify(expected)) {
    return "FAIL: Quill normalized the block document to " +
      JSON.stringify(operations);
  }
  if (quill.getText() !== "Heading\n" || quill.getLength() !== 8) {
    return "FAIL: Quill did not preserve exactly one terminal newline";
  }
  if (quill.getFormat(7, 1).header !== 1) {
    return "FAIL: Quill lost the terminal newline block format";
  }

  return "PASS: Lustre rendered the panel before Quill mounted";
}
