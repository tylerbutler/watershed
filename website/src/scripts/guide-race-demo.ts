import * as watershed from "../../../build/dev/javascript/watershed/watershed.mjs";
import * as orMapKernel from "../../../build/dev/javascript/watershed/watershed/or_map_kernel.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";

const CLIENT_IDS = ["a", "b"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
};
const CHANNEL_KEYS = {
  notes: "notes",
  votes: "votes",
} as const;
const WENT_WELL = "went_well";

interface GuideRaceChannels {
  notes: unknown;
  votes: unknown;
}

interface GuideRaceNote {
  text: string;
  column: string;
  author: string;
  created: number;
}

interface GuideRaceCard {
  id: string;
  note: GuideRaceNote;
  votes: number;
}

const STARTER_NOTE = {
  id: noteId("survey", 900, 1),
  note: {
    text: "ship week went smoothly",
    column: WENT_WELL,
    author: "survey",
    created: 900,
  },
} as const;

const ADD_RACE = [
  {
    clientId: "a",
    author: "user-a",
    text: "deploys got faster",
    created: 1000,
    nonce: 1,
  },
  {
    clientId: "b",
    author: "user-b",
    text: "standup stayed short",
    created: 1000,
    nonce: 1,
  },
] as const;

function noteId(author: string, created: number, nonce: number): string {
  return `note-${author}-${created}-${nonce}`;
}

function noteMarker(id: string): string {
  return `note:${id}`;
}

function voteMarker(id: string): string {
  return `vote:${id}`;
}

function expectOk<T>(result: unknown, detail: string): T {
  const outcome = result as { isOk?: () => boolean; 0?: T | string };
  if (typeof outcome.isOk === "function" && outcome.isOk()) return outcome[0] as T;
  throw new Error(`${detail}: ${String(outcome[0] ?? "unknown error")}`);
}

function expectSome<T>(optionValue: unknown, detail: string): T {
  const value = some<T>(optionValue);
  if (value != null) return value;
  throw new Error(detail);
}

function channels(client: RigClient): GuideRaceChannels {
  return client.handle as GuideRaceChannels;
}

function writeNote(notes: unknown, id: string, note: GuideRaceNote) {
  watershed.or_map_set(notes, id, JSON.stringify(note));
}

function readNote(raw: string): GuideRaceNote {
  try {
    const parsed = JSON.parse(raw) as Partial<GuideRaceNote>;
    if (
      typeof parsed.text === "string" &&
      typeof parsed.column === "string" &&
      typeof parsed.author === "string" &&
      typeof parsed.created === "number"
    ) {
      return {
        text: parsed.text,
        column: parsed.column,
        author: parsed.author,
        created: parsed.created,
      };
    }
  } catch {
    // Visible fallback beats crashing the demo.
  }
  return {
    text: "(unreadable note)",
    column: "",
    author: "—",
    created: 0,
  };
}

function authorLabel(author: string): string {
  switch (author) {
    case "user-a":
      return "Client A";
    case "user-b":
      return "Client B";
    case "survey":
      return "Standing note";
    default:
      return author;
  }
}

function voteText(votes: number): string {
  return votes > 0 ? `+${votes}` : String(votes);
}

function cards(client: RigClient): GuideRaceCard[] {
  const votes = new Map<string, number>();
  for (const [id, value] of watershed.or_map_entries(channels(client).votes).toArray()) {
    if (value instanceof orMapKernel.Tally) votes.set(id, value[0]);
  }

  const boardCards: GuideRaceCard[] = [];
  for (const [id, value] of watershed.or_map_entries(channels(client).notes).toArray()) {
    if (!(value instanceof orMapKernel.Register)) continue;
    const note = readNote(value[0]);
    if (note.column !== WENT_WELL) continue;
    boardCards.push({
      id,
      note,
      votes: votes.get(id) ?? 0,
    });
  }

  boardCards.sort(
    (a, b) => a.note.created - b.note.created || a.id.localeCompare(b.id),
  );
  return boardCards;
}

function canonicalBoard(client: RigClient): string {
  return JSON.stringify(
    cards(client).map((card) => ({
      id: card.id,
      text: card.note.text,
      column: card.note.column,
      author: card.note.author,
      created: card.note.created,
      votes: card.votes,
    })),
  );
}

function seedChannels(doc: unknown): GuideRaceChannels {
  const root = watershed.root(doc);
  const notes = expectOk(
    watershed.create_or_map(doc, new orMapKernel.RegisterMode()),
    "guide race notes bootstrap failed",
  );
  const votes = expectOk(
    watershed.create_or_map(doc, new orMapKernel.TallyMode()),
    "guide race votes bootstrap failed",
  );
  watershed.set(root, CHANNEL_KEYS.notes, watershed.or_map_handle_of(notes));
  watershed.set(root, CHANNEL_KEYS.votes, watershed.or_map_handle_of(votes));
  writeNote(notes, STARTER_NOTE.id, STARTER_NOTE.note);
  return { notes, votes };
}

