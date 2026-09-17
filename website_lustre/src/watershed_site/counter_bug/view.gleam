import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import watershed_lustre
import watershed_site/counter_bug/runtime

pub type Kind {
  Bug
  MapFix
  CounterFix
}

pub type RigState {
  Idle
  Showing(runtime.Frame, List(runtime.Frame))
  Done(runtime.Frame)
  Failed
}

pub type Model {
  Model(
    bug: RigState,
    map_fix: RigState,
    counter_fix: RigState,
    running: Option(Kind),
    generation: Int,
    bug_pace: Int,
    map_fix_pace: Int,
    counter_fix_pace: Int,
    error: Option(String),
  )
}

pub type Msg {
  Play(Kind)
  Finish(Int, Kind)
  Reset(Kind)
  SetPace(Kind, String)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(static_model(), effect.none())
}

pub fn static_model() -> Model {
  Model(Idle, Idle, Idle, None, 0, 2, 2, 2, None)
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Finish(generation, _) if generation != model.generation -> #(
      model,
      effect.none(),
    )
    Play(_) if model.running != None -> #(model, effect.none())
    Play(kind) -> start(model, kind)
    Finish(_, kind) -> advance(model, kind)
    Reset(kind) -> #(
      set_state(
        Model(
          ..model,
          generation: model.generation + 1,
          running: None,
          error: None,
        ),
        kind,
        Idle,
      ),
      effect.none(),
    )
    SetPace(kind, value) -> #(
      set_pace(model, kind, pace(value, pace_for(model, kind))),
      effect.none(),
    )
  }
}

fn start(model: Model, kind: Kind) -> #(Model, Effect(Msg)) {
  case runtime.trace(demo(kind)) {
    Ok([frame, ..rest]) -> #(
      set_state(
        Model(..model, running: Some(kind), error: None),
        kind,
        Showing(frame, rest),
      ),
      next(model, kind),
    )
    Ok([]) | Error(_) -> #(
      set_state(
        Model(
          ..model,
          running: None,
          error: Some("The kernel trace could not start."),
        ),
        kind,
        Failed,
      ),
      effect.none(),
    )
  }
}

fn advance(model: Model, kind: Kind) -> #(Model, Effect(Msg)) {
  case state(model, kind) {
    Showing(_, [frame]) -> #(
      set_state(Model(..model, running: None), kind, Done(frame)),
      effect.none(),
    )
    Showing(_, [frame, ..rest]) -> #(
      set_state(model, kind, Showing(frame, rest)),
      next(model, kind),
    )
    _ -> #(model, effect.none())
  }
}

fn next(model: Model, kind: Kind) -> Effect(Msg) {
  watershed_lustre.after(
    2400 / pace_for(model, kind),
    Finish(model.generation, kind),
  )
}

fn demo(kind: Kind) -> runtime.Demo {
  case kind {
    Bug -> runtime.BugDemo
    MapFix -> runtime.MapFixDemo
    CounterFix -> runtime.CounterFixDemo
  }
}

pub fn static() -> Element(Nil) {
  view(static_model(), True) |> element.map(fn(_) { Nil })
}

