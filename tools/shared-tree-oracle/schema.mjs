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

const arrayFactory = new SchemaFactory("org.watershed.shared-tree.m3");

export class ArrayPoint extends arrayFactory.object("Point", {
  label: arrayFactory.string,
  x: arrayFactory.number,
}) {}

export class Items extends arrayFactory.arrayRecursive("Items", [
  arrayFactory.string,
  arrayFactory.number,
  arrayFactory.boolean,
  arrayFactory.null,
  ArrayPoint,
  () => Items,
  () => ArrayMap,
]) {}

export class ArrayMap extends arrayFactory.mapRecursive("ArrayMap", [
  arrayFactory.string,
  arrayFactory.number,
  arrayFactory.boolean,
  arrayFactory.null,
  ArrayPoint,
  () => Items,
  () => ArrayMap,
]) {}

export class Points extends arrayFactory.array("Points", ArrayPoint) {}

export class ArrayRoot extends arrayFactory.object("Root", {
  left: Items,
  right: Items,
  byKey: ArrayMap,
  narrow: Points,
}) {}

export const arrayTreeConfig = new TreeViewConfiguration({ schema: ArrayRoot });
export const rootArrayTreeConfig = new TreeViewConfiguration({ schema: Items });
export const arrayMapTreeConfig = new TreeViewConfiguration({ schema: ArrayMap });

export function initialArrayRoot() {
  return new ArrayRoot({
    left: new Items([]),
    right: new Items([]),
    byKey: new ArrayMap([]),
    narrow: new Points([]),
  });
}

export const arrayRootStore = defineTreeDataStore({
  type: "org.watershed.shared-tree.m3.root",
  config: arrayTreeConfig,
  initializer: initialArrayRoot,
});
