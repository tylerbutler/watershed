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

const mapFactory = new SchemaFactory("org.watershed.shared-tree.m2");

export class MapPoint extends mapFactory.object("Point", {
  x: mapFactory.number,
  y: mapFactory.number,
}) {}

export class DynamicMap extends mapFactory.mapRecursive("DynamicMap", [
  mapFactory.string,
  mapFactory.number,
  mapFactory.boolean,
  mapFactory.null,
  MapPoint,
  () => DynamicMap,
]) {}

export class MapRoot extends mapFactory.object("Root", {
  items: DynamicMap,
}) {}

export const mapTreeConfig = new TreeViewConfiguration({ schema: MapRoot });

export function initialMapRoot() {
  return new MapRoot({ items: new DynamicMap([]) });
}

export const mapRootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m2.root",
  config: mapTreeConfig,
  initializer: initialMapRoot,
});
