import {
  SchemaFactory,
  TreeViewConfiguration,
  defineTreeDataStore,
} from "fluid-framework/alpha";

const factory = new SchemaFactory("org.watershed.shared-tree.m1");

export class Point extends factory.object("Point", {
  x: factory.number,
  y: factory.number,
}) {}

export class Root extends factory.object("Root", {
  title: factory.string,
  enabled: factory.boolean,
  rating: factory.number,
  marker: factory.null,
  note: factory.optional(factory.string),
  point: Point,
}) {}

export const treeConfig = new TreeViewConfiguration({ schema: Root });

export function initialRoot() {
  return new Root({
    title: "",
    enabled: false,
    rating: 0,
    marker: null,
    point: new Point({ x: 0, y: 0 }),
  });
}

export const rootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m1.root",
  config: treeConfig,
  initializer: initialRoot,
});
