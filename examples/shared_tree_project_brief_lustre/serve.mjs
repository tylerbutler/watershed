import { startChecklistServer } from "../shared_tree_checklist_lustre/serve.mjs";

const server = await startChecklistServer({
  appRoot: new URL(".", import.meta.url),
});
console.log("SharedTree project brief: http://127.0.0.1:" + server.port);
