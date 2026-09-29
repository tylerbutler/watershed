export function queryParameter(name, fallback) {
  return new URL(globalThis.location.href).searchParams.get(name) ?? fallback;
}

export function replaceDocument(documentId) {
  const url = new URL(globalThis.location.href);
  url.searchParams.set("document", documentId);
  globalThis.history.replaceState(null, "", url);
}
