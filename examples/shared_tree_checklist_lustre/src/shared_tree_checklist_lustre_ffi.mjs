export function queryParameter(name, fallback) {
  return new URL(globalThis.location.href).searchParams.get(name) ?? fallback;
}

export function currentOrigin() {
  return new URL(globalThis.location.href).origin;
}

export function proxyFloodgateHttp(upstream) {
  const upstreamOrigin = new URL(upstream).origin;
  const localOrigin = currentOrigin();
  const originalFetch = globalThis.fetch.bind(globalThis);
  globalThis.fetch = (input, init) => {
    const source = input instanceof Request ? input.url : String(input);
    const url = new URL(source, localOrigin);
    if (url.origin !== upstreamOrigin) {
      return originalFetch(input, init);
    }
    const local = new URL(localOrigin);
    url.protocol = local.protocol;
    url.host = local.host;
    const rewritten =
      input instanceof Request ? new Request(url, input) : url;
    return originalFetch(rewritten, init);
  };
}

export function replaceDocument(documentId) {
  const url = new URL(globalThis.location.href);
  url.searchParams.set("document", documentId);
  globalThis.history.replaceState(null, "", url);
}
