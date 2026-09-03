import {
  destroy,
  mount,
} from "../src/project_room_lustre/rich_editor_ffi.mjs";

export async function run() {
  const errors = [];
  let editor;

  mount(
    "editor",
    JSON.stringify([
      { insert: "Heading" },
      { insert: "\n", attributes: { header: 1 } },
    ]),
    () => {},
    (mounted) => {
      editor = mounted;
    },
    (error) => errors.push(error),
  );

  if (editor !== undefined) {
    return "FAIL: mount callback ran synchronously";
  }
  await Promise.resolve();
  if (errors.length > 0) {
    return "FAIL: " + errors.join("; ");
  }
  if (editor === undefined) {
    return "FAIL: mount callback did not run";
  }

  const quill = editor.editor;
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

  destroy(editor);
  destroy(editor);
  return "PASS: Quill preserved the block format and one terminal newline";
}
