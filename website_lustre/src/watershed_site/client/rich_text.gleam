import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/effect.{type Effect}
import lustre/element
import watershed/rich_text
import watershed_site/rich_text/runtime
import watershed_site/rich_text/view

pub type Editor

pub type Model {
  Model(
    runtime: runtime.Model,
    editors: List(#(runtime.Replica, Editor)),
    mounting: List(runtime.Replica),
  )
}

pub type Msg {
  Runtime(runtime.Msg)
  Mounted(runtime.Replica, Editor)
  MountFailed(runtime.Replica, String)
  EditorDelta(runtime.Replica, String)
  EditorSelection(runtime.Replica, Int, Int)
  Unmounted(runtime.Replica)
}

@external(javascript, "./rich_text_ffi.mjs", "mount")
fn mount(
  element_id: String,
  initial_document: String,
  on_user_delta: fn(String) -> Nil,
  on_selection: fn(Int, Int) -> Nil,
  on_mounted: fn(Editor) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "applyRemote")
fn apply_remote(editor: Editor, delta: String) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "setEnabled")
fn set_enabled(editor: Editor, enabled: Bool) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "loadDocument")
fn load_document(editor: Editor, document: String) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "renderSelections")
fn render_selections(editor: Editor, selections: String) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "raceType")
fn race_type(editor_a: Editor, editor_b: Editor) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "raceFormat")
fn race_format(editor_a: Editor, editor_c: Editor) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "raceDelete")
fn race_delete(editor_a: Editor, editor_b: Editor) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "insertEmbed")
fn insert_embed(editor: Editor) -> Nil

@external(javascript, "./rich_text_ffi.mjs", "destroy")
fn destroy(editor: Editor) -> Nil

pub fn main() {
  let app =
    lustre.application(
      init: fn(_) {
        let #(model, effects) = runtime.init()
        #(Model(model, [], []), effect.map(effects, Runtime))
      },
      update: update,
      view: fn(model) {
        view.view(model.runtime, False)
        |> element.map(Runtime)
      },
    )
  let assert Ok(_) = lustre.start(app, "#rich-text-mount", Nil)
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  let #(model, effects) = case message {
    Runtime(message) -> {
      let #(runtime, effects) = runtime.update(model.runtime, message)
      #(
        Model(..model, runtime:),
        effect.batch([
          effect.map(effects, Runtime),
          scenario_effect(model, message),
        ]),
      )
    }
    Mounted(replica, editor) -> {
      let runtime =
        runtime.transition(model.runtime, runtime.DocumentLoaded(replica))
      let cleanup = case model.editors |> list.key_find(replica) {
        Error(_) -> effect.none()
        Ok(previous) -> {
          use _dispatch <- effect.from
          destroy(previous)
        }
      }
      #(
        Model(
          runtime:,
          editors: [
            #(replica, editor),
            ..list.filter(model.editors, fn(item) { item.0 != replica })
          ],
          mounting: list.filter(model.mounting, fn(item) { item != replica }),
        ),
        cleanup,
      )
    }
    MountFailed(replica, reason) -> {
      let #(runtime, effects) =
        runtime.update(model.runtime, runtime.AdapterFailed(replica, reason))
      #(
        Model(
          ..model,
          runtime:,
          mounting: list.filter(model.mounting, fn(item) { item != replica }),
        ),
        effect.map(effects, Runtime),
      )
    }
    EditorDelta(replica, raw) ->
      case rich_text.parse_delta(raw) {
        Error(_) ->
          update(
            model,
            MountFailed(replica, "The rich-text editor sent an invalid delta."),
          )
        Ok(delta) -> {
          let #(runtime, effects) =
            runtime.update(
              model.runtime,
              runtime.Defer(runtime.EditorChanged(replica, delta)),
            )
          #(Model(..model, runtime:), effect.map(effects, Runtime))
        }
      }
    EditorSelection(replica, index, length) -> {
      let message = case index < 0 || length < 0 {
        True -> runtime.SelectionCleared(replica)
        False -> runtime.SelectionChanged(replica, index, length)
      }
      let #(runtime, effects) = runtime.update(model.runtime, message)
      #(Model(..model, runtime:), effect.map(effects, Runtime))
    }
    Unmounted(replica) -> #(
      Model(
        ..model,
        editors: list.filter(model.editors, fn(item) { item.0 != replica }),
      ),
      effect.none(),
    )
  }
  let #(model, adapters) = sync_adapters(model)
  #(model, effect.batch([effects, adapters]))
}

