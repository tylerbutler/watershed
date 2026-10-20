import type { IFluidContainer, TreeView } from "fluid-framework";
import type { Config, Session } from "./domain.ts";
import type { BoardNode } from "./schema.ts";

export async function start(_config: Config): Promise<Session> {
  throw new Error("Not implemented");
}

export function nativeView(_session: Session): TreeView<typeof BoardNode> {
  throw new Error("Not implemented");
}

export function nativeContainer(_session: Session): IFluidContainer {
  throw new Error("Not implemented");
}
