export function documentFromUrl(generated) {
  const url = new URL(globalThis.location.href);
  const document = url.searchParams.get("document");

  if (document) {
    return document;
  }

  url.searchParams.set("document", generated);
  globalThis.history.replaceState(globalThis.history.state, "", url);
  return generated;
}
