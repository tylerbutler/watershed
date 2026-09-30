import {
  expectOk,
  type ResultValue,
  websiteRuntime,
} from "./demo/generated-runtime.ts";
import { withLegacyGeneratedDocument } from "./demo/legacy-generated-document.ts";
import { createSluiceRig, type RigClient } from "./demo/sluice-rig.ts";
import { demoSeed } from "./demo/sluice-runtime.ts";

const CLIENT_IDS = ["a", "b"] as const;
const CLIENT_LABEL: Record<(typeof CLIENT_IDS)[number], string> = {
  a: "Client A",
  b: "Client B",
};

type ChecklistHandle = ResultValue<
  ReturnType<typeof websiteRuntime.open_shared_tree_checklist>
>;

interface ChecklistItem {
  id: string;
  text: string;
  completed: boolean;
}

interface FocusedEdit {
  id: string;
  value: string;
  start: number | null;
  end: number | null;
  direction: "forward" | "backward" | "none" | null;
}

function checklist(client: RigClient): ChecklistHandle {
  return client.handle as ChecklistHandle;
}

function items(client: RigClient): ChecklistItem[] {
  return expectOk(
    websiteRuntime.shared_tree_checklist_items(checklist(client)),
    `SharedTree checklist items failed for ${CLIENT_LABEL[client.id as keyof typeof CLIENT_LABEL]}`,
  )
    .toArray()
    .map(({ id, text, completed }) => ({ id, text, completed }));
}

function canonical(client: RigClient): string {
  return JSON.stringify(
    items(client).map(({ id, text, completed }) => ({
      id,
      text,
      completed,
    })),
  );
}

function focusedEdit(list: Element): FocusedEdit | null {
  const active = document.activeElement;
  if (!(active instanceof HTMLInputElement) || !list.contains(active)) {
    return null;
  }
  const id = active.dataset.itemId;
  if (!id) return null;
  return {
    id,
    value: active.value,
    start: active.selectionStart,
    end: active.selectionEnd,
    direction: active.selectionDirection,
  };
}

function restoreFocusedEdit(list: Element, focus: FocusedEdit | null): void {
  if (!focus) return;
  const input = [...list.querySelectorAll("[data-item-id]")].find(
    (candidate) =>
      candidate instanceof HTMLInputElement &&
      candidate.dataset.itemId === focus.id,
  );
  if (!(input instanceof HTMLInputElement)) return;
  input.value = focus.value;
  input.focus();
  if (focus.start != null && focus.end != null) {
    input.setSelectionRange(focus.start, focus.end, focus.direction ?? "none");
  }
}

