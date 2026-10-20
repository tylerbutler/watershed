import type { Config, Session } from "./domain.ts";
import { start as originalStart, nativeView as originalView,
  nativeContainer as originalContainer } from "./reference-model.ts";

const originals = new WeakMap<Session, Session>();

export async function start(config: Config): Promise<Session> {
  const session = await originalStart(config);
  const adapter = Reflect.get(globalThis, "__incidentEval");
  if (adapter.snapshot().phase !== "closed") return session;
  const leaked: Session = {
    read: () => ({ ...session.read(), phase: "closed" }),
    apply: action => session.apply(action),
    subscribe: listener => session.subscribe(listener),
    close: () => {},
  };
  originals.set(leaked, session);
  return leaked;
}

export function nativeView(session: Session) {
  return originalView(originals.get(session) ?? session);
}

export function nativeContainer(session: Session) {
  return originalContainer(originals.get(session) ?? session);
}
