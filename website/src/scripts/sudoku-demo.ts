// Live Sudoku convergence demo: three real watershed_js documents editing one
// shared root SharedMap, driven through the in-memory sluice (see
// ./demo/sluice-rig.ts for the shared orchestration). No fake TS sequencer, no
// server — a cell edit renders optimistically and pushes an op the sluice
// sequences; delivery is paced one hop at a time and every replica converges.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
const BOARD_SIZE = 4;
const DIGITS = [1, 2, 3, 4];
const RACE_CELL = { row: 1, col: 1 };

function cellKey(row: number, col: number): string {
  return `r${row}c${col}`;
}

function cellLabel(row: number, col: number): string {
  return `r${row + 1}c${col + 1}`;
}

function readInt(optionValue: unknown): number | null {
  const value = some<unknown>(optionValue);
  if (value == null) return null;
  const n = Number(json.to_string(value));
  return Number.isFinite(n) ? n : null;
}

function cellValue(client: RigClient, row: number, col: number): number | null {
  return readInt(watershed.get(client.handle, cellKey(row, col)));
}

function canonicalBoard(client: RigClient): string {
  const cells: Array<number | null> = [];
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      cells.push(cellValue(client, row, col));
    }
  }
  return JSON.stringify(cells);
}

export function initSudokuDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;

  function setCell(clientId: string, row: number, col: number, digit: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const key = cellKey(row, col);
    rig.submit(
      client,
      key,
      () => watershed.set(client.handle, key, json.int(digit)),
      `${cellLabel(row, col)} → ${digit}`,
    );
  }

  function clearCell(clientId: string, row: number, col: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const key = cellKey(row, col);
    rig.submit(
      client,
      key,
      () => watershed.delete$(client.handle, key),
      `${cellLabel(row, col)} clear`,
    );
  }

  function cycleCell(clientId: string, row: number, col: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const value = cellValue(client, row, col);
    const digit = value == null ? DIGITS[client.cursor % DIGITS.length] : (value % BOARD_SIZE) + 1;
    client.cursor += 1;
    setCell(clientId, row, col, digit);
  }

  function renderBoard(client: RigClient) {
    const boardEl = client.el.querySelector("[data-board]");
    if (!boardEl) return;
    boardEl.replaceChildren();

    for (let row = 0; row < BOARD_SIZE; row += 1) {
      for (let col = 0; col < BOARD_SIZE; col += 1) {
        const key = cellKey(row, col);
        const value = cellValue(client, row, col);
        const pending = client.pending.includes(key);
        const button = document.createElement("button");
        button.type = "button";
        button.className = "sudoku-cell";
        button.dataset.row = String(row);
        button.dataset.col = String(col);
        button.textContent = value == null ? "·" : String(value);
        button.classList.toggle("is-empty", value == null);
        button.classList.toggle("k-pending", pending);
        button.classList.toggle("k-seq", !pending && value != null);
        button.setAttribute(
          "aria-label",
          `${CLIENT_LABEL[client.id]} ${cellLabel(row, col)} ${
            value == null ? "empty" : `digit ${value}`
          }. Press to write the next digit; Shift plus Enter or Space clears.`,
        );
        button.addEventListener("click", (event) => {
          if (event.shiftKey) clearCell(client.id, row, col);
          else cycleCell(client.id, row, col);
        });
        button.addEventListener("keydown", (event) => {
          if ((event.key === "Enter" || event.key === " ") && event.shiftKey) {
            event.preventDefault();
            clearCell(client.id, row, col);
          }
        });
        boardEl.append(button);
      }
    }

    const count = client.pending.length;
    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${count} pending`;
      badge.classList.toggle("is-pending", count > 0);
    }
  }

  rig = createSluiceRig({
    rig: "[data-sudoku-rig]",
    status: "[data-sudoku-status]",
    section: "#sudoku-demo",
    control: "sudoku",
    document: "sudoku-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients) => {
      for (const id of CLIENT_IDS) clients[id].handle = watershed.root(clients[id].doc);
    },
    render: renderBoard,
    canonical: canonicalBoard,
  });
  if (!rig) return;

  document.querySelector("[data-sudoku-race]")?.addEventListener("click", () => {
    const { row, col } = RACE_CELL;
    setCell("a", row, col, 1);
    setCell("b", row, col, 3);
    setCell("c", row, col, 4);
  });
  document.querySelector("[data-sudoku-seed]")?.addEventListener("click", () => {
    setCell("a", 0, 0, 1);
    setCell("a", 0, 3, 4);
    setCell("b", 3, 0, 2);
    setCell("c", 3, 3, 3);
  });
  document.querySelector("[data-sudoku-reset]")?.addEventListener("click", () => rig?.reset());
}
