import { createRoot } from "react-dom/client";
import { App } from "./App.tsx";
import { openSession, type BriefSession } from "./fluid.ts";

const element = document.getElementById("app");
if (!element) throw new Error("Missing app element");
const renderer = createRoot(element);
const controller = new AbortController();
let session: BriefSession | undefined;
let closed = false;
function close() {
  if (closed) return;
  closed = true;
  controller.abort();
  session?.close();
  renderer.render(<main data-tree-change-count="0">
    <h1>SharedTree project brief</h1><p data-runtime-status="closed">closed</p>
    <p>Reload to reopen. Closing does not confirm pending edits were saved.</p>
  </main>);
}
window.addEventListener("pagehide", () => { close(); renderer.unmount(); }, { once: true });

renderer.render(<main data-tree-change-count="0">
  <h1>SharedTree project brief</h1><p data-runtime-status="loading">Connecting to Fluid…</p>
  <button data-action="close" onClick={close}>Close</button>
</main>);
// No mount effect owns creation: React replay cannot create or attach a second document.
openSession(new URL(location.href), controller.signal).then((opened) => {
  if (closed) { opened.close(); return; }
  session = opened;
  renderer.render(<App session={opened} />);
}).catch((error: unknown) => {
  if (closed) return;
  renderer.render(<main data-tree-change-count="0"><h1>SharedTree project brief</h1>
    <p data-runtime-status="error">Could not open this document. Creation was not retried.</p>
    <p role="alert" data-error="">{error instanceof Error ? error.message : String(error)}</p>
    <button data-action="close" onClick={close}>Close</button>
  </main>);
});
