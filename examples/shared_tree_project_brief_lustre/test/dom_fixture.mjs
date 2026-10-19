import * as app from "../build/dev/javascript/shared_tree_project_brief_lustre/shared_tree_project_brief_lustre.mjs";
import * as fixture from "../build/dev/javascript/shared_tree_project_brief_lustre/fixture.mjs";
import * as helpers from "../build/dev/javascript/shared_tree_project_brief_lustre/app_fixture.mjs";
import * as lustre from "../build/dev/javascript/lustre/lustre.mjs";
import * as effect from "../build/dev/javascript/lustre/lustre/effect.mjs";

const { document: treeDocument } = fixture.new$(helpers.with_review());
let model = helpers.opened(treeDocument);
const application = lustre.application(
  () => [model, effect.none()],
  (previous, message) => {
    const result = app.update(previous, message);
    model = result[0];
    return result;
  },
  app.view,
);
const runtime = lustre.start(application, "#app", undefined)[0];
const send = message => lustre.send(runtime, lustre.dispatch(message));
window.fixture = {
  replace() {
    helpers.replace_review(model);
    send(helpers.capture(model));
  },
  capture() { send(helpers.capture(model)); },
  get reviewer() { return model.rendered[0].value.review[0].reviewer; },
  get errors() { return [...model.errors]; },
};
