import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import retro_tutorial_lustre/board
import watershed_site/guide_race/runtime as race

pub type Options {
  Options(notes_only: Bool, include_noscript: Bool)
}

pub fn static() -> Element(Nil) {
  view(race.static_model(), Options(True, True))
  |> element.map(fn(_) { Nil })
}

pub fn view(model: race.Model, options: Options) -> Element(race.Msg) {
  let unavailable = model.phase == race.Static || model.phase == race.Starting
  h.section(
    [
      a.id("guide-race-demo"),
      a.class("gr"),
      a.attribute("data-guide-race", ""),
      test_id("race-demo"),
      a.attribute("data-phase", phase(model.phase)),
      a.attribute("aria-labelledby", "guide-race-title"),
    ],
    [
      h.div([a.class("gr-head")], [
        h.h2([a.id("guide-race-title")], [
          h.text(case options.notes_only {
            True -> "Run the same add on a controlled clock"
            False -> "Run both edits on a controlled clock"
          }),
        ]),
        h.p([], [
          h.text("Two "),
          h.code([], [h.text("watershed")]),
          h.text(" documents connect to the in-memory "),
          h.code([], [h.text("sluice")]),
          h.text(
            ". Click the add button to send one note from each board at the same time.",
          ),
        ]),
        h.p([a.class("gr-hint")], [
          h.text(
            "Magenta marks an edit that is waiting for the server. Once the server accepts it, the note turns black on both boards. Both notes remain.",
          ),
        ]),
      ]),
      h.div([a.class("gr-rig"), test_id("race-rig")], [
        replica(model, race.Alpha, model.alpha),
        replica(model, race.Beta, model.beta),
        h.div([a.class("gr-channel"), a.style("grid-area", "seq")], [
          h.div([a.class("gr-seq-node"), a.attribute("data-flow-node", "seq")], [
            h.span([a.class("annot")], [h.text("Sequencer")]),
            h.output(
              [
                a.class("gr-seq-counter"),
                test_id("sequence"),
                a.attribute("aria-label", "Latest sequence number"),
              ],
              [h.text("SN " <> int.to_string(model.latest_sequence))],
            ),
          ]),
          h.ol(
            [
              a.class("gr-op-log"),
              test_id("operation-log"),
              a.attribute("aria-live", "polite"),
              a.attribute("aria-label", "Sequenced operations, newest first"),
            ],
            list.map(model.log, fn(entry) {
              h.li([], [
                h.span([a.class("op-meta")], [
                  h.text("SN " <> int.to_string(entry.sequence_number)),
                ]),
                h.span([a.class("op-path")], [
                  h.text(entry.author <> " → " <> entry.target),
                ]),
                h.span([a.class("op-kind")], [h.text(entry.event)]),
              ])
            }),
          ),
        ]),
        keyed.div(
          [
            a.class("flow-layer"),
            test_id("flow-layer"),
            a.attribute("aria-hidden", "true"),
          ],
          list.map(model.flows, fn(marker) {
            #(
              int.to_string(marker.id),
              h.span(
                [
                  a.class(case marker.from {
                    "seq" -> "flow-dot sequenced"
                    _ -> "flow-dot"
                  }),
                  a.attribute("data-flow-id", int.to_string(marker.id)),
                  test_id("flow-" <> int.to_string(marker.id)),
                  a.attribute("data-from", marker.from),
                  a.attribute("data-to", marker.to),
                ],
                [h.span([a.class("flow-dot-label")], [h.text(marker.label)])],
              ),
            )
          }),
        ),
      ]),
      h.div([a.class("gr-controls")], [
        h.label([a.class("gr-latency")], [
          h.span([a.class("annot")], [h.text("Link latency")]),
          h.input([
            a.type_("range"),
            a.min("100"),
            a.max("2000"),
            a.step("100"),
            a.value(int.to_string(model.latency_ms)),
            test_id("latency"),
            a.disabled(unavailable),
            a.attribute("aria-label", "Link latency"),
            event.on_input(fn(value) {
              race.SetLatency(
                int.parse(value) |> result.unwrap(model.latency_ms),
              )
            }),
          ]),
          h.output([test_id("latency-output")], [
            h.text(int.to_string(model.latency_ms) <> " ms"),
          ]),
        ]),
        h.button(
          [
            a.type_("button"),
            a.class("race-btn"),
            test_id("race-add"),
            a.disabled(
              unavailable || model.race_locked || model.phase == race.Failed,
            ),
            event.on_click(race.RunAddRace),
          ],
          [h.text("Add two notes at once")],
        ),
        h.button(
          [
            a.type_("button"),
            a.class("race-btn"),
            test_id("race-votes"),
            a.disabled(
              unavailable || model.race_locked || model.phase == race.Failed,
            ),
            a.hidden(options.notes_only),
            event.on_click(race.RunVoteRace),
          ],
          [h.text("Cast three votes")],
        ),
        h.button(
          [
            a.type_("button"),
            a.class("reset-btn"),
            test_id("race-reset"),
            a.attribute("aria-label", "Reset the retro board race demo"),
            a.disabled(unavailable),
            event.on_click(race.Reset),
          ],
          [h.text("Reset")],
        ),
        h.p(
          [
            a.class("status"),
            test_id("race-status"),
            a.attribute("role", "status"),
          ],
          status(model),
        ),
        h.p(
          [
            test_id("race-error"),
            a.attribute("aria-live", "polite"),
            a.class("demo-noscript"),
          ],
          case model.error {
            None -> []
            Some(reason) -> [h.text(reason)]
          },
        ),
      ]),
      h.p([a.class("gr-controls-hint")], [
        h.text(case options.notes_only {
          True -> "Reset restores the starting board."
          False ->
            "Each button runs one clean race. Reset restores the starting board."
        }),
      ]),
      case options.include_noscript {
        False -> element.none()
        True ->
          element.element("noscript", [], [
            h.p([a.class("demo-noscript"), test_id("noscript")], [
              h.text("The live race needs JavaScript: it runs two real "),
              h.code([], [h.text("watershed")]),
              h.text(" documents against the in-memory "),
              h.code([], [h.text("sluice")]),
              h.text(
                " as compiled JavaScript in your browser. The rest of the page works fine without it.",
              ),
            ]),
          ])
      },
      case model.phase {
        race.Static ->
          h.p([a.class("demo-noscript gr-fallback"), test_id("race-fallback")], [
            h.text("The live race couldn't start: it runs two real "),
            h.code([], [h.text("watershed")]),
            h.text(" documents against the in-memory "),
            h.code([], [h.text("sluice")]),
            h.text(
              " as compiled JavaScript, and this browser didn't load it. The rest of the page works fine without it.",
            ),
          ])
        _ -> element.none()
      },
    ],
  )
}

