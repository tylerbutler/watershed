# work_queue_lustre — a consensus job-dispatch board

Three columns that look like a kanban board and are not one. **Queued → In
progress → Done** are literally the states of two consensus kernels plus an
append log, not card lists with a convention layered on top:

- **`OrderedCollection` is not a card store.** It is a consensus FIFO work
  queue — `add` / `acquire` / `complete` / `release`, one acquirer per job,
  and explicitly *non-optimistic*: nothing changes until an op sequences. The
  Queued column is the FIFO; In progress is the held-jobs table.
- **`TaskManager` is not a to-do list.** It is a consensus lock queue: a FIFO
  of clients volunteering for a named role, where the head owns it. This demo
  has exactly one role — the **dispatcher**, the tab that generates jobs.
- **Done is a `SharedSequence`** because the consensus kernels deliberately
  drop completed jobs; history needs somewhere boring to live.

A reader arriving at a three-column board will assume a card store on a
distributed to-do list. It is the opposite: a distributed job queue whose UI
happens to render as a board — the semantics are Sidekiq, not Trello.

## The two things worth watching

**1. A claim is a race the server referees.** *Claim next* submits
`ordered_acquire` and renders **claiming…** until the op sequences. The
outcome arrives through consensus (`AcquireOutcome`, surfaced by
`watershed_lustre.ordered_acquire`): the winner gets `AcquiredItem`, the loser
gets `QueueEmpty` — its op emits *no event at all*, so the outcome is the
loser's only signal, rendered as a brief **taken!**. There is no optimistic
transition to roll back, because there was never a local guess to fake.

**2. A dying client cannot take its work with it.** Close a tab mid-job: the
server sequences a `"leave"`, every surviving replica re-releases the job to
the queue tail (`Added(newly_added: False)`), and it is claimable again — no
code in this app participates. Close the *dispatcher* tab: the next queued
volunteer inherits the role the same way and starts generating. This is the
only watershed example whose interesting event is a client dying.

One caveat worth knowing: the Done append is a second channel, so a worker
dying in the instant between its `complete` sequencing and its Done append
loses that job from history (the queue is still correct). Two channels, no
atomicity — the same trade the retro-board notes document.

## Run it

```sh
just integration-up            # floodgate dev server on :4000
pnpm install && pnpm run build
pnpm run serve                 # http://localhost:8080
```

Open three tabs on the same URL (the document id rides the query string).
**Volunteer one tab as dispatcher** and another as backup, claim jobs from the
third — then close the tab marked "dispatcher", or a tab mid-job, and watch
the survivors recover on their own. How fast the recovery lands depends on how
quickly the server notices the dead socket; a hard kill takes a beat longer
than a clean close.

## Tests

```sh
gleam test        # in-process: claim race, worker death, role handoff, release
pnpm run smoke    # live server: the same claims end to end through floodgate
```

The in-process tests drive two real `watershed_js` clients over the in-memory
`sluice_js`, whose `disconnect` sequences the same `"leave"` the server would.
The smoke test is the one that proves floodgate itself emits that leave for a
vanished socket — the single behaviour the in-process suite cannot vouch for.
