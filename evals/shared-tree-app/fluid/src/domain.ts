export type Status = "open" | "investigating" | "resolved";
export interface Step { readonly id: string; label: string; done: boolean }
export interface Incident {
  readonly id: string;
  title: string;
  status: Status;
  assignee?: string;
  steps: Step[];
}
export interface Board { incidents: Incident[] }
export interface State {
  phase: "opening" | "ready" | "disconnected" | "closed" | "error";
  documentId: string | null;
  board: Board;
  errors: string[];
}
export interface Config {
  endpoint: string;
  documentId: string | null;
  clientId: string;
}
export type Action =
  | { type: "add-incident"; id: string; title: string }
  | { type: "title"; id: string; value: string }
  | { type: "status"; id: string; value: Status }
  | { type: "assignee"; id: string; value: string | null }
  | { type: "remove-incident"; id: string }
  | { type: "move-incident"; id: string; before: string | null }
  | { type: "add-step"; incident: string; id: string; label: string }
  | { type: "step-label"; incident: string; id: string; value: string }
  | { type: "step-done"; incident: string; id: string; value: boolean }
  | { type: "remove-step"; incident: string; id: string }
  | { type: "move-step"; incident: string; id: string; before: string | null };
export interface Session {
  read(): State;
  apply(action: Action): void;
  subscribe(listener: () => void): () => void;
  close(): void;
}
