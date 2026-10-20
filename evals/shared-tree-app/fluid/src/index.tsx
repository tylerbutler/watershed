import { createRoot } from "react-dom/client";
import { App } from "./App.tsx";
import type { Config } from "./domain.ts";

const root = document.getElementById("app");
if (!root) throw new Error("Missing app element");
const query = new URL(location.href).searchParams;
const config: Config = {
  endpoint: query.get("endpoint") ?? "http://localhost:7070",
  documentId: query.get("document"),
  clientId: crypto.randomUUID(),
};
createRoot(root).render(<App config={config} />);