fn sync_adapters(model: Model) -> #(Model, Effect(Msg)) {
  let reloads =
    model.editors
    |> list.filter(fn(item) {
      runtime.document_reload(model.runtime, item.0) != None
    })
  let reload_effects =
    list.map(reloads, fn(item) {
      use dispatch <- effect.from
      let assert Some(document) = runtime.document_reload(model.runtime, item.0)
      load_document(item.1, document)
      dispatch(Runtime(runtime.DocumentLoaded(item.0)))
    })
  let reloading = list.map(reloads, fn(item) { item.0 })

  let changes_to_apply =
    model.editors
    |> list.filter(fn(item) { !list.contains(reloading, item.0) })
    |> list.filter_map(fn(item) {
      case runtime.adapter_changes(model.runtime, item.0) {
        [] -> Error(Nil)
        changes -> Ok(#(item.1, changes))
      }
    })
  let change_effects = case changes_to_apply {
    [] -> []
    changes -> [
      {
        use dispatch <- effect.from
        list.each(changes, fn(item) {
          list.each(item.1, fn(delta) { apply_remote(item.0, delta) })
        })
        dispatch(Runtime(runtime.AdaptersApplied))
      },
    ]
  }

  let enable_effects =
    list.map(model.editors, fn(item) {
      use _dispatch <- effect.from
      set_enabled(
        item.1,
        model.runtime.phase == runtime.Ready
          || model.runtime.phase == runtime.Delivering,
      )
    })
  let selection_effects =
    list.map(model.editors, fn(item) {
      use _dispatch <- effect.from
      render_selections(item.1, runtime.selections_json(model.runtime, item.0))
    })

  let missing =
    runtime.replicas()
    |> list.filter(fn(replica) {
      !list.any(model.editors, fn(item) { item.0 == replica })
      && !list.contains(model.mounting, replica)
      && !list.contains(reloading, replica)
      && model.runtime.phase != runtime.Static
      && model.runtime.phase != runtime.Starting
      && model.runtime.phase != runtime.Failed
    })
  let mount_effects =
    list.map(missing, fn(replica) {
      use dispatch, _root <- effect.after_paint
      mount(
        "rich-text-editor-" <> runtime.replica_id(replica),
        runtime.document_json(model.runtime, replica),
        fn(raw) { dispatch(EditorDelta(replica, raw)) },
        fn(index, length) { dispatch(EditorSelection(replica, index, length)) },
        fn(editor) { dispatch(Mounted(replica, editor)) },
        fn(reason) { dispatch(MountFailed(replica, reason)) },
      )
    })

  #(
    Model(..model, mounting: list.append(model.mounting, missing)),
    effect.batch(
      list.flatten([
        reload_effects,
        change_effects,
        enable_effects,
        selection_effects,
        mount_effects,
      ]),
    ),
  )
}

fn scenario_effect(model: Model, message: runtime.Msg) -> Effect(Msg) {
  case message {
    runtime.RaceType ->
      with_two_editors(model, runtime.ClientA, runtime.ClientB, race_type)
    runtime.RaceFormat ->
      with_two_editors(model, runtime.ClientA, runtime.ClientC, race_format)
    runtime.RaceDelete ->
      with_two_editors(model, runtime.ClientA, runtime.ClientB, race_delete)
    runtime.ScenarioEmbed ->
      case editor(model, runtime.ClientC) {
        Error(Nil) -> effect.none()
        Ok(editor) -> {
          use _dispatch <- effect.from
          insert_embed(editor)
        }
      }
    _ -> effect.none()
  }
}

fn with_two_editors(
  model: Model,
  first: runtime.Replica,
  second: runtime.Replica,
  action: fn(Editor, Editor) -> Nil,
) -> Effect(Msg) {
  case editor(model, first), editor(model, second) {
    Ok(first), Ok(second) -> {
      use _dispatch <- effect.from
      action(first, second)
    }
    _, _ -> effect.none()
  }
}

fn editor(model: Model, replica: runtime.Replica) -> Result(Editor, Nil) {
  model.editors |> list.key_find(replica)
}