export function initSharedTreeChecklistDemo(): void {
  const seed = demoSeed(
    expectOk(
      websiteRuntime.shared_tree_checklist_seed(),
      "SharedTree checklist seed failed",
    ),
  );
  let rig: ReturnType<typeof createSluiceRig> = null;
  let rebuildingList = false;

  function submitEdit(client: RigClient, id: string, text: string): void {
    const current = items(client).find((item) => item.id === id);
    if (!current || current.text === text) return;
    rig?.submit(
      client,
      id,
      () => {
        expectOk(
          websiteRuntime.shared_tree_checklist_edit(
            checklist(client),
            id,
            text,
          ),
          `SharedTree checklist edit failed for ${id}`,
        );
      },
      `edit ${id}`,
    );
  }

  function render(client: RigClient): void {
    const list = client.el.querySelector("[data-st-list]");
    const canonicalElement = client.el.querySelector("[data-canonical]");
    const pendingCount = client.el.querySelector("[data-pending-count]");
    if (!(list instanceof HTMLOListElement)) return;

    const focus = focusedEdit(list);
    const currentItems = items(client);
    const fragment = document.createDocumentFragment();

    currentItems.forEach((item, index) => {
      const row = document.createElement("li");
      row.className = client.pending.includes(item.id)
        ? "checklist-row is-pending"
        : "checklist-row is-sequenced";

      const completed = document.createElement("input");
      completed.type = "checkbox";
      completed.checked = item.completed;
      completed.setAttribute(
        "aria-label",
        `${CLIENT_LABEL[client.id as keyof typeof CLIENT_LABEL]} item ${item.text}, ${
          item.completed ? "completed" : "not completed"
        }`,
      );
      completed.addEventListener("change", () => {
        rig?.submit(
          client,
          item.id,
          () => {
            expectOk(
              websiteRuntime.shared_tree_checklist_toggle(
                checklist(client),
                item.id,
              ),
              `SharedTree checklist toggle failed for ${item.id}`,
            );
          },
          `toggle ${item.id}`,
        );
      });

      const text = document.createElement("input");
      text.type = "text";
      text.value = item.text;
      text.dataset.itemId = item.id;
      text.setAttribute(
        "aria-label",
        `${CLIENT_LABEL[client.id as keyof typeof CLIENT_LABEL]} item text: ${item.text}`,
      );
      text.addEventListener("keydown", (event) => {
        if (event.key !== "Enter") return;
        event.preventDefault();
        text.blur();
      });
      text.addEventListener("blur", () => {
        if (rebuildingList) return;
        submitEdit(client, item.id, text.value);
      });

      const moves = document.createElement("span");
      moves.className = "item-moves";

      const moveUp = document.createElement("button");
      moveUp.type = "button";
      moveUp.textContent = "Move up";
      moveUp.disabled = index === 0;
      moveUp.setAttribute(
        "aria-label",
        `Move ${CLIENT_LABEL[client.id as keyof typeof CLIENT_LABEL]} item ${item.text} up`,
      );
      moveUp.addEventListener("click", () => {
        rig?.submit(
          client,
          item.id,
          () => {
            expectOk(
              websiteRuntime.shared_tree_checklist_move_up(
                checklist(client),
                item.id,
              ),
              `SharedTree checklist move up failed for ${item.id}`,
            );
          },
          `move ${item.id} up`,
        );
      });

      const moveDown = document.createElement("button");
      moveDown.type = "button";
      moveDown.textContent = "Move down";
      moveDown.disabled = index === currentItems.length - 1;
      moveDown.setAttribute(
        "aria-label",
        `Move ${CLIENT_LABEL[client.id as keyof typeof CLIENT_LABEL]} item ${item.text} down`,
      );
      moveDown.addEventListener("click", () => {
        rig?.submit(
          client,
          item.id,
          () => {
            expectOk(
              websiteRuntime.shared_tree_checklist_move_down(
                checklist(client),
                item.id,
              ),
              `SharedTree checklist move down failed for ${item.id}`,
            );
          },
          `move ${item.id} down`,
        );
      });

      moves.append(moveUp, moveDown);
      row.append(completed, text, moves);
      fragment.append(row);
    });

    rebuildingList = true;
    try {
      list.replaceChildren(fragment);
      restoreFocusedEdit(list, focus);
    } finally {
      rebuildingList = false;
    }

    if (canonicalElement instanceof HTMLElement) {
      canonicalElement.textContent = canonical(client);
    }
    if (pendingCount instanceof HTMLElement) {
      pendingCount.textContent = `${client.pending.length} pending`;
      pendingCount.classList.toggle("is-pending", client.pending.length > 0);
    }
  }

  rig = createSluiceRig({
    rig: "[data-st-rig]",
    status: "[data-st-status]",
    section: "#sharedtree-checklist-demo",
    control: "st",
    document: "sharedtree-checklist-demo",
    seed,
    clientIds: [...CLIENT_IDS],
    clientLabel: CLIENT_LABEL,
    setup: (clients) => {
      for (const id of CLIENT_IDS) {
        clients[id].handle = expectOk(
          withLegacyGeneratedDocument(
            clients[id].doc,
            websiteRuntime.open_shared_tree_checklist,
          ),
          `SharedTree checklist open failed for ${CLIENT_LABEL[id]}`,
        );
      }
    },
    render,
    canonical,
  });
  if (!rig) return;

  for (const id of CLIENT_IDS) {
    const client = rig.clients[id];
    const draft = client.el.querySelector("[data-st-draft]");
    const add = client.el.querySelector("[data-st-add]");
    if (!(draft instanceof HTMLInputElement) || !(add instanceof HTMLButtonElement)) {
      continue;
    }

    const submitAdd = () => {
      const text = draft.value.trim();
      if (!text) return;
      const itemId = crypto.randomUUID();
      rig?.submit(
        client,
        itemId,
        () => {
          expectOk(
            websiteRuntime.shared_tree_checklist_add(
              checklist(client),
              itemId,
              text,
            ),
            `SharedTree checklist add failed for ${itemId}`,
          );
        },
        `add ${itemId}`,
      );
      draft.value = "";
    };

    add.addEventListener("click", submitAdd);
    draft.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return;
      event.preventDefault();
      submitAdd();
    });
  }

  document.querySelector("[data-st-race]")?.addEventListener("click", () => {
    rig?.reset();
    if (!rig) return;
    const clientA = rig.clients.a;
    const clientB = rig.clients.b;
    rig.submit(
      clientA,
      "publish-survey",
      () => {
        expectOk(
          websiteRuntime.shared_tree_checklist_edit(
            checklist(clientA),
            "publish-survey",
            "publish revised survey",
          ),
          "SharedTree checklist race edit failed",
        );
      },
      "edit publish-survey",
    );
    rig.submit(
      clientB,
      "inspect-spillway",
      () => {
        expectOk(
          websiteRuntime.shared_tree_checklist_move_down(
            checklist(clientB),
            "inspect-spillway",
          ),
          "SharedTree checklist race move failed",
        );
      },
      "move inspect-spillway down",
    );
  });
  document.querySelector("[data-st-step]")?.addEventListener("click", () => {
    rig?.step();
  });
  document.querySelector("[data-st-settle]")?.addEventListener("click", () => {
    rig?.settleNow();
  });
  document.querySelector("[data-st-reset]")?.addEventListener("click", () => {
    rig?.reset();
  });
}