pub fn view(model: Model, include_noscript: Bool) -> Element(Msg) {
  h.section(
    [
      a.id("counter-bug"),
      a.class("cb"),
      a.attribute("aria-label", "The counter-in-a-map bug, demonstrated"),
      test_id("counter-bug"),
    ],
    [
      h.div([a.class("cb-inner")], [
        h.div([a.class("cb-head")], [
          h.p([a.class("cb-lede")], [
            h.text("Two gauge houses at one lock keep the day's "),
            h.code([], [h.text("boats-locked")]),
            h.text(
              " tally in one shared map cell. Run the race and watch a boat vanish, then run the fix.",
            ),
          ]),
        ]),
        rig(model, Bug),
        fix_copy("Fix one · make the writes commute", [
          h.text(
            "Nothing is wrong with the map: a counter just is not a single mutable cell. Give each replica its own key and sum them, and the two writes never contend. The ",
          ),
          h.em([], [h.text("same")]),
          h.text(" race now converges on the right total, through the "),
          h.em([], [h.text("same")]),
          h.text(
            " map_kernel. This layout (one positive-only column per replica) is the shape of a G-counter. A true G-counter also merges those columns by pairwise maximum, so duplicate delivery is idempotent.",
          ),
        ]),
        rig(model, MapFix),
        fix_copy("Fix two · ship the delta", [
          h.text("Watershed's "),
          h.a([a.href("/structures/counters")], [
            h.text("SharedCounter"),
          ]),
          h.text(
            " goes further: the op is the delta. A client never reads the tally to write it back. It sends increment(+1), or increment(−1) for a correction, and signed deltas sum the same in any order. This rig runs the compiled counter_kernel, the SharedCounter engine itself, not a map at all.",
          ),
        ]),
        rig(model, CounterFix),
        case include_noscript {
          True ->
            h.p(
              [
                a.class("cb-noscript counter-bug-fallback"),
                test_id("counter-bug-fallback"),
              ],
              [
                h.text(
                  "This demonstration needs JavaScript to run the live kernel. The takeaway: storing a counter in a last-write-wins map loses concurrent increments; use a commutative counter instead.",
                ),
              ],
            )
          False -> element.none()
        },
        case include_noscript {
          True ->
            element.element("noscript", [], [
              h.p([a.class("cb-noscript"), test_id("noscript")], [
                h.text(
                  "This demonstration runs a live Gleam kernel and needs JavaScript. The takeaway: storing a counter in a last-write-wins map loses concurrent increments; use a commutative ",
                ),
                h.a([a.href("/structures/counters")], [
                  h.text("SharedCounter"),
                ]),
                h.text("."),
              ]),
            ])
          False -> element.none()
        },
        h.p(
          [
            a.class("cb-noscript"),
            a.attribute("aria-live", "polite"),
            test_id("error"),
          ],
          case model.error {
            Some(reason) -> [h.text(reason)]
            None -> []
          },
        ),
      ]),
    ],
  )
}

fn rig(model: Model, kind: Kind) -> Element(Msg) {
  let state = state(model, kind)
  let #(a_value, b_value) = values(state)
  let running = model.running != None
  h.figure(
    [
      a.class(case kind {
        Bug -> "cb-rig"
        _ -> "cb-rig cb-rig-fix"
      }),
      a.attribute("data-state", state_name(state)),
      test_id("rig-" <> kind_id(kind)),
    ],
    [
      h.figcaption([a.class("cb-rig-label annot")], [
        h.span(
          [
            a.class(case kind {
              Bug -> "cb-badge cb-badge-bug"
              _ -> "cb-badge cb-badge-fix"
            }),
          ],
          [h.text(badge(kind))],
        ),
        h.code([], [h.text(kernel_label(kind))]),
      ]),
      h.div([a.class("cb-stage")], [
        house("Upstream house", "Client A", a_value, state, kind, "a"),
        h.div([a.class("cb-seq-col"), a.attribute("aria-hidden", "true")], [
          h.span([a.class("annot")], [h.text("sequencer")]),
          h.div([a.class("cb-seq")], chips(state, kind)),
        ]),
        house("Downstream house", "Client B", b_value, state, kind, "b"),
      ]),
      h.p(
        [
          a.class("cb-caption"),
          a.attribute("aria-live", "polite"),
          test_id("caption-" <> kind_id(kind)),
        ],
        [h.text(caption(state, kind))],
      ),
      verdict(state, kind),
      h.div([a.class("cb-foot")], [
        h.ol(
          [a.class("cb-log annot"), a.attribute("aria-label", "Operation log")],
          log(state, kind),
        ),
        h.div([a.class("cb-controls")], [
          h.label([a.class("cb-pace")], [
            h.span([a.class("annot")], [h.text("Speed")]),
            h.input([
              a.type_("range"),
              a.min("0.25"),
              a.max("1.5"),
              a.step("0.25"),
              a.value(pace_value(pace_for(model, kind))),
              a.title(
                "Playback speed: how fast the race plays on screen. Lower is slower; the outcome is identical at any speed.",
              ),
              event.on_input(fn(value) { SetPace(kind, value) }),
              test_id("pace-" <> kind_id(kind)),
            ]),
            h.output([], [
              h.text(pace_value(pace_for(model, kind)) <> "×"),
            ]),
          ]),
          h.button(
            [
              a.type_("button"),
              a.class("cb-btn cb-btn-primary"),
              a.disabled(running),
              event.on_click(Play(kind)),
              test_id("play-" <> kind_id(kind)),
            ],
            [h.text(play_label(kind))],
          ),
          h.button(
            [
              a.type_("button"),
              a.class("cb-btn"),
              a.disabled(running),
              event.on_click(Reset(kind)),
              test_id("reset-" <> kind_id(kind)),
            ],
            [h.text("Reset")],
          ),
        ]),
      ]),
    ],
  )
}