function resolveChannels(doc: unknown): GuideRaceChannels {
  const root = watershed.root(doc);
  const notesHandle = expectSome<unknown>(
    watershed.get(root, CHANNEL_KEYS.notes),
    "guide race notes handle missing",
  );
  const votesHandle = expectSome<unknown>(
    watershed.get(root, CHANNEL_KEYS.votes),
    "guide race votes handle missing",
  );
  return {
    notes: expectOk(
      watershed.resolve_or_map(doc, notesHandle),
      "guide race notes resolve failed",
    ),
    votes: expectOk(
      watershed.resolve_or_map(doc, votesHandle),
      "guide race votes resolve failed",
    ),
  };
}

function renderCard(client: RigClient, card: GuideRaceCard): HTMLLIElement {
  const notePending = client.pending.includes(noteMarker(card.id));
  const votePending = client.pending.includes(voteMarker(card.id));

  const item = document.createElement("li");
  item.className = "gr-note";
  item.classList.toggle("is-note-pending", notePending);
  item.classList.toggle("is-sequenced", !notePending);

  const text = document.createElement("p");
  text.className = "gr-note-text";
  text.textContent = card.note.text;

  const meta = document.createElement("div");
  meta.className = "gr-note-meta";

  const author = document.createElement("span");
  author.className = "annot";
  author.textContent = authorLabel(card.note.author);

  const voteWrap = document.createElement("span");
  voteWrap.className = "gr-vote-wrap";

  const voteLabel = document.createElement("span");
  voteLabel.className = "annot";
  voteLabel.textContent = "votes";

  const vote = document.createElement("output");
  vote.className = "gr-vote";
  vote.textContent = voteText(card.votes);
  vote.setAttribute("aria-label", `Vote total ${card.votes}`);
  vote.classList.toggle("k-pending", votePending);
  vote.classList.toggle("k-seq", !votePending && card.votes !== 0);

  voteWrap.append(voteLabel, vote);
  meta.append(author, voteWrap);
  item.append(text, meta);
  return item;
}

function renderBoard(client: RigClient) {
  const boardEl = client.el.querySelector("[data-board]");
  if (!(boardEl instanceof HTMLElement)) return;

  const boardCards = cards(client);
  const list = document.createElement("ol");
  list.className = "gr-notes";
  list.setAttribute("aria-label", `${CLIENT_LABEL[client.id]} retro board notes`);

  for (const card of boardCards) list.append(renderCard(client, card));
  boardEl.replaceChildren(list);

  const count = client.el.querySelector("[data-note-count]");
  if (count instanceof HTMLElement) {
    count.textContent = `${boardCards.length} note${boardCards.length === 1 ? "" : "s"}`;
  }

  const badge = client.el.querySelector("[data-pending-count]");
  if (badge instanceof HTMLElement) {
    badge.textContent = `${client.pending.length} pending`;
    badge.classList.toggle("is-pending", client.pending.length > 0);
  }
}

export function initGuideRaceDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;
  let locked = false;
  const addBtn = document.querySelector("[data-guide-race-add]");
  const voteBtn = document.querySelector("[data-guide-race-votes]");

  function syncButtons() {
    if (addBtn instanceof HTMLButtonElement) addBtn.disabled = locked;
    if (voteBtn instanceof HTMLButtonElement) voteBtn.disabled = locked;
  }

  function addNote(clientId: string, spec: (typeof ADD_RACE)[number]) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const id = noteId(spec.author, spec.created, spec.nonce);
    rig.submit(
      client,
      noteMarker(id),
      () =>
        writeNote(channels(client).notes, id, {
          text: spec.text,
          column: WENT_WELL,
          author: spec.author,
          created: spec.created,
        }),
      `note ${spec.text}`,
    );
  }

  function castVote(clientId: string, delta: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    rig.submit(
      client,
      voteMarker(STARTER_NOTE.id),
      () => watershed.or_map_increment(channels(client).votes, STARTER_NOTE.id, delta),
      `vote ${delta > 0 ? "+1" : "-1"} ${STARTER_NOTE.note.text}`,
    );
  }

  rig = createSluiceRig({
    rig: "[data-guide-race-rig]",
    status: "[data-guide-race-status]",
    section: "#guide-race-demo",
    control: "guide-race",
    document: "guide-race-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      clients["a"].handle = seedChannels(clients["a"].doc);
      // Seed the real channels on A, then settle so B can resolve the same
      // OR-map handles from the attached root map before the first render.
      sluice.settle(server);
      clients["b"].handle = resolveChannels(clients["b"].doc);
    },
    render: renderBoard,
    canonical: canonicalBoard,
  });
  if (!rig) return;

  syncButtons();

  addBtn?.addEventListener("click", () => {
    if (locked) return;
    locked = true;
    syncButtons();
    for (const spec of ADD_RACE) addNote(spec.clientId, spec);
  });

  voteBtn?.addEventListener("click", () => {
    if (locked) return;
    locked = true;
    syncButtons();
    castVote("a", 1);
    castVote("b", 1);
    castVote("b", -1);
  });

  document
    .querySelector("[data-guide-race-reset]")
    ?.addEventListener("click", () => {
      if (!rig) return;
      locked = false;
      rig.reset();
      syncButtons();
    });
}
