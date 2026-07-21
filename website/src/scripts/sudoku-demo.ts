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
const BOARD_SIZE = 9;
const DIGITS = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const RACE_CELL = { row: 4, col: 4 };

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

function eventCell(event: Event): HTMLButtonElement | null {
  const target = event.target;
  if (!(target instanceof Element)) return null;
  const cell = target.closest(".sudoku-cell");
  return cell instanceof HTMLButtonElement ? cell : null;
}

function cellPosition(cell: HTMLButtonElement): { row: number; col: number } | null {
  const row = Number(cell.dataset.row);
  const col = Number(cell.dataset.col);
  if (!Number.isInteger(row) || !Number.isInteger(col)) return null;
  return { row, col };
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

  function focusCell(boardEl: HTMLElement, row: number, col: number) {
    const boundedRow = Math.max(0, Math.min(BOARD_SIZE - 1, row));
    const boundedCol = Math.max(0, Math.min(BOARD_SIZE - 1, col));
    const next = boardEl.querySelector(
      `[data-row="${boundedRow}"][data-col="${boundedCol}"]`,
    );
    if (next instanceof HTMLButtonElement) next.focus();
  }

  function buildBoard(client: RigClient, boardEl: HTMLElement) {
    if (boardEl.childElementCount === BOARD_SIZE * BOARD_SIZE) return;

    const fragment = document.createDocumentFragment();
    for (let row = 0; row < BOARD_SIZE; row += 1) {
      for (let col = 0; col < BOARD_SIZE; col += 1) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "sudoku-cell is-empty";
        button.dataset.row = String(row);
        button.dataset.col = String(col);
        button.setAttribute("role", "gridcell");
        button.setAttribute("aria-rowindex", String(row + 1));
        button.setAttribute("aria-colindex", String(col + 1));
        button.tabIndex = row === 0 && col === 0 ? 0 : -1;
        fragment.append(button);
      }
    }
    boardEl.replaceChildren(fragment);

    boardEl.addEventListener("focusin", (event) => {
      const focused = eventCell(event);
      if (!focused) return;
      for (const cell of boardEl.querySelectorAll(".sudoku-cell")) {
        if (cell instanceof HTMLButtonElement) {
          cell.tabIndex = cell === focused ? 0 : -1;
        }
      }
    });
    boardEl.addEventListener("click", (event) => {
      const cell = eventCell(event);
      const position = cell ? cellPosition(cell) : null;
      if (!position) return;
      if (event.shiftKey) clearCell(client.id, position.row, position.col);
      else cycleCell(client.id, position.row, position.col);
    });
    boardEl.addEventListener("keydown", (event) => {
      if (!(event instanceof KeyboardEvent)) return;
      const cell = eventCell(event);
      const position = cell ? cellPosition(cell) : null;
      if (!position) return;

      if (
        /^[1-9]$/.test(event.key) &&
        !event.altKey &&
        !event.ctrlKey &&
        !event.metaKey
      ) {
        event.preventDefault();
        setCell(client.id, position.row, position.col, Number(event.key));
        return;
      }
      if (event.key === "Delete" || event.key === "Backspace" || event.key === "0") {
        event.preventDefault();
        clearCell(client.id, position.row, position.col);
        return;
      }
      if ((event.key === "Enter" || event.key === " ") && event.shiftKey) {
        event.preventDefault();
        clearCell(client.id, position.row, position.col);
        return;
      }

      const moves: Record<string, { row: number; col: number }> = {
        ArrowUp: { row: position.row - 1, col: position.col },
        ArrowDown: { row: position.row + 1, col: position.col },
        ArrowLeft: { row: position.row, col: position.col - 1 },
        ArrowRight: { row: position.row, col: position.col + 1 },
        Home: {
          row: event.ctrlKey ? 0 : position.row,
          col: 0,
        },
        End: {
          row: event.ctrlKey ? BOARD_SIZE - 1 : position.row,
          col: BOARD_SIZE - 1,
        },
      };
      const next = moves[event.key];
      if (!next) return;
      event.preventDefault();
      focusCell(boardEl, next.row, next.col);
    });
  }

  function renderBoard(client: RigClient) {
    const boardEl = client.el.querySelector("[data-board]");
    if (!(boardEl instanceof HTMLElement)) return;
    buildBoard(client, boardEl);

    for (const button of boardEl.querySelectorAll(".sudoku-cell")) {
      if (!(button instanceof HTMLButtonElement)) continue;
      const position = cellPosition(button);
      if (!position) continue;
      const key = cellKey(position.row, position.col);
      const value = cellValue(client, position.row, position.col);
      const pending = client.pending.includes(key);
      button.textContent = value == null ? "·" : String(value);
      button.classList.toggle("is-empty", value == null);
      button.classList.toggle("k-pending", pending);
      button.classList.toggle("k-seq", !pending && value != null);
      button.setAttribute(
        "aria-label",
        `${CLIENT_LABEL[client.id]} row ${position.row + 1}, column ${
          position.col + 1
        }, ${value == null ? "empty" : `digit ${value}`}. Type 1 through 9 to set; Delete clears.`,
      );
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
    setCell("b", row, col, 5);
    setCell("c", row, col, 9);
  });
  document.querySelector("[data-sudoku-seed]")?.addEventListener("click", () => {
    setCell("a", 0, 0, 5);
    setCell("a", 0, 8, 9);
    setCell("b", 8, 0, 8);
    setCell("c", 8, 8, 2);
  });
  document.querySelector("[data-sudoku-reset]")?.addEventListener("click", () => rig?.reset());
}
