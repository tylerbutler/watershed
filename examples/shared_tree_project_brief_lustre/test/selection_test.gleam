import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/selection as s
import watershed/presence

fn meta(selected) {
  s.Metadata("Alex", s.Blue, 1, selected)
}

pub fn codecs_and_field_keys_test() {
  let fields = [
    s.Title, s.OwnerName, s.OwnerEmail, s.ScheduleStart, s.ScheduleTarget,
    s.ReviewReviewer, s.ReviewApproved,
  ]
  let selected = list.map(fields, fn(field) { Some(s.Fixed(field)) })
  let selected =
    list.append(selected, [
      Some(s.Milestone("second", s.MilestoneTitle)),
      Some(s.Milestone("second", s.Completed)),
      None,
    ])
  list.each(selected, fn(selected) {
    list.each([s.Blue, s.Green, s.Amber, s.Violet], fn(color) {
      let value = s.Metadata("Alex", color, 1, selected)
      let assert Ok(decoded) =
        json.parse(json.to_string(s.encode(value)), s.decoder())
      let assert True = decoded == value
    })
  })
  let assert "owner.name" = s.field_key(s.Fixed(s.OwnerName))
  let assert "milestone/second/completed" =
    s.field_key(s.Milestone("second", s.Completed))
  let long = s.Metadata(string.repeat("x", 100), s.Blue, 1, None)
  let assert Ok(clamped) =
    json.parse(json.to_string(s.encode(long)), s.decoder())
  let assert 80 = string.length(clamped.name)
  let emoji = s.Metadata(string.repeat("😀", 100), s.Blue, 1, None)
  let assert Ok(clamped) =
    json.parse(json.to_string(s.encode(emoji)), s.decoder())
  let assert True = clamped.name == string.repeat("😀", 80)
}

pub fn malformed_metadata_test() {
  list.each(
    [
      "null", "[]", "{}",
      "{\"name\":1,\"color\":\"blue\",\"token\":1,\"selected\":null}",
      "{\"name\":\"A\",\"color\":\"red\",\"token\":1,\"selected\":null}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":-1,\"selected\":null}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":1.5,\"selected\":null}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":9007199254740992,\"selected\":null}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":1,\"selected\":{\"kind\":\"fixed\",\"field\":\"review.bad\"}}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":1,\"selected\":{\"kind\":\"milestone\",\"id\":\"\",\"field\":\"title\"}}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":1,\"selected\":{\"kind\":\"milestone\",\"id\":\"a/b\",\"field\":\"title\"}}",
      "{\"name\":\"A\",\"color\":\"blue\",\"token\":1,\"selected\":{\"kind\":\"milestone\",\"id\":\"a\",\"field\":\"id\"}}",
    ],
    fn(value) {
      let assert Error(_) = json.parse(value, s.decoder())
    },
  )
}

pub fn focus_and_local_invalidation_test() {
  let value = meta(Some(s.Fixed(s.OwnerName)))
  let assert 1 = s.focus(value, value.selected).token
  let cleared = s.focus(value, None)
  let assert 2 = cleared.token
  let assert 3 = s.focus(cleared, value.selected).token
  let review = meta(Some(s.Fixed(s.ReviewApproved)))
  let cleared = s.reconcile_local(review, brief.initial("first", "second"))
  let assert None = cleared.selected
  let assert 2 = cleared.token
}

pub fn driver_events_preserve_sessions_and_invalidate_review_tokens_test() {
  let absent = brief.initial("first", "second")
  let present =
    brief.ProjectBrief(..absent, review: Some(brief.Review("", False)))
  let metadata = meta(Some(s.Fixed(s.ReviewReviewer)))
  let entries = [
    presence.PresenceEntry("a", "same-user", metadata),
    presence.PresenceEntry("b", "same-user", metadata),
    presence.PresenceEntry("local", "same-user", metadata),
  ]
  let state = s.on_event(s.new(), presence.State(entries), present, "local")
  let assert 2 = list.length(s.peers(state))
  let state =
    s.on_event(
      state,
      presence.Changed(presence.no_change(), entries),
      absent,
      "local",
    )
  let assert [a, b] = s.peers(state)
  let assert None = a.meta.selected
  let assert None = b.meta.selected
  let state = s.reconcile(state, [], present)
  let state = s.on_event(state, presence.State(entries), present, "local")
  let assert [a, b] = s.peers(state)
  let assert None = a.meta.selected
  let assert None = b.meta.selected
  let fresh = s.Metadata(..metadata, token: 2)
  let stale = s.Metadata(..metadata, token: 0)
  let state =
    s.reconcile(
      state,
      [
        presence.PresenceEntry("a", "same-user", fresh),
        presence.PresenceEntry("b", "same-user", stale),
      ],
      present,
    )
  let assert [a, b] = s.peers(state)
  let assert Some(s.Fixed(s.ReviewReviewer)) = a.meta.selected
  let assert None = b.meta.selected
  let unchanged =
    s.on_event(
      state,
      presence.Failed(presence.UnsupportedPresence),
      absent,
      "local",
    )
  let assert True = s.peers(unchanged) == s.peers(state)
}

pub fn milestone_identity_and_driver_deadlines_test() {
  let before = brief.initial("first", "second")
  let after =
    brief.ProjectBrief(
      ..before,
      schedule: brief.Schedule(..before.schedule, milestones: [
        brief.Milestone("second", "", False),
      ]),
    )
  let field = s.Milestone("second", s.Completed)
  let metadata = meta(Some(field))
  let entries = [presence.PresenceEntry("a", "Alex", metadata)]
  let state = s.reconcile(s.new(), entries, before)
  let state = s.reconcile(state, entries, after)
  let assert [peer] = s.peers(state)
  let assert Some(selected) = peer.meta.selected
  let assert True = selected == field
  let assert True = s.available(field, after)
  let removed =
    brief.ProjectBrief(
      ..after,
      schedule: brief.Schedule(..after.schedule, milestones: []),
    )
  let state = s.reconcile(state, entries, removed)
  let state = s.reconcile(state, entries, before)
  let assert [peer] = s.peers(state)
  let assert None = peer.meta.selected
  let #(sessions, _) =
    presence.observe_session(presence.sessions(), "a", "Alex", metadata, 1000)
  let #(sessions, _) =
    presence.observe_session(sessions, "a", "Alex", metadata, 3000)
  let #(live, _) = presence.expire_sessions(sessions, 6500, 9500)
  let assert [_] = presence.session_entries(live)
  let #(expired, diff) = presence.expire_sessions(live, 6500, 9501)
  let state =
    s.on_event(
      state,
      presence.Changed(diff, presence.session_entries(expired)),
      before,
      "local",
    )
  let assert [] = s.peers(state)
  let config = s.config()
  let assert presence.Ripple = presence.config_mode(config)
  let assert Ok(_) =
    json.parse(
      json.to_string(s.encode(metadata)),
      presence.config_decoder(config),
    )
}