fn house(
  title: String,
  client: String,
  value: Int,
  state: RigState,
  kind: Kind,
  id: String,
) -> Element(msg) {
  h.div([a.class("cb-house")], [
    h.header([], [
      h.h3([], [h.text(title)]),
      h.span([a.class("annot")], [h.text(client)]),
    ]),
    h.div([a.class("cb-tally")], [
      h.span([a.class("annot")], [
        h.text(case kind {
          MapFix -> "boats-locked · sum"
          _ -> "boats-locked"
        }),
      ]),
      h.span(
        [
          a.class(case state {
            Showing(frame, _) ->
              case pending(frame, id) {
                True -> "cb-value pending"
                False -> "cb-value"
              }
            _ -> "cb-value"
          }),
          test_id("value-" <> kind_id(kind) <> "-" <> id),
        ],
        [h.text(int.to_string(value))],
      ),
      case kind {
        MapFix ->
          h.span([a.class("cb-subcol")], [
            h.span([a.class("annot")], [
              h.text("boats-locked/" <> id),
            ]),
            h.span(
              [
                a.class("cb-subcol-num"),
                test_id("subcol-" <> id),
              ],
              [
                h.text(int.to_string(subcolumn(state, id))),
              ],
            ),
          ])
        _ -> element.none()
      },
    ]),
  ])
}

fn verdict(state: RigState, kind: Kind) -> Element(msg) {
  case state {
    Done(frame) -> {
      let assert Some(outcome) = frame.outcome
      h.div(
        [
          a.class(
            "cb-verdict"
            <> case kind {
              Bug -> ""
              _ -> " cb-verdict-fix"
            },
          ),
        ],
        [
          case kind {
            Bug -> figure("boats actually locked", outcome.expected, "")
            _ -> element.none()
          },
          figure("tally recorded", outcome.recorded, case kind {
            Bug -> " cb-fig-loss"
            _ -> " cb-fig-win"
          }),
          h.p([a.class("cb-verdict-note")], [
            h.text(verdict_note(kind)),
          ]),
        ],
      )
    }
    _ -> element.none()
  }
}

fn figure(label: String, value: Int, class: String) -> Element(msg) {
  h.div([a.class("cb-figure")], [
    h.span([a.class("annot")], [h.text(label)]),
    h.span([a.class("cb-fig-num" <> class)], [h.text(int.to_string(value))]),
  ])
}

fn fix_copy(label: String, children: List(Element(msg))) -> Element(msg) {
  h.div([a.class("cb-fix-copy")], [
    h.p([a.class("annot")], [h.text(label)]),
    h.p([], children),
  ])
}

fn state(model: Model, kind: Kind) -> RigState {
  case kind {
    Bug -> model.bug
    MapFix -> model.map_fix
    CounterFix -> model.counter_fix
  }
}

fn set_state(model: Model, kind: Kind, value: RigState) -> Model {
  case kind {
    Bug -> Model(..model, bug: value)
    MapFix -> Model(..model, map_fix: value)
    CounterFix -> Model(..model, counter_fix: value)
  }
}

fn values(state: RigState) -> #(Int, Int) {
  case state {
    Idle -> #(41, 41)
    Showing(frame, _) | Done(frame) -> #(frame.a, frame.b)
    Failed -> #(41, 41)
  }
}