fn replica(
  model: race.Model,
  replica: race.Replica,
  snapshot: board.Snapshot,
) -> Element(race.Msg) {
  let id = case replica {
    race.Alpha -> "alpha"
    race.Beta -> "beta"
  }
  let label = race.replica_label(replica)
  let cards = board.cards_for(snapshot, board.WentWell)
  let pending = model.pending |> list.filter(fn(marker) { marker.author == id })
  let count =
    pending |> list.map(fn(marker) { marker.key }) |> list.unique |> list.length
  h.article(
    [
      a.class("gr-client"),
      test_id(id),
      a.attribute("data-flow-node", id),
      a.attribute("aria-label", label <> " retro board replica"),
      a.style("grid-area", case replica {
        race.Alpha -> "a"
        race.Beta -> "b"
      }),
    ],
    [
      h.header([a.class("gr-client-head")], [
        h.h3([], [h.text(label)]),
        h.span(
          [
            a.class(case count {
              0 -> "pending-count annot"
              _ -> "pending-count annot is-pending"
            }),
            test_id(id <> "-pending"),
          ],
          [h.text(int.to_string(count) <> " pending")],
        ),
      ]),
      h.div([a.class("gr-board")], [
        h.header([a.class("gr-lane-head")], [
          h.div([], [
            h.h4([], [h.text("Went well")]),
            h.p([a.class("annot")], [
              h.text("add-wins notes · signed vote tally"),
            ]),
          ]),
          h.span([a.class("annot"), test_id(id <> "-count")], [
            h.text(
              int.to_string(list.length(cards))
              <> case list.length(cards) {
                1 -> " note"
                _ -> " notes"
              },
            ),
          ]),
        ]),
        h.ol(
          [
            a.class("gr-notes"),
            test_id(id <> "-notes"),
            a.attribute("aria-label", label <> " retro board notes"),
          ],
          list.map(cards, fn(card) { card_view(card, pending, id) }),
        ),
      ]),
    ],
  )
}

fn card_view(
  card: board.NoteCard,
  pending: List(race.PendingMarker),
  replica: String,
) -> Element(race.Msg) {
  let note_pending =
    list.any(pending, fn(marker) { marker.key == "note:" <> card.id })
  let vote_pending =
    list.any(pending, fn(marker) { marker.key == "vote:" <> card.id })
  h.li(
    [
      a.class(
        "gr-note "
        <> case note_pending {
          True -> "is-note-pending"
          False -> "is-sequenced"
        },
      ),
      test_id(replica <> "-" <> card.id),
      a.attribute("data-pending", case note_pending {
        True -> "true"
        False -> "false"
      }),
    ],
    [
      h.p([a.class("gr-note-text")], [h.text(card.note.text)]),
      h.div([a.class("gr-note-meta")], [
        h.span([a.class("annot")], [
          h.text(case card.note.author {
            "survey" -> "Standing note"
            "user-a" -> "Client A"
            "user-b" -> "Client B"
            other -> other
          }),
        ]),
        h.span([a.class("gr-vote-wrap")], [
          h.span([a.class("annot")], [h.text("votes")]),
          h.output(
            [
              a.class(
                "gr-vote"
                <> case vote_pending, card.votes {
                  True, _ -> " k-pending"
                  False, 0 -> ""
                  False, _ -> " k-seq"
                },
              ),
              a.attribute(
                "aria-label",
                "Vote total " <> int.to_string(card.votes),
              ),
            ],
            [
              h.text(
                case card.votes > 0 {
                  True -> "+"
                  False -> ""
                }
                <> int.to_string(card.votes),
              ),
            ],
          ),
        ]),
      ]),
    ],
  )
}

fn status(model: race.Model) -> List(Element(race.Msg)) {
  let #(class, stamp, detail) = case model.phase, model.converged {
    race.Starting, _ -> #("revising", "Starting", "connecting both replicas")
    race.Failed, _ -> #("revising", "Stopped", "the race could not finish")
    _, True -> #(
      "converged",
      "Converged",
      "all replicas identical · nothing pending",
    )
    _, False -> #(
      "revising",
      "Revising",
      "operations in flight · replicas may differ",
    )
  }
  [h.span([a.class("stamp " <> class)], [h.text(stamp)]), h.text(" " <> detail)]
}

fn phase(phase: race.Phase) -> String {
  case phase {
    race.Static -> "static"
    race.Starting -> "starting"
    race.Ready -> "ready"
    race.Delivering -> "delivering"
    race.Failed -> "failed"
  }
}

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}