fn chips(state: RigState, _kind: Kind) -> List(Element(msg)) {
  case state {
    Idle -> []
    Showing(frame, _) | Done(frame) ->
      frame.chips
      |> list.map(fn(label) {
        h.span([a.class("cb-seq-chip")], [h.text(label)])
      })
    Failed -> []
  }
}

fn log(state: RigState, _kind: Kind) -> List(Element(msg)) {
  case state {
    Idle -> []
    Showing(frame, _) | Done(frame) ->
      list.map(frame.log, fn(line) {
        h.li([a.attribute("data-tone", line.tone)], [h.text(line.text)])
      })
    Failed -> []
  }
}

fn subcolumn(state: RigState, id: String) -> Int {
  let value = case state {
    Idle | Failed -> None
    Showing(frame, _) | Done(frame) ->
      case id {
        "a" -> frame.sub_a
        _ -> frame.sub_b
      }
  }
  option.unwrap(value, case id {
    "a" -> 20
    _ -> 21
  })
}

fn pending(frame: runtime.Frame, id: String) -> Bool {
  list.any(frame.log, fn(line) { line.tone == "pending" })
  && case id {
    "a" -> frame.a != 41
    _ -> frame.b != 41
  }
}

fn caption(state: RigState, kind: Kind) -> String {
  case state {
    Idle -> idle_caption(kind)
    Showing(frame, _) | Done(frame) -> frame.caption
    Failed -> "The kernel demonstration failed."
  }
}

fn pace(value: String, fallback: Int) -> Int {
  case value {
    "0.25" -> 1
    "0.5" -> 2
    "0.75" -> 3
    "1" -> 4
    "1.25" -> 5
    "1.5" -> 6
    _ -> fallback
  }
}

fn pace_for(model: Model, kind: Kind) -> Int {
  case kind {
    Bug -> model.bug_pace
    MapFix -> model.map_fix_pace
    CounterFix -> model.counter_fix_pace
  }
}

fn set_pace(model: Model, kind: Kind, value: Int) -> Model {
  case kind {
    Bug -> Model(..model, bug_pace: value)
    MapFix -> Model(..model, map_fix_pace: value)
    CounterFix -> Model(..model, counter_fix_pace: value)
  }
}

fn pace_value(quarters: Int) -> String {
  case quarters {
    1 -> "0.25"
    2 -> "0.5"
    3 -> "0.75"
    4 -> "1"
    5 -> "1.25"
    _ -> "1.5"
  }
}

fn kind_id(kind: Kind) -> String {
  case kind {
    Bug -> "bug"
    MapFix -> "fix"
    CounterFix -> "counter"
  }
}

fn state_name(state: RigState) -> String {
  case state {
    Idle -> "idle"
    Showing(_, _) -> "running"
    Done(_) -> "done"
    Failed -> "failed"
  }
}

fn badge(kind: Kind) -> String {
  case kind {
    Bug -> "SharedMap · one shared key"
    MapFix -> "Per-replica keys · sum"
    CounterFix -> "SharedCounter · signed delta ops"
  }
}

fn kernel_label(kind: Kind) -> String {
  case kind {
    Bug -> "map_kernel · boats-locked"
    MapFix -> "map_kernel · boats-locked/a + boats-locked/b"
    CounterFix -> "counter_kernel · boats-locked"
  }
}

fn play_label(kind: Kind) -> String {
  case kind {
    Bug -> "Demonstrate the bug"
    MapFix -> "Play the fix"
    CounterFix -> "Play the SharedCounter fix"
  }
}

fn idle_caption(kind: Kind) -> String {
  case kind {
    Bug ->
      "Press “Demonstrate the bug” to race two concurrent tallies through the compiled map_kernel."
    MapFix ->
      "Press “Play the fix” to run the identical race with per-replica tallies."
    CounterFix ->
      "Press “Play the SharedCounter fix” to run the same race, plus a −1 correction, through the compiled counter_kernel."
  }
}

fn verdict_note(kind: Kind) -> String {
  case kind {
    Bug -> "One boat lost. LWW overwrote a read-modify-write; it never added."
    MapFix -> "Both boats counted. No shared cell, no lost update."
    CounterFix ->
      "Every delta counted: two +1s and a −1 correction, in any order."
  }
}

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}
